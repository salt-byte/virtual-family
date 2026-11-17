extends TestCase
func _w() -> World:
	var w := TestKit.world(); w.money = 1000; return w
func test_place_charges_and_returns_uid():
	var w := _w(); var r := w.command({type = "place", object_type = "tv", room = "main", x = 0, y = 0})
	assert_true(r.ok); assert_eq(w.money, 1000 - int(w.pack.object_types["tv"]["price"])); assert_true(w.object(r.uid) != {})
func test_overlap_and_bounds_rejected_no_charge():
	var w := _w(); w.command({type = "place", object_type = "tv", room = "main", x = 0, y = 0}); var m := w.money
	assert_eq(w.command({type = "place", object_type = "bed", room = "main", x = 0, y = 0}).error, "overlap")
	assert_eq(w.command({type = "place", object_type = "bed", room = "main", x = 7, y = 5}).error, "out_of_bounds")
	assert_eq(w.money, m)
func test_unbuilt_room_then_build():
	var w := _w()
	assert_eq(w.command({type = "place", object_type = "desk", room = "study", x = 0, y = 0}).error, "room_not_built")
	assert_true(w.command({type = "build_room", room = "study"}).ok); assert_eq(w.money, 500)
	assert_true(w.command({type = "place", object_type = "desk", room = "study", x = 0, y = 0}).ok)
	assert_eq(w.command({type = "build_room", room = "study"}).error, "already_built")
func test_build_without_money():
	var w := _w(); w.money = 100
	assert_eq(w.command({type = "build_room", room = "study"}).error, "no_money"); assert_true("study" not in w.rooms_built)
func test_sell_refunds_and_cancels_user():
	var w := _w(); var p := TestKit.adult(w)
	var uid: int = w.command({type = "place", object_type = "tv", room = "main", x = 0, y = 0}).uid
	w.command({type = "drag", person = p.uid, object = uid}); var m := w.money
	assert_true(not p.current.is_empty())
	assert_true(w.command({type = "sell_object", object = uid}).ok)
	assert_true(p.current.is_empty()); assert_eq(w.object(uid), {})
	assert_eq(w.money, m + int(w.pack.object_types["tv"]["price"] * 0.5))
func test_move_cancels_user_and_keeps_uid():
	var w := _w(); var p := TestKit.adult(w)
	var uid: int = w.command({type = "place", object_type = "tv", room = "main", x = 0, y = 0}).uid
	w.command({type = "drag", person = p.uid, object = uid})
	assert_true(not p.current.is_empty())
	assert_true(w.command({type = "move", object = uid, room = "main", x = 4, y = 2}).ok)
	assert_true(p.current.is_empty()); assert_eq(w.object(uid).x, 4)
func test_can_place_error_order():
	var w := _w()
	assert_eq(HouseSystem.can_place(w, "nope", "main", 0, 0), "no_object_type")
	assert_eq(HouseSystem.can_place(w, "tv", "nope", 0, 0), "no_room")
	assert_eq(HouseSystem.can_place(w, "tv", "study", 0, 0), "room_not_built")
	assert_eq(HouseSystem.can_place(w, "tv", "yard", 0, 0), "wrong_area")
	assert_eq(HouseSystem.can_place(w, "tv", "main", -1, 0), "out_of_bounds")
	assert_eq(HouseSystem.can_place(w, "tv", "main", 7, 0), "out_of_bounds")
	assert_eq(HouseSystem.can_place(w, "tv", "main", 6, 0), "")
func test_place_no_money_and_unknown_type():
	var w := _w(); w.money = 10
	assert_eq(w.command({type = "place", object_type = "tv", room = "main", x = 0, y = 0}).error, "no_money")
	assert_eq(w.money, 10); assert_eq(w.objects.size(), 0)
	assert_eq(w.command({type = "place", object_type = "nope", room = "main", x = 0, y = 0}).error, "no_object_type")
func test_invalid_spot_never_charges_even_when_poor():
	var w := _w(); w.money = 10
	assert_eq(w.command({type = "place", object_type = "tv", room = "main", x = 7, y = 0}).error, "out_of_bounds")
	assert_eq(w.money, 10)
func test_add_object_is_free_and_rejects_invalid():
	var w := _w(); var m := w.money
	assert_true(w.add_object("tv", "main", 0, 0) >= 0); assert_eq(w.money, m)
	assert_eq(w.add_object("tv", "main", 1, 0), -1); assert_eq(w.objects.size(), 1)
func test_move_onto_own_old_footprint_allowed():
	var w := _w(); var uid: int = w.command({type = "place", object_type = "tv", room = "main", x = 2, y = 2}).uid
	assert_true(w.command({type = "move", object = uid, room = "main", x = 3, y = 2}).ok)
	assert_eq(w.object(uid).x, 3)
func test_move_invalid_changes_nothing():
	var w := _w(); var p := TestKit.adult(w)
	var uid: int = w.command({type = "place", object_type = "tv", room = "main", x = 0, y = 0}).uid
	w.command({type = "place", object_type = "desk", room = "main", x = 4, y = 0})
	w.command({type = "drag", person = p.uid, object = uid})
	assert_eq(w.command({type = "move", object = uid, room = "main", x = 4, y = 0}).error, "overlap")
	assert_eq(w.object(uid).x, 0); assert_true(not p.current.is_empty())
	assert_eq(w.command({type = "move", object = 999, room = "main", x = 0, y = 0}).error, "no_object")
func test_sell_unknown_object():
	var w := _w(); assert_eq(w.command({type = "sell_object", object = 5}).error, "no_object")
func test_build_unknown_room():
	var w := _w(); assert_eq(w.command({type = "build_room", room = "nope"}).error, "no_room")
