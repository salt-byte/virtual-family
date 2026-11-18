extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_drag_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main_with_adult_and(type: String, room: String, x: int, y: int) -> Main:
	var m := Main.create("qijia", _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	m.session.world.add_object(type, room, x, y)
	m.tick(0.016)
	return m


func _center(m: Main, o: Dictionary) -> Vector2:
	return m.house.layout.object_rect(o, m.session.pack).get_center()


func test_drop_on_object_starts_its_action():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var uid: int = m.session.world.objects[0].uid
	m.drag.begin(p.uid)
	var r := m.drag.drop(_center(m, m.session.world.object(uid)))
	assert_true(r.ok)
	assert_eq(int(p.current["object_uid"]), uid)
	assert_eq(m.drag.dragging, -1)
	assert_true(not m.house.people[p.uid].held)


func test_drop_on_empty_floor_is_quiet_and_keeps_position():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var at := m.house.layout.cell_center("hall", 6, 4)
	m.drag.begin(p.uid)
	m.drag.drop(at)
	assert_eq(m.hud.toasts(), [])
	assert_eq(m.house.people[p.uid].position, at)
	m.tick(0.5)
	assert_eq(m.house.people[p.uid].position, at, "an idle person stays where they were dropped")


func test_drop_outside_a_built_room_returns_to_where_they_were():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var before: Vector2 = m.house.people[p.uid].position
	var side := m.house.layout.room_rect("side").get_center()  # not built
	m.drag.begin(p.uid)
	m.drag.move(side)
	assert_eq(m.house.people[p.uid].position, side)
	m.drag.drop(side)
	assert_eq(m.house.people[p.uid].position, before)
	assert_eq(m.hud.toasts(), [])
	m.drag.begin(p.uid)
	m.drag.drop(Vector2(-5000, -5000))
	assert_eq(m.house.people[p.uid].position, before)
	assert_eq(m.hud.toasts(), [])


func test_drop_on_busy_object_toasts_busy():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var w := m.session.world
	var a := w.people[0]
	var b := TestKit.adult(w)
	m.tick(0.016)
	var c := _center(m, w.objects.back())
	m.drag.begin(a.uid)
	assert_true(m.drag.drop(c).ok)
	m.drag.begin(b.uid)
	var r := m.drag.drop(c)
	assert_true(not r.ok)
	assert_eq(r.error, "busy")
	assert_true(m.session.strings.error("busy") in m.hud.toasts())
	assert_true(b.current.is_empty())
	assert_eq(m.house.people[b.uid].position, c, "a failed drop leaves them where they were let go")


func test_drag_is_cancelled_when_person_dies_mid_drag():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	m.drag.begin(p.uid)
	m.session.world.kill_person(p, "old_age")
	m.tick(0.016)
	assert_eq(m.drag.dragging, -1)
	assert_eq(m.drag.drop(Vector2.ZERO), {})


func test_drop_on_mess_starts_cleaning_it():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var w := m.session.world
	var p := w.people[0]
	var mu := MessSystem.spawn(w, "dirt", "hall")
	m.tick(0.016)
	var mess: Dictionary = w.messes[0]
	m.drag.begin(p.uid)
	var r := m.drag.drop(m.house.layout.cell_center("hall", int(mess.x), int(mess.y)))
	assert_true(r.ok, str(r))
	assert_eq(int(p.current["target_uid"]), mu)


func test_drop_on_collectible_starts_picking_it_up():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var w := m.session.world
	var p := w.people[0]
	var cu := CollectibleSystem.spawn(w)
	m.tick(0.016)
	var c: Dictionary = w.collectibles[0]
	m.drag.begin(p.uid)
	var r := m.drag.drop(m.house.layout.cell_center(str(c.room), int(c.x), int(c.y)))
	assert_true(r.ok, str(r))
	assert_eq(int(p.current["target_uid"]), cu)


func test_sick_person_dropped_on_floor_shows_the_symptom():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var w := m.session.world
	var p := w.people[0]
	IllnessSystem.infect(w, p, "chill")
	var sym: String = w.pack.illnesses["chill"]["symptom_action"]
	var seen: Array = []
	m.session.event.connect(func(e: Dictionary): seen.append(e))
	m.drag.begin(p.uid)
	var r := m.drag.drop(m.house.layout.cell_center("hall", 6, 4))
	assert_true(not r.ok)
	assert_true(seen.any(func(e): return e.type == "action_started" and e.get("action") == sym), str(seen))
	assert_eq(m.hud.toasts().filter(func(t): return t == m.session.strings.error("no_object")), [])


func test_held_person_follows_cursor_and_refresh_does_not_move_them():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var pv: PersonView = m.house.people[p.uid]
	m.drag.begin(p.uid)
	assert_true(pv.held)
	var at := Vector2(123, 45)
	m.drag.move(at)
	m.tick(0.5)
	m.tick(0.5)
	assert_eq(pv.position, at)
	assert_true(pv.held)
	m.drag.cancel()
	assert_true(not pv.held)
	assert_eq(m.drag.dragging, -1)


func test_hover_marks_the_thing_under_the_cursor():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var o: Dictionary = m.session.world.objects[0]
	m.drag.begin(p.uid)
	m.drag.move(_center(m, o))
	assert_eq(m.house.hover.kind, "object")
	assert_eq(int(m.house.hover.uid), int(o.uid))
	m.drag.move(m.house.layout.cell_center("hall", 6, 4))
	assert_eq(m.house.hover.kind, "room")
	m.drag.drop(m.house.layout.cell_center("hall", 6, 4))
	assert_eq(m.house.hover, {})


func test_failed_command_mute_is_one_shot():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	m.hud.mute("no_object")
	m.session.command({"type": "drag", "person": m.session.world.people[0].uid, "object": -1})
	assert_eq(m.hud.toasts(), [])
	m.hud.unmute()
	m.session.command({"type": "drag", "person": m.session.world.people[0].uid, "object": -1})
	assert_eq(m.hud.toasts().size(), 1)


# --- input state machine -------------------------------------------------

func _screen_of(m: Main, uid: int) -> Vector2:
	return m.house.to_screen(m.house.people[uid].position + Vector2(0, -20))


func test_press_release_on_person_selects():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var w := m.session.world
	var b := TestKit.adult(w)
	m.tick(0.016)
	var at := _screen_of(m, b.uid)
	m.house.press(at)
	m.house.move(at + Vector2(2, 0), Vector2(2, 0))
	m.house.release(at + Vector2(2, 0))
	assert_eq(m.selected, b.uid)
	assert_eq(m.drag.dragging, -1)


func test_press_move_on_person_drags_instead_of_selecting_or_panning():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var w := m.session.world
	var a := w.people[0]
	var b := TestKit.adult(w)
	m.tick(0.016)
	m.select(a.uid)
	var home: Vector2 = m.house.position
	var at := _screen_of(m, b.uid)
	m.house.press(at)
	m.house.move(at + Vector2(10, 0), Vector2(10, 0))
	assert_eq(m.drag.dragging, b.uid)
	m.house.move(at + Vector2(40, 10), Vector2(30, 10))
	assert_eq(m.house.position, home)
	assert_eq(m.house.people[b.uid].position, m.house.world_pos(at + Vector2(40, 10)))
	m.house.release(at + Vector2(40, 10))
	assert_eq(m.drag.dragging, -1)
	assert_eq(m.selected, a.uid)
	assert_eq(m.house.position, home)


func test_press_move_on_empty_space_pans_by_the_whole_displacement():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var home: Vector2 = m.house.position
	var at := Vector2(5, 5)
	m.house.press(at)
	m.house.move(at + Vector2(3, 0), Vector2(3, 0))
	assert_eq(m.house.position, home, "inside the slop nothing moves")
	m.house.move(at + Vector2(10, 0), Vector2(7, 0))
	assert_eq(m.house.position, home + Vector2(10, 0), "the first pixels are not swallowed")
	m.house.move(at + Vector2(14, 0), Vector2(4, 0))
	assert_eq(m.house.position, home + Vector2(14, 0))
	m.house.release(at + Vector2(14, 0))
	assert_eq(m.drag.dragging, -1)


func test_button_released_elsewhere_ends_the_gesture():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var at := _screen_of(m, p.uid)
	var down := [true]
	m.house.button_down = func(): return down[0]
	m.house.press(at)
	var ev := InputEventMouseMotion.new()
	ev.position = at + Vector2(30, 0)
	ev.relative = Vector2(30, 0)
	m.house._unhandled_input(ev)
	assert_eq(m.drag.dragging, p.uid)
	down[0] = false
	ev = InputEventMouseMotion.new()
	ev.position = at + Vector2(50, 0)
	ev.relative = Vector2(20, 0)
	m.house._unhandled_input(ev)
	assert_eq(m.drag.dragging, -1)
	assert_true(not m.house.people[p.uid].held)
	# and a later pan is not stuck either
	var home: Vector2 = m.house.position
	m.house.press(Vector2(5, 5))
	down[0] = false
	ev = InputEventMouseMotion.new()
	ev.position = Vector2(60, 5)
	ev.relative = Vector2(55, 0)
	m.house._unhandled_input(ev)
	assert_eq(m.house.position, home)
