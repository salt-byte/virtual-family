extends TestCase

func test_smoke_pack_loads_clean():
	var p := Pack.load_dir("res://packs/_smoke")
	assert_eq(p.errors, [] as Array[String])
	assert_eq(p.id, "_smoke")
	assert_true(p.actions.has("eat"))
	assert_eq(p.cfg("hours_per_year"), 2.0)

func test_defaults_applied():
	var p := Pack.load_dir("res://packs/_smoke")
	assert_eq(p.cfg("offline_cap_hours"), 48)
	assert_eq(p.cfg("start_money"), 200)
	assert_eq(p.cfg("sell_back_ratio"), 0.5)
	assert_eq(p.cfg("lifespan"), [60, 75])
	assert_eq(p.cfg("vital_need"), "health")
	assert_eq(p.cfg("praise_need"), "happy")
	assert_eq(p.cfg("work_needs_min"), {"fed": 20.0})

func test_entries_are_dictionaries_with_defaults_filled():
	var p := Pack.load_dir("res://packs/_smoke")
	assert_eq(p.actions["eat"]["duration_min"], 20)
	assert_eq(p.actions["eat"]["consumes"], {"food": 1})
	assert_eq(p.actions["eat"]["stages"], ["child", "adult", "elder"])
	assert_eq(p.actions["eat"]["praiseable"], true)
	assert_eq(p.actions["take_out_trash"]["object"], "")
	assert_eq(p.actions["cough"]["praiseable"], false)
	assert_eq(p.object_types["fridge"]["outdoor"], false)
	assert_eq(p.rooms["yard"]["outdoor"], true)
	assert_eq(p.items["cake"]["stock"], {})
	assert_eq(p.needs["fed"]["when_empty"], {"need": "health", "per_hour": 10.0})
	assert_eq(p.needs["fed"]["labels"].size(), 3)
	assert_eq(p.names["family"].is_empty(), false)

func test_bad_pack_reports_file_and_id():
	var p := Pack.load_dir("res://tests/fixtures/bad_pack")
	assert_true(not p.is_valid())
	assert_true(p.errors.any(func(e): return e.begins_with("actions.json: eat:")))
	assert_true(p.errors.any(func(e): return e.begins_with("needs.json: fed:")))
	assert_true(p.errors.any(func(e): return e.begins_with("livelihoods.json: office:")))

func test_missing_dir_is_error_not_crash():
	assert_true(not Pack.load_dir("res://packs/nope").is_valid())

func test_malformed_json_is_file_error():
	var p := Pack.load_dir("res://tests/fixtures/broken_json_pack")
	assert_true(not p.is_valid())
	assert_true(p.errors.any(func(e): return e.begins_with("rooms.json:")))

func test_bad_pack_messages_name_the_problem():
	var p := Pack.load_dir("res://tests/fixtures/bad_pack")
	assert_true(p.errors.any(func(e): return e.begins_with("actions.json: eat:") and e.contains("fridgee")))
	assert_true(p.errors.any(func(e): return e.begins_with("needs.json: fed:") and e.contains("duplicate")))
	assert_true(p.errors.any(func(e): return e.begins_with("livelihoods.json: office:") and e.contains("empty")))
	assert_eq(p.errors.size(), 3)

func test_smoke_pack_cross_references():
	var p := Pack.load_dir("res://packs/_smoke")
	assert_eq(p.illnesses["cold"]["symptom_action"], "cough")
	assert_eq(p.actions["cough"]["requires"], {"illness": "cold"})
	assert_eq(p.object_types["bed"]["w"], 2)
	assert_eq(p.rooms["study"]["build_cost"], 500)
	assert_eq(p.livelihoods["office"]["levels"].size(), 3)
	assert_eq(p.livelihoods["office"]["levels"][2]["progress_to_next"], 0)

## Loads the smoke pack, applies `mutate` to it, and returns the validator's errors.
func _errs(mutate: Callable) -> Array[String]:
	var p := Pack.load_dir("res://packs/_smoke")
	mutate.call(p)
	return PackValidator.validate(p)

