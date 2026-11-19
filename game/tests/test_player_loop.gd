extends TestCase
## The player is needed: a need people cannot fix well alone (hygiene), fixes the player leads
## by dragging, a status that follows the moment, litter to drag people to, and people who
## turn to tell the player what they earned.


## One adopted grown-up, a reader at the first level, in a house with one of each object
## (a bath tub among them), at 08:00; no chance illness and no mood wishes.
func _home(seed := 1) -> World:
	var w := BalanceRun.setup("qijia", seed)
	w.pack.config["illness_daily_chance"] = 0.0
	w.pack.config["wish_chance_per_hour"] = 0.0
	var p := w.people[0]
	p.track = "reading"
	p.level = 0
	p.progress = 0.0
	p.current = {}
	p.wish = {}
	for n in w.pack.needs:
		p.needs[n] = 90.0
	w.stock["food"] = 50
	w.drain_events()
	return w


## Runs `steps` steps of the world.
func _run(w: World, seconds: float) -> void:
	w.advance(seconds)


func _place(w: World, type: String) -> int:
	for room in w.rooms_built:
		var r: Dictionary = w.pack.rooms[room]
		for y in int(r["h"]):
			for x in int(r["w"]):
				var uid := w.add_object(type, room, x, y)
				if uid >= 0:
					return uid
	return -1


func _first_object(w: World, type: String) -> int:
	for o in w.objects:
		if o.type == type:
			return int(o.uid)
	return -1


func test_smoke_has_none_of_it():
	var w := TestKit.world("_smoke")
	var p := TestKit.adult(w)
	assert_eq(FeelingSystem.now(w, p), "")
	assert_true(not ShareSystem.enabled(w.pack))
	assert_true(not bool(NeedsSystem._table(w.pack)[8]["on"]))
	assert_near(NeedsSystem.illness_factor(w, p), 1.0)
	for id in w.pack.actions:
		assert_true(not AutonomySystem.player_led(w.pack.actions[id]), id)


func test_qijia_has_a_clean_need_with_low_effects():
	var w := _home()
	var p := w.people[0]
	assert_true(w.pack.needs.has("clean"))
	assert_true(p.needs.has("clean"))
	p.needs["clean"] = 80.0
	assert_near(NeedsSystem.illness_factor(w, p), 1.0)
	p.needs["clean"] = 10.0
	assert_near(NeedsSystem.illness_factor(w, p), 1.5)
	w.offline = true
	assert_near(NeedsSystem.illness_factor(w, p), 1.0, 0.001, "no harsher odds while away")
	w.offline = false
	# While dirty, the mood sinks a little faster.
	var a := _home(); var b := _home()
	a.people[0].needs["clean"] = 80.0
	b.people[0].needs["clean"] = 10.0
	for q in [a.people[0], b.people[0]]:
		q.needs["happy"] = 60.0
		q.current = {"action": "shell_beans", "object_uid": -1, "target_uid": -1, "remaining_s": 99999}
	NeedsSystem.step(a, 3600.0)
	NeedsSystem.step(b, 3600.0)
	assert_true(float(b.people[0].needs["happy"]) < float(a.people[0].needs["happy"]) - 1.0)


func test_work_rain_and_play_in_the_mud_dirty_faster_than_sitting_still():
	var w := _home()
	var p := w.people[0]
	var rate := func(action: String) -> float:
		p.needs["clean"] = 80.0
		p.current = {"action": action, "object_uid": -1, "target_uid": -1, "remaining_s": 99999}
		NeedsSystem.step(w, 600.0)
		return 80.0 - float(p.needs["clean"])
	var still: float = rate.call("shell_beans")
	var work: float = rate.call("study")
	var sweep: float = rate.call("sweep")
	var mud: float = rate.call("stomp_puddles")
	assert_true(work > still * 2.0, "%f vs %f" % [work, still])
	assert_true(sweep > work, "%f vs %f" % [sweep, work])
	assert_true(mud > sweep, "%f vs %f" % [mud, sweep])
	w.weather = "drizzle"
	var wet_out: float = rate.call("well_reflection")
	w.weather = "clear"
	var dry_out: float = rate.call("well_reflection")
	assert_true(wet_out > dry_out + 1.0, "%f vs %f" % [wet_out, dry_out])


