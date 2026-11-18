class_name PackValidator
extends RefCounted
## Structural and cross-reference checks for a loaded Pack.
## Errors are formatted "<file>: <entry id>: <message>".

const ACTION_KINDS := ["daily", "trouble", "flavor"]
const GOAL_TYPES := ["mess_cleared", "cured", "married", "money_at_least", "objects_owned",
	"room_built", "level_reached", "collected"]

## Required fields per file: name -> type (TYPE_*), TYPE_NIL meaning "any".
const REQUIRED := {
	"pack.json": {"id": TYPE_STRING, "name": TYPE_STRING, "vital_need": TYPE_STRING},
	"needs.json": {"name": TYPE_STRING, "drain_per_hour": TYPE_NIL, "start": TYPE_NIL, "labels": TYPE_ARRAY},
	"actions.json": {"label": TYPE_STRING, "kind": TYPE_STRING, "duration_min": TYPE_NIL},
	"objects.json": {"name": TYPE_STRING, "category": TYPE_STRING, "price": TYPE_NIL, "w": TYPE_NIL, "h": TYPE_NIL},
	"rooms.json": {"name": TYPE_STRING, "w": TYPE_NIL, "h": TYPE_NIL, "built": TYPE_BOOL, "build_cost": TYPE_NIL},
	"livelihoods.json": {"name": TYPE_STRING, "levels": TYPE_ARRAY},
	"items.json": {"name": TYPE_STRING, "category": TYPE_STRING, "price": TYPE_NIL},
	"illnesses.json": {"name": TYPE_STRING, "weight": TYPE_NIL, "drain": TYPE_DICTIONARY, "symptom_action": TYPE_STRING},
	"messes.json": {"name": TYPE_STRING, "spawn_per_day": TYPE_NIL, "outdoor": TYPE_BOOL, "penalty": TYPE_DICTIONARY},
	"collectibles.json": {"name": TYPE_STRING, "value": TYPE_NIL, "weight": TYPE_NIL},
	"goals.json": {"text": TYPE_STRING, "reward": TYPE_NIL, "when": TYPE_DICTIONARY},
	"wishes.json": {"text": TYPE_STRING, "kind": TYPE_STRING, "ttl_hours": TYPE_NIL, "joy": TYPE_NIL},
	"stories.json": {"title": TYPE_STRING, "unlock": TYPE_DICTIONARY, "fragments": TYPE_ARRAY, "finale": TYPE_DICTIONARY},
}
## Whole-number fields and their minimum (money, sizes and durations are never fractional or negative).
const MIN_INT := {
	"actions.json": {"duration_min": 1},
	"objects.json": {"price": 0, "w": 1, "h": 1, "capacity": 1},
	"rooms.json": {"w": 1, "h": 1, "build_cost": 0},
	"items.json": {"price": 0},
	"collectibles.json": {"value": 0},
	"goals.json": {"reward": 0},
}
const LEVEL_FIELDS := ["name", "daily_income", "work_bonus_per_hour", "progress_to_next"]
## The moods an action may require (see `MoodSystem`).
const MOODS := ["sad", "depressed"]
## Stage ids the kernel itself relies on (babies idle and never fall ill; adults and elders
## earn and marry).
const REQUIRED_STAGES := ["baby", "adult", "elder"]

var _errors: Array[String] = []
var _p: Pack


static func validate(pack: Pack) -> Array[String]:
	var v := PackValidator.new()
	v._p = pack
	v._run()
	return v._errors


func _err(file: String, id: String, msg: String) -> void:
	_errors.append("%s: %s: %s" % [file, id, msg])


func _run() -> void:
	_check_required()
	_check_pack_config()
	_check_names()
	_check_needs()
	_check_actions()
	_check_objects()
	_check_rooms()
	_check_livelihoods()
	_check_items()
	_check_illnesses()
	_check_messes()
	_check_goals()
	_check_collectibles()
	_check_wishes()
	_check_stories()
	_check_mood_config()
	_check_births()


func _check_required() -> void:
	# pack.json is not indexed, so check its raw dictionary directly.
	var pj = _p.raw.get("pack.json")
	if pj is Dictionary:
		_check_fields("pack.json", str(pj.get("id", "pack")), pj)
		if str(pj.get("id", "")) == "":
			_err("pack.json", "pack", "missing id")
	for files in [Pack.FILES, Pack.OPTIONAL_FILES]:
		for key in files:
			var file: String = files[key]
			for e in (_p.get(key) as Dictionary).values():
				_check_fields(file, e["id"], e)


func _check_int(file: String, eid: String, field: String, v: Variant, minimum: int) -> void:
	if not v is int:
		_err(file, eid, "field '%s' must be a whole number" % [field])
	elif v < minimum:
		_err(file, eid, "field '%s' must be at least %d" % [field, minimum])


