class_name World
extends RefCounted
## Top-level sim state. Time is fed in from outside: a view calls `sync` with the real clock
## and nothing else; `advance` turns elapsed real seconds into fixed steps of `step_s`
## seconds (the pack's `step_seconds`), each of which runs every system in order.

## A `sync` gap longer than this many seconds is treated as an absence (`catch_up`).
const SYNC_OFFLINE_GAP := 120
## Bump when `to_dict` changes shape; `from_dict` refuses any other version.
const SAVE_VERSION := 1

var pack: Pack
var rng: SimRng
## Seconds per simulation step: the pack's `step_seconds` (a divisor of 60), 60 for an
## invalid pack. Systems scale everything by `dt`, so this changes resolution, not pace.
var step_s := 60
var now := 0
var utc_offset := 0
## "adopting" | "living" | "over" | "invalid"
var phase := "living"
var people: Array[Person] = []
var money := 0
## True while replaying time the player was away: needs are floored so neglect never kills.
var offline := false
## Placed objects: {uid, type, room, x, y}.
var objects: Array[Dictionary] = []
## Consumable stock name -> count.
var stock: Dictionary = {}
## Owned items without a `stock` field: item id -> count.
var inventory: Dictionary = {}
## Salary coins paid ahead of schedule per person uid (<= 0), so 24 hourly parts add up.
var income_carry: Dictionary = {}
## Messes in the house: {uid, type, room, x, y}.
var messes: Array[Dictionary] = []
## Seasons and weather (see `WeatherSystem`; all stay empty / -1 / 0 with seasons off):
## the season id as of the last step, the weather id, the weather slot it was rolled for,
## and `now` until which the ground is still wet.
var season := ""
var weather := ""
var weather_slot := -1
var wet_until := 0
## Cooked food waiting to be eaten (see `DishSystem`).
var dishes: Array[Dictionary] = []
## Ids of rooms that exist in the house (pack rooms with `built`, plus any built later).
var rooms_built: Array[String] = []
## Counters that goals read: cured, collected, mess_cleaned, all_clean.
var stats: Dictionary = {"cured": 0, "collected": 0, "mess_cleaned": 0, "all_clean": 0}

## Loose pick-ups outdoors: {uid, type, x, y, expires_at}.
var collectibles: Array[Dictionary] = []
## Collectible type -> how many of it have ever been picked up.
var collection: Dictionary = {}
## Ids of goals already rewarded.
var goals_done: Array[String] = []
## True once two living people are married.
var married := false
## The person on offer while adopting, in `Person.to_dict()` shape; {} otherwise.
var candidate: Dictionary = {}
## Pending marriage proposals: {id, person: Dictionary, savings, expires_at}.
var proposals: Array[Dictionary] = []
## `now` from which the next proposal may arrive.
var next_proposal_at := 0
## True after the first proposal was declined in this game (later declines wait longer).
var declined_once := false
## True once the first adoption happened: only that one sets the starting money.
var adopted_once := false
## Old stories of the house that have unlocked: story id -> {found: [fragment ids], stage}
## (see `StorySystem`).
var stories: Dictionary = {}
## The factor on the illness chance from finished stories' blessings (kept by `StorySystem`).
var blessing_illness := 1.0
## True while some couple could have a child but the beds have no place for one (see
## `BirthSystem`); kept so the hint is given once each time it starts.
var birth_blocked := false

## The living babies as of `_babies_t` (see `babies`); not saved.
var _babies: Array[Person] = []
## `AutonomySystem._world_key`'s cache: [now, utc_offset, rooms_built, its size, weather,
## wet_until, key]; not saved.
var _flags_ctx: Array = []
## `AutonomySystem._objects_by_type`'s cache: [objects, size, last uid, uids by type]; not saved.
var _by_type_ctx: Array = []
var _babies_t := -1
var _built := {}
var _built_n := -1
var _built_src: Array[String] = []
var _acc := 0.0
var _next_uid := 1
var _events: Array = []


func _init(p: Pack, seed: int) -> void:
	pack = p
	rng = SimRng.new(seed)
	if not p.is_valid():
		phase = "invalid"  # silent on purpose: the reasons stay readable in pack.errors
		return
	step_s = int(p.cfg("step_seconds"))
	money = int(p.cfg("start_money"))
	for id in p.rooms:
		if bool(p.rooms[id].get("built", false)):
			rooms_built.append(str(id))
	phase = "adopting"
	FamilySystem.new_candidate(self)


## The one entry point a view needs for time: call it with the real clock (unix seconds and
## the local UTC offset in seconds) whenever convenient, e.g. every frame or on resume.
## Returns a catch-up summary (see `Offline`); it is the zero summary unless the gap since the
## last sync was longer than `SYNC_OFFLINE_GAP` and the world is living.
## - A clock that did not move forward changes nothing (time never runs backwards).
## - While adopting (time frozen), or before the world was ever given a time (`now` 0),
##   `now` just jumps to `unix`.
## - Afterwards the sim clock (`now` plus the partial step not yet simulated) equals `unix`,
##   also after an absence beyond the cap or one that ended the game.
func sync(unix: int, offset: int) -> Dictionary:
	utc_offset = offset
	var clock := float(now) + _acc
	if float(unix) <= clock:
		return Offline.zero_summary(self)
	if phase == "adopting" or now == 0:
		now = unix
		_acc = 0.0
		return Offline.zero_summary(self)
	var gap := float(unix) - clock
	var summary: Dictionary
	if gap > SYNC_OFFLINE_GAP:
		summary = catch_up(gap)
	else:
		advance(gap)
		summary = Offline.zero_summary(self)
	if float(now) + _acc != float(unix):  # capped, game over, or not living: snap to real time
		now = unix
		_acc = 0.0
	return summary