func _has(errs: Array[String], prefix: String, part := "") -> bool:
	return errs.any(func(e): return e.begins_with(prefix) and e.contains(part))

func test_validator_clean_baseline():
	assert_eq(_errs(func(p): pass), [] as Array[String])

func test_vital_need_must_exist():
	assert_true(_has(_errs(func(p): p.config["vital_need"] = "nope"), "pack.json:", "vital_need"))

func test_praise_need_must_exist():
	assert_true(_has(_errs(func(p): p.config["praise_need"] = "nope"), "pack.json:", "praise_need"))

func test_work_needs_min_key_must_exist():
	assert_true(_has(_errs(func(p): p.config["work_needs_min"] = {"nope": 5}), "pack.json:", "work_needs_min"))

func test_start_money_must_be_nonnegative_integer():
	assert_true(_has(_errs(func(p): p.config["start_money"] = -1), "pack.json:", "start_money"))
	assert_true(_has(_errs(func(p): p.config["start_money"] = 10.5), "pack.json:", "start_money"))

func test_symptom_action_must_exist():
	assert_true(_has(_errs(func(p): p.illnesses["cold"]["symptom_action"] = "nope"), "illnesses.json: cold:", "symptom_action"))

func test_symptom_action_must_point_back():
	assert_true(_has(_errs(func(p): p.actions["cough"]["requires"] = {"sick": true}), "illnesses.json: cold:", "requires.illness"))

func test_symptom_action_must_not_need_an_object():
	assert_true(_has(_errs(func(p): p.actions["cough"]["object"] = "bed"), "illnesses.json: cold:", "object"))

func test_needs_one_built_indoor_room():
	var e := _errs(func(p): p.rooms["main"]["built"] = false)
	assert_true(_has(e, "rooms.json:", "built indoor"))

func test_work_action_needs_object():
	assert_true(_has(_errs(func(p): p.actions["work_desk"]["object"] = ""), "actions.json: work_desk:", "object"))

func test_work_track_must_exist():
	assert_true(_has(_errs(func(p): p.actions["work_desk"]["work"] = {"track": "nope"}), "actions.json: work_desk:", "work.track"))

func test_goal_type_must_be_known():
	assert_true(_has(_errs(func(p): p.goals["tidy_home"]["when"] = {"type": "nope"}), "goals.json: tidy_home:", "when.type"))

func test_labels_must_reach_101():
	var e := _errs(func(p): p.needs["fed"]["labels"][2]["below"] = 100)
	assert_true(_has(e, "needs.json: fed:", "101"))

func test_labels_must_not_be_empty():
	assert_true(_has(_errs(func(p): p.needs["fed"]["labels"] = []), "needs.json: fed:", "empty"))

func test_consumes_must_name_a_stock():
	assert_true(_has(_errs(func(p): p.actions["eat"]["consumes"] = {"nope": 1}), "actions.json: eat:", "consumes"))

func test_cleans_must_name_a_mess():
	assert_true(_has(_errs(func(p): p.actions["take_out_trash"]["cleans"] = "nope"), "actions.json: take_out_trash:", "cleans"))

func test_action_needs_key_and_mess_type_must_exist():
	assert_true(_has(_errs(func(p): p.actions["eat"]["needs"] = {"nope": 1}), "actions.json: eat:", "needs key"))
	assert_true(_has(_errs(func(p): p.actions["eat"]["mess"] = {"type": "nope", "chance": 1}), "actions.json: eat:", "mess.type"))

