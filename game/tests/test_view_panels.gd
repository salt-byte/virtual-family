extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_panels_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _living() -> Main:
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func test_buy_food_raises_stock_and_spends_money():
	var m := _living()
	var w := m.session.world
	var money := w.money
	var food := int(w.stock.get("food", 0))
	m.panels.open("shop")
	m.panels.press("buy:rice")
	assert_eq(w.money, money - 24)
	assert_eq(int(w.stock["food"]), food + 8)
	m.free()


func test_medicine_goes_to_inventory_and_is_used_on_selected_person():
	var m := _living()
	var w := m.session.world
	var p := w.people[0]
	IllnessSystem.infect(w, p, "chill")
	m.panels.open("shop")
	m.panels.press("buy:ginger_pill")
	assert_true(not m.panels.text().contains("伤风"))
	m.panels.press("tab.inventory")
	assert_true(m.panels.text().contains("老姜红枣丸"))
	m.panels.press("use:ginger_pill")
	assert_eq(w.stats["cured"], 1)
	m.free()


func test_wrong_medicine_toasts_and_is_spent():
	var m := _living()
	var w := m.session.world
	var p := w.people[0]
	IllnessSystem.infect(w, p, "chill")
	m.panels.open("shop")
	m.panels.press("buy:indigo_salve")
	m.panels.press("tab.inventory")
	m.panels.press("use:indigo_salve")
	assert_true(m.hud.toasts().has(m.session.strings.error("wrong_medicine")))
	assert_eq(int(w.inventory.get("indigo_salve", 0)), 0)
	assert_true(p.illness != "")
	m.free()


func test_unaffordable_item_button_is_disabled():
	var m := _living()
	var w := m.session.world
	w.money = 10
	m.panels.open("shop")
	assert_true(m.panels.is_disabled("buy:rice"))
	m.panels.press("buy:rice")
	assert_eq(w.money, 10)
	w.money = 100
	m.panels.refresh()
	assert_true(not m.panels.is_disabled("buy:rice"))
	m.free()


func test_item_rows_show_name_category_price_only():
	var m := _living()
	m.panels.open("shop")
	var t := m.panels.text()
	assert_true(t.contains("一袋米面") and t.contains("粮食") and t.contains("24"))
	assert_true(not t.contains("伤风") and not t.contains("chill"))
	m.free()


func test_use_disabled_without_selection():
	var m := _living()
	m.session.world.inventory["rice"] = 1
	m.selected = -1
	m.panels.open("shop")
	m.panels.press("tab.inventory")
	assert_true(m.panels.is_disabled("use:rice"))
	m.free()


func test_goals_and_collection_reflect_world():
	var m := _living()
	var w := m.session.world
	m.panels.open("ledger")
	assert_eq(m.panels.opened(), "ledger")
	assert_true(not m.panels.text().contains("✓"))
	w.goals_done.append("tidy_home")
	m.panels.refresh()
	assert_true(m.panels.text().contains("✓"))
	m.panels.press("tab.collection")
	assert_true(m.panels.text().contains("？"))
	assert_true(not m.panels.text().contains("一串铜钱"))
	w.collection["coins"] = 1
	m.panels.refresh()
	assert_true(m.panels.text().contains("一串铜钱"))
	m.free()


func test_family_row_selects_person_and_closes():
	var m := _living()
	var w := m.session.world
	var p := w.people[0]
	m.selected = -1
	m.panels.open("family")
	assert_true(m.panels.text().contains(m.session.strings.person_name(p)))
	m.panels.press("person:%d" % p.uid)
	assert_eq(m.selected, p.uid)
	assert_eq(m.panels.opened(), "")
	m.free()


func test_family_proposal_row_opens_overlay():
	var m := _living()
	var w := m.session.world
	m.panels.open("family")
	assert_true(not m.panels.has_button("proposal"))
	m.panels.close()
	# No old stories here: with the places outside the house the seeded dice drop the first
	# story fragment where the lone person picks it up within these 16 minutes, and its card
	# would outrank the proposal card these tests look at.
	m.session.world.pack.stories = {}
	for i in 16:
		clk.unix += 60.0
		m.tick(0.016)
	assert_true(not w.proposals.is_empty())
	m.panels.open("family")
	m.panels.press("proposal")
	assert_eq(m.overlays.current(), "proposal")
	assert_eq(m.panels.opened(), "")
	m.free()


