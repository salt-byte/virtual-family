class_name ViewWidgets
extends RefCounted
## The small look shared by the bar, the pop-up panels, the cards and the furniture catalogue
## (ART_DIRECTION section 4: cream ground, wooden frame, dark brown ink), and the label and row
## cells of a list. Static helpers only; nothing here knows what is shown.

const PRICE_WIDTH := 80.0


## A pop-up card: cream inside a wooden frame, rounded, with a soft shadow. Opaque.
static func card_style(margin: float) -> StyleBoxFlat:
	var card := StyleBoxFlat.new()
	card.bg_color = CREAM
	card.border_color = WOOD
	card.set_border_width_all(6 if margin >= 16.0 else 3)
	card.set_corner_radius_all(18 if margin >= 16.0 else 12)
	card.set_content_margin_all(margin)
	card.shadow_color = Color(0.29, 0.2, 0.14, 0.35)
	card.shadow_size = 10
	card.shadow_offset = Vector2(0, 4)
	return card


## A single-line label at its natural width.
static func label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


## A label that may wrap; it fills the width it gets and never asks for more than 100.
static func wrapped(t: String) -> Label:
	var l := label(t)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 100.0
	return l


## The left, expanding cell of a row: one line, ellipsis when too long.
static func name_label(t: String) -> Label:
	var l := label(t)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


static func price_label(t: String) -> Label:
	var l := label(t)
	l.custom_minimum_size.x = PRICE_WIDTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	parent.add_child(r)
	return r


## The cream-and-wood look of the always-on bar (ART_DIRECTION section 4): cream ground,
## dark brown outline and text, warm yellow buttons with a darker "thickness" under them.
const CREAM := Color("#FFF4DF")
const WOOD := Color("#8A5A36")
const INK := Color("#4A3424")
const BUTTON := Color("#FFE3B0")
const ACCENT := Color("#E5533C")
const SKY := Color("#4FB3E8")
## Quiet text: captions, words for things that are fine.
const MUTED := Color("#9A8672")
## The ground of a chip or a small button that holds nothing to worry about.
const PALE := Color("#F3E6CC")


static func bar_style() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = CREAM
	b.border_color = WOOD
	b.border_width_top = 4
	b.corner_radius_top_left = 18
	b.corner_radius_top_right = 18
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 10
	b.content_margin_bottom = 8
	return b


static func button_style(bg: Color, down := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = INK
	b.set_border_width_all(2)
	b.border_width_bottom = 2 if down else 5
	b.set_corner_radius_all(12)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 6 if not down else 9
	b.content_margin_bottom = 6
	return b


## A theme for the bar, the praise/scold buttons and the toasts.
static func hud_theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 15)
	t.set_stylebox("normal", "Button", button_style(BUTTON))
	t.set_stylebox("hover", "Button", button_style(BUTTON.lightened(0.25)))
	t.set_stylebox("pressed", "Button", button_style(BUTTON.darkened(0.08), true))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", button_style(Color(0.9, 0.88, 0.84)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.62, 0.6, 0.57))
	t.set_font_size("font_size", "Button", 16)
	t.set_stylebox("panel", "PanelContainer", bar_style())
	return t


## The theme of the pop-up panels and cards: the bar's buttons and ink, the cream card, and
## readable sizes for lists.
static func panel_theme() -> Theme:
	var t := hud_theme()
	t.set_font_size("font_size", "Label", 16)
	t.set_stylebox("panel", "PanelContainer", card_style(24.0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "CheckButton", INK)
		t.set_color(k, "CheckBox", INK)
	return t


## A small rounded tag (a status word): `bg` ground, `edge` outline (none when transparent).
static func chip_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(0 if edge.a == 0.0 else 2)
	b.set_corner_radius_all(12)
	b.content_margin_left = 9
	b.content_margin_right = 9
	b.content_margin_top = 1
	b.content_margin_bottom = 1
	return b


## A secondary button: smaller and flatter than the main ones, the same ink.
static func small_button(b: Button) -> void:
	var grounds := {"normal": PALE, "hover": PALE.lightened(0.3), "pressed": PALE.darkened(0.06),
		"disabled": Color(0.9, 0.88, 0.84)}
	for state in grounds:
		var s := StyleBoxFlat.new()
		s.bg_color = grounds[state]
		s.border_color = WOOD
		s.set_border_width_all(1)
		s.border_width_bottom = 1 if state == "pressed" else 3
		s.set_corner_radius_all(9)
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 1
		s.content_margin_bottom = 1
		b.add_theme_stylebox_override(state, s)
	b.add_theme_font_size_override("font_size", 14)


## A round button (the praise / scold pair in the corner): `bg` fill, an INK ring.
static func round_button(b: Button, bg: Color, ink: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = bg if state != "disabled" else Color(0.9, 0.88, 0.84)
		if state == "hover":
			s.bg_color = bg.lightened(0.15)
		s.border_color = INK
		s.set_border_width_all(2)
		s.border_width_bottom = 2 if state == "pressed" else 4
		s.set_corner_radius_all(24)
		s.set_content_margin_all(8)
		s.content_margin_left = 12
		s.content_margin_right = 12
		b.add_theme_stylebox_override(state, s)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ink)
	b.custom_minimum_size = Vector2(46, 46)
