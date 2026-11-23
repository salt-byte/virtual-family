extends TestCase
## Festivals (qijia's festivals.json; see `FestivalSystem`): fixed stretches of the year with
## their own actions, wishes and shop items.

## The day each of qijia's festivals begins in 2027 (real dates, local; the tests run at utc
## offset 0). 过年 runs six days from 除夕, the others one day.
const DAY := {"new_year": "2027-02-05", "lantern": "2027-02-20", "qingming": "2027-04-05",
	"duanwu": "2027-06-09", "mid_autumn": "2027-09-15"}
## 2027-03-10 12:00 UTC: a day with no festival.
const PLAIN := 1804680000


## Unix time of festival `id`'s first midnight, plus `minutes`.
func _at(id: String, minutes := 0.0) -> int:
	return FestivalSystem.date_start(DAY[id]) + int(minutes * 60.0)


## Noon on festival `id`'s first day.
func _mid(id: String) -> int:
	return _at(id, 12 * 60)


func _w(t := PLAIN, seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	w.set_time(t, 0)
	return w


func _types(events: Array) -> Array:
	return events.map(func(e): return e.type)


func test_qijia_has_five_festivals_on_the_real_calendar_once_a_year():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(FestivalSystem.calendar(p), [], "none sits in the game's year")
	var y2027 := FestivalSystem.dates_between(p, FestivalSystem.date_start("2027-01-01"), FestivalSystem.date_start("2028-01-01"))
	assert_eq(y2027.map(func(c): return c.id), ["new_year", "lantern", "qingming", "duanwu", "mid_autumn"])
	for c in y2027:
		assert_eq(Time.get_date_string_from_unix_time(c.start_unix), DAY[c.id])
		var f: Dictionary = p.festivals[c.id]
		for k in ["name", "banner", "start_text", "end_text"]:
			assert_true(str(f[k]) != "", "%s has a %s" % [c.id, k])
	assert_eq(y2027[0].end_unix - y2027[0].start_unix, 6 * 86400, "过年: 除夕 to 初五")
	assert_eq(y2027[4].end_unix - y2027[4].start_unix, 86400)
	for id in DAY:
		var dates: Array = p.festivals[id]["dates"]
		assert_true(dates.has("2040-" + str(dates[-1]).substr(5)) and dates.has(DAY[id]), "%s covers 2026-2040" % id)
	# The year's festivals are five events, not one every few hours of play.
	assert_eq(FestivalSystem.dates_between(p, FestivalSystem.date_start("2026-11-23"), FestivalSystem.date_start("2026-11-23") + 30 * 86400), [])


func test_the_festival_is_a_pure_function_of_the_clock_and_the_local_date():
	var p := Pack.load_dir("res://packs/qijia")
	for id in DAY:
		assert_eq(FestivalSystem.id_at(p, _mid(id)), id)
		assert_eq(FestivalSystem.id_at(p, _mid(id) + 4 * 3600), id, "on all day, not for minutes")
	assert_eq(FestivalSystem.id_at(p, PLAIN), "")
	assert_eq(FestivalSystem.id_at(p, _at("lantern")), "lantern", "starts at local midnight")
	assert_eq(FestivalSystem.id_at(p, _at("lantern") - 1), "")
	assert_eq(FestivalSystem.id_at(p, _at("lantern", 24 * 60)), "", "ends at the next midnight")
	assert_eq(FestivalSystem.id_at(p, _at("new_year", 5 * 24 * 60 + 60)), "new_year", "初五")
	assert_eq(FestivalSystem.id_at(p, _at("new_year", 6 * 24 * 60)), "")
	# Local dates: at UTC+8 the festival begins eight hours before UTC midnight.
	assert_eq(FestivalSystem.id_at(p, _at("lantern") - 8 * 3600, 8 * 3600), "lantern")
	assert_eq(FestivalSystem.id_at(p, _at("lantern", 24 * 60) - 8 * 3600, 8 * 3600), "")


func test_smoke_has_no_festivals_and_nothing_changes():
	var w := TestKit.world("_smoke"); TestKit.adult(w)
	assert_true(not FestivalSystem.enabled(w.pack))
	w.advance(3600)
	assert_eq(w.festival, "")
	assert_true(not _types(w.drain_events()).has("festival_started"))
	assert_true(not w.to_dict().has("festival"))


func test_start_and_end_events_and_the_world_field():
	var w := _w(_at("lantern", -1)); TestKit.adult(w)
	w.advance(120)
	var ev := w.drain_events()
	assert_true(_types(ev).has("festival_started"), str(_types(ev)))
	assert_eq(w.festival, "lantern")
	assert_eq(FestivalSystem.current(w)["name"], "元宵")
	assert_eq(FestivalSystem.seconds_left(w), 86400 - 60)
	w.set_time(_at("lantern", 24 * 60 - 1), 0)
	w.drain_events()
	w.advance(120)
	ev = w.drain_events()
	var ended: Array = ev.filter(func(e): return e.type == "festival_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].festival, "lantern")
	assert_eq(w.festival, "")
	assert_eq(FestivalSystem.seconds_left(w), 0)


func test_festival_actions_happen_only_during_their_festival():
	var w := _w(); var p := TestKit.adult(w)
	w.advance(5)
	assert_eq(AutonomySystem.can_do(w, p, "paste_couplets", -1), "not_festival")
	assert_true(not AutonomySystem.candidates(w, p).any(func(c): return c.action == "paste_couplets"))
	var w2 := _w(_mid("new_year")); var p2 := TestKit.adult(w2)
	w2.advance(5)
	assert_eq(AutonomySystem.can_do(w2, p2, "paste_couplets", -1), "")
	assert_true(AutonomySystem.candidates(w2, p2).any(func(c): return c.action == "paste_couplets"))
	assert_eq(AutonomySystem.can_do(w2, p2, "watch_moon", -1), "not_festival")


func test_people_take_part_on_their_own():
	var w := _w(_at("mid_autumn", 19 * 60))
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
	var w := _w(); TestKit.adult(w); w.money = 500
	var why := func(id: String) -> String:
		for sec in MarketSystem.catalogue(w):
			for e in sec.entries:
				if e.kind == "item" and e.id == id:
					return str(e.why)
		return "?"
	assert_true(not Commands.on_sale(w, "realgar_wine"))
	assert_eq(why.call("realgar_wine"), "not_festival", "the market greys it out")
	assert_eq(w.command({"type": "buy", "item": "realgar_wine"}).error, "not_festival")
	assert_eq(w.money, 500)
	assert_true(Commands.on_sale(w, "rice"), "everyday goods are always sold")
	assert_eq(why.call("rice"), "")
	w.set_time(_mid("duanwu"), 0)
	assert_eq(why.call("realgar_wine"), "")
	assert_true(w.command({"type": "buy", "item": "realgar_wine"}).ok)
	assert_eq(int(w.inventory["realgar_wine"]), 1)


func test_festival_wishes_come_with_the_festival_and_end_with_it_unpenalised():
	var w := _w(_at("new_year", -10), 3)
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
	var w := _w(); var p := TestKit.adult(w)
	w.advance(5)
	var pool := WishSystem._eligible(w, p, false)
	for id in pool[0]:
		assert_eq(str(w.pack.wishes[id]["festival"]), "", id)
	w.set_time(_mid("mid_autumn"), 0)
	w.advance(5)
	pool = WishSystem._eligible(w, p, false, "mid_autumn")
	assert_true((pool[0] as Array).has("want_mooncake"), str(pool))
	assert_true(not (pool[0] as Array).has("want_zongzi"))


func test_do_wish_pulls_the_action_up_and_is_granted_by_doing_it():
	var w := _w(_at("mid_autumn", 20 * 60)); var p := TestKit.adult(w)
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
	var w := _w(_mid("qingming")); var p := TestKit.adult(w)
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
	var w := _w(_at("duanwu", -1)); TestKit.adult(w); TestKit.adult(w)
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
	var old := _w(_mid("duanwu")); TestKit.adult(old)
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
	var w := _w(_at("lantern", -12 * 60)); TestKit.adult(w); w.stock["food"] = 30
	w.advance(60)
	var s := w.catch_up(36 * 3600)
	assert_eq(s["festivals"], ["lantern"])
	for e in w.drain_events():
		assert_true(e.type != "wish_formed" or str(w.pack.wishes[e.wish]["festival"]) == "", "no festival wishes while away")


func test_validator_checks_festivals_and_what_uses_them():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(p.errors, [] as Array[String])
	p.festivals["lantern"]["dates"] = ["2027-13-01"]
	p.festivals["qingming"]["dates"] = ["2027-02-07"]  # inside 过年 (2027-02-05, six days)
	p.festivals["duanwu"]["days"] = 0
	# The other way of placing one: in the game's year, by season.
	p.festivals["mid_autumn"].erase("dates")
	p.festivals["mid_autumn"]["season"] = "monsoon"
	p.actions["paste_couplets"]["festivals"] = ["harvest_moon"]
	p.items["mooncake"]["festivals"] = "mid_autumn"
	p.wishes["want_market"]["actions"] = []
	p.wishes["want_moon"]["festival"] = "harvest_moon"
	p.actions["go_to_market"]["outing"]["returns"] = [{"item": "rice", "text": "x"}]
	p.actions["temple_fair"]["object"] = "stool"
	var errs := PackValidator.validate(p)
	var want := ["festivals.json: lantern: '2027-13-01' is not a date (YYYY-MM-DD)",
		"festivals.json: duanwu: days must be a whole number of at least 1",
		"festivals.json: mid_autumn: season 'monsoon' is not a season",
		"actions.json: paste_couplets: festivals must be an array of festival ids",
		"items.json: mooncake: festivals must be an array of festival ids",
		"wishes.json: want_market: a do wish needs actions: a non-empty array of action ids",
		"wishes.json: want_moon: festival 'harvest_moon' is not a festival",
		"actions.json: go_to_market: outing.returns: 'rice' is not an item without stock",
		"actions.json: temple_fair: an outing leaves from rooms (no object)"]
	for e in want:
		assert_true(errs.has(e), "missing: " + e + "\n" + "\n".join(errs))
	assert_true(errs.has("festivals.json: qingming: 2027-02-07 overlaps new_year") \
		or errs.has("festivals.json: new_year: 2027-02-05 overlaps qingming"), "\n".join(errs))
	p.festivals["mid_autumn"]["season"] = "autumn"
	p.festivals["mid_autumn"]["from"] = 0.6
	p.festivals["mid_autumn"]["to"] = 0.4
	assert_true(PackValidator.validate(p).has("festivals.json: mid_autumn: needs 0 <= from < to <= 1"))


func test_a_festival_boost_counts_the_same_in_the_choice_and_in_the_score():
	var p0 := Pack.load_dir("res://packs/qijia")
	assert_near(FestivalSystem.action_factor(p0, p0.actions["eavesdrop"], "new_year"), 1.3)  # tagged 爱热闹
	assert_near(FestivalSystem.action_factor(p0, p0.actions["eavesdrop"], ""), 1.0)
	assert_eq(FestivalSystem.action_factor(p0, p0.actions["paste_couplets"], "lantern"), 0.0)
	var w := _w(_mid("new_year")); var p := TestKit.adult(w)
	w.advance(5)
	p.current = {}
	p.wish = {}
	var cands := AutonomySystem.candidates(w, p)
	assert_true(cands.any(func(c): return c.action == "eavesdrop"))
	assert_true(cands.any(func(c): return c.action == "paste_couplets"))
	for c in cands:
		var want := AutonomySystem._score(w, p, w.pack.actions[c.action])
		assert_near(c.score, want, 1e-6 * maxf(1.0, want), c.action)