func _check_fields(file: String, eid: String, e: Dictionary) -> void:
	var mins: Dictionary = MIN_INT.get(file, {})
	for f in mins:
		if e.has(f) and (e[f] is int or e[f] is float):
			_check_int(file, eid, f, e[f], mins[f])
	var req: Dictionary = REQUIRED.get(file, {})
	for f in req:
		if not e.has(f):
			_err(file, eid, "missing field '%s'" % [f])
		elif req[f] != TYPE_NIL and typeof(e[f]) != req[f]:
			_err(file, eid, "field '%s' has the wrong type" % [f])
		elif req[f] == TYPE_NIL and not (e[f] is int or e[f] is float):
			_err(file, eid, "field '%s' must be a number" % [f])


func _check_pack_config() -> void:
	var c := _p.config
	var vital := str(c.get("vital_need", ""))
	if vital != "" and not _p.needs.has(vital):
		_err("pack.json", _p.id, "vital_need '%s' is not a need" % [vital])
	_check_int("pack.json", _p.id, "start_money", c.get("start_money"), 0)
	var rf = c.get("repeat_factor")
	if not (rf is int or rf is float) or float(rf) <= 0.0 or float(rf) > 1.0:
		_err("pack.json", _p.id, "repeat_factor must be a number above 0 and at most 1")
	var ss = c.get("step_seconds")
	if not ss is int or ss <= 0 or 60 % ss != 0:
		_err("pack.json", _p.id, "step_seconds must be a whole number that divides 60 (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30 or 60)")
	var rm = c.get("repeat_memory")
	if not rm is int or rm < 1 or rm > 8:
		_err("pack.json", _p.id, "repeat_memory must be a whole number from 1 to 8")
	var cp = c.get("choice_pool")
	if not cp is int or cp < 1 or cp > 32:
		_err("pack.json", _p.id, "choice_pool must be a whole number from 1 to 32")
	var sp = c.get("action_speed")
	if not (sp is int or sp is float) or float(sp) < 1.0:
		_err("pack.json", _p.id, "action_speed must be a number of at least 1")
	_check_start_objects(c["start_objects"])
	var pn := str(c.get("praise_need", ""))
	if pn != "" and not _p.needs.has(pn):
		_err("pack.json", _p.id, "praise_need '%s' is not a need" % [pn])
	if c["work_needs_min"] is Dictionary:
		for k in c["work_needs_min"]:
			if not _p.needs.has(k):
				_err("pack.json", _p.id, "work_needs_min key '%s' is not a need" % [k])
	else:
		_err("pack.json", _p.id, "work_needs_min must be an object")
	_check_stages(c["stages"])


## Each starting piece of furniture must be placeable on its own (known type and room, room
## built, right indoor/outdoor kind, inside the room) and clear of the pieces before it.
func _check_start_objects(list) -> void:
	if not list is Array:
		_err("pack.json", _p.id, "start_objects must be an array")
		return
	var placed: Array = []
	for i in list.size():
		var why := _start_object_problem(list[i], placed)
		if why != "":
			_err("pack.json", _p.id, "start_objects #%d: %s" % [i, why])
		else:
			placed.append(list[i])


func _start_object_problem(e, placed: Array) -> String:
	if not (e is Dictionary and e.get("type") is String and e.get("room") is String
			and e.get("x") is int and e.get("y") is int):
		return "needs a string 'type' and 'room' and whole-number 'x' and 'y'"
	var t: Dictionary = _p.object_types.get(e["type"], {})
	if t.is_empty():
		return "'%s' is not an object type" % [e["type"]]
	if _is_true(t.get("fixed")):
		return "'%s' is fixed; list it in a room's props instead" % [e["type"]]
	var r: Dictionary = _p.rooms.get(e["room"], {})
	if r.is_empty():
		return "'%s' is not a room" % [e["room"]]
	return _place_problem(e, placed, true)


## Whether `e` ({type, room, x, y}, known type and room) fits its room clear of `placed`;
## `must_be_built`: the room has to be built from the start.
func _place_problem(e: Dictionary, placed: Array, must_be_built: bool) -> String:
	var t: Dictionary = _p.object_types[e["type"]]
	var r: Dictionary = _p.rooms[e["room"]]
	if not (t.get("w") is int and t.get("h") is int and r.get("w") is int and r.get("h") is int):
		return ""  # the size fields are reported on their own entries
	if must_be_built and r.get("built") != true:
		return "room '%s' is not built" % [e["room"]]
	if bool(t.get("outdoor")) != bool(r.get("outdoor")):
		return "'%s' does not belong in room '%s' (indoor/outdoor mismatch)" % [e["type"], e["room"]]
	var x: int = e["x"]
	var y: int = e["y"]
	if x < 0 or y < 0 or x + int(t["w"]) > int(r["w"]) or y + int(t["h"]) > int(r["h"]):
		return "'%s' at (%d, %d) is outside room '%s'" % [e["type"], x, y, e["room"]]
	for o in placed:
		if o["room"] != e["room"]:
			continue
		var ot: Dictionary = _p.object_types[o["type"]]
		if not (ot.get("w") is int and ot.get("h") is int):
			continue
		if x < int(o["x"]) + int(ot["w"]) and int(o["x"]) < x + int(t["w"]) \
				and y < int(o["y"]) + int(ot["h"]) and int(o["y"]) < y + int(t["h"]):
			return "'%s' at (%d, %d) overlaps '%s'" % [e["type"], x, y, o["type"]]
	return ""


