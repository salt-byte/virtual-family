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
		# A door sill is stepped over (art.json `poses.step_over`): standing on it is fine.
		if str(o.room) in w.rooms_built and not m.house.skin.step_over(str(o.type)):
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


## People are seen at 45°, never head-on: walking up the screen they turn away, three-quarters
## (the back34 rig); walking down or across it, standing, working, sitting, eating they turn
## three-quarters towards the camera (front34), mirrored by the way they go or face. Lying
## down is the side rig. A look without the three-quarter rigs falls back to the back rig
## walking up and the side rig otherwise; the head-on front rig is not used.
func test_people_turn_three_quarters_as_they_walk():
	var m := _main()
	var w := m.session.world
	var p := TestKit.adult(w)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	var look := m.house.skin.person_look(p.stage(w.pack), p.gender)
	assert_true(look.has("rig_front34") and look.has("rig_back34"), "the three-quarter rigs are there")
	assert_eq((look.rig_front34 as CutoutRig).facing, "front34")
	assert_eq((look.rig_back34 as CutoutRig).facing, "back34")
	pv._turn(Vector2(48, 36))  # south-east: straight down the screen
	assert_eq(pv.turned, "front34", "not head-on to the camera")
	assert_eq(pv._rig_for("walk")[0], look.rig_front34)
	pv._turn(Vector2(0, 36))  # south: down-left
	assert_eq(pv.turned, "front34")
	assert_eq(pv._facing, -1.0, "mirrored")
	pv._turn(Vector2(48, -36))  # north-east: straight right
	assert_eq(pv.turned, "front34")
	assert_eq(pv._facing, 1.0)
	pv._turn(Vector2(0, -36))  # north: up-right, away
	assert_eq(pv.turned, "back34")
	assert_eq(pv._rig_for("walk")[0], look.rig_back34)
	pv._turn(Vector2(-48, 0))  # west: up-left
	assert_eq(pv.turned, "back34")
	assert_eq(pv._facing, -1.0)
	pv._turn(Vector2.ZERO)  # standing about: towards the camera, still facing left
	assert_eq(pv.turned, "front34")
	assert_eq(pv._facing, -1.0)
	for bp in ["idle", "work", "sit", "eat", "wave"]:
		assert_eq(pv._rig_for(bp)[0], look.rig_front34, bp)
	assert_eq(pv._rig_for("sleep")[0], look.rig, "lying down: the side rig")
	# The three-quarter rigs play the keyframed animations: the walk swings the legs, the
	# walk turned away is its own ("walk_up"), sitting drops the hips by the rig's own thigh.
	var f34: CutoutRig = look.rig_front34
	var b34: CutoutRig = look.rig_back34
	assert_true(not (f34.pose("walk", 0.0)["leg_upper"] as Vector3).is_equal_approx(f34.pose("walk", 0.18)["leg_upper"]), "legs move")
	assert_true(not (f34.pose("walk", 0.18)["leg_upper"] as Vector3).is_equal_approx(b34.pose("walk", 0.18)["leg_upper"]), "walk_up")
	assert_near((f34.pose("sit", 0.0)["torso"] as Vector3).z, f34.thigh * 0.97 / f34.unit, 0.01)
	assert_true(f34.pose("sit", 0.0).has("_z"), "near leg over the torso")
	# Without the three-quarter rigs: the back rig up the screen, the side rig otherwise.
	pv._look.erase("rig_front34")
	pv._look.erase("rig_back34")
	pv._turn(Vector2(0, -36))
	assert_eq(pv.turned, "back")
	assert_eq(pv._rig_for("walk")[0], look.rig_back)
	assert_eq(pv._rig_for("work")[0], look.rig)
	pv._turn(Vector2(0, 36))
	assert_eq(pv.turned, "side")
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


## No names on the floor: a built room shows none; an unbuilt room keeps its price on the
## floor and shows "name · price" while the pointer is on it; a place out on the map shows
## its name on hover; a built room in the compound nothing.
func test_place_names_show_on_hover_not_on_the_floor():
	var m := _main()
	var w := m.session.world
	var money := func(n): return m.session.strings.t("money").replace("{n}", str(n))
	assert_eq(m.house.place_label("hall"), "", "a built room: no name")
	var study: Dictionary = w.pack.rooms["study"]
	assert_true(not "study" in w.rooms_built)
	assert_eq(m.house.place_label("study"), "%s · %s" % [study.name, money.call(int(study.build_cost))])
	assert_eq(m.house.place_label("riverside"), str(w.pack.rooms["riverside"].name))
	# Pointing at the study's middle shows its words; at the hall, nothing.
	m.house.point_at(m.house.to_screen(m.house.layout.room_rect("study").get_center()))
	assert_eq(m.house.pointed_room, "study")
	m.house.point_at(m.house.to_screen(m.house.layout.room_rect("hall").get_center()))
	assert_eq(m.house.pointed_room, "")
	m.house.point_at(m.house.to_screen(m.house.layout.room_rect("riverside").get_center()))
	assert_eq(m.house.pointed_room, "riverside")
	m.free()


