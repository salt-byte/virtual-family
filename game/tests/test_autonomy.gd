extends TestCase
func _w() -> World:
	var w := TestKit.world(); w.add_object("fridge", "main", 0, 0); w.add_object("bed", "main", 3, 0)
	w.add_object("tv", "main", 0, 3); w.stock["food"] = 5; return w
func test_hungry_person_eats():
	var w := _w(); var p := TestKit.adult(w)
	for n in p.needs: p.needs[n] = 90.0
	p.needs["fed"] = 10.0
	var c := AutonomySystem.candidates(w, p); c.sort_custom(func(x, y): return x.score > y.score)
	assert_eq(c[0].action, "eat")
	w.advance(60)
	assert_true(not p.current.is_empty())
func test_start_eat_consumes_stock():
	var w := _w(); var p := TestKit.adult(w)
	AutonomySystem.start(w, p, "eat", w.objects[0].uid)
	assert_eq(w.stock["food"], 4)
func test_action_applies_needs_proportionally_and_finishes():
	var w := _w(); var p := TestKit.adult(w); p.needs["fed"] = 10.0
	AutonomySystem.start(w, p, "eat", w.objects[0].uid)
	var dur: int = w.pack.actions["eat"]["duration_min"]; w.advance(dur * 60)
	assert_true(p.current.is_empty()); assert_eq(p.last_action, "eat")
	assert_true(p.needs["fed"] > 10.0 + w.pack.actions["eat"]["needs"]["fed"] - 5.0)
func test_no_stock_means_cannot_eat():
	var w := _w(); w.stock["food"] = 0; var p := TestKit.adult(w)
	assert_eq(AutonomySystem.can_do(w, p, "eat", w.objects[0].uid), "no_stock")
func test_object_in_use_is_busy():
	var w := _w(); var a := TestKit.adult(w); var b := TestKit.adult(w)
	AutonomySystem.start(w, a, "watch_tv", w.objects[2].uid)
	assert_eq(AutonomySystem.can_do(w, b, "watch_tv", w.objects[2].uid), "busy")
func test_habit_weight_shifts_choice():
	var w := _w(); var p := TestKit.adult(w)
	for n in p.needs: p.needs[n] = 50.0
	p.habits["watch_tv"] = 3.0
	var c := AutonomySystem.candidates(w, p); c.sort_custom(func(x, y): return x.score > y.score)
	assert_eq(c[0].action, "watch_tv")
func test_sleep_prefers_night():
	var w := _w(); var p := TestKit.adult(w); p.needs["energy"] = 40.0
	var day := _score(w, p, "sleep"); w.set_time(w.now + 11 * 3600, 0)   # 23 点
	assert_true(_score(w, p, "sleep") > day * 5.0)
func test_same_seed_same_life():
	var a := _w(); TestKit.adult(a); var b := _w(); TestKit.adult(b)
	a.advance(6 * 3600); b.advance(6 * 3600)
	assert_eq(a.people[0].to_dict(), b.people[0].to_dict())
func test_can_do_reasons():
	var w := _w(); var p := TestKit.adult(w)
	assert_eq(AutonomySystem.can_do(w, p, "eat", -1), "")
	assert_eq(AutonomySystem.can_do(w, p, "work_desk", -1), "no_object")
	w.add_object("desk", "main", 5, 5)
	assert_eq(AutonomySystem.can_do(w, p, "work_desk", -1), "wrong_track")
	assert_eq(AutonomySystem.can_do(w, p, "nap_sick", -1), "requires")
	assert_eq(AutonomySystem.can_do(w, p, "take_out_trash", -1), "no_target")
	var baby := TestKit.adult(w, 0.5)
	assert_eq(AutonomySystem.can_do(w, baby, "eat", -1), "stage")
	p.alive = false
	assert_eq(AutonomySystem.can_do(w, p, "eat", -1), "dead")
func test_baby_never_acts():
	var w := _w(); var baby := TestKit.adult(w, 0.5)
	w.advance(600); assert_true(baby.current.is_empty())
func test_cancel_and_death_free_the_object():
	var w := _w(); var a := TestKit.adult(w); var b := TestKit.adult(w)
	var tv: int = w.objects[2].uid
	AutonomySystem.start(w, a, "watch_tv", tv)
	AutonomySystem.cancel(w, a)
	assert_true(a.current.is_empty()); assert_eq(AutonomySystem.can_do(w, b, "watch_tv", tv), "")
	AutonomySystem.start(w, a, "watch_tv", tv); w.kill_person(a, "test")
	assert_eq(AutonomySystem.can_do(w, b, "watch_tv", tv), "")
func test_start_with_any_object_picks_first_free():
	var w := _w(); var p := TestKit.adult(w)
	AutonomySystem.start(w, p, "watch_tv", -1)
	assert_eq(p.current["object_uid"], w.objects[2].uid)
func _score(w, p, id) -> float:
	for c in AutonomySystem.candidates(w, p):
		if c.action == id: return c.score
	return 0.0
