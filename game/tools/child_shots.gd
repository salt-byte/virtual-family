extends SceneTree
## godot --path game -s res://tools/child_shots.gd -- <out_dir>
## Dev tool: the family with a girl of 8 standing among them; one screenshot with the camera
## on her (on screen, so it needs a window).

var m: Main
var out := ""
var t := 0.0
var kid: Person


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if not args.is_empty() else "user://shots"
	var dir := "user://child_shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	m = Main.create("qijia", dir)
	root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	kid = TestKit.adult(w, 8.0)
	kid.gender = "female"
	kid.given = "小满"
	kid.family = w.people[0].family
	m.tick(0.016)


func _process(delta: float) -> bool:
	t += delta
	if t > 1.5 and t - delta <= 1.5:
		m.select(kid.uid)
	if t > 4.0:
		root.get_viewport().get_texture().get_image().save_png(out + "/child.png")
		return true
	return false
