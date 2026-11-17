extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0
var last_dir := ""


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_overlays_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	last_dir = d
	return d


func _main(pack := "qijia", dir := "") -> Main:
	var m := Main.create(pack, dir if dir != "" else _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _with_proposal() -> Main:
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	for i in 16:
		clk.unix += 60.0
		m.tick(0.016)
	return m


func test_boot_shows_adopt_then_reroll_changes_candidate_then_adopt_closes():
	var m := _main()
	m.tick(0.016)
	assert_eq(m.overlays.current(), "adopt")
	var before := m.overlays.text()
	m.overlays.press("btn.reroll")
	m.tick(0.016)
	assert_true(m.overlays.text() != before)
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "")
	assert_eq(m.session.world.people.size(), 1)
	m.free()


func test_candidate_age_is_readable_not_encoded():
	var m := _main()
	m.tick(0.016)
	assert_true(not m.overlays.text().contains("$f"))
	var age := int(Person.from_dict(m.session.world.candidate).age)
	assert_true(m.overlays.text().contains(str(age)))
	m.free()


func test_pressing_a_key_the_overlay_lacks_does_nothing():
	var m := _main()
	m.tick(0.016)
	m.overlays.press("btn.accept")
	assert_eq(m.overlays.current(), "adopt")
	m.free()


func test_overlay_backdrop_blocks_house_input():
	var m := _main()
	m.tick(0.016)
	assert_true(m.overlays.blocks_input())
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	assert_true(not m.overlays.blocks_input())
	m.free()


func test_broken_pack_lists_errors():
	var m := _main("no_such_pack")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "pack_error")
	assert_true(m.overlays.text().contains(m.session.pack.errors[0]))
	m.free()


func test_corrupt_save_offers_new_game():
	var d := _clean_dir()
	var f := FileAccess.open(d + "save_qijia.json", FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var m := _main("qijia", d)
	m.tick(0.016)
	assert_eq(m.overlays.current(), "load_error")
	assert_true(m.overlays.text().contains(m.session.strings.t("load.corrupt")))
	m.overlays.press("btn.new_game")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "adopt")
	m.free()


func test_returning_after_hours_shows_summary_once():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	m.session.save()
	var d := last_dir
	m.free()
	clk.unix += 5 * 3600.0
	var m2 := _main("qijia", d)
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "away")
	assert_true(m2.overlays.text().contains(m2.session.strings.t("away.time").replace("{h}", "5")))
	m2.overlays.press("btn.close")
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "")
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "")
	m2.free()


func test_proposal_accept_brings_spouse():
	var m := _with_proposal()
	assert_eq(m.session.world.proposals.size(), 1)
	assert_eq(m.overlays.current(), "")
	m.overlays.open_proposal()
	m.tick(0.016)
	assert_eq(m.overlays.current(), "proposal")
	var pr: Dictionary = m.session.world.proposals[0]
	assert_true(m.overlays.text().contains(str(pr["savings"])))
	m.overlays.press("btn.accept")
	m.tick(0.016)
	assert_eq(m.session.world.people.size(), 2)
	assert_eq(m.overlays.current(), "")
	m.free()


func test_proposal_close_keeps_it_waiting_and_decline_removes_it():
	var m := _with_proposal()
	m.overlays.open_proposal()
	m.tick(0.016)
	m.overlays.press("btn.close")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "")
	assert_eq(m.session.world.proposals.size(), 1)
	m.overlays.open_proposal()
	m.tick(0.016)
	m.overlays.press("btn.decline")
	m.tick(0.016)
	assert_eq(m.session.world.proposals.size(), 0)
	assert_eq(m.overlays.current(), "")
	m.free()


func test_open_proposal_without_one_does_nothing():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	m.overlays.open_proposal()
	m.tick(0.016)
	assert_eq(m.overlays.current(), "")
	m.free()


func test_open_card_closes_when_proposal_expires():
	var m := _with_proposal()
	m.overlays.open_proposal()
	m.tick(0.016)
	assert_eq(m.overlays.current(), "proposal")
	m.session.world.proposals.clear()
	m.tick(0.016)
	assert_eq(m.overlays.current(), "")
	m.free()


func test_family_button_shows_a_dot_while_a_proposal_waits():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	assert_true(not m.hud.bar_text().contains("●"))
	for i in 16:
		clk.unix += 60.0
		m.tick(0.016)
	assert_true(m.hud.bar_text().contains("●"))
	m.session.world.proposals.clear()
	m.tick(0.016)
	assert_true(not m.hud.bar_text().contains("●"))
	m.free()


func test_game_over_then_new_game_returns_to_adopt_keeping_money():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	var w := m.session.world
	w.money = 777
	w.phase = "over"
	m.tick(0.016)
	assert_eq(m.overlays.current(), "over")
	assert_true(m.overlays.text().contains(m.session.strings.t("title.over")))
	m.overlays.press("btn.new_game")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "adopt")
	assert_eq(m.session.world.money, 777)
	m.free()


func test_card_is_opaque_and_padded():
	var m := _main()
	m.tick(0.016)
	var st := m.overlays.card_style()
	assert_eq(st.bg_color.a, 1.0)
	assert_true(st.content_margin_left >= 16 and st.content_margin_top >= 16)
	assert_true(st.content_margin_right >= 16 and st.content_margin_bottom >= 16)
	m.free()