## `Pack` sorts stages by `from` on load, so this rejects two stages starting at one age.
func _check_stages(stages) -> void:
	if not stages is Array:
		_err("pack.json", _p.id, "stages must be an array")
		return
	var ids := []
	var last := -INF
	for s in stages:
		if not (s is Dictionary and s.get("id") is String and (s.get("from") is int or s.get("from") is float)):
			_err("pack.json", _p.id, "each stage needs a string 'id' and a number 'from'")
			return
		if ids.has(s["id"]):
			_err("pack.json", _p.id, "stage id '%s' appears twice" % [s["id"]])
		ids.append(s["id"])
		if float(s["from"]) <= last:
			_err("pack.json", _p.id, "stage 'from' values must be strictly ascending (stage '%s')" % [s["id"]])
		last = float(s["from"])
	for id in REQUIRED_STAGES:
		if not ids.has(id):
			_err("pack.json", _p.id, "stages must include '%s'" % [id])


func _check_names() -> void:
	if not _p.raw.has("names.json"):
		return
	for f in ["family", "male", "female", "tags"]:
		if not _p.names.get(f) is Array:
			_err("names.json", f, "missing or not an array")


func _check_needs() -> void:
	for n in _p.needs.values():
		var labels = n.get("labels")
		if not labels is Array:
			continue
		if labels.is_empty():
			_err("needs.json", n["id"], "labels is empty")
			continue
		var ok := true
		for l in labels:
			if not (l is Dictionary and l.get("below") is int and l.has("text")):
				_err("needs.json", n["id"], "each label needs integer 'below' and 'text'")
				ok = false
				break
		if ok and labels[-1]["below"] < 101:
			_err("needs.json", n["id"], "last label 'below' must be at least 101")
		var we = n["when_empty"]
		if not we is Dictionary or (not we.is_empty() and (not _p.needs.has(we.get("need", "")) or not we.has("per_hour"))):
			_err("needs.json", n["id"], "when_empty must be {need, per_hour} naming an existing need")


func _check_actions() -> void:
	var stock_names := {}
	for it in _p.items.values():
		if it["stock"] is Dictionary:
			for k in it["stock"]:
				stock_names[k] = true
	var stage_ids := []
	if _p.config["stages"] is Array:
		for s in _p.config["stages"]:
			if s is Dictionary:
				stage_ids.append(s.get("id"))
	for a in _p.actions.values():
		var id: String = a["id"]
		if a.get("kind") is String and not ACTION_KINDS.has(a["kind"]):
			_err("actions.json", id, "kind '%s' must be daily, trouble or flavor" % [a["kind"]])
		if not (a["object"] is String):
			_err("actions.json", id, "object must be a string")
		elif a["object"] != "" and not _p.object_types.has(a["object"]):
			_err("actions.json", id, "object '%s' does not exist" % [a["object"]])
		if a["needs"] is Dictionary:
			for k in a["needs"]:
				if not _p.needs.has(k):
					_err("actions.json", id, "needs key '%s' is not a need" % [k])
		else:
			_err("actions.json", id, "needs must be an object")
		if a["consumes"] is Dictionary:
			for k in a["consumes"]:
				if not stock_names.has(k):
					_err("actions.json", id, "consumes '%s' is not provided by any item's stock" % [k])
		else:
			_err("actions.json", id, "consumes must be an object")
		if a["stages"] is Array:
			for s in a["stages"]:
				if not stage_ids.has(s):
					_err("actions.json", id, "stage '%s' is not defined in pack stages" % [s])
		else:
			_err("actions.json", id, "stages must be an array")
		if not (a["hours"] is Array and (a["hours"].is_empty() or a["hours"].size() == 2)):
			_err("actions.json", id, "hours must be [] or [from, to]")
		if a["work"] is Dictionary and not a["work"].is_empty():
			if not _p.livelihoods.has(a["work"].get("track", "")):
				_err("actions.json", id, "work.track '%s' is not a livelihood" % [a["work"].get("track", "")])
			if a["object"] == "" and (not a["rooms"] is Array or a["rooms"].is_empty()):
				_err("actions.json", id, "a work action needs an object or rooms")
		elif not a["work"] is Dictionary:
			_err("actions.json", id, "work must be an object")
		if a["mess"] is Dictionary and not a["mess"].is_empty():
			if not _p.mess_types.has(a["mess"].get("type", "")):
				_err("actions.json", id, "mess.type '%s' is not a mess type" % [a["mess"].get("type", "")])
		elif not a["mess"] is Dictionary:
			_err("actions.json", id, "mess must be an object")
		if a["cleans"] is String:
			if a["cleans"] != "" and not _p.mess_types.has(a["cleans"]):
				_err("actions.json", id, "cleans '%s' is not a mess type" % [a["cleans"]])
		else:
			_err("actions.json", id, "cleans must be a string")
		if not a["slow"] is bool:
			_err("actions.json", id, "slow must be true or false")
		if not a["rooms"] is Array:
			_err("actions.json", id, "rooms must be an array of room ids")
		else:
			for r in a["rooms"]:
				if not (r is String and _p.rooms.has(r)):
					_err("actions.json", id, "rooms: '%s' is not a room" % [str(r)])
			if not a["rooms"].is_empty() and a["object"] is String and a["object"] != "":
				_err("actions.json", id, "an action with an object may not also list rooms")
		_check_requires(id, a["requires"])
		_check_tends(id, a)
		var cs = a.get("completes_story", "")
		if not cs is String:
			_err("actions.json", id, "completes_story must be a story id")
		elif cs != "":
			var st = _p.stories.get(cs)
			if not st is Dictionary:
				_err("actions.json", id, "completes_story '%s' is not a story" % [cs])
			elif not (st.get("finale") is Dictionary and str(st["finale"].get("kind", "")) in ["offering", "dig"]):
				_err("actions.json", id, "completes_story '%s' needs an offering or dig finale" % [cs])


