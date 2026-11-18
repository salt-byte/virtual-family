class_name WorldSave
extends RefCounted
## Turns a World into save data and back, and checks save data before anything is built.
## `World.to_dict` / `World.from_dict` are the public entry points; this holds the work.

const _PHASES := ["adopting", "living", "over", "invalid"]


## Everything that decides what happens next, as plain data (deep copy; JSON-safe).
## Not saved: `offline` (transient) and undrained events. Ints used as dictionary keys
## (`income_carry`) are written as strings, because JSON keys always are. Godot's JSON
## parser can be one ulp off for a float, so every float is written as {"$f": "<bits>"},
## the decimal text of its 64 IEEE bits, which survives any JSON round trip exactly.
static func to_dict(w: World) -> Dictionary:
	return _encode(_snapshot(w))


static func _snapshot(w: World) -> Dictionary:
	var carry := {}
	for uid in w.income_carry:
		carry[str(uid)] = w.income_carry[uid]
	var ppl: Array = []
	for p in w.people:
		ppl.append(p.to_dict())
	return {
		"version": World.SAVE_VERSION, "pack_id": w.pack.id, "seed": w.rng.get_state()["seed"],
		"rng": w.rng.get_state(), "phase": w.phase, "now": w.now, "utc_offset": w.utc_offset,
		"acc": w._acc, "next_uid": w._next_uid, "money": w.money, "people": ppl,
		"objects": w.objects.duplicate(true), "stock": w.stock.duplicate(true),
		"inventory": w.inventory.duplicate(true), "income_carry": carry,
		"messes": w.messes.duplicate(true), "rooms_built": w.rooms_built.duplicate(),
		"stats": w.stats.duplicate(true), "collectibles": w.collectibles.duplicate(true),
		"collection": w.collection.duplicate(true), "goals_done": w.goals_done.duplicate(),
		"married": w.married, "candidate": w.candidate.duplicate(true),
		"proposals": w.proposals.duplicate(true), "next_proposal_at": w.next_proposal_at,
		"declined_once": w.declined_once, "adopted_once": w.adopted_once,
	}


## Rebuilds a world from `to_dict` output, also after a JSON round trip (numbers come back
## as floats and are restored to the exact types the live world uses). Returns null, with
## no engine error, whenever `restore` reports an error.
static func from_dict(pack: Pack, saved: Dictionary) -> World:
	return restore(pack, saved)["world"]


## {world: World or null, error}: error "corrupt" for a wrong version or pack, a missing key
## or a value of the wrong shape; "pack_changed" when well-shaped data names an id this pack
## no longer has (or lacks one of its needs), i.e. the pack's content was updated.
static func restore(pack: Pack, saved: Dictionary) -> Dictionary:
	var bad := []
	var d: Dictionary = _decode(saved, bad)
	if pack == null or not bad.is_empty() or not _valid_save(pack, d):
		return {"world": null, "error": "corrupt"}
	if not _ids_known(pack, d):
		return {"world": null, "error": "pack_changed"}
	return {"world": _build(pack, d), "error": ""}


static func _build(pack: Pack, d: Dictionary) -> World:
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
	# A save from before the pack built more rooms from the start gains them.
	for id in pack.rooms:
		if pack.rooms[id].get("built") == true and not w.rooms_built.has(str(id)):
			w.rooms_built.append(str(id))
	# ...and the fixed furniture of its rooms: each prop whose kind is missing from its room
	# is added where it still fits (skipped silently where something now stands).
	if bool(d["adopted_once"]):
		for room in w.rooms_built:
			HouseSystem.place_props(w, room, true)
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
				if not _is_i64(v["$f"]):
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


## A String holding a whole number that fits in 64 bits (`int()` prints an engine error
## for anything larger, so this must run first).
static func _is_i64(v) -> bool:
	if not _is_str(v) or not v.is_valid_int():
		return false
	var neg: bool = v.begins_with("-")
	var digits: String = v.trim_prefix("-").trim_prefix("+").lstrip("0")
	if digits.length() != 19:
		return digits.length() < 19
	return digits <= ("9223372036854775808" if neg else "9223372036854775807")


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