## Sitting needs a seat: an action that asks to sit, done where there is none (in the shade
## of the grape trellis), is done standing, never sitting on air.
func test_no_sitting_without_a_seat():
	var m := _main()
	var w := m.session.world
	var p := TestKit.adult(w)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	var trellis: Dictionary = w.objects.filter(func(o): return o.type == "grape_trellis")[0]
	AutonomySystem.start(w, p, "trellis_shade", int(trellis.uid))
	pv.refresh()
	assert_true(not pv.on_object)
	assert_eq(pv.action_pose, "idle")
	var stool: Dictionary = w.objects.filter(func(o): return o.type == "stool")[0]
	AutonomySystem.start(w, p, "shell_beans", int(stool.uid))
	pv.refresh()
	assert_eq(pv.action_pose, "sit", "on a stool they sit")
	# Sitting tucks the thighs under the jacket's hem.
	var rig: CutoutRig = m.house.skin.person_look("adult", "male").rig
	var z: Dictionary = rig.pose("sit", 0.0)["_z"]
	assert_true(float(z["leg_upper"]) < 3.0, "under the torso")
	m.free()


## The ring under the feet shows only while the player presses on or carries the person; a
## selected person is known by the plate over their head.
func test_the_ring_shows_only_while_pressed_or_carried():
	var m := _main()
	var pv: PersonView = m.house.people.values()[0]
	pv.held = true
	pv.position = m.house.layout.cell_center("yard", 4, 3)
	pv.held = false
	pv.target = pv.position
	m.select(pv.person.uid)
	assert_true(pv.selected)
	assert_true(not pv.ring_shown(), "selected alone: no ring")
	var at := m.house.to_screen(pv.position + Vector2(0, -2)) + Vector2(0, -30 * m.house.scale.y)
	m.house.press(at)
	assert_eq(m.house.pressing_uid(), pv.person.uid)
	assert_true(pv.ring_shown(), "pressed on")
	m.house.release(at)
	assert_true(not pv.ring_shown())
	pv.held = true
	assert_true(pv.ring_shown(), "carried")
	pv.held = false
	assert_eq(PersonView.RING_FILL.r, 1.0)
	assert_true(PersonView.RING_FILL.a < 0.5, "soft")
	m.free()


## Arrange mode: a piece whose picture would stand over another piece's is not put down
## there (a toast says why); a clear spot is fine.
func test_a_piece_is_not_put_where_its_picture_covers_another():
	var m := _main()
	var w := m.session.world
	w.money = 1000
	assert_true(m.house.picture_blocks("stool", "hall", 6, 2), "right behind the table")
	var free := Vector2i(-1, -1)
	for y in 6:
		for x in 10:
			if free.x < 0 and HouseSystem.can_place(w, "stool", "hall", x, y) == "" and not m.house.picture_blocks("stool", "hall", x, y):
				free = Vector2i(x, y)
	assert_true(free.x >= 0, "somewhere in the hall is clear")
	m.arrange.enter()
	m.arrange.pick_type("stool")
	var r := m.arrange.drop(m.house.layout.cell_center("hall", 6, 2))
	assert_eq(str(r.get("error", "")), "blocks_view")
	assert_eq(m.hud.toasts()[-1], m.session.strings.error("blocks_view"))
	assert_eq(m.arrange.held_type, "stool", "still in hand")
	r = m.arrange.drop(m.house.layout.cell_center("hall", free.x, free.y))
	assert_true(r.get("ok", false), str(r))
	m.free()


## The walk keeps step with the ground: a grown-up's cycle per STRIDE screen pixels, an old
## person slower on the ground.
func test_the_walk_cycle_follows_the_ground():
	var m := _main()
	var w := m.session.world
	var pv: PersonView = null
	for uid in m.house.people:
		var q: PersonView = m.house.people[uid]
		if q.person.stage(w.pack) == "adult":
			pv = q
	assert_true(pv != null)
	pv.position = m.house.layout.cell_center("yard", 2, 3)
	pv.target = pv.position + Vector2(48 * 6, 0)
	var t0 := pv._stride_t
	var from := pv.position
	pv.tick(0.25)
	var screen := IsoMath.basis().basis_xform(pv.position - from).length() / IsoMath.ISO_PACE
	var k := clampf(float(pv._look.height) / 90.0, 0.6, 1.1)
	assert_near(pv._stride_t - t0, screen / (PersonView.STRIDE * k) * CutoutRig.WALK_PERIOD, 0.001)
	assert_true(PersonView.ELDER_PACE < 1.0)
	m.free()


