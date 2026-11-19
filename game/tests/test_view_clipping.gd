extends TestCase
## Nothing stands in anything (穿模): people stop beside furniture, never on it nor on a wall
## line; walks go round furniture; everything standing sorts by its foot; pictures keep to
## their footprint; name plates do not overlap. And people move: the cutout rigs and poses.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_clip_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	# (The hall's own table and altar are already there, where the pack puts them.)
	for e in [["stool", "yard", 8, 1],
			["bookshelf", "hall", 0, 2], ["loom", "bedroom", 3, 3], ["clothesline", "yard", 5, 5]]:
		w.add_object(e[0], e[1], e[2], e[3])
	for i in 3:
		w.add_person(FamilySystem.make_person(w, [20, 40]))
	m.tick(0.016)
	return m


func _footprints(m: Main) -> Array:
	var out: Array = []
	var w := m.session.world
	for o in w.objects:
		if str(o.room) in w.rooms_built:
			out.append(m.house.layout.object_rect(o, w.pack))
	return out


func _on_wall_line(site: HouseSite, p: Vector2) -> bool:
	var c := site.cell_of(p)
	var lo := Vector2(c) * HouseSite.CELL
	var hi := lo + HouseSite.CELL
	return (p.x - lo.x < 8.0 and site.v_walls.has(Vector2i(c.x, c.y))) \
		or (hi.x - p.x < 8.0 and site.v_walls.has(Vector2i(c.x + 1, c.y))) \
		or (p.y - lo.y < 8.0 and site.h_walls.has(Vector2i(c.x, c.y))) \
		or (hi.y - p.y < 8.0 and site.h_walls.has(Vector2i(c.x, c.y + 1)))


func test_use_spots_are_beside_the_piece_never_on_it_nor_across_a_wall():
	var m := _main()
	var w := m.session.world
	var l := m.house.layout
	var feet := _footprints(m)
	for o in w.objects:
		if not str(o.room) in w.rooms_built:
			continue
		var at := l.stand_pos(o, w.pack)
		for r in feet:
			assert_true(not (r as Rect2).grow(-1.0).has_point(at), "%s stands on furniture at %s" % [o.type, at])
		assert_true(l.site.can_stop(at), "%s %s" % [o.type, at])
		assert_true(not _on_wall_line(l.site, at), "%s on a wall line %s" % [o.type, at])
		# Next to its own piece, nothing between.
		var r0 := l.object_rect(o, w.pack)
		assert_true(r0.grow(HouseSite.CELL.y).has_point(at), "%s too far: %s" % [o.type, at])
	m.free()


