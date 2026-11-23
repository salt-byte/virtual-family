extends SceneTree
## godot --path game -s res://tools/rig_sheet.gd -- <out.png> [pose,pose,...] [look,look,...]
## Dev tool: the three-quarter (front34) rigs side by side at the heights the game draws
## them (times ZOOM), one row per pose, the pose frozen a third of the way into its cycle.
## Needs a window (it renders).

const ZOOM := 1.6
var out := ""
var poses := ["idle", "walk", "stoop", "carry", "stow", "wave"]
var looks := ["father", "mother", "child", "adult_5", "elder_2"]
var n := 0


class Sheet extends Node2D:
	var rigs: Array = []   # [rig, height, x]
	var poses: Array = []
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 2000, 2000), Color("#F4ECDD"))
		for r in poses.size():
			var y := 40.0 + (r + 1) * 105.0 * 1.6
			draw_string(ThemeDB.fallback_font, Vector2(8, y - 120), str(poses[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.BLACK)
			for e in rigs:
				var rig: CutoutRig = e[0]
				var k: float = float(e[1]) * 1.6 / rig.height
				var pose := rig.pose(str(poses[r]), 0.24)
				rig.draw(self, pose, Transform2D(0.0, Vector2(k, k), 0.0, Vector2(e[2], y)))
				draw_line(Vector2(e[2] - 40, y), Vector2(e[2] + 40, y), Color(0, 0, 0, 0.3), 2)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if not args.is_empty() else "user://rig_sheet.png"
	if args.size() > 1:
		poses = args[1].split(",")
	if args.size() > 2:
		looks = args[2].split(",")
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://packs/qijia/art.json"))
	var all: Array = []
	for l in art["people"]:
		all.append(l)
	for l in art.get("looks", {}).values() if art.get("looks") is Dictionary else []:
		all.append(l)
	var sheet := Sheet.new()
	sheet.poses = poses
	var x := 150.0
	for id in looks:
		for l in all:
			var name := str(l.get("sprite", l.get("id", "")))
			var rp := str(l.get("rig_front34", ""))
			if (name == id or rp.contains("/" + id + "_front34/")) and rp != "":
				var rig := CutoutRig.load_file("res://packs/qijia/art/" + rp)
				if rig != null:
					sheet.rigs.append([rig, float(l.get("height", 90)), x])
					x += 190.0
				break
	root.add_child(sheet)
	print("size ", int(x), "x", int(60 + (poses.size() + 1) * 315))


func _process(_d: float) -> bool:
	n += 1
	if n == 4:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
