class_name PackSkin
extends RefCounted
## The pack's art, as `art.json` in the pack directory declares it: which texture fills which
## ground, floor, wall face and decor colour, which picture stands for which object, mess,
## collectible and person (by stage and sex), and where extra scenery stands. Everything is
## optional: whatever has no picture is drawn the whitebox way by the caller. A pack without
## `art.json` has a disabled skin and draws exactly as before. Theme-neutral: it only knows
## the keys below.
##
## {
##   "dir": "art",                                   # pictures live under the pack dir
##   "tiles": {"<tile>": {"file": "tiles/x.png", "size": [192, 144], "soften": 0.2,
##             "fit_height": false}},                # size: house pixels one repeat covers
##   "sprites": {"<sprite>": "props/x.png"},
##   "ground": "<tile>", "compound_ground": "<tile>",
##   "floors": {"<room id>": "<tile>"},
##   "decor": {"#rrggbb": {"tile": "<tile>"} | {"sprite": "<sprite>"} | {"hide": true}},
##   "scenery": [{"sprite": "<sprite>", "x": cells, "y": cells (foot), "w": cells}],
##   "walls": {"house": "<tile>", "compound": "<tile>", "gate": "<sprite>", "sill": "<sprite>",
##             "fence_ns": ["<sprite>", ...]},  # north-south fence, one picture per cell in turn
##   "objects": {"<object type>": "<sprite>"}, "messes": {...}, "collectibles": {...},
##   "people": [{"stage": "<id>", "sex": "<gender>", "sprite": "<sprite>", "height": 90,
##               "rig": "rigs/x/x.rig.json",     # a cutout rig, animated (CutoutRig)
##               "rig_front": "...", "rig_back": "...",  # facing the camera / away (if present)
##               "lean": 8,                      # degrees bent forward (a stoop), rig only
##               "asleep": "<sprite>",           # the picture lying asleep (under a quilt)
##               "lying": false}],               # the picture already lies (a swaddled baby)
##   "pets": {"<pet kind>": {"sprite": "<sprite>", "height": 40, "front": "<sprite>", "back": "<sprite>"}},
##   "poses": {"actions": {"<action id>": "<pose>"}, "objects": {"<object type>": "<pose>"},
##             "on": ["<object type>"]},          # see `pose_for`; on: sat / lain on, not beside
##   "unwell": {"sprite": "<sprite>", "need": "<need id>", "below": 50},
##   "accent": "#rrggbb", "pickup": "#rrggbb",    # selection and pick-up colours
##   "view": "iso",                               # the 45° view (else seen from above)
##   "iso": {                                     # what the 45° view uses instead (each optional)
##     "objects": {"<object type>": "<sprite>"},  # pictures drawn at 45°, long side along plan x
##     "axis": {"<sprite>": "y"},                 # this picture's long side runs along plan y
##     "scale": {"<sprite>": 0.8},                # drawn this much of the footprint's width
##     "walls": {"gate": "<sprite>", "fence_x": "<sprite>", "fence_y": "<sprite>"},
##     "asleep": "<sprite>",                      # someone asleep on furniture, along plan x
##     "decals": [{"sprite": "<sprite>", "room": "<room id>", "side": "north" | "west",
##                 "at": cells along the wall, "w": pixels, "y": 0..1 down the wall}],
##     "scenery_scale": 1.0}                      # scenery pictures this much larger
## }

const DEFAULT_ACCENT := Color("#E5533C")
const DEFAULT_PICKUP := Color("#4FB3E8")
const SOFTEN := Color("#FFF4DF")

var enabled := false
var errors: Array[String] = []
var accent := DEFAULT_ACCENT
var pickup := DEFAULT_PICKUP
var _data: Dictionary = {}
var _base := ""
var _textures: Dictionary = {}  # file -> Texture2D (null when missing)
var _rigs: Dictionary = {}  # file -> CutoutRig (null when missing or broken)


