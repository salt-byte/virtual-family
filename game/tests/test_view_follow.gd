extends TestCase
## The camera follows the person the player picks: an explicit select eases the view until
## that person is in the middle; a manual pan stops it; the wheel zooms around them; while a
## person is carried or arrange mode is open it waits, then carries on.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_follow_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


## A living household on `pack` with its one person standing still (no action, no walking).
func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	var p: Person = m.session.world.people[0]
	AutonomySystem.cancel(m.session.world, p)
	m.tick(0.016)
	_hold_still(m)
	return m


func _person(m: Main) -> PersonView:
	return m.house.people[m.session.world.people[0].uid]


func _hold_still(m: Main) -> void:
	var pv := _person(m)
	pv.target = pv.position


func _centre() -> Vector2:
	return Vector2(1280, 720 - HouseView.BOTTOM_BAR) * 0.5


func _on_screen(m: Main) -> Vector2:
	return m.house.to_screen(_person(m).position)


func _ticks(m: Main, seconds: float) -> void:
	for i in int(round(seconds * 60.0)):
		m.house.tick(1.0 / 60.0)


## Pans so the person sits well away from the middle (towards the bottom right of the screen).
func _push_away(m: Main) -> void:
	m.house.pan(_centre() + Vector2(400, 200) - _on_screen(m))


func test_selecting_a_person_brings_them_to_the_middle():
	var m := _main()
	_push_away(m)
	var uid: int = m.session.world.people[0].uid
	assert_true(_on_screen(m).distance_to(_centre()) > 300.0)
	m.select(uid)
	assert_eq(m.house.follow_uid, uid)
	_ticks(m, 0.25)
	var half := _on_screen(m).distance_to(_centre())
	assert_true(half > 1.0 and half < 150.0, "eases, not jumps: %s" % half)
	_ticks(m, 0.5)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	# and keeps them there as they walk
	_person(m).position += Vector2(96, 36)
	_hold_still(m)
	_ticks(m, 1.0)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	# the clamp still holds: panning by nothing changes nothing
	var at := m.house.position
	m.house.pan(Vector2.ZERO)
	assert_eq(m.house.position, at)
	m.free()


func test_the_first_selection_at_start_does_not_follow():
	var m := Main.create("qijia", _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	var opened := m.house.position
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	assert_true(m.selected >= 0)
	assert_eq(m.house.follow_uid, -1)
	_hold_still(m)
	_ticks(m, 1.0)
	assert_eq(m.house.position, opened)
	m.free()


func test_a_manual_pan_stops_following():
	var m := _main()
	_push_away(m)
	m.select(m.session.world.people[0].uid)
	_ticks(m, 1.0)
	var empty := Vector2(80, 80)
	assert_eq(m.house.person_at(m.house.world_pos(empty)), -1)
	m.house.press(empty)
	m.house.move(empty + Vector2(60, 40), Vector2(60, 40))
	m.house.release(empty + Vector2(60, 40))
	assert_eq(m.house.follow_uid, -1)
	var at := m.house.position
	_ticks(m, 1.0)
	assert_eq(m.house.position, at)
	m.free()


func test_selecting_again_recentres():
	var m := _main()
	var uid: int = m.session.world.people[0].uid
	m.select(uid)
	m.house.press(Vector2(80, 80))
	m.house.move(Vector2(380, 280), Vector2(300, 200))
	m.house.release(Vector2(380, 280))
	assert_eq(m.house.follow_uid, -1)
	assert_true(_on_screen(m).distance_to(_centre()) > 100.0)
	m.select(uid)
	_ticks(m, 1.0)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	m.free()


func test_wheel_zoom_while_following_zooms_around_the_person():
	var m := _main()
	m.house.zoom_to(1.0)  # from life-size (the 45° view opens at ISO_START_SCALE)
	var uid: int = m.session.world.people[0].uid
	_push_away(m)
	m.select(uid)
	_ticks(m, 1.0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = Vector2(100, 100)  # far from the person: it does not matter while following
	m.house._unhandled_input(ev)
	assert_near(m.house.scale.x, 1.1)
	assert_eq(m.house.follow_uid, uid)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	_ticks(m, 0.5)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	m.free()


func test_wheel_zoom_without_following_zooms_around_the_cursor():
	var m := _main()
	var at := Vector2(300, 200)
	var under := m.house.world_pos(at)
	m.house.wheel_zoom(at, 1.1)
	assert_true(m.house.world_pos(at).distance_to(under) < 0.01)
	m.free()


func test_carrying_a_person_pauses_following_and_dropping_resumes_it():
	var m := _main()
	var w := m.session.world
	var uid: int = w.people[0].uid
	m.select(uid)
	_ticks(m, 1.0)
	var from := m.house.to_screen(_person(m).position + Vector2(0, -20))
	var to := from + Vector2(250, 120)  # well inside the screen: no edge scrolling
	m.house.press(from)
	m.house.move(to, to - from)
	assert_eq(m.drag.dragging, uid)
	var at := m.house.position
	_ticks(m, 1.0)
	assert_eq(m.house.position, at, "the view waits while the person is carried")
	m.house.release(to)
	assert_eq(m.house.follow_uid, uid)
	_hold_still(m)
	_ticks(m, 1.0)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	m.free()


func test_arrange_mode_pauses_following():
	var m := _main()
	var uid: int = m.session.world.people[0].uid
	m.select(uid)
	_ticks(m, 1.0)
	m.arrange.enter()
	_person(m).position += Vector2(200, 100)
	_hold_still(m)
	var at := m.house.position
	_ticks(m, 1.0)
	assert_eq(m.house.position, at)
	m.arrange.exit()
	assert_eq(m.house.follow_uid, uid)
	_ticks(m, 1.0)
	assert_true(_on_screen(m).distance_to(_centre()) <= 1.0, str(_on_screen(m)))
	m.free()


func test_following_ends_when_the_person_is_gone():
	var m := _main()
	var p: Person = m.session.world.people[0]
	m.select(p.uid)
	p.alive = false
	m.house.refresh()
	assert_eq(m.house.follow_uid, -1)
	m.free()


func test_choosing_in_the_family_panel_follows_too():
	var m := _main()
	var uid: int = m.session.world.people[0].uid
	m.panels.open("family")
	m.panels.press("person:%d" % uid)
	assert_eq(m.house.follow_uid, uid)
	m.free()


## When the whole house fits on the screen the clamp keeps it centred: following changes
## nothing (the small test pack, and qijia zoomed all the way out).
func test_a_house_that_fits_stays_put_while_following():
	var s := _main("_smoke")
	var at := s.house.position
	s.select(s.session.world.people[0].uid)
	_ticks(s, 1.0)
	assert_eq(s.house.position, at)
	s.free()
	var m := _main()
	m.house.zoom_to(m.house.min_zoom(Vector2(1280, 720)))
	var fitted := m.house.position
	m.select(m.session.world.people[0].uid)
	_ticks(m, 1.0)
	assert_true(m.house.position.distance_to(fitted) < 0.01, "%s %s" % [m.house.position, fitted])
	m.free()
