extends TestCase
const PACKS := ["_smoke", "qijia"]

func test_both_packs_valid():
	for id in PACKS:
		assert_eq(Pack.load_dir("res://packs/" + id).errors, [] as Array[String], id)

func test_qijia_action_table_has_all_three_kinds():
	var p := Pack.load_dir("res://packs/qijia")
	var n := {daily = 0, trouble = 0, flavor = 0}
	for a in p.actions.values():
		n[a.kind] += 1
	assert_true(p.actions.size() >= 20)
	assert_true(n.daily >= 8)
	assert_true(n.trouble >= 4)
	assert_true(n.flavor >= 6)

## Trouble actions are gated by a state (sick / need_below / a named illness); flavor
## actions run on `base` alone, without filling any need.
func test_qijia_action_kinds_are_honest():
	var p := Pack.load_dir("res://packs/qijia")
	for a in p.actions.values():
		match a.kind:
			"trouble":
				assert_true(a.requires.has("sick") or a.requires.has("need_below") or a.requires.has("illness"), a.id)
			"flavor":
				assert_true(a.base > 0 and a.needs.is_empty() and a.requires.is_empty(), a.id)

## 2 simulated days = 24 years at 2 real hours per year (_smoke), 12 at 4 (qijia): long
## enough for marriage and illness, short enough that nobody adopted at 22-29 reaches the
## minimum lifespan.
func test_both_packs_survive_two_days_with_caretaker():
	for id in PACKS:
		var r: Dictionary = BalanceRun.run(id, 5, 2, 100)   # 5 families, 2 days, seeds from 100
		assert_eq(r.alive_at_end, 5, id)
		assert_eq(r.deaths_neglect, 0, id)
		assert_true(r.min_money >= 0, id)
		assert_true(r.married >= 3, id)
		if id == "qijia":   # the caretaker's rice lasts: snacks do not empty the larder
			assert_true(r.food_bought_per_day <= 2.0, str(r.food_bought_per_day))
			assert_true(r.max_food_bought_in_a_day <= 2, str(r.max_food_bought_in_a_day))

## One household's first day and night on the fast clock (seeds 1 and 2, the hourly
## caretaker): in the ten minutes 10:00-10:10 every grown-up switches what they do at least
## four times; at least 20 different things done in the day; from 22:00 to 05:00 the married
## couple mostly sleeps (at most six starts each); and sleep, which has an `hours` window,
## ends when that window closes, so by 06:00 plus one step nobody is still asleep.
func test_qijia_day_is_varied_and_night_is_mostly_sleep():
	for seed in [1, 2]:
		var w: World = BalanceRun.setup("qijia", seed)   # 08:00
		var seen := {}
		var night := {}
		for h in 22:                                    # to 06:00
			BalanceRun.caretake(w)
			var events: Array = []
			if h == 2:                                  # 10:00-10:10
				w.advance(600.0)
				events = w.drain_events()
				var ten := _starts_by_person(events)
				for p in w.people:
					if p.alive and p.stage(w.pack) != "baby":
						assert_true(int(ten.get(p.uid, 0)) >= 4, "seed %d person %d: %d starts 10:00-10:10" % [seed, p.uid, int(ten.get(p.uid, 0))])
				w.advance(3000.0)
			else:
				w.advance(3600.0)
			events.append_array(w.drain_events())
			for e in events:
				if e.type == "action_started":
					seen[e.action] = true
			if h >= 14 and h < 21:                      # the hours 22:00-05:00
				var s := _starts_by_person(events)
				for uid in s:
					night[uid] = int(night.get(uid, 0)) + int(s[uid])
			if h == 13:
				assert_true(w.married, "seed %d not married by 22:00" % seed)
		w.advance(float(w.step_s))
		assert_true(seen.size() >= 20, "seed %d: %d: %s" % [seed, seen.size(), seen.keys()])
		var adults := 0
		for p in w.people:
			if p.alive and p.stage(w.pack) in ["adult", "elder"]:
				adults += 1
				assert_true(int(night.get(p.uid, 0)) <= 6, "seed %d person %d: %d starts" % [seed, p.uid, int(night.get(p.uid, 0))])
				assert_true(str(p.current.get("action", "")) != "sleep", "seed %d person %d still asleep at 06:00:05" % [seed, p.uid])
		assert_eq(adults, 2, "seed %d" % seed)

