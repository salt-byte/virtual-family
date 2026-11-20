extends TestCase
## Asks: a person signals what they need and waits for the player before dealing with it
## themselves; help in the window gives the full effect and a thank-you; while the player
## is away nobody waits.


## One adopted grown-up in a house with one of each object, every need at 90, food in the
## larder, at 09:00 local; no chance illness, no wishes and no asks by chance unless asked.
func _home(chance_asks := 0.0, seed := 1) -> World:
	var w := BalanceRun.setup("qijia", seed)
	w.set_time(w.now, 3600)
	w.pack.config["illness_daily_chance"] = 0.0
	w.pack.config["wish_chance_per_hour"] = 0.0
	w.pack.config["ask_chance_per_hour"] = chance_asks
	var p := w.people[0]
	p.current = {}
	p.wish = {}
	for n in w.pack.needs:
		p.needs[n] = 90.0
	w.stock["food"] = 50
	# The hens that come with the house leave: these tests follow the person's own choices
	# (with hens about, the dice fall elsewhere and seed 1 picks shelling beans, which cheers).
	w.pets.clear()
	w.drain_events()
	return w


func _first_object(w: World, type: String) -> int:
	for o in w.objects:
		if o.type == type:
			return int(o.uid)
	return -1


func _types(events: Array) -> Array:
	return events.map(func(e): return str(e.type))


## Steps until `p` holds an ask (at most `seconds`).
func _until_ask(w: World, p: Person, seconds: int) -> void:
	var t := 0
	while p.ask.is_empty() and t < seconds:
		w.advance(float(w.step_s))
		t += w.step_s


func test_smoke_has_no_asks():
	var w := TestKit.world("_smoke")
	var p := TestKit.adult(w)
	assert_true(not AskSystem.enabled(w.pack))
	for n in p.needs:
		p.needs[n] = 5.0
	w.advance(600.0)
	assert_true(p.ask.is_empty())
	assert_true(not _types(w.drain_events()).has("ask_formed"))
	assert_true(not p.to_dict().has("ask") and not p.to_dict().has("ask_last_t") and not p.to_dict().has("ask_again"))
	assert_near(AskSystem.fix_factor(w.pack, p), 1.0)


func test_qijia_asks_load_and_check():
	var pack := Pack.load_dir("res://packs/qijia")
	assert_true(pack.is_valid(), "\n".join(pack.errors))
	assert_true(pack.asks.size() >= 10)
	for id in pack.asks:
		var e: Dictionary = pack.asks[id]
		assert_true(AskSystem.KINDS.has(str(e["kind"])), id)
		assert_true(str(e["text"]).length() <= 6, "short words: " + id)
		assert_true(str(e["icon"]) != "", "an icon: " + id)
	for need in ["fed", "energy", "clean"]:
		assert_true(pack.asks.values().any(func(e): return str(e["kind"]) == "need" and str(e["need"]) == need), need)
	pack.asks["hunger"]["kind"] = "nap"
	pack.asks["snack"]["items"] = ["no_such_thing"]
	pack.asks["sit_in_yard"]["actions"] = []
	pack.asks["grubby"]["above"] = 10
	var errs := PackValidator.validate(pack)
	for want in ["asks.json: hunger: kind 'nap' must be one of need, praise, hold, item, do",
			"asks.json: snack: an item ask needs items: a non-empty array of item ids",
			"asks.json: sit_in_yard: a do ask needs actions: a non-empty array of action ids",
			"asks.json: grubby: a need ask needs a number below (and above, if given, at least below)"]:
		assert_true(errs.has(want), "missing: " + want + "\n" + "\n".join(errs))


func test_a_low_need_waits_for_the_player_then_the_person_deals_with_it():
	var w := _home()
	var p := w.people[0]
	p.needs["fed"] = 66.0
	_until_ask(w, p, 30)
	assert_eq(str(p.ask.get("id", "")), "hunger")
	assert_true(AskSystem.waiting(p))
	var formed_at := w.now
	var fixers := AskSystem.fixers(w.pack, "hunger")
	assert_true(fixers.has(int(w.pack.autonomy_index["cook_porridge"])))
	# While it waits, nothing that would feed them is chosen.
	var started: Array = []
	while w.now - formed_at < int(w.pack.cfg("ask_wait_s")) - w.step_s:
		for c in AutonomySystem.candidates(w, p, int(w.pack.cfg("choice_pool"))):
			assert_true(not fixers.has(int(w.pack.autonomy_index[c.action])), "chose to eat while waiting: " + c.action)
		w.advance(float(w.step_s))
		for e in w.drain_events():
			if e.type == "action_started":
				started.append(e.action)
	assert_true(AskSystem.waiting(p))
	for a in started:
		assert_true(not fixers.has(int(w.pack.autonomy_index[a])), a)
	# Ignored: a little mood lost, then they see to it themselves.
	p.needs["happy"] = 80.0
	w.advance(float(w.step_s * 2))
	assert_eq(str(p.ask.get("phase", "")), "self")
	assert_true(float(p.needs["happy"]) < 80.0 - 1.5, str(p.needs["happy"]))
	var events := _types(w.drain_events())
	assert_true(events.has("ask_ignored"), str(events))
	var dealt := false
	for k in int(w.pack.cfg("ask_self_s")) / w.step_s + 1:
		w.advance(float(w.step_s))
		if _types(w.drain_events()).has("ask_self"):
			dealt = true
			break
	assert_true(dealt, "never fed themselves")
	assert_true(p.ask.is_empty())
	assert_true(fixers.has(int(w.pack.autonomy_index[str(p.current.get("action", p.last_action))])))
	assert_true(not p.thanking(w.now), "no thank-you for what they did alone")


