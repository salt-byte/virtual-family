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
	# qijia's art sits people ON a stool (art.json `poses.on`), so the spot is on it, not
	# below it as for other furniture.
	assert_true(pv.on_object)
	assert_eq(pv.target, PersonView.on_spot(m.house.layout, w.object(uid), w.pack))
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
	# the house never leaves the 1280x720 screen entirely (its bounds as drawn)
	var bounds := m.house.view_bounds()
	var s := m.house.scale.x
	assert_true(a.x + bounds.position.x * s < 1280.0 and b.x + bounds.end.x * s > 0.0)
	assert_eq(m.house.world_pos(m.house.position), Vector2.ZERO)
	m.free()


func test_two_people_on_one_cell_are_offset():
	var m := _main()
	m.session.command({"type": "adopt"})
	var extra := Person.new()
	extra.gender = "male"
	m.session.world.add_person(extra)
	m.tick(0.016)
	var w := m.session.world
	var ps := w.people
	var a: PersonView = m.house.people[ps[0].uid]
	var b: PersonView = m.house.people[ps[1].uid]
	# Both head for one mess (newcomers now appear on cells of their own, so they no longer
	# share a cell just by arriving).
	var uid := w.next_uid()
	w.messes.append({"uid": uid, "type": "x", "room": "hall", "x": 2, "y": 1})
	for p in [ps[0], ps[1]]:
		p.current = {"action": w.pack.actions.keys()[0], "object_uid": -1, "target_uid": uid, "remaining_s": 600}
	m.house.refresh()
	# They used to stand SPREAD (20 px) apart in one cell, close enough to overlap and to put
	# one of them on a wall line; with a site plan the second takes the nearest open cell.
	assert_eq(a.base_target, b.base_target)
	var site := m.house.layout.site
	assert_true(site.cell_of(a.target) != site.cell_of(b.target))
	assert_true(site.can_stop(a.target) and site.can_stop(b.target))
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
	# Rooms share walls now: the gap is the grass just north of the compound.
	pv.position = Vector2(hall.get_center().x, hall.position.y - 40)
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
	var from := m.house.to_screen(pv.position)
	var to := m.house.to_screen(m.house.layout.object_rect(o, w.pack).get_center())
	m.house.press(from)
	m.house.move(to, to - from)
	assert_eq(m.drag.dragging, p.uid)
	m.house.release(to)
	m.tick(0.016)
	assert_eq(m.drag.dragging, -1)
	assert_true(not m.hud.bar_text().contains("文"))
	m.free()


func test_progress_and_bob_follow_the_action():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	assert_eq(pv.progress(), -1.0)
	assert_eq(pv.bob_offset(), 0.0)
	var desk: int = w.objects.filter(func(o): return o.type == "desk")[0].uid
	p.track = "reading"                             # 念书的人拖到书案上才念书
	m.session.command({"type": "drag", "person": p.uid, "object": desk}); m.tick(0.016)
	assert_near(pv.progress(), 0.0, 0.05)
	for i in 200:                                   # 走到位
		pv.tick(0.05)
	pv.tick(0.2)
	assert_true(absf(pv.bob_offset()) > 0.0 and absf(pv.bob_offset()) <= 3.0)
	var half := AutonomySystem.duration_s(w, w.pack.actions["study"]) / 2.0
	clk.unix += half; m.tick(0.016)                 # 念书过了一半
	assert_near(pv.progress(), 0.5, 0.1)
	m.free()


func test_held_person_does_not_bob():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	var desk: int = w.objects.filter(func(o): return o.type == "desk")[0].uid
	m.session.command({"type": "drag", "person": p.uid, "object": desk}); m.tick(0.016)
	for i in 200:
		pv.tick(0.05)
	pv.tick(0.2)
	assert_true(pv.bob_offset() != 0.0)
	pv.held = true
	assert_eq(pv.bob_offset(), 0.0)
	m.free()