## The 穿模 detector (`ClipProbe`) over a minute and a half of a lived-in house at normal speed: every
## room built, seven people, a dog, a cat and a bird going about their day. Nobody's feet in
## furniture or through a wall, nobody drawn on the wrong side of a picture or a back wall,
## nobody sitting off their seat; people walking into one another, hardly ever.
func test_a_lived_in_house_has_no_clipping():
	var tool = load("res://tools/clip_detect.gd")
	var m: Main = tool.start(Engine.get_main_loop(), "full", clk, _clock)
	# The same day every run: the views pick their idle spots with their own dice.
	var dice := 0
	for v in m.house.people.values() + m.house.pets.values():
		dice += 1
		v._rng.seed = 1000 + dice
	var probe := ClipProbe.new(m.house)
	var dt := 1.0 / 30.0
	var opening := 0
	for f in 2700:
		clk.unix += dt
		m.tick(dt)
		probe.frame(dt)
		if f % 3 == 0:
			probe.check()
		if f == 300:
			# The first ten seconds: all seven leave the hall at the same moment (a crowd at
			# one door); the hardly-ever is counted from there on.
			opening = int(probe.counts["people_overlap"]) + int(probe.counts["pet_overlap"])
	for k in ["sort_order", "wall_sort", "feet_in_furniture", "walk_wall", "stop_wall_line", "seat_missing", "lie_wall", "sit_height", "hud"]:
		assert_eq(int(probe.counts[k]), 0, "%s: %s" % [k, probe.events.filter(func(e): return e.kind == k).map(func(e): return "%s %s at %s %s" % [e.who, e.action, e.at, e.detail])])
	assert_true(int(probe.counts["people_overlap"]) + int(probe.counts["pet_overlap"]) - opening <= 5, "%s (opening %d)" % [probe.summary(), opening])
	m.free()


## Each seat has its anchor (art.json `poses.seats`): the sitter's hips are on the seat's
## surface (the body lifted, legs hanging, on a seat higher than their shins) and they are
## drawn over the seat; on the stool they sit in its middle, on the kang on its edge.
func test_sitters_sit_on_the_seat_surface():
	var m := _main()
	var w := m.session.world
	var probe := ClipProbe.new(m.house)
	var jobs := [["shell_beans", "stool"], ["pick_ears", "stone_bench"], ["sit_on_threshold_long", "threshold"]]
	var pvs: Array = []
	for pv in m.house.people.values():
		pv.visible = false  # the household stands about the hall's door; out of the way
	for j in jobs:
		var p := TestKit.adult(w)
		m.tick(0.016)
		var o: Dictionary = w.objects.filter(func(x): return x.type == j[1])[0]
		AutonomySystem.start(w, p, j[0], int(o.uid))
		p.current["remaining_s"] = 99999
		pvs.append(m.house.people[p.uid])
	m.house.refresh()
	for i in 900:
		m.house.tick(1.0 / 30.0)
	for k in pvs.size():
		var pv: PersonView = pvs[k]
		assert_true(pv.on_object and pv.position.distance_to(pv.target) <= 1.0, jobs[k][1])
		assert_eq(pv.body_pose(), "sit", jobs[k][1])
		assert_near(pv.hip_height(), m.house.skin.seat_height(jobs[k][1]), ClipProbe.SIT_SLACK)
		assert_true(pv.get_index() > m.house.props[int(pv.use_object.uid)].get_index(), "%s drawn over the seat" % jobs[k][1])
	var stool := m.house.layout.object_rect((pvs[0] as PersonView).use_object, w.pack)
	assert_near((pvs[0] as PersonView).target.y, stool.get_center().y, 0.5)
	probe.check()
	assert_eq(int(probe.counts["sit_height"]) + int(probe.counts["seat_missing"]) + int(probe.counts["sort_order"]), 0, probe.summary())
	m.free()


