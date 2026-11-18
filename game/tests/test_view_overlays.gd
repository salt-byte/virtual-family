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
	# No old stories here: with the places outside the house the seeded dice drop the first
	# story fragment where the lone person picks it up within these 16 minutes, and its card
	# would outrank the proposal card these tests look at.
	m.session.world.pack.stories = {}
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


func test_death_while_away_shows_summary_with_name_then_game_over_and_no_stale_card():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	var p: Person = m.session.world.people[0]
	p.age = p.lifespan - 1.0
	var who := m.session.strings.person_name(p)
	m.session.save()
	var d := last_dir
	m.free()
	clk.unix += 20 * 3600.0
	var m2 := _main("qijia", d)
	m2.tick(0.016)
	assert_eq(m2.session.world.phase, "over")
	assert_eq(m2.overlays.current(), "away")
	assert_true(m2.overlays.text().contains(who), m2.overlays.text())
	m2.overlays.press("btn.close")
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "over")
	m2.overlays.press("btn.new_game")
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "adopt")
	m2.overlays.press("btn.adopt")
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "")
	m2.free()


func test_away_summary_is_dropped_once_a_new_game_is_adopting():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	m.session.away.emit({"simulated_seconds": 7200, "game_over": true})
	m.session.world.phase = "over"
	m.session.command({"type": "reroll"})
	m.tick(0.016)
	assert_eq(m.overlays.current(), "adopt")
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "")
	m.free()


func test_game_over_card_says_why_and_what_carries_over():
	var m := _main()
	m.overlays.press("btn.adopt")
	m.tick(0.016)
	m.session.world.phase = "over"
	m.tick(0.016)
	var t := m.overlays.text()
	assert_true(t.contains(m.session.strings.t("over.reason")) and t.contains(m.session.strings.t("over.carry")))
	assert_true(m.session.strings.t("over.reason") != "over.reason")
	m.free()


func test_person_card_separates_track_and_level():
	var m := _main()
	m.tick(0.016)
	var job := str(m.session.pack.livelihoods.keys()[0])
	var jd: Dictionary = m.session.pack.livelihoods[job]
	m.session.world.candidate["track"] = job
	m.session.world.candidate["level"] = 0
	m.tick(0.016)
	assert_true(m.overlays.text().contains(str(jd["name"]) + " · " + str(jd["levels"][0]["name"])), m.overlays.text())
	m.free()


func test_first_adoption_hints_dragging_once_per_install():
	var m := _main()
	m.tick(0.016)
	var hint := m.session.strings.t("hint.drag")
	m.overlays.press("btn.adopt")
	assert_true(hint in m.hud.toasts())
	assert_eq(m.session.settings.hint_seen, true)
	# A later re-adoption in the same world says nothing.
	m.session.world.phase = "over"
	m.overlays.refresh()
	m.overlays.press("btn.new_game")
	m.hud.tick(10.0)
	m.session.settings.hint_seen = false
	m.overlays.press("btn.adopt")
	assert_true(not hint in m.hud.toasts())
	var d := last_dir
	m.free()
	# A new world in the same install (same settings.json, no save): already seen.
	var d2 := _clean_dir()
	DirAccess.copy_absolute(d + "settings.json", d2 + "settings.json")
	var m3 := _main("qijia", d2)
	m3.overlays.press("btn.adopt")
	assert_true(not hint in m3.hud.toasts())
	m3.free()


func test_loading_a_save_shows_no_drag_hint():
	var m := _main()
	m.session.command({"type": "adopt"})
	m.session.save()
	var d := last_dir
	m.free()
	var m2 := _main("qijia", d)
	m2.tick(0.016)
	assert_true(not m2.session.strings.t("hint.drag") in m2.hud.toasts())
	m2.free()


func test_ui_json_error_is_toasted_once_at_launch():
	var m := _main()
	assert_eq(m.hud.toasts(), [] as Array[String])
	m.session.strings = ViewStrings.new(m.session.pack, "res://tests/fixtures/bad_ui_pack/ui.json")
	var h := Hud.new()
	m.add_child(h)
	h.setup(m)
	assert_eq(h.toasts(), [m.session.strings.errors[0]] as Array[String])
	h.refresh()
	assert_eq(h.toasts().size(), 1)
	m.free()


func test_pack_with_a_sizeless_room_shows_the_error_overlay():
	var m := _main("../tests/fixtures/sizeless_room_pack")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "pack_error")
	assert_true(m.overlays.text().contains("rooms.json"), m.overlays.text())
	m.free()
