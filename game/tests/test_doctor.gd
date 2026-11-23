extends TestCase
## Having the sick seen to: the doctor service (comes to the house, names the illness, cures
## it, is paid, costs more at night, never visits while the player is away), a family member
## who knows medicine treating the family, and which medicine fits.

const SID := "call_langzhong"


func _sick_world() -> Array:
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	w.money = 500
	IllnessSystem.infect(w, p, "chill")
	w.drain_events()
	return [w, p]


func _types(w: World) -> Array:
	return w.drain_events().map(func(e): return str(e.type))


func test_doctor_arrives_diagnoses_cures_and_is_paid():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var sv: Dictionary = w.pack.services[SID]
	assert_eq(ServiceSystem.price(w, SID), int(sv["price"]), "day price at noon")
	var res := w.command({"type": "buy_service", "service": SID, "person": p.uid})
	assert_true(res.ok, str(res))
	assert_eq(w.money, 500 - int(sv["price"]))
	assert_eq(str(w.doctor.phase), "coming")
	assert_true(_types(w).has("doctor_called"))
	w.advance(int(sv["arrive_seconds"]))
	assert_eq(str(w.doctor.get("phase", "")), "examining", "the doctor came within arrive_seconds")
	assert_true(_types(w).has("doctor_arrived"))
	assert_eq(p.illness, "chill", "still ill while examined")
	w.advance(int(sv["exam_seconds"]))
	var said := w.drain_events().filter(func(e): return e.type == "doctor_diagnosed")
	assert_eq(said.size(), 1)
	assert_eq(str(said[0].line), IllnessSystem.diagnosis(w.pack, "chill"))
	assert_true(str(said[0].line).contains("风寒"), "names the illness")
	assert_eq(p.illness, "", "cured")
	assert_true(w.doctor.is_empty(), "left")
	assert_eq(int(w.stats["cured"]), 1)


func test_every_illness_has_a_diagnosis_line():
	var w := TestKit.world("qijia")
	for id in w.pack.illnesses:
		assert_true(IllnessSystem.diagnosis(w.pack, str(id)) != "", "%s has a line" % id)


func test_night_call_costs_more():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var sv: Dictionary = w.pack.services[SID]
	w.set_time(1767268800 + 10 * 3600, 0)  # 22:00
	assert_eq(ServiceSystem.price(w, SID), int(sv["night_price"]))
	assert_true(int(sv["night_price"]) > int(sv["price"]))
	assert_true(w.command({"type": "buy_service", "service": SID, "person": p.uid}).ok)
	assert_eq(w.money, 500 - int(sv["night_price"]))
	var cat := MarketSystem.catalogue(w)
	var price := -1
	for sec in cat:
		for e in sec.entries:
			if e.kind == "service" and e.id == SID:
				price = int(e.price)
	assert_eq(price, int(sv["night_price"]), "the market shows the night price")


func test_doctor_needs_someone_ill_and_one_visit_at_a_time():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	w.money = 500
	assert_eq(w.command({"type": "buy_service", "service": SID}).error, "nobody_ill")
	assert_eq(w.money, 500)
	IllnessSystem.infect(w, p, "itch")
	assert_true(w.command({"type": "buy_service", "service": SID}).ok, "without a person: whoever is ill")
	assert_eq(int(w.doctor.person), p.uid)
	assert_eq(w.command({"type": "buy_service", "service": SID, "person": p.uid}).error, "doctor_coming")
	w.money = 0
	w.doctor = {}
	assert_eq(w.command({"type": "buy_service", "service": SID, "person": p.uid}).error, "no_money")


func test_no_doctor_visits_while_away():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var twin: World = _sick_world()[0]  # the same house, nobody called
	assert_true(w.command({"type": "buy_service", "service": SID, "person": p.uid}).ok)
	w.sync(w.now + 3600, 0)  # the player went away before the doctor came
	twin.sync(twin.now + 3600, 0)
	assert_true(w.doctor.is_empty())
	assert_eq(w.money, twin.money, "the fee came back")
	assert_eq(p.illness, "chill", "nobody came, so nobody cured")


func test_visit_is_called_off_when_replaying_an_absence():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	assert_true(w.command({"type": "buy_service", "service": SID, "person": p.uid}).ok)
	var paid := w.money
	w.drain_events()
	w.offline = true
	w.advance(w.step_s)
	var off := w.drain_events().filter(func(e): return e.type == "doctor_cancelled")
	assert_eq(off.size(), 1)
	assert_eq(int(off[0].refund), int(w.pack.services[SID]["price"]))
	assert_eq(w.money, paid + int(w.pack.services[SID]["price"]))


func test_doctor_visit_survives_a_save():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	assert_true(w.command({"type": "buy_service", "service": SID, "person": p.uid}).ok)
	var d := w.to_dict()
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(back != null)
	assert_eq(str(back.doctor.service), SID)
	assert_eq(int(back.doctor.person), p.uid)
	assert_eq(int(back.doctor.at), int(w.doctor.at))
	var plain := w.to_dict()
	plain["market"].erase("doctor")  # a save from before doctors came
	assert_true(World.from_dict(w.pack, JSON.parse_string(JSON.stringify(plain))) != null)


