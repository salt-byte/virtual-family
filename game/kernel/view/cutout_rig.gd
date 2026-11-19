class_name CutoutRig
extends RefCounted
## A cutout character: part pictures hung on joints (`<name>.rig.json`, the format of the
## cutout-animation tool: parts with parent, z, pivot_px, attach_px, optional same_as / tint,
## and root_px putting the feet at y 0), and the body poses the view plays on it. Each part
## turns about its own joint; a child hangs on its parent's attach point. Angles are degrees,
## positive clockwise on screen (a leg swings back, a knee bends back); offsets are in
## "torso is 100 high" units. The rig faces right.
##
## Poses: "idle" (breathing), "walk", "work" (arms busy in front), "sit", "eat" (hand to
## mouth), "sleep" (lying, drawn turned on its back by the caller) and "wave".

const POSES := ["idle", "walk", "work", "sit", "eat", "sleep", "wave"]
const WALK_PERIOD := 0.72
const WORK_PERIOD := 0.7
const EAT_PERIOD := 1.6
const BREATH_PERIOD := 2.6
const WAVE_PERIOD := 0.45

## [{id, parent, z, tex, pivot, attach, tint}] with parents before their children.
var parts: Array = []
var root := Vector2.ZERO
## Pixels per offset unit (the torso's height / 100).
var unit := 1.0
## Height of the standing figure, feet to the top of the head (rig pixels).
var height := 1.0
## How far the hips drop when sitting (the thigh's length, rig pixels).
var thigh := 0.0
## "side" (the rig faces right), "front" (faces the camera) or "back" (turned away). A front
## or back rig only walks and stands (`pose`): the side rig does the rest.
var facing := "side"
## The head's height (rig pixels), to size a front or back rig like the side one.
var head_height := 0.0
var _by_id: Dictionary = {}


static func load_file(path: String) -> CutoutRig:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return null
	var data: Dictionary = parser.data
	var dir := path.get_base_dir()
	var r := CutoutRig.new()
	var raw: Dictionary = {}
	for p in data.get("parts", []):
		if p is Dictionary and p.get("id") is String:
			raw[p["id"]] = p
	for id in raw:
		var p: Dictionary = raw[id]
		var img = p.get("image")
		if not img is String and p.get("same_as") is String and raw.has(p["same_as"]):
			img = raw[p["same_as"]].get("image")
		if not img is String or not (p.get("pivot_px") is Array):
			return null
		var file: String = dir + "/" + str(img)
		var tex: Texture2D = load(file) as Texture2D if ResourceLoader.exists(file) else null
		if tex == null:
			return null
		var parent = p.get("parent")
		if parent is String and not (raw.has(parent) and p.get("attach_px") is Array):
			return null
		r._by_id[id] = {"id": id, "parent": parent if parent is String else "", "z": float(p.get("z", 0)),
			"tex": tex, "pivot": _v(p["pivot_px"]), "attach": _v(p.get("attach_px", [0, 0])),
			"tint": float(p.get("tint", 1.0)), "size": Vector2(tex.get_size())}
	if r._by_id.is_empty():
		return null
	var seen := {}
	for id in r._by_id:
		r._visit(id, seen)
	r.root = _v(data.get("root_px", [0, 0]))
	var f := str(data.get("facing", "right"))
	r.facing = f if f in ["front", "back"] else "side"
	if r._by_id.has("head"):
		r.head_height = r._by_id["head"].size.y
	for p in r.parts:
		if p.parent == "":
			r.unit = p.size.y / 100.0
	var top := 0.0
	var w := r.world({})
	for p in r.parts:
		var m: Transform2D = w[p.id]
		for c in [Vector2.ZERO, Vector2(p.size.x, 0), Vector2(0, p.size.y), p.size]:
			top = minf(top, (m * (c - p.pivot)).y)
	r.height = maxf(-top, 1.0)
	if r._by_id.has("leg_upper") and r._by_id.has("leg_lower"):
		r.thigh = (r._by_id["leg_lower"].attach - r._by_id["leg_upper"].pivot).length()
	return r


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


