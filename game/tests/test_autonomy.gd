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
	assert_eq(AutonomySystem.duration_s(w, acts["study"]), 60)
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
	w.advance(float(AutonomySystem.duration_s(w, w.pack.actions["study"])))
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
## time: it is cut to the action's new length, finishes within it and pays its effect once.
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
	var dur := AutonomySystem.duration_s(w, w.pack.actions["wash_face"])
	w.advance(float(dur - 5))
	assert_eq(str(p.current.get("action", "")), "wash_face")
	w.advance(5.0)
	assert_eq(p.last_action, "wash_face")
	# energy +8 once (minus a few seconds' drain), not 8 x 30
	assert_true(p.needs["energy"] > 17.5 and p.needs["energy"] < 18.1, "energy " + str(p.needs["energy"]))

func _qijia_sleeper(local_hour: int) -> Array:
	var w := TestKit.world("qijia")
	w.set_time(1767225600 + local_hour * 3600, 0)
	var p := TestKit.adult(w)
	var kang := w.add_object("kang", "hall", 0, 2)
	if kang < 0:
		for o in w.objects:
			if o.type == "kang": kang = o.uid
	AutonomySystem.start(w, p, "sleep", kang)
	w.drain_events()
	return [w, p]

## Sleep is slow and has an `hours` window: it runs on real time inside the window and ends
## at the next step once the local hour is outside it (day/night flipped).
func test_slow_action_ends_when_the_day_night_setting_flips():
	var r := _qijia_sleeper(23)
	var w: World = r[0]
	var p: Person = r[1]
	w.advance(60.0)
	assert_eq(str(p.current.get("action", "")), "sleep")
	var energy := float(p.needs["energy"])
	w.set_time(w.now, 12 * 3600)   # 23:01 becomes 11:01
	w.advance(float(w.step_s))
	assert_true(str(p.current.get("action", "")) != "sleep", str(p.current))
	assert_eq(p.last_action, "sleep")
	assert_true(w.drain_events().any(func(e): return e.type == "action_finished" and e.action == "sleep"))
	assert_true(float(p.needs["energy"]) >= energy - 0.1, "gains already paid stay")

## A sleeper whose window closes at 06:00 is up by 06:00:05, however long `remaining_s` was.
func test_sleeper_rises_when_the_window_closes():
	var r := _qijia_sleeper(5)
	var w: World = r[0]
	var p: Person = r[1]
	p.current["remaining_s"] = 9 * 3600
	w.advance(3600.0 - float(w.step_s))   # 05:59:55
	assert_eq(str(p.current.get("action", "")), "sleep")
	w.advance(float(w.step_s))            # 06:00:00
	assert_true(str(p.current.get("action", "")) != "sleep", str(p.current))
	assert_eq(p.last_action, "sleep")
	assert_true(w.local_hour() <= 6.0 + 5.0 / 3600.0)

## With `repeat_memory` N the last N finished actions are damped: position k (0 = most
## recent) by repeat_factor^((N - k) / N). N = 1 (the default) is exactly the old rule.
func test_repeat_memory_damps_the_last_few_actions():
	var w := TestKit.world("qijia")
	w.pack.config["repeat_memory"] = 3
	var p := TestKit.adult(w)
	var ids: Array = []
	for id in w.pack.actions:
		if AutonomySystem._score(w, p, w.pack.actions[id]) > 0.0:
			ids.append(id)
	assert_true(ids.size() >= 4)
	var fresh := {}
	for id in ids:
		fresh[id] = AutonomySystem._score(w, p, w.pack.actions[id])
	p.recent_actions = [ids[0], ids[1], ids[2]]
	p.last_action = ids[0]
	var rf := float(w.pack.cfg("repeat_factor"))
	assert_near(AutonomySystem._score(w, p, w.pack.actions[ids[0]]), fresh[ids[0]] * rf, 1e-9)
	assert_near(AutonomySystem._score(w, p, w.pack.actions[ids[1]]), fresh[ids[1]] * pow(rf, 2.0 / 3.0), 1e-9)
	assert_near(AutonomySystem._score(w, p, w.pack.actions[ids[2]]), fresh[ids[2]] * pow(rf, 1.0 / 3.0), 1e-9)
	assert_eq(AutonomySystem._score(w, p, w.pack.actions[ids[3]]), fresh[ids[3]])
	# N = 1: only the last action, the same float as the old expression
	w.pack.config["repeat_memory"] = 1
	assert_eq(AutonomySystem._score(w, p, w.pack.actions[ids[0]]), fresh[ids[0]] * rf)
	assert_eq(AutonomySystem._score(w, p, w.pack.actions[ids[1]]), fresh[ids[1]])

## Finishing an action puts it at the front of `recent_actions`, kept to `repeat_memory`.
func test_recent_actions_keep_the_last_n_finished():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	var n := int(w.pack.cfg("repeat_memory"))
	for id in ["wash_face", "eavesdrop", "pick_up", "sneak_a_bite", "wash_face"]:
		p.current = {"action": id, "object_uid": -1, "target_uid": -1, "remaining_s": 5}
		AutonomySystem._finish(w, p)
	assert_eq(p.recent_actions, ["wash_face", "sneak_a_bite", "pick_up", "eavesdrop", "wash_face"].slice(0, n))
	w.pack.config["repeat_memory"] = 2
	p.current = {"action": "pick_up", "object_uid": -1, "target_uid": -1, "remaining_s": 5}
	AutonomySystem._finish(w, p)
	assert_eq(p.recent_actions, ["pick_up", "wash_face"])
	assert_eq(p.last_action, "pick_up")
	var s := TestKit.world()
	var q := TestKit.adult(s)
	for id in s.pack.actions.keys().slice(0, 3):
		q.current = {"action": id, "object_uid": -1, "target_uid": -1, "remaining_s": 60}
		AutonomySystem._finish(s, q)
	assert_eq(q.recent_actions, [s.pack.actions.keys()[2]])

