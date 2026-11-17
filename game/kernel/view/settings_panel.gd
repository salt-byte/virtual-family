class_name SettingsPanel
extends CanvasLayer
## The settings card: day/night flip, debug fast-forward and the in-game clock. Also owns the
## small speed marker at the top right, shown whenever the speed is above 1, panel open or not.

const LAYER := 6
const PANEL_WIDTH := 420.0
const MARGIN := 24.0
const SPEEDS := [1, 60, 600]

var main: Main
var session: GameSession

var _root: Control
var _box: VBoxContainer
var _marker: Label
var _clock: Label
var _buttons: Dictionary = {}  # id -> Button
var _open := false
var _signature := ""


func setup(m: Main) -> void:
	main = m
	session = m.session
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	panel.add_theme_stylebox_override("panel", ViewWidgets.card_style(MARGIN))
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	_marker = Label.new()
	_marker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_marker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_marker.offset_top = 8.0
	_marker.offset_right = -12.0
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_marker.visible = false
	add_child(_marker)


func opened() -> bool:
	return _open


func blocks_input() -> bool:
	return _open


## The speed marker ("×60"); empty at speed 1.
func marker_text() -> String:
	var sp := int(session.settings.speed)
	return "×%d" % sp if sp > 1 else ""


## Opens the card; ignored while an overlay shows. Other panels and arrange mode are left
## by the caller (Main).
func open() -> void:
	if main.overlays.current() != "":
		return
	_open = true
	_signature = ""
	refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_signature = ""
	_rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func text() -> String:
	var parts: Array[String] = []
	_collect(_box, parts)
	return "\n".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label or c is Button:
			out.append(c.text)
		_collect(c, out)


func button(id: String) -> Button:
	return _buttons.get(id)


func has_button(id: String) -> bool:
	return _buttons.has(id)


## Test entry point and button handler: "flip", "speed:<n>" or "btn.close".
func press(id: String) -> void:
	if id == "btn.close":
		close()
	elif id == "flip":
		session.set_setting("flip_day_night", not bool(session.settings.flip_day_night))
		refresh()
	elif id.begins_with("speed:"):
		var n := int(id.substr(6))
		if n in SPEEDS:
			session.set_setting("speed", n)
			refresh()


func refresh() -> void:
	var mk := marker_text()
	_marker.text = mk
	_marker.visible = mk != ""
	if not _open:
		return
	if main.overlays.current() != "":
		close()
		return
	var clock := _clock_text()
	var sig := "%s|%s|%s" % [session.settings.flip_day_night, session.settings.speed, clock != ""]
	if sig != _signature:
		_signature = sig
		_rebuild()
	elif _clock != null:
		_clock.text = session.strings.t("set.clock").replace("{t}", clock)


## "HH:MM" of the in-game time; empty without a living world.
func _clock_text() -> String:
	var w := session.world
	if w == null or w.phase != "living":
		return ""
	var minutes := int(roundf(w.local_hour() * 60.0)) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_clock = null
	_root.visible = _open
	if not _open:
		return
	var s := session.strings
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := ViewWidgets.label(s.t("btn.settings"))
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_button("btn.close", s.t("btn.close"), head)
	var clock := _clock_text()
	if clock != "":
		_clock = ViewWidgets.label(s.t("set.clock").replace("{t}", clock))
		_box.add_child(_clock)
	var flip := CheckButton.new()
	flip.text = s.t("set.flip")
	flip.set_pressed_no_signal(bool(session.settings.flip_day_night))
	flip.pressed.connect(press.bind("flip"))
	_box.add_child(flip)
	_buttons["flip"] = flip
	_box.add_child(ViewWidgets.label(s.t("set.speed")))
	var row := ViewWidgets.row(_box)
	for sp in SPEEDS:
		var b := _button("speed:%d" % sp, "×%d" % sp, row)
		b.disabled = int(session.settings.speed) == sp
	_box.add_child(ViewWidgets.wrapped(s.t("set.debug_note")))


func _button(id: String, label: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(press.bind(id))
	parent.add_child(b)
	_buttons[id] = b
	return b
