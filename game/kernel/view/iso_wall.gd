class_name IsoWall
extends Node2D
## One cell's length of standing wall in the 45° view (a dollhouse seen from the south-east),
## or a picture that belongs to the walls (a window or a string of chillies on a back wall,
## the gatehouse over the gate). The two outer walls turned away from the camera (north and
## west of the compound, or of a lone house) stand full height with their plaster or rammed
## earth face, a beam and a tiled eave; every other wall is cut to the ankle, so whoever
## stands inside is always in view. A door is a gap. Each piece sits on the stage at the
## middle of its edge (plan coordinates) and draws upright in view pixels; the stage sorts it
## with the people by how far in front it stands (`sort_bias` keeps back walls behind
## whatever stands inside them). A back wall or the gatehouse goes see-through while someone
## stands right behind it.

## Face heights (view pixels): a house's back wall, the compound's, a cut wall, a cut
## compound wall, a fence.
const BACK := 112.0
const COMPOUND_BACK := 74.0
const LOW := 16.0
const COMPOUND_LOW := 22.0
const FENCE_H := 26.0
## Plan thickness, in cells: house walls, the compound wall.
const T := 0.2
const T_COMPOUND := 0.28
## Wall left over a door in a back wall.
const LINTEL := 26.0
## Back walls sort this far (view pixels: 0.45 of a cell's depth) behind their line, so long
## furniture standing against them is drawn over them while whoever stands in the cell
## behind still sorts behind; cut walls a hair in front of theirs.
const BACK_BIAS := -7.2
const LOW_BIAS := 0.8
## The west face is turned from the north-west sun.
const WEST_SHADE := 0.8
const SEE_THROUGH := 0.42

const LINE := Color("#4A3424")
const CAP := Color(0.376, 0.29, 0.227)
## Old dark wood: the beam, the posts, a door's frame.
const BEAM := Color(0.3, 0.2, 0.13)
const SKIRT := Color(0.59, 0.39, 0.24)
const POST := Color(0.34, 0.22, 0.14)
const PLASTER := Color(0.95, 0.9, 0.81)
const EARTH := Color(0.8, 0.62, 0.42)
const STONE := Color(0.59, 0.59, 0.55)
const EAVE := Color(0.44, 0.49, 0.56)
const EAVE_DARK := Color(0.33, 0.37, 0.43)
const TILE_CAP := Color(0.47, 0.52, 0.59)
## The grey tiles laid on a cut house wall, and their rolled ridge.
const LOW_TILE := Color(0.43, 0.44, 0.45)
const LOW_TILE_DARK := Color(0.3, 0.31, 0.33)
const LOW_TOP := Color(0.965, 0.91, 0.8)
const LOW_FACE_X := Color(0.886, 0.824, 0.714)
const LOW_FACE_Y := Color(0.776, 0.714, 0.612)
const LOW_EARTH_X := Color(0.784, 0.588, 0.376)
const LOW_EARTH_Y := Color(0.69, 0.5, 0.314)
const BAMBOO := Color(0.66, 0.6, 0.33)
const OPENING := Color(0.14, 0.09, 0.06, 0.55)

## "wall", "decal" or "gate".
var role := "wall"
## "x": the edge runs east-west (cells at..at+1 on line y = line); "y": north-south.
var along := "x"
var line := 0
var at := 0
var kind := HouseSite.HOUSE
var tall := false
var height := LOW
var open := false
## The house's back wall: a beam, posts and a tiled eave on top.
var eave := false
## Draw the end face at the +x / +y end (the run stops or drops here).
var end_face := false
var sort_bias := 0.0
var skin: PackSkin
## Decal / gate: the picture, its centre along the wall (cells), width (px), top (0..1 down
## the face); the gate's opening in cells.
var tex: Texture2D
var decal_at := 0.0
var decal_w := 50.0
var decal_y := 0.25
var gate_len := 1
var flip := false
## Where on the view this piece covers (view pixels), for the see-through test.
var view_box := Rect2()


