extends TestCase
## The event and command-result contract the view layer reads: `person` always names a
## person, `uid` only ever the mess or collectible an event is about.

func _of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)

func test_action_events_carry_person_action_object_target():
	var w := TestKit.world(); var tv := w.add_object("tv", "main", 0, 0); var p := TestKit.adult(w)
	w.command({type = "drag", person = p.uid, object = tv})
	var s: Array = _of(w.drain_events(), "action_started")
	assert_eq(s.size(), 1)
	assert_eq(s[0].person, p.uid); assert_eq(s[0].action, "watch_tv"); assert_eq(s[0].object, tv); assert_eq(s[0].target, -1)
	assert_true(not s[0].has("uid"))
	w.advance(int(w.pack.actions["watch_tv"]["duration_min"]) * 60)
	var f: Array = _of(w.drain_events(), "action_finished")
	assert_eq(f.size(), 1); assert_eq(f[0].person, p.uid); assert_eq(f[0].action, "watch_tv"); assert_true(not f[0].has("uid"))

func test_action_started_names_mess_target_and_no_object():
	var w := TestKit.world(); var p := TestKit.adult(w); var m := MessSystem.spawn(w, "trash"); w.drain_events()
	w.command({type = "drag", person = p.uid, mess = m})
	var s: Array = _of(w.drain_events(), "action_started")
	assert_eq(s[0].person, p.uid); assert_eq(s[0].object, -1); assert_eq(s[0].target, m)

func test_action_cancelled_carries_person():
	var w := TestKit.world(); var p := TestKit.adult(w); AutonomySystem.start(w, p, "stare_window", -1); w.drain_events()
	AutonomySystem.cancel(w, p)
	var c: Array = _of(w.drain_events(), "action_cancelled")
	assert_eq(c.size(), 1); assert_eq(c[0].person, p.uid); assert_eq(c[0].action, "stare_window"); assert_true(not c[0].has("uid"))

func test_kill_person_cancels_current_action_before_death():
	var w := TestKit.world(); var p := TestKit.adult(w); TestKit.adult(w)
	AutonomySystem.start(w, p, "stare_window", -1); w.drain_events()
	w.kill_person(p, "x")
	var ev := w.drain_events()
	assert_eq(ev.map(func(e): return e.type), ["action_cancelled", "person_died"])
	assert_eq(ev[0].person, p.uid); assert_eq(ev[1].person, p.uid); assert_true(not ev[1].has("uid"))
	assert_true(p.current.is_empty())

func test_income_and_level_up_use_person_and_nonperson_income_has_none():
	var w := TestKit.world(); w.add_object("desk", "main", 0, 0); var p := TestKit.adult(w)
	p.track = "office"; p.aptitude = 1.0
	EconomySystem.on_work_finished(w, p, int(w.pack.livelihoods["office"]["levels"][0]["progress_to_next"]))
	var ev := w.drain_events()
	var inc: Array = _of(ev, "income")
	assert_eq(inc[0].person, p.uid); assert_true(not inc[0].has("uid"))
	var lv: Array = _of(ev, "level_up")
	assert_eq(lv[0].person, p.uid); assert_true(not lv[0].has("uid"))
	EconomySystem.earn(w, 5, "goal")
	var g: Array = _of(w.drain_events(), "income")
	assert_true(not g[0].has("person")); assert_true(not g[0].has("uid"))

func test_salary_income_names_person():
	var w := TestKit.world(); var p := TestKit.adult(w); p.track = "office"
	p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 999999}
	w.advance(3600)
	var inc: Array = _of(w.drain_events(), "income")
	assert_true(inc.size() >= 1); assert_eq(inc[0].person, p.uid); assert_eq(inc[0].source, "salary")

func test_adopt_and_accept_results_name_the_new_person():
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 5); w.set_time(1767268800, 0)
	var r := w.command({type = "adopt"})
	assert_eq(r.person, w.people[0].uid)
	w.offline = true; w.advance(3600 + 60)
	var a := w.command({type = "answer_proposal", id = w.proposals[0].id, accept = true})
	assert_eq(a.person, w.people[1].uid)

func test_catch_up_summary_reports_game_over():
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 11); w.set_time(1767268800, 0)
	w.command({type = "adopt"})
	assert_eq(w.catch_up(600).game_over, false)
	w.people[0].age = 69.99; w.people[0].lifespan = 70.0
	var s := w.catch_up(3600)
	assert_eq(s.game_over, true); assert_eq(s.deaths[0].person, w.people[0].uid)
	assert_eq(w.catch_up(3600).game_over, false)  # already over before this replay

func test_requeue_events_puts_them_first():
	var w := TestKit.world(); w.emit("a"); var held := w.drain_events(); w.emit("b")
	w.requeue_events(held)
	assert_eq(w.drain_events().map(func(e): return e.type), ["a", "b"])

func test_spawn_and_collect_events_name_the_kind():
	var w := TestKit.world()
	var p := TestKit.adult(w)
	var m := MessSystem.spawn(w, w.pack.mess_types.keys()[0])
	var c := CollectibleSystem.spawn(w, w.pack.collectibles.keys()[0])
	CollectibleSystem.collect(w, p, c)
	var by := {}
	for e in w.drain_events():
		by[e.type] = e
	assert_eq(by["mess_spawned"].kind, w.pack.mess_types.keys()[0])
	assert_eq(by["collectible_spawned"].kind, w.pack.collectibles.keys()[0])
	assert_eq(by["collected"].kind, w.pack.collectibles.keys()[0])
	assert_eq(by["collected"].person, p.uid)
	assert_true(m > 0)
