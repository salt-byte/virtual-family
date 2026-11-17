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
}
## Whole-number fields and their minimum (money, sizes and durations are never fractional or negative).
const MIN_INT := {
	"actions.json": {"duration_min": 1},
	"objects.json": {"price": 0, "w": 1, "h": 1},
	"rooms.json": {"w": 1, "h": 1, "build_cost": 0},
	"items.json": {"price": 0},
	"collectibles.json": {"value": 0},
	"goals.json": {"reward": 0},
}
const LEVEL_FIELDS := ["name", "daily_income", "work_bonus_per_hour", "progress_to_next"]

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
	_check_rooms()
	_check_livelihoods()
	_check_items()
	_check_illnesses()
	_check_messes()
	_check_goals()


func _check_required() -> void:
	# pack.json is not indexed, so check its raw dictionary directly.
	var pj = _p.raw.get("pack.json")
	if pj is Dictionary:
		_check_fields("pack.json", str(pj.get("id", "pack")), pj)
		if str(pj.get("id", "")) == "":
			_err("pack.json", "pack", "missing id")
	for key in Pack.FILES:
		var file: String = Pack.FILES[key]
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
	var pn := str(c.get("praise_need", ""))
	if pn != "" and not _p.needs.has(pn):
		_err("pack.json", _p.id, "praise_need '%s' is not a need" % [pn])
	if c["work_needs_min"] is Dictionary:
		for k in c["work_needs_min"]:
			if not _p.needs.has(k):
				_err("pack.json", _p.id, "work_needs_min key '%s' is not a need" % [k])
	else:
		_err("pack.json", _p.id, "work_needs_min must be an object")


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
			if a["object"] == "":
				_err("actions.json", id, "a work action needs an object")
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
		_check_requires(id, a["requires"])


func _check_requires(id: String, r) -> void:
	if not r is Dictionary:
		_err("actions.json", id, "requires must be an object")
		return
	for k in r:
		match k:
			"sick":
				if not r[k] is bool:
					_err("actions.json", id, "requires.sick must be true or false")
			"illness":
				if not _p.illnesses.has(r[k]):
					_err("actions.json", id, "requires.illness '%s' is not an illness" % [r[k]])
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


func _check_items() -> void:
	for it in _p.items.values():
		if it["cures"] is String and it["cures"] != "" and not _p.illnesses.has(it["cures"]):
			_err("items.json", it["id"], "cures '%s' is not an illness" % [it["cures"]])
		if it["needs"] is Dictionary:
			for k in it["needs"]:
				if not _p.needs.has(k):
					_err("items.json", it["id"], "needs key '%s' is not a need" % [k])


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
