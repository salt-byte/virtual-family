class_name SaveStore
extends RefCounted
## Reads and writes a World as one JSON file. Saving goes through `path + ".tmp"` and a
## rename, so a failed save never damages the previous file; loading never changes files.


static func save(world: World, path: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var written := f.store_string(JSON.stringify(world.to_dict()))
	f.close()
	if not written or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


## {world: World or null, error: "" | "missing" | "corrupt" | "version" | "pack_mismatch"}
static func load(pack: Pack, path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"world": null, "error": "missing"}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"world": null, "error": "corrupt"}
	var d: Dictionary = json.data
	var v = d.get("version")
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		return {"world": null, "error": "corrupt"}
	if v != World.SAVE_VERSION:
		return {"world": null, "error": "version"}
	if d.get("pack_id") != pack.id:
		return {"world": null, "error": "pack_mismatch"}
	var w := World.from_dict(pack, d)
	if w == null:
		return {"world": null, "error": "corrupt"}
	return {"world": w, "error": ""}
