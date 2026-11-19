extends TestCase
## The market: the catalogue grouped by section, the used-goods stall, and every service.
const T0 := 1767268800


func _qijia(seed := 3) -> World:
	var w := BalanceRun.setup("qijia", seed)
	w.drain_events()
	return w


func _section(cat: Array, id: String) -> Dictionary:
	for s in cat:
		if s.id == id:
			return s
	return {}


func _entry(cat: Array, kind: String, id) -> Dictionary:
	for s in cat:
		for e in s.entries:
			if e.kind == kind and e.id == id:
				return e
	return {}


# ---- catalogue ----

func test_qijia_catalogue_has_every_section_in_pack_order():
	var w := _qijia()
	w.advance(5)  # the first step stocks the stall
	var ids: Array = MarketSystem.catalogue(w).map(func(s): return s.id)
	assert_eq(ids, ["provisions", "used_goods", "trades", "house", "clothes", "animals", "upgrades"])
	var names: Array = MarketSystem.catalogue(w).map(func(s): return s.name)
	assert_eq(names, ["食物与药", "二手市场", "营生用具", "房屋", "衣裳", "宠物", "升级与服务"])


func test_qijia_catalogue_puts_things_in_their_sections():
	var w := _qijia()
	var cat := MarketSystem.catalogue(w)
	var where := func(kind, id) -> String:
		for s in cat:
			for e in s.entries:
				if e.kind == kind and e.id == id:
					return s.id
		return ""
	assert_eq(where.call("item", "rice"), "provisions")
	assert_eq(where.call("item", "ginger_pill"), "provisions")
	assert_eq(where.call("item", "zongzi"), "provisions")
	assert_eq(where.call("item", "new_clothes"), "clothes")
	assert_eq(where.call("item", "lined_jacket"), "clothes")
	assert_eq(where.call("item", "pork_bone"), "animals")
	assert_eq(where.call("object", "carpenter_bench"), "trades")
	assert_eq(where.call("object", "tofu_box"), "trades")
	assert_eq(where.call("object", "kang"), "house")
	assert_eq(where.call("object", "bird_cage"), "animals")
	assert_eq(where.call("room", "study"), "house")
	assert_eq(where.call("pet", "dog"), "animals")
	assert_eq(where.call("service", "lottery_ticket"), "upgrades")
	# Fixed furniture, keepsakes and rooms built from the start are never for sale.
	assert_eq(where.call("object", "well_head"), "")
	assert_eq(where.call("object", "ayun_hoop"), "")
	assert_eq(where.call("room", "hall"), "")
	assert_eq(where.call("room", "riverside"), "")


func test_catalogue_entries_carry_price_reason_and_command():
	var w := _qijia()
	w.money = 500
	var cat := MarketSystem.catalogue(w)
	var rice := _entry(cat, "item", "rice")
	assert_eq(rice.price, 24); assert_eq(rice.why, ""); assert_eq(rice.command, {"type": "buy", "item": "rice"})
	var study := _entry(cat, "room", "study")
	assert_eq(study.price, 1200); assert_eq(study.why, "no_money")
	assert_eq(study.command, {"type": "build_room", "room": "study"})
	var kang := _entry(cat, "object", "kang")
	assert_eq(kang.command, {"type": "place", "object_type": "kang"})
	w.money = 5000
	assert_true(w.command(study.command).ok)
	assert_eq(_entry(MarketSystem.catalogue(w), "room", "study").why, "already_built")


func test_every_catalogue_command_runs():
	var w := _qijia()
	w.money = 100000
	w.advance(5)
	for s in MarketSystem.catalogue(w):
		for e in s.entries:
			if e.why != "" or e.kind == "object":
				continue
			var r: Dictionary = w.command(e.command)
			assert_true(r.ok, "%s %s: %s" % [e.kind, str(e.id), str(r.get("error", ""))])


