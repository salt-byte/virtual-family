extends TestCase
## Festivals (qijia's festivals.json; see `FestivalSystem`): fixed stretches of the year with
## their own actions, wishes and shop items.

## 2026-01-01 12:00 UTC: a multiple of qijia's 4-hour year (spring begins).
const YEAR_START := 1767268800
## Minutes into qijia's year at which each festival is on (its middle).
const MID := {"lantern": 12, "qingming": 42, "duanwu": 84, "mid_autumn": 150, "new_year": 232}


func _w(minute := 0.0, seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	w.set_time(YEAR_START + int(minute * 60.0), 0)
	return w


func _types(events: Array) -> Array:
	return events.map(func(e): return e.type)


func test_qijia_has_five_festivals_each_visible_for_ten_minutes_or_more():
	var p := Pack.load_dir("res://packs/qijia")
	var cal := FestivalSystem.calendar(p)
	assert_eq(cal.map(func(c): return c.id), ["lantern", "qingming", "duanwu", "mid_autumn", "new_year"])
	var last_end := -1
	for c in cal:
		assert_true(c.end_s - c.start_s >= 600, "%s lasts %d s" % [c.id, c.end_s - c.start_s])
		assert_true(c.start_s >= last_end, "%s overlaps the one before" % c.id)
		last_end = c.end_s
		var f: Dictionary = p.festivals[c.id]
		for k in ["name", "banner", "start_text", "end_text"]:
			assert_true(str(f[k]) != "", "%s has a %s" % [c.id, k])
	assert_eq(p.festivals["new_year"]["season"], "winter")
	assert_eq(float(p.festivals["new_year"]["to"]), 1.0)  # 过年 closes the winter, the year's end
	assert_eq(p.festivals["mid_autumn"]["season"], "autumn")


func test_the_festival_is_a_pure_function_of_the_clock():
	var p := Pack.load_dir("res://packs/qijia")
	for id in MID:
		var t := YEAR_START + int(MID[id]) * 60
		assert_eq(FestivalSystem.id_at(p, t), id)
		assert_eq(FestivalSystem.id_at(p, t + 3 * 4 * 3600), id, "the same a few years on")
	assert_eq(FestivalSystem.id_at(p, YEAR_START), "")
	assert_eq(FestivalSystem.id_at(p, YEAR_START + 30 * 60), "")
	assert_eq(FestivalSystem.id_at(p, YEAR_START + 6 * 60), "lantern", "starts on its first second")
	assert_eq(FestivalSystem.id_at(p, YEAR_START + 18 * 60), "", "ends on its last")


func test_smoke_has_no_festivals_and_nothing_changes():
	var w := TestKit.world("_smoke"); TestKit.adult(w)
	assert_true(not FestivalSystem.enabled(w.pack))
	w.advance(3600)
	assert_eq(w.festival, "")
	assert_true(not _types(w.drain_events()).has("festival_started"))
	assert_true(not w.to_dict().has("festival"))


func test_start_and_end_events_and_the_world_field():
	var w := _w(5); TestKit.adult(w)
	w.advance(60)
	var ev := w.drain_events()
	assert_true(_types(ev).has("festival_started"), str(_types(ev)))
	assert_eq(w.festival, "lantern")
	assert_eq(FestivalSystem.current(w)["name"], "元宵")
	assert_true(FestivalSystem.seconds_left(w) > 600)
	w.advance(12 * 60)
	ev = w.drain_events()
	var ended: Array = ev.filter(func(e): return e.type == "festival_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].festival, "lantern")
	assert_eq(w.festival, "")
	assert_eq(FestivalSystem.seconds_left(w), 0)


func test_festival_actions_happen_only_during_their_festival():
	var w := _w(30); var p := TestKit.adult(w)
	w.advance(5)
	assert_eq(AutonomySystem.can_do(w, p, "paste_couplets", -1), "requires")
	assert_true(not AutonomySystem.candidates(w, p).any(func(c): return c.action == "paste_couplets"))
	var w2 := _w(MID["new_year"]); var p2 := TestKit.adult(w2)
	w2.advance(5)
	assert_eq(AutonomySystem.can_do(w2, p2, "paste_couplets", -1), "")
	assert_true(AutonomySystem.candidates(w2, p2).any(func(c): return c.action == "paste_couplets"))
	assert_eq(AutonomySystem.can_do(w2, p2, "watch_moon", -1), "requires")


func test_people_take_part_on_their_own():
	var w := _w(MID["mid_autumn"] - 6)
	for i in 3:
		TestKit.adult(w)
	var done := {}
	for m in 12:
		w.advance(60)
		for e in w.drain_events():
			if e.type == "action_started" and not (w.pack.actions[e.action]["festivals"] as Array).is_empty():
				done[e.action] = true
	assert_true(done.size() >= 2, str(done.keys()))


func test_festival_items_are_sold_only_during_their_festival():
	var w := _w(30); TestKit.adult(w); w.money = 500
	assert_true(not Commands.on_sale(w, "mooncake"))
	assert_eq(w.command({"type": "buy", "item": "mooncake"}).error, "not_running")
	assert_eq(w.money, 500)
	assert_true(Commands.on_sale(w, "rice"), "everyday goods are always sold")
	w.set_time(YEAR_START + MID["mid_autumn"] * 60, 0)
	assert_true(w.command({"type": "buy", "item": "mooncake"}).ok)
	assert_eq(int(w.inventory["mooncake"]), 1)


func test_festival_wishes_come_with_the_festival_and_end_with_it_unpenalised():
	var w := _w(MID["new_year"] - 12, 3)
	for i in 6:
		TestKit.adult(w)
	w.advance(60 * 3)
	assert_eq(w.festival, "")
	w.advance(60 * 7)
	assert_eq(w.festival, "new_year")
	var holders: Array = w.people.filter(func(p): return str(WishSystem.current(w, p).get("festival", "")) == "new_year")
	assert_true(holders.size() >= 2, "festival wishes formed at its start: %d" % holders.size())
	# Nobody does them: they end with the festival, and nobody's mood pays for it.
	for p in holders:
		p.wish["expires_at"] = w.now + 99999
	var p0: Person = holders[0]
	p0.current = {}
	var happy := float(p0.needs["happy"])
	WishSystem.end_festival(w, "new_year")
	assert_eq(p0.wish, {})
	assert_eq(float(p0.needs["happy"]), happy)


func test_a_festival_wish_forms_only_while_its_festival_is_on():
	var w := _w(30); var p := TestKit.adult(w)
	w.advance(5)
	var pool := WishSystem._eligible(w, p, false)
	for id in pool[0]:
		assert_eq(str(w.pack.wishes[id]["festival"]), "", id)
	w.set_time(YEAR_START + MID["mid_autumn"] * 60, 0)
	w.advance(5)
	pool = WishSystem._eligible(w, p, false, "mid_autumn")
	assert_true((pool[0] as Array).has("want_mooncake"), str(pool))
	assert_true(not (pool[0] as Array).has("want_zongzi"))


func test_do_wish_pulls_the_action_up_and_is_granted_by_doing_it():
	var w := _w(MID["mid_autumn"]); var p := TestKit.adult(w)
	w.advance(5)
	p.current = {}
	p.wish = {}  # (the festival may have handed them a wish as it began)
	var before: float = AutonomySystem.candidates(w, p).filter(func(c): return c.action == "watch_moon")[0].score
	p.wish = {"id": "want_moon", "expires_at": w.now + 3600}
	var after: float = AutonomySystem.candidates(w, p).filter(func(c): return c.action == "watch_moon")[0].score
	assert_near(after, before * float(w.pack.cfg("wish_do_factor")), 0.001)
	var top := AutonomySystem.candidates(w, p, int(w.pack.cfg("choice_pool")))
	assert_true(top.any(func(c): return c.action == "watch_moon"), "the pool keeps a wished action")
	AutonomySystem.start(w, p, "watch_moon", -1)
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["watch_moon"]))
	assert_eq(p.wish, {})
	assert_true(_types(w.drain_events()).has("wish_granted"))
	assert_true(p.thanks_until > w.now)


