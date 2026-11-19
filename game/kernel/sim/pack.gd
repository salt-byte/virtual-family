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
## Files a pack may leave out; without them the feature is simply absent.
const OPTIONAL_FILES := {"wishes": "wishes.json", "stories": "stories.json", "dishes": "dishes.json",
	"pets": "pets.json", "festivals": "festivals.json"}

const DEFAULT_CONFIG := {
	"hours_per_year": 2.0, "offline_cap_hours": 48, "offline_need_floor": 15,
	"stages": [{"id": "baby", "from": 0}, {"id": "child", "from": 2}, {"id": "adult", "from": 18}, {"id": "elder", "from": 55}],
	"lifespan": [60, 75], "adopt_age": [22, 29], "start_money": 200, "sleep_hours": [22, 6],
	"proposal_first_min": 15, "proposal_after_decline_min": 45, "proposal_interval_hours": 24,
	"proposal_ttl_hours": 24, "praise_need": "", "praise_gain": 5, "praise_decay_per_hour": 1,
	"praise_window_min": 10, "praise_annoy_count": 3, "work_needs_min": {},
	"illness_daily_chance": 0.15, "collectible_interval_min": 20, "collectible_max": 3,
	"collectible_ttl_min": 60, "sell_back_ratio": 0.5, "repeat_factor": 0.3,
	"start_objects": [],
	"step_seconds": 60,
	"action_speed": 1.0,
	"repeat_memory": 1, "choice_pool": 3,
	# Wishes (only with a wishes.json): the chance per game hour that someone without a wish
	# forms one, the mood lost when a mood wish runs out, and how long the thanks lasts
	# (game minutes on the fast action clock).
	"wish_chance_per_hour": 0.3, "wish_miss_penalty": 10, "wish_thanks_min": 2,
	# A wish to do something (kind "do") makes the wished actions score this many times
	# higher for the one who holds it.
	"wish_do_factor": 3.0,
	# Low mood (off while mood_low_below is 0): the praise need below the line for
	# mood_sad_after_hours makes a person sad, for mood_depressed_after_hours depressed; above
	# mood_recover_above for mood_recover_hours lifts depression to sadness, and sadness clears
	# after mood_sad_recover_hours. While depressed, actions that do not require the mood
	# score x mood_depressed_factor and mood_depressed_drain adds need drain per hour.
	"mood_low_below": 0, "mood_sad_after_hours": 6, "mood_depressed_after_hours": 24,
	"mood_recover_above": 50, "mood_recover_hours": 12, "mood_sad_recover_hours": 3,
	"mood_depressed_factor": 1.0, "mood_depressed_drain": {},
	# Attention (off while mood_care_hours is 0): once nobody has praised a person, used
	# something on them or granted their wish for mood_care_hours, their own actions only
	# lift the praise need up to a ceiling that sinks mood_neglect_per_hour per further hour,
	# down to mood_neglect_floor.
	"mood_care_hours": 0, "mood_neglect_per_hour": 2.0, "mood_neglect_floor": 10,
	# Story fragments (only with a stories.json): one per story_interval_min on average,
	# lying about for story_ttl_min.
	"story_interval_min": 240, "story_ttl_min": 600,
	# Births (off while empty; see `BirthSystem` for the keys).
	"births": {},
	# The ground plan the view draws (off while empty): map size in cells, an optional
	# compound wall, door openings, fences and ground decor. The sim never reads it; see
	# `PackValidator._check_site` for the keys.
	"site": {},
	# Seasons and weather (off while empty; see `WeatherSystem` and
	# `PackValidator._check_seasons` for the keys).
	"seasons": {},
	# Pay for a clean house (off while empty): `amount` coins when the last mess is cleaned
	# away, at most once per local day.
	"clean_reward": {},
	# Animals (off while empty or without a pets.json; see `PetSystem` and
	# `PackValidator._check_pets` for the keys).
	"pets": {},
}