## `path` overrides the default res://packs/<pack.id>/art.json (tests).
func _init(p: Pack, path := "") -> void:
	if path == "":
		if p == null or p.id == "":
			return
		path = "res://packs/%s/art.json" % p.id
	if not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("art.json: invalid JSON (line %d): %s" % [parser.get_error_line(), parser.get_error_message()])
		return
	if not parser.data is Dictionary:
		errors.append("art.json: must be a JSON object")
		return
	_data = parser.data
	_base = path.get_base_dir() + "/" + str(_data.get("dir", "")).trim_suffix("/")
	enabled = true
	accent = _color(_data.get("accent"), DEFAULT_ACCENT)
	pickup = _color(_data.get("pickup"), DEFAULT_PICKUP)


static func _color(v, fallback: Color) -> Color:
	return Color.html(v) if v is String and Color.html_is_valid(v) else fallback


func _table(key: String) -> Dictionary:
	var t = _data.get(key, {})
	return t if t is Dictionary else {}


## The texture in `file` (relative to the art dir), or null when it does not load.
func texture(file: String) -> Texture2D:
	if _textures.has(file):
		return _textures[file]
	var path := _base + "/" + file
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		errors.append("art.json: missing picture %s" % file)
	_textures[file] = tex
	return tex


## Whether the pack asks for the 45° view (`"view": "iso"`).
func iso() -> bool:
	return enabled and str(_data.get("view", "")) == "iso"


func _iso_table(key: String) -> Dictionary:
	var t = _table("iso").get(key, {})
	return t if iso() and t is Dictionary else {}


## The 45° view's own picture for `key` of iso table `table`, or null.
func _iso_sprite(table: String, key: String) -> Texture2D:
	var name = _iso_table(table).get(key)
	return sprite(str(name)) if name is String else null


## Which plan axis the long side of the picture of object type `type` runs along in the 45°
## view: "x" (the default) or "y". "" when the picture is not a 45° one.
func object_axis(type: String) -> String:
	var name = _iso_table("objects").get(type)
	if not name is String or sprite(str(name)) == null:
		return ""
	return "y" if str(_iso_table("axis").get(name, "x")) == "y" else "x"


## How much smaller or larger the 45° picture of object type `type` stands than its
## footprint's diamond (`iso.scale`, by picture name; 1 by default).
func object_scale(type: String) -> float:
	var name = _iso_table("objects").get(type)
	if not name is String:
		return 1.0
	return clampf(float(_iso_table("scale").get(name, 1.0)), 0.3, 1.5)


## The 45° view's wall pictures: [{tex, room, side, at, w, y}].
func wall_decals() -> Array:
	var out: Array = []
	var list = _table("iso").get("decals", []) if iso() else []
	if not list is Array:
		return out
	for e in list:
		if not e is Dictionary:
			continue
		var tex := sprite(str(e.get("sprite", "")))
		if tex == null:
			continue
		out.append({"tex": tex, "room": str(e.get("room", "")), "side": "west" if str(e.get("side", "")) == "west" else "north",
			"at": float(e.get("at", 0.5)), "w": float(e.get("w", 50.0)), "y": float(e.get("y", 0.25))})
	return out


## How much larger scenery pictures stand in the 45° view.
func scenery_scale() -> float:
	return float(_table("iso").get("scenery_scale", 1.0)) if iso() else 1.0


## A named sprite's texture; null when the name is "" or not declared, or the file is missing.
func sprite(name: String) -> Texture2D:
	var f = _table("sprites").get(name)
	return texture(str(f)) if f is String else null


## A named tile: {tex, size, soften, fit_height}; {} when undeclared or missing.
func tile(name: String) -> Dictionary:
	var t = _table("tiles").get(name)
	if not (t is Dictionary and t.get("file") is String):
		return {}
	var tex := texture(str(t["file"]))
	if tex == null:
		return {}
	var size := Vector2(tex.get_size()) * 0.5
	var s = t.get("size")
	if s is Array and s.size() == 2:
		size = Vector2(float(s[0]), float(s[1]))
	return {"tex": tex, "size": size, "soften": float(t.get("soften", 0.0)), "fit_height": bool(t.get("fit_height", false))}


