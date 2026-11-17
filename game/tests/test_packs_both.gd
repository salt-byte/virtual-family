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

## 2 simulated days = 24 years at 2 real hours per year: long enough for marriage and
## illness, short enough that nobody adopted at 22-29 reaches the minimum lifespan.
func test_both_packs_survive_two_days_with_caretaker():
	for id in PACKS:
		var r: Dictionary = BalanceRun.run(id, 5, 2, 100)   # 5 families, 2 days, seeds from 100
		assert_eq(r.alive_at_end, 5, id)
		assert_eq(r.deaths_neglect, 0, id)
		assert_true(r.min_money >= 0, id)
		assert_true(r.married >= 3, id)

func test_qijia_people_show_variety():
	var w: World = BalanceRun.setup("qijia", 1)
	var seen := {}
	for i in 24 * 60:
		w.advance(60)
		for p in w.people:
			if not p.current.is_empty():
				seen[p.current.action] = true
	assert_true(seen.size() >= 8, str(seen.keys()))

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

## Per-household averages of the dice-driven events, 30 households x 2 days with the
## hourly caretaker, the qijia pack run at `step` seconds.
func _qijia_event_averages(step: int) -> Dictionary:
	var pack := Pack.load_dir("res://packs/qijia")
	pack.config["step_seconds"] = step
	var counts := {"fell_ill": 0.0, "mess_spawned": 0.0, "collectible_spawned": 0.0, "proposal_arrived": 0.0}
	for i in 30:
		var w := BalanceRun.setup_pack(pack, 300 + i)
		assert_eq(w.step_s, step)
		for h in 48:
			BalanceRun.caretake(w)
			w.advance(3600.0)
			for e in w.drain_events():
				if counts.has(e.type):
					counts[e.type] += 1.0
	for k in counts:
		counts[k] /= 30.0
	return counts
