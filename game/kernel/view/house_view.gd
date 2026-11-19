class_name HouseView
extends Node2D
## Draws the house (rooms, furniture, messes, collectibles) and keeps one PersonView per
## living person. Panning moves this node; its scale fits a small house to the window, and a
## house bigger than the window opens at scale 1 on the entrance room, zooms with the wheel
## and scrolls by itself while something is carried near an edge. Reads the World, never
## writes it.

## The window size used when this node is not in a tree (tests).
const VIEW_SIZE := Vector2(1280, 720)
const BOTTOM_BAR := 96.0
## Space kept clear around the fitted house, and the zoom range.
const FIT_MARGIN := 24.0
const MIN_SCALE := 0.36
const MAX_SCALE := 2.0
## One wheel notch zooms by this factor.
const WHEEL_ZOOM := 1.1
## Carrying something this close to an edge of the house area scrolls toward that edge.
const EDGE := 40.0
const EDGE_SPEED := 600.0
## Following a person: the gap to the middle shrinks by this rate per second (about 99 %
## within half a second); under a pixel it closes at once.
const FOLLOW_RATE := 10.0
const SPREAD := 20.0
const NIGHT_COLOR := Color(0.45, 0.5, 0.7)

var session: GameSession
var layout: HouseLayout
var people: Dictionary = {}  # uid -> PersonView
var pets: Dictionary = {}  # uid -> PetView, for the animals at home
var _modulate: CanvasModulate
## With a site plan: the ground under everything, and the standing walls (sorted by y with
## the people). Null / empty without one.
var ground: HouseGround
var walls: Array = []  # WallPiece (seen from above) or IsoWall (45°)
var _site_version := -1
## The 45° view (the pack's art asks for it and there is a site plan): everything standing
## lives on `stage`, whose transform `proj` slants the plan into diamonds; each standing node
## takes the inverse basis so its pictures stay upright, and the stage is sorted by how far
## in front each one stands. Without it `stage` is this node and `proj` the identity.
var iso := false
var stage: Node2D
var proj := Transform2D.IDENTITY
## The pack's art (`art.json`); disabled when the pack has none, and then everything is drawn
## the whitebox way. Pictures for furniture and scenery stand as PropPieces (sorted by y with
## the people); hover and the arrange ghost then go on an overlay above them.
var skin: PackSkin
var props: Dictionary = {}  # object uid -> PropPiece
var scenery: Array[PropPiece] = []
var _overlay: Node2D
## With the pack's art: the people's name plates, on a layer above everything (walls, the
## gatehouse) and kept from overlapping one another.
var _labels: Node2D
## Moving further than this between press and release is a drag, not a click.
const CLICK_SLOP := 6.0

signal person_clicked(uid: int)
signal pet_clicked(uid: int)

var drag: DragController
var arrange: ArrangeMode
## The last `layout.pick` result under a dragged person; {} when nothing is dragged.
var hover: Dictionary = {}
## Whether the left button is physically down; replaceable so tests can drive it.
var button_down: Callable = func() -> bool: return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

## Returns true while something covers the house; set by Main.
var blocked: Callable = func() -> bool: return false

var _pressed := false
var _press_uid := -1
var _press_pet := -1
var _press_at := Vector2.ZERO
var _last := Vector2.ZERO
var _moved := false
## Whether the current press belongs to arrange mode (a picked piece), not to panning.
var _arranging := false
## The last pointer position seen over the house (screen), for edge scrolling.
var _cursor := Vector2.ZERO
var _has_cursor := false
## The person the view follows (-1: none). Set by an explicit select; a manual pan or the
## person leaving ends it; carrying a person or arrange mode only pauses it.
var follow_uid := -1


static func night_amount(hour: float) -> float:
	if hour >= 6.0 and hour <= 18.0:
		return 0.0
	if hour >= 20.0 or hour <= 4.0:
		return 1.0
	if hour > 18.0:
		return (hour - 18.0) / 2.0
	return (6.0 - hour) / 2.0


func setup(s: GameSession) -> void:
	session = s
	layout = HouseLayout.new(s.pack)
	skin = PackSkin.new(s.pack)
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	stage = self
	if layout.site.enabled and skin.iso():
		iso = true
		proj = IsoMath.basis()
		stage = Node2D.new()
		stage.name = "Stage"
		stage.transform = proj
		add_child(stage)
	if skin.enabled:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_overlay = Node2D.new()
		_overlay.z_index = 5
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)
		_labels = Node2D.new()
		_labels.z_index = 6
		_labels.draw.connect(_draw_labels)
		add_child(_labels)
	if layout.site.enabled:
		y_sort_enabled = not iso
		ground = HouseGround.new()
		ground.house = self
		ground.z_index = -1
		ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		stage.add_child(ground)
		_build_scenery()
	scale = Vector2.ONE * start_scale(_view_size())
	position = _centred()
	if fit_scale(_view_size()) < 1.0:
		var entrance := _entrance_rect()
		if entrance.size != Vector2.ZERO:
			position = _area_centre() - proj * entrance.get_center() * scale
	pan(Vector2.ZERO)


func _enter_tree() -> void:
	var vp := get_viewport()
	if not vp.size_changed.is_connected(_refit):
		vp.size_changed.connect(_refit)
	if layout != null:
		_refit()


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp.size_changed.is_connected(_refit):
		vp.size_changed.disconnect(_refit)


## The visible viewport size; VIEW_SIZE when not in a tree.
func _view_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else VIEW_SIZE


## The largest uniform scale at which the house (walls included) fits the area above the
## bottom bar with FIT_MARGIN on every side, clamped to [MIN_SCALE, MAX_SCALE].
func fit_scale(viewport_size: Vector2) -> float:
	var b := view_bounds()
	var room := Vector2(viewport_size.x, viewport_size.y - BOTTOM_BAR) - Vector2.ONE * FIT_MARGIN * 2.0
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return 1.0
	return clampf(minf(room.x / b.size.x, room.y / b.size.y), MIN_SCALE, MAX_SCALE)


## The scale the house opens at: the fitted scale for a house that fits at scale 1 or more,
## else 1 (a big house is shown life-size and panned).
func start_scale(viewport_size: Vector2) -> float:
	return clampf(maxf(fit_scale(viewport_size), ISO_START_SCALE if iso else 1.0), MIN_SCALE, MAX_SCALE)


