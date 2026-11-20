extends TestCase
## The view of wishes, low mood and old stories: bubble, thanks, bar, shop mark, the old-things
## box, fragment and visitor cards, the marks in the yard, and dragging onto a dig mark.

var clk := {"unix": 1767254400.0, "offset": 0}   # 08:00
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_wish_view_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _adopted(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.overlays.refresh()
	m.tick(0.016)
	return m


func _read_fragments(m: Main) -> void:
	while m.overlays.current() == "fragment":
		m.overlays.press("btn.close")


## Finds every fragment of `sid` through the kernel and lets the view see the events.
func _find_all(m: Main, sid: String) -> void:
	var w := m.session.world
	var guard := 0
	while not StorySystem.next_fragment(w, sid).is_empty() and guard < 20:
		guard += 1
		for c in w.collectibles.duplicate():
			if c.has("story"):
				w.collectibles.erase(c)
		CollectibleSystem.collect(w, w.people[0], StorySystem.spawn_fragment(w, sid))
	m.session.command({"type": "noop"})   # dispatches the queued events
	m.tick(0.016)


func test_bubble_bar_and_thanks():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	p.wish = {"id": "want_sugar_figure", "expires_at": w.now + 8 * 3600}  # just formed (a wish shows in pulses later)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	assert_eq(pv.wish_bubble(), "想要个糖人")
	assert_true(m.hud.bar_text().contains("想要个糖人"))
	assert_eq(pv.pose() == "thanks", false)
	w.money = 100
	m.session.command({"type": "buy", "item": "sugar_figure"})
	m.session.command({"type": "use_item", "item": "sugar_figure", "person": p.uid})
	m.tick(0.016)
	assert_eq(pv.wish_bubble(), "")
	assert_true(not m.hud.bar_text().contains("想要个糖人"))
	assert_eq(pv.pose(), "thanks")
	assert_true(pv.thanking())
	# Told once, by the thank-you notice (was a toast; a toast no longer repeats a notice).
	assert_true(m.hud.notices().any(func(x): return x["id"] == "thanks:%d" % p.uid), m.hud.notice_text())
	assert_true(m.hud.notice_text().contains("如愿"), m.hud.notice_text())
	m.free()


func test_shop_marks_the_wished_item():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	p.wish = {"id": "want_cake", "expires_at": w.now + 3600}
	m.panels.open("shop")
	var t := m.panels.text()
	assert_true(t.contains(m.session.strings.person_name(p) + "想要"), t)
	# The goods now sit under the market's tabs (UI_PLAN); a tab that holds more than one
	# kind of shop still names each, so the clothes tab shows the draper and the sundries.
	var clothes := ""
	for tab in m.panels._market_tabs(w):
		if (tab["cats"] as Array).has("布庄"):
			clothes = tab["id"]
	m.panels.press(clothes)
	t = m.panels.text()
	assert_true(t.contains("布庄") and t.contains("杂货"), t)
	m.free()


func test_status_shows_the_low_mood_word_and_events_have_lines():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	var s := m.session.strings
	# The bar leads with what they feel now; the low mood is among the warning words after it.
	p.mood = "sad"
	assert_true(s.status_line(p, w).contains(" · 难过"), s.status_line(p, w))
	p.mood = "depressed"
	assert_true(s.status_line(p, w).contains(" · 抑郁"), s.status_line(p, w))
	var name := s.person_name(p)
	assert_eq(s.event({"type": "mood_changed", "person": p.uid, "mood": "depressed", "was": "sad"}, w), name + "这几天闷闷不乐")
	assert_eq(s.event({"type": "mood_changed", "person": p.uid, "mood": "sad", "was": "depressed"}, w), name + "缓过来了")
	assert_eq(s.event({"type": "mood_changed", "person": p.uid, "mood": "sad", "was": ""}, w), "")
	assert_true(s.event({"type": "wish_formed", "person": p.uid, "wish": "hot_meal"}, w).contains("想吃口热饭"))
	assert_true(s.event({"type": "wish_expired", "person": p.uid, "wish": "hot_meal"}, w).contains("想吃口热饭"))
	m.free()


func test_smoke_has_no_old_things_box():
	var m := _adopted("_smoke")
	assert_true(not m.hud.bar_text().contains(m.session.strings.t("btn.stories")))
	m.free()


func test_fragment_card_then_the_box_lists_what_was_found():
	var m := _adopted()
	var w := m.session.world
	assert_true(m.hud.bar_text().contains("旧物匣"))
	m.session.command({"type": "noop"})
	w.advance(60)
	var uid := StorySystem.spawn_fragment(w, "embroidered_shoe")
	CollectibleSystem.collect(w, w.people[0], uid)
	m.session.command({"type": "noop"})
	m.tick(0.016)
	assert_eq(m.overlays.current(), "fragment")
	var card := m.overlays.text()
	assert_true(card.contains("井边的绣鞋") and card.contains("捡到了半幅绣样") and card.contains("并蒂莲"), card)
	m.overlays.press("btn.close")
	assert_eq(m.overlays.current(), "")
	m.hud.press("stories")
	assert_eq(m.panels.opened(), "stories")
	var t := m.panels.text()
	assert_true(t.contains("井边的绣鞋") and t.contains("半幅绣样") and t.contains("并蒂莲"), t)
	assert_true(t.contains("……"))
	assert_true(not t.contains("书生的藏银"), "locked stories stay hidden")
	m.free()


func test_visitor_card_brings_the_keepsake():
	var m := _adopted()
	var w := m.session.world
	w.advance(60)
	_find_all(m, "embroidered_shoe")
	_read_fragments(m)
	assert_eq(m.overlays.current(), "visitor")
	assert_true(m.overlays.text().contains("阿芸") and m.overlays.text().contains("300"))
	var money := w.money
	m.overlays.press("btn.receive")
	assert_eq(m.overlays.current(), "")
	assert_eq(w.money, money + 300)
	assert_true(w.objects.any(func(o): return o.type == "ayun_hoop"))
	m.arrange.enter()
	assert_true(not m.arrange.has_button("type:ayun_hoop"), "a keepsake is not for sale")
	m.free()


func test_shadow_in_the_yard_only_at_night():
	var m := _adopted()
	var w := m.session.world
	var g := TestKit.adult(w, 30.0)
	g.generation = 2
	w.advance(60)
	assert_true(StorySystem.marks(w).is_empty())
	w.set_time(w.now + 14 * 3600, 0)   # 22:00
	var marks := StorySystem.marks(w)
	assert_eq(marks.size(), 1)
	assert_eq([marks[0].room, marks[0].look], ["yard", "figure"])
	m.free()


func test_dropping_someone_on_the_dig_mark_starts_digging_there():
	var m := _adopted()
	var w := m.session.world
	w.money = 5000
	w.command({"type": "build_room", "room": "study"})
	w.advance(60)
	_find_all(m, "scholar_silver")
	_read_fragments(m)
	assert_true(m.hud.toasts().any(func(t): return t.contains("九步")), str(m.hud.toasts()))
	var p := w.people[0]
	var at := m.house.layout.cell_center("yard", 11, 2)
	var hit := m.house.layout.pick(w, at)
	assert_eq([hit.kind, hit.get("story", "")], ["mark", "scholar_silver"])
	m.drag.begin(p.uid)
	var r := m.drag.drop(at)
	assert_true(r.get("ok", false), str(r))
	assert_eq(str(p.current.action), "dig_for_silver")
	m.tick(0.016)
	assert_eq(m.house.people[p.uid].target, at)
	m.free()
