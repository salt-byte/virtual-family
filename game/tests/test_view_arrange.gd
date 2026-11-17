extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_arrange_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _living() -> Main:
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


## The centre of a cell of `room` where a 1x1 thing fits.
func _free_cell_center(m: Main, room: String) -> Vector2:
	var w := m.session.world
	var r: Dictionary = w.pack.rooms[room]
	for y in int(r.h):
		for x in int(r.w):
			var type := "coop" if bool(r.get("outdoor", false)) else "stool"
			if HouseSystem.can_place(w, type, room, x, y) == "":
				return m.house.layout.cell_center(room, x, y)
	return Vector2.ZERO


func _object_center(m: Main, uid: int) -> Vector2:
	return m.house.layout.object_rect(m.session.world.object(uid), m.session.world.pack).get_center()


func test_place_new_furniture_charges_and_shows_up():
	var m := _living(); var w := m.session.world
	w.money = 1000
	var count := w.objects.size()
	m.arrange.enter(); m.arrange.pick_type("stool")
	var at := _free_cell_center(m, "hall")
	m.arrange.hover(at)
	assert_true(m.arrange.can_drop())
	var r := m.arrange.drop(at)
	assert_true(r.ok)
	assert_eq(w.objects.size(), count + 1)
	assert_eq(w.money, 910)
	assert_eq(m.arrange.held_type, "")
	m.free()


func test_overlap_is_red_and_drop_keeps_holding():
	var m := _living(); var w := m.session.world
	w.money = 1000
	var stove: Dictionary = w.objects.filter(func(o): return o.type == "stove")[0]
	var at := _object_center(m, stove.uid)
	m.arrange.enter(); m.arrange.pick_type("stool")
	m.arrange.hover(at)
	assert_true(not m.arrange.can_drop())
	assert_true(not m.arrange.ghost().ok)
	var count := w.objects.size()
	var r := m.arrange.drop(at)
	assert_true(not r.ok)
	assert_eq(r.error, "overlap")
	assert_eq(m.arrange.held_type, "stool")
	assert_eq(w.objects.size(), count)
	assert_eq(w.money, 1000)
	m.free()


func test_indoor_thing_cannot_go_in_the_yard_and_toast_names_the_place():
	var m := _living()
	m.session.world.money = 1000
	m.arrange.enter(); m.arrange.pick_type("stool")
	var at := _free_cell_center(m, "yard")
	m.arrange.hover(at)
	assert_true(not m.arrange.can_drop())
	var r := m.arrange.drop(at)
	assert_eq(r.error, "wrong_area")
	assert_eq(m.hud.toasts(), ["这东西得放在屋里"] as Array[String])
	m.free()


func test_move_object_cancels_its_user():
	var m := _living(); var w := m.session.world
	var stool: Dictionary = w.objects.filter(func(o): return o.type == "stool")[0]
	var p: Person = w.people[0]
	p.current = {"action": "sit", "object_uid": stool.uid, "left": 5.0}
	var from_x := int(stool.x); var from_y := int(stool.y)
	m.arrange.enter(); m.arrange.pick_object(stool.uid)
	var at := _free_cell_center(m, "hall")
	m.arrange.hover(at)
	assert_true(m.arrange.can_drop())
	assert_true(m.arrange.drop(at).ok)
	assert_true(p.current.is_empty())
	assert_eq(int(w.object(stool.uid).uid), stool.uid)
	assert_true(int(w.object(stool.uid).x) != from_x or int(w.object(stool.uid).y) != from_y)
	assert_eq(w.money, 200)
	m.free()


func test_sell_refunds_half():
	var m := _living(); var w := m.session.world
	var vat: Dictionary = w.objects.filter(func(o): return o.type == "vat")[0]
	var count := w.objects.size()
	m.arrange.enter(); m.arrange.pick_object(vat.uid)
	assert_true(m.arrange.has_button("btn.sell"))
	assert_true(m.arrange.text().contains("90"))
	assert_true(m.arrange.sell_held().ok)
	assert_eq(w.money, 290)
	assert_eq(w.objects.size(), count - 1)
	assert_eq(m.arrange.held_uid, -1)
	m.free()


