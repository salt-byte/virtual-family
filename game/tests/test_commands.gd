extends TestCase
func _w() -> World:
	var w := TestKit.world(); w.add_object("tv", "main", 0, 0); w.add_object("desk", "main", 3, 0); return w
func test_drag_starts_action_and_cancels_previous():
	var w := _w(); var p := TestKit.adult(w); AutonomySystem.start(w, p, "stare_window", -1)
	var r := w.command({type = "drag", person = p.uid, object = w.objects[0].uid})
	assert_true(r.ok); assert_eq(p.current.action, "watch_tv")
func test_drag_to_busy_object_rejected_state_unchanged():
	var w := _w(); var a := TestKit.adult(w); var b := TestKit.adult(w)
	w.command({type = "drag", person = a.uid, object = w.objects[0].uid})
	var before := b.to_dict()
	var r := w.command({type = "drag", person = b.uid, object = w.objects[0].uid})
	assert_true(not r.ok); assert_eq(r.error, "busy"); assert_eq(b.to_dict(), before)
func test_drag_child_to_work_rejected():
	var w := _w(); var c := TestKit.adult(w, 6.0)
	assert_eq(w.command({type = "drag", person = c.uid, object = w.objects[1].uid}).error, "stage")
func test_drag_dead_person_rejected():
	var w := _w(); var p := TestKit.adult(w); p.alive = false
	assert_eq(w.command({type = "drag", person = p.uid, object = w.objects[0].uid}).error, "dead")
func test_praise_and_scold_adjust_habit_with_clamp():
	var w := _w(); var p := TestKit.adult(w)
	w.command({type = "drag", person = p.uid, object = w.objects[0].uid})
	w.command({type = "praise", person = p.uid}); assert_near(p.habits["watch_tv"], 1.25)
	p.habits["watch_tv"] = 2.9; p.praise_times.clear(); w.command({type = "praise", person = p.uid})
	assert_near(p.habits["watch_tv"], 3.0)
	for i in 40: w.command({type = "scold", person = p.uid})
	assert_near(p.habits["watch_tv"], 0.25)
func test_fourth_praise_in_window_annoys_then_recovers():
	var w := _w(); var p := TestKit.adult(w); p.needs["happy"] = 50.0
	p.current = {action = "watch_tv", object_uid = w.objects[0].uid, target_uid = -1, remaining_s = 999999}
	for i in 3: assert_true(w.command({type = "praise", person = p.uid}).ok)
	var h: float = p.habits["watch_tv"]
	assert_eq(w.command({type = "praise", person = p.uid}).error, "annoyed"); assert_near(p.habits["watch_tv"], h)
	assert_near(p.needs["happy"], 50.0 + 3 * float(w.pack.cfg("praise_gain")), 0.01)
	w.advance(11 * 60); assert_true(w.command({type = "praise", person = p.uid}).ok)
func test_praise_with_nothing_recent():
	var w := _w(); var p := TestKit.adult(w)
	assert_eq(w.command({type = "praise", person = p.uid}).error, "nothing_to_judge")
func test_unknown_command():
	assert_eq(_w().command({type = "fly"}).error, "unknown_command")
func test_drag_without_action_picks_first_doable():
	var w := _w(); var p := TestKit.adult(w)
	var r := w.command({type = "drag", person = p.uid, object = w.objects[0].uid})
	assert_true(r.ok); assert_eq(p.current.action, "watch_tv")
func test_drag_no_doable_action_returns_first_reason():
	var w := _w(); var p := TestKit.adult(w)  # track "" so the desk is wrong_track
	assert_eq(w.command({type = "drag", person = p.uid, object = w.objects[1].uid}).error, "wrong_track")
func test_drag_unknown_person_and_object():
	var w := _w(); var p := TestKit.adult(w)
	assert_eq(w.command({type = "drag", person = 99, object = w.objects[0].uid}).error, "no_person")
	assert_eq(w.command({type = "drag", person = p.uid, object = 99}).error, "no_object")
func test_drag_onto_own_object_restarts():
	var w := _w(); var p := TestKit.adult(w); var tv: int = w.objects[0].uid
	w.command({type = "drag", person = p.uid, object = tv}); w.advance(600)
	var left: int = p.current.remaining_s
	assert_true(w.command({type = "drag", person = p.uid, object = tv}).ok)
	assert_true(int(p.current.remaining_s) > left)
func test_praise_uses_recent_last_action_only_within_60s():
	var w := _w(); var p := TestKit.adult(w)
	p.last_action = "watch_tv"; p.last_action_t = w.now - 60
	assert_true(w.command({type = "praise", person = p.uid}).ok)
	p.praise_times.clear(); p.last_action_t = w.now - 61
	assert_eq(w.command({type = "praise", person = p.uid}).error, "nothing_to_judge")
func test_not_praiseable_action():
	var w := _w(); var p := TestKit.adult(w)
	p.current = {action = "cough", object_uid = -1, target_uid = -1, remaining_s = 999}
	assert_eq(w.command({type = "praise", person = p.uid}).error, "not_praiseable")
	assert_eq(w.command({type = "scold", person = p.uid}).error, "not_praiseable")
func test_scold_never_counts_as_praise_and_not_annoyed():
	var w := _w(); var p := TestKit.adult(w)
	p.current = {action = "watch_tv", object_uid = w.objects[0].uid, target_uid = -1, remaining_s = 999999}
	for i in 5: assert_true(w.command({type = "scold", person = p.uid}).ok)
	assert_eq(p.praise_times.size(), 0)
func test_praise_need_decays_extra():
	var w := _w(); var p := TestKit.adult(w); p.needs["happy"] = 50.0
	p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 999999}
	w.advance(3600)
	var expect := 50.0 - float(w.pack.needs["happy"]["drain_per_hour"]) - float(w.pack.cfg("praise_decay_per_hour"))
	assert_near(p.needs["happy"], expect, 0.01)
func test_dead_or_over_world_rejects_commands():
	var w := _w(); var p := TestKit.adult(w); w.phase = "over"
	assert_eq(w.command({type = "praise", person = p.uid}).error, "not_running")
