class_name GameSession
extends RefCounted
## Owns the World for a view: feeds it the real clock (the only place in the view layer that
## reads it), loads and saves, keeps the player's settings, and turns kernel events into signals.

signal event(e: Dictionary)
signal command_failed(code: String)
signal away(summary: Dictionary)
## Emitted when a sliced replay of an absence starts (see `sliced_catch_up`); `away` and the
## replay's events follow when it is done.
signal catch_up_started
## Emitted once after every step (tick or command) so panels can refresh.
signal changed

const AUTOSAVE_SECONDS := 30.0
const FLIP_OFFSET := 43200
## The longest frame that counts toward debug fast-forward: at ×600 a 0.15 s frame adds about
## 90 s, so one slow frame never jumps past World.SYNC_OFFLINE_GAP into an offline catch-up.
const FF_MAX_DELTA := 0.15
## With `sliced_catch_up`, the wall-clock time per frame (microseconds) spent replaying an
## absence; the rest of the frame draws the house. Steps run in groups of `CATCH_UP_SLICE`
## between two looks at the clock.
const CATCH_UP_BUDGET_USEC := 24000
const CATCH_UP_SLICE := 8

var world: World
var pack: Pack
var strings: ViewStrings
var load_error := ""
## `clock_skew` is this pack's debug fast-forward (settings.json keeps one per pack); `speed`
## always starts at 1 and is not saved; `hint_seen` is true once the drag hint was shown.
var settings := {"flip_day_night": false, "clock_skew": 0, "speed": 1, "hint_seen": false}
## When true (the game sets it; tests leave it off unless they test it), a long absence found by
## `tick` is replayed a slice per frame instead of all at once, so the house shows straight
## away. Meanwhile `catching_up()` is true, commands fail with "catching_up" and nothing is
## saved; the finished world is the same either way.
var sliced_catch_up := false

var _dir: String
var _real_clock: Callable
## Accumulated debug fast-forward in seconds, kept as a float; `settings.clock_skew` mirrors it.
var _skew := 0.0
var _since_save := 0.0
var _job: CatchUpJob = null


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
		# Settings lost or older than the save: never leave the world ahead of the clock,
		# or every sync would return early until real time caught up.
		var behind := world.now - now_unix()
		if behind > 0:
			_skew += float(behind)
			_write_settings()
	elif err == "missing":
		_create_world()
	else:
		load_error = err
		world = null


## Moves an unreadable save aside (to the first free `.bad`, `.bad2`, ... name; earlier backups
## are never touched) and starts a fresh world. False, with nothing changed, when the old save
## could not be moved.
func new_game() -> bool:
	var path := save_path()
	if FileAccess.file_exists(path):
		var bad := path + ".bad"
		var n := 2
		while FileAccess.file_exists(bad):
			bad = path + ".bad%d" % n
			n += 1
		if DirAccess.rename_absolute(path, bad) != OK:
			return false
	load_error = ""
	_since_save = 0.0
	_create_world()
	return true


func now_unix() -> int:
	return int(_real().unix + _skew)


func utc_offset() -> int:
	var off := int(_real().offset)
	return off + FLIP_OFFSET if settings.flip_day_night else off


## True while a sliced replay of an absence is still running.
func catching_up() -> bool:
	return _job != null


## How far the running replay has got, 0..1 (1 when none runs).
func catch_up_progress() -> float:
	return _job.progress() if _job != null else 1.0


## Game hours the running replay covers (0 when none runs).
func catch_up_hours() -> float:
	return _job.seconds() / 3600.0 if _job != null else 0.0


func tick(delta: float) -> void:
	if not _running():
		return
	if _job != null:
		_run_job(CATCH_UP_BUDGET_USEC)
		changed.emit()
		return
	var speed := int(settings.speed)
	if speed > 1:
		_skew += (speed - 1) * minf(delta, FF_MAX_DELTA)
		settings.clock_skew = int(_skew)
	_sync_and_dispatch(sliced_catch_up)
	changed.emit()
	if _job != null:
		return
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		_since_save = 0.0
		save()


func command(cmd: Dictionary) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "not_running"}
	if _job != null:
		command_failed.emit("catching_up")
		return {"ok": false, "error": "catching_up"}
	if world.phase != "invalid":
		_sync_and_dispatch()
	var r := world.command(cmd)
	if not r.get("ok", false):
		command_failed.emit(str(r.get("error", "")))
	_dispatch_events()
	changed.emit()
	return r


## Writes the settings first, then the world, so a save is never ahead of its clock skew.
func save() -> bool:
	if not _running() or _job != null:
		return false
	_write_settings()
	return SaveStore.save(world, save_path())


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


## Syncs the world to the clock. An absence is replayed at once, or with `sliced` started as
## a job (`_job`) that `tick` carries on frame by frame; its first slice runs now.
func _sync_and_dispatch(sliced := false) -> void:
	var job := world.begin_sync(now_unix(), utc_offset())
	if job == null:
		_dispatch_events()
		return
	if sliced:
		_job = job
		catch_up_started.emit()
		_run_job(CATCH_UP_BUDGET_USEC)
		return
	_finish_job(job)


## Runs the replay for about `budget_usec`; once it is done, finishes it and saves, so a reload
## right after does not replay the same absence again.
func _run_job(budget_usec: int) -> void:
	var t := Time.get_ticks_usec()
	while not _job.run(CATCH_UP_SLICE):
		if Time.get_ticks_usec() - t >= budget_usec:
			return
	var job := _job
	_job = null
	_finish_job(job)
	_since_save = 0.0
	save()


func _finish_job(job: CatchUpJob) -> void:
	var summary := job.finish()
	if float(summary.get("simulated_seconds", 0)) > 0.0:
		away.emit(summary)
	_dispatch_events()


func _dispatch_events() -> void:
	for e in world.drain_events():
		event.emit(e)


func _settings_path() -> String:
	return _dir + "settings.json"


func _read_settings_file() -> Dictionary:
	var path := _settings_path()
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


## The skew of every pack in the file; an old file's top-level `clock_skew` counts as this pack's.
func _skews_in(d: Dictionary) -> Dictionary:
	var out := {}
	var by_pack = d.get("clock_skew_by_pack")
	if by_pack is Dictionary:
		for k in by_pack:
			if typeof(by_pack[k]) in [TYPE_INT, TYPE_FLOAT]:
				out[str(k)] = float(by_pack[k])
	if not out.has(pack.id) and typeof(d.get("clock_skew")) in [TYPE_INT, TYPE_FLOAT]:
		out[pack.id] = float(d["clock_skew"])
	return out


func _load_settings() -> void:
	var d := _read_settings_file()
	if typeof(d.get("flip_day_night")) == TYPE_BOOL:
		settings.flip_day_night = d["flip_day_night"]
	if typeof(d.get("hint_seen")) == TYPE_BOOL:
		settings.hint_seen = d["hint_seen"]
	var skews := _skews_in(d)
	if skews.has(pack.id):
		_skew = float(skews[pack.id])
		settings.clock_skew = int(_skew)


## Writes settings.json through a temporary file and a rename, keeping the other packs' skews
## as they are on disk.
func _write_settings() -> void:
	settings.clock_skew = int(_skew)
	var skews := _skews_in(_read_settings_file())
	if pack.id != "":
		skews[pack.id] = int(_skew)
	var out := {"flip_day_night": settings.flip_day_night, "hint_seen": settings.hint_seen,
		"clock_skew_by_pack": skews}
	var path := _settings_path()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	var written := f.store_string(JSON.stringify(out))
	f.close()
	if not written or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
