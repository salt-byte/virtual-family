class_name Pack
extends RefCounted
## A loaded theme pack: every JSON file under one directory, indexed by id, with
## documented defaults filled in. Loading never raises engine errors; every problem
## (missing file, bad JSON, bad reference) is recorded in `errors` as
## "<file>: <entry id>: <message>" ("*" stands for a whole-file problem).
##
## Number typing: counts, sizes, money, minutes and levels are ints; need magnitudes
## (start, drain, per-hour amounts, penalties, action needs) stay floats as in JSON.

const FILES := {
	"needs": "needs.json", "actions": "actions.json", "object_types": "objects.json",
	"rooms": "rooms.json", "livelihoods": "livelihoods.json", "items": "items.json",
	"illnesses": "illnesses.json", "mess_types": "messes.json",
	"collectibles": "collectibles.json", "goals": "goals.json",
}

const DEFAULT_CONFIG := {
	"hours_per_year": 2.0, "offline_cap_hours": 48, "offline_need_floor": 15,
	"stages": [{"id": "baby", "from": 0}, {"id": "child", "from": 2}, {"id": "adult", "from": 18}, {"id": "elder", "from": 55}],
	"lifespan": [60, 75], "adopt_age": [22, 29], "start_money": 200, "sleep_hours": [22, 6],
	"proposal_first_min": 15, "proposal_after_decline_min": 45, "proposal_interval_hours": 24,
	"proposal_ttl_hours": 24, "praise_need": "", "praise_gain": 5, "praise_decay_per_hour": 1,
	"praise_window_min": 10, "praise_annoy_count": 3, "work_needs_min": {},
	"illness_daily_chance": 0.15, "collectible_interval_min": 20, "collectible_max": 3,
	"collectible_ttl_min": 60, "sell_back_ratio": 0.5,
}

## Per-file field defaults (applied to every entry that lacks the key).
const ENTRY_DEFAULTS := {
	"actions": {"object": "", "needs": {}, "base": 0, "hours": [], "tags": [], "praiseable": true,
		"consumes": {}, "work": {}, "mess": {}, "cleans": "", "picks": false, "requires": {}},
	"object_types": {"outdoor": false},
	"rooms": {"outdoor": false},
	"items": {"stock": {}, "cures": "", "needs": {}},
	"needs": {"when_empty": {}},
}

## Fields that are always whole numbers (JSON gives floats, so they are converted on load).
const INT_FIELDS := {
	"actions": ["duration_min", "base"],
	"object_types": ["price", "w", "h"],
	"rooms": ["w", "h", "build_cost"],
	"items": ["price"],
	"illnesses": ["weight"],
	"collectibles": ["value", "weight"],
	"goals": ["reward"],
}

var id := ""
var errors: Array[String] = []
var config: Dictionary = {}
var needs: Dictionary = {}
var actions: Dictionary = {}
var object_types: Dictionary = {}
var rooms: Dictionary = {}
var livelihoods: Dictionary = {}
var items: Dictionary = {}
var illnesses: Dictionary = {}
var mess_types: Dictionary = {}
var collectibles: Dictionary = {}
var goals: Dictionary = {}
var names: Dictionary = {}
## Raw parsed file contents by file name, as read; used by the validator.
var raw: Dictionary = {}


static func load_dir(dir: String) -> Pack:
	var p := Pack.new()
	if not DirAccess.dir_exists_absolute(dir):
		p.errors.append("pack: *: directory not found: %s" % dir)
		return p
	var base := dir.trim_suffix("/")
	var pack_json = p._read_json(base, "pack.json")
	var pack_dict: Dictionary = {}
	if pack_json is Dictionary:
		pack_dict = pack_json
	elif pack_json != null:
		p.errors.append("pack.json: *: must be a JSON object")
	var names_json = p._read_json(base, "names.json")
	if names_json is Dictionary:
		p.names = names_json
	elif names_json != null:
		p.errors.append("names.json: *: must be a JSON object")
	for key in FILES:
		var file: String = FILES[key]
		var data = p._read_json(base, file)
		if data == null:
			continue
		if not data is Array:
			p.errors.append("%s: *: must be a JSON array" % file)
			continue
		p.set(key, p._index(file, key, data))
	p._build_config(pack_dict)
	p.id = str(pack_dict.get("id", ""))
	p._apply_defaults()
	p.errors.append_array(PackValidator.validate(p))
	return p


func is_valid() -> bool:
	return errors.is_empty()


