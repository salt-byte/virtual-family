extends TestCase
## A house bigger than one screen: it opens at scale 1 on the entrance room, zooms with the
## wheel around the cursor, pans so any part can reach the middle, and scrolls by itself while
## something is carried near an edge. Also: a person doing an action that names its rooms
## walks into that room; fixed furniture stays put in arrange mode.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_big_house_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _view_centre() -> Vector2:
	return Vector2(1280, 720 - HouseView.BOTTOM_BAR) * 0.5


func test_qijia_opens_at_scale_one_centred_on_the_entrance_room():
	var m := _main()
	assert_true(m.house.fit_scale(Vector2(1280, 720)) < 1.0)
	assert_near(m.house.scale.x, 1.0)
	var hall := m.house.layout.room_rect("hall").get_center()
	assert_true(m.house.to_screen(hall).distance_to(_view_centre()) < 120.0, str(m.house.to_screen(hall)))
	assert_true(absf(m.house.to_screen(hall).x - _view_centre().x) < 0.5)
	m.free()


func test_smoke_keeps_its_fitted_scale():
	var m := _main("_smoke")
	var fit := m.house.fit_scale(Vector2(1280, 720))
	assert_true(fit > 1.0)
	assert_near(m.house.scale.x, fit)
	m.free()


func test_zoom_at_keeps_the_house_point_under_the_cursor():
	var m := _main()
	var at := Vector2(700, 300)
	var under := m.house.world_pos(at)
	m.house.zoom_at(at, 1.1)
	assert_near(m.house.scale.x, 1.1)
	assert_true(m.house.world_pos(at).distance_to(under) < 0.01, str(m.house.world_pos(at)))
	m.house.zoom_at(at, 1.0 / 1.1)
	m.house.zoom_at(at, 1.0 / 1.1)
	assert_near(m.house.scale.x, 1.0 / 1.1)
	for i in 30:
		m.house.zoom_at(at, 1.0 / 1.1)
	assert_near(m.house.scale.x, m.house.fit_scale(Vector2(1280, 720)))
	for i in 30:
		m.house.zoom_at(at, 1.1)
	assert_near(m.house.scale.x, HouseView.MAX_SCALE)
	m.free()


func test_mouse_wheel_zooms():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = Vector2(640, 300)
	m.house._unhandled_input(ev)
	assert_near(m.house.scale.x, 1.1)
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	m.house._unhandled_input(ev)
	assert_near(m.house.scale.x, 1.0)
	m.free()


func test_pan_brings_every_corner_room_to_the_centre():
	var m := _main()
	for id in ["west_room", "woodshed", "pigsty", "threshing"]:
		var c := m.house.layout.room_rect(id).get_center()
		m.house.pan(_view_centre() - m.house.to_screen(c))
		assert_true(m.house.to_screen(c).distance_to(_view_centre()) < 0.5, "%s at %s" % [id, m.house.to_screen(c)])
	# but not past the house's own edge (as drawn: in the 45° view the rect round the map's
	# diamond, walls included)
	var b := m.house.view_bounds()
	m.house.pan(Vector2(100000, 100000))
	assert_true(m.house.view_to_screen(b.position).distance_to(_view_centre()) < 0.5)
	m.house.pan(Vector2(-100000, -100000))
	assert_true(m.house.view_to_screen(b.end).distance_to(_view_centre()) < 0.5)
	m.free()


func test_a_house_smaller_than_the_view_stays_centred():
	var m := _main()
	m.house.zoom_to(m.house.fit_scale(Vector2(1280, 720)))
	var b := m.house.view_bounds()
	m.house.pan(Vector2(5000, 0))
	assert_true(absf(m.house.view_to_screen(b.get_center()).x - _view_centre().x) < 0.5)
	var s := _main("_smoke")
	s.house.pan(Vector2(300, 300))
	assert_true(s.house.to_screen(s.house.layout.bounds().get_center()).distance_to(_view_centre()) < 0.5)
	m.free()
	s.free()


