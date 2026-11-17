class_name World
extends RefCounted
## Top-level sim state. Time is fed in from outside (`set_time`); `advance` turns elapsed
## real seconds into fixed 60-second steps, each of which runs every system in order.

const STEP := 60

var pack: Pack
var rng: SimRng
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

var _acc := 0.0
var _next_uid := 1
var _events: Array = []


func _init(p: Pack, seed: int) -> void:
	pack = p
	rng = SimRng.new(seed)
	if not p.is_valid():
		phase = "invalid"  # silent on purpose: the reasons stay readable in pack.errors
		return
	money = int(p.cfg("start_money"))
	for id in p.rooms:
		if bool(p.rooms[id].get("built", false)):
			rooms_built.append(str(id))
	phase = "adopting"
	FamilySystem.new_candidate(self)


func set_time(unix: int, offset: int) -> void:
	now = unix
	utc_offset = offset


## Local hour of day as 0..24.
func local_hour() -> float:
	return float(posmod(now + utc_offset, 86400)) / 3600.0


func advance(seconds: float) -> void:
	if phase != "living":
		return
	_acc += seconds
	while _acc >= STEP and phase != "over":
		_acc -= STEP
		_step()


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
	p.alive = false
	p.current = {}
	emit("person_died", {"uid": p.uid, "cause": cause})
	if phase == "living" and not people.any(func(q: Person): return q.alive):
		phase = "over"
		emit("game_over")


func _step() -> void:
	now += STEP
	_run_systems(float(STEP))


## Every per-step system, in the fixed order they must run. Later tasks add theirs here.
func _run_systems(dt: float) -> void:
	NeedsSystem.step(self, dt)
	IllnessSystem.step(self, dt)
	MessSystem.step(self, dt)
	AutonomySystem.step(self, dt)
	EconomySystem.step(self, dt)
	CollectibleSystem.step(self, dt)
	FamilySystem.step(self, dt)
	GoalSystem.step(self, dt)