## Per-file field defaults (applied to every entry that lacks the key).
const ENTRY_DEFAULTS := {
	"actions": {"object": "", "needs": {}, "base": 0, "hours": [], "tags": [], "praiseable": true,
		"consumes": {}, "work": {}, "mess": {}, "cleans": "", "picks": false, "requires": {},
		"slow": false, "rooms": [], "completes_story": "", "tends": {}, "serves": "", "eats": [],
		"yields": {}, "seasons": [], "weather": [], "not_wet": false, "pet": {},
		"festivals": [], "outing": {}, "mourns": false},
	"object_types": {"outdoor": false, "capacity": 1, "fixed": false, "keepsake": false},
	"collectibles": {"rooms": []},
	"wishes": {"likes": [], "stages": [], "weight": 1.0, "festival": "", "actions": []},
	"dishes": {"on": [], "leaves": "", "ttl_hours": 0, "max_out": 1, "scraps": ""},
	"pets": {"price": 0, "stray": false, "names": [], "lifespan": [10, 14], "age": [1, 2], "drains": {},
		"home": [], "perch": "", "actions": [], "wishes": [], "perks": {}, "thanks": "", "size": 0.6},
	"rooms": {"outdoor": false, "props": [], "outside": false},
	"items": {"stock": {}, "cures": "", "needs": {}, "work": {}, "childhood": {}, "pet": {}, "festivals": []},
	"festivals": {"boost": {}, "wish_chance": 0.5, "banner": "", "start_text": "", "end_text": ""},
	"needs": {"when_empty": {}},
}

## Field defaults of a pet's own action (an entry of a pets.json kind's `actions`).
const PET_ACTION_DEFAULTS := {"duration_min": 10, "base": 1, "object": "", "rooms": [], "hours": [],
	"weather": [], "wet": false, "sick": false, "follows": "", "scraps": "", "needs": {}, "mess": {}, "above": {}, "every_hours": 0}