## Whether the wall on this edge is one of the back walls (the side turned away from the
## camera): the cell on its inside (south / east) is within the compound, or a built room
## when there is none, and the outside is not.
static func is_back(site: HouseSite, along_: String, line_: int, at_: int) -> bool:
	var inside := Vector2i(at_, line_) if along_ == "x" else Vector2i(line_, at_)
	var outside := inside - (Vector2i(0, 1) if along_ == "x" else Vector2i(1, 0))
	if site.has_compound:
		return site.compound.has_point(inside) and not site.compound.has_point(outside)
	return site.built_indoor(site.room_at(inside)) and not site.built_indoor(site.room_at(outside))


## The face height of the wall on this edge.
static func face_height(site: HouseSite, k: String, along_: String, line_: int, at_: int) -> float:
	if k == HouseSite.FENCE:
		return FENCE_H
	var inside := Vector2i(at_, line_) if along_ == "x" else Vector2i(line_, at_)
	if is_back(site, along_, line_, at_):
		return BACK if site.built_indoor(site.room_at(inside)) or k == HouseSite.HOUSE else COMPOUND_BACK
	return COMPOUND_LOW if k == HouseSite.COMPOUND else LOW


static func thickness(k: String) -> float:
	return T_COMPOUND if k == HouseSite.COMPOUND else (0.06 if k == HouseSite.FENCE else T)


static func _walled(site: HouseSite, along_: String, line_: int, at_: int) -> bool:
	var walls := site.h_walls if along_ == "x" else site.v_walls
	return walls.has(Vector2i(at_, line_) if along_ == "x" else Vector2i(line_, at_))


## Every piece for `site` as it stands now: one per walled edge, the decals on built back
## walls and a gatehouse over each opening in the compound's front walls.
static func build_all(site: HouseSite, skin_: PackSkin, pack: Pack) -> Array:
	var out: Array = []
	for pair in [["x", site.h_walls], ["y", site.v_walls]]:
		var al: String = pair[0]
		for e in pair[1]:
			var ln: int = e.y if al == "x" else e.x
			var a: int = e.x if al == "x" else e.y
			var p := IsoWall.new()
			p.along = al
			p.line = ln
			p.at = a
			p.kind = str(pair[1][e])
			p.height = face_height(site, p.kind, al, ln, a)
			p.tall = p.kind != HouseSite.FENCE and is_back(site, al, ln, a)
			p.open = site.is_open(al, ln, a)
			p.eave = p.tall and p.height == BACK
			var nxt := _walled(site, al, ln, a + 1) and not site.is_open(al, ln, a + 1)
			p.end_face = not nxt or face_height(site, str((site.h_walls if al == "x" else site.v_walls)[Vector2i(a + 1, ln) if al == "x" else Vector2i(ln, a + 1)]), al, ln, a + 1) < p.height
			p.sort_bias = BACK_BIAS if p.tall else LOW_BIAS
			p.position = _mid(al, ln, a)
			p._box()
			out.append(p)
	if skin_ == null:
		return out
	# Pictures on the back walls of built rooms.
	for d in skin_.wall_decals():
		var r = pack.rooms.get(d.room)
		if not (r is Dictionary and site.built_indoor(str(d.room))):
			continue
		var al := "y" if d.side == "west" else "x"
		var ln := int(r["x"]) if al == "y" else int(r["y"])
		var start := int(r["y"]) if al == "y" else int(r["x"])
		var cell := start + int(floor(float(d.at)))
		if not (is_back(site, al, ln, cell) and _walled(site, al, ln, cell)):
			continue
		var p := IsoWall.new()
		p.role = "decal"
		p.along = al
		p.line = ln
		p.at = cell
		p.kind = HouseSite.HOUSE
		p.tall = true
		p.height = face_height(site, HouseSite.HOUSE, al, ln, cell)
		p.tex = d.tex
		p.decal_at = float(start) + float(d.at)
		p.decal_w = float(d.w)
		p.decal_y = float(d.y)
		# In front of every piece of this wall it lies on, still behind the room's things.
		p.sort_bias = 12.0
		p.position = _mid(al, ln, cell)
		p._box()
		out.append(p)
	# A gatehouse over each run of open edges in a front compound wall.
	var gate_pic := skin_.wall_sprite("gate")
	if gate_pic != null and site.has_compound:
		for pair in [["x", site.h_open], ["y", site.v_open]]:
			var al: String = pair[0]
			var seen := {}
			for e in pair[1]:
				var ln: int = e.y if al == "x" else e.x
				var a: int = e.x if al == "x" else e.y
				var walls := site.h_walls if al == "x" else site.v_walls
				if seen.has(e) or str(walls.get(e, "")) != HouseSite.COMPOUND or is_back(site, al, ln, a):
					continue
				if site.is_open(al, ln, a - 1):
					continue  # not the first edge of its opening
				var n := 0
				while site.is_open(al, ln, a + n):
					seen[Vector2i(a + n, ln) if al == "x" else Vector2i(ln, a + n)] = true
					n += 1
				var p := IsoWall.new()
				p.role = "gate"
				p.along = al
				p.line = ln
				p.at = a
				p.kind = HouseSite.COMPOUND
				p.gate_len = n
				p.tex = gate_pic
				p.flip = al == "y"
				p.sort_bias = 5.0
				var mid := float(a) + float(n) * 0.5
				p.position = Vector2(mid * HouseSite.CELL.x, ln * HouseSite.CELL.y) if al == "x" else Vector2(ln * HouseSite.CELL.x, mid * HouseSite.CELL.y)
				p._box()
				out.append(p)
	return out


