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
## At 5 s steps the catch-up simulates exactly the time asked for, and stops at the cap.
func test_qijia_catch_up_simulates_the_time_asked_and_stops_at_the_cap():
	var w := _qhome(); assert_eq(w.step_s, 5)
	var t0 := w.now
	var s := w.catch_up(2 * 3600)
	assert_eq(s.simulated_seconds, 2 * 3600); assert_true(not s.capped); assert_eq(w.now, t0 + 2 * 3600)
	var c := _qhome()
	c.pack.config["offline_cap_hours"] = 1
	var sc := c.catch_up(30 * 86400)
	assert_true(sc.capped); assert_eq(sc.simulated_seconds, 3600)

## True when the run was asked for the timing tests (`./game/tests/run.sh perf`).
func _perf_requested() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.size() > 0 and str(args[0]).contains("perf")

## Timing, skipped in the normal run (wall-clock results depend on the machine's load): a
## realistic household (2 adults, 2 children) catches up 2 hours, best of 3, scaled to the
## 48-hour cap; that must take at most 10 s.
func test_perf_qijia_48_hour_catch_up_of_a_family_within_budget():
	if not _perf_requested():
		assert_true(not _perf_requested(), "skipped: run with the filter 'perf'")
		return
	var best := INF
	for r in 3:
		var w := BalanceRun.family_of_four("qijia", 11)
		assert_eq(w.people.size(), 4)
		var t := Time.get_ticks_usec()
		var s := w.catch_up(2 * 3600)
		var us := float(Time.get_ticks_usec() - t)
		assert_eq(s.simulated_seconds, 2 * 3600)
		best = minf(best, us)
	var est_s := best * 24.0 / 1e6
	print("  perf: %.2f s" % est_s)
	assert_true(est_s <= 10.0, "48 h catch-up of a family of four would take %.1f s" % est_s)
## The same timing with a dog and a cat in the house (their own actions, and the family
## looking after them).
func test_perf_qijia_48_hour_catch_up_with_a_dog_and_a_cat_within_budget():
	if not _perf_requested():
		assert_true(not _perf_requested(), "skipped: run with the filter 'perf'")
		return
	var best := INF
	for r in 3:
		var w := BalanceRun.family_of_four("qijia", 11)
		PetSystem.add(w, "dog", "bought")
		PetSystem.add(w, "cat", "bought")
		var t := Time.get_ticks_usec()
		var s := w.catch_up(2 * 3600)
		var us := float(Time.get_ticks_usec() - t)
		assert_eq(s.simulated_seconds, 2 * 3600)
		assert_eq(PetSystem.at_home(w), 2)
		best = minf(best, us)
	var est_s := best * 24.0 / 1e6
	print("  perf with pets: %.2f s" % est_s)
	assert_true(est_s <= 10.0, "48 h catch-up of a family of four with two pets would take %.1f s" % est_s)
func test_qijia_offline_matches_online_when_no_floor_hit():
	var a := _qhome(); var b := _qhome()
	a.catch_up(2 * 3600); b.offline = true; b.advance(2 * 3600); b.offline = false; b.drain_events()
	assert_eq(a.to_dict(), b.to_dict())
## A replay run in slices (`CatchUpJob`) ends in the same world and summary as the one-shot one,
## whatever the slice size; also through `World.begin_sync` against `World.sync`.
func _sliced(w: World, elapsed: float, slice: int) -> Dictionary:
	var job := CatchUpJob.new(w, elapsed)
	var guard := 0
	while not job.run(slice):
		guard += 1
		assert_true(w.offline, "offline floor stays on mid-replay")
		if guard > 100000:
			break
	assert_near(job.progress(), 1.0, 0.0001)
	return job.finish()
func test_sliced_catch_up_equals_one_shot():
	for slice in [1, 7, 500]:
		var a := _home(); var b := _home()
		a.emit("marker"); b.emit("marker")
		var sa := a.catch_up(6 * 3600)
		var sb := _sliced(b, 6 * 3600, slice)
		assert_eq(sb, sa, "summary, slice %d" % slice)
		assert_eq(b.to_dict(), a.to_dict(), "world, slice %d" % slice)
		assert_eq(b.drain_events(), a.drain_events())
		assert_true(not b.offline)
func test_qijia_sliced_catch_up_equals_one_shot_with_family_and_pets():
	var a := BalanceRun.family_of_four("qijia", 11); var b := BalanceRun.family_of_four("qijia", 11)
	PetSystem.add(a, "dog", "bought"); PetSystem.add(b, "dog", "bought")
	var sa := a.catch_up(3 * 3600)
	var sb := _sliced(b, 3 * 3600, 13)
	assert_eq(JSON.stringify(sb), JSON.stringify(sa))
	assert_eq(JSON.stringify(b.to_dict()), JSON.stringify(a.to_dict()))
func test_sliced_catch_up_capped_and_game_over_equal_one_shot():
	var a := _home(); var b := _home()
	assert_eq(_sliced(b, 30 * 86400, 64), a.catch_up(30 * 86400)); assert_eq(b.to_dict(), a.to_dict())
	var c := _home(); var d := _home()
	c.people[0].age = 69.99; c.people[0].lifespan = 70.0; d.people[0].age = 69.99; d.people[0].lifespan = 70.0
	assert_eq(_sliced(d, 10 * 3600, 3), c.catch_up(10 * 3600)); assert_eq(d.to_dict(), c.to_dict())
	assert_eq(d.phase, "over")
func test_begin_sync_in_slices_equals_sync():
	for gap in [60, 5 * 3600, 60 * 3600]:
		var a := _home(); var b := _home()
		var u: int = a.now + gap
		var sa := a.sync(u, 0)
		var job := b.begin_sync(u, 0)
		var sb := Offline.zero_summary(b)
		if job != null:
			while not job.run(11):
				pass
			sb = job.finish()
		assert_eq(job != null, gap > World.SYNC_OFFLINE_GAP)
		assert_eq(sb, sa, "summary, gap %d" % gap); assert_eq(b.to_dict(), a.to_dict(), "world, gap %d" % gap)
func test_not_living_job_is_done_at_once():
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11); w.set_time(1767268800, 0)
	var job := CatchUpJob.new(w, 3600)
	assert_true(job.done()); assert_eq(job.progress(), 1.0)
	assert_eq(job.finish().simulated_seconds, 0); assert_eq(w.now, 1767268800)