## `candidates` (the fast path on the pack's prepared table) gives exactly what `can_do`
## with any object and `_score` give, for every action, person and a few world states, on
## both packs: same actions, same order, same objects, same targets, bit-identical scores
## (leaving out, as `candidates` does, a slow action outside its `hours`); and with a
## `pool`, the best few of that list in stable score order.
func test_candidates_match_can_do_and_score():
	for id in ["_smoke", "qijia"]:
		var w: World = BalanceRun.family_of_four(id, 21)
		var checked := 0
		for state in 6:
			match state:
				1: w.set_time(w.now, 13 * 3600)          # another local hour
				2:
					for p in w.people: p.needs[p.needs.keys()[0]] = 10.0
				3: w.stock.clear()
				4:
					for p in w.people:
						p.recent_actions = w.pack.actions.keys().slice(0, 3)
						p.last_action = str(w.pack.actions.keys()[0])
						p.habits[w.pack.actions.keys()[1]] = 1.7
				5: w.pack.config["repeat_memory"] = 1 if int(w.pack.cfg("repeat_memory")) > 1 else 3
			w.advance(1800.0)
			for p in w.people:
				var expect: Array = []
				for aid in w.pack.actions:
					var a: Dictionary = w.pack.actions[aid]
					var s := AutonomySystem._score(w, p, a)
					var hours: Array = a["hours"]
					if bool(a["slow"]) and not hours.is_empty() and not AutonomySystem._in_hours(w.local_hour(), hours):
						continue
					# (and, as `candidates` does, an action for the animals that none at home
					# needs now: qijia's hens are there from the start)
					if not (a["pet"] as Dictionary).is_empty() and not AutonomySystem._pet_fits(
							AutonomySystem._table(w.pack)[w.pack.autonomy_index[aid]], PetSystem.home_key(w)):
						continue
					if s > 0.0 and AutonomySystem.can_do(w, p, aid, -1) == "":
						expect.append({"action": aid, "object_uid": AutonomySystem._free_object(w, p, a, -1) if str(a["object"]) != "" else -1,
							"target_uid": AutonomySystem._first_free_target(w, a, p), "score": s})
				var got := AutonomySystem.candidates(w, p)
				assert_eq(got.size(), expect.size(), "%s state %d person %d" % [id, state, p.uid])
				for k in mini(got.size(), expect.size()):
					assert_eq(got[k], expect[k], "%s state %d person %d" % [id, state, p.uid])
					checked += 1
				# With a pool: the first entries of a stable sort of the full list by score.
				var idx: Array = range(got.size())
				idx.sort_custom(func(i, j): return got[i].score > got[j].score or (got[i].score == got[j].score and i < j))
				for pool in [1, 3, 10]:
					var best: Array = idx.slice(0, pool).map(func(i): return got[i])
					assert_eq(AutonomySystem.candidates(w, p, pool), best, "%s state %d person %d pool %d" % [id, state, p.uid, pool])
		assert_true(checked > 30, "%s: %d candidates compared" % [id, checked])

## Sleep (slow, with an `hours` window) is never chosen outside its window: it would end at
## the next step. Inside the window it is a candidate.
func test_slow_action_is_not_chosen_outside_its_hours():
	var w := TestKit.world("qijia")   # noon
	var p := TestKit.adult(w)
	if not w.objects.any(func(o): return o.type == "kang"):
		w.add_object("kang", "hall", 0, 2)
	p.needs["energy"] = 5.0
	assert_true(AutonomySystem._score(w, p, w.pack.actions["sleep"]) > 0.0)
	assert_eq(AutonomySystem.can_do(w, p, "sleep", -1), "")
	assert_true(not AutonomySystem.candidates(w, p).any(func(c): return c.action == "sleep"))
	w.set_time(w.now, 11 * 3600)   # 23:00
	assert_true(AutonomySystem.candidates(w, p).any(func(c): return c.action == "sleep"))

func test_choice_pool_of_one_always_takes_the_best_scoring_action():
	for seed in [1, 2, 3, 4, 5, 6]:
		var w := BalanceRun.setup("qijia", seed)
		w.pack.config["choice_pool"] = 1
		var p := w.people[0]
		AutonomySystem.cancel(w, p)
		var c := AutonomySystem.candidates(w, p)
		assert_true(c.size() >= 2, "need a real choice")
		var best: Dictionary = c[0]
		for x in c:
			if x.score > best.score:
				best = x
		AutonomySystem._choose(w, p)
		assert_eq(str(p.current["action"]), str(best.action), "seed %d" % seed)

func test_wider_choice_pool_reaches_actions_outside_the_top_three():
	var seen := {}
	for seed in 40:
		var w := BalanceRun.setup("qijia", seed + 1)
		w.pack.config["choice_pool"] = 32
		var p := w.people[0]
		AutonomySystem.cancel(w, p)
		var c := AutonomySystem.candidates(w, p)
		var order: Array = range(c.size())
		order.sort_custom(func(i, j): return c[i].score > c[j].score or (c[i].score == c[j].score and i < j))
		AutonomySystem._choose(w, p)
		var rank := 0
		for k in order.size():
			if str(c[order[k]].action) == str(p.current["action"]):
				rank = k
		seen[rank] = true
		assert_true(c.size() > 3, "need more than three candidates")
	assert_true(seen.keys().any(func(r): return r >= 3), "ranks seen: " + str(seen.keys()))