static func _mid(al: String, ln: int, a: int) -> Vector2:
	if al == "x":
		return Vector2((a + 0.5) * HouseSite.CELL.x, ln * HouseSite.CELL.y)
	return Vector2(ln * HouseSite.CELL.x, (a + 0.5) * HouseSite.CELL.y)


## A point given in cells (and a height) -> this piece's local, upright view pixels.
func _p(i: float, j: float, z := 0.0) -> Vector2:
	return IsoMath.cell_view(i, j) - IsoMath.to_view(position) - Vector2(0, z)


## The gatehouse picture's rect, local.
func gate_rect() -> Rect2:
	var w := (float(gate_len) + 2.6) * IsoMath.TILE.x * 0.5
	var ts := Vector2(tex.get_size())
	var s := ts * (w / ts.x)
	return Rect2(-s.x * 0.5, 10.0 - s.y, s.x, s.y)


func _box() -> void:
	var foot := IsoMath.to_view(position)
	match role:
		"gate":
			var g := gate_rect()
			view_box = Rect2(foot + g.position, g.size + Vector2(0, 10))
		"decal":
			view_box = Rect2()
		_:
			if tall:
				var a := _p(at, line) if along == "x" else _p(line, at)
				var b := _p(at + 1, line) if along == "x" else _p(line, at + 1)
				var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y) - height - 20.0)
				var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
				view_box = Rect2(foot + lo, hi - lo)


## The wall's line in plan pixels (a zero-thickness rect along its edge).
func plan_rect() -> Rect2:
	var c := HouseSite.CELL
	if along == "x":
		return Rect2(Vector2(at * c.x, line * c.y), Vector2(c.x, 0))
	return Rect2(Vector2(line * c.x, at * c.y), Vector2(0, c.y))


## What this piece covers on the view, for sorting people against it: `view_box` for a back
## wall or the gatehouse; a cut wall's or fence's low face otherwise (none for a door gap or
## a decal).
var _cover := Rect2()
var _cover_at := Vector2(INF, INF)
func cover_box() -> Rect2:
	if view_box.size != Vector2.ZERO or role != "wall" or open:
		return view_box
	if _cover_at == position:
		return _cover
	_cover_at = position
	var foot := IsoMath.to_view(position)
	var a := _p(at, line) if along == "x" else _p(line, at)
	var b := _p(at + 1, line) if along == "x" else _p(line, at + 1)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y) - height - 4.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y) + 4.0)
	_cover = Rect2(foot + lo, hi - lo)
	return _cover