## The 45° view opens a little closer than 1, so people stand about as tall as in the target
## picture (ART_DIRECTION section 11: a grown-up ~90 px against a 64 px cell).
const ISO_START_SCALE := 1.1


## The smallest zoom the wheel reaches: the whole house in view, but never above 1.
func min_zoom(viewport_size: Vector2) -> float:
	return minf(fit_scale(viewport_size), 1.0)


## The middle of the area above the bottom bar (screen).
func _area_centre() -> Vector2:
	var v := _view_size()
	return Vector2(v.x, v.y - BOTTOM_BAR) * 0.5


## Where this node sits so the house is centred above the bottom bar at the current scale.
func _centred() -> Vector2:
	return _area_centre() - view_bounds().get_center() * scale


## How far the walls of the 45° view rise above the map's top corner.
const ISO_HEADROOM := 120.0

## The house's bounds as drawn (this node's coordinates): the layout's bounds, or in the 45°
## view the rect round the map's diamond with room above for the back walls.
func view_bounds() -> Rect2:
	var b := layout.bounds()
	if not iso:
		return b
	var r := IsoMath.view_rect(b)
	return Rect2(r.position.x, r.position.y - ISO_HEADROOM, r.size.x, r.size.y + ISO_HEADROOM)


## A plan point (house coordinates) -> this node's coordinates (the same without the 45° view).
func view_of(p: Vector2) -> Vector2:
	return proj * p


## Adds a standing node (person, animal, picture, wall) to the stage; in the 45° view it takes
## the inverse slant so it draws upright at its plan position.
func _place(n: Node2D) -> void:
	stage.add_child(n)
	if iso:
		var at := n.position
		n.transform = IsoMath.inverse()
		n.position = at


## The 45° view: the stage's children in drawing order, back to front by `sort_depth` (the
## ground first). Only moves the ones out of place.
func _sort_stage() -> void:
	if not iso:
		return
	var kids: Array = []
	for c in stage.get_children():
		if c != ground and c is Node2D:
			kids.append(c)
	var keyed: Array = []
	for i in kids.size():
		keyed.append([sort_depth(kids[i]), i, kids[i]])
	keyed.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var base := 1 if ground != null and ground.get_parent() == stage else 0
	for i in keyed.size():
		var n: Node = keyed[i][2]
		if n.get_index() != base + i:
			stage.move_child(n, base + i)


## How far in front a standing node is drawn (view y of its foot, plus its own bias).
func sort_depth(n: Node2D) -> float:
	var d := (proj * n.position).y
	if "sort_bias" in n:
		d += float(n.sort_bias)
	return d


## The floor of the first built indoor room in pack order (where newcomers appear).
func _entrance_rect() -> Rect2:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return Rect2()
	for id in w.pack.rooms:
		if id in w.rooms_built and not bool(w.pack.rooms[id].get("outdoor", false)):
			return layout.room_rect(id)
	return Rect2()


## Sets the zoom to `s`, keeping the player's pan (scaled along) within the clamp.
func zoom_to(s: float) -> void:
	var off := (position - _centred()) / scale.x
	scale = Vector2.ONE * s
	position = _centred() + off * s
	pan(Vector2.ZERO)


## Zooms by `factor` around a point on the screen: the house point under it stays under it
## (unless the pan clamp has to move the house). The zoom stays within
## [min_zoom, MAX_SCALE].
func zoom_at(screen: Vector2, factor: float) -> void:
	var v := _view_size()
	var s := clampf(scale.x * factor, min_zoom(v), MAX_SCALE)
	var under := proj * world_pos(screen)
	scale = Vector2.ONE * s
	position = screen - under * s
	pan(Vector2.ZERO)


func _refit() -> void:
	zoom_to(start_scale(_view_size()))


## A point in the house's coordinates -> the screen.
func to_screen(house: Vector2) -> Vector2:
	return transform * (proj * house)


## A point of this node's own coordinates (the view's: see `view_of`) -> the screen.
func view_to_screen(v: Vector2) -> Vector2:
	return transform * v


## A point on the screen -> the house's coordinates.
func world_pos(screen: Vector2) -> Vector2:
	return proj.affine_inverse() * (transform.affine_inverse() * screen)


## Moves the house by `by` (screen pixels), clamped so that every point of the house can be
## brought to the middle of the house area and no further; on an axis where the scaled house
## is smaller than the area it stays centred.
func pan(by: Vector2) -> void:
	var b := view_bounds()
	var v := _view_size()
	var area := Vector2(v.x, v.y - BOTTOM_BAR)
	var c := area * 0.5
	var lo := c - b.end * scale
	var hi := c - b.position * scale
	var at := (position + by).clamp(lo, hi)
	var size := b.size * scale
	var mid := c - b.get_center() * scale
	if size.x <= area.x:
		at.x = mid.x
	if size.y <= area.y:
		at.y = mid.y
	position = at


func refresh() -> void:
	var w := session.world
	var alive := {}
	if w != null and w.phase != "invalid":
		_modulate.color = Color.WHITE.lerp(NIGHT_COLOR, night_amount(w.local_hour()))
		_update_site(w)
		for p in w.people:
			if p.alive:
				alive[p.uid] = p
	for uid in people.keys():
		if not alive.has(uid):
			if uid == follow_uid:
				follow_uid = -1
			people[uid].queue_free()
			stage.remove_child(people[uid])
			people.erase(uid)
	for uid in alive:
		if not people.has(uid):
			var pv := PersonView.new()
			pv.house = self
			_place(pv)
			pv.setup(alive[uid], session)
			if layout.site.enabled:
				# Newcomers appear on an open cell nobody else stands on.
				var occupied := {}
				for o in people:
					occupied[layout.site.cell_of(people[o].position)] = true
				pv.position = layout.stop_point(pv.position, occupied)
				pv.base_target = pv.position
				pv.target = pv.position
			people[uid] = pv
	for uid in people:
		people[uid].refresh()
	_spread(w)
	_refresh_pets(w)
	_sync_props()
	queue_redraw()


