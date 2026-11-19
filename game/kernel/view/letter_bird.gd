class_name LetterBird
extends Control
## The carrier bird drawn in shapes (no picture needed): a grey-blue bird with a little tube
## tied to its leg and, while it sits, a badge with the number of letters waiting. Flaps
## while flying, bobs its head while sitting, hops when another letter comes. Clicked, it
## emits `pressed`. `feet` is the screen point it stands on.

signal pressed

const SIZE := Vector2(72, 64)
## Where the feet are inside the control (unscaled).
const FEET := Vector2(34, 58)
const BODY := Color("#9EA8BA")
const WING := Color("#C9CFDA")
const BAR := Color("#6F7891")
const NECK := Color("#7FA394")
const HEAD := Color("#8E98AC")
const BEAK := Color("#E9C79C")
const EYE := Color("#E58A2C")
const FOOT := Color("#D97A7C")
const TUBE := Color("#C9A35A")
const TUBE_BAND := Color("#6E8B3D")
const STRING := Color("#C8463A")

var feet := Vector2.ZERO:
	set(v):
		feet = v
		position = v - FEET * scale
var flying := false
var count := 0
var _t := 0.0
var _hop := 0.0


func _init() -> void:
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = Vector2.ZERO


func tick(delta: float) -> void:
	_t += delta
	_hop = maxf(_hop - delta * 3.0, 0.0)
	queue_redraw()


## A little jump on the spot (another letter came while it sits).
func hop() -> void:
	_hop = 1.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		pressed.emit()


func _ellipse(c: Vector2, r: Vector2, fill: Color, line := true, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	draw_colored_polygon(pts, fill)
	if line:
		pts.append(pts[0])
		draw_polyline(pts, ViewWidgets.INK, 2.0, true)


func _draw() -> void:
	var lift := -sin(_hop * PI) * 10.0
	var bob := 0.0 if flying else sin(_t * 3.0) * 1.2
	var o := Vector2(0, lift)
	# Shadow on the wall top while sitting.
	if not flying:
		_ellipse(FEET + Vector2(0, 2), Vector2(16, 3), Color(0, 0, 0, 0.18), false)
	# Legs and the tube.
	if not flying:
		for dx in [-4.0, 4.0]:
			draw_line(o + Vector2(32 + dx, 46), o + Vector2(32 + dx, 57), FOOT, 2.5)
			draw_line(o + Vector2(32 + dx, 57), o + Vector2(36 + dx, 58), FOOT, 2.0)
	var tube := Rect2(o + Vector2(24, 44), Vector2(7, 12)) if not flying else Rect2(o + Vector2(28, 46), Vector2(12, 6))
	draw_rect(tube, TUBE)
	draw_rect(tube, ViewWidgets.INK, false, 1.5)
	if not flying:
		draw_line(tube.position + Vector2(0, 4), tube.position + Vector2(7, 4), TUBE_BAND, 1.5)
		draw_line(tube.position + Vector2(0, 8), tube.position + Vector2(7, 8), TUBE_BAND, 1.5)
		draw_line(tube.position + Vector2(-1, 2), tube.position + Vector2(9, 2), STRING, 1.5)
	# Tail.
	draw_colored_polygon(PackedVector2Array([o + Vector2(14, 36), o + Vector2(2, 44), o + Vector2(6, 48), o + Vector2(18, 42)]), BAR)
	draw_polyline(PackedVector2Array([o + Vector2(14, 36), o + Vector2(2, 44), o + Vector2(6, 48), o + Vector2(18, 42)]), ViewWidgets.INK, 2.0, true)
	# Body.
	_ellipse(o + Vector2(30, 36), Vector2(17, 12), BODY)
	# Wing: folded while sitting, beating while flying.
	if flying:
		var beat := sin(_t * 18.0)
		var tip := o + Vector2(20, 22 - beat * 18.0)
		var wing := PackedVector2Array([o + Vector2(22, 32), tip, o + Vector2(40, 30 - beat * 10.0), o + Vector2(38, 34)])
		draw_colored_polygon(wing, WING)
		wing.append(wing[0])
		draw_polyline(wing, ViewWidgets.INK, 2.0, true)
	else:
		_ellipse(o + Vector2(27, 35), Vector2(12, 7), WING, true, 0.18)
		draw_line(o + Vector2(20, 34), o + Vector2(30, 36), BAR, 2.0)
		draw_line(o + Vector2(21, 38), o + Vector2(31, 40), BAR, 2.0)
	# Neck and head.
	_ellipse(o + Vector2(42, 28 + bob * 0.5), Vector2(7, 8), NECK)
	var h := o + Vector2(46, 18 + bob)
	_ellipse(h, Vector2(8, 7), HEAD)
	draw_colored_polygon(PackedVector2Array([h + Vector2(6, -1), h + Vector2(14, 2), h + Vector2(6, 3)]), BEAK)
	draw_polyline(PackedVector2Array([h + Vector2(6, -1), h + Vector2(14, 2), h + Vector2(6, 3)]), ViewWidgets.INK, 1.5, true)
	draw_circle(h + Vector2(2, -2), 2.4, EYE)
	draw_circle(h + Vector2(2.4, -2), 1.1, ViewWidgets.INK)
	# Letters waiting: a badge over its head.
	if count > 0 and not flying:
		var at := o + Vector2(60, 8)
		draw_circle(at, 10.0, ViewWidgets.ACCENT)
		draw_arc(at, 10.0, 0.0, TAU, 24, ViewWidgets.INK, 2.0, true)
		var font := get_theme_default_font()
		var t := str(count) if count < 10 else "9+"
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 13).x
		draw_string(font, at + Vector2(-w * 0.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