func test_build_room_then_place_inside():
	var m := _living(); var w := m.session.world
	w.money = 3000
	m.arrange.enter()
	assert_true(m.arrange.build("side").ok)
	assert_true(w.rooms_built.has("side"))
	assert_eq(w.money, 2100)
	m.arrange.pick_type("stool")
	var at := m.house.layout.cell_center("side", 1, 1)
	m.arrange.hover(at)
	assert_true(m.arrange.can_drop())
	assert_true(m.arrange.drop(at).ok)
	m.free()


func test_cannot_afford_new_furniture():
	var m := _living(); var w := m.session.world
	w.money = 50
	m.arrange.enter(); m.arrange.pick_type("kang")
	assert_true(not m.arrange.can_drop())
	var free_hall := m.house.layout.cell_center("hall", 6, 4)
	m.arrange.hover(free_hall)
	assert_true(not m.arrange.can_drop())
	var r := m.arrange.drop(free_hall)
	assert_eq(r.error, "no_money")
	assert_eq(m.arrange.held_type, "kang")
	m.free()


func test_catalogue_lists_categories_and_greys_what_is_too_dear():
	var m := _living()
	m.session.world.money = 100
	m.arrange.enter()
	var t := m.arrange.text()
	assert_true(t.contains("灶台") and t.contains("矮凳") and t.contains("坐具"))
	assert_true(m.arrange.has_button("type:stool") and not m.arrange.is_disabled("type:stool"))
	assert_true(m.arrange.is_disabled("type:loom"))
	m.arrange.press("type:stool")
	assert_eq(m.arrange.held_type, "stool")
	m.free()


func test_build_asks_first_and_confirm_builds():
	var m := _living(); var w := m.session.world
	w.money = 3000
	m.arrange.enter()
	m.arrange.ask_build("side")
	assert_true(m.arrange.text().contains("厢房") and m.arrange.text().contains("900"))
	assert_true(m.arrange.blocks_input())
	m.arrange.press("cancel")
	assert_true(not w.rooms_built.has("side") and not m.arrange.blocks_input())
	m.arrange.ask_build("side")
	m.arrange.press("confirm")
	assert_true(w.rooms_built.has("side"))
	m.free()


func test_cancel_held_and_close_button():
	var m := _living()
	m.arrange.enter(); m.arrange.pick_type("stool")
	m.arrange.cancel_held()
	assert_eq(m.arrange.held_type, "")
	assert_true(m.arrange.active)
	m.arrange.press("btn.close")
	assert_true(not m.arrange.active)
	m.free()


func test_held_object_that_is_gone_is_dropped_from_the_hand():
	var m := _living(); var w := m.session.world
	var vat: Dictionary = w.objects.filter(func(o): return o.type == "vat")[0]
	m.arrange.enter(); m.arrange.pick_object(vat.uid)
	w.objects.erase(vat)
	m.tick(0.016)
	assert_eq(m.arrange.held_uid, -1)
	assert_eq(m.arrange.held_type, "")
	m.free()


func test_hud_button_enters_and_people_cannot_be_dragged():
	var m := _living()
	m.hud.press("arrange")
	assert_true(m.arrange.active)
	var pv: PersonView = m.house.people.values()[0]
	m.house.press(m.house.position + pv.position)
	m.house.move(m.house.position + pv.position + Vector2(40, 0), Vector2(40, 0))
	assert_eq(m.drag.dragging, -1)
	m.house.release(m.house.position + pv.position + Vector2(40, 0))
	m.hud.press("arrange")
	assert_true(not m.arrange.active)
	m.free()