func test_one_at_a_time_close_and_block():
	var m := _living()
	m.panels.open("shop")
	assert_true(m.panels.blocks_input())
	assert_true(m.is_house_blocked())
	m.panels.open("family")
	assert_eq(m.panels.opened(), "family")
	m.panels.press("btn.close")
	assert_eq(m.panels.opened(), "")
	assert_true(not m.is_house_blocked())
	m.panels.open("shop")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	m.panels._unhandled_key_input(esc)
	assert_eq(m.panels.opened(), "")
	m.free()


func test_hud_signal_opens_and_overlay_prevents():
	var m := _living()
	m.hud.press("shop")
	assert_eq(m.panels.opened(), "shop")
	m.hud.press("ledger")
	assert_eq(m.panels.opened(), "ledger")
	m.hud.press("family")
	assert_eq(m.panels.opened(), "family")
	m.hud.press("arrange")
	assert_eq(m.panels.opened(), "family")
	m.panels.close()
	var m2 := _main()
	m2.tick(0.016)
	assert_eq(m2.overlays.current(), "adopt")
	m2.panels.open("shop")
	assert_eq(m2.panels.opened(), "")
	m.free()
	m2.free()


func test_house_ignores_input_while_panel_open():
	var m := _living()
	m.panels.open("shop")
	var before := m.house.position
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(600, 300)
	m.house._unhandled_input(down)
	assert_true(not m.house._pressed)
	assert_eq(m.house.position, before)
	m.free()


func test_refresh_does_not_rebuild_when_unchanged():
	var m := _living()
	m.panels.open("shop")
	var b := m.panels.button_node("buy:rice")
	m.panels.refresh()
	assert_true(m.panels.button_node("buy:rice") == b)
	m.session.world.money += 1
	m.panels.refresh()
	assert_true(m.panels.button_node("buy:rice") != b)
	m.free()


func test_layout_fits_560_and_row_labels_are_safe():
	var m := _living()
	m.session.world.inventory["rice"] = 2
	m.session.world.goals_done.append("tidy_home")
	# Every market section's tab (the stall stocked, a ticket and a hired hand), then the rest.
	var w := m.session.world
	w.advance(5)
	w.money = 5000
	w.command({"type": "buy_service", "service": "lottery_ticket"})
	w.command({"type": "buy_service", "service": "hire_help"})
	m.panels.open("shop")
	var steps: Array = []
	for t in m.panels._tabs():
		steps.append(["shop", t])
	m.panels.close()
	assert_eq(steps.size(), 8)
	for step in steps + [["ledger", "tab.goals"], ["ledger", "tab.collection"], ["family", ""]]:
		m.panels.open(step[0])
		if step[1] != "":
			m.panels.press(step[1])
		var size := m.panels.card_size()
		assert_true(size.x <= 560.0, "%s width %s" % [step, size.x])
		assert_true(size.y <= 520.0, "%s height %s" % [step, size.y])
		for l in m.panels.row_labels():
			assert_true(l.autowrap_mode == TextServer.AUTOWRAP_OFF or l.custom_minimum_size.x >= 100.0, "%s: %s" % [step, l.text])
	m.panels.open("shop")
	assert_true(m.panels.row_labels().size() >= 5)
	m.free()


func test_inventory_tab_refreshes_money_and_stock():
	var m := _living()
	var w := m.session.world
	w.inventory["rice"] = 1
	m.panels.open("shop")
	m.panels.press("tab.inventory")
	w.money = 4321
	w.stock["food"] = 77
	m.panels.refresh()
	assert_true(m.panels.text().contains("4321"))
	assert_true(m.panels.text().contains("77"))
	m.free()


func test_overlay_blocks_opening_and_closes_open_panel():
	var m := _living()
	# No old stories here: with the places outside the house the seeded dice drop the first
	# story fragment where the lone person picks it up within these 16 minutes, and its card
	# would outrank the proposal card these tests look at.
	m.session.world.pack.stories = {}
	for i in 16:
		clk.unix += 60.0
		m.tick(0.016)
	m.panels.open("shop")
	assert_eq(m.panels.opened(), "shop")
	m.overlays.open_proposal()
	m.tick(0.016)
	assert_eq(m.overlays.current(), "proposal")
	assert_eq(m.panels.opened(), "")
	m.panels.open("family")
	assert_eq(m.panels.opened(), "")
	m.free()


