extends SceneTree
## Headless test runner: ./game/tests/run.sh [filter]
## Runs every test_* method of every res://tests/test_*.gd on a fresh instance.
## The filter is matched against "file::method".

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var passed := 0
	var failed := 0
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for file in files:
		var script = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			if filter == "" or file.contains(filter):
				print("FAIL %s::<load>" % file)
				failed += 1
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if String(m["name"]).begins_with("test_"):
				methods.append(m["name"])
		methods.sort()
		for method in methods:
			var label := "%s::%s" % [file, method]
			if filter != "" and not label.contains(filter):
				continue
			var t = script.new()
			t.call(method)
			if t.assertions == 0:
				print("FAIL " + label)
				print("  no assertions made")
				failed += 1
			elif t.failures.is_empty():
				print("PASS " + label)
				passed += 1
			else:
				print("FAIL " + label)
				for msg in t.failures:
					print("  " + msg)
				failed += 1
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