## Fields that are always whole numbers (JSON gives floats, so they are converted on load).
const INT_FIELDS := {
	"actions": ["duration_min", "base"],
	"object_types": ["price", "w", "h", "capacity"],
	"rooms": ["w", "h", "build_cost", "x", "y"],
	"items": ["price"],
	"illnesses": ["weight"],
	"collectibles": ["value", "weight"],
	"goals": ["reward"],
	"dishes": ["portions", "max_out"],
	"pets": ["price"],
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
var wishes: Dictionary = {}
var stories: Dictionary = {}
## Cooked food that waits on a table to be eaten (optional dishes.json; see `DishSystem`).
var dishes: Dictionary = {}
## Kinds of animals (optional pets.json; see `PetSystem`).
var pets: Dictionary = {}
## Feast days at fixed points of the year (optional festivals.json; see `FestivalSystem`).
var festivals: Dictionary = {}
## `FestivalSystem`'s prepared calendar (built on first use).
var festival_prep: Array = []
## pet action id -> its entry, over every kind (filled by `PetSystem.action`).
var pet_actions: Dictionary = {}
var names: Dictionary = {}
## Raw parsed file contents by file name, as read; used by the validator.
var raw: Dictionary = {}
## The actions' constant parts, prepared by `AutonomySystem` on first use.
var autonomy_table: Array = []
## stage id -> the entries of `autonomy_table` open to that stage, in pack order.
var autonomy_by_stage: Dictionary = {}
## "stage|track" -> `autonomy_by_stage[stage]` without the work actions of other tracks.
var autonomy_by_stage_track: Dictionary = {}
## "likes|dislikes|hour|rooms built" -> per action the yes/no bits `AutonomySystem` reuses.
var autonomy_flags: Dictionary = {}
## `LivelihoodSystem.adult_age`, kept with the stages array it was read from.
var adult_age := -1.0
var adult_age_src: Variant = null
var adult_age_n := -1
## `WeatherSystem`'s prepared constants (built on first use).
var weather_prep: Dictionary = {}
## object type -> index, for the types actions use (see `AutonomySystem.Info.obj_ix`).
var autonomy_obj_types: Dictionary = {}
## The need ids in pack order (indexes of `AutonomySystem.Info.need_ix`).
var autonomy_need_ids := PackedStringArray()
## action id -> its position in `autonomy_table`.
var autonomy_index: Dictionary = {}
## True when every action's `hours` window has whole-hour bounds (set with `autonomy_table`).
var autonomy_whole_hours := true
## livelihood id -> {action id: affinity matches}, prepared by `LivelihoodSystem`.
var affinity_table: Dictionary = {}
## The needs' drains as plain arrays, prepared by `NeedsSystem` on first use.
var needs_table: Array = []
## `stages` as parallel arrays (ids, starting ages), rebuilt when the array is replaced or
## changes size (see `stage_of`).
var _stage_src: Variant = null
var _stage_n := -1
var _stage_ids: PackedStringArray = []
var _stage_from: PackedFloat64Array = []


## The id of the stage someone of `age` years is in: the last stage (in `stages` order) whose
## `from` is at most `age`; "" before the first. Called on every step, so the stages are read
## into plain arrays once.
func stage_of(age: float) -> String:
	var stages = config.get("stages")
	if not is_same(stages, _stage_src) or (stages as Array).size() != _stage_n:
		_stage_src = stages
		_stage_n = (stages as Array).size()
		_stage_ids = []
		_stage_from = []
		for st in stages:
			_stage_ids.append(str(st["id"]))
			_stage_from.append(float(st["from"]))
	var result := ""
	for k in _stage_from.size():
		if age >= _stage_from[k]:
			result = _stage_ids[k]
	return result


## The age (years) at which the baby stage ends, worked out on first use (see `baby_until`).
var _baby_until := -1.0


## The age (years) at which the baby stage ends: where the next stage starts (0 when the pack
## has no baby stage, INF when nothing follows it). Read on the hot path instead of `stage`.
func baby_until() -> float:
	if _baby_until < 0.0:
		_baby_until = 0.0
		var stages = config.get("stages")
		if stages is Array:
			var seen := false
			for st in stages:
				if not st is Dictionary:
					continue
				if seen:
					_baby_until = float(st.get("from", 0.0))
					seen = false
					break
				if str(st.get("id", "")) == "baby":
					seen = true
					_baby_until = INF
			if seen:
				_baby_until = INF
	return _baby_until


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
	for key in OPTIONAL_FILES:
		var file: String = OPTIONAL_FILES[key]
		if not FileAccess.file_exists(base + "/" + file):
			continue
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
	if config["start_objects"] is Array:
		for so in config["start_objects"]:
			if so is Dictionary:
				for f in ["x", "y"]:
					if so.has(f):
						so[f] = _as_int(so[f])
	config["site"] = _deep_ints(config["site"])
	config["seasons"] = _deep_ints(config["seasons"])
	config["clean_reward"] = _deep_ints(config["clean_reward"])
	for r in rooms.values():
		if r["props"] is Array:
			for pr in r["props"]:
				if pr is Dictionary:
					for f in ["x", "y"]:
						if pr.has(f):
							pr[f] = _as_int(pr[f])
	for a in actions.values():
		if not a.has("stages"):
			a["stages"] = stage_ids.duplicate()
		if a["hours"] is Array:
			a["hours"] = (a["hours"] as Array).map(_as_int)
		if a["consumes"] is Dictionary:
			for k in a["consumes"]:
				a["consumes"][k] = _as_int(a["consumes"][k])
		if a["yields"] is Dictionary:
			for k in a["yields"]:
				a["yields"][k] = _as_int(a["yields"][k])
	for k in pets.values():
		if k["actions"] is Array:
			for a in k["actions"]:
				if not a is Dictionary:
					continue
				for f in PET_ACTION_DEFAULTS:
					if not a.has(f):
						var d = PET_ACTION_DEFAULTS[f]
						a[f] = d.duplicate(true) if (d is Array or d is Dictionary) else d
				for f in ["duration_min", "base"]:
					a[f] = _as_int(a[f])
				if a["hours"] is Array:
					a["hours"] = (a["hours"] as Array).map(_as_int)
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


## `v` with every whole-number float inside it (at any depth) turned into an int.
static func _deep_ints(v: Variant) -> Variant:
	if v is Array:
		return (v as Array).map(_deep_ints)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _deep_ints(v[k])
		return out
	return _as_int(v)


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
