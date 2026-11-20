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
## The festival on as of the last step ("" for none; see `FestivalSystem`).
var festival := ""
## The local day (days since the epoch) the house was last paid for being made clean; -1
## for never (see `MessSystem.clean`).
var clean_paid_day := -1
## Cooked food waiting to be eaten (see `DishSystem`).
var dishes: Array[Dictionary] = []
## The household's animals, the dead and lost among them kept as a record (see `PetSystem`).
var pets: Array[Pet] = []
## An animal waiting at the gate to be taken in: {kind, given, age, expires_at}; {} for none.
var pet_offer: Dictionary = {}
## Stock name -> the share of a unit a well-kept pet has saved so far (see `PetSystem`).
var pet_saved: Dictionary = {}
## `now` until which the children miss a pet that ran away or died (0: not).
var pet_grief_until := 0
## Ids of rooms that exist in the house (pack rooms with `built`, plus any built later).
var rooms_built: Array[String] = []
## Counters that goals read: cured, collected, mess_cleaned, all_clean.
var stats: Dictionary = {"cured": 0, "collected": 0, "mess_cleaned": 0, "all_clean": 0}

## Loose pick-ups outdoors: {uid, type, x, y, expires_at}.
var collectibles: Array[Dictionary] = []
## Collectible type -> how many of it have ever been picked up.
var collection: Dictionary = {}
## Collectible type -> how many of it are kept in the box now (only with `collect_keep`, and
## a "scene" story's keepsake; see `CollectibleSystem`).
var box: Dictionary = {}
## Ids of goals already rewarded.
var goals_done: Array[String] = []
## True once two living people are married.
var married := false
## The person on offer while adopting, in `Person.to_dict()` shape; {} otherwise.
var candidate: Dictionary = {}
## Everyone on offer while adopting, side by side (`candidate` first); the command `adopt`
## takes one by `pick`. Not saved: after a load only `candidate` is on offer until a reroll.
var candidates: Array[Dictionary] = []
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
## Letters to the player, oldest first (see `LetterSystem`), the id the next one gets, and
## `now` of the last minor letter (0: none yet).
var letters: Array[Dictionary] = []
var letter_next := 1
var letter_minor_at := 0
## The market (see `MarketSystem`, `ServiceSystem`; all stay empty / 0 without one): the
## used-goods stall, service id -> times bought, lottery tickets {id, service, draw_at,
## amount (-1 until drawn)} and the id the next one gets, until when (`now`) a hired hand
## comes and which service hired them, and the service a candidate on offer while living
## came from.
var secondhand: Dictionary = {}
var services_bought: Dictionary = {}
var tickets: Array[Dictionary] = []
var ticket_next := 1
var helper_until := 0
var helper_service := ""
var adopt_service := ""
## A faster clock (see `ServiceSystem` "speed"): the real unix time until which game time
## runs `speed_factor` times as fast, and how many seconds the sim clock has run ahead of
## the real one because of it (0 for a world that never sped up: the clocks then agree).
var speed_until := 0
var speed_factor := 1.0
var clock_lead := 0

## The living babies as of `_babies_t` (see `babies`); not saved.
var _babies: Array[Person] = []
## `AutonomySystem._world_key`'s cache: [hour key, rooms_built, its size, weather, wet,
## season position, season list, key]; not saved.
var _flags_ctx: Array = []
## `AutonomySystem._objects_by_type`'s cache: [objects, size, last uid, uids by type]; not saved.
var _by_type_ctx: Array = []
## `GoalSystem._owned`'s cache: [objects, size, last uid, object types, count]; not saved.
var _owned_ctx: Array = []
## `GoalSystem.step`'s cache: [goals_done, its size, goals table, open goals]; not saved.
var _goals_open: Array = []
var _babies_t := -1
## `PetSystem.home_key` and `PetSystem.room_now` as of [now, pets size]; not saved.
var _pet_cache: Array = [-1, -1, "", {}]
var _built := {}
var _built_n := -1
var _built_src: Array[String] = []
var _acc := 0.0
var _next_uid := 1
var _events: Array = []
## Events that may become letters, waiting for `LetterSystem.step`; not saved. Filled only
## when the pack has letters (`_letter_watch` is then `LetterSystem.WATCH`).
var _letter_news: Array = []
var _letter_watch: Dictionary = {}


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
	if LetterSystem.enabled(p):
		_letter_watch = LetterSystem.WATCH
	FamilySystem.new_candidate(self)


