class_name World
extends RefCounted
## Top-level sim state. Time is fed in from outside (`set_time`); `advance` turns elapsed
## real seconds into fixed 60-second steps, each of which runs every system in order.

const STEP := 60
## Bump when `to_dict` changes shape; `from_dict` refuses any other version.
const SAVE_VERSION := 1
const _PHASES := ["adopting", "living", "over", "invalid"]

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
	if phase != "living" or seconds <= 0.0:
		return
	_acc += seconds
	while _acc >= STEP and phase != "over":
		_acc -= STEP
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


## Everything that decides what happens next, as plain data (deep copy; JSON-safe).
## Not saved: `offline` (transient) and undrained events. Ints used as dictionary keys
## (`income_carry`) are written as strings, because JSON keys always are. Godot's JSON
## parser can be one ulp off for a float, so every float is written as {"$f": "<bits>"},
## the decimal text of its 64 IEEE bits, which survives any JSON round trip exactly.
func to_dict() -> Dictionary:
	return _encode(_snapshot())


func _snapshot() -> Dictionary:
	var carry := {}
	for uid in income_carry:
		carry[str(uid)] = income_carry[uid]
	var ppl: Array = []
	for p in people:
		ppl.append(p.to_dict())
	return {
		"version": SAVE_VERSION, "pack_id": pack.id, "seed": rng.get_state()["seed"],
		"rng": rng.get_state(), "phase": phase, "now": now, "utc_offset": utc_offset,
		"acc": _acc, "next_uid": _next_uid, "money": money, "people": ppl,
		"objects": objects.duplicate(true), "stock": stock.duplicate(true),
		"inventory": inventory.duplicate(true), "income_carry": carry,
		"messes": messes.duplicate(true), "rooms_built": rooms_built.duplicate(),
		"stats": stats.duplicate(true), "collectibles": collectibles.duplicate(true),
		"collection": collection.duplicate(true), "goals_done": goals_done.duplicate(),
		"married": married, "candidate": candidate.duplicate(true),
		"proposals": proposals.duplicate(true), "next_proposal_at": next_proposal_at,
		"declined_once": declined_once, "adopted_once": adopted_once,
	}


## Rebuilds a world from `to_dict` output, also after a JSON round trip (numbers come back
## as floats and are restored to the exact types the live world uses). Returns null, with
## no engine error, for a wrong version or pack, a missing key or a value of the wrong shape.
static func from_dict(pack: Pack, saved: Dictionary) -> World:
	var bad := []
	var d: Dictionary = _decode(saved, bad)
	if pack == null or not bad.is_empty() or not _valid_save(pack, d):
		return null
	var w := World.new(pack, int(d["seed"]))
	w.rng.set_state(d["rng"])
	w.phase = d["phase"]
	w.now = int(d["now"])
	w.utc_offset = int(d["utc_offset"])
	w._acc = float(d["acc"])
	w._next_uid = int(d["next_uid"])
	w.money = int(d["money"])
	w.people.clear()
	for pd in d["people"]:
		w.people.append(Person.from_dict(pd))
	w.objects.clear()
	for o in d["objects"]:
		w.objects.append(_ints(o, ["uid", "x", "y"]))
	w.stock = _int_values(d["stock"])
	w.inventory = _int_values(d["inventory"])
	w.income_carry = {}
	for k in d["income_carry"]:
		w.income_carry[int(k)] = int(d["income_carry"][k])
	w.messes.clear()
	for m in d["messes"]:
		w.messes.append(_ints(m, ["uid", "x", "y"]))
	w.rooms_built.clear()
	for r in d["rooms_built"]:
		w.rooms_built.append(str(r))
	w.stats = _int_values(d["stats"])
	w.collectibles.clear()
	for c in d["collectibles"]:
		w.collectibles.append(_ints(c, ["uid", "x", "y", "expires_at"]))
	w.collection = _int_values(d["collection"])
	w.goals_done.clear()
	for g in d["goals_done"]:
		w.goals_done.append(str(g))
	w.married = d["married"]
	w.candidate = {} if d["candidate"].is_empty() else Person.from_dict(d["candidate"]).to_dict()
	w.proposals.clear()
	for pr in d["proposals"]:
		w.proposals.append({"id": int(pr["id"]), "person": Person.from_dict(pr["person"]).to_dict(),
			"savings": int(pr["savings"]), "expires_at": int(pr["expires_at"])})
	w.next_proposal_at = int(d["next_proposal_at"])
	w.declined_once = d["declined_once"]
	w.adopted_once = d["adopted_once"]
	w._events = []
	return w


static func _encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, v)
			return {"$f": str(b.decode_s64(0))}
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _encode(v[k])
			return out
		TYPE_ARRAY:
			return v.map(_encode)
	return v


## Inverse of `_encode`; a malformed float marker adds an entry to `bad`.
static func _decode(v: Variant, bad: Array) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.size() == 1 and v.has("$f"):
				if not (_is_str(v["$f"]) and v["$f"].is_valid_int()):
					bad.append(true)
					return 0.0
				var b := PackedByteArray()
				b.resize(8)
				b.encode_s64(0, int(v["$f"]))
				return b.decode_double(0)
			var out := {}
			for k in v:
				out[k] = _decode(v[k], bad)
			return out
		TYPE_ARRAY:
			return v.map(func(x): return _decode(x, bad))
	return v


static func _ints(src: Dictionary, int_keys: Array) -> Dictionary:
	var out := src.duplicate(true)
	for k in int_keys:
		out[k] = int(out[k])
	return out