## Config value, with the documented default when the pack does not set it.
func cfg(key: String) -> Variant:
	return config.get(key)


func _read_json(dir: String, file: String) -> Variant:
	var path := dir + "/" + file
	if not FileAccess.file_exists(path):
		errors.append("%s: *: file missing" % file)
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s: *: invalid JSON (line %d): %s" % [file, parser.get_error_line(), parser.get_error_message()])
		return null
	if parser.data == null:
		errors.append("%s: *: must be a JSON %s" % [file, "object" if file in ["pack.json", "names.json"] else "array"])
		return null
	raw[file] = parser.data
	return parser.data


func _index(file: String, key: String, data: Array) -> Dictionary:
	var out := {}
	for i in data.size():
		var e = data[i]
		if not e is Dictionary:
			errors.append("%s: #%d: entry must be an object" % [file, i])
			continue
		var eid := str(e.get("id", ""))
		if eid == "":
			errors.append("%s: #%d: missing id" % [file, i])
			continue
		if out.has(eid):
			errors.append("%s: %s: duplicate id" % [file, eid])
			continue
		var entry: Dictionary = e.duplicate(true)
		for f in INT_FIELDS.get(key, []):
			if entry.has(f):
				entry[f] = _as_int(entry[f])
		out[eid] = entry
	return out


func _build_config(pack_dict: Dictionary) -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	for k in pack_dict:
		config[k] = _coerce_like(pack_dict[k], DEFAULT_CONFIG[k]) if DEFAULT_CONFIG.has(k) else pack_dict[k]


func _apply_defaults() -> void:
	# Stages are read in age order everywhere, so sort them by `from` (when well-formed).
	var stages = config["stages"]
	if stages is Array and (stages as Array).all(func(s): return s is Dictionary and (s.get("from") is int or s.get("from") is float)):
		(stages as Array).sort_custom(func(a, b): return float(a["from"]) < float(b["from"]))
	for key in ENTRY_DEFAULTS:
		var defaults: Dictionary = ENTRY_DEFAULTS[key]
		for e in (get(key) as Dictionary).values():
			for f in defaults:
				if not e.has(f):
					e[f] = defaults[f].duplicate(true) if (defaults[f] is Array or defaults[f] is Dictionary) else defaults[f]
	var stage_ids: Array = []
	if config["stages"] is Array:
		for s in config["stages"]:
			if s is Dictionary and str(s.get("id", "")) != "baby":
				stage_ids.append(str(s.get("id", "")))
	for a in actions.values():
		if not a.has("stages"):
			a["stages"] = stage_ids.duplicate()
		if a["hours"] is Array:
			a["hours"] = (a["hours"] as Array).map(_as_int)
		if a["consumes"] is Dictionary:
			for k in a["consumes"]:
				a["consumes"][k] = _as_int(a["consumes"][k])
	for it in items.values():
		if it["stock"] is Dictionary:
			for k in it["stock"]:
				it["stock"][k] = _as_int(it["stock"][k])
	for n in needs.values():
		if not n.get("labels") is Array:
			continue
		for l in n["labels"]:
			if l is Dictionary and l.has("below"):
				l["below"] = _as_int(l["below"])
		if (n["labels"] as Array).all(func(l): return l is Dictionary and l.get("below") is int):
			(n["labels"] as Array).sort_custom(func(a, b): return a["below"] < b["below"])
	for lv in livelihoods.values():
		if not lv.get("levels") is Array:
			continue
		for level in lv["levels"]:
			if level is Dictionary:
				for f in ["daily_income", "progress_to_next"]:
					if level.has(f):
						level[f] = _as_int(level[f])
	for g in goals.values():
		if g.get("when") is Dictionary:
			for f in ["amount", "count", "level"]:
				if g["when"].has(f):
					g["when"][f] = _as_int(g["when"][f])


static func _as_int(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	return v


## Converts whole-number floats to int wherever the default has an int in that position.
static func _coerce_like(v: Variant, d: Variant) -> Variant:
	if d is int:
		return _as_int(v)
	if d is Array and v is Array and not d.is_empty():
		var out := []
		for i in v.size():
			out.append(_coerce_like(v[i], d[mini(i, d.size() - 1)]))
		return out
	if d is Dictionary and v is Dictionary:
		var out2 := {}
		for k in v:
			out2[k] = _coerce_like(v[k], d[k]) if d.has(k) else v[k]
		return out2
	return v