func ground_tile() -> Dictionary:
	return tile(str(_data.get("ground", "")))


func compound_tile() -> Dictionary:
	return tile(str(_data.get("compound_ground", "")))


func floor_tile(room: String) -> Dictionary:
	return tile(str(_table("floors").get(room, "")))


## What the skin does with a decor shape of colour `html`: {tile}, {sprite}, {hide} or {}.
func decor_rule(html: String) -> Dictionary:
	var c := Color.html(html) if Color.html_is_valid(html) else Color(0, 0, 0, 0)
	for k in _table("decor"):
		if Color.html_is_valid(str(k)) and Color.html(str(k)).is_equal_approx(c):
			var r = _table("decor")[k]
			return r if r is Dictionary else {}
	return {}


## [{tex, x, y, w}] in cells: the extra scenery the skin stands on the map.
func scenery() -> Array:
	var out: Array = []
	var list = _data.get("scenery", [])
	if not list is Array:
		return out
	for e in list:
		if not e is Dictionary:
			continue
		var tex := sprite(str(e.get("sprite", "")))
		if tex != null:
			out.append({"tex": tex, "x": float(e.get("x", 0)), "y": float(e.get("y", 0)), "w": float(e.get("w", 1))})
	return out


## The wall face tile for a wall kind ("house", "compound"); {} when none.
func wall_tile(kind: String) -> Dictionary:
	return tile(str(_table("walls").get(kind, "")))


func wall_sprite(key: String) -> Texture2D:
	var own := _iso_sprite("walls", key)
	if own != null:
		return own
	return sprite(str(_table("walls").get(key, "")))


## The pictures listed under a walls key (a name or a list of names), missing ones left out.
func wall_sprites(key: String) -> Array:
	var v = _table("walls").get(key)
	var names: Array = v if v is Array else ([v] if v is String else [])
	var out: Array = []
	for nm in names:
		var t := sprite(str(nm))
		if t != null:
			out.append(t)
	return out


func object_sprite(type: String) -> Texture2D:
	var own := _iso_sprite("objects", type)
	if own != null:
		return own
	return sprite(str(_table("objects").get(type, "")))


func mess_sprite(type: String) -> Texture2D:
	return sprite(str(_table("messes").get(type, "")))


func collectible_sprite(type: String) -> Texture2D:
	return sprite(str(_table("collectibles").get(type, "")))


## The look of a person: the first `people` entry whose stage and sex (each optional) match:
## {tex, height}; {} when nothing matches.
func person_look(stage: String, sex: String) -> Dictionary:
	var list = _data.get("people", [])
	if not list is Array:
		return {}
	for e in list:
		if not e is Dictionary:
			continue
		if e.has("stage") and str(e["stage"]) != stage:
			continue
		if e.has("sex") and str(e["sex"]) != sex:
			continue
		var tex := sprite(str(e.get("sprite", "")))
		if tex == null:
			continue
		var out := {"tex": tex, "height": float(e.get("height", 90.0)), "lean": float(e.get("lean", 0.0)),
			"lying": bool(e.get("lying", false))}
		var asleep := sprite(str(e.get("asleep", "")))
		var iso_asleep := sprite(str(_table("iso").get("asleep", ""))) if iso() else null
		if iso_asleep != null and asleep != null:
			out["asleep"] = iso_asleep
			out["asleep_iso"] = true
		elif asleep != null:
			out["asleep"] = asleep
		if e.get("rig") is String:
			var r := rig(str(e["rig"]))
			if r != null:
				out["rig"] = r
		# Facing the camera and facing away: used when they are there (else the side rig).
		for k in ["rig_front", "rig_back"]:
			if e.get(k) is String and FileAccess.file_exists(_base + "/" + str(e[k])):
				var r2 := rig(str(e[k]))
				if r2 != null:
					out[k] = r2
		return out
	return {}