func test_nobody_bathes_alone_but_a_dragged_bath_fixes_hygiene():
	var w := _home()
	var p := w.people[0]
	p.needs["clean"] = 15.0
	_place(w, "washtub")
	for c in AutonomySystem.candidates(w, p):
		assert_true(not str(c.action).begins_with("bathe_"), str(c.action))
	var tub := _first_object(w, "washtub")
	var r := w.command({"type": "drag", "person": p.uid, "object": tub})
	assert_true(r.ok, str(r))
	assert_eq(str(r.action), "bathe_in_tub")
	assert_true(bool(p.current["led"]))
	assert_eq(FeelingSystem.now(w, p), "洗得正舒坦")
	for i in 200:
		if p.current.is_empty() or str(p.current["action"]) != "bathe_in_tub":
			break
		w.advance(5)
	assert_true(float(p.needs["clean"]) > 95.0, str(p.needs["clean"]))
	assert_eq(FeelingSystem.now(w, p), "清清爽爽")
	# At the well, without a tub, the drop starts the bath too (not fetching water).
	var v := _home()
	var q := v.people[0]
	q.needs["clean"] = 20.0
	assert_true(int(v.local_hour()) == 8)  # when fetching water at the well is also open
	var well := _first_object(v, "well_head")
	if well < 0:
		HouseSystem.place_props(v, "well", true)
		well = _first_object(v, "well_head")
	var rw := v.command({"type": "drag", "person": q.uid, "object": well})
	assert_true(rw.ok, str(rw))
	assert_eq(str(rw.action), "bathe_at_well")


func test_own_fixes_are_weak_and_the_players_are_full():
	var w := _home()
	var p := w.people[0]
	var a: Dictionary = w.pack.actions["change_clothes"]
	assert_near(AutonomySystem.self_factor(a, "clean"), 0.25)
	assert_near(AutonomySystem.self_factor(a, "energy"), 1.0)
	# Of their own accord
	p.needs["clean"] = 20.0
	var line := _first_object(w, "clothesline")
	if line < 0:
		HouseSystem.place_props(w, "yard", true)
		line = _first_object(w, "clothesline")
	AutonomySystem.start(w, p, "change_clothes", line)
	while not p.current.is_empty() and str(p.current["action"]) == "change_clothes":
		w.advance(5)
	var own := float(p.needs["clean"]) - 20.0
	# Led there by the player
	p.needs["clean"] = 20.0
	var r := w.command({"type": "drag", "person": p.uid, "object": line})
	assert_true(r.ok, str(r))
	assert_eq(str(r.action), "change_clothes")
	while not p.current.is_empty() and str(p.current["action"]) == "change_clothes":
		w.advance(5)
	var led := float(p.needs["clean"]) - 20.0
	assert_true(led > own * 2.5, "led %f vs own %f" % [led, own])


func test_a_dirty_person_shows_a_bath_wish_that_a_bath_grants():
	var w := _home()
	var p := w.people[0]
	p.needs["clean"] = 20.0
	for i in 3 * 12:
		w.advance(5)
	assert_eq(str(p.wish.get("id", "")), "want_bath")
	var s := ViewStrings.new(w.pack)
	assert_eq(s.wish_text(p, w), "身上黏糊糊，想洗个澡")
	assert_eq(s.wish_icon(p, w), "washtub")
	var tub := _place(w, "washtub")
	assert_true(w.command({"type": "drag", "person": p.uid, "object": tub}).ok)
	var granted := false
	for i in 400:
		w.advance(5)
		for e in w.drain_events():
			if e.type == "wish_granted" and str(e.wish) == "want_bath":
				granted = true
		if granted:
			break
	assert_true(granted)
	assert_true(p.thanking(w.now))