func test_catalogue_without_market_config_groups_by_kind():
	var w := TestKit.world()
	TestKit.adult(w)
	var cat := MarketSystem.catalogue(w)
	assert_true(cat.size() >= 2)
	for s in cat:
		assert_true(s.id in ["items", "objects", "rooms", "pets", "services"], s.id)
		for e in s.entries:
			assert_eq(MarketSystem.PLAIN_SECTIONS[e.kind], s.id)
	assert_eq(w.secondhand, {})


func test_smoke_world_is_unchanged_by_the_market():
	# No market config and no services: no draws, nothing new saved.
	var w := TestKit.world()
	TestKit.adult(w)
	var r0 := w.rng.get_state()
	MarketSystem.step(w, 60.0)
	ServiceSystem.step(w, 60.0)
	assert_eq(w.rng.get_state(), r0)
	assert_true(not w.to_dict().has("market"))


# ---- validator ----

func test_validator_rejects_a_bad_market_and_bad_services():
	var p := Pack.load_dir("res://packs/qijia")
	assert_true(p.is_valid(), str(p.errors))
	p.items["rice"]["market"] = "nowhere"
	p.config["market"]["secondhand"]["price_factor"] = [0.3, 0.9]  # below sell_back_ratio
	p.services["lottery_ticket"]["prizes"] = [{"chance": 0.7, "amount": 5}, {"chance": 0.6, "amount": 5}]
	p.services["hire_help"]["cooks"] = "cake"
	p.services["garden_care"]["requires"] = {"object": "nothing"}
	var errs := PackValidator.validate(p)
	var all := "\n".join(errs)
	assert_true(all.contains("items.json: rice: market 'nowhere'"), all)
	assert_true(all.contains("price_factor"), all)
	assert_true(all.contains("services.json: lottery_ticket: prizes: the chances add up"), all)
	assert_true(all.contains("services.json: hire_help: cooks"), all)
	assert_true(all.contains("services.json: garden_care: requires"), all)


# ---- the used-goods stall ----

func test_secondhand_restocks_each_slot_from_the_right_sections():
	var w := _qijia()
	w.advance(5)
	var sh := w.secondhand
	assert_eq((sh.list as Array).size(), 4)
	var ids := {}
	for l in sh.list:
		ids[l.kind + ":" + l.id] = true
		var src: Dictionary = (w.pack.items if l.kind == "item" else w.pack.object_types)[l.id]
		var sec := MarketSystem.section_of(w.pack, l.kind, src)
		assert_true(sec in ["trades", "house", "clothes"], sec)
		assert_true(l.price >= roundi(src.price * 0.6) and l.price <= roundi(src.price * 0.85), "%s %d" % [l.id, l.price])
		assert_true(l.price > int(src.price * 0.5))  # never worth selling back
	assert_eq(ids.size(), 4)  # distinct
	var slot := int(sh.slot)
	var first: Array = sh.list.duplicate(true)
	assert_eq(MarketSystem.secondhand_refresh_at(w), (slot + 1) * 3 * 3600)
	w.advance(float(MarketSystem.secondhand_refresh_at(w) - w.now) - 1.0)
	assert_eq(int(w.secondhand.slot), slot)
	w.advance(5)
	assert_eq(int(w.secondhand.slot), slot + 1)
	assert_true(w.secondhand.list != first)
	assert_true(int(w.secondhand.list[0].n) > int(first[-1].n))  # listing numbers never repeat


func test_secondhand_is_deterministic_and_survives_a_save():
	var a := _qijia(7)
	var b := _qijia(7)
	a.advance(4 * 3600)
	b.advance(4 * 3600)
	assert_eq(a.secondhand, b.secondhand)
	var c := World.from_dict(a.pack, JSON.parse_string(JSON.stringify(a.to_dict())))
	assert_eq(c.secondhand, a.secondhand)
	a.advance(4 * 3600)
	c.advance(4 * 3600)
	assert_eq(c.secondhand, a.secondhand)
	assert_eq(c.to_dict(), a.to_dict())


