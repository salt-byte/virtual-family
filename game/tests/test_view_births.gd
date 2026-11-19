extends TestCase
## The view of births: the pregnancy word in the bar, the birth card, the family panel by
## generation with the dead greyed out, the bed hint, the relative's card, the away summary,
## and dragging a grown-up onto a baby.

var clk := {"unix": 1767268800.0, "offset": 0}   # noon
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_birth_view_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


## A married qijia couple on screen, both 25, the cards read.
func _couple() -> Main:
	var m := Main.create("qijia", _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	w.pack.config["wish_chance_per_hour"] = 0.0
	w.pack.config["story_interval_min"] = 1000000000   # no story cards in the way
	w.stock["food"] = 50
	w.next_proposal_at = w.now
	w.advance(60)
	m.session.command({"type": "answer_proposal", "id": w.proposals[0].id, "accept": true})
	for p in w.people:
		p.age = 25.0
	m.tick(0.016)
	return m


func _wife(w: World) -> Person:
	for p in w.people:
		if p.gender == "female":
			return p
	return null


## Conceives and lets the child be born; the view sees the events.
func _born(m: Main) -> Person:
	var w := m.session.world
	var wife := _wife(w)
	BirthSystem.conceive(w, wife, w.person(wife.spouse))
	w.advance(3 * 3600 + 60)
	m.session.command({"type": "noop"})   # dispatches the queued events
	m.tick(0.016)
	for p in w.people:
		if p.mother == wife.uid:
			return p
	return null


func test_the_bar_says_she_is_with_child():
	var m := _couple()
	var w := m.session.world
	var wife := _wife(w)
	BirthSystem.conceive(w, wife, w.person(wife.spouse))
	m.select(wife.uid)
	m.tick(0.016)
	assert_true(m.hud.bar_text().contains("怀着身孕"), m.hud.bar_text())
	m.free()


func test_a_birth_brings_a_card_and_the_family_panel_shows_generations():
	var m := _couple()
	var w := m.session.world
	var child := _born(m)
	assert_true(child != null)
	assert_eq(m.overlays.current(), "born")
	var card := m.overlays.text()
	assert_true(card.contains("添丁"), card)
	assert_true(card.contains(child.given), card)
	assert_true(card.contains("大胖小子") or card.contains("闺女"), card)
	assert_true(card.contains("第二代"), card)
	m.overlays.press("btn.close")
	assert_eq(m.overlays.current(), "")
	m.panels.open("family")
	var t := m.panels.text()
	assert_true(t.contains("第一代") and t.contains("第二代"), t)
	assert_true(t.contains("个月"), t)
	assert_true(t.contains("配偶"), t)
	assert_true(t.find("第一代") < t.find("第二代"), t)
	# The dead stay in the tree, greyed, with their age.
	m.panels.close()
	w.kill_person(w.person(_wife(w).spouse), "old_age")
	m.overlays.refresh()
	m.panels.open("family")
	assert_true(m.panels.text().contains("已故"), m.panels.text())
	m.free()


func test_the_bed_hint_shows_once_and_in_the_family_panel():
	var m := _couple()
	var w := m.session.world
	_born(m)
	m.overlays.press("btn.close")
	w.advance(3600)
	m.session.command({"type": "noop"})
	m.tick(0.016)
	assert_true(m.hud.toasts().any(func(x): return x.contains("炕睡不下")), str(m.hud.toasts()))
	m.panels.open("family")
	assert_true(m.panels.text().contains("炕睡不下"), m.panels.text())
	m.free()


func test_a_relative_comes_when_only_children_are_left():
	var m := _couple()
	var w := m.session.world
	var child := _born(m)
	m.overlays.press("btn.close")
	var wife := _wife(w)
	w.kill_person(w.person(wife.spouse), "old_age")
	w.kill_person(wife, "old_age")
	m.session.command({"type": "noop"})
	m.tick(0.016)
	assert_eq(w.phase, "living")
	assert_eq(m.overlays.current(), "relative")
	assert_true(m.overlays.text().contains("远房亲戚"), m.overlays.text())
	assert_true(child.alive)
	m.free()


func test_away_summary_names_the_newborn():
	var m := _couple()
	var w := m.session.world
	var s := ViewStrings.new(w.pack)
	var lines := s.summary_lines({"simulated_seconds": 7200, "births": [w.people[0].uid]}, w)
	assert_true(lines.any(func(l): return l.contains("出生了")), str(lines))


func test_dropping_a_grown_up_on_a_baby_feeds_it():
	var m := _couple()
	var w := m.session.world
	var child := _born(m)
	m.overlays.press("btn.close")
	child.needs["fed"] = 10.0
	var h := w.person(_wife(w).spouse)
	AutonomySystem.cancel(w, h)
	m.tick(0.016)
	# Whoever else picked the baby up on their own in that frame puts it down again (with
	# letters the random draws moved, and the mother now happens to start feeding it first).
	for q in w.people:
		if q != h and int(q.current.get("target_uid", -1)) == child.uid:
			AutonomySystem.cancel(w, q)
	var bpv: PersonView = m.house.people[child.uid]
	var at := bpv.position + Vector2(0, -6)
	m.drag.begin(h.uid)
	m.drag.move(at)
	var r := m.drag.drop(at)
	assert_true(r.get("ok", false), str(r))
	assert_eq(str(h.current.get("action", "")), "feed_baby")
	m.free()
