extends TestCase
## The family panel shows each grown-up's livelihood and lets the player change it; the
## event line tells of livelihoods taken up and changed.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _living() -> Main:
	n += 1
	var d := "user://test_view_livelihood_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _job(pk: Pack, track: String) -> String:
	return str(pk.livelihoods[track]["name"])


func _level(pk: Pack, track: String, level: int) -> String:
	return str(pk.livelihoods[track]["levels"][level]["name"])


func test_event_lines_name_the_livelihood():
	var m := _living()
	var w := m.session.world
	var s := m.session.strings
	var p := w.people[0]
	var took := s.event({"type": "took_up", "person": p.uid, "track": "farming"}, w)
	assert_true(took.contains(p.given) and took.contains(_job(w.pack, "farming")), took)
	var changed := s.event({"type": "changed_track", "person": p.uid, "track": "tofu"}, w)
	assert_true(changed.contains(p.given) and changed.contains(_job(w.pack, "tofu")), changed)
	assert_true(changed.contains(_level(w.pack, "tofu", 0)), changed)
	p.track = "peddling"
	p.level = 1
	var married := s.event({"type": "married", "person": p.uid}, w)
	assert_true(married.contains(_job(w.pack, "peddling")) and married.contains(_level(w.pack, "peddling", 1)), married)
	m.free()


func test_family_panel_shows_livelihood_and_child_as_too_young():
	var m := _living()
	var w := m.session.world
	var p := w.people[0]
	p.track = "carpentry"
	p.level = 1
	var c := FamilySystem.make_person(w, [8, 9])
	w.add_person(c)
	m.panels.open("family")
	var text := m.panels.text()
	assert_true(text.contains(_job(w.pack, "carpentry")), text)
	assert_true(text.contains(_level(w.pack, "carpentry", 1)), text)
	assert_true(text.contains(m.session.strings.t("family.child")), text)
	assert_true(m.panels.has_button("change:%d" % p.uid))
	assert_true(not m.panels.has_button("change:%d" % c.uid))
	m.free()


func test_change_flow_lists_livelihoods_and_issues_the_command():
	var m := _living()
	var w := m.session.world
	var p := w.people[0]
	p.track = "reading"
	p.level = 2
	m.panels.open("family")
	m.panels.press("change:%d" % p.uid)
	var text := m.panels.text()
	assert_true(text.contains(m.session.strings.t("change.note")), text)
	assert_true(not m.panels.has_button("track:reading"), "the current one is not offered")
	for t in w.pack.livelihoods:
		if t != "reading":
			assert_true(m.panels.has_button("track:" + t), t)
			assert_true(text.contains(_job(w.pack, t)) and text.contains(_level(w.pack, t, 0)), t)
	assert_true(text.contains(str(int(w.pack.livelihoods["tofu"]["levels"][0]["daily_income"]))))
	m.panels.press("track:tofu")
	assert_eq(p.track, "tofu")
	assert_eq(p.level, 0)
	assert_eq(m.panels.opened(), "family")
	assert_true(m.panels.has_button("change:%d" % p.uid), "back to the family list")
	assert_true(m.panels.text().contains(_job(w.pack, "tofu")))
	m.free()


func test_change_flow_can_be_cancelled():
	var m := _living()
	var p := m.session.world.people[0]
	var before := p.track
	m.panels.open("family")
	m.panels.press("change:%d" % p.uid)
	m.panels.press("change.cancel")
	assert_eq(p.track, before)
	assert_true(m.panels.has_button("change:%d" % p.uid))
	m.free()


func test_change_layout_fits():
	var m := _living()
	m.panels.open("family")
	m.panels.press("change:%d" % m.session.world.people[0].uid)
	var size := m.panels.card_size()
	assert_true(size.x <= 560.0, "width %s" % size.x)
	assert_true(size.y <= 520.0, "height %s" % size.y)
	for l in m.panels.row_labels():
		assert_true(l.autowrap_mode == TextServer.AUTOWRAP_OFF or l.custom_minimum_size.x >= 100.0, l.text)
	m.free()
