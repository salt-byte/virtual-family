extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var dir := ""


func _clock() -> Dictionary:
	return clk


func _prep(name: String, wipe: bool) -> void:
	dir = "user://test_session_%s/" % name
	DirAccess.make_dir_recursive_absolute(dir)
	if wipe:
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + f)


func _session(name: String, wipe := true, pack_id := "qijia") -> GameSession:
	_prep(name, wipe)
	return GameSession.new(pack_id, dir, _clock)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_new_game_then_adopt_then_time_passes():
	var s := _session("adopt")
	s.start()
	assert_eq(s.world.phase, "adopting")
	assert_true(s.command({"type": "adopt"}).ok)
	clk.unix += 90.0
	s.tick(0.016)
	assert_eq(s.world.now, 1767254400 + 60)


func test_save_and_resume_shows_away_summary():
	var s := _session("resume")
	s.start()
	s.command({"type": "adopt"})
	s.tick(0.016)
	assert_true(s.save())
	clk.unix += 3 * 3600.0
	var got := []
	var s2 := _session("resume", false)
	s2.away.connect(func(sum): got.append(sum))
	s2.start()
	s2.tick(0.016)
	assert_eq(got.size(), 1)
	assert_eq(got[0].simulated_seconds, 3 * 3600)


func test_corrupt_save_is_reported_and_kept_until_new_game():
	_prep("corrupt", true)
	_write(dir + "save_qijia.json", "{not json")
	var s := _session("corrupt", false)
	s.start()
	assert_eq(s.load_error, "corrupt")
	assert_true(s.world == null)
	s.tick(0.016)
	assert_eq(FileAccess.get_file_as_string(dir + "save_qijia.json"), "{not json")
	s.new_game()
	assert_eq(s.world.phase, "adopting")
	assert_eq(s.load_error, "")
	assert_eq(FileAccess.get_file_as_string(dir + "save_qijia.json.bad"), "{not json")


func test_debug_speed_survives_restart():
	var s := _session("speed")
	s.start()
	s.command({"type": "adopt"})
	s.set_setting("speed", 600)
	for i in 100:
		s.tick(0.1)
	var ahead := s.world.now
	assert_true(ahead > 1767254400 + 5000)
	s.save()
	var s2 := _session("speed", false)
	s2.start()
	clk.unix += 120.0
	s2.tick(0.016)
	assert_true(s2.world.now > ahead)


func test_flip_day_night_shifts_local_hour_by_12():
	var s := _session("flip")
	s.start()
	s.command({"type": "adopt"})
	s.tick(0.016)
	var h := s.world.local_hour()
	s.set_setting("flip_day_night", true)
	s.tick(0.016)
	assert_near(fposmod(s.world.local_hour() - h, 24.0), 12.0, 0.1)


func test_failed_command_emits_command_failed():
	var s := _session("fail")
	s.start()
	s.command({"type": "adopt"})
	var codes := []
	s.command_failed.connect(func(c): codes.append(c))
	var item := str(s.pack.items.keys()[0])
	var r := s.command({"type": "buy", "item": item, "qty": 1000000})
	assert_true(not r.ok)
	assert_eq(codes, ["no_money"])


func test_events_are_emitted_once():
	var s := _session("events")
	s.start()
	var got := []
	s.event.connect(func(e): got.append(e))
	s.command({"type": "adopt"})
	for i in 60:
		clk.unix += 60.0
		s.tick(0.016)
	var n := got.size()
	assert_true(n > 0)
	assert_eq(s.world.drain_events().size(), 0)
	s.tick(0.016)
	assert_eq(got.size(), n)


func test_changed_emitted_after_each_step():
	var s := _session("changed")
	s.start()
	var n := [0]
	s.changed.connect(func(): n[0] += 1)
	s.command({"type": "adopt"})
	s.tick(0.016)
	assert_eq(n[0], 2)


func test_invalid_pack_is_safe_and_writes_nothing():
	var s := _session("invalid", true, "no_such_pack")
	s.start()
	assert_eq(s.world.phase, "invalid")
	s.tick(1.0)
	assert_true(not s.save())
	for i in 400:
		s.tick(0.1)
	assert_eq(DirAccess.get_files_at(dir).size(), 0)


func test_bad_settings_file_falls_back_to_defaults():
	_prep("badset", true)
	_write(dir + "settings.json", "{oops")
	var s := GameSession.new("qijia", dir, _clock)
	assert_eq(s.settings.speed, 1)
	assert_eq(s.settings.flip_day_night, false)
	_write(dir + "settings.json", '{"speed": "fast", "flip_day_night": 3, "extra": 1, "clock_skew": 5}')
	var s2 := GameSession.new("qijia", dir, _clock)
	assert_eq(s2.settings.speed, 1)
	assert_eq(s2.settings.flip_day_night, false)
	assert_eq(int(s2.settings.clock_skew), 5)
	assert_true(not s2.settings.has("extra"))


func test_set_setting_writes_file():
	var s := _session("setfile")
	s.set_setting("flip_day_night", true)
	var s2 := GameSession.new("qijia", dir, _clock)
	assert_eq(s2.settings.flip_day_night, true)


func test_autosave_every_30_real_seconds():
	var s := _session("autosave")
	s.start()
	s.command({"type": "adopt"})
	assert_true(not FileAccess.file_exists(s.save_path()))
	for i in 29:
		s.tick(1.0)
	assert_true(not FileAccess.file_exists(s.save_path()))
	s.tick(1.0)
	assert_true(FileAccess.file_exists(s.save_path()))