## `tends`: need id -> amount given to the baby the action is aimed at.
func _check_tends(id: String, a: Dictionary) -> void:
	var t = a.get("tends", {})
	if not t is Dictionary:
		_err("actions.json", id, "tends must be an object")
		return
	if t.is_empty():
		return
	for n in t:
		if not _p.needs.has(n) or not _is_num(t[n]):
			_err("actions.json", id, "tends key '%s' must be a need with a number" % [n])
	if (a["cleans"] is String and a["cleans"] != "") or a["picks"] == true:
		_err("actions.json", id, "an action that tends a baby may not also clean or pick up")
	if a["stages"] is Array and (a["stages"] as Array).has("baby"):
		_err("actions.json", id, "babies cannot tend babies")


func _check_requires(id: String, r) -> void:
	if not r is Dictionary:
		_err("actions.json", id, "requires must be an object")
		return
	for k in r:
		match k:
			"sick":
				if not r[k] is bool:
					_err("actions.json", id, "requires.sick must be true or false")
			"pregnant":
				if not r[k] is bool:
					_err("actions.json", id, "requires.pregnant must be true or false")
			"illness":
				if not _p.illnesses.has(r[k]):
					_err("actions.json", id, "requires.illness '%s' is not an illness" % [r[k]])
			"mood":
				if not MOODS.has(r[k]):
					_err("actions.json", id, "requires.mood must be one of %s" % [", ".join(MOODS)])
			"need_below":
				if r[k] is Dictionary:
					for n in r[k]:
						if not _p.needs.has(n):
							_err("actions.json", id, "requires.need_below key '%s' is not a need" % [n])
				else:
					_err("actions.json", id, "requires.need_below must be an object")
			_:
				_err("actions.json", id, "unknown requires key '%s'" % [k])


func _check_rooms() -> void:
	var has_indoor_built := false
	for r in _p.rooms.values():
		if r.get("built") == true and r["outdoor"] != true:
			has_indoor_built = true
	if not has_indoor_built:
		_err("rooms.json", "*", "needs at least one built indoor room")
	_check_room_positions()
	for id in _p.rooms:
		_check_props(id)
		var r: Dictionary = _p.rooms[id]
		if not r["outside"] is bool:
			_err("rooms.json", id, "outside must be true or false")
		elif r["outside"] and not (r["outdoor"] == true and r.get("built") == true):
			# A place beyond the house (a riverbank, a grove) is open ground that is always there.
			_err("rooms.json", id, "an outside place must be outdoor and built")
		elif r["outside"] and r["props"] is Array and not r["props"].is_empty():
			_err("rooms.json", id, "an outside place has no furniture (props)")
	_check_site()


static func _is_true(v) -> bool:
	return v is bool and v


func _check_objects() -> void:
	for t in _p.object_types.values():
		if not t["fixed"] is bool:
			_err("objects.json", t["id"], "fixed must be true or false")


## A room's fixed furniture: like start_objects, but every piece is a `fixed` type and sits
## in this room, clear of the other props and of the start_objects placed in the room.
func _check_props(room: String) -> void:
	var list = _p.rooms[room]["props"]
	if not list is Array:
		_err("rooms.json", room, "props must be an array")
		return
	var placed: Array = []
	var starts = _p.config["start_objects"]
	if starts is Array:
		for so in starts:
			if so is Dictionary and so.get("room") == room and _p.object_types.has(so.get("type")) \
					and so.get("x") is int and so.get("y") is int:
				placed.append(so)
	for i in list.size():
		var e = list[i]
		var why := ""
		if not (e is Dictionary and e.get("type") is String and e.get("x") is int and e.get("y") is int):
			why = "needs a string 'type' and whole-number 'x' and 'y'"
		elif not _p.object_types.has(e["type"]):
			why = "'%s' is not an object type" % [e["type"]]
		elif not _is_true(_p.object_types[e["type"]].get("fixed")):
			why = "'%s' is not a fixed object type" % [e["type"]]
		else:
			var as_start := {"type": e["type"], "room": room, "x": e["x"], "y": e["y"]}
			why = _place_problem(as_start, placed, false)
			if why == "":
				placed.append(as_start)
		if why != "":
			_err("rooms.json", room, "props #%d: %s" % [i, why])


