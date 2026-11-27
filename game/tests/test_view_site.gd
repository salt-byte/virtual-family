extends TestCase
## The connected house (pack.json `site`): rooms share walls, walls carry doors, people walk
## through the doors; a door into an unbuilt room stays shut until it is built; tall back
## walls, low front walls that go see-through when someone stands behind them. A pack
## without a site (_smoke) keeps the separate rooms and straight walking.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_site_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _site(built: Array) -> HouseSite:
	var s := HouseSite.new(Pack.load_dir("res://packs/qijia"))
	var set := {}
	for r in built:
		set[r] = true
	s.update(set)
	return s


const START := ["hall", "bedroom", "kitchen", "woodshed", "yard", "well", "gate", "coop_run"]


func _centre(s: HouseSite, cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * HouseSite.CELL


## Every leg of the walk from `from` through `pts` to `to` is a clear straight line.
func _legs_clear(s: HouseSite, from: Vector2, pts: PackedVector2Array, to: Vector2) -> bool:
	var at := from
	for p in pts:
		if not s.clear_line(at, p):
			return false
		at = p
	return s.clear_line(at, to)


func test_smoke_has_no_site_and_qijia_has_one():
	assert_true(not HouseSite.new(Pack.load_dir("res://packs/_smoke")).enabled)
	var s := _site(START)
	assert_true(s.enabled)
	assert_eq(s.size, Vector2i(84, 48))
	assert_eq(s.compound, Rect2i(17, 9, 51, 29))


func test_rooms_share_walls_and_doors_open_them():
	var s := _site(START)
	# The hall's south wall: the main door (2 cells) is open, the cell beside it is wall.
	assert_true(s.h_free(Vector2i(41, 18)) and s.h_free(Vector2i(42, 18)))
	assert_true(not s.h_free(Vector2i(40, 18)) and not s.h_free(Vector2i(43, 18)))
	# The hall and the bedroom share one wall with a door in it.
	assert_true(s.v_walls.has(Vector2i(50, 11)) and not s.v_free(Vector2i(50, 11)))
	assert_true(s.v_free(Vector2i(50, 14)))
	# Between two places in the open (yard and well) there is no wall.
	assert_true(not s.v_walls.has(Vector2i(51, 21)))
	# The compound wall, with the gate in its south side.
	assert_true(not s.v_free(Vector2i(17, 30)) and not s.h_free(Vector2i(30, 38)))
	assert_true(s.h_free(Vector2i(41, 38)) and s.h_free(Vector2i(42, 38)))


func test_a_door_into_an_unbuilt_room_opens_when_it_is_built():
	var s := _site(START)
	assert_true(not s.v_free(Vector2i(35, 14)), "hall -> west room shut while it is a foundation")
	assert_true(s.blocked.has(Vector2i(29, 14)), "nobody walks on a bare foundation")
	var v := s.version
	s.update({})  # nothing changes until the built set does
	var built := START.duplicate()
	built.append("west_room")
	var set := {}
	for r in built:
		set[r] = true
	s.update(set)
	assert_true(s.version > v)
	assert_true(s.v_free(Vector2i(35, 14)))
	assert_true(not s.blocked.has(Vector2i(29, 14)))


func test_routes_go_through_doors_never_through_walls():
	var s := _site(START)
	var hall := _centre(s, Vector2i(38, 12))
	var yard := _centre(s, Vector2i(33, 24))
	assert_true(not s.clear_line(hall, yard), "the straight line crosses the hall's front wall")
	var pts := s.route(hall, yard)
	assert_true(pts.size() >= 1)
	assert_true(_legs_clear(s, hall, pts, yard))
	# Out of the bedroom, through the hall and the main door, out of the gate to the road.
	var bed := _centre(s, Vector2i(56, 11))
	var road := _centre(s, Vector2i(42, 44))
	var way := s.route(bed, road)
	assert_true(_legs_clear(s, bed, way, road))
	# The kitchen (west wing) to the woodshed above it: through their shared door.
	var kitchen := _centre(s, Vector2i(23, 24))
	var shed := _centre(s, Vector2i(23, 11))
	assert_true(_legs_clear(s, kitchen, s.route(kitchen, shed), shed))
	# In the open, or inside one room: straight.
	assert_eq(s.route(yard, _centre(s, Vector2i(45, 26))).size(), 0)


func test_a_person_walks_round_the_wall_through_the_door():
	var m := _main()
	var w := m.session.world
	var p: Person = w.people[0]
	AutonomySystem.cancel(w, p)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	var site := m.house.layout.site
	pv.position = m.house.layout.cell_center("hall", 1, 3)
	pv.target = m.house.layout.cell_center("yard", 2, 4)
	var last := pv.position
	var crossed_door := false
	for i in 400:
		pv.tick(0.05)
		assert_true(site.clear_line(last, pv.position), "step %d %s -> %s" % [i, last, pv.position])
		if last.y < 18 * 36 and pv.position.y >= 18 * 36:
			crossed_door = pv.position.x > 41 * 48 and pv.position.x < 43 * 48
		last = pv.position
	assert_true(pv.position.distance_to(pv.target) < 1.0)
	assert_true(crossed_door, "left the hall through its main door")
	m.free()


func test_smoke_walks_straight():
	var m := _main("_smoke")
	var w := m.session.world
	var p: Person = w.people[0]
	AutonomySystem.cancel(w, p)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	pv.position = Vector2(10, 10)
	pv.target = Vector2(1000, 10)
	pv.tick(0.5)
	assert_eq(pv.path.size(), 0)
	assert_near(pv.position.x, 10.0 + PersonView.SPEED * 0.5)
	assert_eq(m.house.walls.size(), 0)
	assert_true(m.house.ground == null)
	m.free()


func test_back_walls_stand_tall_front_walls_low_and_see_through():
	var m := _main()
	var walls := m.house.walls
	assert_true(walls.size() > 10)
	var back: IsoWall = null
	var front: IsoWall = null
	for wp in walls:
		if wp.role == "wall" and wp.along == "x" and wp.line == 9 and wp.at == 38:
			back = wp  # the north wall above the hall
		if wp.role == "wall" and wp.along == "x" and wp.line == 18 and wp.at == 38:
			front = wp  # the hall's south wall, onto the yard
	assert_true(back != null and front != null)
	# The 45° view (ART_DIRECTION section 11): the back walls stand 112 px with an eave, the
	# walls facing the camera are cut to 16.
	assert_true(back.tall and back.height == IsoWall.BACK)
	assert_true(back.eave)
	assert_true(not front.tall and front.height == IsoWall.LOW)
	# Someone on the hall's front row stands behind the cut wall: it only reaches their
	# ankles and never fades.
	var pv: PersonView = m.house.people[m.session.world.people[0].uid]
	pv.position = Vector2(38.5 * 48, 18 * 36 - 18)
	pv.target = pv.position
	pv.held = true
	m.house.tick(0.016)
	assert_true(m.house.sort_depth(front) > m.house.sort_depth(pv))
	assert_eq(front.modulate.a, 1.0)
	# The tall back wall fades for someone behind it (north of the house).
	pv.position = Vector2(37.8 * 48, 9 * 36 - 30)  # on the screen right behind cell 38
	m.house.tick(0.016)
	assert_true(back.modulate.a < 1.0, "someone behind the back wall")
	assert_true(m.house.sort_depth(back) > m.house.sort_depth(pv))
	m.free()


func test_building_a_room_raises_its_walls():
	var m := _main()
	var w := m.session.world
	var before := m.house.walls.size()
	w.money = 5000
	assert_true(m.session.command({"type": "build_room", "room": "west_room"}).ok)
	m.tick(0.016)
	assert_true(m.house.walls.size() != before)
	assert_true(m.house.layout.site.v_free(Vector2i(35, 14)))
	m.free()


func test_bad_site_is_reported():
	var p := Pack.load_dir("res://packs/qijia")
	assert_true(p.is_valid(), str(p.errors))
	# The map keeps the pack's own size (every room fits), so only the three bad entries count.
	var sw := int(p.config["site"]["w"])
	var sh := int(p.config["site"]["h"])
	p.config["site"] = {"w": sw, "h": sh, "doors": [{"x": 1}], "decor": [{"shape": "blob"}], "compound": {"x": sw - 6, "y": 0, "w": 51, "h": 29}}
	var errs := PackValidator.validate(p)
	var site_errs := errs.filter(func(e): return e.begins_with("pack.json: site:"))
	assert_eq(site_errs.size(), 3, str(errs))
	p.config["site"] = {"w": 20, "h": 10}
	assert_true(PackValidator.validate(p).any(func(e): return e.contains("lies outside the map")))
	p.config["site"] = {}
	assert_eq(PackValidator.validate(p), [] as Array[String])


## Out through the gate to the river, the grove or the field, all round by the paths.
func test_routes_to_the_places_outside_go_through_the_gate():
	var m := _main()
	var l := m.house.layout
	var s := l.site
	var hall := l.cell_center("hall", 2, 2)
	for id in ["riverside", "bamboo_grove", "field_ridge", "hill_path", "village_tree"]:
		var to := l.cell_center(id, 1, 1)
		var way := s.route(hall, to)
		assert_true(way.size() >= 2, id)
		assert_true(_legs_clear(s, hall, way, to), id)
		var through_gate := false
		var at := hall
		for p: Vector2 in Array(way) + [to]:
			if at.y < 38 * 36 and p.y > 38 * 36 or at.y > 38 * 36 and p.y < 38 * 36:
				var x := at.x + (p.x - at.x) * (38 * 36 - at.y) / (p.y - at.y)
				through_gate = through_gate or (x > 41 * 48 and x < 43 * 48)
			at = p
		assert_true(through_gate, id)
	m.free()


## Something done "wherever they are" is done at home, not out by the river.
func test_a_roomless_action_brings_someone_home_from_outside():
	var m := _main()
	var w := m.session.world
	var p: Person = w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	pv.position = m.house.layout.cell_center("riverside", 1, 5)
	# qijia names a place for nearly everything; take one and drop the place it picked, as an
	# action that names none would have it.
	var id := ""
	for a in w.pack.actions.values():
		if str(a["object"]) == "" and (a["rooms"] as Array).has("yard") and a["requires"].is_empty() \
				and str(a["cleans"]) == "" and not bool(a["picks"]) and p.stage(w.pack) in a["stages"]:
			id = str(a.id)
			break
	assert_true(id != "")
	AutonomySystem.start(w, p, id, -1)
	p.current.erase("room")
	pv.refresh()
	var hit := m.house.layout.pos_to_cell(pv.target)
	assert_true(hit.get("room", "") != "" and not bool(w.pack.rooms[hit.room]["outside"]), str(hit))
	m.free()
