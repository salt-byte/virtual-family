extends TestCase
## The bubble over a head (`NeedBubble`): an ask before a wish, an icon and a few words, a
## waiting ask bobs, a wish shows in pulses; and the bar's face for the selected one.

var clk := {"unix": 1767254400.0, "offset": 0}   # 08:00
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_asks_view_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _adopted() -> Main:
	var m := Main.create("qijia", _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.overlays.refresh()
	m.tick(0.016)
	return m


func test_an_ask_shows_before_a_wish_with_its_icon_and_bobs_while_it_waits():
	var m := _adopted()
	var w := m.session.world
	var p := w.people[0]
	p.wish = {"id": "want_sugar_figure", "expires_at": w.now + 8 * 3600}
	p.ask = {"id": "hunger", "phase": "wait", "until": w.now + 75}
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	assert_eq(pv.wish_bubble(), "饿了")
	var b := NeedBubble.of(w, p)
	assert_eq(b["icon"], "bowl")
	assert_eq(b["kind"], "ask")
	assert_true(bool(b["waiting"]))
	assert_true(absf(NeedBubble.bob(b, 0.35)) > 1.0, "a waiting ask bobs")
	assert_true(pv.label_size().x >= NeedBubble.size_of(b).x)
	# Dealing with it alone: still there, but calm.
	p.ask["phase"] = "self"
	assert_eq(NeedBubble.bob(NeedBubble.of(w, p), 0.35), 0.0)
	# Gone: the wish shows again (it has just formed).
	p.ask = {}
	m.tick(0.016)
	assert_eq(pv.wish_bubble(), "想要个糖人")
	# Thanking: no bubble at all.
	p.thanks_until = w.now + 10
	assert_true(NeedBubble.of(w, p).is_empty())
	m.free()


func test_a_wish_shows_when_it_forms_then_in_pulses_and_a_need_wish_always():
	var w := BalanceRun.setup("qijia", 1)
	var p := w.people[0]
	p.wish = {"id": "want_cake", "expires_at": w.now + 8 * 3600}
	var shown := 0
	for t in 600:
		if t < NeedBubble.WISH_FIRST_S:
			assert_true(NeedBubble.wish_shown(w, p, WishSystem.current(w, p)))
		if NeedBubble.wish_shown(w, p, WishSystem.current(w, p)):
			shown += 1
		w.now += 1
	assert_true(shown > 150 and shown < 330, str(shown))
	p.wish = {"id": "hot_meal", "expires_at": w.now - 5 * 3600}
	assert_true(NeedBubble.wish_shown(w, p, WishSystem.current(w, p)))


func test_every_ask_icon_draws():
	var pack := Pack.load_dir("res://packs/qijia")
	for id in pack.asks:
		var icon := str(pack.asks[id]["icon"])
		assert_true(NeedBubble.SHAPES.has(icon) or pack.object_types.has(icon), id + ": " + icon)
