extends TestCase
const PACKS := ["_smoke", "qijia"]

func _kernel_sources() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at("res://kernel/sim"):
		if f.ends_with(".gd"):
			out[f] = FileAccess.get_file_as_string("res://kernel/sim/" + f)
	return out

func test_kernel_has_no_theme_words_or_engine_time():
	var banned := ["qijia", "_smoke", "fridge", "科举", "侯府", "灶台", "Time.get_", "extends Node", "Input."]
	var src := _kernel_sources()
	for f in src:
		for b in banned:
			assert_true(not src[f].contains(b), f + " contains " + b)

## Words the kernel may quote although a pack might also use them as an id: the default
## stage ids and the schema keys the kernel itself defines.
func _allowed() -> Dictionary:
	var ok := {"baby": true, "child": true, "adult": true, "elder": true}
	for k in Pack.DEFAULT_CONFIG:
		ok[k] = true
	for k in Pack.FILES:
		ok[k] = true
	for file in Pack.ENTRY_DEFAULTS:
		for k in Pack.ENTRY_DEFAULTS[file]:
			ok[k] = true
	for file in PackValidator.REQUIRED:
		for k in PackValidator.REQUIRED[file]:
			ok[k] = true
	return ok

## Every id (length >= 3) in every file of both packs, e.g. "cook_porridge", "office".
func _pack_ids() -> Dictionary:
	var ids := {}
	for pack in PACKS:
		var dir: String = "res://packs/" + pack
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json"):
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + f))
			var entries: Array = data if data is Array else [data]
			if data is Dictionary and data.get("stages") is Array:
				entries.append_array(data["stages"])
			for e in entries:
				if e is Dictionary and e.get("id") is String and str(e["id"]).length() >= 3:
					ids[str(e["id"])] = true
	return ids

func test_kernel_quotes_no_pack_id():
	var ids := _pack_ids()
	var allowed := _allowed()
	assert_true(ids.size() > 50, "pack ids were found (%d)" % ids.size())
	var src := _kernel_sources()
	for id in ids:
		if allowed.has(id):
			continue
		for f in src:
			for q in ["\"", "'"]:
				assert_true(not src[f].contains(q + id + q), "%s quotes pack id %s" % [f, id])

func test_view_layer_has_no_theme_words():
	var banned := ["qijia", "_smoke", "灶台", "科举", "侯府", "集市", "账房", "家谱", "媒人", ".illness"]
	var n := 0
	for f in DirAccess.get_files_at("res://kernel/view"):
		if not f.ends_with(".gd"):
			continue
		n += 1
		var src := FileAccess.get_file_as_string("res://kernel/view/" + f)
		for b in banned:
			assert_true(not src.contains(b), f + " contains " + b)
	assert_true(n >= 1)
