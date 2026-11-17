class_name Main
extends Node
## Root of the playable scene. Builds the session and every child in code.

## The pack to play when `--pack=<id>` is not given; set in project.godot.
const DEFAULT_PACK_SETTING := "lifesim/default_pack"

var session: GameSession
var house: HouseView


static func create(pack_id: String, dir := "user://", real_clock := Callable()) -> Main:
	var m := Main.new()
	m._build(pack_id, dir, real_clock)
	return m


static func pack_from_args() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			return a.substr(7)
	return str(ProjectSettings.get_setting(DEFAULT_PACK_SETTING, ""))


func _build(pack_id: String, dir: String, real_clock: Callable) -> void:
	session = GameSession.new(pack_id, dir, real_clock)
	session.start()
	house = HouseView.new()
	add_child(house)
	house.setup(session)
	house.refresh()


func _ready() -> void:
	if session == null:
		_build(pack_from_args(), "user://", Callable())


func tick(delta: float) -> void:
	session.tick(delta)
	house.refresh()
	house.tick(delta)


func _process(delta: float) -> void:
	tick(delta)


func _notification(what: int) -> void:
	if session == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		session.save()
