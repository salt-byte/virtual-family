class_name HouseGround
extends Node2D
## The flat ground of a house with a site plan, drawn once per change of the plan: the map's
## ground and decor, room floors and bare foundations, the shadows the walls cast (sun in
## the north-west), door sills, the names written on the floor (seen from above) and the prices of rooms still to build. Sits under everything
## (z_index -1); walls are `WallPiece`s, sorted with the people. Reads the World only.

const LINE := Color("#4A3424")
const CREAM := Color("#FFF4DF")
const FOUNDATION := Color("#F6ECD4")
const FOUNDATION_EDGE := Color(0.69, 0.66, 0.61)
## How much cream lies over the earth of a bare foundation (with the pack's art).
const FOUNDATION_WASH := 0.32
const DASH := Color(0.59, 0.45, 0.33)
const PILL := Color("#FFE3B0")
const SILL := Color(0.62, 0.61, 0.58)
const SHADOW := Color(0.16, 0.11, 0.08)
## Default floor of an indoor room that names no colour.
const FLOOR := Color(0.94, 0.91, 0.84)
## Floors darken towards the side away from the back wall by this much (alpha of SHADOW).
const FLOOR_FALLOFF := 0.13

var house: HouseView


func _draw() -> void:
	var w := house.session.world if house != null and house.session != null else null
	if w == null or w.phase == "invalid":
		return
	var site := house.layout.site
	if not site.enabled:
		return
	var skin := house.skin
	var around := site.rect()
	if house.iso:
		# The 45° view shows past the map's corners: the ground goes on round it.
		# Far enough that the screen's corners are covered at the smallest zoom.
		around = around.grow_individual(40 * HouseSite.CELL.x, 40 * HouseSite.CELL.y, 40 * HouseSite.CELL.x, 40 * HouseSite.CELL.y)
	_fill(around, site.ground, skin.ground_tile() if skin != null else {})
	if site.has_compound:
		_fill(_cells(Rect2(site.compound)), site.compound_ground, skin.compound_tile() if skin != null else {})
	for d in site.decor:
		var r := _cells(Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"])))
		var c := Color.html(str(d["color"]))
		var rule := skin.decor_rule(str(d["color"])) if skin != null else {}
		if rule.has("tile") and not skin.tile(str(rule["tile"])).is_empty():
			PackSkin.draw_tile(self, skin.tile(str(rule["tile"])), r)
		elif rule.has("hide") or (rule.has("sprite") and skin.sprite(str(rule["sprite"])) != null):
			pass  # hidden, or standing up as scenery (see HouseView)
		elif str(d["shape"]) == "ellipse":
			draw_colored_polygon(_ellipse(r), c)
		else:
			draw_rect(r, c)
	for id in w.pack.rooms:
		_floor(w, str(id))
	_shadows(site)
	_sills(site)
	for id in w.pack.rooms:
		_label(w, str(id))


## A plain colour, or the skin's tile when it has one.
func _fill(r: Rect2, c: Color, t: Dictionary) -> void:
	if t.is_empty():
		draw_rect(r, c)
	else:
		PackSkin.draw_tile(self, t, r)


static func _cells(r: Rect2) -> Rect2:
	return Rect2(r.position * HouseSite.CELL, r.size * HouseSite.CELL)


static func _ellipse(r: Rect2, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(r.get_center() + Vector2(cos(a), sin(a)) * r.size * 0.5)
	return pts


func _floor(w: World, id: String) -> void:
	var r: Dictionary = w.pack.rooms[id]
	var rect := house.layout.room_rect(id)
	if rect.size == Vector2.ZERO:
		return
	var outdoor := bool(r.get("outdoor", false))
	var col := Color.html(str(r["floor"])) if r.get("floor") is String and Color.html_is_valid(str(r["floor"])) else Color(0, 0, 0, 0)
	var t := house.skin.floor_tile(id) if house.skin != null else {}
	if id in w.rooms_built:
		if outdoor:
			if not t.is_empty():
				PackSkin.draw_tile(self, t, rect)
			elif col.a > 0.0:
				draw_rect(rect, col)
			return
		_fill(rect, col if col.a > 0.0 else FLOOR, t)
		# Light comes in over the back (north) wall; the far side of the room is a little darker.
		var top := Color(SHADOW, 0.0)
		var bottom := Color(SHADOW, FLOOR_FALLOFF)
		draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))
		return
	if outdoor:
		_dashed(rect, DASH)
		return
	# A bare foundation: the yard's earth under a cream wash, so it darkens at night like
	# the floors and ground round it instead of standing out as a cold pale slab.
	draw_rect(rect, FOUNDATION_EDGE)
	var earth := house.skin.compound_tile() if house.skin != null else {}
	if earth.is_empty():
		draw_rect(rect.grow(-6), FOUNDATION)
	else:
		PackSkin.draw_tile(self, earth, rect.grow(-6))
		draw_rect(rect.grow(-6), Color(FOUNDATION, FOUNDATION_WASH))
	_dashed(rect.grow(-6), DASH)