func test_overlay_exits_arrange_mode():
	var m := _living()
	m.arrange.enter(); m.arrange.pick_type("stool")
	m.session.world.kill_person(m.session.world.people[0], "old_age")
	m.tick(0.016)
	assert_true(not m.arrange.active)
	assert_eq(m.arrange.held_type, "")
	m.free()


func test_pointer_flow_picks_by_press_and_drops_by_release():
	var m := _living(); var w := m.session.world
	var vat: Dictionary = w.objects.filter(func(o): return o.type == "vat")[0]
	var from := m.house.position + _object_center(m, vat.uid)
	var to := m.house.position + m.house.layout.cell_center("hall", 3, 3)
	m.arrange.enter()
	m.house.press(from)
	assert_eq(m.arrange.held_uid, vat.uid)
	m.house.move(to, to - from)
	assert_true(m.arrange.ghost().ok)
	m.house.release(to)
	assert_eq(m.arrange.held_uid, -1)
	assert_eq(int(w.object(vat.uid).x), 3)
	assert_eq(int(w.object(vat.uid).y), 3)
	m.free()


func test_banner_says_the_house_can_be_dragged():
	var m := _living()
	m.arrange.enter()
	assert_true(m.arrange.text().contains("拖动"), m.arrange.text())
	m.free()


func test_click_with_a_piece_in_hand_places_it():
	var m := _living(); var w := m.session.world
	w.money = 1000
	var count := w.objects.size()
	m.arrange.enter(); m.arrange.press("type:stool")
	var at := m.house.position + _free_cell_center(m, "hall")
	m.house.move(at, Vector2.ZERO)
	m.house.press(at)
	m.house.release(at)
	assert_eq(w.objects.size(), count + 1)
	assert_eq(m.arrange.held_type, "")
	m.free()


func test_press_drag_with_a_piece_in_hand_pans_and_does_not_place():
	var m := _living(); var w := m.session.world
	w.money = 1000
	var count := w.objects.size()
	m.arrange.enter(); m.arrange.press("type:coop")
	var from := m.house.position + _free_cell_center(m, "hall")
	var to := from + Vector2(-200, 0)
	var before := m.house.position
	m.house.press(from)
	m.house.move(to, to - from)
	assert_eq(m.house.position, before + Vector2(-200, 0))
	m.house.release(to)
	assert_eq(w.objects.size(), count)
	assert_eq(m.arrange.held_type, "coop")
	# The ghost follows the pointer over the panned house; a click there places the piece.
	var yard := m.house.position + _free_cell_center(m, "yard")
	m.house.move(yard, Vector2.ZERO)
	assert_eq(str(m.arrange.ghost().room), "yard")
	m.house.press(yard)
	m.house.release(yard)
	assert_eq(w.objects.size(), count + 1)
	m.free()


func test_furniture_under_a_mess_can_be_picked_up():
	var m := _living(); var w := m.session.world
	var stool: Dictionary = w.objects.filter(func(o): return o.type == "stool")[0]
	w.messes.append({"uid": 9001, "type": "dirt", "room": stool.room, "x": stool.x, "y": stool.y})
	m.arrange.enter()
	m.house.press(m.house.position + m.house.layout.cell_center(stool.room, stool.x, stool.y))
	assert_eq(m.arrange.held_uid, stool.uid)
	m.free()


func test_hover_is_reset_on_exit_and_on_catalogue_pick():
	var m := _living()
	m.session.world.money = 1000
	m.arrange.enter(); m.arrange.pick_type("stool")
	m.arrange.hover(_free_cell_center(m, "hall"))
	assert_true(not m.arrange.ghost().is_empty())
	m.arrange.exit()
	m.arrange.enter(); m.arrange.press("type:stool")
	assert_true(m.arrange.ghost().is_empty())
	m.arrange.hover(_free_cell_center(m, "hall"))
	assert_true(not m.arrange.ghost().is_empty())
	m.arrange.press("type:kang")
	assert_true(m.arrange.ghost().is_empty())
	m.free()
