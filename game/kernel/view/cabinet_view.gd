class_name CabinetView
extends Control
## The keepsake box drawn as a wooden curio cabinet: one shelf per row, the first compartment
## of each shelf holds its paper tag (title and how many are in), the rest one thing each.
## A thing that is in shows its picture (a wrapped bundle until the pack has one), with a
## count badge when there are several; one still missing shows a faint "?" and nothing else.
## Built from the pack's cabinet picture (`PackSkin.cabinet`), else drawn plainly in wood.
## Each thing that is in gets a flat button over it, made by the caller's `make_button`.

## Things per shelf (the tag's compartment comes on top).
const COLUMNS := 6
## On-screen size of the cabinet picture's pixels.
const SCALE := 0.9
## Parts in cabinet pixels when the pack has no cabinet picture.
const PLAIN := {"left": Rect2(0, 0, 26, 114), "cell": Rect2(0, 0, 115, 114), "right": Rect2(0, 0, 26, 114),
	"top": Rect2(0, 0, 532, 30), "bottom": Rect2(0, 0, 532, 26), "edge": 26.0}
## The divider on a compartment's right and the board under it, in cabinet pixels.
const DIVIDER := 13.0
const BOARD := 14.0
const WOOD_DARK := Color("#5A3820")
const WOOD_BACK := Color("#7A4E2C")
const WOOD_EDGE := Color("#A8743F")
const PAPER := Color("#EED9AE")
const STRING := Color("#B8452F")

## {title, progress, slots: [{id, tex, found, count, done}]}; `title` "" hides the title.
var rows: Array = []
var _cab: Dictionary = {}
var _tag: Texture2D
var _font: Font
var _title_font: Font


## Lays the cabinet out for `shelves` and puts a button over every thing that is in.
func setup(shelves: Array, skin: PackSkin, make_button: Callable) -> void:
	rows = shelves
	_cab = skin.cabinet() if skin != null and skin.enabled else {}
	_tag = skin.tag() if skin != null and skin.enabled else null
	_font = load(ViewWidgets.BODY_FONT) if ResourceLoader.exists(ViewWidgets.BODY_FONT) else ThemeDB.fallback_font
	_title_font = ViewWidgets.title_font()
	if _title_font == null:
		_title_font = _font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_part("left").size.x + (COLUMNS + 1) * _part("cell").size.x + _part("right").size.x,
		_part("top").size.y + rows.size() * _part("cell").size.y + _part("bottom").size.y) * SCALE
	for r in rows.size():
		var slots: Array = rows[r]["slots"]
		for i in slots.size():
			var s: Dictionary = slots[i]
			if not s["found"]:
				continue
			var b: Button = make_button.call(str(s["id"]), self)
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for st in ["normal", "pressed", "focus", "disabled"]:
				b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			var hover := StyleBoxFlat.new()
			hover.bg_color = Color(1, 0.95, 0.8, 0.14)
			hover.set_corner_radius_all(6)
			b.add_theme_stylebox_override("hover", hover)
			var rect := slot_rect(r, i + 1)
			b.position = rect.position
			b.size = rect.size


## What the tags say, one line per shelf ("title n / total"); for tests.
func lines() -> Array[String]:
	var out: Array[String] = []
	for r in rows:
		out.append(("%s %s" % [str(r.get("title", "")), str(r.get("progress", ""))]).strip_edges())
	return out


func _part(key: String) -> Rect2:
	return _cab.get(key, PLAIN[key])


## The open inside of compartment `col` (0: the tag's) of shelf `row`, on screen.
func slot_rect(row: int, col: int) -> Rect2:
	var cell := _part("cell").size
	var x := _part("left").size.x + col * cell.x
	var y := _part("top").size.y + row * cell.y
	return Rect2(Vector2(x + 2.0, y + 4.0) * SCALE, Vector2(cell.x - DIVIDER - 4.0, cell.y - BOARD - 6.0) * SCALE)


func _draw() -> void:
	var tex: Texture2D = _cab.get("tex")
	var cell := _part("cell").size * SCALE
	var lw := _part("left").size.x * SCALE
	var rw := _part("right").size.x * SCALE
	var top_h := _part("top").size.y * SCALE
	var w := size.x
	_band("top", Rect2(0, 0, w, top_h), tex)
	for r in rows.size():
		var y := top_h + r * cell.y
		if tex != null:
			draw_texture_rect_region(tex, Rect2(0, y, lw, cell.y), _part("left"))
			for c in COLUMNS + 1:
				draw_texture_rect_region(tex, Rect2(lw + c * cell.x, y, cell.x, cell.y), _part("cell"))
			draw_texture_rect_region(tex, Rect2(w - rw, y, rw, cell.y), _part("right"))
		else:
			_plain_row(y, cell, lw, rw, w)
		_tag_at(r)
		var slots: Array = rows[r]["slots"]
		for i in slots.size():
			_thing(slot_rect(r, i + 1), slots[i])
	_band("bottom", Rect2(0, top_h + rows.size() * cell.y, w, _part("bottom").size.y * SCALE), tex)


## The cornice or the base: its corners as they are, the middle stretched.
func _band(key: String, at: Rect2, tex: Texture2D) -> void:
	if tex == null:
		draw_rect(at, WOOD_EDGE)
		draw_rect(Rect2(at.position + Vector2(0, at.size.y - 4), Vector2(at.size.x, 4)), WOOD_DARK)
		return
	var src := _part(key)
	var e := float(_cab.get("edge", 0.0))
	var es := e * SCALE
	draw_texture_rect_region(tex, Rect2(at.position, Vector2(es, at.size.y)), Rect2(src.position, Vector2(e, src.size.y)))
	draw_texture_rect_region(tex, Rect2(at.position + Vector2(es, 0), Vector2(at.size.x - 2 * es, at.size.y)),
		Rect2(src.position + Vector2(e, 0), Vector2(src.size.x - 2 * e, src.size.y)))
	draw_texture_rect_region(tex, Rect2(at.position + Vector2(at.size.x - es, 0), Vector2(es, at.size.y)),
		Rect2(src.position + Vector2(src.size.x - e, 0), Vector2(e, src.size.y)))


