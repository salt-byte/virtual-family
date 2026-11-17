extends TestCase
func test_mess_penalizes_everyone():
	var w := TestKit.world(); var p := TestKit.adult(w)
	p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 999999}
	var clean := TestKit.world(); var q := TestKit.adult(clean); q.current = p.current.duplicate()
	MessSystem.spawn(w, "trash"); w.advance(3600); clean.advance(3600)
	assert_true(p.needs["happy"] < q.needs["happy"])
func test_drag_to_mess_cleans_it():
	var w := TestKit.world(); var p := TestKit.adult(w); var uid := MessSystem.spawn(w, "trash")
	assert_true(w.command({type = "drag", person = p.uid, mess = uid}).ok)
	w.advance(w.pack.actions["take_out_trash"]["duration_min"] * 60)
	assert_eq(w.messes.size(), 0); assert_eq(w.stats["mess_cleaned"], 1); assert_eq(w.stats["all_clean"], 1)
func test_cannot_clean_without_mess():
	var w := TestKit.world(); var p := TestKit.adult(w)
	assert_eq(AutonomySystem.can_do(w, p, "take_out_trash", -1), "no_target")
func test_two_people_do_not_clean_same_mess():
	var w := TestKit.world(); var a := TestKit.adult(w); var b := TestKit.adult(w); var uid := MessSystem.spawn(w, "trash")
	w.command({type = "drag", person = a.uid, mess = uid})
	var r := w.command({type = "drag", person = b.uid, mess = uid})
	assert_true(not r.ok); assert_eq(r.error, "busy")
func test_people_clean_on_their_own_eventually():
	var w := TestKit.world(); var p := TestKit.adult(w); p.habits["take_out_trash"] = 3.0
	for i in 5: MessSystem.spawn(w, "trash")
	w.offline = true; w.advance(12 * 3600); assert_true(w.stats["mess_cleaned"] >= 1)
func test_drag_unknown_mess_is_no_target():
	var w := TestKit.world(); var p := TestKit.adult(w)
	assert_eq(w.command({type = "drag", person = p.uid, mess = 99}).error, "no_target")
func test_spawn_lands_in_matching_room_inside_bounds():
	var w := TestKit.world(); var uid := MessSystem.spawn(w, "trash")
	assert_true(uid >= 0)
	var m: Dictionary = w.messes[0]
	assert_eq(m.uid, uid); assert_eq(m.type, "trash")
	var room: Dictionary = w.pack.rooms[m.room]
	assert_true(not room["outdoor"] and w.rooms_built.has(m.room))
	assert_true(m.x >= 0 and m.x < room["w"] and m.y >= 0 and m.y < room["h"])
	assert_eq(MessSystem.spawn(w, "nope"), -1)
func test_clean_unknown_uid_does_nothing():
	var w := TestKit.world(); MessSystem.spawn(w, "trash")
	MessSystem.clean(w, 999)
	assert_eq(w.messes.size(), 1); assert_eq(w.stats["mess_cleaned"], 0)
func test_all_clean_only_when_house_empty():
	var w := TestKit.world(); var a := MessSystem.spawn(w, "trash"); var b := MessSystem.spawn(w, "trash")
	MessSystem.clean(w, a); assert_eq(w.stats["all_clean"], 0)
	MessSystem.clean(w, b); assert_eq(w.stats["all_clean"], 1); assert_eq(w.stats["mess_cleaned"], 2)
func test_mess_spawns_over_time():
	var w := TestKit.world("_smoke", 2); TestKit.adult(w).lifespan = 1e9
	w.offline = true; w.advance(10 * 86400)
	assert_true(w.drain_events().any(func(e): return e.type == "mess_spawned" and e.has("uid")))
func test_action_mess_spawns_in_object_room():
	var w := TestKit.world(); w.add_object("tv", "main", 0, 0); var p := TestKit.adult(w)
	w.pack.actions["watch_tv"]["mess"] = {"type": "trash", "chance": 1.0}
	w.command({type = "drag", person = p.uid, object = w.objects[0].uid})
	w.advance(60 * 60)
	assert_true(w.messes.size() >= 1); assert_eq(w.messes[0].room, "main")