## People heading for the same spot: with a site plan the first one there keeps it and the
## others take the nearest open cells (at furniture: another side of it); without one they
## stand SPREAD apart in a row.
func _spread(w: World) -> void:
	var order: Array = people.keys()
	if layout.site.enabled:
		# Whoever already stands at their spot keeps it.
		var there := order.filter(func(u): return people[u].position.distance_to(people[u].base_target) <= PersonView.ARRIVED)
		order = there + order.filter(func(u): return not there.has(u))
		var cells := {}
		var seated := {}  # object uid -> how many sit or lie on it already
		for uid in order:
			var pv: PersonView = people[uid]
			var t := pv.base_target
			if pv.on_object and w != null:
				# Side by side along the piece, within its width.
				var r := layout.object_rect(pv.use_object, w.pack)
				var k := int(seated.get(int(pv.use_object.uid), 0))
				seated[int(pv.use_object.uid)] = k + 1
				var steps := [0.0, -1.0, 1.0, -2.0, 2.0]
				t.x = clampf(t.x + float(steps[mini(k, 4)]) * 34.0, r.position.x + 14.0, r.end.x - 14.0)
				pv.target = t
				continue
			if cells.has(layout.site.cell_of(t)):
				if not pv.use_object.is_empty() and w != null:
					t = layout.stand_pos(pv.use_object, w.pack, cells)
				else:
					t = layout.stop_point(t, cells)
			for dx in [-HouseSite.FEET, 0.0, HouseSite.FEET]:
				cells[layout.site.cell_of(t + Vector2(dx, 0))] = true
			pv.target = t
		return
	var taken: Array = []
	for uid in order:
		var pv: PersonView = people[uid]
		var t := pv.base_target
		var n := 0
		while taken.any(func(o: Vector2): return o.distance_to(t) < 1.0):
			n += 1
			t = pv.base_target + Vector2(SPREAD * n, 0)
		taken.append(t)
		pv.target = t


## Pictures standing on the map that the sim knows nothing of: decor shapes the skin turns
## into sprites (as wide as the shape, standing on its bottom edge) and the skin's scenery.
func _build_scenery() -> void:
	if not skin.enabled:
		return
	var cell := HouseSite.CELL
	var list: Array = []
	for d in layout.site.decor:
		var rule := skin.decor_rule(str(d["color"]))
		var tex := skin.sprite(str(rule.get("sprite", "")))
		if tex != null:
			list.append({"tex": tex, "x": float(d["x"]) + float(d["w"]) * 0.5, "y": float(d["y"]) + float(d["h"]), "w": float(d["w"])})
	list.append_array(skin.scenery())
	for e in list:
		var w: float = float(e["w"]) * cell.x
		var piece := PropPiece.new()
		var at := Vector2(float(e["x"]) * cell.x, float(e["y"]) * cell.y)
		if iso:
			# Upright on its foot; a cell's diamond is TILE.x wide on the screen.
			var vw: float = float(e["w"]) * IsoMath.TILE.x * skin.scenery_scale()
			piece.place_at(e["tex"], PackSkin.fit_rect(e["tex"], Vector2(0, 4), Vector2(vw, vw * 3.0)), at)
		else:
			piece.place(e["tex"], PackSkin.fit_rect(e["tex"], at, Vector2(w, w * 3.0)))
		scenery.append(piece)
		_place(piece)


## The picture an object stands as, or null (drawn as a block).
func object_picture(o: Dictionary) -> Texture2D:
	return skin.object_sprite(str(o.type)) if skin != null else null


## One PropPiece per object with a picture, kept in step with the world's objects.
func _sync_props() -> void:
	var w := session.world if session != null else null
	var seen := {}
	if w != null and w.phase != "invalid" and skin != null and skin.enabled:
		var lifted := arrange.held_uid if _arrange_on() else -1
		for o in w.objects:
			var tex := object_picture(o)
			if tex == null:
				continue
			var uid := int(o.uid)
			seen[uid] = true
			var piece: PropPiece = props.get(uid)
			if piece == null:
				piece = PropPiece.new()
				piece.object_uid = uid
				piece.house = self
				props[uid] = piece
				_place(piece)
			var a := 0.35 if uid == lifted else 1.0
			var lift := PropPiece.ON_LIFT if skin.sat_on(str(o.type)) else 0.0
			if iso:
				var spot := iso_picture(o, tex, w)
				var r: Rect2 = spot.rect
				if r != piece.rect or tex != piece.tex or a != piece.alpha or spot.flip != piece.flip or spot.at != piece.position:
					if ground != null and (r != piece.rect or spot.at != piece.position):
						ground.queue_redraw()  # the names on the floor keep clear of the pictures
					piece.alpha = a
					piece.flip = spot.flip
					piece.sort_bias = FURNITURE_BIAS - lift * IsoMath.TILE.y / HouseSite.CELL.y
					piece.place_at(tex, r, spot.at)
				else:
					piece.queue_redraw()
				continue
			var fit := picture_rect(o, tex, w)
			if fit != piece.rect or tex != piece.tex or a != piece.alpha or lift != piece.sort_lift:
				piece.alpha = a
				piece.sort_lift = lift
				piece.place(tex, fit)
			else:
				piece.queue_redraw()
	for uid in props.keys():
		if not seen.has(uid):
			props[uid].queue_free()
			stage.remove_child(props[uid])
			props.erase(uid)


## Where the picture of furniture `o` goes: standing on the bottom of its footprint, no wider
## than 90 % of it and at most WALL_LEAN above it (furniture on a room's back row leans on
## the wall); kept clear of a side wall standing on either edge of the footprint, so it never
## reaches over a wall into the room next door.
const WALL_LEAN := 24.0
const WALL_GAP := 8.0
func picture_rect(o: Dictionary, tex: Texture2D, w: World) -> Rect2:
	var r := layout.object_rect(o, w.pack)
	var left := 0.0
	var right := 0.0
	if layout.site.enabled:
		var c := HouseLayout.cells_of(r)
		for y in range(c.position.y, c.end.y):
			if layout.site.v_walls.has(Vector2i(c.position.x, y)):
				left = WALL_GAP
			if layout.site.v_walls.has(Vector2i(c.end.x, y)):
				right = WALL_GAP
	var span := r.size.x - left - right
	var mid := r.position.x + left + span * 0.5
	return PackSkin.fit_rect(tex, Vector2(mid, r.end.y + 2.0), Vector2(minf(r.size.x * 0.9, span), r.size.y + WALL_LEAN))


