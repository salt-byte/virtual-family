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
