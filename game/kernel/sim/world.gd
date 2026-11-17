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

var _acc := 0.0
var _next_uid := 1
var _next_object_uid := 1
var _events: Array = []


func _init(p: Pack, seed: int) -> void:
	pack = p
	rng = SimRng.new(seed)
	if not p.is_valid():
		phase = "invalid"  # silent on purpose: the reasons stay readable in pack.errors
		return
	money = int(p.cfg("start_money"))


func set_time(unix: int, offset: int) -> void:
	now = unix
	utc_offset = offset


## Local hour of day as 0..24.
func local_hour() -> float:
	return float(posmod(now + utc_offset, 86400)) / 3600.0


func advance(seconds: float) -> void:
	if phase == "invalid" or phase == "over":
		return
	_acc += seconds
	while _acc >= STEP and phase != "over":
		_acc -= STEP
		_step()


## Runs a player command. Always returns {ok, error}; handlers live in `Commands.handlers`.
func command(cmd: Dictionary) -> Dictionary:
	if phase == "invalid" or phase == "over":
		return Commands.fail("not_running")
	var handler: Callable = Commands.handlers.get(str(cmd.get("type", "")), Callable())
	if handler.is_null():
		return Commands.fail("unknown_command")
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
	p.uid = _next_uid
	_next_uid += 1
	people.append(p)


## Adds an object with the next uid and returns it. No placement checks yet.
func add_object(type: String, room: String, x: int, y: int) -> int:
	var uid := _next_object_uid
	_next_object_uid += 1
	objects.append({"uid": uid, "type": type, "room": room, "x": x, "y": y})
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
	AutonomySystem.step(self, dt)
	EconomySystem.step(self, dt)