## Getting off a seat (or onto one) is by its front: the way from a stool to somewhere behind
## it steps out to the south first, never across the seat.
func test_ways_off_a_seat_leave_by_its_front():
	var m := _main()
	var w := m.session.world
	var site := m.house.layout.site
	var uid := -1
	w.money = 1000
	var hall := HouseLayout.cells_of(m.house.layout.room_rect("hall")).position
	for y in range(1, 5):
		for x in range(1, 9):
			# Open all round, so the way behind it goes round it.
			var open := true
			for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
				open = open and site.walkable(hall + Vector2i(x, y) + d)
			if uid < 0 and open and HouseSystem.can_place(w, "stool", "hall", x, y) == "":
				uid = w.add_object("stool", "hall", x, y)
	assert_true(uid >= 0)
	m.tick(0.016)
	var o := w.object(uid)
	var r := m.house.layout.object_rect(o, w.pack)
	var seat := Vector2(r.get_center().x, r.get_center().y)
	var behind := Vector2(r.get_center().x, r.position.y - HouseSite.CELL.y * 0.5)
	assert_true(site.walkable(site.cell_of(behind)))
	for pair in [[seat, behind], [behind, seat]]:
		var pts := site.route(pair[0], pair[1])
		var at: Vector2 = pair[0]
		for p in Array(pts) + [pair[1]]:
			var n := int(ceil(at.distance_to(p) / 3.0))
			for k in range(1, n):
				var q := at.lerp(p, float(k) / float(n))
				assert_true(not r.grow(-3.0).has_point(q) or q.y >= r.get_center().y - 1.0, "%s across the seat at %s" % [pair, q])
			at = p
	m.free()


## Two people walking at each other along a row of the yard pass without walking through
## each other (one goes round or waits); someone walking at a person standing in the way
## goes round them.
func test_walkers_give_way():
	var m := _main()
	var w := m.session.world
	var a := TestKit.adult(w)
	var b := TestKit.adult(w)
	m.tick(0.016)
	var pa: PersonView = m.house.people[a.uid]
	var pb: PersonView = m.house.people[b.uid]
	for pv in m.house.people.values():
		if pv != pa and pv != pb:
			pv.visible = false
	var l := m.house.layout
	var left := l.cell_center("yard", 9, 3)
	var right := l.cell_center("yard", 15, 3)
	var mid := l.cell_center("yard", 12, 3)
	for runs in [[left, right, right, left], [left, right, mid, mid]]:
		pa.position = runs[0]
		pa.target = runs[1]
		pb.position = runs[2]
		pb.target = runs[3]
		pa.waited = 0.0
		pb.waited = 0.0
		var closest := INF
		for i in 240:
			pa.tick(1.0 / 30.0)
			pb.tick(1.0 / 30.0)
			closest = minf(closest, pa.position.distance_to(pb.position))
		assert_true(closest >= 22.0, "came %.0f px close" % closest)
		assert_true(pa.position.distance_to(pa.target) <= 1.0, "got there")
	m.free()


## A long piece's picture is drawn behind someone standing in front of its far end, and over
## someone standing behind it, though its middle is nearer the camera than either of them.
func test_long_pieces_sort_by_their_edges_not_their_middle():
	var m := _main()
	var w := m.session.world
	var o: Dictionary = w.objects.filter(func(x): return x.type == "grape_trellis")[0]
	var piece: PropPiece = m.house.props[int(o.uid)]
	var r := m.house.layout.object_rect(o, w.pack)
	var pv: PersonView = m.house.people.values()[0]
	pv.held = true
	# South of its west end: in front; the middle of the piece sorts deeper than the feet.
	pv.position = Vector2(r.position.x + 20.0, r.end.y + 16.0)
	assert_true(m.house.sort_depth(piece) > m.house.sort_depth(pv), "the middle alone would draw it over them")
	m.house.tick(0.016)
	assert_true(pv.get_index() > piece.get_index(), "in front of the trellis")
	# North of its east end: behind it, though deeper than its middle.
	pv.position = Vector2(r.end.x - 10.0, r.position.y - 10.0)
	m.house.tick(0.016)
	if m.house.mover_box(pv).intersects(m.house.stage_box(piece)):
		assert_true(pv.get_index() < piece.get_index(), "behind the trellis")
	m.free()


## The door sill lies in the gateway: people step over it (art.json `poses.step_over`), so
## its cells stay walkable, a walk out of the gate goes straight over it, and whoever stands
## on it is drawn over it.
func test_the_door_sill_is_stepped_over():
	var m := _main()
	var w := m.session.world
	var site := m.house.layout.site
	var o: Dictionary = w.objects.filter(func(x): return x.type == "threshold")[0]
	var r := m.house.layout.object_rect(o, w.pack)
	var c := HouseLayout.cells_of(r)
	for x in range(c.position.x, c.end.x):
		assert_true(site.walkable(Vector2i(x, c.position.y)), "sill cell %d walkable" % x)
	var inside := Vector2(r.get_center().x, r.position.y - HouseSite.CELL.y * 0.5)
	var outside := Vector2(r.get_center().x, r.end.y + HouseSite.CELL.y * 0.5)
	assert_true(site.clear_line(inside, outside), "straight over the sill")
	var pv: PersonView = m.house.people.values()[0]
	pv.held = true
	pv.position = r.get_center()
	m.house.tick(0.016)
	assert_true(pv.get_index() > m.house.props[int(o.uid)].get_index(), "drawn over the sill")
	m.free()