func test_help_in_the_window_gives_the_full_effect_and_a_thank_you():
	var w := _home()
	var p := w.people[0]
	p.needs["clean"] = 50.0
	_until_ask(w, p, 30)
	assert_eq(str(p.ask.get("id", "")), "grubby")
	w.advance(20.0)
	assert_true(AskSystem.waiting(p))
	p.needs["happy"] = 70.0
	var r := w.command({"type": "drag", "person": p.uid, "object": _first_object(w, "washtub")})
	assert_true(r.ok, str(r))
	assert_eq(str(p.current["action"]), "bathe_in_tub")
	assert_true(bool(p.current.get("led", false)))
	assert_true(p.ask.is_empty())
	assert_true(p.thanking(w.now))
	assert_near(float(p.needs["happy"]), 70.0 + float(w.pack.asks["grubby"]["joy"]))
	assert_true(_types(w.drain_events()).has("ask_helped"))
	assert_true(not p.ask_again.has("grubby"), "a met ask may come again")
	w.advance(120.0)
	assert_true(float(p.needs["clean"]) > 95.0, "the full bath: " + str(p.needs["clean"]))


func test_attention_asks_are_met_by_praise_a_drag_an_item_or_leading_them():
	var w := _home()
	var p := w.people[0]
	var cases := {"praise_me": {"type": "praise", "person": p.uid},
		"bored": {"type": "drag", "person": p.uid, "object": _first_object(w, "stool")},
		"snack": {"type": "use_item", "person": p.uid, "item": "tanghulu"},
		"sit_in_yard": {"type": "drag", "person": p.uid, "object": _first_object(w, "stone_bench"), "action": "pick_ears"}}
	for id in cases:
		AutonomySystem.cancel(w, p)
		AutonomySystem.start(w, p, "wipe_table", -1)
		p.thanks_until = 0
		p.ask = {"id": id, "phase": "wait", "until": w.now + 75}
		if id == "snack":
			w.money = 100
			assert_true(w.command({"type": "buy", "item": "tanghulu"}).ok)
		var r := w.command(cases[id])
		assert_true(r.ok, id + " " + str(r))
		assert_true(p.ask.is_empty(), id)
		assert_true(p.thanking(w.now), id)
	# A praise does not meet a wish to be picked up.
	p.thanks_until = 0
	p.ask = {"id": "bored", "phase": "wait", "until": w.now + 75}
	w.command({"type": "praise", "person": p.uid})
	assert_eq(str(p.ask.get("id", "")), "bored")


func test_ignored_attention_ask_ends_with_a_small_mood_loss():
	var w := _home()
	var p := w.people[0]
	p.ask = {"id": "praise_me", "phase": "wait", "until": w.now + 10}
	p.needs["happy"] = 80.0
	w.advance(15.0)
	assert_true(p.ask.is_empty())
	assert_true(int(p.ask_again.get("praise_me", 0)) >= w.now + int(w.pack.cfg("ask_again_s")) - 15, "stays away a while")
	assert_true(float(p.needs["happy"]) < 78.5, "%f %s" % [p.needs["happy"], p.current])
	assert_true(_types(w.drain_events()).has("ask_expired"))


func test_chance_asks_come_every_few_minutes_and_not_in_sleep():
	var w := _home(6.0)
	var p := w.people[0]
	var formed := 0
	for k in 3600 / w.step_s:
		w.advance(float(w.step_s))
		for e in w.drain_events():
			if e.type == "ask_formed":
				formed += 1
	assert_true(formed >= 3 and formed <= 15, str(formed))
	AutonomySystem.cancel(w, p)
	p.ask = {}
	p.ask_last_t = 0
	w.utc_offset += 14 * 3600  # 23:00: bedtime
	AutonomySystem.start(w, p, "sleep", _first_object(w, "kang"))
	w.pack.config["ask_chance_per_hour"] = 1000.0
	w.advance(60.0)
	assert_true(p.ask.is_empty(), "asked in their sleep")


func test_while_the_player_is_away_nobody_waits():
	var w := _home()
	var p := w.people[0]
	# An ask waiting when the player left goes straight to dealing with it, unpenalised.
	p.ask = {"id": "hunger", "phase": "wait", "until": w.now + 75}
	p.needs["fed"] = 66.0
	p.needs["happy"] = 80.0
	w.offline = true
	w.advance(float(w.step_s))
	assert_eq(str(p.ask.get("phase", "")), "self")
	assert_near(float(p.needs["happy"]), 80.0, 0.1)
	assert_near(AskSystem.fix_factor(w.pack, p), float(w.pack.cfg("ask_self_factor")))
	w.offline = false
	# No new asks form while away: low needs are simply dealt with.
	p.ask = {}
	p.needs["clean"] = 40.0
	var summary := w.catch_up(1800.0)
	assert_true(summary.simulated_seconds > 0)
	assert_true(p.ask.is_empty())
	var events := _types(w.drain_events())
	assert_true(not events.has("ask_formed") and not events.has("ask_ignored"), str(events))


func test_an_ask_survives_a_save_and_old_saves_load():
	var w := _home()
	var p := w.people[0]
	p.ask = {"id": "sleepy", "phase": "wait", "until": w.now + 40}
	p.ask_again = {"snack": w.now + 300}
	p.ask_last_t = w.now - 5
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(w.to_dict())))
	var q := back.people[0]
	assert_eq(q.ask, {"id": "sleepy", "phase": "wait", "until": w.now + 40})
	assert_eq(q.ask_again, {"snack": w.now + 300})
	assert_eq(q.ask_last_t, w.now - 5)
	var d := p.to_dict()
	d.erase("ask")
	d.erase("ask_last_t")
	d.erase("ask_again")
	var old := Person.from_dict(d)
	assert_true(old.ask.is_empty() and old.ask_again.is_empty() and old.ask_last_t == 0)
