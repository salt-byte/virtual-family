extends TestCase
func _w() -> World:
	var w := TestKit.world(); w.add_object("desk", "main", 0, 0); w.money = 100; return w
func _worker(w) -> Person:
	var p := TestKit.adult(w); p.track = "office"; p.level = 0; p.aptitude = 1.0; return p
func test_passive_income_per_day():
	var w := _w(); var p := _worker(w); p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 999999}
	w.advance(86400)
	assert_eq(w.money, 100 + int(w.pack.livelihoods["office"]["levels"][0]["daily_income"]))
func test_working_adds_bonus_and_progress():
	var w := _w(); var p := _worker(w)
	EconomySystem.on_work_finished(w, p, 60)
	assert_eq(w.money, 100 + int(w.pack.livelihoods["office"]["levels"][0]["work_bonus_per_hour"]))
	assert_near(p.progress, 60.0)
func test_pay_arrives_hourly_in_24_parts():
	var w := _w(); var p := _worker(w); p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 999999}
	w.advance(3600 - 60); assert_eq(w.money, 100); w.advance(60); assert_true(w.money > 100)
	w.advance(23 * 3600); assert_eq(w.drain_events().filter(func(e): return e.type == "income").size(), 24)
func test_sick_or_hungry_work_gives_coins_but_no_progress():
	var w := _w(); var p := _worker(w); p.needs["fed"] = 10.0
	EconomySystem.on_work_finished(w, p, 60); assert_near(p.progress, 0.0); assert_true(w.money > 100)
	p.needs["fed"] = 80.0; p.illness = "cold"; EconomySystem.on_work_finished(w, p, 60); assert_near(p.progress, 0.0)
func test_level_up():
	var w := _w(); var p := _worker(w)
	var need: float = w.pack.livelihoods["office"]["levels"][0]["progress_to_next"]
	EconomySystem.on_work_finished(w, p, int(need))
	assert_eq(p.level, 1); assert_near(p.progress, 0.0)
	assert_true(w.drain_events().any(func(e): return e.type == "level_up"))
func test_top_level_does_not_overflow():
	var w := _w(); var p := _worker(w); p.level = w.pack.livelihoods["office"]["levels"].size() - 1
	EconomySystem.on_work_finished(w, p, 100000); assert_eq(p.level, w.pack.livelihoods["office"]["levels"].size() - 1)
func test_buy_food_adds_stock():
	var w := _w(); assert_true(w.command({type = "buy", item = "groceries", qty = 1}).ok)
	assert_eq(w.money, 70); assert_eq(w.stock["food"], 10)
func test_buy_without_money_rejected_money_never_negative():
	var w := _w(); w.money = 10
	assert_eq(w.command({type = "buy", item = "groceries", qty = 1}).error, "no_money"); assert_eq(w.money, 10)
func test_use_gift_raises_need():
	var w := _w(); var p := _worker(w); p.needs["happy"] = 20.0
	w.command({type = "buy", item = "cake", qty = 1}); w.command({type = "use_item", item = "cake", person = p.uid})
	assert_near(p.needs["happy"], 50.0); assert_eq(w.inventory.get("cake", 0), 0)
func test_spend_and_earn_guards():
	var w := _w()
	assert_true(not EconomySystem.spend(w, 101)); assert_eq(w.money, 100)
	assert_true(EconomySystem.spend(w, 100)); assert_eq(w.money, 0)
	EconomySystem.earn(w, 0, "x"); EconomySystem.earn(w, -5, "x")
	assert_eq(w.money, 0); assert_eq(w.drain_events().size(), 0)
func test_salary_24_parts_sum_exactly():
	var w := _w(); var p := _worker(w); p.level = 1; p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 999999}
	w.advance(24 * 3600)
	var sum := 0
	for e in w.drain_events():
		if e.type == "income" and e.source == "salary": sum += int(e.amount)
	assert_eq(sum, 45); assert_eq(w.money, 145)
func test_buy_errors_and_quantity():
	var w := _w()
	assert_eq(w.command({type = "buy", item = "nope", qty = 1}).error, "no_item")
	assert_eq(w.command({type = "buy", item = "cake", qty = 0}).error, "bad_qty")
	assert_true(w.command({type = "buy", item = "cake", qty = 2}).ok)
	assert_eq(w.money, 50); assert_eq(w.inventory["cake"], 2)
func test_use_item_errors():
	var w := _w(); var p := _worker(w)
	assert_eq(w.command({type = "use_item", item = "cake", person = p.uid}).error, "no_item")
	w.command({type = "buy", item = "cake", qty = 1})
	assert_eq(w.command({type = "use_item", item = "cake", person = 99}).error, "no_person")
	assert_eq(w.inventory["cake"], 1)
func test_finished_work_action_pays_bonus():
	var w := _w(); var p := _worker(w); w.drain_events()
	AutonomySystem.start(w, p, "work_desk", -1)
	w.advance(60 * 60)
	assert_true(w.drain_events().any(func(e): return e.type == "income" and e.source == "work"))
	assert_near(p.progress, 60.0)