func test_edge_scrolling_while_dragging_moves_the_house_and_stops_at_the_clamp():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p: Person = w.people[0]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	var from := m.house.to_screen(pv.position + Vector2(0, -20))
	var edge := Vector2(1270, 300)
	m.house.press(from)
	m.house.move(edge, edge - from)
	assert_eq(m.drag.dragging, p.uid)
	var before := m.house.position
	m.house.tick(0.1)
	assert_near(m.house.position.x, before.x - 60.0)
	assert_near(m.house.position.y, before.y)
	assert_true(pv.position.distance_to(m.house.world_pos(edge)) < 0.01, "the carried person stays under the cursor")
	for i in 100:
		m.house.tick(0.1)
	var b := m.house.view_bounds()
	assert_near(m.house.view_to_screen(b.end).x, _view_centre().x)
	var stuck := m.house.position
	m.house.tick(0.1)
	assert_eq(m.house.position, stuck)
	m.house.release(edge)
	m.free()


func test_no_edge_scrolling_without_something_in_hand():
	var m := _main()
	var before := m.house.position
	m.house.move(Vector2(1275, 300), Vector2.ZERO)
	m.house.tick(0.5)
	assert_eq(m.house.position, before)
	m.free()


func test_edge_scrolling_while_holding_a_piece_in_arrange_mode():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	m.session.world.money = 1000
	m.arrange.enter(); m.arrange.press("type:stool")
	var before := m.house.position
	m.house.move(Vector2(10, 300), Vector2.ZERO)
	m.house.tick(0.1)
	assert_near(m.house.position.x, before.x + 60.0)
	m.free()


## With the view panned to the west, the coop is off-screen in the bottom-right corner;
## carrying a person to the edge scrolls it into view, and dropping them on it starts
## something there. (In the connected house the coop is on screen at the start, so the test
## pans away first.)
func test_drag_onto_furniture_off_screen_after_edge_scrolling():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p: Person = w.people[0]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	var o: Dictionary = w.objects.filter(func(x): return x.type == "coop")[0]
	var centre := m.house.layout.object_rect(o, w.pack).get_center()
	# In the 45° view the coop sits lower on the screen than the hall: lift the house a
	# little too, so it comes level with the middle when scrolled back.
	m.house.pan(Vector2(2000, -100))
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720 - HouseView.BOTTOM_BAR))
	assert_true(not screen.has_point(m.house.to_screen(centre)), str(m.house.to_screen(centre)))
	var pv: PersonView = m.house.people[p.uid]
	var from := m.house.to_screen(pv.position + Vector2(0, -20))
	# The right edge only: the coop is already level with the middle of the screen, and
	# scrolling down as well would carry it past the top.
	var corner := Vector2(1270, 400)
	m.house.press(from)
	m.house.move(corner, corner - from)
	var guard := 0
	while not screen.grow(-60).has_point(m.house.to_screen(centre)) and guard < 200:
		m.house.tick(0.05)
		guard += 1
	var to := m.house.to_screen(centre)
	assert_true(screen.has_point(to), str(to))
	m.house.move(to, to - corner)
	m.house.release(to)
	assert_eq(int(p.current.get("object_uid", -1)), int(o.uid))
	m.free()


func test_person_doing_a_room_action_walks_into_that_room():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p: Person = w.people[0]
	var id := ""
	for a in w.pack.actions.values():
		if str(a["object"]) == "" and (a["rooms"] as Array).has("gate") and p.stage(w.pack) in a["stages"] \
				and a["requires"].is_empty() and str(a["cleans"]) == "" and not bool(a["picks"]):
			id = str(a.id)
			break
	assert_true(id != "")
	for i in 10:
		AutonomySystem.start(w, p, id, -1)
		m.house.refresh()
		var room := str(p.current["room"])
		var pv: PersonView = m.house.people[p.uid]
		assert_true(m.house.layout.room_rect(room).has_point(pv.base_target), "%s %s" % [room, pv.base_target])
		AutonomySystem.cancel(w, p)
		m.house.refresh()
	m.free()


func test_fixed_furniture_is_not_picked_up_and_says_so_once():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var well: Dictionary = w.objects.filter(func(x): return x.type == "well_head")[0]
	m.house.pan(_view_centre() - m.house.to_screen(m.house.layout.object_rect(well, w.pack).get_center()))
	m.arrange.enter()
	assert_true(not m.arrange.has_button("type:well_head"))
	var at := m.house.to_screen(m.house.layout.object_rect(well, w.pack).get_center())
	var toasts := m.hud.toasts().size()
	m.house.press(at)
	m.house.release(at)
	assert_eq(m.arrange.held_uid, -1)
	assert_eq(m.hud.toasts().size(), toasts + 1)
	assert_eq(m.hud.toasts()[-1], m.session.strings.error("fixed"))
	m.free()
