extends SceneTree
## godot --path game -s res://tools/kitchen_shot.gd -- <out.png> [zoom] [hour]
## Dev tool: a new game with the kitchen furnished (stove, vat, two stools by the cupboard),
## the view on the kitchen, one screenshot (needs a window).

var m: Main
var out := ""
var zoom := 1.6
var t := 0.0
var hour := -1.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if not args.is_empty() else "user://kitchen.png"
	if args.size() > 1:
		zoom = float(args[1])
	if args.size() > 2:
		hour = float(args[2])
	var dir := "user://kitchen_shot/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	m = Main.create("qijia", dir)
	if hour >= 0.0:
		# The clock's time zone moved so the local hour is `hour`.
		var unix := int(Time.get_unix_time_from_system())
		var off := int(hour * 3600.0) - posmod(unix, 86400)
		m.session._real_clock = func() -> Dictionary: return {"unix": Time.get_unix_time_from_system(), "offset": off}
	root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	w.add_object("stool", "kitchen", 6, 5)
	w.add_object("vat", "kitchen", 8, 0)
	w.add_object("stool", "kitchen", 3, 3)
	m.tick(0.016)


func _process(delta: float) -> bool:
	t += delta
	if t > 0.5 and t - delta <= 0.5:
		m.overlays.press(str(m.overlays._buttons.keys()[0])) if m.overlays.current() != "" else null
	if t > 1.0 and t - delta <= 1.0:
		var h := m.house
		h.follow_uid = -1
		h.zoom_to(h.scale.x * zoom)
		h.pan(h._area_centre() - h.to_screen(h.layout.cell_center("kitchen", 4, 3)))
	if t > 1.0:
		# Someone standing by the stove for scale (held there each frame).
		var h2 := m.house
		var k := 0
		for uid in h2.people:
			var pv: Node2D = h2.people[uid]
			pv.position = h2.layout.cell_center("kitchen", 3 + k * 3, 2 + k * 2)
			k += 1
			if k >= 2:
				break
	if t > 3.0:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