func _bin_action(w: World) -> void:
	w.pack.actions["take_out_trash"]["object"] = "bed"
func test_mess_drag_occupies_object_of_cleaning_action():
	var w := TestKit.world(); _bin_action(w)
	var bed := w.add_object("bed", "main", 0, 0); var a := TestKit.adult(w); var b := TestKit.adult(w)
	var uid := MessSystem.spawn(w, "trash")
	assert_true(w.command({type = "drag", person = a.uid, mess = uid}).ok)
	assert_eq(a.current["object_uid"], bed)
	MessSystem.spawn(w, "trash")
	assert_eq(AutonomySystem.can_do(w, b, "take_out_trash", -1), "busy")
	w.advance(w.pack.actions["take_out_trash"]["duration_min"] * 60)
	assert_eq(w.stats["mess_cleaned"], 1)
func test_object_drag_of_cleaning_action_resolves_target():
	var w := TestKit.world(); _bin_action(w)
	var bed := w.add_object("bed", "main", 0, 0); var p := TestKit.adult(w)
	MessSystem.spawn(w, "trash")
	assert_true(w.command({type = "drag", person = p.uid, object = bed, action = "take_out_trash"}).ok)
	assert_true(p.current["target_uid"] >= 0)
	w.advance(w.pack.actions["take_out_trash"]["duration_min"] * 60)
	assert_eq(w.messes.size(), 0); assert_eq(w.stats["mess_cleaned"], 1)
func test_object_drag_of_cleaning_action_without_mess_is_rejected():
	var w := TestKit.world(); _bin_action(w)
	var bed := w.add_object("bed", "main", 0, 0); var p := TestKit.adult(w)
	assert_eq(w.command({type = "drag", person = p.uid, object = bed, action = "take_out_trash"}).error, "no_target")
func test_spawn_without_matching_room_returns_minus_one():
	var w := TestKit.world(); w.rooms_built.clear()
	assert_eq(MessSystem.spawn(w, "trash"), -1); assert_eq(w.messes.size(), 0)
	w.rooms_built.append("yard")  # outdoor only: trash is indoor
	assert_eq(MessSystem.spawn(w, "trash"), -1)
func test_candidates_target_skips_claimed_mess_and_own_claim_does_not_block():
	var w := TestKit.world(); var a := TestKit.adult(w); var b := TestKit.adult(w)
	var m1 := MessSystem.spawn(w, "trash"); var m2 := MessSystem.spawn(w, "trash")
	w.command({type = "drag", person = a.uid, mess = m1})
	var c := AutonomySystem.candidates(w, b).filter(func(x): return x.action == "take_out_trash")
	assert_eq(c.size(), 1); assert_eq(c[0].target_uid, m2)
	var own := AutonomySystem.candidates(w, a).filter(func(x): return x.action == "take_out_trash")
	assert_eq(own[0].target_uid, m1)
	assert_true(w.command({type = "drag", person = a.uid, mess = m1}).ok)
func test_claim_requires_cleaning_action():
	var w := TestKit.world(); var a := TestKit.adult(w); var b := TestKit.adult(w)
	var m := MessSystem.spawn(w, "trash")
	a.current = {action = "stare_window", object_uid = -1, target_uid = m, remaining_s = 600}
	assert_true(w.command({type = "drag", person = b.uid, mess = m}).ok)
func test_offline_floor_holds_under_mess_penalty():
	var w := TestKit.world(); var p := TestKit.adult(w); w.offline = true
	p.current = {action = "stare_window", object_uid = -1, target_uid = -1, remaining_s = 99999999}
	p.needs["happy"] = 0.0; MessSystem.spawn(w, "trash"); w.advance(600)
	assert_true(p.needs["happy"] >= float(w.pack.cfg("offline_need_floor")))
func test_uids_are_unique_across_kinds():
	var w := TestKit.world(); var p := TestKit.adult(w); var o := w.add_object("bed", "main", 0, 0)
	var m := MessSystem.spawn(w, "trash")
	assert_true(p.uid != o and o != m and p.uid != m)
