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

func test_object_with_capacity_two_takes_two_people():
	var w := TestKit.world()
	var a := TestKit.adult(w)
	var b := TestKit.adult(w)
	var c := TestKit.adult(w)
	var type := str(w.pack.actions["sleep"]["object"])
	w.pack.object_types[type]["capacity"] = 2
	var uid := w.add_object(type, w.rooms_built[0], 0, 0)
	AutonomySystem.start(w, a, "sleep", uid)
	assert_eq(AutonomySystem.can_do(w, b, "sleep", uid), "")
	AutonomySystem.start(w, b, "sleep", uid)
	assert_eq(AutonomySystem.can_do(w, c, "sleep", uid), "busy")

func test_just_finished_action_scores_lower():
	var w := TestKit.world()
	var p := TestKit.adult(w)
	var a: Dictionary = w.pack.actions[w.pack.actions.keys()[0]]
	for id in w.pack.actions:
		var cand: Dictionary = w.pack.actions[id]
		if AutonomySystem._score(w, p, cand) > 0.0:
			a = cand
			break
	var fresh := AutonomySystem._score(w, p, a)
	assert_true(fresh > 0.0)
	p.last_action = str(a["id"])
	assert_near(AutonomySystem._score(w, p, a), fresh * 0.3)

## qijia runs actions 30x faster (step 5): durations shrink and round up to whole steps;
## a `slow` action keeps its real length; the default (speed 1) changes nothing.
func test_duration_is_scaled_rounded_up_to_steps_and_slow_is_exempt():
	var w := TestKit.world("qijia")
	var acts := w.pack.actions
	assert_eq(AutonomySystem.duration_s(w, acts["study"]), 120)
	assert_eq(AutonomySystem.duration_s(w, acts["wash_face"]), 20)
	assert_eq(AutonomySystem.duration_s(w, acts["sleep"]), int(acts["sleep"]["duration_min"]) * 60)   # slow: unscaled (540 min in qijia)
	var s := TestKit.world()
	assert_eq(AutonomySystem.duration_s(s, s.pack.actions["eat"]), int(s.pack.actions["eat"]["duration_min"]) * 60)

## Positive need effects are paid in full over the short real time; negative ones (costs)
## shrink with it.
func test_gain_is_whole_but_cost_follows_real_time():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	p.track = "reading"
	var uid := w.add_object("desk", "hall", 6, 4)
	assert_true(uid >= 0)
	p.needs["energy"] = 80.0
	p.needs["fed"] = 40.0
	AutonomySystem.start(w, p, "study", uid)
	w.advance(120.0)
	assert_true(p.needs["energy"] > 79.0, "energy " + str(p.needs["energy"]))
	assert_eq(p.last_action, "study")
	var q := TestKit.adult(w)
	q.needs["fed"] = 20.0
	w.stock["food"] = 3
	AutonomySystem.start(w, q, "eat_on_threshold", -1)
	w.advance(float(AutonomySystem.duration_s(w, w.pack.actions["eat_on_threshold"])))
	assert_true(q.needs["fed"] > 54.0, "fed " + str(q.needs["fed"]))

## An action shorter than one step after the speed-up takes exactly one step and pays out.
func test_action_shorter_than_a_step_takes_one_step_and_pays():
	var w := TestKit.world("qijia")
	var a: Dictionary = w.pack.actions["wash_face"]
	a["duration_min"] = 1
	assert_eq(AutonomySystem.duration_s(w, a), 5)
	var p := TestKit.adult(w)
	p.needs["energy"] = 50.0
	AutonomySystem.start(w, p, "wash_face", -1)
	w.advance(5.0)
	assert_true(p.current.is_empty())
	assert_eq(p.last_action, "wash_face")
	assert_true(p.needs["energy"] > 57.9, "energy " + str(p.needs["energy"]))

## A save from before the speed-up holds a running action with its old, longer remaining
## time: it runs that time out, finishes normally and pays its effect only once.
func test_legacy_remaining_time_runs_out_without_overpaying():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	p.needs["energy"] = 10.0
	p.needs["happy"] = 10.0
	var vat: int = -1
	for o in w.objects:
		if o.type == "vat": vat = o.uid
	if vat < 0: vat = w.add_object("vat", "hall", 6, 4)
	p.current = {"action": "wash_face", "object_uid": vat, "target_uid": -1, "remaining_s": 600}
	w.advance(580.0)
	assert_eq(str(p.current.get("action", "")), "wash_face")
	w.advance(20.0)
	assert_eq(p.last_action, "wash_face")
	# energy +8 once (minus ten minutes' drain), not 8 x 30
	assert_true(p.needs["energy"] > 17.0 and p.needs["energy"] < 18.1, "energy " + str(p.needs["energy"]))
