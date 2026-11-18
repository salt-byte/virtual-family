extends TestCase
## Cooked food as a thing on the table (qijia's dishes.json; see `DishSystem`).


## A qijia house at noon with a stove, the dining table and food in the larder.
func _home() -> World:
	var w := TestKit.world("qijia")
	assert_true(w.add_object("stove", "kitchen", 0, 0) >= 0)
	assert_true(w.add_object("dining_table", "hall", 5, 2) >= 0)
	w.stock["food"] = 5
	return w


func _table(w: World) -> int:
	for o in w.objects:
		if o.type == "dining_table":
			return o.uid
	return -1


func _run(w: World, p: Person, action: String) -> void:
	AutonomySystem.start(w, p, action, -1)
	w.advance(float(AutonomySystem.duration_s(w, w.pack.actions[action])))


func test_cooking_puts_a_dish_on_the_table_not_in_the_cook():
	var w := _home(); var cook := TestKit.adult(w)
	cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	assert_eq(w.dishes.size(), 1)
	assert_eq(w.dishes[0].type, "porridge")
	assert_eq(int(w.dishes[0].object_uid), _table(w))
	assert_eq(int(w.dishes[0].portions), 3)
	assert_eq(int(w.stock["food"]), 4)
	assert_true(cook.needs["fed"] < 50.0, "the cook only tastes it: %s" % cook.needs["fed"])


func test_without_a_table_the_dish_stays_on_the_stove():
	var w := TestKit.world("qijia"); w.add_object("stove", "kitchen", 0, 0); w.stock["food"] = 2
	var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	assert_eq(w.object(int(w.dishes[0].object_uid)).type, "stove")


func test_one_pot_at_a_time():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	assert_eq(AutonomySystem.can_do(w, cook, "cook_porridge", -1), "requires")
	assert_true(AutonomySystem.candidates(w, cook).all(func(c): return c.action != "cook_porridge"))


func test_eating_walks_to_the_table_and_takes_a_portion():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	var kid := TestKit.adult(w, 8.0); kid.needs["fed"] = 30.0
	AutonomySystem.start(w, kid, "eat_porridge", -1)
	assert_eq(int(kid.current.object_uid), _table(w))
	assert_eq(int(kid.current.target_uid), int(w.dishes[0].uid))
	w.advance(float(AutonomySystem.duration_s(w, w.pack.actions["eat_porridge"])))
	assert_true(kid.needs["fed"] > 70.0, str(kid.needs["fed"]))
	assert_eq(int(w.dishes[0].portions), 2)


func test_hot_food_beats_cold_food():
	var a: Dictionary = Pack.load_dir("res://packs/qijia").actions["eat_porridge"]
	var c: Dictionary = Pack.load_dir("res://packs/qijia").actions["eat_on_threshold"]
	assert_true(float(a.needs.fed) > float(c.needs.fed))
	assert_true(a.needs.has("happy") and not c.needs.has("happy"))


func test_cold_food_needs_no_dish():
	var w := _home(); var p := TestKit.adult(w); p.needs["fed"] = 30.0
	assert_eq(w.dishes.size(), 0)
	assert_eq(AutonomySystem.can_do(w, p, "eat_porridge", -1), "no_target")
	assert_eq(AutonomySystem.can_do(w, p, "eat_on_threshold", -1), "no_object")  # no threshold in this bare house
	w.add_object("threshold", "gate", 2, 3)
	assert_eq(AutonomySystem.can_do(w, p, "eat_on_threshold", -1), "")


func test_last_portion_leaves_bowls_to_clear():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	var at := Vector2i(int(w.dishes[0].x), int(w.dishes[0].y))
	for i in 3:
		var p := TestKit.adult(w); p.needs["fed"] = 30.0
		_run(w, p, "eat_porridge")
	assert_eq(w.dishes.size(), 0)
	var bowls := w.messes.filter(func(m): return m.type == "bowls")
	assert_eq(bowls.size(), 1)
	assert_eq(bowls[0].room, "hall")
	assert_eq(Vector2i(int(bowls[0].x), int(bowls[0].y)), at)
	_run(w, cook, "clear_bowls")
	assert_eq(w.messes.filter(func(m): return m.type == "bowls").size(), 0)


func test_no_more_eaters_than_portions():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	w.stock["greens"] = 1
	_run(w, cook, "cook_greens")
	assert_eq(int(w.dishes[0].portions), 2)
	var eaters: Array = []
	for i in 3:
		var p := TestKit.adult(w); p.needs["fed"] = 30.0
		eaters.append(p)
	assert_eq(AutonomySystem.can_do(w, eaters[0], "eat_greens", -1), "")
	AutonomySystem.start(w, eaters[0], "eat_greens", -1)
	AutonomySystem.start(w, eaters[1], "eat_greens", -1)
	assert_eq(AutonomySystem.can_do(w, eaters[2], "eat_greens", -1), "no_target")


func test_a_dish_left_out_goes_to_waste():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	w.drain_events()
	w.offline = true
	w.advance(5.5 * 3600.0)
	assert_eq(w.dishes.size(), 0)
	var wasted := w.drain_events().filter(func(e): return e.type == "dish_finished")
	assert_eq(wasted.size(), 1)
	assert_eq(wasted[0].how, "wasted")


func test_picking_greens_fills_the_larder_for_a_plate():
	var w := _home(); w.add_object("garden", "yard", 8, 0)
	w.set_time(w.now - 3600, 0)  # 11:00, inside the picking hours
	var p := TestKit.adult(w); p.needs["fed"] = 40.0
	assert_eq(int(w.stock.get("greens", 0)), 0)
	assert_eq(AutonomySystem.can_do(w, p, "cook_greens", -1), "no_stock")
	_run(w, p, "pick_greens")
	assert_true(int(w.stock.get("greens", 0)) >= 1)


func test_drag_onto_the_table_with_food_eats_it():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	var p := TestKit.adult(w); p.needs["fed"] = 30.0
	var r := w.command({"type": "drag", "person": p.uid, "object": _table(w)})
	assert_true(r.ok); assert_eq(r.action, "eat_porridge")


func test_dishes_survive_a_save_and_old_saves_have_none():
	var w := _home(); var cook := TestKit.adult(w); cook.needs["fed"] = 40.0
	_run(w, cook, "cook_porridge")
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, d)
	assert_true(back != null)
	assert_eq(back.dishes, w.dishes)
	assert_eq(back.to_dict(), w.to_dict())
	d.erase("dishes")
	var old := World.from_dict(w.pack, d)
	assert_true(old != null)
	assert_eq(old.dishes.size(), 0)


func test_smoke_pack_has_no_dishes():
	var p := Pack.load_dir("res://packs/_smoke")
	assert_true(p.dishes.is_empty())
	assert_true(p.actions.values().all(func(a): return a.serves == "" and (a.eats as Array).is_empty()))


func test_validator_catches_bad_dish_references():
	var p := Pack.load_dir("res://packs/qijia")
	p.actions["eat_porridge"]["eats"] = ["gruel"]
	p.actions["cook_porridge"]["serves"] = "stew"
	p.dishes["porridge"]["on"] = ["spaceship"]
	var errs := PackValidator.validate(p)
	assert_true(errs.has("actions.json: eat_porridge: eats: 'gruel' is not a dish"), str(errs))
	assert_true(errs.has("actions.json: cook_porridge: serves 'stew' is not a dish"), str(errs))
	assert_true(errs.has("dishes.json: porridge: on: 'spaceship' is not an object type"), str(errs))