## Rooms may carry `x`/`y` (whole cells, top-left corner on a shared grid): all rooms or
## none, and positioned rooms must not overlap.
func _check_room_positions() -> void:
	var with := 0
	for r in _p.rooms.values():
		if r.has("x") and r.has("y"):
			with += 1
		elif r.has("x") or r.has("y"):
			with = -1
			break
	if with == 0:
		return
	if with != _p.rooms.size():
		_err("rooms.json", "*", "every room needs a position ('x' and 'y') or none may have one")
		return
	var placed: Array = []
	for id in _p.rooms:
		var r: Dictionary = _p.rooms[id]
		var ok := true
		for f in ["x", "y"]:
			if not (r[f] is int and r[f] >= 0):
				_err("rooms.json", id, "field '%s' must be a whole number of at least 0" % [f])
				ok = false
		if not (ok and r.get("w") is int and r.get("h") is int):
			continue
		var rect := Rect2i(r["x"], r["y"], r["w"], r["h"])
		for other in placed:
			if rect.intersects(other[1]):
				_err("rooms.json", id, "overlaps room '%s'" % [other[0]])
		placed.append([id, rect])


## The optional ground plan in pack.json `site` (read only by the view):
## - `w`, `h`: map size in cells; every room must have a position and lie inside it.
## - `ground`, `compound.ground`: colours ("#rrggbb").
## - `compound`: {x, y, w, h} in cells, inside the map: a wall round it.
## - `doors`, `fences`: lists of {x, y, along, len}: `along` "x" is a stretch of the
##   east-west line y from cell x, "y" a stretch of the north-south line x from cell y.
##   A door opens a wall (or fence) there; a fence is a low wall of its own.
## - `decor`: list of {shape "rect" | "ellipse", x, y, w, h (cells, may be fractional),
##   color, solid (blocks walking), passable (lifts `solid` under it)}.
func _check_site() -> void:
	var site = _p.config.get("site")
	if not site is Dictionary:
		_err("pack.json", "site", "must be an object")
		return
	if (site as Dictionary).is_empty():
		return
	var size := Rect2i()
	if not (site.get("w") is int and site.get("h") is int and site["w"] >= 1 and site["h"] >= 1):
		_err("pack.json", "site", "needs whole-number 'w' and 'h' of at least 1")
		return
	size = Rect2i(0, 0, site["w"], site["h"])
	for id in _p.rooms:
		var r: Dictionary = _p.rooms[id]
		if not (r.get("x") is int and r.get("y") is int and r.get("w") is int and r.get("h") is int):
			_err("pack.json", "site", "room '%s' needs a position" % [id])
		elif not size.encloses(Rect2i(r["x"], r["y"], r["w"], r["h"])):
			_err("pack.json", "site", "room '%s' lies outside the map" % [id])
	for key in ["ground"]:
		if site.has(key) and not _color_ok(site[key]):
			_err("pack.json", "site", "'%s' must be a colour like #c4d696" % [key])
	if site.has("compound"):
		var c = site["compound"]
		if not (c is Dictionary and c.get("x") is int and c.get("y") is int and c.get("w") is int \
				and c.get("h") is int and c["w"] >= 1 and c["h"] >= 1 and size.encloses(Rect2i(c["x"], c["y"], c["w"], c["h"]))):
			_err("pack.json", "site", "compound needs whole-number x, y, w, h inside the map")
		elif c.has("ground") and not _color_ok(c["ground"]):
			_err("pack.json", "site", "compound ground must be a colour like #c4d696")
	for key in ["doors", "fences"]:
		var list = site.get(key, [])
		if not list is Array:
			_err("pack.json", "site", "%s must be an array" % [key])
			continue
		for i in list.size():
			var d = list[i]
			if not (d is Dictionary and _site_int(d, "x", size.size.x) and _site_int(d, "y", size.size.y) \
					and d.get("along") in ["x", "y"] and d.get("len") is int and d["len"] >= 1):
				_err("pack.json", "site", "%s #%d needs whole-number x, y, len and along \"x\" or \"y\" inside the map" % [key, i])
	var decor = site.get("decor", [])
	if not decor is Array:
		_err("pack.json", "site", "decor must be an array")
		return
	for i in decor.size():
		var d = decor[i]
		var ok: bool = d is Dictionary and d.get("shape") in ["rect", "ellipse"] and _color_ok(d.get("color"))
		if ok:
			for f in ["x", "y", "w", "h"]:
				ok = ok and _is_num(d.get(f))
		if ok:
			for f in ["solid", "passable"]:
				ok = ok and (not d.has(f) or d[f] is bool)
		if not ok:
			_err("pack.json", "site", "decor #%d needs shape \"rect\" or \"ellipse\", numbers x, y, w, h and a colour" % [i])


static func _site_int(d: Dictionary, key: String, limit: int) -> bool:
	var v = d.get(key)
	return v is int and v >= 0 and v <= limit


static func _color_ok(v) -> bool:
	return v is String and v.begins_with("#") and Color.html_is_valid(v)


