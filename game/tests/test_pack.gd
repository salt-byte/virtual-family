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