static func _int_values(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[str(k)] = int(src[k])
	return out


# --- validation: pure checks, no engine errors, nothing is built until all of it passes ---

static func _is_num(v) -> bool:
	var t := typeof(v)
	return t == TYPE_INT or (t == TYPE_FLOAT and is_finite(v))


static func _is_whole(v) -> bool:
	var t := typeof(v)
	return t == TYPE_INT or (t == TYPE_FLOAT and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15)


static func _is_str(v) -> bool:
	return typeof(v) == TYPE_STRING


static func _is_bool(v) -> bool:
	return typeof(v) == TYPE_BOOL


## True when `d` is a Dictionary whose `kind`-typed keys are all present.
## kind: "i" whole number, "n" number, "s" string, "b" bool, "a" array, "d" dictionary.
static func _has(d, spec: Dictionary) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for k in spec:
		if not d.has(k):
			return false
		var v = d[k]
		var ok := false
		match spec[k]:
			"i": ok = _is_whole(v)
			"n": ok = _is_num(v)
			"s": ok = _is_str(v)
			"b": ok = _is_bool(v)
			"a": ok = typeof(v) == TYPE_ARRAY
			"d": ok = typeof(v) == TYPE_DICTIONARY
		if not ok:
			return false
	return true


static func _all_strings(a: Array) -> bool:
	for v in a:
		if not _is_str(v):
			return false
	return true


## Dictionary whose values are all whole numbers and (when `ids` is given) keys all in it.
static func _count_map(v, ids = null, key_whole := false) -> bool:
	if typeof(v) != TYPE_DICTIONARY:
		return false
	for k in v:
		if key_whole:
			if not (_is_str(k) and k.is_valid_int()):
				return false
		elif not _is_str(k) or (ids != null and not ids.has(k)):
			return false
		if not _is_whole(v[k]):
			return false
	return true


static func _valid_person(pack: Pack, p) -> bool:
	if not _has(p, {"uid": "i", "given": "s", "family": "s", "gender": "s", "age": "n",
			"lifespan": "n", "alive": "b", "needs": "d", "likes": "a", "dislikes": "a",
			"habits": "d", "praise_times": "a", "track": "s", "level": "i", "progress": "n",
			"aptitude": "n", "illness": "s", "current": "d", "last_action": "s", "last_action_t": "i"}):
		return false
	for k in p["needs"]:
		if not (pack.needs.has(k) and _is_num(p["needs"][k])):
			return false
	for k in p["habits"]:
		if not (_is_str(k) and _is_num(p["habits"][k])):
			return false
	for t in p["praise_times"]:
		if not _is_whole(t):
			return false
	if p["track"] != "" and not pack.livelihoods.has(p["track"]):
		return false
	if p["illness"] != "" and not pack.illnesses.has(p["illness"]):
		return false
	var c: Dictionary = p["current"]
	if c.is_empty():
		return true
	return _has(c, {"action": "s", "object_uid": "i", "target_uid": "i", "remaining_s": "i"}) \
			and pack.actions.has(c["action"])


## Every entry has uid, x, y, a `type` known in `types`, plus `extra` whole-number keys;
## `with_room` also demands a `room` the pack knows.
static func _valid_placed(pack: Pack, a, types: Dictionary, with_room: bool, extra: Array) -> bool:
	if typeof(a) != TYPE_ARRAY:
		return false
	var spec := {"uid": "i", "type": "s", "x": "i", "y": "i"}
	for e in extra:
		spec[e] = "i"
	if with_room:
		spec["room"] = "s"
	for o in a:
		if not _has(o, spec) or not types.has(o["type"]):
			return false
		if with_room and not pack.rooms.has(o["room"]):
			return false
	return true


static func _valid_save(pack: Pack, d: Dictionary) -> bool:
	if not _has(d, {"version": "i", "pack_id": "s", "seed": "s", "rng": "d", "phase": "s",
			"now": "i", "utc_offset": "i", "acc": "n", "next_uid": "i", "money": "i",
			"people": "a", "objects": "a", "stock": "d", "inventory": "d", "income_carry": "d",
			"messes": "a", "rooms_built": "a", "stats": "d", "collectibles": "a",
			"collection": "d", "goals_done": "a", "married": "b", "candidate": "d",
			"proposals": "a", "next_proposal_at": "i", "declined_once": "b", "adopted_once": "b"}):
		return false
	if int(d["version"]) != SAVE_VERSION or d["pack_id"] != pack.id:
		return false
	if not (d["phase"] in _PHASES) or not d["seed"].is_valid_int() or int(d["money"]) < 0:
		return false
	if not _has(d["rng"], {"seed": "s", "state": "s"}) or not d["rng"]["seed"].is_valid_int() \
			or not d["rng"]["state"].is_valid_int():
		return false
	for p in d["people"]:
		if not _valid_person(pack, p):
			return false
	if not _valid_placed(pack, d["objects"], pack.object_types, true, []):
		return false
	if not _valid_placed(pack, d["messes"], pack.mess_types, true, []):
		return false
	if not _valid_placed(pack, d["collectibles"], pack.collectibles, false, ["expires_at"]):
		return false
	if not (_count_map(d["stock"]) and _count_map(d["inventory"]) and _count_map(d["collection"], pack.collectibles)):
		return false
	if not _count_map(d["income_carry"], null, true):
		return false
	if not _count_map(d["stats"]) or not _has(d["stats"], {"cured": "i", "collected": "i", "mess_cleaned": "i", "all_clean": "i"}):
		return false
	if not _all_strings(d["goals_done"]) or not _all_strings(d["rooms_built"]):
		return false
	for r in d["rooms_built"]:
		if not pack.rooms.has(r):
			return false
	if not d["candidate"].is_empty() and not _valid_person(pack, d["candidate"]):
		return false
	for pr in d["proposals"]:
		if not _has(pr, {"id": "i", "person": "d", "savings": "i", "expires_at": "i"}) \
				or not _valid_person(pack, pr["person"]):
			return false
	return true