## Test / setup only: sets the clock directly. Views use `sync`. Once people live in the
## world, `now` is never moved backwards (the offset still updates).
func set_time(unix: int, offset: int) -> void:
	utc_offset = offset
	if unix < now and phase == "living" and not people.is_empty():
		return
	now = unix


## `rooms_built` as a set (room id -> true), rebuilt only when rooms are added.
func built_set() -> Dictionary:
	if _built_n != rooms_built.size() or not is_same(_built_src, rooms_built):
		_built_src = rooms_built
		_built = {}
		for r in rooms_built:
			_built[r] = true
		_built_n = rooms_built.size()
	return _built


## The people in the baby stage, worked out once per step (the dead among them are left for
## callers to skip: someone may die later in the same step).
func babies() -> Array[Person]:
	if _babies_t != now:
		_babies_t = now
		_babies = []
		var until := pack.baby_until()
		for p in people:
			if p.alive and p.age < until:
				_babies.append(p)
	return _babies


## Local hour of day as 0..24.
func local_hour() -> float:
	return float(posmod(now + utc_offset, 86400)) / 3600.0


func advance(seconds: float) -> void:
	if phase != "living" or seconds <= 0.0:
		return
	_acc += seconds
	while _acc >= step_s and phase != "over":
		_acc -= step_s
		_step()


## Replays the time the player was away (capped) and returns the summary; see `Offline`.
func catch_up(elapsed_seconds: float) -> Dictionary:
	return Offline.catch_up(self, elapsed_seconds)


## Runs a player command. Always returns {ok, error}; handlers live in `Commands.handlers`.
func command(cmd: Dictionary) -> Dictionary:
	if phase == "invalid":
		return Commands.fail("not_running")
	var type := str(cmd.get("type", ""))
	var handler: Callable = Commands.handlers.get(type, Callable())
	if handler.is_null():
		return Commands.fail("unknown_command")
	match phase:
		"adopting":
			if type != "adopt" and type != "reroll":
				return Commands.fail("not_running")
		"over":
			if type != "reroll":
				return Commands.fail("not_running")
		_:
			if type == "adopt" or type == "reroll":
				return Commands.fail("not_adopting")
	return handler.call(self, cmd)


func emit(type: String, data := {}) -> void:
	var e := {"type": type, "t": now}
	e.merge(data)
	_events.append(e)


## Puts `events` back at the front of the queue, ahead of anything queued since.
func requeue_events(events: Array) -> void:
	_events = events + _events


func drain_events() -> Array:
	var out := _events
	_events = []
	return out


func person(uid: int) -> Person:
	for p in people:
		if p.uid == uid:
			return p
	return null


func add_person(p: Person) -> void:
	p.uid = next_uid()
	people.append(p)


## Adds an object with the next uid and returns it, free of charge; -1 (nothing added)
## when `HouseSystem.can_place` rejects the spot.
func add_object(type: String, room: String, x: int, y: int) -> int:
	if HouseSystem.can_place(self, type, room, x, y) != "":
		return -1
	var uid := next_uid()
	objects.append({"uid": uid, "type": type, "room": room, "x": x, "y": y})
	return uid


## One world-wide uid counter: people, objects, messes (and later collectibles) never collide.
func next_uid() -> int:
	var uid := _next_uid
	_next_uid += 1
	return uid


## The object with this uid, or {} when missing.
func object(uid: int) -> Dictionary:
	for o in objects:
		if o.uid == uid:
			return o
	return {}


## Marks a person dead, and ends the game when nobody is left.
func kill_person(p: Person, cause: String) -> void:
	if not p.alive:
		return
	AutonomySystem.cancel(self, p)
	p.alive = false
	emit("person_died", {"person": p.uid, "cause": cause})
	BirthSystem.on_death(self, p)
	if phase == "living" and not people.any(func(q: Person): return q.alive):
		phase = "over"
		emit("game_over")


func _step() -> void:
	now += step_s
	_run_systems(float(step_s))


## Every per-step system, in the fixed order they must run. Later tasks add theirs here.
func _run_systems(dt: float) -> void:
	WeatherSystem.step(self, dt)
	NeedsSystem.step(self, dt)
	IllnessSystem.step(self, dt)
	MessSystem.step(self, dt)
	DishSystem.step(self, dt)
	AutonomySystem.step(self, dt)
	EconomySystem.step(self, dt)
	CollectibleSystem.step(self, dt)
	FamilySystem.step(self, dt)
	BirthSystem.step(self, dt)
	GoalSystem.step(self, dt)
	MoodSystem.step(self, dt)
	WishSystem.step(self, dt)
	StorySystem.step(self, dt)


## Everything that decides what happens next, as plain JSON-safe data; see `WorldSave`.
func to_dict() -> Dictionary:
	return WorldSave.to_dict(self)


## Rebuilds a world from `to_dict` output (also after a JSON round trip); null, with no
## engine error, when the data does not fit this pack. See `WorldSave.from_dict`.
static func from_dict(p: Pack, saved: Dictionary) -> World:
	return WorldSave.from_dict(p, saved)