func _check_livelihoods() -> void:
	for l in _p.livelihoods.values():
		var levels = l.get("levels")
		if not levels is Array:
			continue
		if levels.is_empty():
			_err("livelihoods.json", l["id"], "levels is empty")
			continue
		for lv in levels:
			if not lv is Dictionary or LEVEL_FIELDS.any(func(f): return not lv.has(f)):
				_err("livelihoods.json", l["id"], "each level needs %s" % [", ".join(LEVEL_FIELDS)])
				break
			for f in ["daily_income", "progress_to_next"]:
				if lv[f] is int or lv[f] is float:
					_check_int("livelihoods.json", l["id"], f, lv[f], 0)
				else:
					_err("livelihoods.json", l["id"], "level field '%s' must be a number" % [f])
		if levels[-1] is Dictionary and levels[-1].get("progress_to_next", 0) != 0:
			_err("livelihoods.json", l["id"], "last level progress_to_next must be 0")
		_check_affinity(l)


## Optional `affinity`: an array of action ids and/or tags some action carries.
func _check_affinity(l: Dictionary) -> void:
	if not l.has("affinity"):
		return
	if not l["affinity"] is Array:
		_err("livelihoods.json", l["id"], "affinity must be an array of action ids or tags")
		return
	var tags := {}
	for a in _p.actions.values():
		if a.get("tags") is Array:
			for t in a["tags"]:
				tags[t] = true
	for entry in l["affinity"]:
		if not (entry is String and (_p.actions.has(entry) or tags.has(entry))):
			_err("livelihoods.json", l["id"], "affinity: '%s' is neither an action id nor an action tag" % [str(entry)])


func _check_items() -> void:
	for it in _p.items.values():
		if it["cures"] is String and it["cures"] != "" and not _p.illnesses.has(it["cures"]):
			_err("items.json", it["id"], "cures '%s' is not an illness" % [it["cures"]])
		if it["needs"] is Dictionary:
			for k in it["needs"]:
				if not _p.needs.has(k):
					_err("items.json", it["id"], "needs key '%s' is not a need" % [k])
		var wk = it.get("work", {})
		if not (wk is Dictionary and (wk.is_empty() or (_p.livelihoods.has(wk.get("track", "")) and _is_num(wk.get("minutes"))))):
			_err("items.json", it["id"], "work needs a livelihood track and minutes")
		var ch = it.get("childhood", {})
		if not ch is Dictionary or not ch.keys().all(func(a): return _p.actions.has(a) and _is_num(ch[a])):
			_err("items.json", it["id"], "childhood must map action ids to counts")


func _check_illnesses() -> void:
	for i in _p.illnesses.values():
		var id: String = i["id"]
		if i.get("drain") is Dictionary:
			for k in i["drain"]:
				if not _p.needs.has(k):
					_err("illnesses.json", id, "drain key '%s' is not a need" % [k])
		var sa = i.get("symptom_action")
		if not sa is String:
			continue
		if not _p.actions.has(sa):
			_err("illnesses.json", id, "symptom_action '%s' does not exist" % [sa])
		else:
			var req = _p.actions[sa]["requires"]
			if not (req is Dictionary and req.get("illness") == id):
				_err("illnesses.json", id, "symptom_action '%s' must have requires.illness '%s'" % [sa, id])
			# The symptom is started without resolving an object (see IllnessSystem.show_symptom).
			if str(_p.actions[sa]["object"]) != "":
				_err("illnesses.json", id, "symptom_action '%s' must not need an object" % [sa])


func _check_messes() -> void:
	for m in _p.mess_types.values():
		if m.get("penalty") is Dictionary:
			for k in m["penalty"]:
				if not _p.needs.has(k):
					_err("messes.json", m["id"], "penalty key '%s' is not a need" % [k])


func _check_goals() -> void:
	for g in _p.goals.values():
		var w = g.get("when")
		if not w is Dictionary:
			continue
		var t = w.get("type")
		if not GOAL_TYPES.has(t):
			_err("goals.json", g["id"], "when.type '%s' is not a known goal type" % [str(t)])
		elif t == "room_built" and not _p.rooms.has(w.get("room", "")):
			_err("goals.json", g["id"], "when.room '%s' is not a room" % [w.get("room", "")])
		else:
			var param: String = {"money_at_least": "amount", "objects_owned": "count", "level_reached": "level", "collected": "count"}.get(t, "")
			if param != "" and not w.has(param):
				_err("goals.json", g["id"], "when.%s is required for %s" % [param, t])


func _rooms_list(file: String, id: String, field: String, v) -> void:
	if not v is Array:
		_err(file, id, "%s must be an array of room ids" % [field])
		return
	for r in v:
		if not (r is String and _p.rooms.has(r)):
			_err(file, id, "%s: '%s' is not a room" % [field, str(r)])


func _is_num(v) -> bool:
	return v is int or v is float


func _check_collectibles() -> void:
	for c in _p.collectibles.values():
		_rooms_list("collectibles.json", c["id"], "rooms", c["rooms"])