## The 45° view: where the picture of furniture `o` goes. {at: its plan foot (the middle of
## the footprint, which it sorts by), rect: the picture upright round that foot (view
## pixels), flip: mirrored}. The picture is as wide as the footprint's diamond and stands on
## its bottom corner; a picture whose long side runs the other way than the footprint's is
## mirrored (pictures stand against a north wall; mirrored they stand against a west one).
const ISO_FILL := 1.0
## Furniture sorts this far in front of its middle (0.3 of a cell's depth), so a long piece
## against a back wall is drawn over all of the wall behind it.
const FURNITURE_BIAS := 4.8
func iso_picture(o: Dictionary, tex: Texture2D, w: World) -> Dictionary:
	var r := layout.object_rect(o, w.pack)
	var at := r.get_center()
	var d := IsoMath.diamond(r)
	var foot := proj * at
	var axis := skin.object_axis(str(o.type))
	var long_y := r.size.y / HouseSite.CELL.y > r.size.x / HouseSite.CELL.x
	var flip := axis != "" and long_y != (axis == "y")
	var width := (d[1].x - d[3].x) * ISO_FILL * skin.object_scale(str(o.type))
	if axis == "":
		# An old picture drawn from above: no wider than the footprint's middle.
		width = (d[1].x - d[3].x) * 0.7
	var ts := Vector2(tex.get_size())
	var k := width / ts.x
	var size := ts * k
	var mid_x := (d[1].x + d[3].x) * 0.5 - foot.x
	var bottom := d[2].y - foot.y + 6.0
	return {"at": at, "rect": Rect2(mid_x - size.x * 0.5, bottom - size.y, size.x, size.y), "flip": flip}


## A picture's rect on the view, less the transparent margin round the drawing (what the
## overlap rules compare).
static func picture_core(r: Rect2) -> Rect2:
	return r.grow_individual(-r.size.x * 0.12, -r.size.y * 0.12, -r.size.x * 0.12, -r.size.y * 0.04)


## How much (0..1 of the smaller) two picture cores overlap.
static func picture_overlap(a: Rect2, b: Rect2) -> float:
	var x := picture_core(a).intersection(picture_core(b))
	if not x.has_area():
		return 0.0
	return x.get_area() / minf(picture_core(a).get_area(), picture_core(b).get_area())


## Most a placed piece's picture may overlap another's.
const PICTURE_OVERLAP_MAX := 0.05


## The 45° view: whether a piece of `type` put at `room` (x, y) would stand its picture over
## another piece's (beyond PICTURE_OVERLAP_MAX); piece `except` (the one being moved) aside.
func picture_blocks(type: String, room: String, x: int, y: int, except := -1) -> bool:
	var w := session.world if session != null else null
	if not iso or w == null:
		return false
	var o := {"uid": -1, "type": type, "room": room, "x": x, "y": y}
	var tex := object_picture(o)
	if tex == null:
		return false
	var spot := iso_picture(o, tex, w)
	var mine := Rect2(proj * spot.at + (spot.rect as Rect2).position, (spot.rect as Rect2).size)
	for uid in props:
		if int(uid) == except:
			continue
		var p: PropPiece = props[uid]
		if picture_overlap(mine, Rect2(proj * p.position + p.rect.position, p.rect.size)) > PICTURE_OVERLAP_MAX:
			return true
	return false


## One PetView per animal at home; the ones that ran off or died are taken away.
func _refresh_pets(w: World) -> void:
	var home := {}
	if w != null and w.phase != "invalid":
		for p in w.pets:
			if p.home():
				home[p.uid] = p
	for uid in pets.keys():
		if not home.has(uid):
			stage.remove_child(pets[uid])
			pets[uid].queue_free()
			pets.erase(uid)
	for uid in home:
		if not pets.has(uid):
			var pv := PetView.new()
			pv.house = self
			_place(pv)
			pv.setup(home[uid], session)
			pets[uid] = pv
		pets[uid].refresh()


## The uid of the animal under a point in the house's coordinates, or -1.
func pet_at(wpos: Vector2) -> int:
	var best := -1
	var best_y := -INF
	for uid in pets:
		var pv: PetView = pets[uid]
		if pv.hit(wpos) and (proj * pv.position).y >= best_y:
			best = uid
			best_y = (proj * pv.position).y
	return best


## Rebuilds the walls and redraws the ground when the rooms built changed.
func _update_site(w: World) -> void:
	if ground == null:
		return
	layout.site.update(w.built_set())
	layout.site.set_furniture(layout.furniture_cells(w))
	if layout.site.version == _site_version:
		return
	_site_version = layout.site.version
	for p in walls:
		p.get_parent().remove_child(p)
		p.queue_free()
	if iso:
		walls = IsoWall.build_all(layout.site, skin, session.world.pack)
	else:
		walls = WallPiece.build_all(layout.site)
	for p in walls:
		p.skin = skin
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_place(p)
	ground.queue_redraw()


## Walls go see-through while someone stands behind them.
func _fade_walls() -> void:
	if walls.is_empty():
		return
	var feet: Array = []
	for uid in people:
		feet.append(people[uid].position)
	if iso:
		# [view foot, depth] of everyone: a wall fades for whoever stands behind it under it.
		var seen: Array = []
		for f in feet:
			seen.append([proj * f, (proj * f).y])
		for p in walls:
			p.fade_for_view(seen, sort_depth(p))
		return
	for p in walls:
		p.fade_for(feet)


func tick(delta: float) -> void:
	_edge_scroll(delta)
	for uid in people:
		people[uid].tick(delta)
	for uid in pets:
		pets[uid].tick(delta)
	_fade_walls()
	_sort_stage()
	_follow_step(delta)
	if _labels != null:
		_labels.queue_redraw()


## Starts following `uid` (again: re-centres on them).
func follow(uid: int) -> void:
	follow_uid = uid


func unfollow() -> void:
	follow_uid = -1


## Whether following is waiting: a person is carried or arrange mode is open.
func _follow_paused() -> bool:
	return _carrying() or _arrange_on()


## The followed person's view, or null when not following (or paused).
func _followed() -> PersonView:
	if follow_uid < 0 or not people.has(follow_uid) or _follow_paused():
		return null
	return people[follow_uid]


## Eases the pan so the followed person heads for the middle of the house area; the pan
## clamp still applies (near the house edge they may stay off-centre).
func _follow_step(delta: float) -> void:
	if follow_uid >= 0 and not people.has(follow_uid):
		follow_uid = -1
	var pv := _followed()
	if pv == null or delta <= 0.0:
		return
	var gap := _area_centre() - to_screen(pv.position)
	if gap.length() <= 1.0:
		pan(gap)
	else:
		pan(gap * (1.0 - exp(-FOLLOW_RATE * delta)))