func test_sleeping_person_is_dimmed_not_bobbing():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	# Night (local 23:00): sleep, which is slow; a drag onto the kang by day only naps.
	clk["offset"] = 15 * 3600; m.tick(0.016)
	var bed: int = w.objects.filter(func(o): return o.type == "kang")[0].uid
	AutonomySystem.start(w, p, "sleep", bed); m.tick(0.016)
	assert_true(w.pack.actions[str(p.current.get("action", ""))].get("slow", false))
	assert_true(not pv.asleep())                    # still walking
	for i in 400:
		pv.tick(0.05)
	pv.tick(0.2)
	assert_true(pv.asleep())
	assert_eq(pv.bob_offset(), 0.0)
	m.free()


# --- zoom ------------------------------------------------------------------

func test_fit_scale_fills_the_window_and_is_capped():
	var q := Main.create("qijia", _clean_dir(), _clock)  # not in the tree: 1280x720
	var qs := q.house.fit_scale(Vector2(1280, 720))
	# The whole 56 x 32 map in the 45° view (a 2816 x 1408 diamond plus the back walls'
	# headroom) fits at about 0.38; the smallest zoom went down to 0.36 so it does, and a huge
	# window still caps at 2.
	assert_true(qs >= HouseView.MIN_SCALE and qs <= 0.5, str(qs))   # the map is bigger than the window
	assert_eq(q.house.fit_scale(Vector2(8000, 4800)), 2.0)
	assert_eq(q.house.fit_scale(Vector2(200, 200)), HouseView.MIN_SCALE)
	q.free()
	var m := Main.create("_smoke", _clean_dir(), _clock)
	var s := m.house.fit_scale(Vector2(1280, 720))
	assert_true(s >= 1.0 and s <= 1.2, str(s))
	assert_near(m.house.scale.x, s)
	# The fitted house sits inside the area above the bottom bar.
	var b := m.house.layout.bounds()
	var tl := m.house.to_screen(b.position)
	var br := m.house.to_screen(b.end)
	assert_true(tl.x >= 23.9 and tl.y >= 23.9 and br.x <= 1256.1 and br.y <= 720 - 96 - 23.9, "%s %s" % [tl, br])
	m.free()


func test_world_pos_inverts_to_screen_at_any_scale():
	var m := _main()
	for s in [0.5, 1.07, 1.7, 2.0]:
		m.house.zoom_to(s)
		assert_near(m.house.scale.x, s)
		for p in [Vector2.ZERO, Vector2(100, -20), Vector2(700, 400), Vector2(1100, 480)]:
			var back: Vector2 = m.house.world_pos(m.house.to_screen(p))
			assert_true(back.distance_to(p) < 0.001, "%s at %s -> %s" % [p, s, back])
	m.free()


func test_pan_clamp_uses_the_scaled_house():
	var m := _main()
	m.house.zoom_to(2.0)
	var b := m.house.view_bounds()
	m.house.pan(Vector2(-100000, -100000))
	assert_near(m.house.view_to_screen(b.end).x, 640.0)
	m.house.pan(Vector2(100000, 100000))
	assert_near(m.house.view_to_screen(b.position).x, 640.0)
	m.free()


func _drag_person_onto_furniture_at(s: float) -> void:
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	m.house.zoom_to(s)
	var w := m.session.world
	var p: Person = w.people[0]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	var o: Dictionary = w.objects.filter(func(x): return x.type == "stove")[0]
	var pv: PersonView = m.house.people[p.uid]
	var from := m.house.to_screen(pv.position + Vector2(0, -20))
	var to := m.house.to_screen(m.house.layout.object_rect(o, w.pack).get_center())
	m.house.press(from)
	m.house.move(to, to - from)
	assert_eq(m.drag.dragging, p.uid, "scale %s" % s)
	m.house.release(to)
	assert_eq(int(p.current.get("object_uid", -1)), int(o.uid), "scale %s" % s)
	m.free()


func test_drag_onto_furniture_works_when_zoomed():
	_drag_person_onto_furniture_at(1.07)
	_drag_person_onto_furniture_at(2.0)


func test_arrange_hover_lands_on_the_cell_under_the_pointer_when_zoomed():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	m.session.world.money = 1000
	m.house.zoom_to(2.0)
	m.arrange.enter(); m.arrange.press("type:stool")
	var at := m.house.to_screen(m.house.layout.cell_center("hall", 6, 4))
	m.house.move(at, Vector2.ZERO)
	var g := m.arrange.ghost()
	assert_eq([str(g.room), int(g.x), int(g.y)], ["hall", 6, 4])
	m.free()
