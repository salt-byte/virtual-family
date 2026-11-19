extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_hud_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func _adopted() -> Main:
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _click(m: Main, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	m.house._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	m.house._unhandled_input(up)


func test_bar_shows_selected_person_in_words_not_numbers():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	# Busy: the bar names the action without a percentage (the plate's line shows progress).
	var desk: int = w.objects.filter(func(o): return o.type == "desk")[0].uid
	m.session.command({"type": "drag", "person": p.uid, "object": desk})
	# Need values whose digits cannot turn up in the age, the money or the larder count:
	# two at their worst, one low, one fine.
	var values := [11.0, 13.0, 43.0, 89.0]
	var k := 0
	for nid in p.needs:
		p.needs[nid] = values[k % values.size()]
		k += 1
	w.money = 500
	m.tick(0.016)
	assert_true(not p.current.is_empty())
	assert_eq(m.selected, p.uid)
	var text := m.hud.bar_text()
	assert_true(text.contains(p.given))
	assert_true(not text.contains("%"), text)
	# The bar's first line is how they feel right now (FeelingSystem); the action's own words
	# are on the plate over their head.
	assert_true(text.contains(m.hud.feeling_now(p)), text)
	assert_eq(m.house.people[p.uid].doing_text(), str(w.pack.actions[p.current.action].label))
	# The bar shows the words for what is wrong, loudest first, and leaves out the fine one
	# (UI_PLAN: need words only when something is wrong).
	var levels := {}
	for c in m.session.strings.status_chips(p, w):
		levels[c["word"]] = c["level"]
	for word in p.status(m.session.pack).values():
		assert_eq(text.contains(word), levels[word] in ["bad", "warn"], "%s (%s)" % [word, levels[word]])
	# Five needs in qijia now (干净 is the fifth, at 11 like the first): three at their worst.
	assert_eq(m.hud.chip_levels(), ["bad", "bad", "bad", "warn"] as Array[String])
	var re := RegEx.create_from_string("\\d+%")
	var stripped := re.sub(text, "", true)
	assert_true(not stripped.contains("%"), stripped)
	for v in values:
		assert_true(not str(int(v)) in str(int(p.age)) + " 500", "%d collides" % int(v))
		assert_true(not stripped.contains(str(int(v))), "%d in %s" % [int(v), stripped])
	m.free()


## The kernel leaves a person idle for one step between two actions: the plate keeps the
## previous action's words through that gap, then falls back to the idle text (the bar
## shows the feeling of the moment).
func test_previous_action_shows_through_the_idle_step_between_actions():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	var idle: String = m.session.strings.t("idle")
	var label := str(w.pack.actions["wash_face"]["label"])
	AutonomySystem.start(w, p, "wash_face", -1)
	m.tick(0.016)
	assert_eq(pv.doing_text(), label)
	while not p.current.is_empty():
		w.advance(float(w.step_s))
	m.tick(0.016)
	assert_eq(pv.doing_text(), label)
	# The bar itself shows the feeling of the moment (FeelingSystem), not the action's words.
	assert_true(m.hud.bar_text().contains(m.hud.feeling_now(p)), m.hud.bar_text())
	assert_eq(pv.bob_offset(), 0.0)
	assert_eq(pv.progress(), -1.0)
	w.advance(float(w.step_s))         # one step later they are still idle (cancelled here)
	AutonomySystem.cancel(w, p)
	m.tick(0.016)
	assert_eq(pv.doing_text(), label)
	w.advance(float(w.step_s))         # idle longer than one step plus a second
	AutonomySystem.cancel(w, p)
	m.tick(0.016)
	assert_eq(pv.doing_text(), idle)
	assert_true(m.hud.bar_text().contains(m.hud.feeling_now(p)), m.hud.bar_text())
	m.free()


func test_praise_with_nothing_to_judge_toasts_reason():
	var m := _adopted()
	AutonomySystem.cancel(m.session.world, m.session.world.people[0])
	m.session.world.people[0].last_action = ""
	m.hud.press("praise")
	assert_eq(m.hud.toasts(), [m.session.strings.error("nothing_to_judge")])
	m.free()


func test_selection_moves_on_when_person_dies():
	var m := _adopted()
	var w := m.session.world
	var first := w.people[0]
	w.add_person(FamilySystem.make_person(w, [20, 20]))
	var second := w.people[1]
	m.tick(0.016)
	assert_eq(m.selected, first.uid)
	w.kill_person(first, "old_age")
	m.tick(0.016)
	assert_eq(m.selected, second.uid)
	w.kill_person(second, "old_age")
	m.tick(0.016)
	assert_eq(m.selected, -1)
	m.free()


func test_goal_done_event_toasts_with_reward():
	var m := _adopted()
	var w := m.session.world
	var gid = w.pack.goals.keys()[0]
	w.emit("goal_done", {"goal": gid, "reward": 4321})
	m.tick(0.016)
	var all := " ".join(m.hud.toasts())
	assert_true(all.contains("4321"))
	m.free()


func test_fifth_toast_pushes_out_the_oldest():
	var m := _adopted()
	for i in 5:
		m.hud.toast("条%d" % i)
	assert_eq(m.hud.toasts(), ["条1", "条2", "条3", "条4"])
	m.free()


func test_toast_expires_after_three_seconds():
	var m := _adopted()
	m.hud.toast("a")
	m.hud.tick(2.9)
	assert_eq(m.hud.toasts().size(), 1)
	m.hud.tick(0.2)
	assert_eq(m.hud.toasts().size(), 0)
	m.free()


func test_buttons_emit_open_and_judge_buttons_disabled_without_selection():
	var m := _main()
	m.tick(0.016)
	assert_true(m.hud.judge_disabled())
	var got := []
	m.hud.open.connect(func(what): got.append(what))
	for what in ["family", "shop", "ledger", "arrange", "settings"]:
		m.hud.press(what)
	assert_eq(got, ["family", "shop", "ledger", "arrange", "settings"])
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	assert_true(not m.hud.judge_disabled())
	m.free()


func test_bar_shows_only_money_when_not_living():
	var m := _main()
	m.tick(0.016)
	var text := m.hud.bar_text()
	assert_true(text.contains(m.session.strings.t("btn.settings")))
	assert_true(not text.contains(m.session.strings.t("btn.shop")))
	m.free()


func test_click_selects_person_and_empty_press_pans():
	var m := _adopted()
	var w := m.session.world
	var first := w.people[0]
	w.add_person(FamilySystem.make_person(w, [20, 20]))
	m.tick(0.016)
	var pv2: PersonView = m.house.people[w.people[1].uid]
	pv2.position = pv2.position + Vector2(200, 0)
	pv2.target = pv2.position
	assert_eq(m.house.person_at(pv2.position + Vector2(0, -10)), w.people[1].uid)
	assert_eq(m.house.person_at(pv2.position + Vector2(500, 500)), -1)
	_click(m, m.house.to_screen(pv2.position + Vector2(0, -10)))
	assert_eq(m.selected, w.people[1].uid)
	assert_true(first.uid != m.selected)
	m.free()


func test_praise_success_floats_a_character_for_one_second():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	p.last_action = str(w.pack.actions.keys()[0])
	p.last_action_t = w.now
	p.current = {}
	m.hud.press("praise")
	var pv: PersonView = m.house.people[p.uid]
	assert_true(pv.float_text() != "")
	pv.tick(1.1)
	assert_eq(pv.float_text(), "")
	m.free()



func test_bar_never_shows_a_percentage_busy_or_asleep():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	AutonomySystem.cancel(w, p)
	m.tick(0.016)
	assert_true(not m.hud.bar_text().contains("%"))   # idle: nothing
	var desk: int = w.objects.filter(func(o): return o.type == "desk")[0].uid
	m.session.command({"type": "drag", "person": p.uid, "object": desk})
	m.tick(0.016)
	assert_true(not m.hud.bar_text().contains("%"))   # no percentage any more
	assert_true(m.house.people[p.uid].progress() >= 0.0)   # the plate's line still runs
	AutonomySystem.cancel(w, p)
	# Night (local 23:00): sleep, which is slow and keeps its real length.
	clk["offset"] = 15 * 3600
	m.tick(0.016)
	var bed: int = w.objects.filter(func(o): return o.type == "kang")[0].uid
	AutonomySystem.start(w, p, "sleep", bed)
	m.tick(0.016)
	assert_true(w.pack.actions[str(p.current.get("action", ""))].get("slow", false))
	assert_true(not m.hud.bar_text().contains("%"))
	m.free()


## The bar names the season and the weather (qijia has seasons; _smoke has none).
func test_bar_shows_season_and_weather():
	var m := _adopted()
	var w := m.session.world
	w.weather = "drizzle"
	w.weather_slot = w.now / 900
	m.tick(0.016)
	var sky := m.session.strings.sky_line(w)
	assert_true(sky.ends_with("小雨"), sky)
	assert_true(m.hud.bar_text().contains(sky), m.hud.bar_text())
	m.queue_free()
	var s := _main("_smoke")
	s.session.command({"type": "adopt"})
	s.tick(0.016)
	assert_eq(s.session.strings.sky_line(s.session.world), "")
	s.queue_free()


## Rain and snow fall over the view as the weather entry's `view` says; clear skies draw none.
func test_weather_view_follows_the_weather():
	var m := _adopted()
	var w := m.session.world
	for c in [["clear", ""], ["drizzle", "rain"], ["snowfall", "snow"]]:
		w.weather = c[0]
		w.weather_slot = w.now / 900
		m.tick(0.016)
		assert_eq(m.weather.kind(), c[1], c[0])
		assert_eq(m.weather.drop_count() > 0, c[1] != "", c[0])
	m.queue_free()


## Sweeping away the last mess: the pay floats up over the sweeper and a toast says why.
func test_clean_house_pay_floats_over_the_sweeper():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	w.messes.clear()
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"), p.uid)
	m.tick(0.016)
	var amount := int(w.pack.cfg("clean_reward")["amount"])
	assert_eq(m.house.people[p.uid].float_text(), m.session.strings.t("float.clean_reward").replace("{n}", str(amount)))
	assert_true(m.hud.toasts().has(m.session.strings.t("ev.clean_reward").replace("{n}", str(amount))), str(m.hud.toasts()))
	m.queue_free()


## Something turning up on the ground shows a toast at the top (the pack's words); clicking
## it brings the thing to the middle of the house area.
## Was "a pickup shows a toast that takes the view there": the pickup is now told once, by
## its notice (which takes the view there, see test_view_notices); no toast says it again.
func test_a_pickup_is_told_by_its_notice_not_a_toast_too():
	var m := _adopted()
	var w := m.session.world
	var uid := CollectibleSystem.spawn(w)
	assert_true(uid >= 0)
	m.tick(0.016)
	var c := CollectibleSystem.find(w, uid)
	var line: String = m.session.strings.t("ev.pickup_spotted").format({"room": str(w.pack.rooms[str(c.room)]["name"])})
	assert_true(not m.hud.toasts().has(line), str(m.hud.toasts()))
	assert_true(m.hud.notices().any(func(x): return x["id"] == "pickup:%d" % uid))
	# A toast given a click runs it and goes; one without a click does nothing when clicked.
	var hit := [false]
	m.hud.toast("clickable", func(): hit[0] = true)
	assert_true(m.hud.click_toast(m.hud.toasts().find("clickable")))
	assert_true(hit[0])
	assert_true(not m.hud.toasts().has("clickable"), "the toast goes once clicked")
	m.hud.toast("plain")
	assert_true(not m.hud.click_toast(m.hud.toasts().find("plain")))
	m.free()


func test_toasts_take_turns_two_at_most_and_say_nothing_twice():
	var m := _adopted()
	for t in ["一", "二", "三"]:
		m.hud.toast(t)
	m.hud.toast("二")
	assert_eq(m.hud.toasts(), ["一", "二", "三"] as Array[String], "the same words are not queued twice")
	assert_eq(m.hud.visible_toasts(), ["一", "二"] as Array[String])
	m.hud.tick(Hud.TOAST_SECONDS + 0.1)
	assert_eq(m.hud.visible_toasts(), ["三"] as Array[String], "the waiting one gets its turn")
	m.hud.tick(Hud.TOAST_SECONDS - 0.2)
	assert_eq(m.hud.visible_toasts(), ["三"] as Array[String], "with its full time")
	m.free()
