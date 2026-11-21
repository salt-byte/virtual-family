extends TestCase
## Going to bed in the 45° view: people lie along the bed on its surface, under a quilt, with
## their own head on the pillow; sleepers sharing a bed lie side by side; lying down and
## getting up take a moment; dozing sits nodding; a baby sleeps on the bed beside its parent.

var clk := {"unix": 1767254400.0, "offset": 15 * 3600}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_sleep_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _kang(w: World) -> Dictionary:
	return w.objects.filter(func(o): return o.type == "kang")[0]


## Puts `p` to `action` on the kang (or nowhere) for good and lets the house walk them there.
func _to_bed(m: Main, people: Array, action := "sleep", obj := true) -> void:
	var w := m.session.world
	for p in people:
		AutonomySystem.start(w, p, action, int(_kang(w).uid) if obj else -1)
		p.current["remaining_s"] = 99999
	m.house.refresh()
	for i in 900:
		m.house.tick(1.0 / 30.0)
		if i % 60 == 0:
			m.house.refresh()


func _adults(w: World, k: int) -> Array:
	var out: Array = [w.people[0]]
	for i in k - 1:
		var p := FamilySystem.make_person(w, [25, 40])
		w.add_person(p)
		out.append(p)
	for p in w.people:
		if not p in out:
			AutonomySystem.cancel(w, p)
	return out


func test_one_lies_along_the_kang_on_its_surface():
	var m := _main()
	var w := m.session.world
	var p: Person = _adults(w, 1)[0]
	_to_bed(m, [p])
	var pv: PersonView = m.house.people[p.uid]
	assert_true(pv.lying_down(), "lying")
	assert_eq(pv._lie, 1.0, "fully lain down")
	var r := m.house.layout.object_rect(_kang(w), w.pack)
	var g := pv.lie_geo()
	# The kang is 3 x 2 cells: the body runs along its long side (plan x: down-right).
	assert_eq(g.axis, Vector2(1, 0))
	assert_true(g.bed)
	assert_eq(float(g.lift), float(m.house.skin.bed("kang").h), "on the kang's surface")
	var head_end: Vector2 = g.head - g.axis * g.head_len
	var feet: Vector2 = g.head + g.axis * g.length
	for e in [head_end, feet, g.head + g.across * g.width * 0.5, g.head - g.across * g.width * 0.5]:
		assert_true(r.grow(0.5).has_point(e), "%s within the kang %s" % [e, r])
	assert_true(g.length > r.size.x * 0.5, "a body's length, not a stub")
	# Drawn over the kang, the body over its top (not floating above the picture).
	var piece: PropPiece = m.house.props[int(_kang(w).uid)]
	assert_true(pv.get_index() > piece.get_index(), "over the kang")
	var lr := pv.lie_rect()
	var foot := m.house.proj * pv.position
	var pic := Rect2(m.house.proj * piece.position + piece.rect.position, piece.rect.size)
	assert_true(pic.encloses(Rect2(foot + lr.position, lr.size).grow(-4.0)), "within the kang's picture")
	m.free()


func test_sharing_a_kang_they_lie_side_by_side():
	var m := _main()
	var w := m.session.world
	var ps := _adults(w, 3)
	_to_bed(m, ps)
	var r := m.house.layout.object_rect(_kang(w), w.pack)
	var across: Array = []
	var slots := {}
	var xs: Array = []
	for p in ps:
		var pv: PersonView = m.house.people[p.uid]
		assert_true(pv.lying_down(), "lying")
		assert_eq(pv.bed_uid, int(_kang(w).uid))
		assert_eq(pv.bed_n, 3)
		slots[pv.bed_slot] = true
		var g := pv.lie_geo()
		across.append((g.head as Vector2).y)
		xs.append(pv.position.x)
		assert_true(float(g.width) < r.size.y * 0.5, "each in a share of the width")
	assert_eq(slots.size(), 3, "three places")
	across.sort()
	for i in 2:
		assert_true(across[i + 1] - across[i] > r.size.y * 0.2, "apart across the kang: %s" % [across])
	xs.sort()
	for i in 2:
		assert_true(xs[i + 1] - xs[i] >= ClipProbe.NEAR, "got in a step apart: %s" % [xs])
	# A fourth joining moves nobody off the kang: those lying keep their places.
	var before := {}
	for p in ps:
		before[p.uid] = m.house.people[p.uid].bed_slot
	var probe := ClipProbe.new(m.house)
	probe.check()
	assert_eq(int(probe.counts["people_overlap"]) + int(probe.counts["sort_order"]) + int(probe.counts["lie_wall"]), 0, probe.summary())
	var p4 := FamilySystem.make_person(w, [25, 40])
	w.add_person(p4)
	m.tick(0.016)
	AutonomySystem.cancel(w, p4)
	_to_bed(m, [p4])
	for p in ps:
		assert_eq(m.house.people[p.uid].bed_slot, before[p.uid], "kept their place")
		assert_true(m.house.people[p.uid].lying_down())
	m.free()


