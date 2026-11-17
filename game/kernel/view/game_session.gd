class_name GameSession
extends RefCounted
## Owns the World for a view: feeds it the real clock (the only place in the view layer that
## reads it), loads and saves, keeps the player's settings, and turns kernel events into signals.

signal event(e: Dictionary)
signal command_failed(code: String)
signal away(summary: Dictionary)
## Emitted once after every step (tick or command) so panels can refresh.
signal changed

const AUTOSAVE_SECONDS := 30.0
const FLIP_OFFSET := 43200

var world: World
var pack: Pack
var strings: ViewStrings
var load_error := ""
var settings := {"flip_day_night": false, "clock_skew": 0, "speed": 1}

var _dir: String
var _real_clock: Callable
## Accumulated debug fast-forward in seconds, kept as a float; `settings.clock_skew` mirrors it.
var _skew := 0.0
var _since_save := 0.0


func _init(pack_id: String, dir := "user://", real_clock := Callable()) -> void:
	_dir = dir if dir.ends_with("/") else dir + "/"
	_real_clock = real_clock
	pack = Pack.load_dir("res://packs/" + pack_id)
	strings = ViewStrings.new(pack)
	_load_settings()


func save_path() -> String:
	return _dir + "save_" + pack.id + ".json"


func start() -> void:
	load_error = ""
	if not pack.is_valid():
		world = World.new(pack, 0)
		return
	var r := SaveStore.load(pack, save_path())
	var err := str(r.error)
	if err == "":
		world = r.world
	elif err == "missing":
		_create_world()
	else:
		load_error = err
		world = null


func new_game() -> void:
	var path := save_path()
	if FileAccess.file_exists(path):
		var bad := path + ".bad"
		if FileAccess.file_exists(bad):
			DirAccess.remove_absolute(bad)
		DirAccess.rename_absolute(path, bad)
	load_error = ""
	_since_save = 0.0
	_create_world()


func now_unix() -> int:
	return int(_real().unix + _skew)


func utc_offset() -> int:
	var off := int(_real().offset)
	return off + FLIP_OFFSET if settings.flip_day_night else off


func tick(delta: float) -> void:
	if not _running():
		return
	var speed := int(settings.speed)
	if speed > 1:
		_skew += (speed - 1) * delta
		settings.clock_skew = int(_skew)
	_sync_and_dispatch()
	changed.emit()
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		_since_save = 0.0
		save()


func command(cmd: Dictionary) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "not_running"}
	if world.phase != "invalid":
		_sync_and_dispatch()
	var r := world.command(cmd)
	if not r.get("ok", false):
		command_failed.emit(str(r.get("error", "")))
	_dispatch_events()
	changed.emit()
	return r


func save() -> bool:
	if not _running():
		return false
	if not SaveStore.save(world, save_path()):
		return false
	_write_settings()
	return true


func set_setting(key: String, value) -> void:
	if key == "clock_skew":
		_skew = float(value)
		settings.clock_skew = int(_skew)
	else:
		settings[key] = value
	_write_settings()


func _running() -> bool:
	return world != null and world.phase != "invalid"


func _create_world() -> void:
	world = World.new(pack, int(_real().unix))


func _real() -> Dictionary:
	if _real_clock.is_valid():
		return _real_clock.call()
	return {
		"unix": Time.get_unix_time_from_system(),
		"offset": int(Time.get_time_zone_from_system().bias) * 60,
	}


func _sync_and_dispatch() -> void:
	var summary := world.sync(now_unix(), utc_offset())
	if float(summary.get("simulated_seconds", 0)) > 0.0:
		away.emit(summary)
	_dispatch_events()


func _dispatch_events() -> void:
	for e in world.drain_events():
		event.emit(e)


func _settings_path() -> String:
	return _dir + "settings.json"


func _load_settings() -> void:
	var path := _settings_path()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = json.data
	if typeof(d.get("flip_day_night")) == TYPE_BOOL:
		settings.flip_day_night = d["flip_day_night"]
	if typeof(d.get("clock_skew")) in [TYPE_INT, TYPE_FLOAT]:
		_skew = float(d["clock_skew"])
		settings.clock_skew = int(_skew)
	if typeof(d.get("speed")) in [TYPE_INT, TYPE_FLOAT]:
		settings.speed = int(d["speed"])


func _write_settings() -> void:
	settings.clock_skew = int(_skew)
	var f := FileAccess.open(_settings_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(settings))
	f.close()