## How high (screen pixels at this zoom) the top of the wall stands at map point `map`
## (cells: the middle of a walled edge); -1 when this view has no say (seen from above the
## caller keeps its own height).
func wall_top_at(map: Vector2) -> float:
	if not iso:
		return -1.0
	var site := layout.site
	var along := "x" if absf(map.y - roundf(map.y)) < 0.01 else "y"
	var line := int(roundf(map.y)) if along == "x" else int(roundf(map.x))
	var at := int(floorf(map.x)) if along == "x" else int(floorf(map.y))
	var walls := site.h_walls if along == "x" else site.v_walls
	var e := Vector2i(at, line) if along == "x" else Vector2i(line, at)
	if not walls.has(e):
		return 0.0
	return IsoWall.face_height(site, str(walls[e]), along, line, at) * scale.y


## What is under plan point `pos` (see `HouseLayout.pick`). In the 45° view a furniture
## picture stands up over the cells behind its footprint: a point on the picture is that piece
## (the one in front when pictures overlap), unless something lies on the ground right there.
func pick(w: World, pos: Vector2, furniture_only := false) -> Dictionary:
	var hit := layout.pick(w, pos, furniture_only)
	if not iso or str(hit.get("kind", "")) in ["mark", "collectible", "mess"]:
		return hit
	var v := proj * pos
	var best := -1
	var best_d := -INF
	for uid in props:
		var p: PropPiece = props[uid]
		if p.tex == null:
			continue
		var r := Rect2(proj * p.position + p.rect.position, p.rect.size)
		r = r.grow_individual(-r.size.x * 0.12, -r.size.y * 0.06, -r.size.x * 0.12, 0.0)
		if r.has_point(v) and sort_depth(p) > best_d:
			best = int(uid)
			best_d = sort_depth(p)
	if best >= 0:
		var o := w.object(best)
		if not o.is_empty() and str(o.room) in w.rooms_built:
			return {"kind": "object", "uid": best, "room": str(o.room)}
	return hit


## Brings collectible `uid` to the middle of the house area (ends following); false when it
## is gone.
func look_at_collectible(uid: int) -> bool:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return false
	for c in w.collectibles:
		if int(c.uid) == uid:
			follow_uid = -1
			pan(_area_centre() - to_screen(layout.cell_center(str(c.room), int(c.x), int(c.y))))
			return true
	return false


## A wheel notch: zooms around the followed person while following, else around `screen`.
func wheel_zoom(screen: Vector2, factor: float) -> void:
	var pv := _followed()
	zoom_at(to_screen(pv.position) if pv != null else screen, factor)


## A pan the player makes by dragging the ground: it ends following.
func _manual_pan(by: Vector2) -> void:
	follow_uid = -1
	pan(by)


## Whether a person is being carried or arrange mode has a piece in hand.
func _carrying() -> bool:
	return (drag != null and drag.dragging >= 0) or (_arrange_on() and arrange.held_type != "")


## While something is carried, a pointer within EDGE of an edge of the house area pans the
## house toward that edge at EDGE_SPEED; whatever is carried keeps following the pointer.
func _edge_scroll(delta: float) -> void:
	if not _has_cursor or not _carrying() or delta <= 0.0:
		return
	var v := _view_size()
	var area := Vector2(v.x, v.y - BOTTOM_BAR)
	var dir := Vector2.ZERO
	if _cursor.x <= EDGE:
		dir.x = 1.0
	elif _cursor.x >= area.x - EDGE:
		dir.x = -1.0
	if _cursor.y <= EDGE:
		dir.y = 1.0
	elif _cursor.y >= area.y - EDGE:
		dir.y = -1.0
	if dir == Vector2.ZERO:
		return
	var before := position
	pan(dir * EDGE_SPEED * delta)
	if position == before:
		return
	if drag != null and drag.dragging >= 0:
		drag.move(world_pos(_cursor))
	elif _arrange_on():
		arrange.hover(world_pos(_cursor))


func _see_cursor(screen: Vector2) -> void:
	_cursor = screen
	_has_cursor = true


## The uid of the person under a point in the house's coordinates (the one drawn on top
## wins), or -1.
func person_at(wpos: Vector2, except := -1) -> int:
	var best := -1
	var best_y := -INF
	for uid in people:
		if uid == except:
			continue
		var pv: PersonView = people[uid]
		if pv.hit(wpos) and (proj * pv.position).y >= best_y:
			best = uid
			best_y = (proj * pv.position).y
	return best


func set_hover(h: Dictionary) -> void:
	hover = h
	queue_redraw()


func _arrange_on() -> bool:
	return arrange != null and arrange.active


## The person the pointer is pressed on (-1: none).
func pressing_uid() -> int:
	return _press_uid if _pressed else -1


func press(screen: Vector2) -> void:
	_see_cursor(screen)
	_pressed = true
	_moved = false
	_press_at = screen
	_last = screen
	if _arrange_on():
		_press_uid = -1
		_arranging = arrange.house_press(world_pos(screen))
		return
	_press_uid = person_at(world_pos(screen))
	if people.has(_press_uid):
		people[_press_uid].queue_redraw()  # the ring under them while pressed
	_press_pet = pet_at(world_pos(screen)) if _press_uid < 0 else -1


func move(screen: Vector2, relative: Vector2) -> void:
	_see_cursor(screen)
	if _arrange_on():
		# A press that did not pick a piece up pans once it moves past the slop, also with a
		# piece in hand; the ghost keeps following the pointer.
		if _pressed:
			_last = screen
			if not _moved:
				if screen.distance_to(_press_at) > CLICK_SLOP:
					_moved = true
					if not _arranging:
						_manual_pan(screen - _press_at)
			elif not _arranging:
				_manual_pan(relative)
		arrange.hover(world_pos(screen))
		return
	if not _pressed:
		return
	_last = screen
	if not _moved:
		if screen.distance_to(_press_at) <= CLICK_SLOP:
			return
		_moved = true
		if _press_uid >= 0 and drag != null:
			drag.begin(_press_uid)
		else:
			# Catch up on everything since the press, not only this event's step.
			_manual_pan(screen - _press_at)
			return
	if drag != null and drag.dragging >= 0:
		drag.move(world_pos(screen))
	else:
		_manual_pan(relative)


