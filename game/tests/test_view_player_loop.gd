extends TestCase
## The player loop in the view: litter in the 45° view can be dropped on, the bar shows the
## feeling of the moment, and someone sharing their earnings says so over their head.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_view_player_loop_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


## The litter sprite sits a little below its cell in the 45° view: a drop where it is drawn
## (or on the next cell) still sends the person to pick it up.
func test_drop_beside_litter_in_the_iso_view_picks_it_up():
	var m := _main()
	var w := m.session.world
	assert_true(m.house.iso, "qijia draws the 45° view")
	var p := w.people[0]
	var mu := MessSystem.spawn(w, "wrapper", "hall", Vector2i(3, 2))
	m.tick(0.016)
	var at := m.house.layout.cell_center("hall", 3, 2) + Vector2(0, HouseLayout.CELL.y * 0.9)
	assert_eq(str(m.house.layout.pick(w, at).kind), "mess")
	m.drag.begin(p.uid)
	var r := m.drag.drop(at)
	assert_true(r.ok, str(r))
	assert_eq(str(r.action), "pick_wrapper")
	assert_eq(int(p.current["target_uid"]), mu)
	m.free()


func test_the_bar_shows_the_feeling_of_the_moment():
	var m := _main()
	var w := m.session.world
	var p := w.people[0]
	for nid in p.needs:
		p.needs[nid] = 90.0
	p.current = {}
	var s := m.session.strings
	assert_eq(s.status_line(p, w), "歇口气")
	p.needs["clean"] = 20.0
	assert_eq(s.status_line(p, w), "浑身不自在 · 身上黏糊糊")
	p.needs["clean"] = 90.0
	p.current = {"action": "study", "object_uid": -1, "target_uid": -1, "remaining_s": 60}
	assert_eq(s.status_line(p, w), "干活呢")
	m.free()


func test_someone_sharing_earnings_says_it_over_their_head():
	var m := _main()
	var w := m.session.world
	var p := w.people[0]
	p.current = {}
	EconomySystem.earn(w, 40, "work", p.uid)
	m.tick(0.016)
	var pv: PersonView = m.house.people[p.uid]
	assert_true(pv.thanking())
	assert_eq(pv.thanks_words(), "今天挣了 40 文！")
	assert_true(pv.thanks_width() > 80.0)
	m.free()