## See-through while anyone ([view foot, depth] in `seen`) stands behind this piece under it.
func fade_for_view(seen: Array, depth: float) -> void:
	var want := 1.0
	if view_box.size != Vector2.ZERO:
		for s in seen:
			if s[1] < depth - 1.0 and view_box.has_point(s[0]):
				want = SEE_THROUGH
				break
	if modulate.a != want:
		modulate.a = want


## The same rule as WallPiece's, for callers that only have plan feet (unused here).
func fade_for(_feet: Array) -> void:
	pass


func _draw() -> void:
	match role:
		"decal":
			_draw_decal()
		"gate":
			var g := gate_rect()
			if flip:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
			draw_texture_rect(tex, g, false)
			draw_set_transform(Vector2.ZERO)
		_:
			if kind == HouseSite.FENCE:
				_draw_fence()
			elif tall:
				_draw_back()
			elif not open:
				_draw_low()


## The face's plane: [(i, j) of its start, (i, j) of its end] at ground level.
func _face_ends(off: float) -> Array:
	if along == "x":
		return [Vector2(at, line + off), Vector2(at + 1, line + off)]
	return [Vector2(line + off, at), Vector2(line + off, at + 1)]


## A transform taking a flat elevation (u pixels along the wall from the line's origin, v
## pixels up negative) onto the face plane at offset `off` (cells) from the wall line.
func _elevation(off: float) -> Transform2D:
	var ends := _face_ends(off)
	var o := _p(ends[0].x, ends[0].y)
	var u := (_p(ends[1].x, ends[1].y) - o) / IsoMath.EDGE
	return Transform2D(u, Vector2(0, 1), o - u * float(at) * IsoMath.EDGE)


## A soft dark band over part of a face (elevation space): `a0` alpha at its top, `a1` at its
## foot, so the face darkens toward the ground or under the beam the way a rendered wall does.
func _band(r: Rect2, a0: float, a1: float) -> void:
	var c0 := Color(0.08, 0.05, 0.03, a0)
	var c1 := Color(0.08, 0.05, 0.03, a1)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([c0, c0, c1, c1]))


## The wall's shadow on the ground in front of its face: `reach` cells out, fading.
func _ground_shadow(t: float, reach: float, alpha: float) -> void:
	var ends := _face_ends(t * 0.5)
	var far := _face_ends(t * 0.5 + reach)
	var c0 := Color(0.1, 0.06, 0.03, alpha)
	var c1 := Color(0.1, 0.06, 0.03, 0.0)
	draw_polygon(PackedVector2Array([_p(ends[0].x, ends[0].y), _p(ends[1].x, ends[1].y), _p(far[1].x, far[1].y), _p(far[0].x, far[0].y)]),
		PackedColorArray([c0, c0, c1, c1]))


