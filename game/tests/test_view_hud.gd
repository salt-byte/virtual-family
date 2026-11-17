extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_hud_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _adopted() -> Main:
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _click(m: Main, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	m.house._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	m.house._unhandled_input(up)


func test_bar_shows_selected_person_in_words_not_numbers():
	var m := _adopted()
	var p := m.session.world.people[0]
	p.needs["fed"] = 73.0
	m.tick(0.016)
	assert_eq(m.selected, p.uid)
	var text := m.hud.bar_text()
	assert_true(text.contains(p.given))
	for word in p.status(m.session.pack).values():
		assert_true(text.contains(word))
	assert_true(not text.contains(str(int(p.needs["fed"]))))
	m.free()


func test_praise_with_nothing_to_judge_toasts_reason():
	var m := _adopted()
	AutonomySystem.cancel(m.session.world, m.session.world.people[0])
	m.session.world.people[0].last_action = ""
	m.hud.press("praise")
	assert_eq(m.hud.toasts(), [m.session.strings.error("nothing_to_judge")])
	m.free()


func test_selection_moves_on_when_person_dies():
	var m := _adopted()
	var w := m.session.world
	var first := w.people[0]
	w.add_person(FamilySystem.make_person(w, [20, 20]))
	var second := w.people[1]
	m.tick(0.016)
	assert_eq(m.selected, first.uid)
	w.kill_person(first, "old_age")
	m.tick(0.016)
	assert_eq(m.selected, second.uid)
	w.kill_person(second, "old_age")
	m.tick(0.016)
	assert_eq(m.selected, -1)
	m.free()


func test_goal_done_event_toasts_with_reward():
	var m := _adopted()
	var w := m.session.world
	var gid = w.pack.goals.keys()[0]
	w.emit("goal_done", {"goal": gid, "reward": 4321})
	m.tick(0.016)
	var all := " ".join(m.hud.toasts())
	assert_true(all.contains("4321"))
	m.free()


func test_fifth_toast_pushes_out_the_oldest():
	var m := _adopted()
	for i in 5:
		m.hud.toast("条%d" % i)
	assert_eq(m.hud.toasts(), ["条1", "条2", "条3", "条4"])
	m.free()


func test_toast_expires_after_three_seconds():
	var m := _adopted()
	m.hud.toast("a")
	m.hud.tick(2.9)
	assert_eq(m.hud.toasts().size(), 1)
	m.hud.tick(0.2)
	assert_eq(m.hud.toasts().size(), 0)
	m.free()


func test_buttons_emit_open_and_judge_buttons_disabled_without_selection():
	var m := _main()
	m.tick(0.016)
	assert_true(m.hud.judge_disabled())
	var got := []
	m.hud.open.connect(func(what): got.append(what))
	for what in ["family", "shop", "ledger", "arrange", "settings"]:
		m.hud.press(what)
	assert_eq(got, ["family", "shop", "ledger", "arrange", "settings"])
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	assert_true(not m.hud.judge_disabled())
	m.free()


func test_bar_shows_only_money_when_not_living():
	var m := _main()
	m.tick(0.016)
	var text := m.hud.bar_text()
	assert_true(text.contains(m.session.strings.t("btn.settings")))
	assert_true(not text.contains(m.session.strings.t("btn.shop")))
	m.free()


func test_click_selects_person_and_empty_press_pans():
	var m := _adopted()
	var w := m.session.world
	var first := w.people[0]
	w.add_person(FamilySystem.make_person(w, [20, 20]))
	m.tick(0.016)
	var pv2: PersonView = m.house.people[w.people[1].uid]
	pv2.position = pv2.position + Vector2(200, 0)
	pv2.target = pv2.position
	assert_eq(m.house.person_at(pv2.position + Vector2(0, -10)), w.people[1].uid)
	assert_eq(m.house.person_at(pv2.position + Vector2(500, 500)), -1)
	_click(m, m.house.position + pv2.position + Vector2(0, -10))
	assert_eq(m.selected, w.people[1].uid)
	assert_true(first.uid != m.selected)
	m.free()


func test_praise_success_floats_a_character_for_one_second():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	p.last_action = str(w.pack.actions.keys()[0])
	p.last_action_t = w.now
	p.current = {}
	m.hud.press("praise")
	var pv: PersonView = m.house.people[p.uid]
	assert_true(pv.float_text() != "")
	pv.tick(1.1)
	assert_eq(pv.float_text(), "")
	m.free()

