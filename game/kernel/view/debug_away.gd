class_name DebugAway
extends RefCounted
## Debug only, for timing a long absence: `?debug_away=<hours>` on the web build (or
## `-- --debug-away=<hours>` on the command line) plays a throwaway family of four, kept in its
## own folder (`DIR`), that was last seen that many hours ago. Each start writes that save anew,
## so a reload measures the same absence again. The player's real save is never read or touched.
## Load phases and the catch-up time go to the console as lines starting with `[load]`.

const DIR := "user://debug_away/"


## The hours asked for, 0 when the flag is absent or not a positive number.
static func hours() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--debug-away="):
			return maxf(0.0, a.substr(13).to_float())
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('debug_away') || ''")
		return maxf(0.0, str(v).to_float())
	return 0.0


## Writes a family of four (the adopted adult, a spouse, two children, 20 food) that was last
## synced `away_hours` before now into `DIR`.
static func seed_save(pack_id: String, away_hours: float) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var pack := Pack.load_dir("res://packs/" + pack_id)
	var w := World.new(pack, 11)
	var now := int(Time.get_unix_time_from_system())
	w.set_time(now - int(away_hours * 3600.0), int(Time.get_time_zone_from_system().bias) * 60)
	w.command({"type": "adopt"})
	var spouse := FamilySystem.make_person(w, pack.cfg("adopt_age"))
	w.add_person(spouse)
	w.married = true
	for i in 2:
		w.add_person(FamilySystem.make_person(w, [6, 12]))
	w.stock["food"] = 20
	SaveStore.save(w, DIR + "save_" + pack.id + ".json")
	if FileAccess.file_exists(DIR + "settings.json"):
		DirAccess.remove_absolute(DIR + "settings.json")


## Milliseconds since the page started loading on the web (performance.now()); engine ticks
## elsewhere.
static func page_ms() -> float:
	if OS.has_feature("web"):
		return float(JavaScriptBridge.eval("performance.now()"))
	return float(Time.get_ticks_msec())


static func log(what: String) -> void:
	print("[load] %s page_ms=%.0f engine_ms=%d" % [what, page_ms(), Time.get_ticks_msec()])
