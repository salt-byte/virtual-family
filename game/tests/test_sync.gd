extends TestCase
## World.sync: the wall-clock protocol a view drives the sim with.
const T0 := 1767268800

func _living() -> World:
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11); w.sync(T0, 0)
	w.command({type = "adopt"}); w.drain_events(); return w

func test_first_sync_snaps_without_simulating():
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11)
	var s := w.sync(T0, 3600)
	assert_eq(w.now, T0); assert_eq(w.utc_offset, 3600); assert_eq(s.simulated_seconds, 0)

func test_backwards_clock_is_a_noop():
	var w := _living(); w.sync(T0 + 90, 0); var d := w.to_dict()
	var s := w.sync(T0 + 30, 7200)
	assert_eq(s.simulated_seconds, 0); assert_eq(w.utc_offset, 7200)
	d["utc_offset"] = 7200; assert_eq(w.to_dict(), d)
	w.sync(T0 + 90, 7200); assert_eq(w.to_dict(), d)   # same instant again: still nothing

func test_small_gap_advances_online():
	var a := _living(); var b := _living()
	var s := a.sync(T0 + 110, 0); b.advance(110)
	assert_eq(s.simulated_seconds, 0); assert_eq(a.now, T0 + 60); assert_eq(a.to_dict(), b.to_dict())
	assert_true(not a.offline)

func test_large_gap_returns_catch_up_summary():
	var a := _living(); var b := _living()
	var s := a.sync(T0 + 3 * 3600, 0); var t := b.catch_up(3 * 3600)
	assert_eq(s.simulated_seconds, 3 * 3600); assert_eq(s, t); assert_eq(a.to_dict(), b.to_dict())

func test_gap_beyond_cap_snaps_now_to_real_clock():
	var w := _living(); var unix := T0 + 10 * 86400 + 5 * 3600 + 17
	var s := w.sync(unix, 8 * 3600)
	assert_true(s.capped); assert_eq(s.simulated_seconds, 48 * 3600)
	assert_eq(w.now, unix)
	assert_near(w.local_hour(), float(posmod(unix + 8 * 3600, 86400)) / 3600.0)
	var s2 := w.sync(unix + 60, 8 * 3600)   # and the clock carries on from there
	assert_eq(s2.simulated_seconds, 0); assert_eq(w.now, unix + 60)

func test_adopting_phase_snaps_without_simulating():
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11); w.sync(T0, 0)
	var cand := w.candidate.duplicate(true)
	var s := w.sync(T0 + 5 * 3600, 0)
	assert_eq(w.now, T0 + 5 * 3600); assert_eq(s.simulated_seconds, 0); assert_eq(w.candidate, cand)
	assert_eq(w.phase, "adopting")

func test_salary_arrives_with_sync_calls_seconds_apart():
	var w := _living(); var p := w.people[0]; p.lifespan = 1e9
	var m := w.money; var t := T0; var paid := false
	while t < T0 + 3600 + 30:
		t += 7
		w.sync(t, 0)
		if w.drain_events().any(func(e): return e.type == "income" and e.source == "salary"):
			paid = true
	assert_true(paid); assert_true(w.money > m)
	assert_true(w.now <= t and w.now > t - World.STEP)

func test_set_time_never_moves_living_world_backwards():
	var w := TestKit.world(); TestKit.adult(w)
	w.set_time(T0 - 3600, 3600)
	assert_eq(w.now, T0); assert_eq(w.utc_offset, 3600)
	w.set_time(T0 + 60, 0); assert_eq(w.now, T0 + 60)

func test_sync_is_deterministic_through_save_and_load():
	var a := _living(); a.sync(T0 + 100, 0)
	var b := World.from_dict(a.pack, JSON.parse_string(JSON.stringify(a.to_dict())))
	for t in [T0 + 107, T0 + 5000, T0 + 5003, T0 + 400000]:
		assert_eq(a.sync(t, 0), b.sync(t, 0))
		assert_eq(a.to_dict(), b.to_dict())