func test_patient_cured_meanwhile_hears_the_well_line():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var sv: Dictionary = w.pack.services[SID]
	assert_true(w.command({"type": "buy_service", "service": SID, "person": p.uid}).ok)
	IllnessSystem.cure(w, p)
	w.drain_events()
	w.advance(int(sv["arrive_seconds"]) + int(sv["exam_seconds"]))
	var said := w.drain_events().filter(func(e): return e.type == "doctor_diagnosed")
	assert_eq(said.size(), 1)
	assert_eq(str(said[0].line), str(sv["well_line"]))


func _healer(w: World) -> Person:
	var h := TestKit.adult(w, 40.0)
	h.track = "medicine"
	return h


func test_family_healer_treats_a_sick_member_with_herbs():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var h := _healer(w)
	assert_eq(w.command({"type": "drag", "person": h.uid, "treat": p.uid}).error, "no_stock", "needs herbs")
	w.stock["herbs"] = 1
	var res := w.command({"type": "drag", "person": h.uid, "treat": p.uid})
	assert_true(res.ok, str(res))
	assert_eq(str(res.action), "treat_family")
	assert_eq(int(h.current.target_uid), p.uid)
	assert_eq(int(w.stock["herbs"]), 0, "the herbs are used")
	var before := h.progress
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["treat_family"]))
	assert_eq(p.illness, "", "cured by the family's own healer")
	var ev := w.drain_events()
	assert_true(ev.any(func(e): return e.type == "diagnosed" and int(e.by) == h.uid and str(e.line).contains("风寒")))
	assert_true(h.progress > before or h.level > 0, "it counts as their work")
	assert_true(not ev.any(func(e): return e.type == "doctor_called"), "free: no doctor paid")
	assert_true(int(w.money) >= 500, "free")


func test_family_healer_refuses_the_healthy_and_others_cannot_treat():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	var h := _healer(w)
	w.stock["herbs"] = 3
	assert_eq(w.command({"type": "drag", "person": h.uid, "treat": p.uid}).error, "not_ill")
	IllnessSystem.infect(w, p, "chill")
	var other := TestKit.adult(w)
	assert_eq(w.command({"type": "drag", "person": other.uid, "treat": p.uid}).error, "wrong_track")


func test_family_healer_treats_of_their_own_accord():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var h := _healer(w)
	w.stock["herbs"] = 2
	var started := false
	# Within a few hours of play (they may first be out at the temple fair).
	for i in 240:
		w.advance(w.step_s)
		if not h.current.is_empty() and str(h.current.action) == "treat_family":
			started = true
			assert_eq(int(h.current.target_uid), p.uid)
			break
	assert_true(started, "the healer went to the sick one by themselves")


func test_herbs_come_from_the_hill_and_the_shop():
	var w := TestKit.world("qijia")
	assert_eq(int(w.pack.actions["gather_hill_herbs"]["yields"]["herbs"]), 1)
	w.money = 100
	assert_true(w.command({"type": "buy", "item": "herb_bundle"}).ok)
	assert_eq(int(w.stock["herbs"]), 3)


func test_remedies_name_the_fitting_medicine():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	assert_eq(IllnessSystem.remedies(w, p), [] as Array[String], "the healthy need none")
	IllnessSystem.infect(w, p, "chill")
	assert_eq(IllnessSystem.remedies(w, p), ["ginger_pill"] as Array[String])
	IllnessSystem.cure(w, p)
	IllnessSystem.infect(w, p, "itch")
	assert_eq(IllnessSystem.remedies(w, p), ["indigo_salve"] as Array[String])


func test_tray_marks_the_fitting_medicine_and_offers_the_doctor():
	var r := _sick_world()
	var w: World = r[0]
	var p: Person = r[1]
	var s := ViewStrings.new(w.pack)
	w.inventory["ginger_pill"] = 1
	w.inventory["indigo_salve"] = 1
	var opts := CareTray.options(w, p, null, s, true)
	var fits := {}
	for e in opts:
		if e.kind == "use" and e.has("fits"):
			fits[str(e.item)] = bool(e.fits)
	assert_eq(fits, {"ginger_pill": true, "indigo_salve": false})
	var doc := opts.filter(func(e): return e.kind == "doctor")
	assert_eq(doc.size(), 1)
	assert_true(str(doc[0].text).contains("50"), str(doc[0].text))
	assert_true(CareTray.options(w, p, null, s, false).all(func(e): return e.kind != "doctor"),
		"only for someone seen to be ill")
	w.command({"type": "buy_service", "service": SID, "person": p.uid})
	var wait := CareTray.options(w, p, null, s, true).filter(func(e): return e.kind == "doctor_wait")
	assert_eq(wait.size(), 1)
