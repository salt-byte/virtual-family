extends TestCase
## The keepsake box on screen: the cabinet's shelves, a piece's card, selling the extras, the
## midpoint line on a fragment card and the ending card of a finished story.

var clk := {"unix": 1767268800.0, "offset": 0}   # noon
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_cabinet_view_%d/" % n
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


func _dispatch(m: Main) -> void:
	m.session.command({"type": "noop"})
	m.tick(0.016)


## Jumps to just before the next local midnight and lets the new day begin (when stories
## that come by chance roll their dice).
func _new_day(w: World) -> void:
	w.set_time(w.now + 86400 - posmod(w.now + w.utc_offset, 86400) - 30, w.utc_offset)
	w.advance(60)


func _pick(m: Main, kind: String) -> void:
	var w := m.session.world
	CollectibleSystem.collect(w, w.people[0], CollectibleSystem.spawn(w, kind))


func _find_next(m: Main, sid: String) -> void:
	var w := m.session.world
	for c in w.collectibles.duplicate():
		if c.has("story"):
			w.collectibles.erase(c)
	CollectibleSystem.collect(w, w.people[0], StorySystem.spawn_fragment(w, sid))
	_dispatch(m)


func test_cabinet_shelves_the_finds_and_sells_the_extras():
	var m := _adopted()
	var w := m.session.world
	for i in 3:
		_pick(m, "egg")
	_pick(m, "hairpin")
	_dispatch(m)
	assert_true(m.hud.toasts().any(func(t): return t.contains("收进了旧物匣")), str(m.hud.toasts()))
	m.hud.press("stories")
	assert_eq(m.panels.opened(), "stories")
	var t := m.panels.text()
	assert_true(t.contains("捡来的 2 / 8"), t)
	assert_true(m.panels.has_button("curio:egg") and m.panels.has_button("curio:hairpin"))
	assert_true(not m.panels.has_button("curio:coins"), "a kind not found yet stays a ?")
	assert_true(not m.panels.has_button("curio:old_kite"), "a story's keepsake shows once it is in")
	var egg := int(w.pack.collectibles["egg"]["value"])
	assert_true(m.panels.has_button("sell_extras"))
	assert_true(t.contains("+%d 文" % (2 * egg)), t)
	m.panels.press("curio:egg")
	t = m.panels.text()
	assert_true(t.contains("鸡窝外的鸡蛋") and t.contains("3"), t)
	var money := w.money
	m.panels.press("sell_one:egg")
	assert_eq([w.box["egg"], w.money], [2, money + egg])
	m.panels.press("sell_one:egg")
	assert_eq(w.box["egg"], 1)
	assert_true(m.panels.is_disabled("sell_one:egg"), "the last one is kept")
	m.panels.press("btn.back")
	assert_true(not m.panels.has_button("sell_extras"))
	_pick(m, "hairpin")
	_pick(m, "hairpin")
	m.panels.refresh()
	money = w.money
	m.panels.press("sell_extras")
	assert_eq([w.box["hairpin"], w.money], [1, money + 2 * int(w.pack.collectibles["hairpin"]["value"])])
	m.free()


func test_story_shelf_shows_its_title_once_a_piece_is_in():
	var m := _adopted()
	var w := m.session.world
	w.advance(60)
	_dispatch(m)
	m.hud.press("stories")
	var t := m.panels.text()
	assert_true(t.contains("0 / 6") and not t.contains("井边的绣鞋"), t)
	m.panels.close()
	_find_next(m, "embroidered_shoe")
	m.overlays.press("btn.close")
	m.hud.press("stories")
	assert_true(m.panels.text().contains("井边的绣鞋 1 / 6"), m.panels.text())
	m.free()


func test_the_midpoint_line_shows_on_the_fragment_card():
	var m := _adopted()
	var w := m.session.world
	w.advance(60)
	_dispatch(m)
	for i in 3:
		_find_next(m, "embroidered_shoe")
	var cards: Array[String] = []
	while m.overlays.current() == "fragment":
		cards.append(m.overlays.text())
		m.overlays.press("btn.close")
	assert_eq(cards.size(), 3)
	var mid := str(w.pack.stories["embroidered_shoe"]["midpoint"])
	assert_true(not cards[1].contains(mid) and cards[2].contains(mid), str(cards))
	m.free()


func test_a_finished_story_plays_its_ending_card():
	var m := _adopted()
	var w := m.session.world
	w.pack.stories["ferry_tags"]["unlock"]["chance_per_day"] = 1.0e7
	w.pack.stories["peddler_bell"]["unlock"]["chance_per_day"] = 0.0001
	w.pack.stories["paper_kite"]["unlock"]["chance_per_day"] = 0.0001
	_new_day(w)
	assert_true(w.stories.has("ferry_tags"))
	var money := w.money
	for i in 4:
		_find_next(m, "ferry_tags")
	while m.overlays.current() == "fragment":
		m.overlays.press("btn.close")
	assert_eq(m.overlays.current(), "story_end")
	var t := m.overlays.text()
	assert_true(t.contains("渡口的木牌") and t.contains("一串木牌") and t.contains("刻着欠字的木牌"), t)
	m.overlays.press("btn.read_on")
	assert_eq(m.overlays.current(), "story_end")
	t = m.overlays.text()
	assert_true(t.contains("布包") and t.contains("120"), t)
	m.overlays.press("btn.close")
	assert_eq(m.overlays.current(), "")
	assert_eq(w.money, money + 120)
	assert_eq(w.stories["ferry_tags"]["stage"], "done")
	m.hud.press("stories")
	assert_true(m.panels.text().contains("渡口的木牌 4 / 4 ✓"), m.panels.text())
	m.free()
