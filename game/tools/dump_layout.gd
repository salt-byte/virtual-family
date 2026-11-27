extends SceneTree
## godot --headless --path game -s res://tools/dump_layout.gd -- <out.json>
## Dev tool: a new game (the kitchen furnished as in kitchen_shot.gd), its plan as JSON in
## map cells for the white-model scene (assets/blender/build_white_scene.py): the site's size,
## the compound, rooms {id, x, y, w, h, indoor, built}, wall runs {along, line, a, b, kind,
## open: [cells]}, furniture {type, room, cell: [x, y] in the room, x, y, w, h in the map}, the
## pack's real sizes (metres) and metres per cell, and where the people stand.


var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_dump()
	return true


func _dump() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://layout.json"
	var dir := "user://dump_layout/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	var m := Main.create("qijia", dir)
	root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	w.add_object("stove", "kitchen", 2, 0)
	w.add_object("vat", "kitchen", 5, 0)
	w.add_object("stool", "kitchen", 2, 2)
	w.add_object("stool", "kitchen", 4, 3)
	m.tick(0.016)
	var h: HouseView = m.house
	var site := h.layout.site
	var cell := HouseSite.CELL
	var rooms := []
	for rid in w.pack.rooms:
		var r: Dictionary = w.pack.rooms[rid]
		var rr: Rect2 = h.layout.room_rect(str(rid))
		rooms.append({"id": rid, "name": r.get("name", ""), "x": rr.position.x / cell.x, "y": rr.position.y / cell.y,
			"w": rr.size.x / cell.x, "h": rr.size.y / cell.y, "indoor": not bool(r.get("outdoor", false)),
			"built": site.built_indoor(str(rid)) or bool(r.get("outdoor", false))})
	var walls := []
	for run in site.runs():
		var open := []
		for at in range(int(run.a), int(run.b)):
			if site.is_open(str(run.along), int(run.line), at):
				open.append(at)
		run["open"] = open
		walls.append(run)
	var things := []
	for o in w.objects:
		var r := h.layout.object_rect(o, w.pack)
		things.append({"type": o.type, "room": o.room, "cell": [int(o.x), int(o.y)],
			"x": r.position.x / cell.x, "y": r.position.y / cell.y, "w": r.size.x / cell.x, "h": r.size.y / cell.y})
	var people := []
	for p in w.people:
		if p.alive:
			var pv: Node2D = h.people.get(p.uid)
			if pv != null:
				people.append({"uid": p.uid, "x": pv.position.x / cell.x, "y": pv.position.y / cell.y})
	var iso: Dictionary = h.skin._table("iso")
	var data := {"size": [site.size.x, site.size.y],
		"compound": [site.compound.position.x, site.compound.position.y, site.compound.size.x, site.compound.size.y],
		"rooms": rooms, "walls": walls, "things": things, "people": people,
		"sizes": iso.get("sizes", {}), "metres_per_cell": iso.get("metres_per_cell", 0.7)}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("WROTE ", out, " rooms ", rooms.size(), " walls ", walls.size(), " things ", things.size(), " people ", people.size())