func _check_wishes() -> void:
	var stage_ids := []
	if _p.config["stages"] is Array:
		for s in _p.config["stages"]:
			if s is Dictionary:
				stage_ids.append(s.get("id"))
	for w in _p.wishes.values():
		var id: String = w["id"]
		var kind = w.get("kind")
		if kind is String and not WishSystem.KINDS.has(kind):
			_err("wishes.json", id, "kind '%s' must be one of %s" % [kind, ", ".join(WishSystem.KINDS)])
		if _is_num(w.get("ttl_hours")) and float(w["ttl_hours"]) <= 0.0:
			_err("wishes.json", id, "ttl_hours must be above 0")
		if not _is_num(w["weight"]) or float(w["weight"]) <= 0.0:
			_err("wishes.json", id, "weight must be a number above 0")
		if not (w["likes"] is Array and (w["likes"] as Array).all(func(t): return t is String)):
			_err("wishes.json", id, "likes must be an array of tags")
		if w["stages"] is Array:
			for s in w["stages"]:
				if not stage_ids.has(s):
					_err("wishes.json", id, "stage '%s' is not defined in pack stages" % [s])
		else:
			_err("wishes.json", id, "stages must be an array")
		match kind:
			"item":
				if not _p.items.has(w.get("item", "")):
					_err("wishes.json", id, "item '%s' is not an item" % [str(w.get("item", ""))])
			"object":
				if not _p.object_types.has(w.get("object", "")):
					_err("wishes.json", id, "object '%s' is not an object type" % [str(w.get("object", ""))])
			"room":
				if not _p.rooms.has(w.get("room", "")):
					_err("wishes.json", id, "room '%s' is not a room" % [str(w.get("room", ""))])
			"need":
				if not _p.needs.has(w.get("need", "")):
					_err("wishes.json", id, "need '%s' is not a need" % [str(w.get("need", ""))])
				if not (_is_num(w.get("below")) and _is_num(w.get("above")) and float(w["below"]) <= float(w["above"])):
					_err("wishes.json", id, "a need wish needs numbers below <= above")


func _check_stories() -> void:
	var ids := {}
	for c in _p.collectibles:
		ids[c] = true
	for st in _p.stories.values():
		var id: String = st["id"]
		var u = st.get("unlock")
		if u is Dictionary:
			var t = u.get("type")
			if not StorySystem.UNLOCKS.has(t):
				_err("stories.json", id, "unlock.type '%s' must be one of %s" % [str(t), ", ".join(StorySystem.UNLOCKS)])
			elif t == "room_built" and not _p.rooms.has(u.get("room", "")):
				_err("stories.json", id, "unlock.room '%s' is not a room" % [str(u.get("room", ""))])
			elif t == "generation_at_least" and not (u.get("generation") is int or (u.get("generation") is float and u["generation"] == floorf(u["generation"]))):
				_err("stories.json", id, "unlock.generation must be a whole number")
		if st.has("rooms"):
			_rooms_list("stories.json", id, "rooms", st["rooms"])
		if st.has("hours") and not _hours_ok(st["hours"]):
			_err("stories.json", id, "hours must be [from, to]")
		var frags = st.get("fragments")
		if frags is Array:
			if frags.is_empty():
				_err("stories.json", id, "fragments must not be empty")
			for f in frags:
				if not (f is Dictionary and f.get("id") is String and f.get("name") is String and f.get("text") is String):
					_err("stories.json", id, "every fragment needs a string id, name and text")
					continue
				if ids.has(f["id"]):
					_err("stories.json", id, "fragment id '%s' is used twice (fragments and collectibles share ids)" % [f["id"]])
				ids[f["id"]] = true
				if f.has("rooms"):
					_rooms_list("stories.json", id, "fragment %s rooms" % f["id"], f["rooms"])
				if f.has("hours") and not _hours_ok(f["hours"]):
					_err("stories.json", id, "fragment %s hours must be [from, to]" % f["id"])
		if st.has("mark"):
			_check_mark(id, "mark", st["mark"])
		var fin = st.get("finale")
		if fin is Dictionary:
			_check_finale(id, fin)


func _hours_ok(h) -> bool:
	return h is Array and h.size() == 2 and _is_num(h[0]) and _is_num(h[1])


## A cell inside a room: {room, x, y}.
func _check_mark(id: String, what: String, m) -> void:
	if not (m is Dictionary and _p.rooms.has(m.get("room", ""))):
		_err("stories.json", id, "%s needs a room" % [what])
		return
	var r: Dictionary = _p.rooms[m["room"]]
	for k in ["x", "y"]:
		if not (_is_num(m.get(k)) and float(m[k]) == floorf(float(m[k])) and m[k] >= 0):
			_err("stories.json", id, "%s.%s must be a whole number of at least 0" % [what, k])
			return
	if not (_is_num(r.get("w")) and _is_num(r.get("h")) and m["x"] < r["w"] and m["y"] < r["h"]):
		_err("stories.json", id, "%s lies outside its room" % [what])
	if m.has("hours") and not _hours_ok(m["hours"]):
		_err("stories.json", id, "%s.hours must be [from, to]" % [what])