func test_buying_used_goods():
	var w := _qijia()
	w.advance(5)
	w.money = 10000
	# An item and a piece of furniture, whatever the stall drew.
	w.secondhand.list = [{"n": 90, "kind": "item", "id": "new_clothes", "price": 55, "sold": false},
		{"n": 91, "kind": "object", "id": "stool", "price": 60, "sold": false}]
	var before := w.objects.size()
	assert_true(w.command({"type": "buy_secondhand", "listing": 90}).ok)
	assert_eq(w.money, 10000 - 55)
	assert_eq(int(w.inventory["new_clothes"]), 1)
	assert_eq(w.command({"type": "buy_secondhand", "listing": 90}).error, "sold")
	var r := w.command({"type": "buy_secondhand", "listing": 91})
	assert_true(r.ok)
	assert_eq(w.objects.size(), before + 1)
	assert_eq(w.object(int(r.uid)).type, "stool")
	assert_eq(_entry(MarketSystem.catalogue(w), "secondhand", 91).why, "sold")
	assert_eq(w.command({"type": "buy_secondhand", "listing": 5}).error, "no_item")
	w.secondhand.list.append({"n": 92, "kind": "item", "id": "rice", "price": 20, "sold": false})
	w.money = 10
	assert_eq(w.command({"type": "buy_secondhand", "listing": 92}).error, "no_money")


# ---- services ----

func test_adopting_another_person_costs_more_each_time():
	var w := _qijia()
	w.money = 5000
	var n0 := w.people.size()
	assert_eq(ServiceSystem.price(w, "adopt_more"), 300)
	assert_true(w.command({"type": "buy_service", "service": "adopt_more"}).ok)
	assert_eq(w.money, 5000)  # nothing paid for a look
	assert_true(not w.candidate.is_empty())
	# The same picker as the game's start: a lot of people, any one of them taken by `pick`.
	assert_eq(w.candidates.size(), FamilySystem.CHOICES)
	assert_eq(ServiceSystem.why_not(w, "adopt_more"), "pending")
	var c0 := w.candidates.duplicate(true)
	assert_true(w.command({"type": "reroll"}).ok)
	assert_true(w.candidates != c0)
	assert_eq(w.candidates.size(), FamilySystem.CHOICES)
	var chosen: Dictionary = w.candidates[1]
	var r := w.command({"type": "adopt", "pick": 1})
	assert_true(r.ok, str(r))
	assert_eq(w.money, 4700)
	assert_eq(w.people.size(), n0 + 1)
	var newcomer := w.person(int(r.person))
	assert_eq(newcomer.given, str(chosen["given"]))
	assert_true(w.candidates.is_empty())
	assert_eq(newcomer.family, w.people[0].family)
	assert_true(newcomer.age >= 6.0 and newcomer.age <= 30.0)
	assert_true(w.candidate.is_empty())
	assert_eq(ServiceSystem.price(w, "adopt_more"), 500)
	assert_true(w.drain_events().any(func(e): return e.type == "adopted" and e.person == newcomer.uid))
	# Sent away: nothing paid, nobody new.
	w.command({"type": "buy_service", "service": "adopt_more"})
	assert_true(w.command({"type": "dismiss_candidate"}).ok)
	assert_eq(w.money, 4700); assert_eq(w.people.size(), n0 + 1)
	# Without a candidate on offer, adopt and reroll stay closed while living.
	assert_eq(w.command({"type": "adopt"}).error, "not_adopting")
	assert_eq(w.command({"type": "reroll"}).error, "not_adopting")


func test_adopting_stops_at_max_people():
	var w := _qijia()
	w.money = 100000
	while w.people.filter(func(p): return p.alive).size() < 8:
		w.add_person(FamilySystem.make_person(w, [20, 30]))
	assert_eq(ServiceSystem.why_not(w, "adopt_more"), "full")
	assert_eq(w.command({"type": "buy_service", "service": "adopt_more"}).error, "full")