func test_mourning_needs_someone_dead_and_names_them():
	var w := _w(MID["qingming"]); var p := TestKit.adult(w)
	w.advance(5)
	p.current = {}
	assert_eq(AutonomySystem.can_do(w, p, "mourn_at_altar", -1), "no_object")  # no altar yet
	w.objects.append({"uid": w.next_uid(), "type": "altar", "room": "hall", "x": 4, "y": 0})
	assert_eq(AutonomySystem.can_do(w, p, "mourn_at_altar", -1), "requires", "nobody has died")
	assert_true(not AutonomySystem.candidates(w, p).any(func(c): return c.action == "mourn_at_altar"))
	var father := TestKit.adult(w, 80.0)
	father.given = "Father"
	var stranger := TestKit.adult(w, 70.0)
	w.kill_person(stranger, "old_age")
	w.kill_person(father, "old_age")
	p.father = father.uid
	assert_eq(AutonomySystem.can_do(w, p, "mourn_at_altar", -1), "")
	AutonomySystem.start(w, p, "mourn_at_altar", -1)
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["mourn_at_altar"]))
	var m: Array = w.drain_events().filter(func(e): return e.type == "mourned")
	assert_eq(m.size(), 1)
	assert_eq(int(m[0].dead), father.uid, "a parent is remembered before others")


