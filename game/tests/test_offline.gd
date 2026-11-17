extends TestCase
func _home() -> World:
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11); w.set_time(1767268800, 0)
	w.command({type = "adopt"}); w.money = 3000
	w.command({type = "place", object_type = "fridge", room = "main", x = 0, y = 0})
	w.command({type = "place", object_type = "bed", room = "main", x = 3, y = 0})
	w.command({type = "buy", item = "groceries", qty = 5}); return w
func test_negative_or_zero_elapsed_is_noop():
	var w := _home(); var d := w.to_dict()
	assert_eq(w.catch_up(-500).simulated_seconds, 0); assert_eq(w.catch_up(0).simulated_seconds, 0); assert_eq(w.to_dict(), d)
func test_cap_at_48_hours():
	var w := _home(); var s := w.catch_up(30 * 86400)
	assert_true(s.capped); assert_eq(s.simulated_seconds, 48 * 3600); assert_eq(w.now, 1767268800 + 48 * 3600)
func test_nobody_dies_of_neglect_offline():
	var w := _home(); w.stock["food"] = 0; w.people[0].age = 25.0; w.people[0].lifespan = 70.0
	var s := w.catch_up(48 * 3600); assert_true(w.people[0].alive); assert_eq(s.deaths, [])
func test_summary_counts_and_consumes_events():
	var w := _home(); var m := w.money; var s := w.catch_up(8 * 3600)
	assert_eq(s.money_delta, w.money - m); assert_near(s.years_passed, 4.0, 0.01)
	assert_eq(w.drain_events(), []); assert_true(not w.offline)
func test_offline_matches_online_when_no_floor_hit():
	var a := _home(); var b := _home()
	a.catch_up(2 * 3600); b.offline = true; b.advance(2 * 3600); b.offline = false; b.drain_events()
	assert_eq(a.to_dict(), b.to_dict())
func test_proposal_waits_for_player():
	var w := _home(); var s := w.catch_up(2 * 3600)
	assert_eq(s.proposals_waiting, 1); assert_eq(w.people.size(), 1)
func test_advance_ignores_negative_seconds():
	var w := _home(); var t := w.now; w.advance(-1000); w.advance(60)
	assert_eq(w.now, t + 60)
func test_not_living_simulates_nothing():
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11); w.set_time(1767268800, 0)
	var s := w.catch_up(3600)
	assert_eq(s.simulated_seconds, 0); assert_eq(w.now, 1767268800); assert_eq(s.deaths, []); assert_eq(s.proposals_waiting, 0)
func test_prior_events_survive_catch_up():
	var w := _home(); w.drain_events(); w.emit("marker")
	w.catch_up(3600)
	var ev := w.drain_events()
	assert_eq(ev.size(), 1); assert_eq(ev[0].type, "marker")
func test_stops_when_everyone_dies_and_restores_offline():
	var w := _home(); w.people[0].age = 69.99; w.people[0].lifespan = 70.0
	var s := w.catch_up(10 * 3600)
	assert_eq(w.phase, "over"); assert_eq(s.deaths.size(), 1); assert_eq(s.deaths[0].person, w.people[0].uid)
	assert_true(s.simulated_seconds < 10 * 3600); assert_true(not w.offline)
func _qhome() -> World:
	return BalanceRun.setup("qijia", 11)
func test_qijia_48_hour_catch_up_is_fast_enough():
	var w := _qhome(); assert_eq(w.step_s, 5)
	var t := Time.get_ticks_msec()
	var s := w.catch_up(48 * 3600)
	var ms := Time.get_ticks_msec() - t
	assert_eq(s.simulated_seconds, 48 * 3600)
	assert_true(ms <= 5000, "48 h catch-up took %d ms" % ms)
func test_qijia_offline_matches_online_when_no_floor_hit():
	var a := _qhome(); var b := _qhome()
	a.catch_up(2 * 3600); b.offline = true; b.advance(2 * 3600); b.offline = false; b.drain_events()
	assert_eq(a.to_dict(), b.to_dict())