func test_panel_closes_when_game_leaves_living():
	var m := _living()
	m.panels.open("shop")
	m.session.world.phase = "over"
	m.panels.refresh()
	assert_eq(m.panels.opened(), "")
	m.free()


func test_done_goals_sort_last():
	var m := _living()
	var w := m.session.world
	var ids: Array = w.pack.goals.keys()
	w.goals_done.append(ids[0])
	m.panels.open("ledger")
	var t := m.panels.text()
	var first_done := t.find(str(w.pack.goals[ids[0]]["text"]))
	var second := t.find(str(w.pack.goals[ids[1]]["text"]))
	assert_true(first_done > second and second >= 0)
	m.free()


func test_market_tabs_follow_the_catalogue_sections():
	var m := _living()
	var w := m.session.world
	w.advance(5)
	m.panels.open("shop")
	var want: Array = MarketSystem.sections(w.pack).map(func(s): return Panels.MARKET_TAB + str(s.id))
	assert_eq(m.panels._tabs(), want + ["tab.inventory"])
	assert_true(m.panels.is_disabled("market:provisions"), "the first section is open")
	assert_true(m.panels.text().contains("食物与药") and m.panels.text().contains("升级与服务"))
	m.free()


func test_market_buttons_build_place_and_buy_services():
	var m := _living()
	var w := m.session.world
	w.advance(5)
	w.money = 5000
	m.panels.open("shop")
	m.panels.press("market:house")
	m.panels.press("build:veg_plot")
	assert_true(w.rooms_built.has("veg_plot"))
	assert_true(m.panels.is_disabled("build:veg_plot"))
	assert_true(m.panels.text().contains("已盖好"))
	# Furniture is set down by hand: the panel hands it to arrange mode.
	m.panels.press("place:kang")
	assert_eq(m.panels.opened(), "")
	assert_true(m.arrange.active)
	assert_eq(m.arrange.held_type, "kang")
	m.arrange.exit()
	m.panels.open("shop")
	m.panels.press("market:upgrades")
	var money := w.money
	m.panels.press("service:lottery_ticket")
	assert_eq(w.money, money - 10)
	assert_true(m.panels.text().contains("开奖"), m.panels.text())
	w.tickets[0].amount = 40
	m.panels.refresh()
	m.panels.press("ticket:%d" % int(w.tickets[0].id))
	assert_true(w.tickets.is_empty())
	assert_true(m.hud.toasts().any(func(t): return t.contains("中了")), str(m.hud.toasts()))
	# Taking in another person opens the same picker as the game's start, a lot at a time.
	m.panels.press("service:adopt_more")
	m.tick(0.016)
	assert_eq(m.overlays.current(), "adopt")
	assert_eq(m.panels.opened(), "")
	assert_eq(w.candidates.size(), FamilySystem.CHOICES)
	var lot := w.candidates.duplicate(true)
	m.overlays.press("btn.reroll")
	assert_true(w.candidates != lot, "换一批")
	var n := w.people.size()
	var picked: Dictionary = w.candidates[2]
	money = w.money
	m.overlays.press("pick:2")
	assert_eq(w.people.size(), n + 1)
	assert_eq(w.people[-1].given, str(picked["given"]))
	assert_eq(w.money, money - 300)
	m.tick(0.016)
	assert_true(m.overlays.current() != "adopt")
	# Sent off: nobody new, nothing paid.
	m.panels.open("shop")
	m.panels.press("market:upgrades")
	m.panels.press("service:adopt_more")
	m.tick(0.016)
	m.overlays.press("btn.dismiss")
	assert_eq(w.people.size(), n + 1)
	assert_true(w.candidate.is_empty() and w.candidates.is_empty())
	m.free()


func test_market_used_goods_tab_sells_off_the_stall():
	var m := _living()
	var w := m.session.world
	w.advance(5)
	w.money = 5000
	m.panels.open("shop")
	m.panels.press("market:used_goods")
	var l: Dictionary = w.secondhand.list[0]
	assert_true(m.panels.text().contains("原价") or m.panels.text().contains("想要"), m.panels.text())
	m.panels.press("used:%d" % int(l.n))
	assert_true(bool(w.secondhand.list[0].sold))
	assert_true(m.panels.is_disabled("used:%d" % int(l.n)))
	m.free()
