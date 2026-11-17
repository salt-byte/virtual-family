class_name Main
extends Node
## Root of the playable scene. Builds the session and every child in code.

## The pack to play when `--pack=<id>` is not given; set in project.godot.
const DEFAULT_PACK_SETTING := "lifesim/default_pack"

var session: GameSession
var house: HouseView
var hud: Hud
var drag: DragController
var overlays: Overlays
## Uid of the selected person; -1 for none.
var selected := -1


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
	house.person_clicked.connect(select)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	drag = DragController.new()
	add_child(drag)
	drag.setup(self)
	house.drag = drag
	overlays = Overlays.new()
	add_child(overlays)
	overlays.setup(self)
	_sync_selection()
	house.refresh()
	hud.refresh()
	overlays.refresh()


func select(uid: int) -> void:
	selected = uid
	_sync_selection()
	_apply_selection()
	if hud != null:
		hud.refresh()


## Keeps `selected` pointing at a living person: when the chosen one is gone, the first
## living person takes over, and with nobody left it is -1. A newcomer (adopted, married in)
## is picked up the same way when nothing was selected.
func _sync_selection() -> void:
	var w := session.world
	var first := -1
	var found := false
	if w != null and w.phase != "invalid":
		for p in w.people:
			if p.alive:
				if first < 0:
					first = p.uid
				if p.uid == selected:
					found = true
	if not found:
		selected = first


func _apply_selection() -> void:
	for uid in house.people:
		house.people[uid].selected = (uid == selected)


func _ready() -> void:
	if session == null:
		_build(pack_from_args(), "user://", Callable())


func tick(delta: float) -> void:
	session.tick(delta)
	_sync_selection()
	house.refresh()
	drag.refresh()
	_apply_selection()
	house.tick(delta)
	hud.refresh()
	hud.tick(delta)
	overlays.refresh()


func _process(delta: float) -> void:
	tick(delta)


func _notification(what: int) -> void:
	if session == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		session.save()
