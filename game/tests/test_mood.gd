extends TestCase
## Low mood: sad, then depressed, and back; what depression changes; the attention ceiling.

func _home() -> World:
	var w := TestKit.world("qijia", 1)
	w.adopted_once = true
	w.pack.config["wish_chance_per_hour"] = 0.0
	var p := TestKit.adult(w)
	p.track = "reading"
	w.stock["food"] = 50
	return w


## Holds the mood need at `v` for `hours`, one minute at a time; returns the events.
func _hold(w: World, v: float, hours: float) -> Array:
	var out: Array = []
	for i in int(hours * 60):
		for p in w.people:
			p.needs["happy"] = v
			p.needs["fed"] = maxf(float(p.needs["fed"]), 50.0)
		w.advance(60)
		out.append_array(w.drain_events())
	return out


func _moods(events: Array) -> Array:
	return events.filter(func(e): return e.type == "mood_changed").map(func(e): return e.mood)


func test_smoke_never_gets_low_mood():
	var w := TestKit.world("_smoke")
	var p := TestKit.adult(w)
	for i in 48:
		for nid in p.needs:
			p.needs[nid] = maxf(float(p.needs[nid]), 30.0)
		w.advance(3600)
	assert_eq(p.mood, "")
	assert_true(not MoodSystem.enabled(w.pack))


func test_low_mood_turns_sad_then_depressed():
	var w := _home()
	var p := w.people[0]
	assert_eq(_moods(_hold(w, 10.0, 5.9)), [])
	assert_eq(_moods(_hold(w, 10.0, 0.2)), ["sad"])
	assert_eq(_moods(_hold(w, 10.0, 17.8)), [])
	assert_eq(_moods(_hold(w, 10.0, 0.3)), ["depressed"])
	assert_eq(p.mood, "depressed")


func test_between_the_lines_neither_clock_runs():
	var w := _home()
	var p := w.people[0]
	_hold(w, 10.0, 5.0)
	_hold(w, 40.0, 10.0)
	assert_eq(p.mood, "")
	assert_eq(_moods(_hold(w, 10.0, 1.1)), ["sad"])


func test_recovery_goes_back_through_sadness():
	var w := _home()
	var p := w.people[0]
	_hold(w, 10.0, 24.5)
	assert_eq(p.mood, "depressed")
	assert_eq(_moods(_hold(w, 80.0, 11.9)), [])
	assert_eq(_moods(_hold(w, 80.0, 0.2)), ["sad"])
	assert_eq(_moods(_hold(w, 80.0, 3.0)), [""])
	assert_eq(p.mood, "")


func test_medicine_does_not_cure_depression():
	var w := _home()
	var p := w.people[0]
	p.mood = "depressed"
	p.illness = "chill"
	w.money = 100
	w.command({"type": "buy", "item": "ginger_pill"})
	w.command({"type": "use_item", "item": "ginger_pill", "person": p.uid})
	assert_eq(p.illness, "")
	assert_eq(p.mood, "depressed")


func test_depressed_work_pays_coins_but_no_progress():
	var w := _home()
	var p := w.people[0]
	p.mood = "depressed"
	var m := w.money
	EconomySystem.on_work_finished(w, p, 60.0)
	assert_near(p.progress, 0.0)
	assert_true(w.money > m)


func test_depressed_mostly_do_the_heavy_things():
	var w := _home()
	var p := w.people[0]
	p.mood = "depressed"
	var heavy := 0
	var all := 0
	for i in 6 * 60:
		p.needs["happy"] = 10.0
		w.advance(60)
		for e in w.drain_events():
			if e.type == "action_started":
				all += 1
				if (w.pack.actions[e.action]["requires"] as Dictionary).get("mood", "") == "depressed":
					heavy += 1
	assert_true(all > 10)
	assert_true(heavy * 2 > all, "%d of %d" % [heavy, all])


func test_depression_drains_food_faster():
	var w := _home()
	var a := w.people[0]
	var b := TestKit.adult(w)
	b.track = "reading"
	a.mood = "depressed"
	a.needs["fed"] = 80.0
	b.needs["fed"] = 80.0
	MoodSystem.step(w, 3600.0)
	assert_near(float(a.needs["fed"]), 78.5)
	assert_near(float(b.needs["fed"]), 80.0)


func test_the_absent_do_not_sink():
	var w := _home()
	var p := w.people[0]
	w.offline = true
	_hold(w, 10.0, 8.0)
	w.offline = false
	assert_eq(p.mood, "")


func test_without_attention_own_doings_only_lift_mood_so_far():
	var w := _home()
	var p := w.people[0]
	w.advance(60)
	assert_true(p.cared_at > 0 and p.cared_at <= w.now)
	p.cared_at = w.now
	assert_near(MoodSystem.ceiling(w, p), 100.0)
	w.now += 22 * 3600
	assert_near(MoodSystem.ceiling(w, p), 75.0, 0.1)
	w.now += 100 * 3600
	assert_near(MoodSystem.ceiling(w, p), 10.0)
	p.praise_times = []
	p.current = {"action": "weave", "object_uid": -1, "target_uid": -1, "remaining_s": 120}
	assert_true(w.command({"type": "praise", "person": p.uid}).ok)
	assert_near(MoodSystem.ceiling(w, p), 100.0)


## Neglect: food and medicine but never a treat, a praise or a wish granted. Within four days
## someone is depressed; then treats every few hours bring everyone back.
func test_neglected_household_sinks_and_recovers_with_care():
	var w := BalanceRun.setup("qijia", 2)
	var deep_at := -1
	for h in 4 * 24:
		_basic_care(w)
		w.advance(3600)
		if deep_at < 0 and w.people.any(func(p: Person): return p.alive and p.mood == "depressed"):
			deep_at = h
	assert_true(deep_at >= 0, "nobody became depressed in four days")
	for h in 2 * 24:
		_basic_care(w)
		for p in w.people:
			if p.alive and h % 3 == 0:
				w.money += 20
				w.command({"type": "buy", "item": "sugar_figure"})
				w.command({"type": "use_item", "item": "sugar_figure", "person": p.uid})
		w.advance(3600)
	for p in w.people:
		if p.alive:
			assert_eq(p.mood, "", "%s still %s" % [p.given, p.mood])


func _basic_care(w: World) -> void:
	if not w.proposals.is_empty():
		w.command({"type": "answer_proposal", "id": w.proposals[0]["id"], "accept": true})
	if int(w.stock.get("food", 0)) < 3:
		w.command({"type": "buy", "item": "rice"})
	for p in w.people:
		if p.alive and p.illness != "":
			var ill := p.illness
			for id in w.pack.items:
				if w.pack.items[id]["cures"] == ill and w.command({"type": "buy", "item": id}).ok:
					w.command({"type": "use_item", "item": id, "person": p.uid})
