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
	var out := {
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
	# Optional: written only once a story has unlocked (older saves and story-less packs lack it).
	if not w.stories.is_empty():
		out["stories"] = w.stories.duplicate(true)
	# Optional: written only once something is kept in the box (older saves lack it).
	if not w.box.is_empty():
		out["box"] = w.box.duplicate(true)
	if w.weather_slot >= 0:  # optional: only once a pack with seasons has rolled the weather
		out["weather"] = {"season": w.season, "now": w.weather, "slot": w.weather_slot, "wet_until": w.wet_until}
	if w.festival != "":  # optional: only while a festival is on
		out["festival"] = w.festival
	if w.clean_paid_day >= 0:  # optional: only once the house was paid for being clean
		out["clean_paid_day"] = w.clean_paid_day
	if not w.dishes.is_empty():  # optional: written only while food is out
		out["dishes"] = w.dishes.duplicate(true)
	if w.birth_blocked:  # optional: written only while true
		out["birth_blocked"] = true
	# Optional, written only once there is something to keep: the animals (and the record of
	# those gone), one waiting at the gate, the share of a stock saved, the children's grief.
	if not w.pets.is_empty():
		var pets: Array = []
		for pet in w.pets:
			pets.append(pet.to_dict())
		out["pets"] = pets
	if not w.pet_offer.is_empty():
		out["pet_offer"] = w.pet_offer.duplicate(true)
	if not w.pet_saved.is_empty():
		out["pet_saved"] = w.pet_saved.duplicate(true)
	if w.pet_grief_until > 0:
		out["pet_grief_until"] = w.pet_grief_until
	if not w.pet_buyer.is_empty():
		out["pet_buyer"] = w.pet_buyer.duplicate(true)
	if w.letter_next > 1:  # optional: only once a letter came (older saves lack it)
		out["letters"] = {"list": w.letters.duplicate(true), "next": w.letter_next, "minor_at": w.letter_minor_at}
	# Optional, written only once the market has something to keep (older saves lack it).
	var market := {}
	if not w.secondhand.is_empty():
		market["secondhand"] = w.secondhand.duplicate(true)
	if not w.services_bought.is_empty():
		market["bought"] = w.services_bought.duplicate(true)
	if w.ticket_next > 1:
		market["tickets"] = w.tickets.duplicate(true)
		market["ticket_next"] = w.ticket_next
	if w.helper_until > 0:
		market["helper"] = {"until": w.helper_until, "service": w.helper_service}
	if w.adopt_service != "":
		market["adopt_service"] = w.adopt_service
	if not w.doctor.is_empty():
		market["doctor"] = w.doctor.duplicate(true)
	if w.speed_until > 0 or w.clock_lead != 0:
		market["speed"] = {"until": w.speed_until, "factor": w.speed_factor, "lead": w.clock_lead}
	if not market.is_empty():
		out["market"] = market
	return out


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
		w.people.append(_gain_needs(pack, Person.from_dict(pd)))
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
	# A room that shrank since the save keeps what stood in it: see `_fit_to_rooms`.
	_fit_to_rooms(w)
	# ...and the fixed furniture of its rooms: each prop whose kind is missing from its room
	# is added where it still fits (skipped silently where something now stands).
	if bool(d["adopted_once"]):
		for room in w.rooms_built:
			HouseSystem.place_props(w, room, true)
	w.stats = _int_values(d["stats"])
	w.collectibles.clear()
	for c in d["collectibles"]:
		w.collectibles.append(_ints(c, ["uid", "x", "y", "expires_at"]))
	for c in w.collectibles:
		_clamp_into_room(pack, c)
	w.collection = _int_values(d["collection"])
	# A save from before the box: of each kind found, the first was kept and the rest sold.
	w.box = {}
	if d.has("box"):
		w.box = _int_values(d["box"])
	elif CollectibleSystem.keeps(pack):
		for k in w.collection:
			if int(w.collection[k]) > 0:
				w.box[k] = 1
	w.goals_done.clear()
	for g in d["goals_done"]:
		w.goals_done.append(str(g))
	w.married = d["married"]
	w.candidate = {} if d["candidate"].is_empty() else _gain_needs(pack, Person.from_dict(d["candidate"])).to_dict()
	w.proposals.clear()
	for pr in d["proposals"]:
		var prop := {"id": int(pr["id"]), "person": _gain_needs(pack, Person.from_dict(pr["person"])).to_dict(),
			"savings": int(pr["savings"]), "expires_at": int(pr["expires_at"])}
		if pr.has("for"):  # optional: only with births on, and absent in older saves
			prop["for"] = int(pr["for"])
		w.proposals.append(prop)
	w.next_proposal_at = int(d["next_proposal_at"])
	w.declined_once = d["declined_once"]
	w.adopted_once = d["adopted_once"]
	w.stories = {}
	var sd: Dictionary = d.get("stories", {})  # absent in saves from before stories existed
	for sid in sd:
		var found: Array = []
		for f in sd[sid]["found"]:
			found.append(str(f))
		w.stories[str(sid)] = {"found": found, "stage": str(sd[sid]["stage"])}
	w.blessing_illness = StorySystem.illness_factor(w)
	w.birth_blocked = bool(d.get("birth_blocked", false))
	var wd: Dictionary = d.get("weather", {})  # absent in older saves and packs without seasons
	if not wd.is_empty() and WeatherSystem.enabled(pack):
		w.season = str(wd["season"])
		w.weather = str(wd["now"]) if not WeatherSystem.weather_entry(pack, str(wd["now"])).is_empty() else ""
		w.weather_slot = int(wd["slot"]) if w.weather != "" else -1
		w.wet_until = int(wd["wet_until"])
	w.clean_paid_day = int(d.get("clean_paid_day", -1))  # absent in older saves
	# Absent in older saves and while no festival is on; one the pack no longer has is dropped.
	w.festival = str(d.get("festival", ""))
	if not pack.festivals.has(w.festival):
		w.festival = ""
	w.dishes.clear()
	for dd in d.get("dishes", []):  # absent in older saves and while no food is out
		if pack.dishes.has(str(dd.get("type", ""))) and w.object(int(dd.get("object_uid", -1))).size() > 0:
			w.dishes.append(_ints(dd, ["uid", "object_uid", "x", "y", "portions", "expires_at"]))
	w.pets.clear()
	for pd in d.get("pets", []):  # absent in older saves and before the first animal
		w.pets.append(Pet.from_dict(pd))
	var po: Dictionary = d.get("pet_offer", {})
	w.pet_offer = {} if po.is_empty() else {"kind": str(po["kind"]), "given": str(po["given"]),
		"age": float(po["age"]), "expires_at": int(po["expires_at"])}
	w.pet_saved = {}
	var ps: Dictionary = d.get("pet_saved", {})
	for k in ps:
		w.pet_saved[str(k)] = float(ps[k])
	w.pet_grief_until = int(d.get("pet_grief_until", 0))
	var pb: Dictionary = d.get("pet_buyer", {})  # absent in older saves and while nobody waits
	w.pet_buyer = {} if pb.is_empty() else {"pet": int(pb["pet"]), "price": int(pb["price"]),
		"expires_at": int(pb["expires_at"])}
	var ld: Dictionary = d.get("letters", {})  # absent in older saves and before the first letter
	if not ld.is_empty():
		w.letters.clear()
		for l in ld["list"]:
			w.letters.append(_letter(l))
		w.letter_next = int(ld["next"])
		w.letter_minor_at = int(ld["minor_at"])
	_restore_market(w, d.get("market", {}))
	PetSystem.rebuild_held(w)
	if BirthSystem.enabled(pack):
		_link_old_couple(w)
	if MoodSystem.enabled(pack):
		for p in w.people:
			MoodSystem.refresh_cap(w, p)
	w._events = []
	return w


## The market's part of a save (see `_snapshot`); `md` passed `_valid_market`. Listings and
## services the pack no longer has are dropped.
static func _restore_market(w: World, md: Dictionary) -> void:
	var sh: Dictionary = md.get("secondhand", {})
	if not sh.is_empty():
		var list: Array = []
		for l in sh["list"]:
			var src: Dictionary = w.pack.items if str(l["kind"]) == "item" else w.pack.object_types
			if src.has(str(l["id"])):
				list.append({"n": int(l["n"]), "kind": str(l["kind"]), "id": str(l["id"]), "price": int(l["price"]), "sold": bool(l["sold"])})
		w.secondhand = {"slot": int(sh["slot"]), "list": list, "next": int(sh["next"])}
	var bought: Dictionary = md.get("bought", {})
	for k in bought:
		if w.pack.services.has(str(k)):
			w.services_bought[str(k)] = int(bought[k])
	for t in md.get("tickets", []):
		if w.pack.services.has(str(t["service"])):
			w.tickets.append({"id": int(t["id"]), "service": str(t["service"]), "draw_at": int(t["draw_at"]), "amount": int(t["amount"])})
	w.ticket_next = int(md.get("ticket_next", 1))
	var hd: Dictionary = md.get("helper", {})
	if not hd.is_empty() and w.pack.services.has(str(hd["service"])):
		w.helper_until = int(hd["until"])
		w.helper_service = str(hd["service"])
	w.adopt_service = str(md.get("adopt_service", ""))
	if not w.pack.services.has(w.adopt_service):
		w.adopt_service = ""
		if w.phase == "living":
			w.candidate = {}  # an offer from a service the pack lost
	var dd: Dictionary = md.get("doctor", {})
	if not dd.is_empty() and w.pack.services.has(str(dd["service"])):
		w.doctor = {"person": int(dd["person"]), "service": str(dd["service"]), "phase": str(dd["phase"]),
			"at": int(dd["at"]), "fee": int(dd["fee"])}
	var sp: Dictionary = md.get("speed", {})
	if not sp.is_empty():
		w.speed_until = int(sp["until"])
		w.speed_factor = float(sp["factor"])
		w.clock_lead = int(sp["lead"])


## Shape of the optional `market` part of a save.
static func _valid_market(m) -> bool:
	if typeof(m) != TYPE_DICTIONARY:
		return false
	if m.has("secondhand"):
		var sh = m["secondhand"]
		if not _has(sh, {"slot": "i", "list": "a", "next": "i"}):
			return false
		for l in sh["list"]:
			if not _has(l, {"n": "i", "kind": "s", "id": "s", "price": "i", "sold": "b"}) or not (l["kind"] in ["item", "object"]):
				return false
	if m.has("bought") and not _count_map(m["bought"]):
		return false
	if m.has("tickets"):
		if typeof(m["tickets"]) != TYPE_ARRAY or not _is_whole(m.get("ticket_next")):
			return false
		for t in m["tickets"]:
			if not _has(t, {"id": "i", "service": "s", "draw_at": "i", "amount": "i"}):
				return false
	if m.has("helper") and not _has(m["helper"], {"until": "i", "service": "s"}):
		return false
	if m.has("adopt_service") and not _is_str(m["adopt_service"]):
		return false
	if m.has("doctor") and not (_has(m["doctor"], {"person": "i", "service": "s", "phase": "s", "at": "i", "fee": "i"})
			and str(m["doctor"]["phase"]) in ["coming", "examining"]):
		return false
	if m.has("speed") and not _has(m["speed"], {"until": "i", "factor": "n", "lead": "i"}):
		return false
	return true


## A save from before spouses were linked: a household that had its wedding links its first
## man and first woman who are grown-ups (that is who the couple was: nobody was born yet).
static func _link_old_couple(w: World) -> void:
	if not w.married or w.people.any(func(p: Person): return p.spouse != 0):
		return
	var man: Person = null
	var woman: Person = null
	for p in w.people:
		if not (p.stage(w.pack) in ["adult", "elder"]):
			continue
		if p.gender == "male" and man == null:
			man = p
		elif p.gender == "female" and woman == null:
			woman = p
	if man != null and woman != null:
		man.spouse = woman.uid
		woman.spouse = man.uid


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
	# Optional (older saves lack them): the wish, the thanks, the mood and the generation.
	if p.has("wish") and not (typeof(p["wish"]) == TYPE_DICTIONARY and (p["wish"].is_empty() \
			or _has(p["wish"], {"id": "s", "expires_at": "i"}))):
		return false
	if p.has("wish_last") and not _is_str(p["wish_last"]):
		return false
	if p.has("look") and not _is_str(p["look"]):
		return false  # optional: older saves lack it
	if p.has("mood") and not (_is_str(p["mood"]) and p["mood"] in ["", "sad", "depressed"]):
		return false
	for k in ["thanks_until", "mood_low_s", "mood_ok_s", "generation", "cared_at",
			"spouse", "mother", "father", "pregnant_until", "pregnant_by"]:
		if p.has(k) and not (_is_whole(p[k]) and float(p[k]) >= 0.0):
			return false
	# Optional (older saves lack them): the day's earnings and what is being shared.
	if p.has("earned") and not (typeof(p["earned"]) == TYPE_DICTIONARY and _has(p["earned"], {"day": "i", "n": "i", "told": "i", "shared_at": "i"})):
		return false
	if p.has("share") and not (typeof(p["share"]) == TYPE_DICTIONARY and _has(p["share"], {"kind": "s", "n": "i", "level": "i"})):
		return false
	var c: Dictionary = p["current"]
	if c.has("led") and not c["led"] is bool:
		return false
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
	for c in d["collectibles"]:
		if c.has("story") and not _is_str(c["story"]):
			return false
	if d.has("stories"):  # optional: older saves lack it
		if typeof(d["stories"]) != TYPE_DICTIONARY:
			return false
		for sid in d["stories"]:
			var st = d["stories"][sid]
			if not _has(st, {"found": "a", "stage": "s"}) or not _all_strings(st["found"]) \
					or not (st["stage"] in ["open", "finale", "done"]):
				return false
	if d.has("box") and not (_count_map(d["box"]) and (d["box"] as Dictionary).values().all(func(v): return v >= 0)):
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
		if pr.has("for") and not (_is_whole(pr["for"]) and float(pr["for"]) > 0.0):
			return false
	if d.has("birth_blocked") and not _is_bool(d["birth_blocked"]):
		return false
	if d.has("weather") and not _has(d["weather"], {"season": "s", "now": "s", "slot": "i", "wet_until": "i"}):
		return false
	if d.has("clean_paid_day") and not _is_whole(d["clean_paid_day"]):
		return false
	if d.has("festival") and typeof(d["festival"]) != TYPE_STRING:
		return false
	if d.has("dishes"):  # optional: only while food is out
		if typeof(d["dishes"]) != TYPE_ARRAY:
			return false
		for dd in d["dishes"]:
			if not _has(dd, {"uid": "i", "type": "s", "object_uid": "i", "room": "s", "x": "i", "y": "i",
					"portions": "i", "expires_at": "i"}):
				return false
	if d.has("pets"):  # optional: only once an animal came to the house
		if typeof(d["pets"]) != TYPE_ARRAY:
			return false
		for pet in d["pets"]:
			if not _valid_pet(pet):
				return false
	if d.has("pet_offer") and not (typeof(d["pet_offer"]) == TYPE_DICTIONARY and (d["pet_offer"].is_empty() \
			or _has(d["pet_offer"], {"kind": "s", "given": "s", "age": "n", "expires_at": "i"}))):
		return false
	if d.has("pet_saved"):
		if typeof(d["pet_saved"]) != TYPE_DICTIONARY:
			return false
		for k in d["pet_saved"]:
			if not (_is_str(k) and _is_num(d["pet_saved"][k]) and float(d["pet_saved"][k]) >= 0.0):
				return false
	if d.has("pet_buyer") and not (typeof(d["pet_buyer"]) == TYPE_DICTIONARY and (d["pet_buyer"].is_empty() \
			or _has(d["pet_buyer"], {"pet": "i", "price": "i", "expires_at": "i"}))):
		return false
	if d.has("pet_grief_until") and not (_is_whole(d["pet_grief_until"]) and float(d["pet_grief_until"]) >= 0.0):
		return false
	if d.has("letters") and not _valid_letters(d["letters"]):
		return false
	if d.has("market") and not _valid_market(d["market"]):
		return false
	# The uid counter must lie above every uid in use, or new things would collide.
	var top := 0
	for key in ["people", "objects", "messes", "collectibles"]:
		for e in d[key]:
			top = maxi(top, int(e["uid"]))
	for pr in d["proposals"]:
		top = maxi(top, int(pr["id"]))
	for dd in d.get("dishes", []):
		top = maxi(top, int(dd["uid"]))
	for pet in d.get("pets", []):
		top = maxi(top, int(pet["uid"]))
	return int(d["next_uid"]) > top


## Saved letters: {list, next, minor_at}, every letter well-formed and numbered below `next`.
static func _valid_letters(ld) -> bool:
	if not _has(ld, {"list": "a", "next": "i", "minor_at": "i"}):
		return false
	for l in ld["list"]:
		if not _has(l, {"id": "i", "t": "i", "kind": "s", "template": "s", "from": "i", "about": "i",
				"writer": "s", "hand": "s", "text": "s", "sign": "s", "choices": "a", "answer": "i", "read": "b"}):
			return false
		if int(l["id"]) >= int(ld["next"]):
			return false
		for ch in l["choices"]:
			if not _has(ch, {"label": "s", "effect": "d"}) or not _valid_effect(ch["effect"]):
				return false
	return true


## A letter choice's effect: a known type with the fields that type acts on.
static func _valid_effect(e: Dictionary) -> bool:
	if not _has(e, {"type": "s"}) or not str(e["type"]) in LetterSystem.EFFECTS:
		return false
	match str(e["type"]):
		"mood":
			return _has(e, {"person": "i", "amount": "n"})
		"wish_keep":
			return _has(e, {"person": "i", "wish": "s", "amount": "n", "hours": "n"})
		"wish_drop":
			return _has(e, {"person": "i", "wish": "s", "amount": "n"})
		"answer_proposal":
			return _has(e, {"proposal": "i", "accept": "b"})
		"change_track":
			return _has(e, {"person": "i", "from": "s", "track": "s"})
		"money":
			return _has(e, {"amount": "i"})
	return true


## A saved letter with the exact types the live one has (JSON brings whole numbers back as floats).
static func _letter(l: Dictionary) -> Dictionary:
	var out := _ints(l, ["id", "t", "from", "about", "answer"])
	var choices: Array = []
	for ch in l["choices"]:
		var e: Dictionary = ch["effect"].duplicate(true)
		for k in ["person", "proposal"]:
			if e.has(k):
				e[k] = int(e[k])
		if str(e["type"]) == "money":
			e["amount"] = int(e["amount"])
		else:
			for k in ["amount", "hours"]:
				if e.has(k):
					e[k] = float(e[k])
		choices.append({"label": str(ch["label"]), "effect": e})
	out["choices"] = choices
	return out


## A saved pet: its keys with the right types; the optional ones in range.
static func _valid_pet(p) -> bool:
	if not _has(p, {"uid": "i", "kind": "s", "given": "s", "age": "n", "lifespan": "n", "alive": "b",
			"state": "s", "needs": "d", "sick": "b", "current": "d", "last_action": "s", "wish": "d",
			"wish_last": "s", "thanks_until": "i", "hungry_s": "i", "lonely_s": "i", "away_since": "i",
			"how": "s", "came_at": "i", "cause": "s", "died_at": "i"}):
		return false
	if not p["state"] in ["home", "away"]:
		return false
	for k in p["needs"]:
		if not (_is_str(k) and _is_num(p["needs"][k])):
			return false
	if not (p["wish"].is_empty() or _has(p["wish"], {"id": "s", "expires_at": "i"})):
		return false
	if p.has("done_at") and not _count_map(p["done_at"]):
		return false
	if p.has("weight") and not (_is_num(p["weight"]) and float(p["weight"]) >= 0.0):
		return false
	if p.has("young_at") and not (_is_whole(p["young_at"]) and float(p["young_at"]) >= 0.0):
		return false
	var c: Dictionary = p["current"]
	if not c.is_empty() and not _has(c, {"action": "s", "remaining_s": "i"}):
		return false
	for k in ["object_uid", "follow", "mess"]:
		if c.has(k) and not _is_whole(c[k]):
			return false
	return not c.has("room") or _is_str(c["room"])


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
		if not pack.rooms.has(c["room"]):
			return false
		if c.has("story"):
			if StorySystem.fragment(pack, c["story"], c["type"]).is_empty():
				return false
		elif not pack.collectibles.has(c["type"]):
			return false
	var sd: Dictionary = d.get("stories", {})
	for sid in sd:
		if not pack.stories.has(sid):
			return false
		for f in sd[sid]["found"]:
			if StorySystem.fragment(pack, sid, f).is_empty():
				return false
	for pet in d.get("pets", []):
		if not _pet_ids_known(pack, pet):
			return false
	if not d.get("pet_offer", {}).is_empty() and not pack.pets.has(d["pet_offer"]["kind"]):
		return false
	return _keys_in(d["inventory"], pack.items) and _keys_in(d["collection"], pack.collectibles) \
			and _keys_in(d.get("box", {}), pack.collectibles) \
			and _all_in(d["rooms_built"], pack.rooms) and _all_in(d["goals_done"], pack.goals)


## A person from a save written before the pack gained a need gets it at its `start`.
static func _gain_needs(pack: Pack, p: Person) -> Person:
	for nid in pack.needs:
		if not p.needs.has(nid):
			p.needs[nid] = float(pack.needs[nid]["start"])
	return p


## A need the pack no longer has is a change; one it gained is filled in (`_gain_needs`).
static func _person_ids_known(pack: Pack, p: Dictionary) -> bool:
	if not _keys_in(p["needs"], pack.needs):
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
	if p.has("wish") and not p["wish"].is_empty() and not pack.wishes.has(p["wish"]["id"]):
		return false
	return p["current"].is_empty() or pack.actions.has(p["current"]["action"])


static func _pet_ids_known(pack: Pack, p: Dictionary) -> bool:
	if not pack.pets.has(p["kind"]):
		return false
	var ids := {}
	for n in PetSystem.need_list(pack):
		ids[str(n.get("id", ""))] = true
	if not (_keys_in(p["needs"], ids) and _keys_in(ids, p["needs"])):
		return false
	var acts := {}
	for a in pack.pets[p["kind"]].get("actions", []):
		acts[str(a.get("id", ""))] = true
	var wishes := {}
	for w in pack.pets[p["kind"]].get("wishes", []):
		wishes[str(w.get("id", ""))] = true
	if p["last_action"] != "" and not acts.has(p["last_action"]):
		return false
	if not p["current"].is_empty() and not acts.has(p["current"]["action"]):
		return false
	if p["current"].has("room") and not pack.rooms.has(p["current"]["room"]):
		return false
	return p["wish"].is_empty() or wishes.has(p["wish"]["id"])


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


## Rooms may change size between versions of a pack. Furniture that no longer fits where it
## stood moves to the first free spot of the same room (row by row); fixed furniture that
## does not fit is dropped (the props step puts it back where it fits), and anything else
## that fits nowhere in its room is sold back at full price. Messes move inside the room.
static func _fit_to_rooms(w: World) -> void:
	var keep: Array[Dictionary] = []
	var moved: Array[Dictionary] = []
	for o in w.objects:
		if _fits_here(w, o, keep):
			keep.append(o)
		else:
			moved.append(o)
	w.objects = keep
	for o in moved:
		if HouseSystem.is_fixed(w, str(o["type"])):
			continue
		var r: Dictionary = w.pack.rooms[o["room"]]
		var placed := false
		for y in int(r["h"]):
			for x in int(r["w"]):
				if not placed and HouseSystem.can_place(w, str(o["type"]), str(o["room"]), x, y) == "":
					o["x"] = x
					o["y"] = y
					w.objects.append(o)
					placed = true
		if not placed:
			w.money += int(w.pack.object_types[o["type"]]["price"])
	for m in w.messes:
		_clamp_into_room(w.pack, m)


## Whether `o` still lies inside its room and clear of the pieces in `placed`.
static func _fits_here(w: World, o: Dictionary, placed: Array[Dictionary]) -> bool:
	var t: Dictionary = w.pack.object_types[o["type"]]
	var r: Dictionary = w.pack.rooms[o["room"]]
	var x := int(o["x"])
	var y := int(o["y"])
	if x < 0 or y < 0 or x + int(t["w"]) > int(r["w"]) or y + int(t["h"]) > int(r["h"]):
		return false
	for q in placed:
		if q["room"] != o["room"]:
			continue
		var qt: Dictionary = w.pack.object_types[q["type"]]
		if x < int(q["x"]) + int(qt["w"]) and int(q["x"]) < x + int(t["w"]) \
				and y < int(q["y"]) + int(qt["h"]) and int(q["y"]) < y + int(t["h"]):
			return false
	return true


## Moves a mess or a thing lying about back inside its room when the room shrank.
static func _clamp_into_room(pack: Pack, e: Dictionary) -> void:
	var r: Dictionary = pack.rooms[e["room"]]
	e["x"] = clampi(int(e["x"]), 0, int(r["w"]) - 1)
	e["y"] = clampi(int(e["y"]), 0, int(r["h"]) - 1)