func release(screen: Vector2) -> void:
	if not _pressed:
		return
	if _arrange_on():
		arrange.house_release(world_pos(screen), _moved)
		_pressed = false
		_arranging = false
		_moved = false
		return
	if _moved:
		if drag != null and drag.dragging >= 0:
			drag.drop(world_pos(screen))
	elif _press_uid >= 0:
		person_clicked.emit(_press_uid)
	elif _press_pet >= 0:
		pet_clicked.emit(_press_pet)
	if people.has(_press_uid):
		people[_press_uid].queue_redraw()
	_pressed = false
	_press_uid = -1
	_press_pet = -1
	_moved = false


func _unhandled_input(event: InputEvent) -> void:
	if blocked.call():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press(event.position)
		else:
			release(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		wheel_zoom(event.position, WHEEL_ZOOM if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _arrange_on():
		arrange.cancel_held()
	elif event is InputEventMouseMotion and _pressed:
		if not button_down.call():
			# The release went to a HUD control; finish where the pointer last was.
			release(_last)
		else:
			move(event.position, event.relative)
	elif event is InputEventMouseMotion and _arrange_on():
		_see_cursor(event.position)
		arrange.hover(world_pos(event.position))


func _draw() -> void:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return
	var font := ThemeDB.fallback_font
	for id in ([] if ground != null else w.pack.rooms):
		var r: Dictionary = w.pack.rooms[id]
		var rect := layout.room_rect(id)
		var outdoor := bool(r.get("outdoor", false))
		if id in w.rooms_built:
			if outdoor:
				draw_rect(rect, Color(0.8, 0.9, 0.76))
			else:
				draw_rect(rect, Color(0.94, 0.91, 0.84))
				draw_rect(Rect2(rect.position.x, rect.position.y - HouseLayout.WALL, rect.size.x, HouseLayout.WALL), Color(0.7, 0.62, 0.52))
			var label_at := rect.position + Vector2(6, 16) if outdoor else rect.position + Vector2(6, -9)
			draw_string(font, label_at, str(r.name), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 14, Color(0.12, 0.1, 0.08))
		else:
			_dashed(rect, Color(0.8, 0.8, 0.8))
			var cost := session.strings.t("money").replace("{n}", str(int(r.get("build_cost", 0))))
			draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 - 6), str(r.name), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color(0.95, 0.95, 0.95))
			draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 + 14), cost, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, Color(0.9, 0.85, 0.6))
	var lifted := arrange.held_uid if _arrange_on() else -1
	for o in w.objects:
		if object_picture(o) != null:
			continue
		var t: Dictionary = w.pack.object_types.get(str(o.type), {})
		var rect := layout.object_rect(o, w.pack)
		var hue := float(hash(str(t.get("category", ""))) % 360) / 360.0
		var faded := 0.35 if int(o.uid) == lifted else 1.0
		if iso:
			_iso_block(rect, Color.from_hsv(hue, 0.4, 0.82, faded), faded)
			draw_string(font, proj * rect.get_center() + Vector2(-rect.size.x, -10), str(t.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x * 2.0, 12, Color(0.15, 0.15, 0.15))
			continue
		if ground != null:
			# Standing up a little: a soft shadow under it and a darker front face.
			var foot := Vector2(rect.get_center().x, rect.end.y - 2)
			draw_colored_polygon(HouseGround._ellipse(Rect2(foot - Vector2(rect.size.x * 0.475, 6), Vector2(rect.size.x * 0.95, 12))), Color(HouseGround.SHADOW, 0.3 * faded))
			draw_rect(rect.grow(-2), Color.from_hsv(hue, 0.4, 0.82, faded))
			draw_rect(Rect2(rect.position.x + 2, rect.end.y - 12, rect.size.x - 4, 10), Color.from_hsv(hue, 0.45, 0.62, faded))
			draw_rect(rect.grow(-2), Color(HouseGround.LINE, faded), false, 2.0)
		else:
			draw_rect(rect.grow(-2), Color.from_hsv(hue, 0.4, 0.82, faded))
		draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 + 4), str(t.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(0.15, 0.15, 0.15))
	_draw_dishes(w)
	var cellv := Vector2(IsoMath.TILE.x * 0.8, IsoMath.TILE.y * 1.3) if iso else HouseLayout.CELL * Vector2(1.15, 0.9)
	for m in w.messes:
		var plan_at := layout.cell_center(str(m.room), int(m.x), int(m.y))
		var at := proj * plan_at
		var mt: Dictionary = w.pack.mess_types.get(str(m.type), {})
		var pic := skin.mess_sprite(str(m.type)) if skin != null else null
		if pic != null:
			# Flat on the ground, about a cell wide, no outline: drawn centred on the cell.
			draw_texture_rect(pic, PackSkin.fit_rect(pic, at + Vector2(0, (IsoMath.TILE.y if iso else HouseLayout.CELL.y) * 0.4), cellv), false)
			continue
		if str(mt.get("look", "")) == "patch":
			# Lying over the ground (snow): soft irregular patches; no label, there would be
			# one on every patch (hovering still outlines it).
			draw_set_transform_matrix(proj)
			_soft_patch(plan_at, pack_color(mt, MESS_COLOR), int(m.uid))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			continue
		draw_rect(Rect2(at - Vector2(8, 6), Vector2(16, 12)), pack_color(mt, MESS_COLOR))
		_small_name(font, at, thing_name(w.pack.mess_types, str(m.type)))
	for c in w.collectibles:
		var at := proj * layout.cell_center(str(c.room), int(c.x), int(c.y))
		if skin != null and skin.enabled and not c.has("story"):
			var pic := skin.collectible_sprite(str(c.type))
			_draw_pickup(at, pic)
			if pic != null:
				continue
		if c.has("story"):
			# An old thing of the house: a pale scrap, turned on its corner.
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)]), Color(0.93, 0.88, 0.74))
			draw_polyline(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0), at + Vector2(0, -8)]), Color(0.55, 0.4, 0.25), 1.5)
		else:
			draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), Color(0.95, 0.8, 0.2))
		_small_name(font, at, session.strings.thing_name(c, w))
	_draw_marks(w)
	if _overlay != null:
		_overlay.queue_redraw.call_deferred()
		_sync_props.call_deferred()
		return
	_draw_hover(w, self)
	_draw_ghost(w, self)