func _visit(id: String, seen: Dictionary) -> void:
	if seen.has(id):
		return
	seen[id] = true
	var p: Dictionary = _by_id[id]
	if p.parent != "":
		_visit(p.parent, seen)
	parts.append(p)


func has_part(id: String) -> bool:
	return _by_id.has(id)


## Every part's transform (part joint space -> rig space, feet at the origin) for `pose`:
## {part id: Vector3(rot degrees, dx, dy)}; a part not named stays at rest.
func world(pose: Dictionary) -> Dictionary:
	var out := {}
	for p in parts:
		var v: Vector3 = pose.get(p.id, Vector3.ZERO)
		var off: Vector2 = root if p.parent == "" else (p.attach - _by_id[p.parent].pivot)
		var m := Transform2D(deg_to_rad(v.x), off + Vector2(v.y, v.z) * unit)
		out[p.id] = (out[p.parent] * m) if p.parent != "" else m
	return out


## Draws the rig on `ci` under `xform` (rig space -> the canvas), parts by z.
func draw(ci: CanvasItem, pose: Dictionary, xform: Transform2D, modulate := Color.WHITE) -> void:
	var w := world(pose)
	var order := parts.duplicate()
	order.sort_custom(func(a, b): return a.z < b.z)
	for p in order:
		ci.draw_set_transform_matrix(xform * (w[p.id] as Transform2D) * Transform2D(0.0, -p.pivot))
		var t: float = p.tint
		ci.draw_texture(p.tex, Vector2.ZERO, Color(modulate.r * t, modulate.g * t, modulate.b * t, modulate.a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## The joint angles and offsets of `name` at time `t` (seconds): {part: Vector3(rot, dx, dy)}.
## An unknown name is "idle".
func pose(name: String, t: float) -> Dictionary:
	var breath := sin(TAU * t / BREATH_PERIOD)
	if facing != "side":
		return _pose_facing(name, t, breath)
	match name:
		"walk":
			var s := sin(TAU * t / WALK_PERIOD)
			var c := cos(TAU * t / WALK_PERIOD)
			return {
				"torso": Vector3(3.0, 0.0, -2.0 * absf(c)),
				"head": Vector3(-2.0, 0.0, 0.0),
				"leg_upper": Vector3(-26.0 * s, 0.0, 0.0),
				"leg_lower": Vector3(28.0 * maxf(0.0, s), 0.0, 0.0),
				"leg_back_upper": Vector3(26.0 * s, 0.0, 0.0),
				"leg_back_lower": Vector3(28.0 * maxf(0.0, -s), 0.0, 0.0),
				"arm_upper": Vector3(20.0 * s, 0.0, 0.0),
				"arm_lower": Vector3(-10.0 - 8.0 * maxf(0.0, -s), 0.0, 0.0),
				"arm_back_upper": Vector3(-20.0 * s, 0.0, 0.0),
				"arm_back_lower": Vector3(-10.0 - 8.0 * maxf(0.0, s), 0.0, 0.0),
			}
		"work":
			var w := sin(TAU * t / WORK_PERIOD)
			return {
				"torso": Vector3(9.0 + 2.0 * w, 0.0, 0.5 * absf(w)),
				"head": Vector3(8.0, 0.0, 0.0),
				"arm_upper": Vector3(-48.0 + 20.0 * w, 0.0, 0.0),
				"arm_lower": Vector3(-48.0 + 18.0 * w, 0.0, 0.0),
				"arm_back_upper": Vector3(-36.0 - 16.0 * w, 0.0, 0.0),
				"arm_back_lower": Vector3(-50.0 - 10.0 * w, 0.0, 0.0),
				"leg_upper": Vector3(-6.0, 0.0, 0.0),
				"leg_lower": Vector3(8.0, 0.0, 0.0),
				"leg_back_upper": Vector3(6.0, 0.0, 0.0),
			}
		"eat":
			var e := (1.0 - cos(TAU * t / EAT_PERIOD)) * 0.5
			return {
				"torso": Vector3(4.0, 0.0, 0.6 * breath),
				"head": Vector3(-4.0 + 8.0 * e, 0.0, 0.0),
				"arm_upper": Vector3(-20.0 - 25.0 * e, 0.0, 0.0),
				"arm_lower": Vector3(-35.0 - 95.0 * e, 0.0, 0.0),
				"arm_back_upper": Vector3(-28.0, 0.0, 0.0),
				"arm_back_lower": Vector3(-75.0, 0.0, 0.0),
			}
		"sit":
			# The hips drop by the thigh's length, so the feet stay on the ground.
			return {
				"torso": Vector3(-2.0, 0.0, thigh * 0.97 / unit + 0.6 * breath),
				"head": Vector3(2.0 * breath, 0.0, 0.0),
				"leg_upper": Vector3(-86.0, 0.0, 0.0),
				"leg_lower": Vector3(86.0, 0.0, 0.0),
				"leg_back_upper": Vector3(-80.0, 0.0, 0.0),
				"leg_back_lower": Vector3(80.0, 0.0, 0.0),
				"arm_upper": Vector3(-22.0 + 2.0 * breath, 0.0, 0.0),
				"arm_lower": Vector3(-45.0, 0.0, 0.0),
				"arm_back_upper": Vector3(-18.0, 0.0, 0.0),
				"arm_back_lower": Vector3(-40.0, 0.0, 0.0),
			}
		"sleep":
			return {
				"torso": Vector3(0.0, 0.0, 0.8 * breath),
				"head": Vector3(-6.0, 0.0, 0.0),
				"leg_upper": Vector3(-18.0, 0.0, 0.0),
				"leg_lower": Vector3(24.0, 0.0, 0.0),
				"leg_back_upper": Vector3(-12.0, 0.0, 0.0),
				"leg_back_lower": Vector3(18.0, 0.0, 0.0),
				"arm_upper": Vector3(-12.0, 0.0, 0.0),
				"arm_lower": Vector3(-30.0, 0.0, 0.0),
			}
		"wave":
			var v := sin(TAU * t / WAVE_PERIOD)
			return {
				"torso": Vector3(-2.0, 0.0, 0.0),
				"head": Vector3(-6.0, 0.0, 0.0),
				"arm_upper": Vector3(-150.0 + 8.0 * v, 0.0, 0.0),
				"arm_lower": Vector3(-25.0 + 30.0 * v, 0.0, 0.0),
				"arm_back_upper": Vector3(4.0, 0.0, 0.0),
			}
	return {
		"torso": Vector3(0.0, 0.0, 0.7 * breath),
		"head": Vector3(1.5 * breath, 0.0, 0.0),
		"arm_upper": Vector3(2.0 * breath, 0.0, 0.0),
		"arm_back_upper": Vector3(-2.0 * breath, 0.0, 0.0),
		"arm_lower": Vector3(-6.0, 0.0, 0.0),
		"arm_back_lower": Vector3(-6.0, 0.0, 0.0),
	}


## Facing the camera or turned away: walking lifts each leg in turn (it cannot swing it
## sideways) with the arms swaying a little; anything else stands breathing.
const FRONT_WALK_PERIOD := 0.6
## How far (offset units: a torso is 100) a knee comes up, and the body with each step.
const FRONT_LIFT := 14.0
const FRONT_BOB := 5.0
func _pose_facing(name: String, t: float, breath: float) -> Dictionary:
	if name == "walk":
		var ph := fmod(t, FRONT_WALK_PERIOD) / FRONT_WALK_PERIOD
		var s := sin(TAU * ph)
		# Each step lifts the body (a clear bob, feet and all) and one knee well up.
		var bob := -FRONT_BOB * absf(s)
		return {
			"torso": Vector3(2.5 * s, 0.0, bob),
			"head": Vector3(-2.0 * s, 0.0, 0.0),
			"leg_upper": Vector3(0.0, 0.0, -FRONT_LIFT * maxf(0.0, s)),
			"leg_back_upper": Vector3(0.0, 0.0, -FRONT_LIFT * maxf(0.0, -s)),
			"arm_upper": Vector3(-12.0 * s, 0.0, 0.0),
			"arm_back_upper": Vector3(-12.0 * s, 0.0, 0.0),
		}
	return {
		"torso": Vector3(0.0, 0.0, 0.8 * (breath * 0.5 + 0.5)),
		"head": Vector3(1.5 * breath, 0.0, 0.0),
	}