func test_garden_care_needs_a_garden_and_adds_to_each_harvest():
	var w := _qijia()
	w.money = 5000
	w.objects = w.objects.filter(func(o): return o.type != "garden")
	assert_eq(ServiceSystem.why_not(w, "garden_care"), "needs_object")
	var spot := MarketSystem.first_fit(w, "garden")
	w.add_object("garden", spot.room, spot.x, spot.y)
	assert_eq(ServiceSystem.yield_bonus(w, "greens"), 0)
	assert_true(w.command({"type": "buy_service", "service": "garden_care"}).ok)
	assert_eq(w.money, 4740)
	assert_eq(ServiceSystem.why_not(w, "garden_care"), "owned")
	assert_eq(ServiceSystem.yield_bonus(w, "greens"), 1)
	assert_eq(ServiceSystem.yield_bonus(w, "fish"), 0)
	# Picking greens now brings two bunches in where it brought one.
	var p := w.people[0]
	var g: Dictionary = w.objects.filter(func(o): return o.type == "garden")[0]
	var before := int(w.stock.get("greens", 0))
	p.needs["fed"] = 100.0; p.needs["energy"] = 100.0
	AutonomySystem.start(w, p, "pick_greens", int(g.uid))
	p.current["remaining_s"] = 0
	AutonomySystem._finish(w, p)
	assert_eq(int(w.stock.get("greens", 0)) - before, roundi(WeatherSystem.yield_factor(w, "greens")) + 1)


func test_lucky_charm_doubles_the_drop_rate():
	var w := _qijia()
	w.money = 5000
	assert_eq(ServiceSystem.drop_factor(w), 1.0)
	assert_true(w.command({"type": "buy_service", "service": "lucky_charm"}).ok)
	assert_eq(ServiceSystem.drop_factor(w), 2.0)
	assert_eq(w.command({"type": "buy_service", "service": "lucky_charm"}).error, "owned")
	# Counted over a long stretch, roughly twice as many things turn up.
	var a := _count_drops(_qijia(21), false)
	var b := _count_drops(_qijia(21), true)
	assert_true(b > a * 1.5, "%d with the charm, %d without" % [b, a])


func _count_drops(w: World, charm: bool) -> int:
	if charm:
		w.services_bought["lucky_charm"] = 1
	var n := 0
	for i in 20000:
		w.collectibles.clear()
		CollectibleSystem.step(w, 5.0)
		n += w.collectibles.size()
	return n


func test_lottery_tickets_are_drawn_later_and_opened():
	var w := _qijia()
	w.money = 100
	var r := w.command({"type": "buy_service", "service": "lottery_ticket"})
	assert_true(r.ok); assert_eq(w.money, 90)
	var t := int(r.ticket)
	assert_eq(w.command({"type": "open_ticket", "ticket": t}).error, "not_drawn")
	w.command({"type": "buy_service", "service": "lottery_ticket"})
	w.command({"type": "buy_service", "service": "lottery_ticket"})
	assert_eq(w.command({"type": "buy_service", "service": "lottery_ticket"}).error, "max")
	w.drain_events()
	var m := w.money
	w.advance(2 * 3600 + 5)
	var drawn := w.drain_events().filter(func(e): return e.type == "lottery_drawn")
	assert_eq(drawn.size(), 3)
	var won := 0
	for e in drawn:
		won += int(e.amount)
	assert_true(w.money >= m + won - 1000 and won >= 0)
	var o := w.command({"type": "open_ticket", "ticket": t})
	assert_true(o.ok); assert_eq(int(o.amount), int(drawn[0].amount))
	assert_eq(w.tickets.size(), 2)
	assert_eq(w.command({"type": "open_ticket", "ticket": t}).error, "no_ticket")


func test_lottery_odds_over_many_draws():
	var w := _qijia(5)
	var counts := {0: 0, 10: 0, 40: 0, 500: 0}
	var n := 40000
	var paid := 0
	for i in n:
		var t := {"id": i, "service": "lottery_ticket", "draw_at": 0, "amount": -1}
		ServiceSystem._draw(w, t)
		counts[int(t.amount)] += 1
		paid += int(t.amount)
	w.drain_events()
	assert_near(float(counts[500]) / n, 0.01, 0.003)
	assert_near(float(counts[40]) / n, 0.04, 0.006)
	assert_near(float(counts[10]) / n, 0.12, 0.01)
	# The house always wins: a ticket returns about 7.8 of its 10 on average.
	assert_true(float(paid) / n < 10.0, "%.2f back per ticket" % (float(paid) / n))
	assert_near(float(paid) / n, 7.8, 1.2)