func test_money_and_sizes_must_be_whole_and_nonnegative():
	assert_true(_has(_errs(func(p): p.object_types["fridge"]["price"] = 12.5), "objects.json: fridge:", "price"))
	assert_true(_has(_errs(func(p): p.object_types["fridge"]["price"] = -1), "objects.json: fridge:", "price"))
	assert_true(_has(_errs(func(p): p.rooms["study"]["build_cost"] = -500), "rooms.json: study:", "build_cost"))
	assert_true(_has(_errs(func(p): p.items["cake"]["price"] = 0.5), "items.json: cake:", "price"))
	assert_true(_has(_errs(func(p): p.goals["tidy_home"]["reward"] = -5), "goals.json: tidy_home:", "reward"))
	assert_true(_has(_errs(func(p): p.collectibles["coin"]["value"] = -1), "collectibles.json: coin:", "value"))
	assert_true(_has(_errs(func(p): p.livelihoods["office"]["levels"][0]["daily_income"] = -1), "livelihoods.json: office:", "daily_income"))
	assert_true(_has(_errs(func(p): p.object_types["bed"]["w"] = 0), "objects.json: bed:", "w"))
	assert_true(_has(_errs(func(p): p.rooms["main"]["h"] = 0), "rooms.json: main:", "h"))
	assert_true(_has(_errs(func(p): p.actions["eat"]["duration_min"] = 0), "actions.json: eat:", "duration_min"))

func test_array_values_do_not_crash_validator():
	var e := _errs(func(p):
		p.actions["eat"]["stages"] = [["x"]]
		p.actions["eat"]["cleans"] = ["x"]
		p.config["vital_need"] = ["x"])
	assert_true(not e.is_empty())

func test_json_null_file_is_an_error():
	var p := Pack.load_dir("res://tests/fixtures/null_json_pack")
	assert_true(_has(p.errors, "goals.json:", "array"))
	assert_true(_has(p.errors, "names.json:", "object"))

func test_stages_must_include_kernel_stage_ids():
	for id in ["baby", "adult", "elder"]:
		var e := _errs(func(p): p.config["stages"] = (p.config["stages"] as Array).filter(func(s): return s.id != id))
		assert_true(_has(e, "pack.json:", "'%s'" % id), id)
	assert_true(not _has(_errs(func(p): p.config["stages"] = (p.config["stages"] as Array).filter(func(s): return s.id != "child")), "pack.json:", "stage"))

func test_stage_from_must_be_strictly_ascending():
	var swapped := func(p):
		var st: Array = p.config["stages"]; var t = st[1]; st[1] = st[2]; st[2] = t
	assert_true(_has(_errs(swapped), "pack.json:", "strictly ascending"))
	assert_true(_has(_errs(func(p): p.config["stages"][2]["from"] = p.config["stages"][1]["from"]), "pack.json:", "strictly ascending"))
	assert_true(_has(_errs(func(p): p.config["stages"] = "x"), "pack.json:", "stages"))
	assert_true(_has(_errs(func(p): p.config["stages"][0] = {"id": "baby"}), "pack.json:", "'from'"))

## A pack listing its stages out of order loads with them sorted by `from`.
func test_pack_sorts_stages_on_load():
	var src := "res://packs/_smoke"; var dst := "user://test_unsorted_stages_pack"
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		var text := FileAccess.get_file_as_string(src + "/" + f)
		if f == "pack.json":
			var d: Dictionary = JSON.parse_string(text)
			d["stages"] = [{"id": "elder", "from": 55}, {"id": "baby", "from": 0}, {"id": "adult", "from": 18}, {"id": "child", "from": 2}]
			text = JSON.stringify(d)
		var out := FileAccess.open(dst + "/" + f, FileAccess.WRITE); out.store_string(text); out.close()
	var p := Pack.load_dir(dst)
	for f in DirAccess.get_files_at(dst):
		DirAccess.remove_absolute(dst + "/" + f)
	DirAccess.remove_absolute(dst)
	assert_eq(p.errors, [] as Array[String])
	assert_eq((p.cfg("stages") as Array).map(func(s): return s.id), ["baby", "child", "adult", "elder"])
	var q := Person.new(); q.age = 30.0
	assert_eq(q.stage(p), "adult")

func test_object_capacity_must_be_a_positive_whole_number():
	var first := func(p): return p.object_types.keys()[0]
	assert_true(_has(_errs(func(p): p.object_types[first.call(p)]["capacity"] = 0), "objects.json:", "capacity"))
	assert_true(_has(_errs(func(p): p.object_types[first.call(p)]["capacity"] = 1.5), "objects.json:", "capacity"))
	assert_eq(_errs(func(p): p.object_types[first.call(p)]["capacity"] = 2), [] as Array[String])