## Dictionary whose values are all whole numbers and whose keys are strings (`key_whole`:
## strings holding a 64-bit whole number).
static func _count_map(v, key_whole := false) -> bool:
	if typeof(v) != TYPE_DICTIONARY:
		return false
	for k in v:
		if key_whole:
			if not _is_i64(k):
				return false
		elif not _is_str(k):
			return false
		if not _is_whole(v[k]):
			return false
	return true


static func _valid_person(p) -> bool:
	if not _has(p, {"uid": "i", "given": "s", "family": "s", "gender": "s", "age": "n",
			"lifespan": "n", "alive": "b", "needs": "d", "likes": "a", "dislikes": "a",
			"habits": "d", "praise_times": "a", "track": "s", "level": "i", "progress": "n",
			"aptitude": "n", "illness": "s", "current": "d", "last_action": "s", "last_action_t": "i"}):
		return false
	for k in p["needs"]:
		if not (_is_str(k) and _is_num(p["needs"][k])):
			return false
	if not (_all_strings(p["likes"]) and _all_strings(p["dislikes"])):
		return false
	for k in p["habits"]:
		if not (_is_str(k) and _is_num(p["habits"][k])):
			return false
	for t in p["praise_times"]:
		if not _is_whole(t):
			return false
	# optional (older saves lack it); a fraction of a coin: 0 <= work_carry < 1
	if p.has("recent_actions") and not (typeof(p["recent_actions"]) == TYPE_ARRAY and _all_strings(p["recent_actions"])):
		return false  # optional: older saves lack it
	if p.has("work_carry") and not (_is_num(p["work_carry"]) and float(p["work_carry"]) >= 0.0 and float(p["work_carry"]) < 1.0):
		return false
	if p.has("childhood"):  # optional: older saves lack it; action id -> whole count >= 0
		if typeof(p["childhood"]) != TYPE_DICTIONARY:
			return false
		for k in p["childhood"]:
			if not (_is_str(k) and _is_whole(p["childhood"][k]) and float(p["childhood"][k]) >= 0.0):
				return false
	var c: Dictionary = p["current"]
	if c.has("room") and not _is_str(c["room"]):
		return false  # optional: saves from before actions had rooms lack it
	return c.is_empty() or _has(c, {"action": "s", "object_uid": "i", "target_uid": "i", "remaining_s": "i"})


## Every entry has uid, x, y, a string `type`, plus `extra` whole-number keys and, when
## `with_room`, a string `room`.
static func _valid_placed(a, with_room: bool, extra: Array) -> bool:
	if typeof(a) != TYPE_ARRAY:
		return false
	var spec := {"uid": "i", "type": "s", "x": "i", "y": "i"}
	for e in extra:
		spec[e] = "i"
	if with_room:
		spec["room"] = "s"
	for o in a:
		if not _has(o, spec):
			return false
	return true