func test_helper_cleans_and_cooks_at_its_hours_for_the_days_paid():
	var w := _qijia()
	w.money = 1000
	w.stock["food"] = 5
	# Start just before 07:00 local.
	var day0 := (w.now / 86400) * 86400
	w.now = day0 + 7 * 3600 - 30
	assert_true(w.command({"type": "buy_service", "service": "hire_help"}).ok)
	assert_eq(w.money, 955)
	assert_eq(w.helper_until, w.now + 86400)
	MessSystem.spawn(w, "dirt")
	MessSystem.spawn(w, "dirt")
	w.dishes.clear()
	w.drain_events()
	# Only the hand's own effect: run the system across the hour.
	w.now += 30
	ServiceSystem.step(w, 30.0)
	var came := w.drain_events().filter(func(e): return e.type == "helper_came")
	assert_eq(came.size(), 1)
	assert_true(int(came[0].cleaned) >= 2)
	assert_eq(w.messes.size(), 0)
	assert_eq(came[0].cooked, "porridge")
	assert_eq(int(w.stock["food"]), 4)
	assert_eq(DishSystem.count(w, "porridge"), 1)
	# Not at other hours; gone once the day is up.
	w.now += 3600
	ServiceSystem.step(w, 3600.0)
	assert_true(w.drain_events().filter(func(e): return e.type == "helper_came").is_empty())
	w.now = w.helper_until
	ServiceSystem.step(w, 60.0)
	assert_eq(w.helper_until, 0)
	assert_true(w.drain_events().any(func(e): return e.type == "helper_left"))
	# Paid ahead at most max_days.
	for i in 7:
		assert_true(w.command({"type": "buy_service", "service": "hire_help"}).ok)
	assert_eq(w.command({"type": "buy_service", "service": "hire_help"}).error, "max")


func test_helper_without_food_still_sweeps():
	var w := _qijia()
	w.money = 1000
	w.stock["food"] = 0
	var day0 := (w.now / 86400) * 86400
	w.now = day0 + 17 * 3600 - 10
	w.command({"type": "buy_service", "service": "hire_help"})
	MessSystem.spawn(w, "dirt")
	w.dishes.clear()
	w.drain_events()
	w.now += 10
	ServiceSystem.step(w, 10.0)
	var came := w.drain_events().filter(func(e): return e.type == "helper_came")
	assert_eq(came.size(), 1); assert_eq(came[0].cooked, ""); assert_eq(w.messes.size(), 0)


# ---- a faster clock ----

func _synced(seed := 3) -> World:
	var w := _qijia(seed)
	w.sync(w.now, 0)
	return w


func test_double_time_runs_the_clock_twice_as_fast_while_it_lasts():
	var w := _synced()
	w.money = 1000
	var t := w.now
	var r := w.command({"type": "buy_service", "service": "double_time"})
	assert_true(r.ok); assert_eq(w.money, 880)
	assert_eq(w.speed_until, t + 4 * 3600)
	w.sync(t + 60, 0)
	assert_eq(w.now + int(w._acc), t + 120)
	assert_eq(w.clock_lead, 60)
	# Across the end: 20 real seconds fast, 40 plain.
	w.sync(t + 4 * 3600 - 20, 0)
	assert_eq(w.clock_lead, 4 * 3600 - 20)
	w.sync(t + 4 * 3600 + 40, 0)
	assert_eq(w.clock_lead, 4 * 3600)
	w.sync(t + 4 * 3600 + 100, 0)
	assert_eq(w.clock_lead, 4 * 3600)
	assert_eq(float(w.now) + w._acc, float(t + 4 * 3600 + 100 + 4 * 3600))


func test_double_time_adds_up_to_its_cap():
	var w := _synced()
	w.money = 1000
	var t := w.now
	for i in 3:
		assert_true(w.command({"type": "buy_service", "service": "double_time"}).ok)
	assert_eq(w.speed_until, t + 12 * 3600)
	assert_eq(w.command({"type": "buy_service", "service": "double_time"}).error, "max")


