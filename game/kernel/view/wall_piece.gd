class_name WallPiece
extends Node2D
## One stretch of wall in a house with a site plan, drawn standing up ("treatment A"): an
## east-west wall shows its sunless south face under a dark cut top; a north-south wall shows
## only its raised top and, at the south end, a slice of face. A back wall (a built room with
## a roof right south of it) stands tall; every other east-west wall is cut low so people
## behind it stay in view. The node sits at the wall's south foot, so the house's y-sort
## draws a person south of the wall in front of it and one north of it behind. A wall goes
## see-through while someone stands behind it.

## Plan thickness of house walls and the compound wall (pixels).
const T := 12.0
const T_COMPOUND := 16.0
## Visible height of a back wall's face; of a front wall cut low; of the compound wall; of a fence.
const BACK := 88.0
const FRONT := 18.0
const COMPOUND_H := 34.0
const FENCE_H := 14.0
## Low walls are cut into pieces of at most this many cells (each fades on its own).
const LOW_PIECE := 6
## Wall left standing above a door in a back wall.
const LINTEL := 26.0
## The roof eave along the top of the north row.
const EAVE := 26.0
## Ground shadows (see `HouseGround`): depth south of back / front walls, east of north-south
## walls, opacity at the wall foot; the dark band at the west foot of north-south walls.
const SHADOW_BACK := 46.0
const SHADOW_FRONT := 14.0
const SHADOW_EAST := 28.0
const SHADOW_ALPHA := 0.52
const AO_WIDTH := 9.0
const AO_ALPHA := 0.26
## South faces are turned away from the north-west sun.
const SHADE := 0.82
## Opacity of a wall while someone stands behind it.
const SEE_THROUGH := 0.42

const LINE := Color("#4A3424")
const CAP := Color("#604A3A")
const PLASTER := Color(0.95, 0.9, 0.81)
const BEAM := Color(0.43, 0.29, 0.18)
const SKIRT := Color("#8A5A36")
const EARTH := Color(0.8, 0.66, 0.49)
const STONE := Color(0.62, 0.6, 0.56)
const TILE := Color(0.46, 0.5, 0.56)
const TILE_DARK := Color(0.33, 0.36, 0.42)
const BAMBOO := Color(0.66, 0.6, 0.33)
const OPENING := Color(0.14, 0.09, 0.06, 0.5)

## "x": an east-west run (cells a..b along line y); "y": one cell `a` of a north-south line x.
var along := "x"
var line := 0
var a := 0
var b := 0
var kind := HouseSite.HOUSE
## East-west: the face height of each cell of the run; north-south: the raised height.
var heights: Array = []
var open: Array = []
var eave := false
## North-south: this cell ends the run (draws the slice of south face).
var last := false
var first := false
var gate := false
## Where a person counts as standing behind this wall (house coordinates); empty: never.
var behind := Rect2()
## The pack's art (wall faces, the gatehouse); null or disabled: drawn plain.
var skin: PackSkin
## A low wall sorts by its top, not its foot (this many pixels up): whoever stands just
## north of it, on the room's front row, is drawn over it, as ART_DIRECTION's "front walls
## never hide anyone" asks. Drawing is shifted back down by the same amount.
var sort_lift := 0.0


static func thickness(k: String) -> float:
	return T_COMPOUND if k == HouseSite.COMPOUND else (4.0 if k == HouseSite.FENCE else T)


## Whether the east-west edge at cell `at` of line `line` is a back wall: a built indoor room
## lies right south of it.
static func is_back(site: HouseSite, line: int, at: int) -> bool:
	return site.built_indoor(site.room_at(Vector2i(at, line)))


## Height of the east-west wall face at cell `at`.
static func face_height(site: HouseSite, k: String, line: int, at: int) -> float:
	if k == HouseSite.FENCE:
		return FENCE_H
	if is_back(site, line, at):
		return BACK
	return COMPOUND_H if k == HouseSite.COMPOUND else FRONT


## Raised height of a north-south wall at cell `at`: house height beside a built room with a
## roof, else the compound wall's.
static func side_height(site: HouseSite, k: String, line: int, at: int) -> float:
	if k == HouseSite.FENCE:
		return FENCE_H
	if k == HouseSite.HOUSE:
		return BACK
	var beside := site.built_indoor(site.room_at(Vector2i(line - 1, at))) or site.built_indoor(site.room_at(Vector2i(line, at)))
	return BACK if beside else COMPOUND_H