func _plain_row(y: float, cell: Vector2, lw: float, rw: float, w: float) -> void:
	draw_rect(Rect2(0, y, lw, cell.y), WOOD_EDGE)
	draw_rect(Rect2(w - rw, y, rw, cell.y), WOOD_EDGE)
	for c in COLUMNS + 1:
		var x := lw + c * cell.x
		draw_rect(Rect2(x, y, cell.x, cell.y), WOOD_BACK)
		draw_rect(Rect2(x, y, cell.x, 6 * SCALE), WOOD_DARK)
		draw_rect(Rect2(x + cell.x - DIVIDER * SCALE, y, DIVIDER * SCALE, cell.y), WOOD_EDGE)
		draw_rect(Rect2(x, y + cell.y - BOARD * SCALE, cell.x, BOARD * SCALE), WOOD_EDGE)


## The paper tag in the shelf's first compartment: the title (when known) over "n / total".
func _tag_at(r: int) -> void:
	var at := slot_rect(r, 0)
	var box := Rect2(at.position + Vector2(0, at.size.y * 0.22), Vector2(at.size.x, at.size.y * 0.62))
	if _tag != null:
		draw_texture_rect(_tag, box, false)
	else:
		draw_rect(box, PAPER)
		draw_rect(box, WOOD_DARK, false, 1.5)
	var left := box.position.x + box.size.x * 0.2
	var width := box.size.x * 0.76
	var title := str(rows[r].get("title", ""))
	var progress := str(rows[r].get("progress", ""))
	var ink := ViewWidgets.INK
	if title != "":
		var fs := 15 if title.length() <= 4 else 12
		draw_string(_title_font, Vector2(left, box.position.y + box.size.y * 0.45), title, HORIZONTAL_ALIGNMENT_CENTER, width, fs, ink)
	draw_string(_font, Vector2(left, box.position.y + box.size.y * (0.82 if title != "" else 0.62)), progress,
		HORIZONTAL_ALIGNMENT_CENTER, width, 12, ink if title != "" else ViewWidgets.MUTED)


## One compartment's thing: its picture standing on the board, a bundle without one, a faint
## "?" while it is missing; a badge with the count when there are several.
func _thing(at: Rect2, s: Dictionary) -> void:
	if not s["found"]:
		draw_string(_title_font, Vector2(at.position.x, at.position.y + at.size.y * 0.66), "?",
			HORIZONTAL_ALIGNMENT_CENTER, at.size.x, int(at.size.y * 0.5), Color(1, 0.94, 0.8, 0.22))
		return
	var tex: Texture2D = s.get("tex")
	var inner := at.grow(-5.0)
	if tex != null:
		var k := minf(inner.size.x / tex.get_width(), inner.size.y / tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * k
		var pos := Vector2(inner.position.x + (inner.size.x - sz.x) / 2.0, inner.end.y - sz.y)
		draw_rect(Rect2(pos + Vector2(sz.x * 0.1, sz.y - 3), Vector2(sz.x * 0.8, 4)), Color(0, 0, 0, 0.18))
		draw_texture_rect(tex, Rect2(pos, sz), false)
	else:
		bundle(self, inner)
	var n := int(s.get("count", 1))
	if n > 1:
		var badge := "×%d" % n
		var bw := 12.0 + 8.0 * badge.length()
		var br := Rect2(Vector2(at.end.x - bw - 2, at.position.y + 2), Vector2(bw, 20))
		var st := ViewWidgets.chip_style(ViewWidgets.CREAM, ViewWidgets.WOOD)
		st.set_corner_radius_all(10)
		draw_style_box(st, br)
		draw_string(_font, Vector2(br.position.x, br.position.y + 15), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, 13, ViewWidgets.INK)


## A cloth bundle tied with red string: the stand-in for a thing that has no picture yet.
static func bundle(ci: CanvasItem, at: Rect2) -> void:
	var s := minf(at.size.x, at.size.y) * 0.8
	var c := Vector2(at.get_center().x, at.end.y - s * 0.42)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.42, s * 0.36), Vector2(s * 0.84, 4)), Color(0, 0, 0, 0.18))
	var body := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		body.append(c + Vector2(cos(a) * s * 0.44, sin(a) * s * 0.36))
	ci.draw_colored_polygon(body, PAPER)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), Color("#8A5A36"), 1.5)
	var knot := c + Vector2(0, -s * 0.36)
	ci.draw_colored_polygon(PackedVector2Array([knot, knot + Vector2(-s * 0.16, -s * 0.14), knot + Vector2(-s * 0.04, 0)]), PAPER.darkened(0.08))
	ci.draw_colored_polygon(PackedVector2Array([knot, knot + Vector2(s * 0.16, -s * 0.14), knot + Vector2(s * 0.04, 0)]), PAPER.darkened(0.08))
	ci.draw_line(knot, c + Vector2(0, s * 0.36), STRING, 2.0)
	ci.draw_line(c + Vector2(-s * 0.44, 0), c + Vector2(s * 0.44, 0), STRING, 2.0)
	ci.draw_circle(knot, 3.0, STRING)
