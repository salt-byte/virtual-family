extends TestCase
func test_illness_drains_health():
	var w := TestKit.world(); var p := TestKit.adult(w); var h: float = p.needs["health"]
	IllnessSystem.infect(w, p, "cold"); w.advance(3600)
	assert_true(p.needs["health"] < h - 0.5 * absf(w.pack.illnesses["cold"]["drain"]["health"]))
func test_right_medicine_cures():
	var w := TestKit.world(); var p := TestKit.adult(w); w.money = 100
	IllnessSystem.infect(w, p, "cold"); w.command({type = "buy", item = "cold_pill", qty = 1})
	assert_true(w.command({type = "use_item", item = "cold_pill", person = p.uid}).ok)
	assert_eq(p.illness, ""); assert_eq(w.stats["cured"], 1)
func test_medicine_on_healthy_person_is_wrong_and_consumed():
	var w := TestKit.world(); var p := TestKit.adult(w); w.money = 100
	w.command({type = "buy", item = "cold_pill", qty = 1})
	var r := w.command({type = "use_item", item = "cold_pill", person = p.uid})
	assert_eq(r.error, "wrong_medicine"); assert_true(not r.ok)
	assert_eq(w.inventory.get("cold_pill", 0), 0)
func test_illness_arrives_eventually_and_deterministically():
	var a := TestKit.world("_smoke", 3); var pa := TestKit.adult(a)
	var b := TestKit.world("_smoke", 3); var pb := TestKit.adult(b)
	a.offline = true; b.offline = true; a.advance(30 * 86400 / 12); b.advance(30 * 86400 / 12)
	assert_eq(pa.illness, pb.illness)
func test_illness_does_strike_over_many_days():
	var w := TestKit.world("_smoke", 5); var p := TestKit.adult(w); p.lifespan = 1e9
	w.offline = true; w.advance(60 * 86400)
	assert_true(w.drain_events().any(func(e): return e.type == "fell_ill"))
func test_symptom_action_only_for_that_illness_and_shows_on_drop():
	var w := TestKit.world(); w.add_object("tv", "main", 0, 0); var a := TestKit.adult(w); var b := TestKit.adult(w)
	var sym: String = w.pack.illnesses["cold"]["symptom_action"]
	assert_eq(AutonomySystem.can_do(w, a, sym, -1), "requires"); IllnessSystem.infect(w, a, "cold")
	w.command({type = "drag", person = b.uid, object = w.objects[0].uid})      # tv occupied by b
	w.command({type = "drag", person = a.uid, object = w.objects[0].uid})      # a fails, then shows symptom on drop
	assert_eq(a.current.get("action"), sym)
func test_fell_ill_event_does_not_name_illness_to_ui():
	var w := TestKit.world(); var p := TestKit.adult(w); IllnessSystem.infect(w, p, "cold")
	var seen := 0
	for e in w.drain_events():
		if e.type == "fell_ill":
			seen += 1; assert_true(not e.has("illness")); assert_eq(e.person, p.uid)
	assert_eq(seen, 1)
func test_sick_person_does_sick_action():
	var w := TestKit.world(); w.add_object("bed", "main", 0, 0); var p := TestKit.adult(w)
	assert_eq(AutonomySystem.can_do(w, p, "nap_sick", w.objects[0].uid), "requires")
	IllnessSystem.infect(w, p, "cold"); assert_eq(AutonomySystem.can_do(w, p, "nap_sick", w.objects[0].uid), "")
func test_wrong_illness_medicine_is_consumed_and_keeps_illness():
	var w := TestKit.world(); var p := TestKit.adult(w); w.inventory["cake"] = 1
	var q := TestKit.adult(w); w.inventory["cold_pill"] = 1
	var r := w.command({type = "use_item", item = "cold_pill", person = q.uid})
	assert_eq(r.error, "wrong_medicine"); assert_eq(w.stats["cured"], 0)
func test_infect_sick_person_does_nothing_and_cure_emits():
	var w := TestKit.world(); var p := TestKit.adult(w)
	IllnessSystem.infect(w, p, "cold"); IllnessSystem.infect(w, p, "cold")
	assert_eq(w.drain_events().filter(func(e): return e.type == "fell_ill").size(), 1)
	IllnessSystem.cure(w, p)
	var ev := w.drain_events().filter(func(e): return e.type == "cured")
	assert_eq(ev.size(), 1); assert_eq(ev[0].person, p.uid)
func test_offline_illness_never_drains_below_floor():
	var w := TestKit.world(); var p := TestKit.adult(w); w.offline = true
	IllnessSystem.infect(w, p, "cold"); w.advance(86400 * 3)
	assert_true(p.alive)
	assert_true(p.needs["health"] >= float(w.pack.cfg("offline_need_floor")))
func test_dead_person_not_infected_by_chance_or_drained():
	var w := TestKit.world(); var p := TestKit.adult(w); w.kill_person(p, "x")
	w.advance(86400); assert_eq(p.illness, "")
func test_cure_cancels_sick_only_action():
	var w := TestKit.world(); var bed := w.add_object("bed", "main", 0, 0); var p := TestKit.adult(w)
	IllnessSystem.infect(w, p, "cold"); AutonomySystem.start(w, p, "nap_sick", bed); w.drain_events()
	IllnessSystem.cure(w, p)
	assert_true(p.current.is_empty())
	assert_true(w.drain_events().any(func(e): return e.type == "action_cancelled" and e.action == "nap_sick"))
	IllnessSystem.infect(w, p, "cold"); AutonomySystem.start(w, p, "cough", -1)
	IllnessSystem.cure(w, p); assert_true(p.current.is_empty())
func test_cure_keeps_ordinary_action():
	var w := TestKit.world(); var p := TestKit.adult(w)
	IllnessSystem.infect(w, p, "cold"); AutonomySystem.start(w, p, "stare_window", -1)
	IllnessSystem.cure(w, p)
	assert_eq(p.current.get("action"), "stare_window")