## The pieces for every standing wall of `site`, positioned in house coordinates.
static func build_all(site: HouseSite) -> Array[WallPiece]:
	var out: Array[WallPiece] = []
	for run in site.runs():
		var k := str(run["kind"])
		var ln := int(run["line"])
		if run["along"] == "x":
			# Split where the height changes (a back wall meets a front wall on one line); a
			# low wall also splits at its doors and every LOW_PIECE cells, so it goes
			# see-through only where someone stands behind it.
			var start := int(run["a"])
			for at in range(int(run["a"]), int(run["b"]) + 1):
				if at < int(run["b"]) and (at == start or _same_piece(site, k, ln, start, at)):
					continue
				out.append(_east_west(site, k, ln, start, at, int(run["a"]), int(run["b"])))
				start = at
		else:
			var a0 := int(run["a"])
			var b0 := int(run["b"])
			for at in range(a0, b0):
				var p := WallPiece.new()
				p.along = "y"
				p.kind = k
				p.line = ln
				p.a = at
				p.b = at + 1
				var hgt := side_height(site, k, ln, at)
				# A stretch of one height starts and ends with its own corner (and face).
				p.first = at == a0 or side_height(site, k, ln, at - 1) != hgt
				p.last = at == b0 - 1 or side_height(site, k, ln, at + 1) != hgt
				p.heights = [hgt]
				p.open = [site.is_open("y", ln, at)]
				var foot := float(at + 1) * HouseSite.CELL.y + (thickness(k) * 0.5 if p.last else 0.0)
				p.position = Vector2(0, foot)
				out.append(p)
	return out


## Whether cell `at` still belongs to the piece that starts at `start` on this line.
static func _same_piece(site: HouseSite, k: String, ln: int, start: int, at: int) -> bool:
	var h := face_height(site, k, ln, start)
	if face_height(site, k, ln, at) != h:
		return false
	if h == BACK:
		return true
	return site.is_open("x", ln, at) == site.is_open("x", ln, start) and at - start < LOW_PIECE


static func _east_west(site: HouseSite, k: String, ln: int, from: int, to: int, run_a: int, run_b: int) -> WallPiece:
	var p := WallPiece.new()
	p.along = "x"
	p.kind = k
	p.line = ln
	p.a = from
	p.b = to
	p.first = from == run_a
	p.last = to == run_b
	for at in range(from, to):
		p.heights.append(face_height(site, k, ln, at))
		p.open.append(site.is_open("x", ln, at))
	var h: float = p.heights[0]
	var foot := float(ln) * HouseSite.CELL.y + thickness(k) * 0.5
	p.position = Vector2(0, foot)
	# The eave runs along the top of the map's north row of rooms: a back wall on the
	# compound's north line.
	p.eave = h == BACK and site.has_compound and ln == site.compound.position.y
	p.gate = k == HouseSite.COMPOUND and p.open.has(true) and ln == site.compound.end.y
	var top := h + thickness(k) + (EAVE if p.eave else 0.0)
	if k != HouseSite.FENCE:
		p.behind = Rect2(from * HouseSite.CELL.x, foot - top, (to - from) * HouseSite.CELL.x, top)
	if p.gate:
		# The gatehouse picture stands over the opening and rises well above the wall: it goes
		# see-through while anyone is under or behind it (a little south of its foot too, as
		# the feet of someone in the gateway are drawn just below it).
		var g := gate_rect(from, to, p.open)
		p.behind = Rect2(g.position.x, g.position.y + foot, g.size.x, g.size.y + 14.0)
	elif h != BACK and k != HouseSite.FENCE:
		# Nobody is ever hidden by it now, so it needs no see-through either.
		p.sort_lift = h + thickness(k)
		p.position.y -= p.sort_lift
		p.behind = Rect2()
	return p


## The gatehouse's rect over the doors of a gate piece (cells from..to), local to its foot.
static func gate_rect(from: int, to: int, open_cells: Array) -> Rect2:
	var cw := HouseSite.CELL.x
	var g0 := INF
	var g1 := -INF
	for i in open_cells.size():
		if open_cells[i]:
			g0 = minf(g0, (from + i) * cw)
			g1 = maxf(g1, (from + i + 1) * cw)
	var w := g1 - g0 + 60.0
	var hgt := w * 1.2
	return Rect2((g0 + g1) * 0.5 - w * 0.5, 2.0 - hgt, w, hgt)


## See-through while any of `feet` (house coordinates) stands in the band behind this wall.
func fade_for(feet: Array) -> void:
	var want := 1.0
	if behind.size != Vector2.ZERO:
		for f in feet:
			if behind.has_point(f):
				want = SEE_THROUGH
				break
	if modulate.a != want:
		modulate.a = want


func _draw() -> void:
	draw_set_transform(Vector2(0, sort_lift))
	if along == "x":
		_draw_east_west()
	else:
		_draw_north_south()