func test_repeat_factor_must_be_in_zero_exclusive_to_one():
	assert_true(_has(_errs(func(p): p.config["repeat_factor"] = 0.0), "pack.json:", "repeat_factor"))
	assert_true(_has(_errs(func(p): p.config["repeat_factor"] = 1.5), "pack.json:", "repeat_factor"))
	assert_eq(_errs(func(p): p.config["repeat_factor"] = 1.0), [] as Array[String])

func _start(entries: Array) -> Callable:
	return func(p): p.config["start_objects"] = entries

func test_start_objects_default_is_empty_and_smoke_has_some():
	assert_eq(Pack.DEFAULT_CONFIG["start_objects"], [])
	var p := Pack.load_dir("res://packs/_smoke")
	assert_true((p.cfg("start_objects") as Array).size() >= 2)
	assert_eq(p.errors, [] as Array[String])

func test_start_objects_unknown_type():
	var e := _errs(_start([{"type": "nope", "room": "main", "x": 0, "y": 0}]))
	assert_true(_has(e, "pack.json:", "start_objects #0"))

func test_start_objects_unknown_room_and_unbuilt_room():
	assert_true(_has(_errs(_start([{"type": "fridge", "room": "nope", "x": 0, "y": 0}])), "pack.json:", "start_objects #0"))
	assert_true(_has(_errs(_start([{"type": "fridge", "room": "study", "x": 0, "y": 0}])), "pack.json:", "not built"))

func test_start_objects_out_of_bounds_and_wrong_area():
	assert_true(_has(_errs(_start([{"type": "tv", "room": "main", "x": 7, "y": 0}])), "pack.json:", "start_objects #0"))
	assert_true(_has(_errs(_start([{"type": "fridge", "room": "yard", "x": 0, "y": 0}])), "pack.json:", "start_objects #0"))

func test_start_objects_overlap_names_the_second_entry():
	var e := _errs(_start([{"type": "fridge", "room": "main", "x": 0, "y": 0}, {"type": "tv", "room": "main", "x": 0, "y": 0}]))
	assert_true(_has(e, "pack.json:", "start_objects #1"))
	assert_true(not _has(e, "pack.json:", "start_objects #0"))

func test_start_objects_must_be_a_list_of_objects():
	assert_true(_has(_errs(func(p): p.config["start_objects"] = 5), "pack.json:", "start_objects"))
	assert_true(_has(_errs(_start([5])), "pack.json:", "start_objects #0"))

func test_step_seconds_must_divide_a_minute():
	for bad in [0, 7, 61, 5.5]:
		assert_true(_has(_errs(func(p): p.config["step_seconds"] = bad), "pack.json:", "step_seconds"), str(bad))
	for good in [5, 60]:
		assert_eq(_errs(func(p): p.config["step_seconds"] = good), [] as Array[String], str(good))
	assert_eq(Pack.DEFAULT_CONFIG["step_seconds"], 60)
	assert_eq(Pack.load_dir("res://packs/qijia").cfg("step_seconds"), 5)

func test_action_speed_must_be_at_least_one():
	for bad in [0.5, 0, -2, "fast"]:
		assert_true(_has(_errs(func(p): p.config["action_speed"] = bad), "pack.json:", "action_speed"), str(bad))
	for good in [1, 1.0, 30]:
		assert_eq(_errs(func(p): p.config["action_speed"] = good), [] as Array[String], str(good))
	assert_eq(Pack.DEFAULT_CONFIG["action_speed"], 1.0)
	assert_eq(Pack.load_dir("res://packs/qijia").cfg("action_speed"), 30.0)

func test_slow_must_be_a_bool_and_defaults_to_false():
	var first := func(p): return p.actions.keys()[0]
	assert_true(_has(_errs(func(p): p.actions[first.call(p)]["slow"] = 1), "actions.json:", "slow"))
	assert_eq(_errs(func(p): p.actions[first.call(p)]["slow"] = true), [] as Array[String])
	var smoke := Pack.load_dir("res://packs/_smoke")
	assert_true(smoke.actions.values().all(func(a): return a["slow"] == false))
	var q := Pack.load_dir("res://packs/qijia")
	assert_true(q.actions["sleep"]["slow"])
	assert_true(not q.actions["nap"]["slow"])   # a nap is a quick lie-down, not a dead hour
	assert_true(not q.actions["study"]["slow"])

