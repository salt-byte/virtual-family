class_name HudIcon
extends Control
## A small drawn icon for the bar's buttons, the resources and the notices: flat warm fills
## inside the dark brown outline (ART_DIRECTION section 4: the same hand as the props, no
## line icons). Draws into its own size; nothing here knows the theme's words.

const INK := ViewWidgets.INK
const FILL := ViewWidgets.BUTTON
const GOLD := Color("#E8B64A")
const LINE := 2.0
## Every kind it can draw.
const KINDS := ["family", "shop", "ledger", "stories", "arrange", "settings", "letters", "coin",
	"grain", "sky", "proposal", "stray", "reply", "thanks", "need", "ill", "wish", "pet_away",
	"pickup", "letter"]

var kind := "":
	set(v):
		kind = v
		queue_redraw()


static func make(k: String, side := 22.0) -> HudIcon:
	var i := HudIcon.new()
	i.kind = k
	i.custom_minimum_size = Vector2(side, side)
	i.size = Vector2(side, side)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return i


func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_set_transform(Vector2((size.x - 24.0 * s) * 0.5, (size.y - 24.0 * s) * 0.5), 0.0, Vector2(s, s))
	match kind:
		"family":
			_disc(Vector2(8, 8), 4.0, FILL)
			_disc(Vector2(16.5, 9.5), 3.4, FILL)
			_shape([Vector2(2, 21), Vector2(3, 15), Vector2(8, 13), Vector2(13, 15), Vector2(14, 21)], FILL)
			_shape([Vector2(12, 21), Vector2(13, 16), Vector2(16.5, 14.5), Vector2(20.5, 16), Vector2(21.5, 21)], FILL)
		"shop":
			_shape([Vector2(3, 10), Vector2(21, 10), Vector2(18.5, 21), Vector2(5.5, 21)], Color("#D99A4E"))
			draw_arc(Vector2(12, 10), 6.0, PI, TAU, 12, INK, LINE)
			draw_line(Vector2(5, 14.5), Vector2(19, 14.5), INK, 1.5)
		"ledger":
			_shape([Vector2(4, 3), Vector2(19, 3), Vector2(19, 21), Vector2(4, 21)], Color("#C8573E"))
			_shape([Vector2(7, 3), Vector2(20, 3), Vector2(20, 19), Vector2(7, 19)], ViewWidgets.CREAM)
			for y in [7.0, 11.0, 15.0]:
				draw_line(Vector2(10, y), Vector2(17, y), INK, 1.5)
		"stories":
			_shape([Vector2(3, 9), Vector2(21, 9), Vector2(21, 20), Vector2(3, 20)], Color("#B5763E"))
			_shape([Vector2(2, 5), Vector2(22, 5), Vector2(22, 9), Vector2(2, 9)], Color("#D99A4E"))
			_shape([Vector2(10, 9), Vector2(14, 9), Vector2(14, 13), Vector2(10, 13)], GOLD)
		"arrange":
			_shape([Vector2(3, 8), Vector2(21, 8), Vector2(21, 12), Vector2(3, 12)], Color("#D99A4E"))
			_shape([Vector2(5, 12), Vector2(8, 12), Vector2(7, 21), Vector2(5, 21)], Color("#B5763E"))
			_shape([Vector2(16, 12), Vector2(19, 12), Vector2(19, 21), Vector2(17, 21)], Color("#B5763E"))
		"settings":
			for k in 8:
				var a := TAU * float(k) / 8.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				_shape([Vector2(12, 12) + d * 6.0 + n * 2.2, Vector2(12, 12) + d * 10.0 + n * 1.8,
					Vector2(12, 12) + d * 10.0 - n * 1.8, Vector2(12, 12) + d * 6.0 - n * 2.2], ViewWidgets.WOOD.lightened(0.35))
			_disc(Vector2(12, 12), 7.0, ViewWidgets.WOOD.lightened(0.35))
			_disc(Vector2(12, 12), 2.6, ViewWidgets.CREAM)
		"letters", "letter", "reply":
			_shape([Vector2(2, 6), Vector2(22, 6), Vector2(22, 19), Vector2(2, 19)], ViewWidgets.CREAM)
			draw_polyline(PackedVector2Array([Vector2(2, 6), Vector2(12, 13.5), Vector2(22, 6)]), INK, LINE)
			if kind == "reply":
				_disc(Vector2(19, 6), 4.0, ViewWidgets.ACCENT)
		"coin":
			_disc(Vector2(12, 12), 9.0, GOLD)
			_shape([Vector2(9.5, 9.5), Vector2(14.5, 9.5), Vector2(14.5, 14.5), Vector2(9.5, 14.5)], ViewWidgets.CREAM)
		"grain":
			draw_colored_polygon(_arc_poly(Vector2(12, 12), 7.5), ViewWidgets.CREAM)
			draw_arc(Vector2(12, 12), 7.5, PI, TAU, 14, INK, LINE)
			_shape([Vector2(3, 12), Vector2(21, 12), Vector2(18, 19), Vector2(6, 19)], Color("#C8573E"))
		"sky":
			for k in 8:
				var a := TAU * float(k) / 8.0
				draw_line(Vector2(12, 12) + Vector2(cos(a), sin(a)) * 7.5, Vector2(12, 12) + Vector2(cos(a), sin(a)) * 10.5, INK, LINE)
			_disc(Vector2(12, 12), 5.5, GOLD)
		"proposal":
			# Two rings tied by the red thread of a match.
			draw_arc(Vector2(9, 12), 5.5, 0, TAU, 20, ViewWidgets.ACCENT, 3.0)
			draw_arc(Vector2(15, 12), 5.5, 0, TAU, 20, ViewWidgets.ACCENT, 3.0)
		"stray", "pet_away":
			_disc(Vector2(12, 15.5), 5.0, Color("#D99A4E"))
			for c in [Vector2(5.5, 9.5), Vector2(10, 5.5), Vector2(14, 5.5), Vector2(18.5, 9.5)]:
				_disc(c, 2.4, Color("#D99A4E"))
			if kind == "pet_away":
				draw_line(Vector2(17, 21), Vector2(23, 21), INK, LINE)
				draw_line(Vector2(20.5, 18.5), Vector2(23, 21), INK, LINE)
		"thanks":
			_shape([Vector2(12, 21), Vector2(3, 11), Vector2(4, 6), Vector2(8, 4), Vector2(12, 7.5),
				Vector2(16, 4), Vector2(20, 6), Vector2(21, 11)], ViewWidgets.ACCENT)
		"need":
			_disc(Vector2(12, 12), 9.5, ViewWidgets.ACCENT)
			draw_line(Vector2(12, 6.5), Vector2(12, 13.5), ViewWidgets.CREAM, 3.0)
			draw_circle(Vector2(12, 17), 1.7, ViewWidgets.CREAM)
		"ill":
			# The medicine bowl with its steam (the same sign as over a sick person).
			_shape([Vector2(3, 12), Vector2(21, 12), Vector2(17, 20), Vector2(7, 20)], ViewWidgets.CREAM)
			draw_line(Vector2(9, 9), Vector2(10, 4), ViewWidgets.ACCENT, LINE)
			draw_line(Vector2(14, 9), Vector2(15, 4), ViewWidgets.ACCENT, LINE)
		"wish":
			_disc(Vector2(9, 11), 5.0, ViewWidgets.CREAM)
			_disc(Vector2(15, 10), 6.0, ViewWidgets.CREAM)
			_disc(Vector2(6, 20), 1.8, ViewWidgets.CREAM)
		"pickup":
			_disc(Vector2(12, 12), 9.5, ViewWidgets.SKY.lightened(0.55), ViewWidgets.SKY)
			_shape([Vector2(12, 4.5), Vector2(14, 10), Vector2(19.5, 12), Vector2(14, 14), Vector2(12, 19.5),
				Vector2(10, 14), Vector2(4.5, 12), Vector2(10, 10)], ViewWidgets.SKY, ViewWidgets.SKY.darkened(0.3))
	draw_set_transform(Vector2.ZERO)


func _disc(c: Vector2, r: float, fill: Color, edge := INK) -> void:
	draw_circle(c, r, fill)
	draw_arc(c, r, 0.0, TAU, 24, edge, LINE, true)


func _shape(pts: Array, fill: Color, edge := INK) -> void:
	var p := PackedVector2Array(pts)
	draw_colored_polygon(p, fill)
	p.append(pts[0])
	draw_polyline(p, edge, LINE, true)


## The upper half of a circle as a polygon (the rice heaped in the bowl).
func _arc_poly(c: Vector2, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in 13:
		var a := PI + PI * float(k) / 12.0
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p