func test_save_keeps_the_festival_and_old_saves_load():
	var w := _w(MID["duanwu"] - 1); TestKit.adult(w); TestKit.adult(w)
	w.advance(120)
	assert_eq(w.festival, "duanwu")
	var d := w.to_dict()
	assert_eq(d["festival"], "duanwu")
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(back != null)
	assert_eq(back.festival, "duanwu")
	w.advance(900); back.advance(900)
	assert_eq(back.to_dict(), w.to_dict(), "continues identically")
	# A save from before festivals existed has no such key; it loads, and the first step
	# notices the festival on.
	var old := _w(MID["duanwu"]); TestKit.adult(old)
	var od := old.to_dict()
	od.erase("festival")
	var loaded := World.from_dict(old.pack, od)
	assert_true(loaded != null)
	assert_eq(loaded.festival, "")
	loaded.advance(5)
	assert_eq(loaded.festival, "duanwu")
	assert_true(_types(loaded.drain_events()).has("festival_started"))
	od["festival"] = 5
	assert_true(World.from_dict(old.pack, od) == null, "a festival that is not a string is corrupt")


func test_an_absence_lists_the_festivals_it_crossed():
	var w := _w(0); TestKit.adult(w); w.stock["food"] = 30
	w.advance(60)
	var s := w.catch_up(4 * 3600)
	assert_eq(s["festivals"], ["lantern", "qingming", "duanwu", "mid_autumn", "new_year"])
	for e in w.drain_events():
		assert_true(e.type != "wish_formed" or str(w.pack.wishes[e.wish]["festival"]) == "", "no festival wishes while away")


func test_validator_checks_festivals_and_what_uses_them():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(p.errors, [] as Array[String])
	p.festivals["lantern"]["season"] = "monsoon"
	p.festivals["qingming"]["from"] = 0.2  # now overlaps nothing (lantern is gone), but:
	p.festivals["duanwu"]["from"] = 0.6  # from >= to
	p.actions["paste_couplets"]["festivals"] = ["harvest_moon"]
	p.items["mooncake"]["festivals"] = "mid_autumn"
	p.wishes["want_market"]["actions"] = []
	p.wishes["want_moon"]["festival"] = "harvest_moon"
	p.actions["go_to_market"]["outing"]["returns"] = [{"item": "rice", "text": "x"}]
	p.actions["temple_fair"]["object"] = "stool"
	var errs := PackValidator.validate(p)
	var want := ["festivals.json: lantern: season 'monsoon' is not a season",
		"festivals.json: duanwu: needs 0 <= from < to <= 1",
		"actions.json: paste_couplets: festivals must be an array of festival ids",
		"items.json: mooncake: festivals must be an array of festival ids",
		"wishes.json: want_market: a do wish needs actions: a non-empty array of action ids",
		"wishes.json: want_moon: festival 'harvest_moon' is not a festival",
		"actions.json: go_to_market: outing.returns: 'rice' is not an item without stock",
		"actions.json: temple_fair: an outing leaves from rooms (no object)"]
	for e in want:
		assert_true(errs.has(e), "missing: " + e + "\n" + "\n".join(errs))
	p.festivals["qingming"]["from"] = 0.05
	p.festivals["lantern"]["season"] = "spring"
	assert_true(PackValidator.validate(p).has("festivals.json: qingming: overlaps lantern"))
