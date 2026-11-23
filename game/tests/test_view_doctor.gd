extends TestCase
## Having the sick seen to, in the view: "请郎中" on the sick one's notice and in the tray,
## the doctor walking in at the gate to the bedside and saying what it is, the tray marking
## the medicine that fits, and dropping the family's own healer on the patient.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_view_doctor_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _later(m: Main, seconds: float) -> void:
	clk.unix += seconds
	m.tick(0.016)


func test_doctor_called_from_the_notice_walks_in_and_names_the_illness():
	var m := _main()
	var w := m.session.world
	var p := w.people[0]
	w.money = 500
	IllnessSystem.infect(w, p, "chill")
	m.tick(0.016)
	assert_true(m.hud.seen_sick(p.uid), "seen sick")
	var chip := m.hud.doctor_chip(p.uid)
	assert_true(chip != null, "the sick one's notice has a doctor button")
	assert_eq(chip.text, "请老郎中")
	chip.pressed.emit()
	assert_eq(int(w.doctor.get("person", -1)), p.uid)
	assert_eq(w.money, 450)
	m.tick(0.016)
	assert_true(m.hud.doctor_chip(p.uid) == null, "no second call while one is on the way")
	assert_true(m.hud.notices().any(func(x): return str(x.text).contains("老郎中在路上")), str(m.hud.notices()))
	assert_true(m.house.visitor == null, "not at the gate yet")
	_later(m, 20.0)
	var v := m.house.visitor
	assert_true(v != null, "the doctor turns up at the gate")
	assert_true(v.position.distance_to(m.house._gate_pos(w, str(w.doctor.service))) < 40.0, "at the gate %s" % v.position.distance_to(m.house._gate_pos(w, str(w.doctor.service))))
	assert_true(v.pictured(), "drawn with the pack's art")
	_later(m, 12.0)
	assert_eq(str(w.doctor.get("phase", "")), "examining")
	for i in 400:
		m.house.tick(0.05)
		if v.arrived():
			break
	assert_true(v.arrived(), "reached the bedside")
	var bed: Vector2 = m.house.people[p.uid].position
	assert_true(v.position.distance_to(bed) < HouseSite.CELL.x * 2.5, "beside the patient")
	assert_eq(v.busy_text, "搭脉瞧病")
	_later(m, 12.0)
	assert_eq(p.illness, "", "cured")
	assert_true(v.say.contains("风寒"), v.say)
	assert_true(m.hud.toasts().any(func(t): return str(t).contains("风寒")), str(m.hud.toasts()))
	assert_true(v.leaving, "and off he goes")
	m.free()


func test_tray_offers_the_doctor_and_marks_the_fitting_medicine():
	var m := _main()
	var w := m.session.world
	var p := w.people[0]
	w.money = 500
	w.inventory["ginger_pill"] = 1
	w.inventory["indigo_salve"] = 1
	IllnessSystem.infect(w, p, "chill")
	m.select(p.uid)
	m.tick(0.016)
	var texts := m.hud.tray().texts()
	assert_true(texts.any(func(t): return t.begins_with("老姜红枣丸") and t.contains("对症") and not t.contains("不对症")), str(texts))
	assert_true(texts.any(func(t): return t.begins_with("青黛药膏") and t.contains("不对症")), str(texts))
	assert_true(texts.has("请老郎中 · 50 文"), str(texts))
	assert_true(m.hud.tray().press("doctor"))
	assert_eq(int(w.doctor.get("person", -1)), p.uid)
	m.free()


func test_dropping_the_family_healer_on_the_patient_treats_them():
	var m := _main()
	var w := m.session.world
	var p := w.people[0]
	var h := TestKit.adult(w, 40.0)
	h.track = "medicine"
	w.stock["herbs"] = 1
	m.tick(0.016)
	IllnessSystem.infect(w, p, "chill")
	AutonomySystem.cancel(w, h)
	m.tick(0.016)
	var at: Vector2 = m.house.people[p.uid].position + Vector2(0, -6)
	m.drag.begin(h.uid)
	m.drag.move(at)
	var r := m.drag.drop(at)
	assert_true(r.get("ok", false), str(r))
	assert_eq(str(h.current.get("action", "")), "treat_family")
	assert_eq(int(h.current.get("target_uid", -1)), p.uid)
	m.free()
