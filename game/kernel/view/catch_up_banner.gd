class_name CatchUpBanner
extends CanvasLayer
## While the session replays an absence a slice per frame (`GameSession.catching_up`): a small
## cream line at the top, "正在补上你不在时的日子…" with how far it has got, over a clear sheet
## that takes every click and wheel turn, so nothing can be done to the house until it is over.

const LAYER := 20

var session: GameSession
var _sheet: Control
var _label: Label


func setup(s: GameSession) -> void:
	session = s
	layer = LAYER
	_sheet = Control.new()
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet)
	var pill := PanelContainer.new()
	pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.position.y = 18
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := ViewWidgets.chip_style(ViewWidgets.CREAM, ViewWidgets.WOOD)
	style.set_corner_radius_all(18)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0.29, 0.2, 0.14, 0.3)
	style.shadow_size = 6
	pill.add_theme_stylebox_override("panel", style)
	_sheet.add_child(pill)
	_label = Label.new()
	_label.add_theme_color_override("font_color", ViewWidgets.INK)
	_label.add_theme_font_size_override("font_size", 20)
	ViewWidgets.use_title_font(_label)
	pill.add_child(_label)
	refresh()


func refresh() -> void:
	var on := session != null and session.catching_up()
	visible = on
	if on:
		_label.text = "%s  %d%%" % [session.strings.t("away.catching_up"), int(session.catch_up_progress() * 100.0)]


## True while the replay runs; the house ignores input then.
func blocks_input() -> bool:
	return visible