## Shape only: every key present with the right type and range; ids are not looked up here.
static func _valid_save(pack: Pack, d: Dictionary) -> bool:
	if not _has(d, {"version": "i", "pack_id": "s", "seed": "s", "rng": "d", "phase": "s",
			"now": "i", "utc_offset": "i", "acc": "n", "next_uid": "i", "money": "i",
			"people": "a", "objects": "a", "stock": "d", "inventory": "d", "income_carry": "d",
			"messes": "a", "rooms_built": "a", "stats": "d", "collectibles": "a",
			"collection": "d", "goals_done": "a", "married": "b", "candidate": "d",
			"proposals": "a", "next_proposal_at": "i", "declined_once": "b", "adopted_once": "b"}):
		return false
	if int(d["version"]) != World.SAVE_VERSION or d["pack_id"] != pack.id:
		return false
	if not (d["phase"] in _PHASES) or not _is_i64(d["seed"]) or int(d["money"]) < 0:
		return false
	# A partial step: below 60 s, the largest legal step. A save written when the pack had
	# longer steps may hold more than one current step; `advance` folds it into whole steps.
	if float(d["acc"]) < 0.0 or float(d["acc"]) >= 60.0:
		return false
	if not _has(d["rng"], {"seed": "s", "state": "s"}) or not _is_i64(d["rng"]["seed"]) \
			or not _is_i64(d["rng"]["state"]):
		return false
	for p in d["people"]:
		if not _valid_person(p):
			return false
	if not (_valid_placed(d["objects"], true, []) and _valid_placed(d["messes"], true, [])
			and _valid_placed(d["collectibles"], true, ["expires_at"])):
		return false
	if not (_count_map(d["stock"]) and _count_map(d["inventory"]) and _count_map(d["collection"])):
		return false
	if not _count_map(d["income_carry"], true):
		return false
	if not _count_map(d["stats"]) or not _has(d["stats"], {"cured": "i", "collected": "i", "mess_cleaned": "i", "all_clean": "i"}):
		return false
	if not _all_strings(d["goals_done"]) or not _all_strings(d["rooms_built"]):
		return false
	if not d["candidate"].is_empty() and not _valid_person(d["candidate"]):
		return false
	for pr in d["proposals"]:
		if not _has(pr, {"id": "i", "person": "d", "savings": "i", "expires_at": "i"}) \
				or not _valid_person(pr["person"]):
			return false
	# The uid counter must lie above every uid in use, or new things would collide.
	var top := 0
	for key in ["people", "objects", "messes", "collectibles"]:
		for e in d[key]:
			top = maxi(top, int(e["uid"]))
	for pr in d["proposals"]:
		top = maxi(top, int(pr["id"]))
	return int(d["next_uid"]) > top


# --- pack references: run on well-shaped data; a miss means the pack's content changed ---

## True when every pack id the save refers to still exists (and every need the pack has
## is in each saved person).
static func _ids_known(pack: Pack, d: Dictionary) -> bool:
	var persons: Array = d["people"].duplicate()
	if not d["candidate"].is_empty():
		persons.append(d["candidate"])
	for pr in d["proposals"]:
		persons.append(pr["person"])
	for p in persons:
		if not _person_ids_known(pack, p):
			return false
	for o in d["objects"]:
		if not (pack.object_types.has(o["type"]) and pack.rooms.has(o["room"])):
			return false
	for m in d["messes"]:
		if not (pack.mess_types.has(m["type"]) and pack.rooms.has(m["room"])):
			return false
	for c in d["collectibles"]:
		if not (pack.collectibles.has(c["type"]) and pack.rooms.has(c["room"])):
			return false
	return _keys_in(d["inventory"], pack.items) and _keys_in(d["collection"], pack.collectibles) \
			and _all_in(d["rooms_built"], pack.rooms) and _all_in(d["goals_done"], pack.goals)


static func _person_ids_known(pack: Pack, p: Dictionary) -> bool:
	if not (_keys_in(p["needs"], pack.needs) and _keys_in(pack.needs, p["needs"])):
		return false
	if not _keys_in(p["habits"], pack.actions):
		return false
	if p["track"] != "" and not pack.livelihoods.has(p["track"]):
		return false
	if p["illness"] != "" and not pack.illnesses.has(p["illness"]):
		return false
	if p["last_action"] != "" and not pack.actions.has(p["last_action"]):
		return false
	if p.has("recent_actions") and not _all_in(p["recent_actions"], pack.actions):
		return false
	if p.has("childhood") and not _keys_in(p["childhood"], pack.actions):
		return false
	if p["current"].has("room") and not pack.rooms.has(p["current"]["room"]):
		return false
	return p["current"].is_empty() or pack.actions.has(p["current"]["action"])


static func _keys_in(d: Dictionary, ids: Dictionary) -> bool:
	for k in d:
		if not ids.has(k):
			return false
	return true


static func _all_in(a: Array, ids: Dictionary) -> bool:
	for v in a:
		if not ids.has(v):
			return false
	return true
