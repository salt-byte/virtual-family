extends SceneTree
## godot --path game -s res://tools/room_shot.gd -- <out.png> <room> <cell_x> <cell_y> [zoom] [hour]
## Dev tool: a new game (its starting furniture only), the view centred on a cell of a room,
## a person standing there for scale, one screenshot (needs a window).
## Extra args after the hour: build:<room> builds a room first, put:<type>:<room>:<x>:<y>
## places a piece (the family is given the money for both).

var m: Main
var out := ""
var room := ""
var cell := Vector2i.ZERO
var zoom := 2.0
var t := 0.0
var hour := -1.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	room = args[1]
	cell = Vector2i(int(args[2]), int(args[3]))
	if args.size() > 4:
		zoom = float(args[4])
	if args.size() > 5:
		hour = float(args[5])
	var dir := "user://room_shot/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	m = Main.create("qijia", dir)
	if hour >= 0.0:
		var unix := int(Time.get_unix_time_from_system())
		var off := int(hour * 3600.0) - posmod(unix, 86400)
		m.session._real_clock = func() -> Dictionary: return {"unix": Time.get_unix_time_from_system(), "offset": off}
	root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	for a in args.slice(6):
		var p: PackedStringArray = a.split(":")
		m.session.world.money += 10000
		var r: Dictionary = {}
		if p[0] == "build":
			r = m.session.command({"type": "build_room", "room": p[1]})
		elif p[0] == "put":
			r = m.session.command({"type": "place", "object_type": p[1], "room": p[2], "x": int(p[3]), "y": int(p[4])})
		if not r.get("ok", false):
			push_warning("room_shot %s: %s" % [a, r])
	m.tick(0.016)


func _process(delta: float) -> bool:
	t += delta
	if t > 0.5 and t - delta <= 0.5:
		m.overlays.press(str(m.overlays._buttons.keys()[0])) if m.overlays.current() != "" else null
	if t > 1.0 and t - delta <= 1.0:
		var h := m.house
		h.follow_uid = -1
		h.zoom_to(h.scale.x * zoom)
		h.pan(h._area_centre() - h.to_screen(h.layout.cell_center(room, cell.x, cell.y)))
	if t > 1.0:
		var h2 := m.house
		for uid in h2.people:
			var pv: Node2D = h2.people[uid]
			pv.position = h2.layout.cell_center(room, cell.x + 1, cell.y + 1)
			break
	if t > 3.0:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