func test_stop_points_are_open_and_off_wall_lines_everywhere():
	var m := _main()
	var site := m.house.layout.site
	var feet := _footprints(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var p := Vector2(rng.randf_range(11 * 48, 45 * 48), rng.randf_range(6 * 36, 25 * 36))
		var s := site.stop_point(p)
		assert_true(site.walkable(site.cell_of(s)), str(p))
		assert_true(not _on_wall_line(site, s), "%s -> %s" % [p, s])
		for r in feet:
			assert_true(not (r as Rect2).grow(-1.0).has_point(s), "%s -> %s on furniture" % [p, s])
	m.free()


func test_people_never_stop_on_furniture_or_wall_lines():
	var m := _main()
	var w := m.session.world
	var site := m.house.layout.site
	var feet := _footprints(m)
	for step in 40:
		clk.unix += 60.0
		m.tick(0.5)
		for uid in m.house.people:
			var pv: PersonView = m.house.people[uid]
			if pv.on_object:
				continue
			assert_true(not _on_wall_line(site, pv.target), "%s target %s" % [pv.doing_text(), pv.target])
			for r in feet:
				assert_true(not (r as Rect2).grow(-1.0).has_point(pv.target), "%s target on furniture %s" % [pv.doing_text(), pv.target])
	m.free()


func test_routes_go_round_furniture():
	var m := _main()
	var site := m.house.layout.site
	assert_true(site.furniture.size() > 10)
	for c in site.furniture:
		assert_true(site.blocked.has(c))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var open: Array = []
	for y in range(6, 25):
		for x in range(11, 45):
			if site.walkable(Vector2i(x, y)):
				open.append(Vector2i(x, y))
	for i in 60:
		var a: Vector2 = site.centre(open[rng.randi_range(0, open.size() - 1)])
		var b: Vector2 = site.centre(open[rng.randi_range(0, open.size() - 1)])
		var pts := site.route(a, b)
		var at := a
		var ok := true
		for p in pts:
			ok = ok and site.clear_line(at, p)
			at = p
		if pts.is_empty() and not site.clear_line(a, b):
			continue  # no way at all (walled off): walks straight, as before
		assert_true(ok and site.clear_line(at, b), "%s -> %s" % [a, b])
	# The dining table stands between: the straight line through it is not clear.
	var table := m.house.layout.object_rect(m.session.world.objects.filter(func(o): return o.type == "dining_table")[0], m.session.world.pack)
	assert_true(not site.clear_line(Vector2(table.position.x - 30, table.get_center().y), Vector2(table.end.x + 30, table.get_center().y)))
	m.free()


## The 45° view sorts everything standing by how far in front it is (view y of its foot):
## a back wall is drawn before whoever stands in the room in front of it and after whoever
## stands outside behind it; a cut wall is drawn after the room's front row (it is only
## ankle-high) and before whoever stands outside it.
func test_walls_sort_with_the_people_by_depth():
	var m := _main()
	var house := m.house
	var pv: PersonView = house.people.values()[0]
	var checked := 0
	for wp in house.walls:
		if wp.role != "wall" or wp.open or wp.kind == HouseSite.FENCE:
			continue
		var inside := Vector2i(wp.at, wp.line) if wp.along == "x" else Vector2i(wp.line, wp.at)
		var outside := inside - (Vector2i(0, 1) if wp.along == "x" else Vector2i(1, 0))
		var d := house.sort_depth(wp)
		pv.position = HouseSite.CELL * (Vector2(inside) + Vector2(0.5, 0.5))
		assert_true(house.sort_depth(pv) > d, "in front of %s %s %s" % [wp.along, wp.line, wp.at])
		pv.position = HouseSite.CELL * (Vector2(outside) + Vector2(0.5, 0.5))
		assert_true(house.sort_depth(pv) < d, "behind %s %s %s" % [wp.along, wp.line, wp.at])
		if not wp.tall:
			assert_true(wp.height <= IsoWall.COMPOUND_LOW, "cut to the ankle")
		checked += 1
	assert_true(checked > 50)
	# Long furniture against a back wall is drawn over every stretch of wall behind it.
	var w := m.session.world
	for o in w.objects:
		if not house.props.has(int(o.uid)):
			continue
		var c := HouseLayout.cells_of(house.layout.object_rect(o, w.pack))
		for wp in house.walls:
			if wp.role == "wall" and wp.tall and wp.along == "x" and wp.line == c.position.y and wp.at >= c.position.x and wp.at < c.end.x:
				assert_true(house.sort_depth(house.props[int(o.uid)]) > house.sort_depth(wp), str(o.type))
	m.free()


func test_the_gatehouse_fades_for_someone_under_it():
	var m := _main()
	var gate: IsoWall = null
	for wp in m.house.walls:
		if wp.role == "gate":
			gate = wp
	assert_true(gate != null)
	var pv: PersonView = m.house.people.values()[0]
	pv.held = true
	pv.position = Vector2(28 * 48, 25 * 36 - 20)
	m.house.tick(0.016)
	assert_true(gate.modulate.a < 1.0, "someone in the gateway")
	pv.position = Vector2(20 * 48, 15 * 36)
	m.house.tick(0.016)
	assert_eq(gate.modulate.a, 1.0)
	m.free()


## The 45° view: a picture stays within its footprint's diamond across the screen and stands
## on its bottom corner, so it never reaches over a wall beside it.
func test_pictures_keep_to_their_footprint_and_off_walls():
	var m := _main()
	var w := m.session.world
	for uid in m.house.props:
		var piece: PropPiece = m.house.props[uid]
		var o := w.object(uid)
		var r := m.house.layout.object_rect(o, w.pack)
		var d := IsoMath.diamond(r)
		var pic := Rect2(IsoMath.to_view(piece.position) + piece.rect.position, piece.rect.size)
		assert_true(pic.position.x >= d[3].x - 0.01 and pic.end.x <= d[1].x + 0.01, str(o.type))
		assert_true(pic.end.y <= d[2].y + 6.01, str(o.type))
	m.free()


func test_name_plates_do_not_overlap_and_only_the_selected_shows_the_action():
	var m := _main()
	var at := m.house.layout.cell_center("yard", 4, 3)
	for uid in m.house.people:
		var pv: PersonView = m.house.people[uid]
		pv.held = true
		pv.position = at + Vector2(randf_range(-6, 6), randf_range(-4, 4))
	var first: int = m.house.people.keys()[0]
	m.select(first)
	var spots := m.house.label_spots()
	var rects: Array = []
	for uid in spots:
		var size: Vector2 = m.house.people[uid].label_size()
		rects.append(Rect2(spots[uid] - Vector2(size.x * 0.5, size.y), size))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_true(not (rects[i] as Rect2).intersects(rects[j]), "plates %d and %d overlap" % [i, j])
	var sel: PersonView = m.house.people[first]
	var other: PersonView = m.house.people[m.house.people.keys()[1]]
	assert_true(sel.label_size().y > other.label_size().y, "the selected plate has the action line")
	m.free()


func test_rigs_load_and_poses_move():
	var m := _main()
	var skin := m.house.skin
	var look := skin.person_look("adult", "male")
	assert_true(look.has("rig"), "the father has a rig")
	var rig: CutoutRig = look.rig
	assert_true(rig.has_part("leg_back_upper") and rig.height > 100.0 and rig.thigh > 0.0)
	var a := rig.world(rig.pose("walk", 0.0))
	var b := rig.world(rig.pose("walk", CutoutRig.WALK_PERIOD * 0.25))
	assert_true(not (a["leg_lower"] as Transform2D).is_equal_approx(b["leg_lower"]), "legs swing")
	var w0 := rig.world(rig.pose("work", 0.0))
	var w1 := rig.world(rig.pose("work", CutoutRig.WORK_PERIOD * 0.25))
	assert_true(not (w0["arm_lower"] as Transform2D).is_equal_approx(w1["arm_lower"]), "arms work")
	# Sitting drops the hips by the thigh: the feet stay on the ground.
	var sit := rig.world(rig.pose("sit", 0.0))
	var rest := rig.world({})
	assert_true((sit["torso"] as Transform2D).origin.y > (rest["torso"] as Transform2D).origin.y + rig.thigh * 0.8)
	m.free()


func test_actions_pick_poses_from_the_pack():
	var m := _main()
	var w := m.session.world
	var p := TestKit.adult(w)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	var kang: Dictionary = w.objects.filter(func(o): return o.type == "kang")[0]
	AutonomySystem.start(w, p, "sleep", int(kang.uid))
	pv.refresh()
	assert_eq(pv.action_pose, "sleep")
	assert_true(pv.on_object, "lies on the kang")
	pv.position = pv.target
	assert_eq(pv.body_pose(), "sleep")
	assert_true(pv.drawn_height() < 40.0)
	AutonomySystem.start(w, p, "sweep", -1)
	pv.refresh()
	assert_eq(pv.action_pose, "work")
	assert_true(not pv.on_object)
	var stool: Dictionary = w.objects.filter(func(o): return o.type == "stool")[0]
	AutonomySystem.start(w, p, "shell_beans", int(stool.uid))
	pv.refresh()
	assert_eq(pv.action_pose, "sit")
	assert_true(pv.on_object)
	pv.position = pv.target
	assert_true(pv.drawn_height() < pv.body_size().y - 10.0, "sitting is lower")
	m.free()


## The 45° view: a cell is a 64 x 32 diamond; plan x runs down-right, plan y down-left; a
## click lands back on the plan point under it. The smoke pack (no art, no site) keeps the
## view from above.
func test_the_view_is_a_45_degree_projection_of_the_plan():
	var m := _main()
	assert_true(m.house.iso)
	assert_eq(IsoMath.to_view(Vector2(48, 0)), Vector2(32, 16))
	assert_eq(IsoMath.to_view(Vector2(0, 36)), Vector2(-32, 16))
	assert_true(IsoMath.to_plan(IsoMath.to_view(Vector2(123, 45))).distance_to(Vector2(123, 45)) < 0.001)
	for s in [0.5, 1.0, 1.7]:
		m.house.zoom_to(s)
		var p := Vector2(25 * 48 + 7, 9 * 36 + 11)
		assert_true(m.house.world_pos(m.house.to_screen(p)).distance_to(p) < 0.001)
	var smoke := Main.create("_smoke", "user://test_clip_smoke/", _clock)
	assert_true(not smoke.house.iso)
	assert_eq(smoke.house.proj, Transform2D.IDENTITY)
	smoke.free()
	m.free()


## People turn with the way they walk: down the screen towards the camera (the front rig),
## up it away (the back rig), across it sideways; at furniture the side rig, turned to it.
func test_people_turn_to_the_camera_or_away_as_they_walk():
	var m := _main()
	var w := m.session.world
	var p := TestKit.adult(w)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	var look := m.house.skin.person_look(p.stage(w.pack), p.gender)
	assert_true(look.has("rig_front") and look.has("rig_back"), "the facing rigs are there")
	assert_eq((look.rig_front as CutoutRig).facing, "front")
	assert_eq((look.rig_back as CutoutRig).facing, "back")
	pv._turn(Vector2(48, 36))  # south-east: straight down the screen
	assert_eq(pv.turned, "front")
	assert_eq(pv._rig_for("walk")[0], look.rig_front)
	pv._turn(Vector2(-48, -36))  # north-west: up the screen
	assert_eq(pv.turned, "back")
	assert_eq(pv._rig_for("walk")[0], look.rig_back)
	pv._turn(Vector2(48, -36))  # north-east: straight right
	assert_eq(pv.turned, "side")
	assert_eq(pv._facing, 1.0)
	assert_eq(pv._rig_for("walk")[0], look.rig)
	pv._turn(Vector2(0, 36))  # south: down-left, towards the camera
	assert_eq(pv.turned, "front")
	assert_eq(pv._facing, -1.0)
	# Sitting, working, eating: always the side rig.
	assert_eq(pv._rig_for("work")[0], look.rig)
	assert_eq(pv._rig_for("sit")[0], look.rig)
	# The front walk lifts the legs in turn instead of swinging them.
	var front: CutoutRig = look.rig_front
	var a := front.pose("walk", 0.15)
	var b := front.pose("walk", 0.45)
	assert_true((a["leg_upper"] as Vector3).z < 0.0 and (b["leg_back_upper"] as Vector3).z < 0.0)
	assert_eq((a["leg_upper"] as Vector3).x, 0.0)
	m.free()


## A picture's rect on the view, less the transparent margin round the drawing.
func _pic(house: HouseView, p: PropPiece) -> Rect2:
	var r := Rect2(IsoMath.to_view(p.position) + p.rect.position, p.rect.size)
	return r.grow_individual(-r.size.x * 0.12, -r.size.y * 0.12, -r.size.x * 0.12, -r.size.y * 0.04)


## Every room built, the pack's own furniture where it puts it: no two pictures overlap by
## more than a sliver (5 % of the smaller), and no scenery stands over the gatehouse.
func test_default_furniture_pictures_do_not_overlap():
	var n2 := "user://test_clip_layout/"
	DirAccess.make_dir_recursive_absolute(n2)
	for f in DirAccess.get_files_at(n2):
		DirAccess.remove_absolute(n2 + f)
	var m := Main.create("qijia", n2, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	w.money = 100000
	for id in w.pack.rooms:
		if not id in w.rooms_built:
			m.session.command({"type": "build_room", "room": id})
	m.tick(0.016)
	var uids: Array = m.house.props.keys()
	assert_true(uids.size() > 15)
	for i in uids.size():
		for j in range(i + 1, uids.size()):
			var a := _pic(m.house, m.house.props[uids[i]])
			var b := _pic(m.house, m.house.props[uids[j]])
			var x := a.intersection(b)
			var frac := x.get_area() / minf(a.get_area(), b.get_area()) if x.has_area() else 0.0
			assert_true(frac <= 0.05, "%s / %s overlap %.2f" % [w.object(uids[i]).type, w.object(uids[j]).type, frac])
	for wp in m.house.walls:
		if wp.role == "gate":
			for s in m.house.scenery:
				assert_true(not _pic(m.house, s).intersects(wp.view_box), "scenery over the gatehouse at %s" % (s.position / HouseSite.CELL))
	m.free()


## The 45° view: a point on the upper part of a furniture picture (over the floor behind its
## footprint) picks that piece, for drops and arrange mode.
func test_a_point_on_a_tall_picture_picks_the_furniture():
	var m := _main()
	var w := m.session.world
	var o: Dictionary = w.objects.filter(func(x): return x.type == "grape_trellis")[0]
	var p: PropPiece = m.house.props[int(o.uid)]
	var top := IsoMath.to_view(p.position) + Vector2(p.rect.get_center().x, p.rect.position.y + p.rect.size.y * 0.25)
	var plan := IsoMath.to_plan(top)
	assert_true(not m.house.layout.object_rect(o, w.pack).has_point(plan), "the cell under is behind the piece")
	var hit := m.house.pick(w, plan)
	assert_eq(str(hit.kind), "object")
	assert_eq(int(hit.uid), int(o.uid))
	m.free()


## Walking takes as long on the screen whichever way: a step east covers as many screen
## pixels as a step south.
func test_walking_speed_is_even_on_the_screen():
	var m := _main()
	var pv: PersonView = m.house.people.values()[0]
	var start := m.house.layout.cell_center("yard", 3, 3)
	var dist := []
	for d in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		pv.position = start
		pv.target = start + d * 400.0
		pv.path = PackedVector2Array()
		pv._path_goal = pv.target
		pv._path_from = pv.position
		pv.walk(30.0)
		dist.append(IsoMath.basis().basis_xform(pv.position - start).length())
	assert_near(dist[0], dist[1], 0.01)
	assert_near(dist[1], dist[2], 0.01)
	m.free()


## The rooms' names lie on a free part of the floor, clear of every furniture picture.
func test_room_names_are_clear_of_the_furniture():
	var m := _main()
	var font := ThemeDB.fallback_font
	for id in ["hall", "kitchen", "bedroom", "woodshed"]:
		var rect := m.house.layout.room_rect(id)
		var name := str(m.session.world.pack.rooms[id]["name"])
		var wdt := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var at := m.house.ground.free_label_spot(rect, wdt, 16, Vector2(INF, INF))
		assert_true(at.x != INF, id)
		var box := Rect2(IsoMath.to_view(at) + Vector2(0, -16), Vector2(wdt, 20))
		for uid in m.house.props:
			var r: Rect2 = _pic(m.house, m.house.props[uid])
			assert_true(not r.intersects(box), "%s name under %s" % [id, m.session.world.object(uid).type])
	m.free()