func _check_finale(id: String, fin: Dictionary) -> void:
	var kind = fin.get("kind")
	if not StorySystem.FINALES.has(kind):
		_err("stories.json", id, "finale.kind '%s' must be one of %s" % [str(kind), ", ".join(StorySystem.FINALES)])
		return
	if fin.has("money") and not (fin["money"] is int or (fin["money"] is float and fin["money"] == floorf(fin["money"]))) or float(fin.get("money", 0)) < 0.0:
		_err("stories.json", id, "finale.money must be a whole number of at least 0")
	match kind:
		"visitor_gift":
			var o = fin.get("object", "")
			if o != "":
				if not _p.object_types.has(o):
					_err("stories.json", id, "finale.object '%s' is not an object type" % [str(o)])
				elif not bool(_p.object_types[o].get("keepsake", false)):
					_err("stories.json", id, "finale.object '%s' must be a keepsake" % [str(o)])
			if fin.has("room") and not _p.rooms.has(fin["room"]):
				_err("stories.json", id, "finale.room '%s' is not a room" % [str(fin["room"])])
		"offering", "dig":
			var act := StorySystem.finale_action(_p, id)
			if act == "":
				_err("stories.json", id, "no action completes_story this story")
			elif kind == "offering" and str(_p.actions[act]["object"]) == "":
				_err("stories.json", id, "the offering action needs an object")
			elif kind == "dig" and str(_p.actions[act]["object"]) != "":
				_err("stories.json", id, "the dig action must not need an object")
			if kind == "dig":
				_check_mark(id, "finale", fin)
	var b = fin.get("blessing", {})
	if not (b is Dictionary and (not b.has("illness_factor") or (_is_num(b["illness_factor"]) and b["illness_factor"] >= 0))):
		_err("stories.json", id, "finale.blessing.illness_factor must be a number of at least 0")


func _check_mood_config() -> void:
	var c := _p.config
	for k in ["wish_chance_per_hour", "wish_miss_penalty", "wish_thanks_min", "mood_low_below",
			"mood_sad_after_hours", "mood_depressed_after_hours", "mood_recover_above",
			"mood_recover_hours", "mood_sad_recover_hours", "mood_depressed_factor",
			"mood_care_hours", "mood_neglect_per_hour", "mood_neglect_floor",
			"story_interval_min", "story_ttl_min"]:
		if not _is_num(c.get(k)) or float(c[k]) < 0.0:
			_err("pack.json", _p.id, "%s must be a number of at least 0" % [k])
	for k in ["story_interval_min", "story_ttl_min"]:
		if _is_num(c.get(k)) and float(c[k]) <= 0.0:
			_err("pack.json", _p.id, "%s must be above 0" % [k])
	var d = c.get("mood_depressed_drain")
	if not d is Dictionary:
		_err("pack.json", _p.id, "mood_depressed_drain must be an object")
	else:
		for k in d:
			if not _p.needs.has(k) or not _is_num(d[k]):
				_err("pack.json", _p.id, "mood_depressed_drain key '%s' must be a need with a number" % [k])


## The optional `births` object (see `BirthSystem`).
func _check_births() -> void:
	var b = _p.config.get("births")
	if not b is Dictionary:
		_err("pack.json", _p.id, "births must be an object")
		return
	if b.is_empty():
		return
	var fa = b.get("fertile_age", BirthSystem.DEFAULT_FERTILE)
	if not (fa is Array and fa.size() == 2 and _is_num(fa[0]) and _is_num(fa[1]) and float(fa[0]) >= 0.0 and float(fa[0]) < float(fa[1])):
		_err("pack.json", _p.id, "births.fertile_age must be [from, to] with 0 <= from < to")
	var c = b.get("chance_per_day", 0.0)
	if not (_is_num(c) and float(c) >= 0.0 and float(c) <= 1.0):
		_err("pack.json", _p.id, "births.chance_per_day must be a number from 0 to 1")
	var py = b.get("pregnancy_years", 0.75)
	if not (_is_num(py) and float(py) > 0.0):
		_err("pack.json", _p.id, "births.pregnancy_years must be a number above 0")
	var beds = b.get("beds", [])
	if not (beds is Array and not beds.is_empty()):
		_err("pack.json", _p.id, "births.beds must list at least one object type")
	else:
		for t in beds:
			if not (t is String and _p.object_types.has(t)):
				_err("pack.json", _p.id, "births.beds: '%s' is not an object type" % [str(t)])
	if not str(b.get("surname_from", "father")) in ["father", "mother"]:
		_err("pack.json", _p.id, "births.surname_from must be father or mother")
	if not b.get("avoid_tag", "") is String:
		_err("pack.json", _p.id, "births.avoid_tag must be a string")
	var d = b.get("drain", {})
	if not d is Dictionary:
		_err("pack.json", _p.id, "births.drain must be an object")
	else:
		for k in d:
			if not _p.needs.has(k) or not _is_num(d[k]):
				_err("pack.json", _p.id, "births.drain key '%s' must be a need with a number" % [k])
	if not b.get("guardian", false) is bool:
		_err("pack.json", _p.id, "births.guardian must be true or false")
	for k in b:
		if not k in ["fertile_age", "chance_per_day", "pregnancy_years", "beds", "surname_from", "avoid_tag", "drain", "guardian"]:
			_err("pack.json", _p.id, "unknown births key '%s'" % [k])