## Where each pictured person's label block goes (uid -> its bottom middle, this node's
## coordinates: the view's in the 45° view): over their head, pushed up past any block it would overlap. The selected
## person's block stays put, then whoever stands further south (in front) keeps theirs.
const LABEL_GAP := 2.0
func label_spots() -> Dictionary:
	var entries: Array = []
	for uid in people:
		var pv: PersonView = people[uid]
		if pv.pictured():
			var foot := proj * pv.position
			entries.append({"uid": uid, "size": pv.label_size(), "at": foot + pv.label_anchor(), "sel": pv.selected, "y": foot.y})
	entries.sort_custom(func(a, b):
		if a.sel != b.sel:
			return a.sel
		return a.y > b.y if a.y != b.y else int(a.uid) < int(b.uid))
	var placed: Array[Rect2] = []
	var out := {}
	for e in entries:
		var size: Vector2 = e.size
		var at: Vector2 = e.at
		var rect := Rect2(at.x - size.x * 0.5, at.y - size.y, size.x, size.y)
		for k in 12:
			var hit := -1
			for i in placed.size():
				if placed[i].grow(LABEL_GAP * 0.5).intersects(rect.grow(LABEL_GAP * 0.5)):
					hit = i
					break
			if hit < 0:
				break
			rect.position.y = placed[hit].position.y - rect.size.y - LABEL_GAP
		placed.append(rect)
		out[e.uid] = Vector2(rect.get_center().x, rect.end.y)
	return out


func _draw_labels() -> void:
	var spots := label_spots()
	for uid in spots:
		people[uid].draw_label(_labels, spots[uid])


## Hover and the arrange ghost above the standing pictures.
func _draw_overlay() -> void:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return
	_draw_hover(w, _overlay)
	_draw_ghost(w, _overlay)


## The 45° view's whitebox furniture: its footprint's diamond raised into a low block.
func _iso_block(rect: Rect2, c: Color, faded: float) -> void:
	var d := IsoMath.diamond(rect)
	var up := Vector2(0, -18)
	var line := Color(HouseGround.LINE, faded)
	draw_colored_polygon(PackedVector2Array([d[3], d[2], d[2] + up, d[3] + up]), c.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([d[2], d[1], d[1] + up, d[2] + up]), c.darkened(0.4))
	var top := PackedVector2Array([d[0] + up, d[1] + up, d[2] + up, d[3] + up])
	draw_colored_polygon(top, c)
	top.append(top[0])
	draw_polyline(top, line, 2.0)
	draw_polyline(PackedVector2Array([d[3] + up, d[3], d[2], d[1], d[1] + up]), line, 2.0)
	draw_line(d[2], d[2] + up, line, 2.0)


## A soft irregular patch (snow lying on the ground): a few lumpy blobs around `at`, each in
## rings that fade out towards the edge, so it has no hard outline. `seed` keeps its shape.
func _soft_patch(at: Vector2, c: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var cell := HouseLayout.CELL
	for b in 4:
		var centre := at + Vector2(rng.randf_range(-0.7, 0.7) * cell.x, rng.randf_range(-0.3, 0.3) * cell.y)
		var radius := Vector2(rng.randf_range(0.55, 0.95) * cell.x, rng.randf_range(0.3, 0.5) * cell.y)
		var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
		for ring in [[1.0, 0.16], [0.82, 0.22], [0.62, 0.3], [0.42, 0.34]]:
			var pts := PackedVector2Array()
			for i in 22:
				var a := TAU * float(i) / 22.0
				var wob := 1.0 + 0.16 * sin(2.0 * a + ph[0]) + 0.1 * sin(3.0 * a + ph[1]) + 0.06 * sin(5.0 * a + ph[2])
				pts.append(centre + Vector2(cos(a), sin(a)) * radius * float(ring[0]) * wob)
			draw_colored_polygon(pts, Color(c.lightened(0.15 * (1.0 - float(ring[0]))), float(ring[1])))


## Something to pick up: a pale disc ringed in the skin's pick-up colour, two small sparkles,
## and the picture (if any) on top.
func _draw_pickup(at: Vector2, pic: Texture2D) -> void:
	var c := skin.pickup
	var disc := HouseGround._ellipse(Rect2(at - Vector2(20, 10), Vector2(40, 20)), 24)
	draw_colored_polygon(disc, c.lerp(Color.WHITE, 0.82))
	disc.append(disc[0])
	draw_polyline(disc, c, 2.5)
	for sp in [Vector2(22, -14), Vector2(-24, -6)]:
		var p: Vector2 = at + sp
		draw_line(p - Vector2(4, 0), p + Vector2(4, 0), c, 2.0)
		draw_line(p - Vector2(0, 4), p + Vector2(0, 4), c, 2.0)
	if pic != null:
		draw_texture_rect(pic, PackSkin.fit_rect(pic, at + Vector2(0, 4), Vector2(30, 30)), false)


## Cooked food on the table it was served to: bowls side by side on the top face, each in
## the dish's `color`, with one dot under it per portion left (whitebox until the art).
func _draw_dishes(w: World) -> void:
	var on_object := {}  # object uid -> how many dishes already drawn on it
	for d in w.dishes:
		var o := w.object(int(d.object_uid))
		if o.is_empty() or object_picture(o) != null:
			continue  # a table with a picture draws its own dishes (PropPiece)
		var n := int(on_object.get(int(d.object_uid), 0))
		on_object[int(d.object_uid)] = n + 1
		_dish(self, w, o, d, n)


## The dishes served on object `uid`, drawn by `ci` (in house coordinates).
func draw_dishes_on(ci: CanvasItem, uid: int) -> void:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return
	var o := w.object(uid)
	if o.is_empty():
		return
	var on: Array = w.dishes.filter(func(d): return int(d.object_uid) == uid)
	# Side by side across the middle of the picture's top, about a third of the way down.
	var pic: Rect2 = props[uid].rect if props.has(uid) else layout.object_rect(o, w.pack)
	for n in on.size():
		var at := Vector2(pic.get_center().x + (n - (on.size() - 1) * 0.5) * 32.0, pic.position.y + pic.size.y * 0.3)
		_dish(ci, w, o, on[n], n, at)


func _dish(ci: CanvasItem, w: World, o: Dictionary, d: Dictionary, n: int, at := Vector2(INF, INF)) -> void:
	var rect := layout.object_rect(o, w.pack)
	if at.x == INF and iso:
		at = proj * rect.get_center() + Vector2(-20.0 + n * 34.0, -14.0)
	elif at.x == INF:
		at = Vector2(rect.position.x + 22.0 + n * 38.0, rect.position.y + 18.0)
	var dt: Dictionary = w.pack.dishes.get(str(d.type), {})
	ci.draw_colored_polygon(HouseGround._ellipse(Rect2(at - Vector2(14, 8), Vector2(28, 16))), Color(0.97, 0.96, 0.93))
	ci.draw_colored_polygon(HouseGround._ellipse(Rect2(at - Vector2(10, 5), Vector2(20, 10))), pack_color(dt, DISH_COLOR))
	ci.draw_arc(at, 14.0, 0.0, TAU, 20, Color(0.35, 0.3, 0.25), 1.5)
	for k in int(d.portions):
		ci.draw_circle(at + Vector2(-8 + k * 8, 13), 2.5, Color(0.35, 0.3, 0.25))


const MESS_COLOR := Color(0.45, 0.3, 0.18)
const DISH_COLOR := Color(0.9, 0.85, 0.7)


## The `color` of a pack entry ("#rrggbb"), or `fallback` when it has none.
static func pack_color(entry: Dictionary, fallback: Color) -> Color:
	var c = entry.get("color")
	return Color.html(c) if c is String and Color.html_is_valid(c) else fallback


## Story marks: "figure" a faint small figure (placeholder for the art pass), anything else
## (a spot to dig) a cross on the ground in a ring.
func _draw_marks(w: World) -> void:
	for m in StorySystem.marks(w):
		var at := proj * layout.cell_center(str(m.room), int(m.x), int(m.y))
		if str(m.look) == "figure":
			var c := Color(0.15, 0.15, 0.22, 0.35)
			draw_circle(at + Vector2(0, -20), 6.0, c)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-7, -13), at + Vector2(7, -13), at + Vector2(9, 8), at + Vector2(-9, 8)]), c)
		else:
			var c2 := Color(0.55, 0.25, 0.12)
			draw_arc(at, 15.0, 0.0, TAU, 24, c2, 2.0)
			draw_line(at + Vector2(-8, -8), at + Vector2(8, 8), c2, 3.0)
			draw_line(at + Vector2(-8, 8), at + Vector2(8, -8), c2, 3.0)


