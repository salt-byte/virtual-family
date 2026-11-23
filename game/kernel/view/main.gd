class_name Main
extends Node
## Root of the playable scene. Builds the session and every child in code.

## The pack to play when `--pack=<id>` is not given; set in project.godot.
const DEFAULT_PACK_SETTING := "lifesim/default_pack"

var session: GameSession
var house: HouseView
var weather: WeatherView
var hud: Hud
var drag: DragController
var overlays: Overlays
var panels: Panels
var arrange: ArrangeMode
var settings: SettingsPanel
var letters: LetterView
var catch_up: CatchUpBanner
## Uid of the selected person; -1 for none.
var selected := -1
## Uid of the selected animal (-1: none); while one is selected the bar shows it.
var selected_pet := -1
## True from a real start (`_ready`) until the first frame has run: load phases are logged.
var _log_load := false
## Frames, and the microseconds `tick` took in them, while a replay ran (logged at its end).
var _cu_frames := 0
var _cu_usec := 0


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
	house.pet_clicked.connect(select_pet)
	weather = WeatherView.new()
	add_child(weather)
	weather.setup(session)
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
	panels = Panels.new()
	add_child(panels)
	panels.setup(self)
	arrange = ArrangeMode.new()
	add_child(arrange)
	arrange.setup(self)
	house.arrange = arrange
	settings = SettingsPanel.new()
	add_child(settings)
	settings.setup(self)
	letters = LetterView.new()
	add_child(letters)
	letters.setup(self)
	catch_up = CatchUpBanner.new()
	add_child(catch_up)
	catch_up.setup(session)
	hud.open.connect(_on_hud_open)
	house.blocked = is_house_blocked
	_sync_selection()
	house.refresh()
	hud.refresh()
	overlays.refresh()
	panels.refresh()
	arrange.refresh()
	settings.refresh()


## "arrange" toggles arrange mode; any panel button leaves it first.
func _on_hud_open(what: String) -> void:
	if what == "arrange":
		if arrange.active:
			arrange.exit()
		else:
			arrange.enter()
		return
	arrange.exit()
	letters.close()
	if what == "letters":
		panels.close()
		settings.close()
		letters.open_box()
		return
	if what == "settings":
		panels.close()
		settings.open()
		return
	settings.close()
	panels.open(what)


## A click on a "waiting for you" notice (`Notices`): opens the card that answers it, or
## takes the view to whoever it is about. Whatever covered the house is put away first.
func open_notice(n: Dictionary) -> void:
	var t := int(n.get("target", -1))
	var kind := str(n.get("kind", ""))
	arrange.exit()
	settings.close()
	panels.close()
	if not kind in ["letter", "reply", "letters"]:
		letters.close()
	match kind:
		"proposal":
			overlays.open_proposal(t)
		"stray":
			overlays.open_stray()
		"buyer":
			overlays.open_buyer()
		"letter", "reply":
			letters.open_letter(t)
		"letters":
			letters.open_box()
		"ill", "need", "thanks", "wish", "ask":
			select(t)
		"pet_ill", "pet_hungry":
			select_pet(t)
		"pet_away":
			panels.open("family")
		"pickup", "pickups":
			house.look_at_collectible(t)
	# Then point at what answers it: the button to press, where to take them, the market.
	if hud != null:
		hud.guide(n.get("guide", {}))


## True while an overlay, a panel or the build confirmation covers the house; the house then
## ignores input.
func is_house_blocked() -> bool:
	return catch_up.blocks_input() or overlays.blocks_input() or panels.blocks_input() \
		or arrange.blocks_input() \
		or settings.blocks_input() or letters.blocks_input()


## An explicit choice (a click on a person, the family panel): also makes the view follow
## them unless `follow` is false (the bar's switcher, for someone away on an outing). The
## automatic pick in `_sync_selection` does not.
func select(uid: int, follow := true) -> void:
	selected_pet = -1
	selected = uid
	_sync_selection()
	if follow and selected == uid and uid >= 0:
		house.follow(uid)
	_apply_selection()
	if hud != null:
		hud.refresh()


## Shows an animal of the house in the bar (its status, what it does, what it wants).
func select_pet(uid: int) -> void:
	var pet := PetSystem.find(session.world, uid) if session.world != null else null
	selected_pet = uid if pet != null and pet.home() else -1
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
	if selected_pet >= 0:
		var pet := PetSystem.find(w, selected_pet) if w != null and w.phase != "invalid" else null
		if pet == null or not pet.home():
			selected_pet = -1


func _apply_selection() -> void:
	for uid in house.people:
		house.people[uid].selected = (uid == selected and selected_pet < 0)
	for uid in house.pets:
		house.pets[uid].selected = (uid == selected_pet)


func _ready() -> void:
	if session == null:
		_log_load = true
		DebugAway.log("main_ready")
		var dir := "user://"
		var away := DebugAway.hours()
		if away > 0.0:
			dir = DebugAway.DIR
			DebugAway.seed_save(pack_from_args(), away)
		_build(pack_from_args(), dir, Callable())
		session.sliced_catch_up = true
		session.catch_up_started.connect(func():
			DebugAway.log("catchup_start hours=%.1f" % session.catch_up_hours()))
		session.away.connect(func(summary: Dictionary):
			DebugAway.log("catchup_done simulated_h=%.1f frames=%d avg_tick_ms=%.1f" % [
				float(summary.simulated_seconds) / 3600.0, _cu_frames,
				float(_cu_usec) / 1000.0 / maxf(1.0, float(_cu_frames))]))
		DebugAway.log("built")


## While an absence is being replayed (`GameSession.catching_up`) only the session and the
## "catching up" line move: the house stays as it was left, so the frame's time goes to the
## replay, and everything catches up at once when it is done.
func tick(delta: float) -> void:
	session.tick(delta)
	if session.catching_up():
		catch_up.refresh()
		return
	_sync_selection()
	house.refresh()
	drag.refresh()
	_apply_selection()
	house.tick(delta)
	weather.refresh()
	weather.tick(delta)
	hud.refresh()
	hud.tick(delta)
	overlays.refresh()
	panels.refresh()
	arrange.refresh()
	settings.refresh()
	letters.refresh()
	letters.tick(delta)
	catch_up.refresh()


func _process(delta: float) -> void:
	if _log_load:
		var t := Time.get_ticks_usec()
		tick(delta)
		_log_load = false
		DebugAway.log("first_tick_done tick_ms=%.0f" % (float(Time.get_ticks_usec() - t) / 1000.0))
		return
	if session.catching_up():
		var t := Time.get_ticks_usec()
		tick(delta)
		_cu_frames += 1
		_cu_usec += Time.get_ticks_usec() - t
		return
	tick(delta)


func _notification(what: int) -> void:
	if session == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		session.save()