## Local coordinates: y 0 is the wall's south foot.
func _draw_east_west() -> void:
	var t := thickness(kind)
	var cw := HouseSite.CELL.x
	var h: float = heights[0]
	var x0 := a * cw - (t * 0.5 if first else 0.0)
	var x1 := b * cw + (t * 0.5 if last else 0.0)
	if kind == HouseSite.FENCE:
		_fence_x()
		return
	var back := h == BACK
	# The face: a back wall runs over its doors (a lintel above an opening); a low wall
	# simply stops at a door.
	var segs: Array = []
	if back:
		segs.append([x0, x1])
	else:
		var s := x0
		for i in open.size():
			if open[i]:
				var g0 := (a + i) * cw
				if g0 > s:
					segs.append([s, g0])
				s = (a + i + 1) * cw
		if x1 > s:
			segs.append([s, x1])
	var earthen := kind == HouseSite.COMPOUND and not back
	for sg in segs:
		_face(Rect2(sg[0], -h, sg[1] - sg[0], h), earthen)
		_cap(Rect2(sg[0], -h - t, sg[1] - sg[0], t), earthen)
	if back:
		for i in open.size():
			if open[i]:
				_back_door((a + i) * cw, (a + i + 1) * cw, h)
	if eave:
		_eave(x0, x1, -h - t)
	if gate:
		for i in open.size():
			if open[i] and (i == 0 or not open[i - 1]):
				var j := i
				while j < open.size() and open[j]:
					j += 1
				_gatehouse((a + i) * cw, (a + j) * cw, h)


func _face(r: Rect2, compound: bool) -> void:
	var t := skin.wall_tile("compound" if compound else "house") if skin != null else {}
	if not t.is_empty():
		PackSkin.draw_tile(self, t, r, Color(SHADE, SHADE, SHADE))
		if not compound:
			if r.size.y >= 30.0:
				draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 6), BEAM)
			var sk := minf(14.0, floorf(r.size.y / 3.0))
			draw_rect(Rect2(r.position.x, r.end.y - sk, r.size.x, sk), SKIRT)
			draw_line(Vector2(r.position.x, r.end.y - sk), Vector2(r.end.x, r.end.y - sk), LINE, 1.5)
		draw_rect(r, LINE, false, 2.0)
		return
	if compound:
		draw_rect(r, EARTH * SHADE)
		var base := minf(10.0, r.size.y * 0.3)
		draw_rect(Rect2(r.position.x, r.end.y - base, r.size.x, base), STONE * SHADE)
	else:
		draw_rect(r, PLASTER * SHADE)
		if r.size.y >= 30.0:
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 6), BEAM)
		var skirt := minf(14.0, floorf(r.size.y / 3.0))
		draw_rect(Rect2(r.position.x, r.end.y - skirt, r.size.x, skirt), SKIRT)
		draw_line(Vector2(r.position.x, r.end.y - skirt), Vector2(r.end.x, r.end.y - skirt), LINE, 1.5)
	draw_rect(r, LINE, false, 2.0)


func _cap(r: Rect2, tiled: bool) -> void:
	if tiled:
		draw_rect(r, TILE)
		var x := r.position.x + 6.0
		while x < r.end.x:
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), TILE_DARK, 1.0)
			x += 12.0
	else:
		draw_rect(r, CAP)
	draw_rect(r, LINE, false, 2.0)


## A doorway in a tall wall: the room behind shows through, darker, under a lintel beam
## between two posts.
func _back_door(g0: float, g1: float, h: float) -> void:
	var top := -h + LINTEL
	draw_rect(Rect2(g0, top, g1 - g0, -top), OPENING)
	draw_rect(Rect2(g0, top - 6, g1 - g0, 6), BEAM)
	draw_rect(Rect2(g0, top - 6, g1 - g0, 6), LINE, false, 1.5)
	draw_rect(Rect2(g0 - 3, top, 6, -top), BEAM)
	draw_rect(Rect2(g1 - 3, top, 6, -top), BEAM)


func _eave(x0: float, x1: float, y_bottom: float) -> void:
	var r := Rect2(x0, y_bottom - EAVE, x1 - x0, EAVE)
	draw_rect(r, Color(0.46, 0.5, 0.56))
	var x := x0 + 7.0
	while x < x1:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.36, 0.39, 0.45), 2.0)
		draw_arc(Vector2(x, r.end.y - 3), 7.0, 0.0, PI, 8, Color(0.27, 0.3, 0.35), 2.0)
		x += 14.0
	draw_rect(Rect2(x0, r.end.y - 4, x1 - x0, 4), Color(0.27, 0.3, 0.35))
	draw_rect(r, LINE, false, 2.0)
	# The eave's shadow on the top of the wall face below it.
	var s0 := Color(HouseGround.SHADOW, 0.35)
	var s1 := Color(HouseGround.SHADOW, 0.0)
	var y := y_bottom + thickness(kind)
	draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + 14), Vector2(x0, y + 14)]),
		PackedColorArray([s0, s0, s1, s1]))


