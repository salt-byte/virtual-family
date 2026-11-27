class_name TestKit
extends RefCounted
## Helpers for building worlds and people in tests.


## A living world at local noon (UTC, 2026-01-01) with nobody in it yet.
static func world(pack_id := "_smoke", seed := 1) -> World:
	var w := World.new(Pack.load_dir("res://packs/" + pack_id), seed)
	w.set_time(1767268800, 0)
	w.phase = "living"
	w.candidate = {}
	return w


## Adds an adult at each need's `start` value and a lifespan of 70.
static func adult(w: World, age := 25.0) -> Person:
	var p := Person.new()
	p.given = "Test"
	p.age = age
	p.lifespan = 70.0
	for nid in w.pack.needs:
		p.needs[nid] = float(w.pack.needs[nid]["start"])
	w.add_person(p)
	w.phase = "living"
	return p


## The 45° view, a piece drawn on its ruler (art.json `iso.ruler`): what is wrong with how it
## stands, [] when nothing. The ruler's anchor (the footprint's middle in the picture) is on
## the footprint's middle and the picture is at the ruler's scale; the foot of the drawing
## (its opaque pixels at or in front of the footprint's middle) keeps within the footprint's
## diamond across the screen and reaches no lower than its bottom corner (as any picture,
## 6 px of soft edge allowed), so it stands clear of the walls round it. Above that the
## drawing may rise as tall as it is (a cupboard over the wall behind it) and overhang a
## little sideways (a pot's rim), at most RULER_OVERHANG of the diamond's width each side.
const RULER_OVERHANG := 0.15
static func ruler_problems(house: HouseView, o: Dictionary, piece: PropPiece, w: World) -> Array[String]:
	var out: Array[String] = []
	var ruler := house.skin.object_ruler(str(o.type))
	if ruler.is_empty():
		return ["%s has no ruler" % o.type]
	var r := house.layout.object_rect(o, w.pack)
	if piece.position != r.get_center():
		out.append("not on its footprint's middle: %s vs %s" % [piece.position, r.get_center()])
	var k := house.view_px_per_m() / float(ruler["px_per_m"])
	var ts := Vector2(piece.tex.get_size())
	var an: Vector2 = ruler["anchor"] * k
	# Backed onto its wall when it stands against one (design/PLACEMENT.md section 5).
	var east := house._faces_east(o, r, house.skin.object_axis(str(o.type)))
	var back := house.back_view(o, r, east, w)
	var want := Rect2(Vector2(-(ts.x * k - an.x) if piece.flip else -an.x, -an.y) + back, ts * k)
	if not (piece.rect.position.is_equal_approx(want.position) and piece.rect.size.is_equal_approx(want.size)):
		out.append("not anchored on the ruler: %s vs %s" % [piece.rect, want])
	var at := IsoMath.to_view(piece.position)
	var d := IsoMath.diamond(r)
	var lo := d[3].x - at.x
	var hi := d[1].x - at.x
	var bottom := d[2].y - at.y + 6.0
	# The foot is checked where it stood before it was backed onto the wall.
	var foot := drawn_rect(piece, 0.0)
	foot.position -= back
	if not foot.has_area():
		out.append("no foot drawn at the footprint's middle")
	elif foot.position.x < lo - 0.01 or foot.end.x > hi + 0.01 or foot.end.y > bottom + 0.01:
		out.append("foot %s off the diamond x %.1f..%.1f, bottom %.1f" % [foot, lo, hi, bottom])
	var whole := drawn_rect(piece)
	var over := (hi - lo) * RULER_OVERHANG
	if whole.position.x < lo - over or whole.end.x > hi + over:
		out.append("overhangs sideways: %s vs x %.1f..%.1f" % [whole, lo, hi])
	return out


static var _opaque := {}


## The bounds (round the piece's foot, view pixels) of the opaque pixels (alpha >= 0.5) of a
## piece's picture as drawn (mirrored when it is), only those at or below `from_y`.
static func drawn_rect(piece: PropPiece, from_y := -INF) -> Rect2:
	var key := piece.tex.get_rid()
	if not _opaque.has(key):
		var img := piece.tex.get_image()
		if img.is_compressed():
			img.decompress()
		var rows := []
		for v in img.get_height():
			var a := -1
			var b := -1
			for u in img.get_width():
				if img.get_pixel(u, v).a >= 0.5:
					if a < 0:
						a = u
					b = u
			rows.append(Vector2i(a, b))
		_opaque[key] = rows
	var rows: Array = _opaque[key]
	var sx := piece.rect.size.x / piece.tex.get_width()
	var sy := piece.rect.size.y / piece.tex.get_height()
	var out := Rect2()
	var any := false
	for v in rows.size():
		var span: Vector2i = rows[v]
		var y0 := piece.rect.position.y + v * sy
		if span.x < 0 or y0 + sy <= from_y:
			continue
		var x0 := piece.rect.position.x + span.x * sx
		var x1 := piece.rect.position.x + (span.y + 1) * sx
		if piece.flip:
			var mid := piece.rect.get_center().x
			var t := x0
			x0 = 2.0 * mid - x1
			x1 = 2.0 * mid - t
		var row := Rect2(x0, maxf(y0, from_y), x1 - x0, y0 + sy - maxf(y0, from_y))
		out = row if not any else out.merge(row)
		any = true
	return out
