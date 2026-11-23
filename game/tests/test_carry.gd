extends TestCase
## Carrying things to their place (`CarrySystem`): what is picked up or swept is carried to
## its object (qijia: litter to the 土筐, finds to the 旧物匣, eggs, greens, herbs and bowls
## to the 碗柜) and only counts once it is put down; called away, it falls on the way.


func _w(seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	for room in ["hall", "kitchen", "yard"]:
		HouseSystem.place_props(w, room)
	w.pack.config["wish_chance_per_hour"] = 0.0
	return w


func _obj(w: World, type: String) -> Dictionary:
	for o in w.objects:
		if str(o.type) == type:
			return o
	return {}


func _types(w: World) -> Array:
	return w.drain_events().map(func(e): return str(e.type))


## Runs `action` on `target` to its end (the picking or sweeping leg).
func _do(w: World, p: Person, action: String, target: int) -> void:
	AutonomySystem.start(w, p, action, -1, target)
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions[action]))


func test_qijia_places_the_basket_the_chest_and_the_cupboard():
	var w := _w()
	assert_eq(_obj(w, "trash_basket").get("room"), "yard")
	assert_eq(_obj(w, "keepsake_chest").get("room"), "hall")
	assert_eq(_obj(w, "cupboard").get("room"), "kitchen")
	var p := w.pack
	assert_eq(p.errors, [] as Array[String])
	assert_eq(CarrySystem.stow_type(p, "collectible", "coins"), "keepsake_chest")
	assert_eq(CarrySystem.stow_type(p, "collectible", "egg"), "cupboard")
	assert_eq(CarrySystem.stow_type(p, "mess", "wrapper"), "trash_basket")
	assert_eq(CarrySystem.stow_type(p, "mess", "bowls"), "cupboard")
	assert_eq(CarrySystem.stow_type(p, "mess", "snow_cover"), "", "snow is shovelled aside, not carried")


func test_a_find_is_carried_to_the_chest_and_counts_only_when_put_down():
	var w := _w(); var p := TestKit.adult(w)
	var uid := CollectibleSystem.spawn(w, "coins", "yard")
	_do(w, p, "pick_up", uid)
	assert_true(CollectibleSystem.find(w, uid).is_empty(), "off the ground")
	assert_true(p.current.has("carry"), str(p.current))
	assert_eq(int(p.current.object_uid), int(_obj(w, "keepsake_chest").uid))
	assert_eq(str(p.current.action), "pick_up", "the second leg of the same action")
	assert_eq(int(w.box.get("coins", 0)), 0, "not yet in the box")
	var left := int(p.current.remaining_s)
	assert_true(left >= 5 and left <= 60, "a walk across the yard: %d s" % left)
	w.advance(left - w.step_s)
	assert_true(p.current.has("carry"), "still on the way")
	w.drain_events()
	w.advance(w.step_s)
	var ev := w.drain_events()
	var types: Array = ev.map(func(e): return str(e.type))
	assert_true(types.has("carried") and types.has("collected"), str(types))
	assert_eq(int(w.box.get("coins", 0)), 1)
	assert_true(not p.current.has("carry"))


func test_greens_go_to_the_larder_and_eggs_to_the_box_by_the_cupboard():
	var w := _w(); var p := TestKit.adult(w)
	_do(w, p, "pick_up", CollectibleSystem.spawn(w, "greens", "yard"))
	assert_eq(int(p.current.object_uid), int(_obj(w, "cupboard").uid))
	w.advance(int(p.current.remaining_s))
	assert_eq(int(w.stock.get("greens", 0)), 1, "into the larder")
	assert_eq(int(w.box.get("greens", 0)), 0)