func test_status_now_follows_what_they_do():
	var w := _home()
	var p := w.people[0]
	var s := ViewStrings.new(w.pack)
	p.current = {}
	assert_eq(FeelingSystem.now(w, p), "歇口气")
	var desk := _first_object(w, "desk")
	var r := w.command({"type": "drag", "person": p.uid, "object": desk})
	assert_true(r.ok, str(r))
	assert_eq(FeelingSystem.now(w, p), "干活呢")
	p.needs["energy"] = 20.0
	assert_eq(FeelingSystem.now(w, p), "干活呢 · 有点累")
	p.needs["fed"] = 20.0
	assert_eq(FeelingSystem.now(w, p), "饿着肚子干活")
	# Only what is wrong is listed beside it: hungry and drowsy here, not the fine needs.
	p.needs["happy"] = 90.0
	p.needs["clean"] = 90.0
	p.needs["health"] = 100.0
	assert_eq(s.status_line(p, w), "饿着肚子干活 · 肚里空、发蔫")
	p.needs["fed"] = 90.0
	p.needs["energy"] = 90.0
	assert_eq(s.status_line(p, w), "干活呢")
	# Fed at the table by the player: "吃得香"; the feeling changes the moment the action does.
	var dish := DishSystem.serve(w, "porridge")
	assert_true(dish >= 0)
	p.needs["fed"] = 50.0
	var re := w.command({"type": "drag", "person": p.uid, "object": int(DishSystem.find(w, dish)["object_uid"])})
	assert_true(re.ok, str(re))
	assert_eq(str(re.get("action", "")), "eat_porridge")
	assert_true(bool(p.current["led"]))
	assert_eq(FeelingSystem.now(w, p), "吃得香")
	p.current = {"action": "sleep", "object_uid": -1, "target_uid": -1, "remaining_s": 9999}
	assert_eq(FeelingSystem.now(w, p), "睡得正香")


func test_earnings_are_shared_now_and_then():
	var w := _home()
	var p := w.people[0]
	p.current = {}
	EconomySystem.earn(w, 20, "work", p.uid)
	assert_true(not p.thanking(w.now), "20 coins: not yet")
	EconomySystem.earn(w, 15, "work", p.uid)
	assert_true(p.thanking(w.now))
	assert_eq(ShareSystem.text(w, p), "今天挣了 35 文！")
	var s := ViewStrings.new(w.pack)
	assert_eq(s.thanks_text(p, w), "今天挣了 35 文！")
	assert_eq(FeelingSystem.now(w, p), "乐得合不拢嘴")
	# Throttled: more coins within the gap are counted, not told.
	w.drain_events()
	var shares := 0
	for i in 40:
		w.advance(5)
		EconomySystem.earn(w, 10, "work", p.uid)
		for e in w.drain_events():
			if e.type == "shared":
				shares += 1
	assert_eq(shares, 0)
	# After the gap, the next coin past a multiple of 30 brings them back with the day's sum.
	w.now += 31 * 60
	EconomySystem.earn(w, 10, "work", p.uid)
	assert_true(p.thanking(w.now))
	assert_eq(ShareSystem.text(w, p), "今天挣了 %d 文！" % p.earned)
	# A new level is told at once, gap or not.
	w.now += WishSystem.thanks_seconds(w) + 5
	EconomySystem.add_progress(w, p, 10000.0)
	assert_eq(p.level, 1)
	assert_true(p.thanking(w.now))
	assert_eq(ShareSystem.text(w, p), "当上%s了！" % str(w.pack.livelihoods["reading"]["levels"][1]["name"]))
	# Asleep: nobody gets up to tell; the coins wait for the next time.
	w.now += 3600
	p.current = {"action": "sleep", "object_uid": -1, "target_uid": -1, "remaining_s": 9999}
	EconomySystem.earn(w, 60, "work", p.uid)
	assert_true(not p.thanking(w.now))


func test_a_granted_wish_is_a_thank_you_not_news_of_money():
	var w := _home()
	var p := w.people[0]
	EconomySystem.earn(w, 40, "work", p.uid)
	assert_true(p.thanking(w.now))
	p.wish = {"id": "want_a_good_word", "expires_at": w.now + 3600}
	WishSystem.grant(w, p)
	var s := ViewStrings.new(w.pack)
	assert_eq(s.thanks_text(p, w), s.t("thanks"))


