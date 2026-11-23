extends SceneTree
## godot --path game -s res://tools/house_shot.gd -- <out.png> [furniture_scale] [figure_scale]
## Dev tool: a new game's house a few seconds in, one screenshot (needs a window). With a
## scale, the pack's iso.furniture_scale is set to it first.

var m: Main
var out := ""
var t := 0.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if not args.is_empty() else "user://house.png"
	var dir := "user://house_shot/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	m = Main.create("qijia", dir)
	if args.size() > 1:
		m.house.skin._data["iso"]["furniture_scale"] = float(args[1])
	if args.size() > 2:
		m.house.skin._data["iso"]["figure_scale"] = float(args[2])
	root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)


func _process(delta: float) -> bool:
	t += delta
	if t > 0.5 and t - delta <= 0.5:
		m.overlays.press(str(m.overlays._buttons.keys()[0])) if m.overlays.current() != "" else null
	if t > 3.0:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