func test_each_sleeps_with_their_own_head():
	var m := _main()
	var w := m.session.world
	var ps := _adults(w, 2)
	ps[0].gender = "male"
	ps[1].gender = "female"
	m.house.refresh()
	_to_bed(m, ps)
	var heads: Array = []
	for p in ps:
		var pv: PersonView = m.house.people[p.uid]
		var r := pv.sleeping_head_rig()
		assert_true(r != null, "a head to sleep with")
		assert_true(r == pv._look.get("rig_back34", pv._look.get("rig")), "from their own look")
		heads.append(r.part("head").tex)
	assert_true(heads[0] != heads[1], "not one face for everyone")
	m.free()


func test_lying_down_and_getting_up_take_a_moment():
	var m := _main()
	var w := m.session.world
	var p: Person = _adults(w, 1)[0]
	var pv: PersonView = m.house.people[p.uid]
	AutonomySystem.start(w, p, "sleep", int(_kang(w).uid))
	p.current["remaining_s"] = 99999
	m.house.refresh()
	var i := 0
	while not pv.lying_down() and i < 900:
		m.house.tick(1.0 / 30.0)
		i += 1
	assert_true(pv.lying_down(), "got there")
	assert_true(pv._lie < 0.2, "not lying at once")
	for k in 6:
		m.house.tick(1.0 / 30.0)
	assert_true(pv._lie > 0.0 and pv._lie < 1.0, "lying down: %f" % pv._lie)
	for k in 30:
		m.house.tick(1.0 / 30.0)
	assert_eq(pv._lie, 1.0)
	# Getting up: they stay on the kang until they have sat up, then walk off.
	var at := pv.position
	AutonomySystem.cancel(w, p)
	m.house.refresh()
	assert_eq(pv.seat_uid(), int(_kang(w).uid), "still on the kang while getting up")
	for k in 6:
		m.house.tick(1.0 / 30.0)
	assert_true(pv._lie > 0.0, "getting up")
	assert_eq(pv.position, at, "not walking yet")
	for k in 60:
		m.house.tick(1.0 / 30.0)
	assert_eq(pv._lie, 0.0)
	m.free()


func test_dozing_sits_on_the_edge_nodding():
	var m := _main()
	var w := m.session.world
	var p: Person = _adults(w, 1)[0]
	_to_bed(m, [p], "doze_on_kang")
	var pv: PersonView = m.house.people[p.uid]
	assert_eq(pv.body_pose(), "doze")
	assert_true(pv.on_object and not pv.lying_down(), "sitting, not lying")
	assert_true(pv.seat_lift() > 0.0, "on the kang's edge")
	var rig: CutoutRig = pv._rig_for("doze")[0]
	var a: Vector3 = rig.pose("doze", 0.2)["head"]
	var b: Vector3 = rig.pose("doze", CutoutRig.DOZE_PERIOD * 0.8)["head"]
	assert_true(b.x - a.x > 10.0, "the head sinks: %s -> %s" % [a, b])
	m.free()


func test_a_baby_sleeps_on_the_kang_beside_a_parent():
	var m := _main()
	var w := m.session.world
	var mum: Person = _adults(w, 1)[0]
	var baby := FamilySystem.make_person(w, [0.5, 1.0])
	w.add_person(baby)
	m.tick(0.016)
	AutonomySystem.cancel(w, baby)
	_to_bed(m, [mum])
	AutonomySystem.start(w, baby, "baby_sleep", -1)
	baby.current["remaining_s"] = 99999
	baby.current["room"] = str(_kang(w).room)
	_to_bed(m, [])
	var bv: PersonView = m.house.people[baby.uid]
	var mv: PersonView = m.house.people[mum.uid]
	assert_true(bool(bv._look.get("lying", false)), "the swaddle picture")
	assert_true(bv.on_object and bv.bed_uid == int(_kang(w).uid), "on the kang")
	assert_eq(bv.bed_n, 2)
	assert_true(bv.bed_slot != mv.bed_slot, "beside, not on, the parent")
	var r := m.house.layout.object_rect(_kang(w), w.pack)
	assert_true(r.grow(1.0).has_point(bv.lie_geo().head))
	m.free()


func test_no_bed_they_sleep_on_a_mat_inside_the_room():
	var m := _main()
	var w := m.session.world
	var p: Person = _adults(w, 1)[0]
	w.objects.erase(_kang(w))
	m.house.refresh()
	p.current = {"action": "sleep", "object_uid": -1, "target_uid": -1, "remaining_s": 99999, "room": "bedroom"}
	_to_bed(m, [])
	var pv: PersonView = m.house.people[p.uid]
	assert_true(pv.lying_down())
	var g := pv.lie_geo()
	assert_true(not g.bed)
	var room := m.house.layout.room_rect("bedroom")
	assert_true(room.has_point(g.head - g.axis * g.head_len) and room.has_point(g.head + g.axis * g.length), "the mat within the room")
	m.free()