## Soft shadows on the ground: east-west walls cast south, north-south walls cast east, and
## the west foot of a north-south wall gets a thin dark band.
func _shadows(site: HouseSite) -> void:
	if house.iso:
		_iso_shadows(site)
		return
	for run in site.runs():
		var line := int(run["line"])
		var kind := str(run["kind"])
		for at in range(int(run["a"]), int(run["b"])):
			if site.is_open(str(run["along"]), line, at):
				continue
			if run["along"] == "x":
				var y := line * HouseSite.CELL.y + WallPiece.thickness(kind) * 0.5
				var depth := WallPiece.SHADOW_FRONT
				var alpha := WallPiece.SHADOW_ALPHA * 0.85
				if kind == HouseSite.FENCE:
					depth = 8.0
					alpha = 0.3
				elif WallPiece.is_back(site, line, at):
					depth = WallPiece.SHADOW_BACK
					alpha = WallPiece.SHADOW_ALPHA
				elif kind == HouseSite.COMPOUND:
					depth = 16.0
				_ramp(Rect2(at * HouseSite.CELL.x, y, HouseSite.CELL.x, depth), alpha, true)
			else:
				var x := line * HouseSite.CELL.x
				var half := WallPiece.thickness(kind) * 0.5
				var r := Rect2(x + half, at * HouseSite.CELL.y, WallPiece.SHADOW_EAST, HouseSite.CELL.y)
				_ramp(r, WallPiece.SHADOW_ALPHA * 0.85 if kind != HouseSite.FENCE else 0.25, false)
				var ao := Rect2(x - half - WallPiece.AO_WIDTH, at * HouseSite.CELL.y, WallPiece.AO_WIDTH, HouseSite.CELL.y)
				var c0 := Color(SHADOW, 0.0)
				var c1 := Color(SHADOW, WallPiece.AO_ALPHA)
				draw_polygon(PackedVector2Array([ao.position, Vector2(ao.end.x, ao.position.y), ao.end, Vector2(ao.position.x, ao.end.y)]),
					PackedColorArray([c0, c1, c1, c0]))


## The 45° view: the back walls shade a band of floor inside them; cut walls only a thin one.
func _iso_shadows(site: HouseSite) -> void:
	for pair in [["x", site.h_walls], ["y", site.v_walls]]:
		var al: String = pair[0]
		for e in pair[1]:
			var ln: int = e.y if al == "x" else e.x
			var at: int = e.x if al == "x" else e.y
			var k := str(pair[1][e])
			if site.is_open(al, ln, at) or k == HouseSite.FENCE:
				continue
			var back := IsoWall.is_back(site, al, ln, at)
			var half := IsoWall.thickness(k) * 0.5
			var depth := 0.9 if back else 0.22
			var alpha := 0.42 if back else 0.22
			if al == "x":
				var y := (ln + half) * HouseSite.CELL.y
				_ramp(Rect2(at * HouseSite.CELL.x, y, HouseSite.CELL.x, depth * HouseSite.CELL.y), alpha, true)
			else:
				var x := (ln + half) * HouseSite.CELL.x
				_ramp(Rect2(x, at * HouseSite.CELL.y, depth * HouseSite.CELL.x, HouseSite.CELL.y), alpha, false)


## A shadow that is `alpha` dark at the wall and fades to nothing across `r` (downwards, or
## to the right).
func _ramp(r: Rect2, alpha: float, down: bool) -> void:
	var a := Color(SHADOW, alpha)
	var z := Color(SHADOW, 0.0)
	var cols := PackedColorArray([a, a, z, z]) if down else PackedColorArray([a, z, z, a])
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), cols)


