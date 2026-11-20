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
	"dishes.json": {"name": TYPE_STRING, "portions": TYPE_NIL},
	"stories.json": {"title": TYPE_STRING, "unlock": TYPE_DICTIONARY, "fragments": TYPE_ARRAY, "finale": TYPE_DICTIONARY},
	"pets.json": {"name": TYPE_STRING},
	"festivals.json": {"name": TYPE_STRING, "season": TYPE_STRING, "from": TYPE_NIL, "to": TYPE_NIL},
	"letters.json": {"kind": TYPE_STRING, "text": TYPE_STRING},
	"services.json": {"name": TYPE_STRING, "kind": TYPE_STRING, "price": TYPE_NIL},
	"asks.json": {"text": TYPE_STRING, "kind": TYPE_STRING},
}
## Whole-number fields and their minimum (money, sizes and durations are never fractional or negative).
const MIN_INT := {
	"actions.json": {"duration_min": 1},
	"objects.json": {"price": 0, "w": 1, "h": 1, "capacity": 1},
	"rooms.json": {"w": 1, "h": 1, "build_cost": 0},
	"items.json": {"price": 0},
	"collectibles.json": {"value": 0},
	"goals.json": {"reward": 0},
	"dishes.json": {"portions": 1, "max_out": 1},
	"pets.json": {"price": 0},
	"services.json": {"price": 0, "price_step": 0},
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
	_check_asks()
	_check_stories()
	_check_mood_config()
	_check_births()
	_check_dishes()
	_check_seasons()
	_check_pets()
	_check_festivals()
	_check_festival_uses()
	_check_letters()
	_check_market()
	_check_services()


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
	var cr = c.get("clean_reward", {})
	if not cr is Dictionary or (not cr.is_empty() and not (cr.get("amount") is int and cr["amount"] >= 0)):
		_err("pack.json", _p.id, "clean_reward must be {} or {\"amount\": a whole number of at least 0}")


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
		if n.has("warn_below") and not _is_num(n["warn_below"]):
			_err("needs.json", n["id"], "warn_below must be a number")
		var xd = n.get("extra_drain", [])
		if not xd is Array or not (xd as Array).all(func(r): return r is Dictionary and _is_num(r.get("per_hour"))):
			_err("needs.json", n["id"], "extra_drain must be a list of {per_hour, ...} rules")
		else:
			for r in xd:
				for aid in r.get("actions", []):
					if not _p.actions.has(aid):
						_err("needs.json", n["id"], "extra_drain: action '%s' does not exist" % [str(aid)])
		var lo = n.get("low", {})
		if not lo is Dictionary or (not lo.is_empty() and not (_is_num(lo.get("below")) and lo.get("drain", {}) is Dictionary \
				and _is_num(lo.get("illness_factor", 1.0)) and float(lo.get("illness_factor", 1.0)) >= 0.0)):
			_err("needs.json", n["id"], "low must be {} or {below, drain: {need: per hour}, illness_factor >= 0}")
		elif not lo.is_empty():
			for k in lo.get("drain", {}):
				if not _p.needs.has(k):
					_err("needs.json", n["id"], "low.drain key '%s' is not a need" % [k])


func _check_actions() -> void:
	var stock_names := {}
	for it in _p.items.values():
		if it["stock"] is Dictionary:
			for k in it["stock"]:
				stock_names[k] = true
	for a0 in _p.actions.values():
		if a0.get("yields") is Dictionary:
			for k in a0["yields"]:
				stock_names[k] = true
	for d0 in _p.dishes.values():
		if d0.get("scraps") is String and d0["scraps"] != "":
			stock_names[d0["scraps"]] = true
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
			if a["object"] == "" and (not a["rooms"] is Array or a["rooms"].is_empty()) \
					and not (a.get("pet") is Dictionary and not a["pet"].is_empty()):
				_err("actions.json", id, "a work action needs an object, rooms or a pet to look after")
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
		var sf = a.get("self_factor", 1.0)
		if sf is Dictionary:
			for k in sf:
				if not _p.needs.has(k) or not _is_num(sf[k]) or float(sf[k]) < 0.0:
					_err("actions.json", id, "self_factor key '%s' must be a need with a number of at least 0" % [k])
		elif not _is_num(sf) or float(sf) < 0.0:
			_err("actions.json", id, "self_factor must be a number of at least 0 or {need: number}")
		if not a.get("player_only", false) is bool:
			_err("actions.json", id, "player_only must be true or false")
		_check_tends(id, a)
		_check_pet_target("actions.json", id, a.get("pet", {}))
		if a.get("pet") is Dictionary and not a["pet"].is_empty():
			if (a["cleans"] is String and a["cleans"] != "") or a["picks"] == true \
					or (a.get("tends") is Dictionary and not a["tends"].is_empty()) \
					or (a.get("eats") is Array and not a["eats"].is_empty()):
				_err("actions.json", id, "an action that looks after a pet may not also clean, pick up, tend or eat")
			if ((a["object"] is String and a["object"] != "") or (a["rooms"] is Array and not a["rooms"].is_empty())) \
					and not _penned(a["pet"]):
				_err("actions.json", id, "an action that looks after a pet happens where the pet is: no object or rooms (only for livestock, which keep to their pen, or watching)")
		var ca = a.get("counts_as", "")
		if not (ca is String and (ca == "" or _p.livelihoods.has(ca))):
			_err("actions.json", id, "counts_as must be a livelihood")
		_check_food(id, a)
		var cs = a.get("completes_story", "")
		if not cs is String:
			_err("actions.json", id, "completes_story must be a story id")
		elif cs != "":
			var st = _p.stories.get(cs)
			if not st is Dictionary:
				_err("actions.json", id, "completes_story '%s' is not a story" % [cs])
			elif not (st.get("finale") is Dictionary and str(st["finale"].get("kind", "")) in ["offering", "dig"]):
				_err("actions.json", id, "completes_story '%s' needs an offering or dig finale" % [cs])


## `serves` (a dish id), `eats` (dish ids) and `yields` (stock name -> whole number added).
func _check_food(id: String, a: Dictionary) -> void:
	var sv = a.get("serves", "")
	if not sv is String:
		_err("actions.json", id, "serves must be a dish id")
	elif sv != "" and not _p.dishes.has(sv):
		_err("actions.json", id, "serves '%s' is not a dish" % [sv])
	var ea = a.get("eats", [])
	if not ea is Array:
		_err("actions.json", id, "eats must be an array of dish ids")
	else:
		for d in ea:
			if not (d is String and _p.dishes.has(d)):
				_err("actions.json", id, "eats: '%s' is not a dish" % [str(d)])
		if not ea.is_empty():
			if (a["cleans"] is String and a["cleans"] != "") or a["picks"] == true \
					or (a.get("tends") is Dictionary and not a["tends"].is_empty()):
				_err("actions.json", id, "an action that eats a dish may not also clean, pick up or tend")
			if (a["object"] is String and a["object"] != "") or (a["rooms"] is Array and not a["rooms"].is_empty()):
				_err("actions.json", id, "an action that eats a dish happens where the dish is: no object or rooms")
	var y = a.get("yields", {})
	if not y is Dictionary:
		_err("actions.json", id, "yields must be an object")
	else:
		for k in y:
			if not (y[k] is int and y[k] > 0):
				_err("actions.json", id, "yields '%s' must be a whole number above 0" % [k])


## The pack's `seasons` (see `WeatherSystem`), then what actions and messes say about them.
func _check_seasons() -> void:
	var c = _p.config.get("seasons", {})
	var season_ids := []
	var weather_ids := []
	if not c is Dictionary:
		_err("pack.json", _p.id, "seasons must be an object")
		c = {}
	if not c.is_empty():
		var ws = c.get("weather")
		if not (ws is Array and not ws.is_empty()):
			_err("pack.json", _p.id, "seasons.weather must be a non-empty array")
			ws = []
		for w in ws:
			if not (w is Dictionary and w.get("id") is String and w.get("name") is String):
				_err("pack.json", _p.id, "seasons.weather: each needs an id and a name")
				continue
			weather_ids.append(w["id"])
			var wid := "seasons.weather %s" % w["id"]
			for f in ["outdoor", "outside"]:
				if w.has(f) and not (_is_num(w[f]) and float(w[f]) >= 0.0):
					_err("pack.json", _p.id, "%s: %s must be a number of at least 0" % [wid, f])
			if w.has("wet") and not w["wet"] is bool:
				_err("pack.json", _p.id, "%s: wet must be true or false" % wid)
			_check_rates(wid + ": boost", w.get("boost", {}), false)
			_check_rates(wid + ": messes", w.get("messes", {}), true)
			var v = w.get("view", {})
			if not v is Dictionary:
				_err("pack.json", _p.id, "%s: view must be an object" % wid)
			elif not v.is_empty():
				if not str(v.get("kind", "")) in ["", "rain", "snow"]:
					_err("pack.json", _p.id, "%s: view.kind must be rain or snow" % wid)
				if v.has("amount") and not (_is_num(v["amount"]) and float(v["amount"]) >= 0.0 and float(v["amount"]) <= 1.0):
					_err("pack.json", _p.id, "%s: view.amount must be from 0 to 1" % wid)
				for f in ["color", "tint"]:
					if v.has(f) and not _color_ok(v[f]):
						_err("pack.json", _p.id, "%s: view.%s must be a colour like \"#rrggbb\"" % [wid, f])
		var list = c.get("list")
		if not (list is Array and not list.is_empty()):
			_err("pack.json", _p.id, "seasons.list must be a non-empty array")
			list = []
		for se in list:
			if not (se is Dictionary and se.get("id") is String and se.get("name") is String):
				_err("pack.json", _p.id, "seasons.list: each needs an id and a name")
				continue
			season_ids.append(se["id"])
			var sid := "seasons.list %s" % se["id"]
			var wt = se.get("weather")
			if not (wt is Dictionary and not wt.is_empty()):
				_err("pack.json", _p.id, "%s: weather must be a non-empty object of weather id -> weight" % sid)
			else:
				for k in wt:
					if not weather_ids.has(k) or not (_is_num(wt[k]) and float(wt[k]) > 0.0):
						_err("pack.json", _p.id, "%s: weather '%s' must be a weather id with a weight above 0" % [sid, k])
			_check_rates(sid + ": boost", se.get("boost", {}), false)
			_check_rates(sid + ": messes", se.get("messes", {}), true)
			var y = se.get("yields", {})
			if not y is Dictionary:
				_err("pack.json", _p.id, "%s: yields must be an object" % sid)
			else:
				for k in y:
					if not (_is_num(y[k]) and float(y[k]) >= 0.0):
						_err("pack.json", _p.id, "%s: yields '%s' must be a number of at least 0" % [sid, k])
		var cm = c.get("change_min")
		if not (cm is int and cm >= 1):
			_err("pack.json", _p.id, "seasons.change_min must be a whole number of at least 1")
		var ps = c.get("persist", 0.0)
		if not (_is_num(ps) and float(ps) >= 0.0 and float(ps) <= 1.0):
			_err("pack.json", _p.id, "seasons.persist must be from 0 to 1")
		var dh = c.get("dry_hours", 0.0)
		if not (_is_num(dh) and float(dh) >= 0.0):
			_err("pack.json", _p.id, "seasons.dry_hours must be a number of at least 0")
		_check_rates("seasons: wet_messes", c.get("wet_messes", {}), true)
	for a in _p.actions.values():
		var id: String = a["id"]
		for pair in [["seasons", season_ids], ["weather", weather_ids]]:
			var v = a.get(pair[0], [])
			if not v is Array:
				_err("actions.json", id, "%s must be an array" % pair[0])
				continue
			for x in v:
				if not (pair[1] as Array).has(x):
					_err("actions.json", id, "%s: '%s' is not in the pack's seasons" % [pair[0], str(x)])
		if not a.get("not_wet", false) is bool:
			_err("actions.json", id, "not_wet must be true or false")
	for m in _p.mess_types.values():
		var v = m.get("seasons", [])
		if not v is Array:
			_err("messes.json", m["id"], "seasons must be an array")
		else:
			for x in v:
				if not season_ids.has(x):
					_err("messes.json", m["id"], "seasons: '%s' is not in the pack's seasons" % [str(x)])
		if not str(m.get("look", "")) in ["", "patch"]:
			_err("messes.json", m["id"], "look must be \"patch\" or left out")


## `rates`: an object of numbers of at least 0; with `messes` its keys must be mess types.
func _check_rates(where: String, rates, messes: bool) -> void:
	if not rates is Dictionary:
		_err("pack.json", _p.id, "%s must be an object" % where)
		return
	for k in rates:
		if not (_is_num(rates[k]) and float(rates[k]) >= 0.0):
			_err("pack.json", _p.id, "%s: '%s' must be a number of at least 0" % [where, k])
		elif messes and not _p.mess_types.has(k):
			_err("pack.json", _p.id, "%s: '%s' is not a mess type" % [where, k])


func _check_dishes() -> void:
	for d in _p.dishes.values():
		var id: String = d["id"]
		if not d["on"] is Array or d["on"].is_empty():
			_err("dishes.json", id, "on must be a non-empty array of object types")
		else:
			for t in d["on"]:
				if not (t is String and _p.object_types.has(t)):
					_err("dishes.json", id, "on: '%s' is not an object type" % [str(t)])
		if not d["leaves"] is String or (d["leaves"] != "" and not _p.mess_types.has(d["leaves"])):
			_err("dishes.json", id, "leaves '%s' is not a mess type" % [str(d["leaves"])])
		if not _is_num(d["ttl_hours"]) or float(d["ttl_hours"]) < 0.0:
			_err("dishes.json", id, "ttl_hours must be a number of at least 0")
		if d.has("color") and not _color_ok(d["color"]):
			_err("dishes.json", id, "color must be a colour like \"#rrggbb\"")


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


## A `pet` field (of an action or an item): {kinds: [pet kinds] ([]: any), needs: {pet need:
## number}, cures: bool}.
func _check_pet_target(file: String, id: String, t) -> void:
	if not t is Dictionary:
		_err(file, id, "pet must be an object")
		return
	if t.is_empty():
		return
	var ids := _pet_need_ids()
	var kinds = t.get("kinds", [])
	if not kinds is Array:
		_err(file, id, "pet.kinds must be an array of pet kinds")
	else:
		for k in kinds:
			if not (k is String and _p.pets.has(k)):
				_err(file, id, "pet.kinds: '%s' is not a kind in pets.json" % [str(k)])
	var needs = t.get("needs", {})
	if not needs is Dictionary:
		_err(file, id, "pet.needs must be an object")
	else:
		for n in needs:
			if not ids.has(n) or not _is_num(needs[n]):
				_err(file, id, "pet.needs key '%s' must be a pet need with a number" % [n])
	if not t.get("cures", false) is bool:
		_err(file, id, "pet.cures must be true or false")
	var watch = t.get("watch", false)
	if not watch is bool:
		_err(file, id, "pet.watch must be true or false")
	elif watch:
		if file != "actions.json" or not (kinds is Array and not kinds.is_empty()) \
				or not (needs is Dictionary and needs.is_empty()) or bool(t.get("cures", false)):
			_err(file, id, "pet.watch needs kinds and gives no needs and no cure (an action only)")
		return
	if (needs is Dictionary and needs.is_empty()) and not bool(t.get("cures", false)):
		_err(file, id, "pet must give the pet some need or cure it")


## A `pet` target that may name an object or rooms: watching, or only livestock kinds (they
## keep to their pen, so the carer goes to the trough or the pen).
func _penned(t: Dictionary) -> bool:
	if typeof(t.get("watch", false)) == TYPE_BOOL and t.get("watch", false):
		return true
	var kinds = t.get("kinds", [])
	return kinds is Array and not kinds.is_empty() and (kinds as Array).all(func(k):
		return _p.pets.has(k) and _p.pets[k].get("livestock") is Dictionary and not _p.pets[k]["livestock"].is_empty())


## The ids of the pack's `pets.needs` (id -> true).
func _pet_need_ids() -> Dictionary:
	var ids := {}
	var c = _p.config.get("pets", {})
	if c is Dictionary and c.get("needs") is Array:
		for n in c["needs"]:
			if n is Dictionary and n.get("id") is String:
				ids[n["id"]] = true
	return ids


## The `pets` config and pets.json: both or neither; the needs and their roles; each kind's
## numbers, places, own actions, wishes and perks.
func _check_pets() -> void:
	var c = _p.config.get("pets", {})
	if not c is Dictionary:
		_err("pack.json", _p.id, "pets must be an object")
		return
	if _p.pets.is_empty():
		if not c.is_empty():
			_err("pack.json", _p.id, "pets is set but there is no pets.json")
		return
	if c.is_empty():
		_err("pets.json", "*", "pets.json needs the pets settings in pack.json")
		return
	var needs = c.get("needs")
	if not (needs is Array and not needs.is_empty()):
		_err("pack.json", _p.id, "pets.needs must be a non-empty array")
		needs = []
	for n in needs:
		if not (n is Dictionary and n.get("id") is String and n.get("name") is String):
			_err("pack.json", _p.id, "pets.needs: each needs an id and a name")
			continue
		if n.has("start") and not (_is_num(n["start"]) and float(n["start"]) >= 0.0 and float(n["start"]) <= 100.0):
			_err("pack.json", _p.id, "pets.needs %s: start must be from 0 to 100" % n["id"])
		var labels = n.get("labels", [])
		if not labels is Array or not (labels as Array).all(func(l): return l is Dictionary and _is_num(l.get("below")) and l.get("text") is String):
			_err("pack.json", _p.id, "pets.needs %s: labels need a number 'below' and a 'text'" % n["id"])
		elif not labels.is_empty() and float(labels[-1]["below"]) < 101.0:
			_err("pack.json", _p.id, "pets.needs %s: the last label 'below' must be at least 101" % n["id"])
	var ids := _pet_need_ids()
	for r in ["food_need", "love_need", "clean_need", "health_need"]:
		var v = c.get(r, "")
		if not (v is String and (v == "" or ids.has(v))):
			_err("pack.json", _p.id, "pets.%s must be one of pets.needs" % r)
	for f in ["max", "content_above", "run_below", "run_after_hours", "come_back_after_hours", "gone_after_hours",
			"come_back_at", "stray_ttl_hours", "illness_chance_per_day", "dirty_below", "dirty_illness_factor",
			"sick_drain_per_hour", "heal_per_hour", "wish_miss", "cure_gain", "age_rate", "care_below"]:
		if c.has(f) and not (_is_num(c[f]) and float(c[f]) >= 0.0):
			_err("pack.json", _p.id, "pets.%s must be a number of at least 0" % f)
	for f in ["stray_chance_per_hour", "come_back_chance_per_hour", "wish_chance_per_hour"]:
		if c.has(f) and not (_is_num(c[f]) and float(c[f]) >= 0.0 and float(c[f]) <= 1.0):
			_err("pack.json", _p.id, "pets.%s must be from 0 to 1" % f)
	for f in ["action_speed", "offline_action_speed", "effect_speed"]:
		if c.has(f) and not (_is_num(c[f]) and float(c[f]) >= 1.0):
			_err("pack.json", _p.id, "pets.%s must be a number of at least 1" % f)
	_check_livestock_config(c)
	for g in ["cheer", "grief"]:
		var e = c.get(g, {})
		if not e is Dictionary:
			_err("pack.json", _p.id, "pets.%s must be an object" % g)
		elif not e.is_empty() and not _p.needs.has(str(e.get("need", ""))):
			_err("pack.json", _p.id, "pets.%s.need must be a need" % g)
	var seen := {}
	for k in _p.pets.values():
		var id: String = k["id"]
		for f in ["lifespan", "age", "stray_age"]:
			var r = k.get(f, [1, 2])
			if not (r is Array and r.size() == 2 and _is_num(r[0]) and _is_num(r[1]) and float(r[0]) >= 0.0 and float(r[0]) <= float(r[1])):
				_err("pets.json", id, "%s must be [from, to] in years" % f)
		if not (k["names"] is Array and (k["names"] as Array).all(func(s): return s is String)):
			_err("pets.json", id, "names must be an array of names")
		if not k["drains"] is Dictionary or not (k["drains"] as Dictionary).keys().all(func(n): return ids.has(n) and _is_num(k["drains"][n])):
			_err("pets.json", id, "drains must map pet needs to numbers per hour")
		if not (k["home"] is Array and (k["home"] as Array).all(func(r): return r is String and _p.rooms.has(r))):
			_err("pets.json", id, "home must be an array of rooms")
		var perch = k["perch"]
		if not (perch is String and (perch == "" or _p.object_types.has(perch))):
			_err("pets.json", id, "perch '%s' is not an object type" % [str(perch)])
		if not (k["idle"] is String and k["idle"] in ["", "wag", "flick", "bob", "peck", "root"]):
			_err("pets.json", id, "idle must be one of wag, flick, bob, peck, root")
		_check_livestock(id, k)
		if not _is_num(k["size"]) or float(k["size"]) <= 0.0:
			_err("pets.json", id, "size must be a number above 0")
		if k.has("color") and not _color_ok(k["color"]):
			_err("pets.json", id, "color must be a colour like \"#rrggbb\"")
		var perks = k["perks"]
		if not perks is Dictionary:
			_err("pets.json", id, "perks must be an object")
		else:
			if perks.has("guard") and not (_is_num(perks["guard"]) and float(perks["guard"]) >= 1.0):
				_err("pets.json", id, "perks.guard must be a number of at least 1")
			if perks.has("save") and not (perks["save"] is Dictionary and (perks["save"] as Dictionary).values().all(func(v): return _is_num(v) and float(v) >= 0.0 and float(v) <= 1.0)):
				_err("pets.json", id, "perks.save must map stock names to shares from 0 to 1")
		if not k["actions"] is Array or (k["actions"] as Array).is_empty():
			_err("pets.json", id, "actions must be a non-empty array")
		else:
			for a in k["actions"]:
				_check_pet_action(id, k, a, ids, seen)
		var acts := {}
		if k["actions"] is Array:
			for a in k["actions"]:
				if a is Dictionary:
					acts[str(a.get("id", ""))] = true
		if not k["wishes"] is Array:
			_err("pets.json", id, "wishes must be an array")
			continue
		for w in k["wishes"]:
			if not (w is Dictionary and w.get("id") is String and w.get("text") is String):
				_err("pets.json", id, "wishes: each needs an id and a text")
				continue
			var wid := "wish %s" % w["id"]
			var item := str(w.get("item", ""))
			var wa = w.get("actions", [])
			if item != "" and not _p.items.has(item):
				_err("pets.json", id, "%s: item '%s' is not an item" % [wid, item])
			if not wa is Array or not (wa as Array).all(func(x): return acts.has(x) or (_p.actions.has(x) and _p.actions[x].get("pet") is Dictionary and not _p.actions[x]["pet"].is_empty())):
				_err("pets.json", id, "%s: actions must be this kind's actions or actions that look after pets" % wid)
			elif item == "" and wa.is_empty():
				_err("pets.json", id, "%s: needs an item or actions that grant it" % wid)
			for f in ["ttl_hours", "joy"]:
				if w.has(f) and not (_is_num(w[f]) and float(w[f]) >= 0.0):
					_err("pets.json", id, "%s: %s must be a number of at least 0" % [wid, f])
			var below = w.get("below", {})
			if not (below is Dictionary and (below as Dictionary).keys().all(func(n): return ids.has(n) and _is_num(below[n]))):
				_err("pets.json", id, "%s: below must map pet needs to numbers" % wid)


func _check_pet_action(kind: String, k: Dictionary, a, ids: Dictionary, seen: Dictionary) -> void:
	if not (a is Dictionary and a.get("id") is String and a.get("label") is String):
		_err("pets.json", kind, "actions: each needs an id and a label")
		return
	var aid := "%s %s" % [kind, a["id"]]
	if seen.has(a["id"]) or _p.actions.has(a["id"]):
		_err("pets.json", aid, "action id is used twice")
	seen[a["id"]] = true
	if not (a["duration_min"] is int and a["duration_min"] >= 1):
		_err("pets.json", aid, "duration_min must be a whole number of at least 1")
	if not (_is_num(a["base"]) and float(a["base"]) >= 0.0):
		_err("pets.json", aid, "base must be a number of at least 0")
	if not (a["object"] is String and (a["object"] == "" or _p.object_types.has(a["object"]))):
		_err("pets.json", aid, "object '%s' is not an object type" % [str(a["object"])])
	if not (a["rooms"] is Array and (a["rooms"] as Array).all(func(r): return r is String and _p.rooms.has(r))):
		_err("pets.json", aid, "rooms must be an array of rooms")
	elif not a["rooms"].is_empty() and a["object"] is String and a["object"] != "":
		_err("pets.json", aid, "an action with an object may not also list rooms")
	if not (a["hours"] is Array and (a["hours"].is_empty() or a["hours"].size() == 2)):
		_err("pets.json", aid, "hours must be [] or [from, to]")
	if not a["weather"] is Array:
		_err("pets.json", aid, "weather must be an array")
	for f in ["wet", "sick"]:
		if not a[f] is bool:
			_err("pets.json", aid, "%s must be true or false" % f)
	var st = _p.config["stages"]
	var who_ok: bool = a["follows"] is String and (a["follows"] in ["", "anyone"] or (a["follows"] == "who" and a["on"] is String and a["on"] != ""))
	if not (who_ok or (a["follows"] is String and st is Array and (st as Array).any(func(s): return s is Dictionary and s.get("id") == a["follows"]))):
		_err("pets.json", aid, "follows must be a stage id, \"anyone\" or (with on) \"who\"")
	if not (a["on"] is String and a["on"] in ["", "back", "dragged"]):
		_err("pets.json", aid, "on must be \"back\" or \"dragged\"")
	if not (_is_num(a["chance"]) and float(a["chance"]) >= 0.0 and float(a["chance"]) <= 1.0):
		_err("pets.json", aid, "chance must be from 0 to 1")
	if not (a["trot"] is int and a["trot"] >= 0):
		_err("pets.json", aid, "trot must be a whole number of at least 0")
	if not (a["pace"] is String and a["pace"] in ["", "trot", "slink", "dash", "leap", "hop", "flap", "peck", "root"]):
		_err("pets.json", aid, "pace must be one of trot, slink, dash, leap, hop, flap, peck, root")
	if not a["rest"] is bool:
		_err("pets.json", aid, "rest must be true or false")
	if not a["brood"] is bool:
		_err("pets.json", aid, "brood must be true or false")
	elif a["brood"] and not (k["livestock"] is Dictionary and k["livestock"].get("young") is Dictionary):
		_err("pets.json", aid, "brood is for a livestock kind that has young")
	if not (a["scraps"] is String and (a["scraps"] == "" or _p.mess_types.has(a["scraps"]))):
		_err("pets.json", aid, "scraps must be a mess type")
	if not (a["needs"] is Dictionary and (a["needs"] as Dictionary).keys().all(func(n): return ids.has(n) and _is_num(a["needs"][n]))):
		_err("pets.json", aid, "needs must map pet needs to numbers")
	if not (_is_num(a["every_hours"]) and float(a["every_hours"]) >= 0.0):
		_err("pets.json", aid, "every_hours must be a number of at least 0")
	if not (a["above"] is Dictionary and (a["above"] as Dictionary).keys().all(func(n): return ids.has(n) and _is_num(a["above"][n]))):
		_err("pets.json", aid, "above must map pet needs to numbers")
	if not a["mess"] is Dictionary or (not a["mess"].is_empty() and not _p.mess_types.has(str(a["mess"].get("type", "")))):
		_err("pets.json", aid, "mess.type must be a mess type")


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
		_check_pet_target("items.json", it["id"], it.get("pet", {}))


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
		if m.has("color") and not _color_ok(m["color"]):
			_err("messes.json", m["id"], "color must be a colour like \"#rrggbb\"")
		var sc = m.get("scrap", {})
		if not sc is Dictionary or (not sc.is_empty() and not (_is_num(sc.get("value")) and float(sc["value"]) >= 0.0 \
				and _is_num(sc.get("chance", 1.0)))):
			_err("messes.json", m["id"], "scrap must be {} or {value: whole number, chance}")


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
		if not c["keepsake"] is bool:
			_err("collectibles.json", c["id"], "keepsake must be true or false")
	if not _p.config.get("collect_keep") is bool:
		_err("pack.json", _p.id, "collect_keep must be true or false")


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
			"pet":
				if not _p.pets.has(w.get("pet", "")):
					_err("wishes.json", id, "pet '%s' is not a kind in pets.json" % [str(w.get("pet", ""))])
			"need":
				if not _p.needs.has(w.get("need", "")):
					_err("wishes.json", id, "need '%s' is not a need" % [str(w.get("need", ""))])
				if not (_is_num(w.get("below")) and _is_num(w.get("above")) and float(w["below"]) <= float(w["above"])):
					_err("wishes.json", id, "a need wish needs numbers below <= above")


## asks.json (see `AskSystem`) and the pack's ask numbers.
func _check_asks() -> void:
	var c := _p.config
	for k in ["ask_check_s", "ask_wait_s", "ask_self_s"]:
		if not (c.get(k) is int and int(c[k]) >= 1):
			_err("pack.json", _p.id, "%s must be a whole number of seconds of at least 1" % [k])
	for k in ["ask_gap_s", "ask_again_s"]:
		if not (c.get(k) is int and int(c[k]) >= 0):
			_err("pack.json", _p.id, "%s must be a whole number of seconds of at least 0" % [k])
	for k in ["ask_chance_per_hour", "ask_ignored", "ask_self_factor"]:
		if not _is_num(c.get(k)) or float(c[k]) < 0.0:
			_err("pack.json", _p.id, "%s must be a number of at least 0" % [k])
	var stage_ids := []
	if c["stages"] is Array:
		for s in c["stages"]:
			if s is Dictionary:
				stage_ids.append(s.get("id"))
	for e in _p.asks.values():
		var id: String = e["id"]
		var kind = e.get("kind")
		if kind is String and not AskSystem.KINDS.has(kind):
			_err("asks.json", id, "kind '%s' must be one of %s" % [kind, ", ".join(AskSystem.KINDS)])
		if not _is_num(e["weight"]) or float(e["weight"]) <= 0.0:
			_err("asks.json", id, "weight must be a number above 0")
		for f in ["joy", "ignored"]:
			if e.has(f) and not (_is_num(e[f]) and float(e[f]) >= 0.0):
				_err("asks.json", id, "%s must be a number of at least 0" % [f])
		if e.has("wait_s") and not (_is_num(e["wait_s"]) and float(e["wait_s"]) >= 1.0):
			_err("asks.json", id, "wait_s must be a number of seconds of at least 1")
		if not e["icon"] is String:
			_err("asks.json", id, "icon must be a string")
		if not (e["likes"] is Array and (e["likes"] as Array).all(func(t): return t is String)):
			_err("asks.json", id, "likes must be an array of tags")
		if e["stages"] is Array:
			for s in e["stages"]:
				if not stage_ids.has(s):
					_err("asks.json", id, "stage '%s' is not defined in pack stages" % [s])
		else:
			_err("asks.json", id, "stages must be an array")
		match kind:
			"need":
				if not _p.needs.has(e.get("need", "")):
					_err("asks.json", id, "need '%s' is not a need" % [str(e.get("need", ""))])
				if not _is_num(e.get("below")) or (e.has("above") and not (_is_num(e["above"]) and float(e["above"]) >= float(e["below"]))):
					_err("asks.json", id, "a need ask needs a number below (and above, if given, at least below)")
			"item":
				if not (e["items"] is Array and not (e["items"] as Array).is_empty() and (e["items"] as Array).all(func(i): return _p.items.has(i))):
					_err("asks.json", id, "an item ask needs items: a non-empty array of item ids")
			"do":
				if not (e["actions"] is Array and not (e["actions"] as Array).is_empty() and (e["actions"] as Array).all(func(a): return _p.actions.has(a))):
					_err("asks.json", id, "a do ask needs actions: a non-empty array of action ids")


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
			elif t == "random" and not (_is_num(u.get("chance_per_day")) and float(u["chance_per_day"]) > 0.0):
				_err("stories.json", id, "unlock.chance_per_day must be a number above 0")
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
		if st.has("midpoint") and not st["midpoint"] is String:
			_err("stories.json", id, "midpoint must be a text")
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
		"scene":
			var k = fin.get("keepsake", "")
			if k != "" and not (_p.collectibles.has(k) and _p.collectibles[k].get("keepsake", false) is bool and _p.collectibles[k]["keepsake"]):
				_err("stories.json", id, "finale.keepsake '%s' must be a collectible marked keepsake" % [str(k)])
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
	for k in ["wish_check_min", "need_wish_check_min"]:
		var v = c.get(k)
		if not (_is_num(v) and float(v) == floorf(float(v)) and int(v) >= 1 and (60 % int(v) == 0 or int(v) % 60 == 0)):
			_err("pack.json", _p.id, "%s must be a whole number of minutes that divides 60, or whole hours" % [k])
	var fe = c.get("feelings")
	if not fe is Array or not (fe as Array).all(func(r): return r is Dictionary and r.get("text") is String):
		_err("pack.json", _p.id, "feelings must be a list of rules, each with a text")
	var sh = c.get("share")
	if not sh is Dictionary or (not sh.is_empty() and not (_is_num(sh.get("every")) and float(sh["every"]) >= 1.0)):
		_err("pack.json", _p.id, "share must be {} or {every: whole coins >= 1, gap_min, level, money_text, level_text}")
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


## festivals.json: each at a stretch of a season of the pack (0 <= from < to <= 1, no two
## overlapping), with a boost of numbers, a wish chance between 0 and 1 and text strings.
func _check_festivals() -> void:
	if _p.festivals.is_empty():
		return
	var c = _p.config.get("seasons", {})
	var season_ids := []
	if c is Dictionary and c.get("list") is Array:
		for s in c["list"]:
			if s is Dictionary:
				season_ids.append(str(s.get("id", "")))
	if season_ids.is_empty():
		_err("festivals.json", "*", "festivals need seasons in pack.json")
	var spans := {}  # season -> [[from, to, id], ...]
	for f in _p.festivals.values():
		var id: String = f["id"]
		if not (f.get("season") is String and season_ids.has(f["season"])):
			if not season_ids.is_empty():
				_err("festivals.json", id, "season '%s' is not a season" % [str(f.get("season", ""))])
			continue
		if not (_is_num(f.get("from")) and _is_num(f.get("to")) and float(f["from"]) >= 0.0 \
				and float(f["from"]) < float(f["to"]) and float(f["to"]) <= 1.0):
			_err("festivals.json", id, "needs 0 <= from < to <= 1")
			continue
		for other in spans.get(f["season"], []):
			if float(f["from"]) < float(other[1]) and float(other[0]) < float(f["to"]):
				_err("festivals.json", id, "overlaps %s" % [other[2]])
		if not spans.has(f["season"]):
			spans[f["season"]] = []
		spans[f["season"]].append([f["from"], f["to"], id])
		_check_rates("festivals.json %s: boost" % id, f["boost"], false)
		if not (_is_num(f["wish_chance"]) and float(f["wish_chance"]) >= 0.0 and float(f["wish_chance"]) <= 1.0):
			_err("festivals.json", id, "wish_chance must be a number from 0 to 1")
		for k in ["banner", "start_text", "end_text"]:
			if not f[k] is String:
				_err("festivals.json", id, "%s must be a string" % k)


## `festivals` of actions and items name festivals; an action's `outing` and `mourns`, and a
## wish's `festival` and (kind "do") `actions`, are well-formed.
func _check_festival_uses() -> void:
	for a in _p.actions.values():
		var id: String = a["id"]
		_festival_list("actions.json", id, a.get("festivals", []))
		if not a.get("mourns", false) is bool:
			_err("actions.json", id, "mourns must be true or false")
		var o = a.get("outing", {})
		if not o is Dictionary:
			_err("actions.json", id, "outing must be an object")
		elif not o.is_empty():
			if a["object"] is String and a["object"] != "" or not (a["rooms"] is Array and not a["rooms"].is_empty()):
				_err("actions.json", id, "an outing leaves from rooms (no object)")
			if not (a["work"] is Dictionary and a["work"].is_empty()):
				_err("actions.json", id, "an outing is not work")
			var rs = o.get("returns", [])
			if not (rs is Array and not rs.is_empty()):
				_err("actions.json", id, "outing.returns must be a non-empty array")
				rs = []
			for r in rs:
				if not (r is Dictionary and r.get("text") is String and r["text"] != ""):
					_err("actions.json", id, "outing.returns: each needs a text")
					continue
				var item := str(r.get("item", ""))
				if item != "" and not (_p.items.has(item) and (_p.items[item]["stock"] as Dictionary).is_empty()):
					_err("actions.json", id, "outing.returns: '%s' is not an item without stock" % item)
	for it in _p.items.values():
		_festival_list("items.json", it["id"], it.get("festivals", []))
	for w in _p.wishes.values():
		var id: String = w["id"]
		var fest = w.get("festival", "")
		if not (fest is String and (fest == "" or _p.festivals.has(fest))):
			_err("wishes.json", id, "festival '%s' is not a festival" % [str(fest)])
		if str(w.get("kind", "")) == "do":
			var acts = w.get("actions", [])
			if not (acts is Array and not acts.is_empty() and acts.all(func(x): return x is String and _p.actions.has(x))):
				_err("wishes.json", id, "a do wish needs actions: a non-empty array of action ids")


func _festival_list(file: String, id: String, v) -> void:
	if not (v is Array and v.all(func(x): return x is String and _p.festivals.has(x))):
		_err(file, id, "festivals must be an array of festival ids")


## The `letters` settings and letters.json: both or neither; the hands; each template's kind,
## hands, facts, choices and (for a story letter) the story and the moment it is for.
func _check_letters() -> void:
	var c = _p.config.get("letters", {})
	if not c is Dictionary:
		_err("pack.json", _p.id, "letters must be an object")
		return
	if _p.letters.is_empty():
		if not (c as Dictionary).is_empty():
			_err("pack.json", _p.id, "letters is set but there is no letters.json")
		return
	if (c as Dictionary).is_empty():
		_err("letters.json", "*", "letters.json needs the letters settings in pack.json")
		return
	for f in ["min_gap_min", "unread_max", "keep", "offline_max", "kin_chance_per_day"]:
		if c.has(f) and not ((c[f] is int or c[f] is float) and c[f] >= 0):
			_err("pack.json", _p.id, "letters.%s must be a number of at least 0" % f)
	var chance = c.get("chance", {})
	if not chance is Dictionary:
		_err("pack.json", _p.id, "letters.chance must be an object")
	else:
		for k in chance:
			if not LetterSystem.MINOR.has(k):
				_err("pack.json", _p.id, "letters.chance: '%s' is not a minor kind" % [str(k)])
			elif not ((chance[k] is int or chance[k] is float) and chance[k] >= 0 and chance[k] <= 1):
				_err("pack.json", _p.id, "letters.chance.%s must be from 0 to 1" % [str(k)])
	var hands = c.get("hands", [])
	var hand_ids := {}
	if not (hands is Array and not (hands as Array).is_empty()):
		_err("pack.json", _p.id, "letters.hands must be a non-empty array")
		hands = []
	for h in hands:
		if not (h is Dictionary and str(h.get("id", "")) != "" and h.get("sign", "") is String):
			_err("pack.json", _p.id, "letters.hands: each needs an id and a sign")
			continue
		hand_ids[str(h["id"])] = true
		for f in ["stages", "tracks", "likes"]:
			if not h.get(f, []) is Array:
				_err("pack.json", _p.id, "letters.hands %s: %s must be an array" % [h["id"], f])
		for t in h.get("tracks", []):
			if not _p.livelihoods.has(str(t)):
				_err("pack.json", _p.id, "letters.hands %s: '%s' is not a livelihood" % [h["id"], str(t)])
	for id in _p.letters:
		var t: Dictionary = _p.letters[id]
		var kind := str(t["kind"])
		if not LetterSystem.KINDS.has(kind):
			_err("letters.json", id, "kind '%s' is not a letter kind" % kind)
		if not (t["hand"] is Array and (t["hand"] as Array).all(func(h): return hand_ids.has(str(h)))):
			_err("letters.json", id, "hand must be an array of the settings' hands")
		if not t["if"] is Dictionary:
			_err("letters.json", id, "if must be an object")
		if not (t["weight"] is int or t["weight"] is float) or float(t["weight"]) < 0.0:
			_err("letters.json", id, "weight must be a number of at least 0")
		if kind in ["proposal", "kin", "story"] and str(t["from"]) == "":
			_err("letters.json", id, "a letter from outside needs a 'from'")
		if kind == "story":
			if not _p.stories.has(str(t["story"])):
				_err("letters.json", id, "story '%s' is not in stories.json" % [str(t["story"])])
			if not str(t["on"]) in LetterSystem.STORY_ON:
				_err("letters.json", id, "on must be one of %s" % [str(LetterSystem.STORY_ON)])
		if not t["choices"] is Array:
			_err("letters.json", id, "choices must be an array")
			continue
		for ch in t["choices"]:
			if not (ch is Dictionary and ch.get("label") is String and ch.get("effect") is Dictionary):
				_err("letters.json", id, "choices: each needs a label and an effect")
			elif not str(ch["effect"].get("type", "")) in LetterSystem.EFFECTS:
				_err("letters.json", id, "effect type '%s' is unknown" % [str(ch["effect"].get("type", ""))])


func _num_at_least(v, minimum: float) -> bool:
	return (v is int or v is float) and float(v) >= minimum


## pack.json `market` (see `MarketSystem`) and every entry's `market` section.
func _check_market() -> void:
	var m = _p.config.get("market", {})
	if not m is Dictionary:
		_err("pack.json", _p.id, "market must be an object")
		return
	var ids := {}
	if not (m as Dictionary).is_empty():
		var secs = m.get("sections")
		if not (secs is Array and not (secs as Array).is_empty()):
			_err("pack.json", _p.id, "market.sections must be a non-empty list")
			return
		for s in secs:
			if not (s is Dictionary and s.get("id") is String and s.get("name") is String and str(s["id"]) != ""):
				_err("pack.json", _p.id, "market.sections: each needs an id and a name")
			elif ids.has(s["id"]):
				_err("pack.json", _p.id, "market.sections: duplicate id '%s'" % [s["id"]])
			else:
				ids[s["id"]] = true
		var d = m.get("default", {})
		if not d is Dictionary:
			_err("pack.json", _p.id, "market.default must be an object")
		else:
			for k in d:
				if not k in MarketSystem.KINDS:
					_err("pack.json", _p.id, "market.default: '%s' is not a kind of goods" % [k])
				elif not ids.has(d[k]):
					_err("pack.json", _p.id, "market.default.%s: '%s' is not a section" % [k, str(d[k])])
		if m.has("secondhand"):
			_check_secondhand(m["secondhand"], ids)
	for pair in [["items.json", _p.items], ["objects.json", _p.object_types], ["rooms.json", _p.rooms],
			["pets.json", _p.pets], ["services.json", _p.services]]:
		for e in (pair[1] as Dictionary).values():
			var sec = e.get("market", "")
			if not sec is String:
				_err(pair[0], e["id"], "market must be a section id")
			elif sec != "" and not ids.has(sec):
				_err(pair[0], e["id"], "market '%s' is not a section" % [sec])


func _check_secondhand(sh, ids: Dictionary) -> void:
	if not sh is Dictionary:
		_err("pack.json", _p.id, "market.secondhand must be an object")
		return
	if not ids.has(sh.get("section")):
		_err("pack.json", _p.id, "market.secondhand.section must be a section")
	if not (_num_at_least(sh.get("refresh_hours"), 0.0) and float(sh["refresh_hours"]) > 0.0):
		_err("pack.json", _p.id, "market.secondhand.refresh_hours must be above 0")
	if not (sh.get("count") is int and sh["count"] >= 1):
		_err("pack.json", _p.id, "market.secondhand.count must be a whole number of at least 1")
	var pf = sh.get("price_factor")
	var back := float(_p.cfg("sell_back_ratio")) if _is_num(_p.cfg("sell_back_ratio")) else 0.0
	if not (pf is Array and pf.size() == 2 and _is_num(pf[0]) and _is_num(pf[1]) \
			and float(pf[0]) > back and float(pf[0]) <= float(pf[1]) and float(pf[1]) <= 1.0):
		_err("pack.json", _p.id, "market.secondhand.price_factor must be [lo, hi] with sell_back_ratio < lo <= hi <= 1")
	var from = sh.get("from")
	if not (from is Array and (from as Array).all(func(s): return ids.has(s))):
		_err("pack.json", _p.id, "market.secondhand.from must list sections")


## services.json (see `ServiceSystem`).
func _check_services() -> void:
	for sv in _p.services.values():
		var id: String = sv["id"]
		var kind := str(sv.get("kind", ""))
		if not kind in ServiceSystem.KINDS:
			_err("services.json", id, "kind '%s' is unknown" % [kind])
			continue
		var req = sv.get("requires", {})
		if not req is Dictionary or req.keys().any(func(k): return k != "object") \
				or (req.has("object") and not _p.object_types.has(req["object"])):
			_err("services.json", id, "requires must be {object: an object type}")
		match kind:
			"adopt":
				var age = sv.get("age", [0, 0])
				if not (age is Array and age.size() == 2 and _is_num(age[0]) and _is_num(age[1]) and age[0] <= age[1]):
					_err("services.json", id, "age must be [from, to]")
				if sv.has("max_people") and not (sv["max_people"] is int and sv["max_people"] >= 0):
					_err("services.json", id, "max_people must be a whole number of at least 0")
			"speed":
				if not (_num_at_least(sv.get("factor"), 1.0) and _num_at_least(sv.get("hours"), 0.0) and float(sv["hours"]) > 0.0):
					_err("services.json", id, "speed needs factor >= 1 and hours > 0")
				elif sv.has("max_hours") and not _num_at_least(sv["max_hours"], float(sv["hours"])):
					_err("services.json", id, "max_hours must be at least hours")
			"yield":
				var b = sv.get("bonus")
				if not (b is Dictionary and not b.is_empty() and b.values().all(func(v): return v is int and v >= 1)):
					_err("services.json", id, "bonus must map stocks to whole numbers of at least 1")
			"drops":
				if not _num_at_least(sv.get("factor"), 1.0):
					_err("services.json", id, "factor must be a number of at least 1")
			"lottery":
				var prizes = sv.get("prizes")
				var total := 0.0
				if not prizes is Array or prizes.is_empty():
					_err("services.json", id, "prizes must be a non-empty list")
				else:
					for pr in prizes:
						if not (pr is Dictionary and _num_at_least(pr.get("chance"), 0.0) and pr.get("amount") is int and pr["amount"] >= 0):
							_err("services.json", id, "prizes: each needs a chance and a whole amount")
						else:
							total += float(pr["chance"])
					if total > 1.0:
						_err("services.json", id, "prizes: the chances add up to more than 1")
				if not _num_at_least(sv.get("draw_hours"), 0.0):
					_err("services.json", id, "draw_hours must be a number of at least 0")
				if sv.has("max_tickets") and not (sv["max_tickets"] is int and sv["max_tickets"] >= 1):
					_err("services.json", id, "max_tickets must be a whole number of at least 1")
			"helper":
				if not (_num_at_least(sv.get("days"), 0.0) and float(sv["days"]) > 0.0):
					_err("services.json", id, "days must be above 0")
				elif sv.has("max_days") and not _num_at_least(sv["max_days"], float(sv["days"])):
					_err("services.json", id, "max_days must be at least days")
				var hours = sv.get("hours", [])
				if not (hours is Array and hours.all(func(h): return h is int and h >= 0 and h < 24)):
					_err("services.json", id, "hours must list whole hours 0-23")
				var cooks = sv.get("cooks", "")
				if not (cooks is String and (cooks == "" or _p.dishes.has(cooks))):
					_err("services.json", id, "cooks must be a dish id")
				var cons = sv.get("consumes", {})
				if not (cons is Dictionary and cons.values().all(func(v): return v is int and v >= 0)):
					_err("services.json", id, "consumes must map stocks to whole numbers")


## A kind's `livestock` block (see `LivestockSystem`).
func _check_livestock(id: String, k: Dictionary) -> void:
	var b = k.get("livestock", {})
	if not b is Dictionary:
		_err("pets.json", id, "livestock must be an object")
		return
	if b.is_empty():
		return
	var pen = b.get("pen", "")
	if not (pen is String and _p.rooms.has(pen)):
		_err("pets.json", id, "livestock.pen must be a room")
	if not _is_num(b.get("pen_max", 1)) or float(b.get("pen_max", 1)) < 1.0:
		_err("pets.json", id, "livestock.pen_max must be a number of at least 1")
	if bool(k.get("stray", false)) or str(k.get("perch", "")) != "":
		_err("pets.json", id, "livestock never strays in and has no perch")
	for f in ["weight", "grows_into", "sell", "lays", "young"]:
		if not b.get(f, {}) is Dictionary:
			_err("pets.json", id, "livestock.%s must be an object" % f)
			return
	var wt: Dictionary = b.get("weight", {})
	if not wt.is_empty():
		var st = wt.get("start")
		if not (st is Array and st.size() == 2 and _is_num(st[0]) and _is_num(st[1]) and float(st[0]) > 0.0 and float(st[0]) <= float(st[1])):
			_err("pets.json", id, "livestock.weight.start must be [from, to] above 0")
		for f in ["gain_per_day", "lose_per_day", "fed_above", "hungry_below", "min", "max"]:
			if wt.has(f) and not (_is_num(wt[f]) and float(wt[f]) >= 0.0):
				_err("pets.json", id, "livestock.weight.%s must be a number of at least 0" % f)
	var g: Dictionary = b.get("grows_into", {})
	if not g.is_empty():
		if not _p.pets.has(str(g.get("kind", ""))) or str(g.get("kind", "")) == id:
			_err("pets.json", id, "livestock.grows_into.kind must be another kind")
		if not ((g.has("age") and _is_num(g["age"])) or (g.has("weight") and _is_num(g["weight"]) and not wt.is_empty())):
			_err("pets.json", id, "livestock.grows_into needs an age or (with weight) a weight")
	var s: Dictionary = b.get("sell", {})
	if not s.is_empty() and not ((s.has("per_weight") and _is_num(s["per_weight"]) and not wt.is_empty()) or (s.has("price") and _is_num(s["price"]))):
		_err("pets.json", id, "livestock.sell needs a price or (with weight) a per_weight")
	var l: Dictionary = b.get("lays", {})
	if not l.is_empty():
		if not _p.collectibles.has(str(l.get("collectible", ""))):
			_err("pets.json", id, "livestock.lays.collectible must be a collectible")
		if not (_is_num(l.get("per_day")) and float(l["per_day"]) >= 0.0):
			_err("pets.json", id, "livestock.lays.per_day must be a number of at least 0")
	var y: Dictionary = b.get("young", {})
	if not y.is_empty():
		var yk := str(y.get("kind", ""))
		if not (_p.pets.has(yk) and _p.pets[yk].get("livestock") is Dictionary and str(_p.pets[yk]["livestock"].get("pen", "")) == str(pen)):
			_err("pets.json", id, "livestock.young.kind must be livestock of the same pen")
		var c = y.get("count", [1, 1])
		if not (c is Array and c.size() == 2 and _whole(c[0]) and _whole(c[1]) and float(c[0]) >= 1.0 and float(c[0]) <= float(c[1])):
			_err("pets.json", id, "livestock.young.count must be [from, to] whole numbers of at least 1")
		for f in ["chance_per_day", "hours"]:
			if not (_is_num(y.get(f)) and float(y[f]) >= 0.0):
				_err("pets.json", id, "livestock.young.%s must be a number of at least 0" % f)


## The `pets` settings for livestock: `start` [{kind, count}] and `buyer`.
func _check_livestock_config(c: Dictionary) -> void:
	var st = c.get("start", [])
	if not st is Array or not (st as Array).all(func(e): return e is Dictionary and _p.pets.has(str(e.get("kind", ""))) \
			and _whole(e.get("count", 1)) and float(e.get("count", 1)) >= 1.0):
		_err("pack.json", _p.id, "pets.start must be [{kind, count}] of pets.json kinds")
	var b = c.get("buyer", {})
	if not b is Dictionary:
		_err("pack.json", _p.id, "pets.buyer must be an object")
		return
	if b.is_empty():
		return
	var kinds = b.get("kinds", [])
	if not (kinds is Array and (kinds as Array).all(func(k): return _p.pets.has(k) and _p.pets[k].get("livestock") is Dictionary \
			and not (_p.pets[k]["livestock"].get("sell", {}) as Dictionary).is_empty())):
		_err("pack.json", _p.id, "pets.buyer.kinds must be livestock kinds that sell")
	if not (_is_num(b.get("chance_per_hour")) and float(b["chance_per_hour"]) >= 0.0 and float(b["chance_per_hour"]) <= 1.0):
		_err("pack.json", _p.id, "pets.buyer.chance_per_hour must be from 0 to 1")
	for f in ["ttl_hours", "factor"]:
		if not (_is_num(b.get(f)) and float(b[f]) > 0.0):
			_err("pack.json", _p.id, "pets.buyer.%s must be a number above 0" % f)


## A whole number (JSON gives every number as a float).
func _whole(v) -> bool:
	return _is_num(v) and float(v) == floorf(float(v))
