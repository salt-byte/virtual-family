extends TestCase
## Outings (actions with `outing`; see `OutingSystem`): someone leaves through the gate, is
## away for a few fast hours and comes back with something; the player can send them.

## 2026-01-01 12:00 UTC (local noon), the start of qijia's year.
const NOON := 1767268800


func _w(seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	w.set_time(NOON + 30 * 60, 0)  # 12:30: no festival on
	return w


func _back(events: Array) -> Array:
	return events.filter(func(e): return e.type == "outing_back")


func test_qijia_outings_leave_through_the_gate_and_take_a_few_hours():
	var p := Pack.load_dir("res://packs/qijia")
	var ids: Array = []
	for id in p.actions:
		var a: Dictionary = p.actions[id]
		if OutingSystem.is_outing(a):
			ids.append(id)
			assert_eq(a["rooms"], ["gate"], id)
			assert_true(int(a["duration_min"]) >= 120 and int(a["duration_min"]) <= 240, id)
			assert_true((a["outing"]["returns"] as Array).size() >= 3, id)
			for r in a["outing"]["returns"]:
				assert_true(str(r["text"]).contains("{name}"), "%s: %s" % [id, r["text"]])
	for id in ["go_to_market", "temple_fair", "see_lanterns"]:
		assert_true(ids.has(id), id)


func test_go_out_sends_someone_away_and_they_come_back_with_something():
	var w := _w(); var p := TestKit.adult(w); var other := TestKit.adult(w)
	w.inventory["sugar_figure"] = 1
	var r := w.command({"type": "go_out", "person": p.uid, "action": "go_to_market"})
	assert_true(r.ok, str(r))
	assert_eq(str(p.current["action"]), "go_to_market")
	assert_eq(str(p.current["room"]), "gate", "they leave through the gate")
	assert_true(OutingSystem.away(w, p))
	assert_true(not OutingSystem.away(w, other))
	# While away nobody can reach them, and nothing is spent trying.
	assert_eq(w.command({"type": "praise", "person": p.uid}).error, "requires")
	assert_eq(w.command({"type": "use_item", "person": p.uid, "item": "sugar_figure"}).error, "requires")
	assert_eq(int(w.inventory["sugar_figure"]), 1)
	assert_eq(w.command({"type": "drag", "person": p.uid, "object": 999}).error, "requires")
	assert_eq(w.command({"type": "go_out", "person": p.uid, "action": "temple_fair"}).error, "requires")
	var happy := float(p.needs["happy"])
	var inv_before := w.inventory.duplicate()
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["go_to_market"]))
	var back := _back(w.drain_events())
	assert_eq(back.size(), 1)
	assert_eq(int(back[0].person), p.uid)
	assert_true(str(back[0].text).contains("{name}"))
	if str(back[0].item) != "":
		assert_eq(int(w.inventory.get(back[0].item, 0)), int(inv_before.get(back[0].item, 0)) + 1)
	assert_true(not OutingSystem.away(w, p))
	assert_true(float(p.needs["happy"]) > happy, "a day out lifts the mood")


func test_go_out_says_why_not():
	var w := _w(); var p := TestKit.adult(w)
	var kid := TestKit.adult(w, 8.0)
	assert_eq(w.command({"type": "go_out", "person": 999, "action": "go_to_market"}).error, "no_person")
	assert_eq(w.command({"type": "go_out", "person": p.uid, "action": "nap"}).error, "no_action")
	assert_eq(w.command({"type": "go_out", "person": p.uid, "action": "fell_old_bamboo"}).error, "no_action", "work is not an outing")
	assert_eq(w.command({"type": "go_out", "person": kid.uid, "action": "go_to_market"}).error, "stage")
	assert_eq(w.command({"type": "go_out", "person": p.uid, "action": "see_lanterns"}).error, "requires")
	w.set_time(NOON + 10 * 3600, 0)  # 22:00: the market is long over
	assert_eq(w.command({"type": "go_out", "person": p.uid, "action": "go_to_market"}).error, "requires")
	w.kill_person(kid, "old_age")
	assert_eq(w.command({"type": "go_out", "person": kid.uid, "action": "temple_fair"}).error, "dead")


func test_the_player_can_send_someone_to_a_place_outside_the_wall():
	var w := _w(); var p := TestKit.adult(w)
	assert_true(OutingSystem.sendable(w.pack, w.pack.actions["fish_off_bank"]))
	assert_true(not OutingSystem.sendable(w.pack, w.pack.actions["watch_moon"]))
	var r := w.command({"type": "go_out", "person": p.uid, "action": "fish_off_bank"})
	assert_true(r.ok, str(r))
	assert_eq(str(p.current["room"]), "riverside")
	assert_true(not OutingSystem.away(w, p), "the river is in sight: they are not away")


func test_options_list_what_someone_could_be_sent_to_do():
	var w := _w(); var p := TestKit.adult(w)
	var ids: Array = OutingSystem.options(w, p).map(func(o): return o.action)
	for id in ["go_to_market", "temple_fair", "fish_off_bank", "pace_the_ridge"]:
		assert_true(ids.has(id), id)
	assert_true(not ids.has("see_lanterns"), "a festival's outing waits for the festival")
	for o in OutingSystem.options(w, p):
		assert_eq(o.why, "", o.action)
	var w2 := TestKit.world("qijia")
	w2.set_time(NOON + 12 * 60, 0)  # 元宵
	var p2 := TestKit.adult(w2)
	ids = OutingSystem.options(w2, p2).map(func(o): return o.action)
	assert_true(ids.has("see_lanterns"), str(ids))
	var kid := TestKit.adult(w2, 8.0)
	var kid_ids: Array = OutingSystem.options(w2, kid).map(func(o): return o.action)
	assert_true(kid_ids.has("skip_stones") and not kid_ids.has("go_to_market"))


func test_an_outing_wish_waits_while_they_are_out_and_is_granted_on_return():
	var w := _w(); var p := TestKit.adult(w)
	p.wish = {"id": "want_market", "expires_at": w.now + 60}
	assert_true(w.command({"type": "go_out", "person": p.uid, "action": "go_to_market"}).ok)
	w.advance(120)
	assert_eq(str(p.wish.get("id", "")), "want_market", "kept past its time while out")
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["go_to_market"]))
	var types: Array = w.drain_events().map(func(e): return e.type)
	assert_true(types.has("outing_back") and types.has("wish_granted"), str(types))
	assert_true(types.find("outing_back") < types.find("wish_granted"), "back first, then thanks")
	assert_eq(p.wish, {})


func test_what_they_bring_back_is_the_same_for_the_same_seed():
	var got: Array = []
	for k in 2:
		var w := _w(7); var p := TestKit.adult(w)
		var seq: Array = []
		for i in 4:
			w.set_time(NOON + 30 * 60 + i * 86400, 0)
			w.command({"type": "go_out", "person": p.uid, "action": "temple_fair"})
			w.drain_events()
			w.advance(AutonomySystem.duration_s(w, w.pack.actions["temple_fair"]))
			seq.append_array(_back(w.drain_events()).map(func(e): return e.text))
		got.append(seq)
	assert_eq(got[0].size(), 4)
	assert_eq(got[0], got[1])


func test_outings_happen_in_a_day_of_play():
	var r: Dictionary = BalanceRun.run("qijia", 3, 1, 50)
	var n := 0
	for id in r["outings_back"]:
		n += int(r["outings_back"][id])
	assert_true(n >= 3, str(r["outings_back"]))
