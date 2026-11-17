extends TestCase

var clk := {"unix": 1767268800.0, "offset": 0}
var n := 0
var last_dir := ""


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_settings_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	last_dir = _clean_dir()
	var m := Main.create(pack, last_dir, _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _main_same_dir(pack := "qijia") -> Main:
	var m := Main.create(pack, last_dir, _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _living() -> Main:
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func test_speed_marker_and_setting_persist():
	var m := _living()
	assert_eq(m.settings.marker_text(), "")
	m.settings.open()
	m.settings.press("speed:60")
	m.tick(0.016)
	assert_eq(m.session.settings.speed, 60)
	assert_true(m.hud.bar_text().contains("×60") or m.settings.marker_text() == "×60")
	m.settings.press("btn.close")
	assert_true(not m.settings.opened())
	assert_eq(m.settings.marker_text(), "×60")
	var m2 := _main_same_dir()
	assert_eq(m2.session.settings.speed, 60)
	m2.free()
	m.free()


func test_speed_back_to_one_clears_marker():
	var m := _living()
	m.settings.open()
	m.settings.press("speed:600")
	assert_eq(m.settings.marker_text(), "×600")
	m.settings.press("speed:1")
	assert_eq(m.settings.marker_text(), "")
	m.free()


func test_flip_toggle_changes_night_tint():
	var m := _living()
	assert_eq(HouseView.night_amount(m.session.world.local_hour()), 0.0)
	m.settings.open()
	m.settings.press("flip")
	m.tick(0.016)
	assert_eq(m.session.settings.flip_day_night, true)
	assert_eq(HouseView.night_amount(m.session.world.local_hour()), 1.0)
	m.settings.press("flip")
	m.tick(0.016)
	assert_eq(m.session.settings.flip_day_night, false)
	assert_eq(HouseView.night_amount(m.session.world.local_hour()), 0.0)
	m.free()


func test_panel_shows_clock_and_note():
	var m := _living()
	m.settings.open()
	assert_true(m.settings.opened())
	assert_true(m.settings.text().contains("12:00"))
	assert_true(m.settings.text().contains(m.session.strings.t("set.debug_note")))
	m.free()


func test_opening_blocks_house_and_closes_panels_and_arrange():
	var m := _living()
	m.panels.open("shop")
	m.hud.press("settings")
	assert_eq(m.panels.opened(), "")
	assert_true(m.settings.opened())
	assert_true(m.is_house_blocked())
	m.settings.close()
	m.arrange.enter()
	assert_true(m.arrange.active)
	m.hud.press("settings")
	assert_true(not m.arrange.active)
	assert_true(m.settings.opened())
	m.free()


func test_overlay_closes_settings():
	var m := _living()
	m.settings.open()
	m.session.world.proposals.append({"id": 99})
	m.session.world.proposals.clear()
	m.session.world.phase = "over"
	m.tick(0.016)
	assert_true(not m.settings.opened())
	m.free()


func test_no_clock_without_living_world():
	var m := _main()
	m.settings.open()
	assert_true(not m.settings.text().contains(":"))
	m.free()


func test_export_preset_includes_json():
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var found := false
	for sec in cfg.get_sections():
		if cfg.has_section_key(sec, "platform") and cfg.get_value(sec, "platform") == "Web":
			found = true
			assert_eq(cfg.get_value(sec, "name"), "Web")
			assert_true(str(cfg.get_value(sec, "include_filter")).contains("*.json"))
	assert_true(found)


func test_clock_updates_in_place_without_rebuilding_buttons():
	var m := _living()
	m.settings.open()
	var b: Button = m.settings.button("speed:60")
	var before: String = m.settings.text()
	for i in 5:
		clk["unix"] = float(clk["unix"]) + 60.0
		m.tick(0.016)
	assert_true(m.settings.opened())
	assert_true(m.settings.text() != before)
	assert_true(m.settings.text().contains("12:05"))
	assert_true(is_instance_valid(b) and b.get_parent() != null and not b.is_queued_for_deletion())
	assert_true(m.settings.button("speed:60") == b)
	m.free()
