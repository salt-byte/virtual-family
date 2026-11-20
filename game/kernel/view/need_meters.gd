class_name NeedMeters
extends Control
## The selected one's needs at a glance, in the bottom bar: one short bar per need with its
## short name above it (a need's `short` in needs.json, else its `name`). A full bar is sage;
## as it empties it turns toward tomato, and the lowest one, once it is below `CALM`, pulses so
## the eye goes to what they need. Draws itself; knows no theme words.

const BAR_W := 46.0
const BAR_H := 9.0
const GAP := 9.0
const LABEL_SIZE := 12
## Above this a need is fine: sage, still. The colour runs to tomato by `LOW`.
const CALM := 60.0
const LOW := 25.0
const FULL := Color("#7FA36A")
const PULSE_PERIOD := 0.9

## [{id, name, value (0..100)}] in pack order.
var entries: Array = []
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Shows `p`'s needs (the pack's, in pack order).
func show_person(p: Person, pack: Pack) -> void:
	var out: Array = []
	for nid in pack.needs:
		if not p.needs.has(nid):
			continue
		var n: Dictionary = pack.needs[nid]
		out.append({"id": str(nid), "name": str(n.get("short", n.get("name", nid))), "value": float(p.needs[nid])})
	set_entries(out)


func set_entries(list: Array) -> void:
	entries = list
	custom_minimum_size = Vector2(maxf(entries.size() * (BAR_W + GAP) - GAP, 0.0), 34.0)
	queue_redraw()


## The id of the need that pulses now ("" when every need is above `CALM`).
func pulsing() -> String:
	var low := ""
	var lv := CALM
	for e in entries:
		if float(e["value"]) < lv:
			lv = float(e["value"])
			low = str(e["id"])
	return low


## The colour of a bar at `v`: sage above `CALM`, tomato at `LOW` and under.
static func color_at(v: float) -> Color:
	if v >= CALM:
		return FULL
	return FULL.lerp(ViewWidgets.ACCENT, clampf((CALM - v) / (CALM - LOW), 0.0, 1.0))


func _process(delta: float) -> void:
	_t += delta
	if pulsing() != "":
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var low := pulsing()
	var x := 0.0
	for e in entries:
		var v := clampf(float(e["value"]), 0.0, 100.0)
		var col := color_at(v)
		var name := str(e["name"])
		var lift := 0.0
		var ink := ViewWidgets.INK if v >= CALM else col.darkened(0.25)
		if str(e["id"]) == low:
			var k := 0.5 + 0.5 * sin(TAU * _t / PULSE_PERIOD)
			lift = -1.5 * k
			col = col.lerp(Color.WHITE, 0.25 * k)
		var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		draw_string(font, Vector2(x + (BAR_W - tw) * 0.5, 13.0 + lift), name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, ink)
		var r := Rect2(Vector2(x, 19.0 + lift), Vector2(BAR_W, BAR_H))
		var back := StyleBoxFlat.new()
		back.bg_color = ViewWidgets.PALE
		back.border_color = ViewWidgets.INK
		back.set_border_width_all(2 if str(e["id"]) == low else 1)
		back.set_corner_radius_all(4)
		draw_style_box(back, r.grow(1.0))
		if v > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = col
			fill.set_corner_radius_all(3)
			draw_style_box(fill, Rect2(r.position, Vector2(maxf(r.size.x * v / 100.0, 4.0), r.size.y)))
		x += BAR_W + GAP


## A small drawn face for the mood beside the name: a smile at `value` 65 and up, a straight
## mouth from 35, a frown below.
class Face:
	extends Control
	var value := 70.0:
		set(v):
			value = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, Color("#FFD98A") if value >= 35.0 else Color("#F3C9A8"))
		draw_arc(c, r, 0.0, TAU, 20, ViewWidgets.INK, 1.4, true)
		draw_circle(c + Vector2(-r * 0.38, -r * 0.2), 1.3, ViewWidgets.INK)
		draw_circle(c + Vector2(r * 0.38, -r * 0.2), 1.3, ViewWidgets.INK)
		var m := c + Vector2(0, r * 0.35)
		if value >= 65.0:
			draw_arc(m + Vector2(0, -r * 0.25), r * 0.42, 0.35, PI - 0.35, 8, ViewWidgets.INK, 1.4, true)
		elif value >= 35.0:
			draw_line(m + Vector2(-r * 0.35, 0), m + Vector2(r * 0.35, 0), ViewWidgets.INK, 1.4)
		else:
			draw_arc(m + Vector2(0, r * 0.3), r * 0.42, PI + 0.35, TAU - 0.35, 8, ViewWidgets.INK, 1.4, true)