## The look of a pet kind: {tex, height}; {} when the skin has no picture for it.
func pet_look(kind: String) -> Dictionary:
	var e = _table("pets").get(kind)
	if not e is Dictionary:
		return {}
	var tex := sprite(str(e.get("sprite", "")))
	if tex == null:
		return {}
	var out := {"tex": tex, "height": float(e.get("height", 40.0))}
	# Facing the camera / turned away (each optional).
	for k in ["front", "back"]:
		var t := sprite(str(e.get(k, "")))
		if t != null:
			out[k] = t
	return out


## The cutout rig in `file` (relative to the art dir); null when it is missing or broken.
func rig(file: String) -> CutoutRig:
	if _rigs.has(file):
		return _rigs[file]
	var path := _base + "/" + file
	var r: CutoutRig = null
	if FileAccess.file_exists(path):
		r = CutoutRig.load_file(path)
	if r == null:
		errors.append("art.json: missing or broken rig %s" % file)
	_rigs[file] = r
	return r


## The body pose for doing action `action` at an object of type `object` ("" for none): the
## pack's `poses.actions`, then `poses.objects`, else "" (the view picks a default).
func pose_for(action: String, object: String) -> String:
	var t = _data.get("poses", {})
	if not t is Dictionary:
		return ""
	var a = t.get("actions", {})
	if a is Dictionary and a.get(action) is String:
		return a[action]
	var o = t.get("objects", {})
	if object != "" and o is Dictionary and o.get(object) is String:
		return o[object]
	return ""


## Whether a person sits or lies on furniture of this type (else they stand beside it).
func sat_on(object: String) -> bool:
	var t = _data.get("poses", {})
	return t is Dictionary and t.get("on") is Array and (t["on"] as Array).has(object)


## The "looks unwell" mark: {tex, need, below}; {} when the skin has none.
func unwell() -> Dictionary:
	var u = _data.get("unwell")
	if not u is Dictionary:
		return {}
	var tex := sprite(str(u.get("sprite", "")))
	if tex == null or not u.get("need") is String:
		return {}
	return {"tex": tex, "need": str(u["need"]), "below": float(u.get("below", 50.0))}


## Fills `rect` (house coordinates) with a tile, its pattern anchored to the house origin so
## neighbouring rects join seamlessly; then the soften wash. The canvas item needs
## texture_repeat on. `fit_height`: the texture's full height spans the rect.
static func draw_tile(ci: CanvasItem, t: Dictionary, rect: Rect2, tint := Color.WHITE) -> void:
	var tex: Texture2D = t["tex"]
	var ts := Vector2(tex.get_size())
	var src: Rect2
	if bool(t.get("fit_height", false)):
		var k := ts.y / maxf(rect.size.y, 1.0)
		src = Rect2(rect.position.x * k, 0.0, rect.size.x * k, ts.y)
	else:
		var k2: Vector2 = ts / (t["size"] as Vector2)
		src = Rect2(rect.position * k2, rect.size * k2)
	ci.draw_texture_rect_region(tex, rect, src, tint)
	var soft := float(t.get("soften", 0.0))
	if soft > 0.0:
		ci.draw_rect(rect, Color(SOFTEN, soft))


## The rect a picture takes when it stands with its bottom middle at `foot`, scaled to fit
## within `max_size` (house pixels), never above its 2x drawn size.
static func fit_rect(tex: Texture2D, foot: Vector2, max_size: Vector2) -> Rect2:
	var ts := Vector2(tex.get_size())
	var k := minf(minf(max_size.x / ts.x, max_size.y / ts.y), 1.0)
	var s := ts * k
	return Rect2(foot.x - s.x * 0.5, foot.y - s.y, s.x, s.y)