## A reading-track adult living alone, 10:00-11:00 of the first day (proposals declined):
## at least 1.5 action starts per minute, at least 10 different actions, never the same
## action three times in a row, and at least four switches in every ten minutes.
func test_qijia_lone_adult_daytime_hour_is_varied():
	for seed in [1, 2]:
		var w: World = BalanceRun.setup("qijia", seed)   # 08:00
		var p: Person = w.people[0]
		assert_eq(p.track, "reading")
		for h in 2:
			_decline_and_care(w)
			w.advance(3600.0)
		_decline_and_care(w)
		w.drain_events()
		var seq: Array = []
		var per_ten := [0, 0, 0, 0, 0, 0]
		for m in 60:
			w.advance(60.0)
			for e in w.drain_events():
				if e.type == "action_started" and e.person == p.uid:
					seq.append(e.action)
					per_ten[m / 10] += 1
		assert_eq(w.people.size(), 1, "seed %d" % seed)
		var msg := "seed %d: %s" % [seed, seq]
		assert_true(seq.size() >= 90, "%.2f starts per minute; %s" % [seq.size() / 60.0, msg])
		var distinct := {}
		for a in seq:
			distinct[a] = true
		assert_true(distinct.size() >= 10, "%d distinct; %s" % [distinct.size(), msg])
		for i in range(2, seq.size()):
			assert_true(not (seq[i] == seq[i - 1] and seq[i] == seq[i - 2]), "%s three times in a row; %s" % [seq[i], msg])
		for k in 6:
			assert_true(per_ten[k] >= 4, "ten minutes #%d: %d starts; %s" % [k, per_ten[k], msg])

func _decline_and_care(w: World) -> void:
	while not w.proposals.is_empty():
		w.command({"type": "answer_proposal", "id": w.proposals[0]["id"], "accept": false})
	BalanceRun.caretake(w)

func _starts_by_person(events: Array) -> Dictionary:
	var out := {}
	for e in events:
		if e.type == "action_started":
			out[e.person] = int(out.get(e.person, 0)) + 1
	return out

func test_setup_places_one_of_each_object_and_adopts():
	for id in PACKS:
		var w: World = BalanceRun.setup(id, 7)
		assert_eq(w.phase, "living", id)
		assert_eq(w.people.size(), 1, id)
		assert_eq(w.objects.size(), w.pack.object_types.size(), id)
		var types := {}
		for o in w.objects:
			types[o.type] = true
		assert_eq(types.size(), w.pack.object_types.size(), id)

## A married couple sharing one kang both sleep through the night.
func test_qijia_two_adults_share_one_kang_overnight():
	var w := TestKit.world("qijia")
	var a := TestKit.adult(w)
	var b := TestKit.adult(w)
	var kang: String = str(w.pack.actions["sleep"]["object"])
	w.add_object(kang, w.rooms_built[0], 0, 0)
	w.set_time(1767268800 + 9 * 3600, 0)
	a.needs["energy"] = 20.0
	b.needs["energy"] = 20.0
	for i in 3 * 60:
		w.advance(60.0)
	assert_eq(str(a.current.get("action", "")), "sleep")
	assert_eq(str(b.current.get("action", "")), "sleep")

## The step length must not change how fast things happen: the same qijia content at 60 s
## and at 5 s steps gives about the same average number of illnesses, messes, drops and
## proposals per household over two days (wide margin: the random sequences differ).
func test_qijia_event_rates_do_not_depend_on_step_length():
	var at60 := _qijia_event_averages(60)
	var at5 := _qijia_event_averages(5)
	for k in at60:
		var msg := "%s: %.2f at 60 s vs %.2f at 5 s" % [k, at60[k], at5[k]]
		assert_true(at60[k] > 0.0 and at5[k] > 0.0, msg)
		assert_true(absf(at5[k] - at60[k]) <= 0.35 * at60[k], msg)

## Per-household averages of the dice-driven events, 10 households x 2 days with the
## hourly caretaker, the qijia pack run at `step` seconds and action speed 1.
func _qijia_event_averages(step: int) -> Dictionary:
	var pack := Pack.load_dir("res://packs/qijia")
	pack.config["step_seconds"] = step
	# Actions at their full length in both arms, so both make the same number of actions
	# (and of action-made messes): only what the step length must not change is compared.
	pack.config["action_speed"] = 1
	# Illness is rare (0.3 a day): raised in both arms so each counts enough cases to compare.
	pack.config["illness_daily_chance"] = 2.0
	var counts := {"fell_ill": 0.0, "mess_spawned": 0.0, "collectible_spawned": 0.0, "proposal_arrived": 0.0}
	for i in 10:
		var w := BalanceRun.setup_pack(pack, 300 + i)
		assert_eq(w.step_s, step)
		for h in 48:
			BalanceRun.caretake(w)
			w.advance(3600.0)
			for e in w.drain_events():
				if counts.has(e.type):
					counts[e.type] += 1.0
	for k in counts:
		counts[k] /= 10.0
	return counts