## A small gatehouse over the opening: two posts and a tiled roof.
func _gatehouse(g0: float, g1: float, h: float) -> void:
	var pic := skin.wall_sprite("gate") if skin != null else null
	if pic != null:
		var w := g1 - g0 + 60.0
		draw_texture_rect(pic, PackSkin.fit_rect(pic, Vector2((g0 + g1) * 0.5, 2.0), Vector2(w, w * 1.2)), false)
		return
	var post := 10.0
	var top := -h - 34.0
	for px in [g0 - post * 0.5, g1 - post * 0.5]:
		draw_rect(Rect2(px, top, post, -top), SKIRT)
		draw_rect(Rect2(px, top, post, -top), LINE, false, 2.0)
	var roof := PackedVector2Array([Vector2(g0 - 26, top + 4), Vector2(g0 - 10, top - 18), Vector2(g1 + 10, top - 18), Vector2(g1 + 26, top + 4)])
	draw_colored_polygon(roof, TILE)
	var x := g0 - 14.0
	while x < g1 + 16.0:
		draw_line(Vector2(x, top - 16), Vector2(x - 4, top + 2), TILE_DARK, 1.5)
		x += 10.0
	roof.append(roof[0])
	draw_polyline(roof, LINE, 2.0)
	draw_rect(Rect2(g0, top + 4, g1 - g0, 6), BEAM)


func _fence_x() -> void:
	for i in open.size():
		if open[i]:
			continue
		var s := (a + i) * HouseSite.CELL.x
		for y in [-FENCE_H, -FENCE_H * 0.4]:
			draw_line(Vector2(s, y), Vector2(s + HouseSite.CELL.x, y), BAMBOO.darkened(0.2), 3.0)
		for k in 4:
			var px := s + 6.0 + k * 12.0
			draw_line(Vector2(px, 0), Vector2(px, -FENCE_H - 4), BAMBOO, 3.0)


## Local coordinates: y 0 is the foot of this cell's stretch (the south end of the run for
## the last cell, which also shows a slice of south face).
func _draw_north_south() -> void:
	var t := thickness(kind)
	var cw := HouseSite.CELL
	var h: float = heights[0]
	var x := line * cw.x
	var y_top := a * cw.y - position.y
	var y_bot := b * cw.y - position.y
	if kind == HouseSite.FENCE:
		if open[0]:
			return
		var pics: Array = skin.wall_sprites("fence_ns") if skin != null else []
		if not pics.is_empty():
			# A bamboo fence seen end on: one picture per cell, standing on the cell's foot.
			var pic: Texture2D = pics[a % pics.size()]
			var hgt := y_bot - y_top + FENCE_H + 8.0
			var wd := hgt * pic.get_width() / pic.get_height()
			draw_texture_rect(pic, Rect2(x - wd * 0.5, y_bot - hgt + 2.0, wd, hgt), false)
			return
		for k in 3:
			var py := y_top + 6.0 + k * 12.0
			draw_line(Vector2(x, py), Vector2(x, py - FENCE_H - 4), BAMBOO, 3.0)
		draw_line(Vector2(x, y_top - FENCE_H * 0.5), Vector2(x, y_bot - FENCE_H * 0.5), BAMBOO.darkened(0.2), 3.0)
		return
	var top0 := y_top - h - (t * 0.5 if first else 0.0)
	var top1 := y_bot - h + (t * 0.5 if last else 0.0)
	if open[0]:
		# The doorway seen edge-on: a dark slot under the top, which runs on as a lintel.
		draw_rect(Rect2(x - t * 0.5 - 2, y_top - h + LINTEL, t + 4, h - LINTEL), OPENING)
	var cap := Rect2(x - t * 0.5, top0, t, top1 - top0)
	if kind == HouseSite.COMPOUND and h != BACK:
		draw_rect(cap, TILE)
	else:
		draw_rect(cap, CAP)
	draw_line(cap.position, Vector2(cap.position.x, cap.end.y), LINE, 2.0)
	draw_line(Vector2(cap.end.x, cap.position.y), cap.end, LINE, 2.0)
	if first:
		draw_line(cap.position, Vector2(cap.end.x, cap.position.y), LINE, 2.0)
	if last:
		var face := Rect2(x - t * 0.5 - 2, top1, t + 4, h)
		_face(face, kind == HouseSite.COMPOUND and h != BACK)
