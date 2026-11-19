extends TestCase
## Letters in the view: the bird lands on the compound wall while a letter waits, its tube
## opens the newest letter, choices answer it, and the letter box keeps them newest first.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main(pack := "qijia") -> Main:
	n += 1
	var d := "user://test_view_letters_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create(pack, d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _done(m: Main) -> void:
	m.get_parent().remove_child(m)
	m.free()


## A letter of illness from the one grown-up, made through the kernel.
func _ill_letter(m: Main) -> Dictionary:
	var w := m.session.world
	w.pack.config["letters"]["chance"] = {"ill": 1.0}
	w.letter_minor_at = 0
	w.emit("fell_ill", {"person": w.people[0].uid})
	w.advance(float(w.step_s))
	m.session._dispatch_events()
	return w.letters.back()


func test_the_bird_lands_on_the_wall_and_its_tube_opens_the_letter():
	var m := _main()
	assert_true(not m.letters.bird.visible, "no letter, no bird")
	assert_true(m.letters.box_button.visible)
	var l := _ill_letter(m)
	m.tick(0.016)
	assert_true(m.letters.bird.visible)
	assert_true(m.letters.bird.flying, "it flies in first")
	for i in 120:
		m.tick(0.016)
	assert_true(not m.letters.bird.flying, "and then sits")
	var at := m.letters.bird.feet
	var area := Rect2(Vector2.ZERO, Vector2(1280, 720 - HouseView.BOTTOM_BAR))
	assert_true(area.has_point(at), "on screen: %s" % at)
	assert_eq(m.letters.bird.count, 1)
	assert_true(m.letters.box_button.text.contains("1"))
	m.letters.open_newest()
	m.tick(0.016)
	assert_eq(m.letters.opened(), "letter")
	assert_true(m.is_house_blocked())
	assert_true(m.letters.text().contains(str(l["text"])), m.letters.text())
	assert_true(m.letters.text().contains(str(l["sign"])))
	assert_true(bool(l["read"]))
	assert_true(not m.letters.bird.visible, "the bird leaves once nothing waits")
	m.letters.press("btn.close")
	assert_eq(m.letters.opened(), "")
	_done(m)


func test_the_bird_sits_on_a_spot_of_the_compound_wall():
	var m := _main()
	_ill_letter(m)
	for i in 120:
		m.tick(0.016)
	var site := m.house.layout.site
	var at := m.letters.bird.feet + Vector2(0, LetterView.WALL_TOP * m.house.scale.y)
	var cell := m.house.world_pos(at) / HouseLayout.CELL
	var c := site.compound
	var on_h := absf(cell.y - c.position.y) < 0.01 or absf(cell.y - c.end.y) < 0.01
	var on_v := absf(cell.x - c.position.x) < 0.01 or absf(cell.x - c.end.x) < 0.01
	assert_true(on_h or on_v, "on the wall line: %s" % cell)
	_done(m)


func test_a_proposal_letter_is_answered_from_the_paper():
	var m := _main()
	var w := m.session.world
	w.next_proposal_at = w.now
	w.advance(60)
	m.session._dispatch_events()
	m.overlays.refresh()
	var l: Dictionary = w.letters.back()
	assert_eq(l["kind"], "proposal")
	m.letters.open_letter(int(l["id"]))
	m.tick(0.016)
	assert_true(m.letters.has_button("choice.0"))
	assert_true(m.letters.text().contains("应下这门亲"), m.letters.text())
	m.letters.press("choice.0")
	m.tick(0.016)
	assert_eq(w.people.size(), 2, "the match moved in")
	assert_true(not m.letters.has_button("choice.0"))
	assert_true(m.letters.text().contains("应下这门亲"), "the answer stays on the paper")
	_done(m)


func test_the_letter_box_lists_letters_newest_first():
	var m := _main()
	# No old things turn up in the half hour (their card would cover the box).
	m.session.world.pack.config["story_interval_min"] = 1000000
	var a := _ill_letter(m)
	m.session.world.advance(30 * 60)
	var b := _ill_letter(m)
	m.letters.open_box()
	m.tick(0.016)
	assert_eq(m.letters.opened(), "box")
	var t := m.letters.text()
	assert_true(t.find(str(b["writer"])) >= 0)
	var rows: Array = []
	for id in m.letters._buttons:
		if str(id).begins_with("open."):
			rows.append(int(str(id).trim_prefix("open.")))
	assert_eq(rows[0], int(b["id"]))
	assert_true(rows.find(int(a["id"])) > 0)
	var sorted := rows.duplicate()
	sorted.sort()
	sorted.reverse()
	assert_eq(rows, sorted, "newest first")
	m.letters.press("open.%d" % int(a["id"]))
	assert_eq(m.letters.opened(), "letter")
	m.letters.press("btn.letters")
	assert_eq(m.letters.opened(), "box")
	_done(m)


func test_letters_away_show_in_the_summary():
	var m := _main()
	var w := m.session.world
	w.pack.config["letters"]["chance"] = {"ill": 1.0}
	w.emit("fell_ill", {"person": w.people[0].uid})
	var s := w.catch_up(600)
	assert_eq((s["letters"] as Array).size(), 1)
	var lines := m.session.strings.summary_lines(s, w)
	assert_true(lines.any(func(x): return x.contains("1")), str(lines))
	assert_true("\n".join(lines).contains(m.session.strings.t("away.letters").replace("{n}", "1")), str(lines))
	_done(m)


func test_a_pack_without_letters_shows_no_bird_and_no_box():
	var m := _main("_smoke")
	m.tick(0.016)
	assert_true(not m.letters.bird.visible)
	assert_true(not m.letters.box_button.visible)
	m.letters.open_box()
	assert_eq(m.letters.opened(), "")
	_done(m)
