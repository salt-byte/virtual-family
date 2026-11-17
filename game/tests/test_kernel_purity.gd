extends TestCase

func test_kernel_has_no_theme_words_or_engine_time():
	var banned := ["qijia", "_smoke", "fridge", "科举", "侯府", "灶台", "Time.get_", "extends Node", "Input."]
	for f in DirAccess.get_files_at("res://kernel/sim"):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://kernel/sim/" + f)
		for b in banned:
			assert_true(not src.contains(b), f + " contains " + b)
