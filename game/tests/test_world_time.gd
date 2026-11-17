extends TestCase
func test_two_real_hours_is_one_year():
	var w := TestKit.world(); var p := TestKit.adult(w, 25.0)
	w.advance(7200); assert_near(p.age, 26.0, 0.01); assert_eq(w.now, 1767268800 + 7200)
func test_needs_drain_per_hour():
	var w := TestKit.world(); var p := TestKit.adult(w)
	var before: float = p.needs["fed"]; w.advance(3600)
	assert_near(p.needs["fed"], before - w.pack.needs["fed"]["drain_per_hour"], 0.01)
func test_partial_seconds_accumulate():
	var w := TestKit.world(); w.advance(30); assert_eq(w.now, 1767268800)
	w.advance(30); assert_eq(w.now, 1767268860)
func test_neglect_kills_online():
	var w := TestKit.world(); var p := TestKit.adult(w)
	p.needs["fed"] = 0; p.needs["health"] = 5; w.advance(3600)
	assert_true(not p.alive)
	assert_true(w.drain_events().any(func(e): return e.type == "person_died" and e.cause == "neglect"))
	assert_eq(w.phase, "over")
func test_offline_floor_prevents_neglect_death():
	var w := TestKit.world(); var p := TestKit.adult(w); w.offline = true
	p.needs["fed"] = 0; p.needs["health"] = 5; w.advance(48 * 3600)
	assert_true(p.alive); assert_true(p.needs["health"] >= 15.0)
func test_old_age_death_even_offline():
	var w := TestKit.world(); var p := TestKit.adult(w, 69.9); w.offline = true
	w.advance(7200); assert_true(not p.alive)
	assert_true(w.drain_events().any(func(e): return e.type == "person_died" and e.cause == "old_age"))
func test_local_hour_uses_offset():
	var w := TestKit.world(); w.set_time(1767268800, 8 * 3600); assert_near(w.local_hour(), 20.0)
func test_invalid_pack_refuses():
	var w := World.new(Pack.load_dir("res://tests/fixtures/bad_pack"), 1)
	assert_eq(w.phase, "invalid")
	w.advance(600); assert_eq(w.now, 0)
func test_status_words_follow_labels():
	var w := TestKit.world(); var p := TestKit.adult(w); var labels: Array = w.pack.needs["happy"]["labels"]
	p.needs["happy"] = float(labels[0].below) - 1.0; assert_eq(p.status(w.pack)["happy"], labels[0].text)
	p.needs["happy"] = 100.0; assert_eq(p.status(w.pack)["happy"], labels[-1].text)
func test_stage_follows_age():
	var w := TestKit.world(); var p := TestKit.adult(w, 1.0)
	assert_eq(p.stage(w.pack), "baby"); p.age = 10.0; assert_eq(p.stage(w.pack), "child")
	p.age = 30.0; assert_eq(p.stage(w.pack), "adult"); p.age = 60.0; assert_eq(p.stage(w.pack), "elder")
func test_dead_world_does_not_advance():
	var w := TestKit.world(); var p := TestKit.adult(w, 69.99); w.advance(600)
	assert_eq(w.phase, "over"); var t := w.now; w.advance(600); assert_eq(w.now, t)
func test_person_round_trips_through_json():
	var w := TestKit.world(); var p := TestKit.adult(w)
	p.likes = ["a"]; p.habits = {"eat": 2.0}; p.praise_times = [100, 200]; p.level = 2
	p.last_action_t = 55; p.illness = "flu"
	p.current = {"action": "eat", "object_uid": 3, "target_uid": 4, "remaining_s": 120}
	var back := Person.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.to_dict(), p.to_dict())
	assert_eq(typeof(back.uid), TYPE_INT); assert_eq(typeof(back.level), TYPE_INT)
	assert_eq(typeof(back.praise_times[0]), TYPE_INT); assert_eq(typeof(back.last_action_t), TYPE_INT)
	assert_eq(typeof(back.current["remaining_s"]), TYPE_INT); assert_eq(typeof(back.current["object_uid"]), TYPE_INT)