## The pack's name for a mess or collectible type; "" when the type is unknown.
static func thing_name(table: Dictionary, type: String) -> String:
	var e = table.get(type, {})
	return str(e.get("name", "")) if e is Dictionary else ""


## A small label under a marker centred at `at`: dark text on a cream plate, so it reads
## on a textured ground.
func _small_name(font: Font, at: Vector2, text: String) -> void:
	if text == "":
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(HouseGround.CREAM, 0.9)
	plate.border_color = Color(HouseGround.LINE, 0.45)
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(6)
	draw_style_box(plate, Rect2(at + Vector2(-w * 0.5, 9), Vector2(w, 16)))
	draw_string(font, at + Vector2(-w * 0.5, 21), text, HORIZONTAL_ALIGNMENT_CENTER, w, 11, HouseGround.LINE)


## The piece in hand under the pointer: green where it can go, red where it cannot.
func _draw_ghost(w: World, ci: CanvasItem) -> void:
	if not _arrange_on():
		return
	var g := arrange.ghost()
	if g.is_empty():
		return
	var rect := Rect2(layout.cell_to_pos(str(g.room), int(g.x), int(g.y)), Vector2(int(g.w), int(g.h)) * HouseLayout.CELL)
	var color := Color(0.3, 0.85, 0.35) if g.ok else Color(0.9, 0.25, 0.25)
	if iso:
		var d := IsoMath.diamond(rect.grow(-2))
		ci.draw_colored_polygon(d, Color(color, 0.45))
		d.append(d[0])
		ci.draw_polyline(d, color, 2.0)
		return
	ci.draw_rect(rect.grow(-2), Color(color, 0.45))
	ci.draw_rect(rect.grow(-2), color, false, 2.0)


func _draw_hover(w: World, ci: CanvasItem) -> void:
	var rect := Rect2()
	var upright := Rect2()  # people and animals: a box round the body as drawn
	match str(hover.get("kind", "")):
		"person":
			if people.has(int(hover.uid)):
				var pv: PersonView = people[int(hover.uid)]
				var body := pv.body_size()
				upright = Rect2(proj * pv.position - Vector2(body.x * 0.5, body.y), body)
		"pet":
			if pets.has(int(hover.uid)):
				var pr := (pets[int(hover.uid)] as PetView).rect()
				upright = Rect2(proj * pets[int(hover.uid)].position + (pr.position - pets[int(hover.uid)].position), pr.size)
		"object":
			var o := w.object(int(hover.uid))
			if not o.is_empty():
				rect = layout.object_rect(o, w.pack)
		"mark":
			for m in StorySystem.marks(w):
				if str(m.story) == str(hover.get("story", "")):
					rect = Rect2(layout.cell_center(str(m.room), int(m.x), int(m.y)) - HouseLayout.CELL * 0.5, HouseLayout.CELL)
		"mess", "collectible":
			var list: Array = w.messes if hover.kind == "mess" else w.collectibles
			for m in list:
				if int(m.uid) == int(hover.uid):
					rect = Rect2(layout.cell_center(str(m.room), int(m.x), int(m.y)) - HouseLayout.CELL * 0.5, HouseLayout.CELL)
	if upright.size != Vector2.ZERO:
		ci.draw_rect(upright.grow(2), Color(1.0, 0.85, 0.2), false, 3.0)
	elif rect.size != Vector2.ZERO and iso:
		var d := IsoMath.diamond(rect.grow(2))
		d.append(d[0])
		ci.draw_polyline(d, Color(1.0, 0.85, 0.2), 3.0)
	elif rect.size != Vector2.ZERO:
		ci.draw_rect(rect.grow(2), Color(1.0, 0.85, 0.2), false, 3.0)


func _dashed(rect: Rect2, color: Color) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	for seg in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		draw_dashed_line(seg[0], seg[1], color, 2.0, 8.0)
