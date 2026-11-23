extends SceneTree
## godot --path game -s res://tools/carry_shots.gd -- <out_dir>
## Dev tool: one adult picks up a string of coins in the yard and carries it to the
## keepsake chest; saves a screenshot every half second (on screen, so it needs a window).

var m: Main
var out := ""
var t := 0.0
var n := 0
var started := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if not args.is_empty() else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var dir := "user://carry_shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	m = Main.create("qijia", dir)
	root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)


func _process(delta: float) -> bool:
	var w := m.session.world
	t += delta
	if not started and t > 1.0:
		started = true
		w.pack.config["collectible_interval_min"] = 99999
		var p: Person = w.people[0]
		var uid := CollectibleSystem.spawn(w, "coins", "yard")
		AutonomySystem.start(w, p, "pick_up", -1, uid)
		m.select(p.uid)
	if started and fmod(t, 0.5) < delta:
		root.get_viewport().get_texture().get_image().save_png("%s/shot_%03d.png" % [out, n])
		n += 1
	return t > 22.0