## A grey stone sill in every open door.
func _sills(site: HouseSite) -> void:
	# (In the 45° view a plain slab: the picture drawn from above would be slanted.)
	var sill := house.skin.wall_sprite("sill") if house.skin != null and not house.iso else null
	for e in site.h_open:
		var x: float = e.x * HouseSite.CELL.x
		var y: float = e.y * HouseSite.CELL.y
		var r := Rect2(x + 2, y - 5, HouseSite.CELL.x - 4, 10)
		if sill != null:
			draw_texture_rect(sill, PackSkin.fit_rect(sill, Vector2(r.get_center().x, r.end.y + 4), Vector2(r.size.x, 24)), false)
			continue
		draw_rect(r, SILL)
		draw_rect(r, LINE, false, 1.5)
	for e in site.v_open:
		var x2: float = e.x * HouseSite.CELL.x
		var y2: float = e.y * HouseSite.CELL.y
		var r2 := Rect2(x2 - 6, y2 + 2, 12, HouseSite.CELL.y - 4)
		draw_rect(r2, SILL)
		draw_rect(r2, LINE, false, 1.5)


## The room's name written on the floor: indoors under the back wall, outdoors in the
## bottom-left corner; an unbuilt place has its name in the middle and the price under it.
func _label(w: World, id: String) -> void:
	var r: Dictionary = w.pack.rooms[id]
	var rect := house.layout.room_rect(id)
	if rect.size == Vector2.ZERO:
		return
	var font := ThemeDB.fallback_font
	var name := str(r.get("name", ""))
	if house.iso:
		_iso_label(w, id, r, rect, font, name)
		return
	if id in w.rooms_built:
		var at := rect.position + Vector2(14, 22) if not bool(r.get("outdoor", false)) else Vector2(rect.position.x + 10, rect.end.y - 10)
		var size := 15
		var site := house.layout.site
		if bool(r.get("outside", false)):
			# A place out on the map: a bigger name at its top-left, where nothing stands over it.
			at = rect.position + Vector2(10, 24)
			size = 20
		elif bool(r.get("outdoor", false)) and site.has_compound and int(r.get("y", 0)) + int(r.get("h", 0)) == site.compound.end.y:
			at.y -= WallPiece.COMPOUND_H + WallPiece.T_COMPOUND  # clear of the compound wall's face
		draw_string_outline(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, CREAM)
		draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LINE)
		return
	var mid := rect.get_center()
	draw_string_outline(font, Vector2(rect.position.x, mid.y - 4), name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, 4, CREAM)
	draw_string(font, Vector2(rect.position.x, mid.y - 4), name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(0.51, 0.39, 0.28))
	var cost := house.session.strings.t("money").replace("{n}", str(int(r.get("build_cost", 0))))
	var tw := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0
	var pill := Rect2(mid.x - tw * 0.5, mid.y + 6, tw, 24)
	var box := StyleBoxFlat.new()
	box.bg_color = PILL
	box.border_color = LINE
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	draw_style_box(box, pill)
	draw_string(font, Vector2(pill.position.x, pill.position.y + 17), cost, HORIZONTAL_ALIGNMENT_CENTER, tw, 13, LINE)


## The 45° view writes no names on the floor (the house shows a place's name while the
## pointer is on it, `HouseView.place_label`): an unbuilt room keeps only its price, on a
## pill in its middle.
func _iso_label(w: World, id: String, r: Dictionary, rect: Rect2, font: Font, _name: String) -> void:
	if id in w.rooms_built:
		return
	draw_set_transform_matrix(IsoMath.upright(rect.get_center()))
	var cost := house.session.strings.t("money").replace("{n}", str(int(r.get("build_cost", 0))))
	var tw := font.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0
	var pill := Rect2(-tw * 0.5, -12, tw, 24)
	var box := StyleBoxFlat.new()
	box.bg_color = PILL
	box.border_color = LINE
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	draw_style_box(box, pill)
	draw_string(font, Vector2(pill.position.x, pill.position.y + 17), cost, HORIZONTAL_ALIGNMENT_CENTER, tw, 13, LINE)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _dashed(rect: Rect2, color: Color) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	for seg in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		draw_dashed_line(seg[0], seg[1], color, 2.0, 8.0)
