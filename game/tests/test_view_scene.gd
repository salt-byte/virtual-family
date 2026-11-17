extends TestCase

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_scene_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	return m


func test_both_packs_boot_and_adopt():
	for pack in ["qijia", "_smoke"]:
		var m := _main(pack)
		m.tick(0.016)
		assert_eq(m.house.people.size(), 0)
		m.session.command({"type": "adopt"})
		m.tick(0.016)
		assert_eq(m.house.people.size(), 1)
		m.free()


func test_person_walks_to_the_object_they_use():
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	# 新开的一局没有家具：先免费放一件能用的
	var uid := w.add_object("stool", "hall", 3, 3)
	assert_true(m.session.command({"type": "drag", "person": p.uid, "object": uid}).ok)
	var pv: PersonView = m.house.people[p.uid]
	m.tick(0.016)
	assert_eq(pv.target, m.house.layout.stand_pos(w.object(uid), w.pack))
	for i in 200:
		pv.tick(0.05)
	assert_true(pv.position.distance_to(pv.target) < 1.0)
	m.free()


func test_dead_person_node_is_removed():
	var m := _main()
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	var p := m.session.world.people[0]
	m.session.world.kill_person(p, "old_age")
	m.tick(0.016)
	assert_eq(m.house.people.size(), 0)
	m.free()


func test_night_amount():
	assert_eq(HouseView.night_amount(12.0), 0.0)
	assert_eq(HouseView.night_amount(23.0), 1.0)
	assert_near(HouseView.night_amount(19.0), 0.5)


func test_pan_is_clamped_to_the_house():
	var m := _main()
	m.house.pan(Vector2(100000, 100000))
	var a := m.house.position
	m.house.pan(Vector2(100000, 100000))
	assert_eq(m.house.position, a)
	m.house.pan(Vector2(-100000, -100000))
	var b := m.house.position
	m.house.pan(Vector2(-100000, -100000))
	assert_eq(m.house.position, b)
	assert_true(a != b)
	# the house never leaves the 1280x720 screen entirely
	var bounds := m.house.layout.bounds()
	assert_true(a.x + bounds.position.x < 1280.0 and b.x + bounds.end.x > 0.0)
	assert_eq(m.house.world_pos(m.house.position), Vector2.ZERO)
	m.free()


func test_two_people_on_one_cell_are_offset():
	var m := _main()
	m.session.command({"type": "adopt"})
	var extra := Person.new()
	extra.gender = "male"
	m.session.world.add_person(extra)
	m.tick(0.016)
	var ps := m.session.world.people
	var a: PersonView = m.house.people[ps[0].uid]
	var b: PersonView = m.house.people[ps[1].uid]
	assert_eq(a.base_target, b.base_target)
	assert_near(absf(a.target.x - b.target.x), 20.0)
	m.free()


func test_invalid_pack_does_not_crash():
	var m := _main("no_such_pack")
	m.tick(0.016)
	m.house.queue_redraw()
	assert_eq(m.house.people.size(), 0)
	m.free()