func test_litter_is_cleaned_by_a_drag_and_some_is_sold():
	var w := _home()
	var p := w.people[0]
	w.pack.mess_types["cloth_scraps"]["scrap"] = {"value": 2, "chance": 1.0}
	var mu := MessSystem.spawn(w, "cloth_scraps", "hall")
	var r := w.command({"type": "drag", "person": p.uid, "mess": mu})
	assert_true(r.ok, str(r))
	assert_eq(str(r.action), "gather_cloth_scraps")
	var money := w.money
	var cleaned := int(w.stats["mess_cleaned"])
	for i in 100:
		if p.current.is_empty() or str(p.current["action"]) != "gather_cloth_scraps":
			break
		w.advance(5)
	assert_true(MessSystem.find(w, mu).is_empty())
	assert_eq(int(w.stats["mess_cleaned"]), cleaned + 1)
	assert_true(w.money >= money + 2, "%d -> %d" % [money, w.money])
	# Every litter type has an action that clears it, and appears by itself or from work.
	for id in ["wrapper", "fruit_core", "cloth_scraps", "feathers"]:
		assert_true(w.pack.mess_types.has(id), id)
		var by_hand := false
		for aid in w.pack.actions:
			if str(w.pack.actions[aid]["cleans"]) == id:
				by_hand = true
		assert_true(by_hand, id)


## Food and medicine only: no baths, no praise, no treats, no wishes granted. After three
## days everyone is alive, mostly dirty and gloomier than a household that is looked after.
func test_a_neglected_household_drifts_dirty_and_sad_but_lives():
	var seeds := [3, 4]
	for seed in seeds:
		var lone := BalanceRun.family_of_four("qijia", seed)
		var kept := BalanceRun.family_of_four("qijia", seed)
		for h in 3 * 24:
			_basic_care(lone)
			BalanceRun.caretake(kept)
			lone.advance(3600)
			kept.advance(3600)
		var lone_clean := 0.0
		var kept_clean := 0.0
		var lone_happy := 0.0
		var kept_happy := 0.0
		for p in lone.people:
			assert_true(p.alive, "seed %d: %s died" % [seed, p.given])
			lone_clean += float(p.needs["clean"]) / lone.people.size()
			lone_happy += float(p.needs["happy"]) / lone.people.size()
		for p in kept.people:
			if p.alive:
				kept_clean += float(p.needs["clean"]) / kept.people.size()
				kept_happy += float(p.needs["happy"]) / kept.people.size()
		assert_true(lone_clean < 40.0, "seed %d: neglected clean %.1f" % [seed, lone_clean])
		assert_true(kept_clean > lone_clean + 15.0, "seed %d: kept %.1f vs neglected %.1f" % [seed, kept_clean, lone_clean])
		assert_true(kept_happy > lone_happy, "seed %d: kept %.1f vs neglected %.1f" % [seed, kept_happy, lone_happy])


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


## Away for a day: dirt piles up but nobody is shared at, no wish forms, no harsher illness
## odds, and needs stay above the floor.
func test_while_away_there_is_no_punishment():
	var w := BalanceRun.family_of_four("qijia", 5)
	for p in w.people:
		p.needs["clean"] = 40.0
	var s := w.catch_up(24 * 3600)
	assert_eq(s.deaths.size(), 0)
	var floor_v := float(w.pack.cfg("offline_need_floor"))
	for p in w.people:
		assert_eq(p.mood, "", p.given)
		for n in p.needs:
			assert_true(float(p.needs[n]) >= floor_v - 0.001, "%s %s %f" % [p.given, n, float(p.needs[n])])
		assert_true(p.share.is_empty(), p.given)


func test_a_save_from_before_the_clean_need_loads():
	var w := _home()
	var d := w.to_dict()
	for p in d["people"]:
		(p["needs"] as Dictionary).erase("clean")
	var back := World.from_dict(w.pack, d)
	assert_true(back != null)
	assert_near(float(back.people[0].needs["clean"]), float(w.pack.needs["clean"]["start"]))
	# Earnings and what is being shared survive a save.
	EconomySystem.earn(w, 40, "work", w.people[0].uid)
	var again := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_true(again != null)
	assert_eq(again.people[0].earned, 40)
	assert_eq(ShareSystem.text(again, again.people[0]), "今天挣了 40 文！")


## A running entry without an action id (a half-built one, as a script might leave it) reads
## as doing nothing instead of failing.
func test_feeling_reads_an_entry_without_an_action_as_idle():
	var w := _home()
	var p := w.people[0]
	p.current = {"remaining_s": 60}
	assert_eq(FeelingSystem.now(w, p), "歇口气")