func _draw_back() -> void:
	var t := thickness(kind)
	var h := height
	var compound := not eave
	var shade := WEST_SHADE if along == "y" else 1.0
	var tint := Color(shade, shade, shade)
	var u0 := float(at) * IsoMath.EDGE
	var L := IsoMath.EDGE
	if not open:
		_ground_shadow(t, 0.4, 0.3)
	draw_set_transform_matrix(_elevation(t * 0.5))
	var tile := skin.wall_tile("compound" if compound else "house") if skin != null else {}
	var face := Rect2(u0, -h, L, h)
	var solid := face if not open else Rect2(u0, -h, L, LINTEL)
	if tile.is_empty():
		draw_rect(solid, (EARTH if compound else PLASTER) * tint)
	elif open:
		# Over a door: the same strip of the face as a whole wall would show there.
		var tex: Texture2D = tile["tex"]
		var k := float(tex.get_height()) / h
		draw_texture_rect_region(tex, solid, Rect2(u0 * k, 0.0, L * k, LINTEL * k), tint)
	else:
		PackSkin.draw_tile(self, tile, solid, tint)
	var soft := not tile.is_empty()
	if soft and not open:
		_band(Rect2(u0, -h * 0.4, L, h * 0.4), 0.0, 0.34)
	if soft and not compound:
		_band(Rect2(u0, -h + 9, L, 14), 0.32, 0.0)
	if compound:
		if not open:
			draw_rect(Rect2(u0, -16, L, 16), STONE * tint)
			var x := u0 + fmod(22.0 - fmod(u0, 22.0), 22.0)
			while x < u0 + L:
				draw_line(Vector2(x, -16), Vector2(x, 0), STONE.darkened(0.3), 1.0)
				x += 22.0
			draw_line(Vector2(u0, -16), Vector2(u0 + L, -16), LINE, 2.0)
	else:
		draw_rect(Rect2(u0, -h, L, 9), BEAM * tint)
		draw_rect(Rect2(u0, -h + 7, L, 2), BEAM.darkened(0.35) * tint)
		if not soft:
			draw_line(Vector2(u0, -h + 9), Vector2(u0 + L, -h + 9), LINE, 2.0)
		if tile.is_empty() and not open:
			draw_rect(Rect2(u0, -20, L, 20), SKIRT * tint)
			draw_line(Vector2(u0, -20), Vector2(u0 + L, -20), LINE, 2.0)
		# A post every third cell along the line.
		if at % 3 == 0:
			draw_rect(Rect2(u0 - 4, -h, 8, h), POST * tint)
			draw_rect(Rect2(u0 - 4, -h, 3, h), POST.lightened(0.12) * tint)
			draw_rect(Rect2(u0 + 2, -h, 2, h), POST.darkened(0.3) * tint)
			if not soft:
				draw_rect(Rect2(u0 - 4, -h, 8, h), LINE, false, 1.0)
			else:
				_band(Rect2(u0 - 4, -h * 0.4, 8, h * 0.4), 0.0, 0.3)
	if open:
		draw_rect(Rect2(u0, -h + LINTEL, L, h - LINTEL), OPENING)
		draw_rect(Rect2(u0, -h + LINTEL - 6, L, 6), BEAM)
		draw_rect(Rect2(u0 - 3, -h + LINTEL, 6, h - LINTEL), BEAM)
		draw_rect(Rect2(u0 + L - 3, -h + LINTEL, 6, h - LINTEL), BEAM)
	if not soft:
		draw_line(Vector2(u0, -h), Vector2(u0 + L, -h), LINE, 2.0)
		if not open:
			draw_line(Vector2(u0, 0), Vector2(u0 + L, 0), LINE, 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if end_face:
		_end(h, t, (PLASTER if not compound else EARTH) * 0.85, soft)
	# The top: a dark cut (house) or grey tiles (compound), and the house's eave outside.
	var ends := _face_ends(0.0)
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var n := Vector2(0, 1) if along == "x" else Vector2(1, 0)
	var top := PackedVector2Array([_p(a.x - n.x * t * 0.5, a.y - n.y * t * 0.5, h), _p(b.x - n.x * t * 0.5, b.y - n.y * t * 0.5, h),
		_p(b.x + n.x * t * 0.5, b.y + n.y * t * 0.5, h), _p(a.x + n.x * t * 0.5, a.y + n.y * t * 0.5, h)])
	draw_colored_polygon(top, TILE_CAP if compound else CAP)
	top.append(top[0])
	if not soft:
		draw_polyline(top, LINE, 1.5)
	if eave:
		var e0 := 0.11
		var e1 := 0.75
		var poly := PackedVector2Array([_p(a.x - n.x * e0, a.y - n.y * e0, h), _p(b.x - n.x * e0, b.y - n.y * e0, h),
			_p(b.x - n.x * e1, b.y - n.y * e1, h - 10), _p(a.x - n.x * e1, a.y - n.y * e1, h - 10)])
		draw_colored_polygon(poly, EAVE)
		var k := 0.25
		while k < 1.0:
			var s := a.lerp(b, k)
			draw_line(_p(s.x - n.x * 0.15, s.y - n.y * 0.15, h), _p(s.x - n.x * 0.72, s.y - n.y * 0.72, h - 10), EAVE_DARK, 2.0)
			k += 0.5
		# The eave's lit front edge and its dark underside.
		draw_line(poly[0], poly[1], EAVE.lightened(0.25), 1.5)
		draw_line(poly[3], poly[2], EAVE_DARK.darkened(0.3), 2.0)
		if not soft:
			poly.append(poly[0])
			draw_polyline(poly, LINE, 1.5)
	elif compound:
		var k2 := 0.25
		while k2 < 1.0:
			var s2 := a.lerp(b, k2)
			draw_line(_p(s2.x - n.x * t * 0.5, s2.y - n.y * t * 0.5, h), _p(s2.x + n.x * t * 0.5, s2.y + n.y * t * 0.5, h), EAVE_DARK, 1.5)
			k2 += 0.5


## The face where the wall stops at its +x / +y end, `h` high.
func _end(h: float, t: float, c: Color, soft := false) -> void:
	var e := float(at + 1)
	var pts: PackedVector2Array
	if along == "x":
		pts = PackedVector2Array([_p(e, line - t * 0.5), _p(e, line + t * 0.5), _p(e, line + t * 0.5, h), _p(e, line - t * 0.5, h)])
	else:
		pts = PackedVector2Array([_p(line - t * 0.5, e), _p(line + t * 0.5, e), _p(line + t * 0.5, e, h), _p(line - t * 0.5, e, h)])
	if soft:
		# Lit from the north-west: the end faces turn away, a shade darker toward the foot.
		var top := c * 0.92
		var foot := c * 0.7
		top.a = 1.0
		foot.a = 1.0
		draw_polygon(pts, PackedColorArray([foot, foot, top, top]))
		return
	draw_colored_polygon(pts, c)
	pts.append(pts[0])
	draw_polyline(pts, LINE, 1.5)


func _draw_low() -> void:
	var t := thickness(kind)
	var h := height
	var earth := kind == HouseSite.COMPOUND
	var face_col := (LOW_EARTH_X if earth else LOW_FACE_X) if along == "x" else (LOW_EARTH_Y if earth else LOW_FACE_Y)
	var ends := _face_ends(t * 0.5)
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var face := PackedVector2Array([_p(a.x, a.y), _p(b.x, b.y), _p(b.x, b.y, h), _p(a.x, a.y, h)])
	var bricks := skin.wall_tile("house_low") if skin != null and not earth else {}
	if not bricks.is_empty():
		_ground_shadow(t, 0.22, 0.32)
	if bricks.is_empty():
		draw_colored_polygon(face, face_col)
	else:
		# Grey brick, the west-turned faces a shade darker.
		var shade := 1.0 if along == "x" else 0.84
		draw_set_transform_matrix(_elevation(t * 0.5))
		var r := Rect2(float(at) * IsoMath.EDGE, -h, IsoMath.EDGE, h)
		PackSkin.draw_tile(self, bricks, r, Color(shade, shade, shade))
		_band(r, 0.22, 0.0)
		_band(Rect2(r.position.x, -h * 0.5, r.size.x, h * 0.5), 0.0, 0.3)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		face_col = Color(0.5, 0.5, 0.5) * shade
	if bricks.is_empty():
		face.append(face[0])
		draw_polyline(face, LINE, 1.5)
	if end_face:
		_end(h, t, face_col * 0.85, not bricks.is_empty())
	var c := _face_ends(0.0)
	var n := Vector2(0, 1) if along == "x" else Vector2(1, 0)
	var top := PackedVector2Array([_p(c[0].x - n.x * t * 0.5, c[0].y - n.y * t * 0.5, h), _p(c[1].x - n.x * t * 0.5, c[1].y - n.y * t * 0.5, h),
		_p(c[1].x + n.x * t * 0.5, c[1].y + n.y * t * 0.5, h), _p(c[0].x + n.x * t * 0.5, c[0].y + n.y * t * 0.5, h)])
	if earth or skin == null or skin.wall_tile("house_low").is_empty():
		draw_colored_polygon(top, TILE_CAP if earth else LOW_TOP)
		top.append(top[0])
		draw_polyline(top, LINE, 1.5)
		return
	_tile_cap(c[0], c[1], n, t, h)


## Grey tiles laid on a cut house wall: a cap a little wider than the wall, a rolled ridge
## along the middle and the tiles' rolls across it.
func _tile_cap(a: Vector2, b: Vector2, n: Vector2, t: float, h: float) -> void:
	var w := t * 0.5 + 0.04
	var lift := 3.0
	var cap := PackedVector2Array([_p(a.x - n.x * w, a.y - n.y * w, h), _p(b.x - n.x * w, b.y - n.y * w, h),
		_p(b.x + n.x * w, b.y + n.y * w, h), _p(a.x + n.x * w, a.y + n.y * w, h)])
	draw_colored_polygon(cap, LOW_TILE_DARK)
	var ridge := PackedVector2Array([_p(a.x - n.x * w * 0.55, a.y - n.y * w * 0.55, h + lift), _p(b.x - n.x * w * 0.55, b.y - n.y * w * 0.55, h + lift),
		_p(b.x + n.x * w * 0.55, b.y + n.y * w * 0.55, h + lift), _p(a.x + n.x * w * 0.55, a.y + n.y * w * 0.55, h + lift)])
	# The ridge's front side down to the cap, then its top.
	var front := PackedVector2Array([_p(a.x + n.x * w, a.y + n.y * w, h), _p(b.x + n.x * w, b.y + n.y * w, h), ridge[2], ridge[3]])
	draw_colored_polygon(front, LOW_TILE)
	draw_colored_polygon(ridge, LOW_TILE.lightened(0.12))
	var k := 0.125
	while k < 1.0:
		var s2 := a.lerp(b, k)
		draw_line(_p(s2.x + n.x * w, s2.y + n.y * w, h), _p(s2.x + n.x * w * 0.55, s2.y + n.y * w * 0.55, h + lift), LOW_TILE_DARK, 1.0)
		k += 0.25
	# Light catches the ridge's top edge; the cap's front lip throws a thin dark line.
	draw_line(ridge[0], ridge[1], LOW_TILE.lightened(0.35), 1.0)
	draw_line(cap[3], cap[2], LOW_TILE_DARK.darkened(0.35), 1.2)


func _draw_fence() -> void:
	if open:
		return
	var pic := skin.wall_sprite("fence_x" if along == "x" else "fence_y") if skin != null else null
	if pic != null:
		# One stretch of bamboo per cell edge, standing on it.
		var w := IsoMath.TILE.x * 0.5 * 1.15
		var ts := Vector2(pic.get_size())
		var s := ts * (w / ts.x)
		draw_texture_rect(pic, Rect2(-s.x * 0.5, s.y * 0.25 - s.y, s.x, s.y), false)
		return
	var ends := _face_ends(0.0)
	for z in [FENCE_H * 0.4, FENCE_H * 0.85]:
		draw_line(_p(ends[0].x, ends[0].y, z), _p(ends[1].x, ends[1].y, z), BAMBOO.darkened(0.2), 2.5)
	for k in 4:
		var s2: Vector2 = ends[0].lerp(ends[1], (k + 0.5) / 4.0)
		draw_line(_p(s2.x, s2.y), _p(s2.x, s2.y, FENCE_H), BAMBOO, 2.5)


## A picture flat on the face of a back wall, slanted with it.
func _draw_decal() -> void:
	var t := thickness(kind)
	draw_set_transform_matrix(_elevation(t * 0.5 + 0.01))
	var ts := Vector2(tex.get_size())
	var s := ts * (decal_w / ts.x)
	var cx := decal_at * IsoMath.EDGE
	var shade := WEST_SHADE if along == "y" else 1.0
	draw_texture_rect(tex, Rect2(cx - s.x * 0.5, -height + height * decal_y, s.x, s.y), false, Color(shade, shade, shade))
	draw_set_transform_matrix(Transform2D.IDENTITY)
