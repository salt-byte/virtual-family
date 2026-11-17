class_name ViewWidgets
extends RefCounted
## The small look shared by the pop-up panels and the furniture catalogue: the dark card, and
## the label and row cells of a list. Static helpers only; nothing here knows what is shown.

const PRICE_WIDTH := 80.0


static func card_style(margin: float) -> StyleBoxFlat:
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.13, 0.12, 0.11, 1.0)
	card.set_corner_radius_all(8)
	card.set_content_margin_all(margin)
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
