extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_scene_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func test_both_packs_boot_and_adopt():
	for pack in ["qijia", "_smoke"]:
		var m := _main(pack)
		m.tick(0.016)
		assert_eq(m.house.people.size(), 0)
		m.session.command({"type": "adopt"})
		m.tick(0.016)
		assert_eq(m.house.people.size(), 1)
		m.free()


func test_person_walks_to_the_object_they_use():
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	# 新开的一局没有家具：先免费放一件能用的
	var uid := w.add_object("stool", "hall", 3, 3)
	assert_true(m.session.command({"type": "drag", "person": p.uid, "object": uid}).ok)
	var pv: PersonView = m.house.people[p.uid]
	m.tick(0.016)
	assert_eq(pv.target, m.house.layout.stand_pos(w.object(uid), w.pack))
	for i in 200:
		pv.tick(0.05)
	assert_true(pv.position.distance_to(pv.target) < 1.0)
	m.free()


func test_dead_person_node_is_removed():
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	var p := m.session.world.people[0]
	m.session.world.kill_person(p, "old_age")
	m.tick(0.016)
	assert_eq(m.house.people.size(), 0)
	m.free()


func test_night_amount():
	assert_eq(HouseView.night_amount(12.0), 0.0)
	assert_eq(HouseView.night_amount(23.0), 1.0)
	assert_near(HouseView.night_amount(19.0), 0.5)


func test_pan_is_clamped_to_the_house():
	var m := _main()
	m.house.pan(Vector2(100000, 100000))
	var a := m.house.position
	m.house.pan(Vector2(100000, 100000))
	assert_eq(m.house.position, a)
	m.house.pan(Vector2(-100000, -100000))
	var b := m.house.position
	m.house.pan(Vector2(-100000, -100000))
	assert_eq(m.house.position, b)
	assert_true(a != b)
	# the house never leaves the 1280x720 screen entirely
	var bounds := m.house.layout.bounds()
	assert_true(a.x + bounds.position.x < 1280.0 and b.x + bounds.end.x > 0.0)
	assert_eq(m.house.world_pos(m.house.position), Vector2.ZERO)
	m.free()


func test_two_people_on_one_cell_are_offset():
	var m := _main()
	m.session.command({"type": "adopt"})
	var extra := Person.new()
	extra.gender = "male"
	m.session.world.add_person(extra)
	m.tick(0.016)
	var ps := m.session.world.people
	var a: PersonView = m.house.people[ps[0].uid]
	var b: PersonView = m.house.people[ps[1].uid]
	assert_eq(a.base_target, b.base_target)
	assert_near(absf(a.target.x - b.target.x), 20.0)
	m.free()


func test_invalid_pack_does_not_crash():
	var m := _main("no_such_pack")
	m.tick(0.016)
	m.house.queue_redraw()
	assert_eq(m.house.people.size(), 0)
	m.free()


func _adopted() -> Main:
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _wander(m: Main, p: Person) -> void:
	var id: String = m.session.world.pack.actions.keys()[0]
	p.current = {"action": id, "object_uid": -1, "target_uid": -1, "remaining_s": 600}


func test_new_person_appears_inside_a_built_indoor_room():
	var m := _adopted()
	var w := m.session.world
	var pv: PersonView = m.house.people[w.people[0].uid]
	var hit := m.house.layout.pos_to_cell(pv.position)
	assert_true(not hit.is_empty() and hit.room in w.rooms_built)
	assert_true(not bool(w.pack.rooms[hit.room].get("outdoor", false)))
	m.free()


func test_mess_target_walks_to_the_mess_cell():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	var uid := w.next_uid()
	w.messes.append({"uid": uid, "type": "x", "room": "hall", "x": 2, "y": 1})
	_wander(m, p)
	p.current["target_uid"] = uid
	m.tick(0.016)
	assert_eq(m.house.people[p.uid].target, m.house.layout.cell_center("hall", 2, 1))
	m.free()


func test_collectible_target_walks_to_the_collectible_cell():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	var uid := w.next_uid()
	w.collectibles.append({"uid": uid, "type": "x", "room": "hall", "x": 1, "y": 2, "expires_at": 0})
	_wander(m, p)
	p.current["target_uid"] = uid
	m.tick(0.016)
	assert_eq(m.house.people[p.uid].target, m.house.layout.cell_center("hall", 1, 2))
	m.free()


func test_random_cell_picked_from_nearest_room_when_in_a_gap():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	var hall := m.house.layout.room_rect("hall")
	pv.position = Vector2(hall.end.x + 10, hall.get_center().y)
	assert_true(m.house.layout.pos_to_cell(pv.position).is_empty())
	_wander(m, p)
	pv.refresh()
	var first := pv.target
	var hit := m.house.layout.pos_to_cell(first)
	assert_eq(hit.get("room", ""), "hall")
	pv.refresh()
	assert_eq(pv.target, first)
	m.free()


func test_random_cell_is_rerolled_after_idle():
	var m := _adopted()
	var p := m.session.world.people[0]
	var pv: PersonView = m.house.people[p.uid]
	var seen := {}
	for i in 12:
		_wander(m, p)
		pv.refresh()
		seen[pv.target] = true
		p.current = {}
		pv.refresh()
		assert_eq(pv._key, "")
	assert_true(seen.size() > 1)
	m.free()


func test_smoke_pack_through_the_view_has_no_theme_money_words():
	var m := _main("_smoke")
	m.tick(0.016)
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	var w := m.session.world
	var bar := m.hud.bar_text()
	assert_true(bar.contains(m.session.strings.t("money").replace("{n}", str(w.money))), bar)
	assert_true(not bar.contains("文") and not bar.contains("存粮"), bar)
	for what in ["shop", "ledger", "family"]:
		m.hud.press(what)
		m.tick(0.016)
		assert_eq(m.panels.opened(), what)
		assert_true(not m.panels.text().contains(" 文") and not m.panels.text().contains("存粮"), m.panels.text())
	m.hud.press("settings")
	m.tick(0.016)
	assert_true(m.settings.opened())
	m.settings.press("btn.close")
	m.hud.press("arrange")
	m.tick(0.016)
	assert_true(m.arrange.active)
	assert_true(not m.arrange.text().contains(" 文"), m.arrange.text())
	m.hud.press("arrange")
	# One person drag onto a piece of furniture.
	var p: Person = w.people[0]
	var o: Dictionary = w.objects[0]
	var pv: PersonView = m.house.people[p.uid]
	var from := m.house.position + pv.position
	var to := m.house.position + m.house.layout.object_rect(o, w.pack).get_center()
	m.house.press(from)
	m.house.move(to, to - from)
	assert_eq(m.drag.dragging, p.uid)
	m.house.release(to)
	m.tick(0.016)
	assert_eq(m.drag.dragging, -1)
	assert_true(not m.hud.bar_text().contains("文"))
	m.free()