func test_litter_pays_its_scrap_at_the_basket():
	var w := _w(); var p := TestKit.adult(w)
	w.pack.mess_types["cloth_scraps"]["scrap"] = {"value": 2, "chance": 1.0}
	var m := MessSystem.spawn(w, "cloth_scraps", "hall")
	var scrap := func(ev: Array) -> int:
		var n := 0
		for e in ev:
			if e.type == "income" and str(e.source) == "scrap":
				n += int(e.amount)
		return n
	AutonomySystem.start(w, p, "gather_cloth_scraps", -1, m)
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["gather_cloth_scraps"]))
	assert_true(MessSystem.find(w, m).is_empty(), "swept up")
	assert_eq(scrap.call(w.drain_events()), 0, "no scrap money yet")
	assert_eq(int(p.current.object_uid), int(_obj(w, "trash_basket").uid))
	w.advance(int(p.current.remaining_s))
	assert_eq(scrap.call(w.drain_events()), 2, "sold at the basket")


func test_called_away_they_drop_it_on_the_way():
	var w := _w(); var p := TestKit.adult(w)
	var uid := CollectibleSystem.spawn(w, "hairpin", "yard")
	_do(w, p, "pick_up", uid)
	w.advance(w.step_s)
	assert_true(p.current.has("carry"))
	w.drain_events()
	AutonomySystem.start(w, p, "sweep", -1)   # anything else
	var ev: Array = w.drain_events().filter(func(e): return e.type == "carry_dropped")
	assert_eq(ev.size(), 1)
	var back := CollectibleSystem.find(w, uid)
	assert_true(not back.is_empty(), "lies on the ground again")
	assert_true(w.rooms_built.has(str(back.room)))
	assert_eq(str(back.room), str(ev[0].room))
	assert_eq(int(w.box.get("hairpin", 0)), 0)
	# A mess spills again.
	var m := MessSystem.spawn(w, "wrapper", "hall")
	_do(w, p, "pick_wrapper", m)
	var before := w.messes.size()
	AutonomySystem.cancel(w, p)
	assert_eq(w.messes.size(), before + 1)


func test_without_the_place_it_counts_at_once_as_before():
	var w := TestKit.world("qijia"); var p := TestKit.adult(w)   # no props: no chest
	var uid := CollectibleSystem.spawn(w, "coins", "yard")
	_do(w, p, "pick_up", uid)
	assert_true(not p.current.has("carry"))
	assert_true(int(w.box.get("coins", 0)) == 1 or int(w.collection.get("coins", 0)) == 1)


func test_a_save_in_the_middle_of_carrying_goes_on_the_same():
	var w := _w(); var p := TestKit.adult(w); TestKit.adult(w)
	_do(w, p, "pick_up", CollectibleSystem.spawn(w, "purse", "yard"))
	assert_true(p.current.has("carry"))
	var d := w.to_dict()
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(back != null, "a carry leg loads")
	w.advance(120); back.advance(120)
	assert_eq(back.to_dict(), w.to_dict(), "continues identically")
	assert_eq(int(back.box.get("purse", 0)), 1)
	var bad: Dictionary = JSON.parse_string(JSON.stringify(d))
	for q in bad["people"]:
		if (q["current"] as Dictionary).has("carry"):
			q["current"]["carry"]["x"] = "far"
	assert_true(World.from_dict(w.pack, bad) == null, "a malformed carry is corrupt")


func test_validator_checks_stow_and_stock():
	var p := Pack.load_dir("res://packs/qijia")
	p.collectibles["coins"]["stow"] = "piano"
	p.collectibles["egg"]["stock"] = 3
	p.mess_types["dirt"]["stow"] = "barn"
	p.config["carry"] = {"cell_s": -1}
	var errs := PackValidator.validate(p)
	for e in ["collectibles.json: coins: stow 'piano' is not an object type",
			"collectibles.json: egg: stock must be a stock id (a string)",
			"messes.json: dirt: stow 'barn' is not an object type"]:
		assert_true(errs.has(e), "missing: " + e + "\n" + "\n".join(errs))
	assert_true(errs.any(func(e): return str(e).begins_with("pack.json: qijia: carry must be")), "\n".join(errs))