func test_repeat_memory_is_a_whole_number_from_one_to_eight():
	for bad in [0, 9, 2.5, "3", -1]:
		assert_true(_has(_errs(func(p): p.config["repeat_memory"] = bad), "pack.json:", "repeat_memory"), str(bad))
	for good in [1, 3, 8]:
		assert_eq(_errs(func(p): p.config["repeat_memory"] = good), [] as Array[String], str(good))
	assert_eq(Pack.DEFAULT_CONFIG["repeat_memory"], 1)
	assert_eq(Pack.load_dir("res://packs/_smoke").cfg("repeat_memory"), 1)
	assert_eq(Pack.load_dir("res://packs/qijia").cfg("repeat_memory"), 8)

## qijia's fast tempo fits 6-20 actions in ten minutes, so praise annoys only when three
## praises come within three minutes.
func test_qijia_praise_window_fits_the_fast_tempo():
	var q := Pack.load_dir("res://packs/qijia")
	assert_eq(q.cfg("praise_window_min"), 3)
	assert_eq(q.cfg("praise_annoy_count"), 3)
	assert_eq(Pack.load_dir("res://packs/_smoke").cfg("praise_window_min"), 10)

func test_choice_pool_is_a_whole_number_from_one_to_thirty_two():
	for bad in [0, 33, 2.5, "3"]:
		assert_true(_has(_errs(func(p): p.config["choice_pool"] = bad), "pack.json:", "choice_pool"), str(bad))
	for good in [1, 3, 32]:
		assert_eq(_errs(func(p): p.config["choice_pool"] = good), [] as Array[String], str(good))
	assert_eq(Pack.DEFAULT_CONFIG["choice_pool"], 3)
	assert_eq(Pack.load_dir("res://packs/_smoke").cfg("choice_pool"), 3)


## Places the smoke rooms on a grid: main (0,0), study (9,0), yard (0,7).
func _place(p: Pack) -> void:
	p.rooms["main"]["x"] = 0
	p.rooms["main"]["y"] = 0
	p.rooms["study"]["x"] = 9
	p.rooms["study"]["y"] = 0
	p.rooms["yard"]["x"] = 0
	p.rooms["yard"]["y"] = 7

func test_positioned_rooms_validate_clean():
	assert_eq(_errs(_place), [] as Array[String])

func test_rooms_must_be_all_positioned_or_none():
	var e := _errs(func(p): _place(p); p.rooms["yard"].erase("x"); p.rooms["yard"].erase("y"))
	assert_true(_has(e, "rooms.json: *:", "position"))
	assert_true(_has(_errs(func(p): _place(p); p.rooms["yard"].erase("y")), "rooms.json: *:", "position"))
	assert_true(_has(_errs(func(p): p.rooms["main"]["x"] = 0), "rooms.json: *:", "position"))

func test_positioned_rooms_must_not_overlap():
	var e := _errs(func(p): _place(p); p.rooms["study"]["x"] = 7)
	assert_true(_has(e, "rooms.json: study:", "main"))
	assert_true(not _has(e, "rooms.json: *:"))

func test_room_position_must_be_whole_and_nonnegative():
	assert_true(_has(_errs(func(p): _place(p); p.rooms["study"]["x"] = 9.5), "rooms.json: study:", "'x'"))
	assert_true(_has(_errs(func(p): _place(p); p.rooms["yard"]["y"] = -1), "rooms.json: yard:", "'y'"))
	assert_true(_has(_errs(func(p): _place(p); p.rooms["yard"]["y"] = "7"), "rooms.json: yard:", "'y'"))

func test_room_positions_load_as_ints():
	var p := Pack.load_dir("res://packs/qijia")
	assert_true(p.rooms["hall"]["x"] is int)
	assert_eq(p.rooms["yard"]["y"], 18)  # the site plan puts the compound at (17, 9), the yard below the 9-deep wings