func test_double_time_matches_a_plain_clock_that_ran_twice_as_long():
	# Two worlds from one seed: one sped up for an hour, the other given the same game time.
	var a := _synced(9)
	var b := _synced(9)
	var t := a.now
	a.money = 1000; b.money = 1000
	a.command({"type": "buy_service", "service": "double_time"})
	b.services_bought["double_time"] = 1; b.money -= 120
	for i in 60:
		a.sync(t + (i + 1) * 60, 0)
		b.sync(t + (i + 1) * 120, 0)
	assert_eq(a.now, b.now)
	var da := a.to_dict(); var db := b.to_dict()
	da.erase("market"); db.erase("market")
	assert_eq(da, db)


func test_double_time_offline_counts_double_until_it_ends_and_keeps_the_cap():
	var w := _synced()
	w.money = 1000
	var t := w.now
	w.command({"type": "buy_service", "service": "double_time"})
	# Away 10 real hours: 4 of them fast -> 14 game hours replayed.
	var s := w.sync(t + 10 * 3600, 0)
	assert_eq(s.simulated_seconds, 14 * 3600)
	assert_true(not s.capped)
	assert_eq(w.clock_lead, 4 * 3600)
	assert_eq(float(w.now) + w._acc, float(t + 14 * 3600))
	# Away 46 real hours with 4 fast: 50 game hours, capped at 48; the clock still lands right.
	var v := _synced()
	v.money = 1000
	var t2 := v.now
	v.command({"type": "buy_service", "service": "double_time"})
	var s2 := v.sync(t2 + 46 * 3600, 0)
	assert_true(s2.capped)
	assert_eq(s2.simulated_seconds, 48 * 3600)
	assert_eq(v.now, t2 + 50 * 3600)
	var s3 := v.sync(t2 + 46 * 3600 + 60, 0)
	assert_eq(s3.simulated_seconds, 0); assert_eq(v.now, t2 + 50 * 3600 + 60)


func test_a_short_real_gap_is_never_an_absence_even_when_fast():
	var w := _synced()
	w.money = 1000
	var t := w.now
	w.command({"type": "buy_service", "service": "double_time"})
	w.sync(t + 100, 0)  # 200 game seconds, but only 100 real ones
	assert_true(not w.offline)
	assert_eq(w.clock_lead, 100)


# ---- saves ----

func test_market_state_round_trips_through_a_save():
	var w := _qijia()
	w.money = 5000
	w.sync(w.now, 0)
	w.advance(5)
	w.command({"type": "buy_service", "service": "lottery_ticket"})
	w.command({"type": "buy_service", "service": "hire_help"})
	w.command({"type": "buy_service", "service": "double_time"})
	w.command({"type": "buy_service", "service": "lucky_charm"})
	w.command({"type": "buy_service", "service": "adopt_more"})
	w.sync(w.now + 30, 0)
	var d := w.to_dict()
	assert_true(d.has("market"))
	var c := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(c != null)
	assert_eq(c.to_dict(), d)
	assert_eq(c.adopt_service, "adopt_more")
	assert_eq(c.services_bought, w.services_bought)
	assert_eq(c.tickets, w.tickets)
	assert_eq(c.clock_lead, w.clock_lead)
	w.advance(3 * 3600); c.advance(3 * 3600)
	assert_eq(c.to_dict(), w.to_dict())


func test_old_save_without_market_loads_with_defaults():
	var w := _qijia()
	var d := w.to_dict()
	d.erase("market")
	var c := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(c != null)
	assert_eq(c.secondhand, {}); assert_eq(c.services_bought, {}); assert_eq(c.clock_lead, 0)
	c.advance(5)
	assert_eq((c.secondhand.list as Array).size(), 4)


func test_bad_market_save_is_corrupt():
	var w := _qijia()
	w.advance(5)
	var d := w.to_dict()
	d["market"]["secondhand"]["list"][0]["kind"] = "room"
	assert_eq(WorldSave.restore(w.pack, d)["error"], "corrupt")