## The one entry point a view needs for time: call it with the real clock (unix seconds and
## the local UTC offset in seconds) whenever convenient, e.g. every frame or on resume.
## Returns a catch-up summary (see `Offline`); it is the zero summary unless the gap since the
## last sync was longer than `SYNC_OFFLINE_GAP` and the world is living.
## - A clock that did not move forward changes nothing (time never runs backwards).
## - While adopting (time frozen), or before the world was ever given a time (`now` 0),
##   `now` just jumps to `unix`.
## - Afterwards the sim clock (`now` plus the partial step not yet simulated) equals `unix`
##   plus `clock_lead`, also after an absence beyond the cap or one that ended the game.
## - While a faster clock was bought (`speed_until`), the part of the gap before it ends
##   counts `speed_factor` times; the surplus goes into `clock_lead`. Whether the gap is an
##   absence is judged on real time.
func sync(unix: int, offset: int) -> Dictionary:
	var job := begin_sync(unix, offset)
	if job == null:
		return Offline.zero_summary(self)
	job.run(-1)
	return job.finish()


## `sync` in two halves, for a view that must not stall on a long absence: does everything
## `sync` does, except that an absence comes back unfinished as a `CatchUpJob` (null when there
## was none). Run it (`run`) in slices, then `finish` it: the world ends up exactly as after
## `sync`. Until then nothing else may touch the world (no `sync`, `command` or save).
func begin_sync(unix: int, offset: int) -> CatchUpJob:
	utc_offset = offset
	var clock := float(now) + _acc - float(clock_lead)
	if float(unix) <= clock:
		return null
	if phase == "adopting" or now == 0:
		now = unix + clock_lead
		_acc = 0.0
		return null
	var gap := float(unix) - clock
	var away := gap > SYNC_OFFLINE_GAP  # judged on real time
	# While the clock runs fast, game time gains on real time.
	if speed_until > 0 and clock < float(speed_until):
		var extra := roundi((minf(float(unix), float(speed_until)) - clock) * (speed_factor - 1.0))
		clock_lead += extra
		gap += float(extra)
	if away:
		var job := CatchUpJob.new(self, gap)
		job.snap_unix = unix
		return job
	advance(gap)
	snap_clock(unix)
	return null


## After a sync: when the sim clock is not at `unix` plus `clock_lead` (the absence was capped,
## ended the game, or the world is not living), puts it there.
func snap_clock(unix: int) -> void:
	if float(now) + _acc != float(unix + clock_lead):
		now = unix + clock_lead
		_acc = 0.0


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
	if queue_time(seconds):
		run_steps(-1)


## Adds `seconds` to the time still to simulate without running it (`run_steps` does); false,
## with nothing added, unless the world is living and `seconds` is positive.
func queue_time(seconds: float) -> bool:
	if phase != "living" or seconds <= 0.0:
		return false
	_acc += seconds
	return true


## Runs up to `max_steps` (all when negative) of the steps queued by `queue_time`; true when
## none are left (or the game is over).
func run_steps(max_steps: int) -> bool:
	var n := 0
	while _acc >= step_s and phase != "over":
		if max_steps >= 0 and n >= max_steps:
			return false
		_acc -= step_s
		_step()
		n += 1
	return true


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
			# While living, only a candidate offered by a service can be taken in or swapped.
			if (type == "adopt" or type == "reroll") and candidate.is_empty():
				return Commands.fail("not_adopting")
	return handler.call(self, cmd)


func emit(type: String, data := {}) -> void:
	var e := {"type": type, "t": now}
	e.merge(data)
	_events.append(e)
	if _letter_watch.has(type):
		_letter_news.append(e)


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
	FestivalSystem.step(self, dt)
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
	PetSystem.step(self, dt)  # its hourly look for a stray draws after everything but letters
	LetterSystem.step(self, dt)  # turns this step's news into letters
	MarketSystem.step(self, dt)  # last two: draw only in packs with a market or services
	ServiceSystem.step(self, dt)


## Everything that decides what happens next, as plain JSON-safe data; see `WorldSave`.
func to_dict() -> Dictionary:
	return WorldSave.to_dict(self)


## Rebuilds a world from `to_dict` output (also after a JSON round trip); null, with no
## engine error, when the data does not fit this pack. See `WorldSave.from_dict`.
static func from_dict(p: Pack, saved: Dictionary) -> World:
	return WorldSave.from_dict(p, saved)
