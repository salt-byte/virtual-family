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
## What a notice points at (`show_guide`): object and animal uids marked with a pulsing
## outline and a small arrow above, for `guide_left` more seconds.
var guide_objects: Array = []
## The person under the pointer while nothing is carried (-1: none): their bubble's hint
## shows under them (`hover_hint`).
var pointed_person := -1
var guide_pets: Array = []
var guide_left := 0.0
var _guide_t := 0.0
const GUIDE_SECONDS := 8.0
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
	var movers: Array = []
	for c in stage.get_children():
		if c == ground or not c is Node2D:
			continue
		if c is PersonView or c is PetView:
			movers.append(c)
		else:
			kids.append(c)
	var keyed: Array = []
	for i in kids.size():
		keyed.append([sort_depth(kids[i]), i, kids[i]])
	keyed.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var order: Array = []
	for k in keyed:
		order.append(k[2])
	_order_furniture(order)
	var deps: Array = []
	var boxes: Array = []
	for o in order:
		deps.append(sort_depth(o))
		boxes.append(stage_box(o))
	# People and animals go in one by one, front-most last, each between whatever it must be
	# drawn over and whatever must be drawn over it (`_slot`).
	var mk: Array = []
	for i in movers.size():
		mk.append([sort_depth(movers[i]), i, movers[i]])
	mk.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	for k in mk:
		var at := _slot(order, deps, boxes, k[2], k[0])
		order.insert(at, k[2])
		deps.insert(at, k[0])
		boxes.insert(at, mover_box(k[2]))
	var base := 1 if ground != null and ground.get_parent() == stage else 0
	for i in order.size():
		var n: Node = order[i]
		if n.get_index() != base + i:
			stage.move_child(n, base + i)


## Local avoidance: someone walking who would walk into another goes round them or waits a
## moment. Each frame they look LOOK_AHEAD seconds on: if they would then be closer than
## KEEP_APART to someone (where that one will be, walking on) and closing in, that one is in
## the way. Someone standing in the way is walked round (a way that keeps off their cell); of
## two walking into each other the later born gives way (goes round, else waits); behind
## someone going the same way one waits a step back. An animal gives way to everyone (animals
## pay one another no mind) and nobody to a walking animal. A wait lasts at most WAIT_MAX,
## then they go on regardless (a narrow door they both need). Returns true to stand still
## this frame. `n` is a PersonView or PetView; it keeps `waited` and `walked_round` for this.
const KEEP_APART := 38.0
const PET_EXTRA := 10.0
const LOOK_AHEAD := 0.3
const WAIT_MAX := 1.5
## A way round may be at most this much longer than the way it replaces (plan pixels), and
## a walker goes round someone at most once per DETOUR_GAP seconds (no dancing in a crowd).
const DETOUR_MAX := 120.0
const DETOUR_GAP := 0.6
## Waiting this long (seconds) to let someone by, one counts as standing (others go round).
const STOOD := 0.25
func give_way(n: Node2D, delta: float) -> bool:
	if not layout.site.enabled or n.position.distance_to(n.target) <= PersonView.ARRIVED:
		n.waited = 0.0
		return false
	var dir := _heading(n)
	if dir == Vector2.ZERO:
		return false
	var pet := n is PetView
	var rank := _rank(n)
	n.round_age += delta
	var mv: Vector2 = dir * float(n.SPEED)
	var blocker: Node2D = null
	var follow := false
	for o in people.values() + pets.values():
		if o == n or not o.visible or (o is PersonView and o.held) or (pet and o is PetView):
			continue
		# An animal's picture is wider than a person's: keep a little further from one.
		var keep := KEEP_APART + (PET_EXTRA if pet or o is PetView else 0.0)
		var now: float = n.position.distance_to(o.position)
		if now > keep + float(n.SPEED) * LOOK_AHEAD * 2.0:
			continue
		# Arrived: standing at their spot. Otherwise on the way (walking, or waiting a moment).
		# Someone who has stood a moment to let others by counts as standing too.
		var arrived: bool = o.position.distance_to(o.target) <= PersonView.ARRIVED or float(o.waited) >= STOOD \
			or (o is PetView and float(o.waited) > 0.0)
		if arrived and o.position.distance_to(n.target) < keep:
			continue  # standing where this one is going: the house spreads them on arrival
		if not arrived and o is PetView and not pet:
			continue
		var od := _heading(o) if not arrived and float(o.waited) <= 0.0 else Vector2.ZERO
		# The closest the two come within LOOK_AHEAD, each walking on as now.
		var rel: Vector2 = o.position - n.position
		var rv: Vector2 = od * float(o.SPEED) - mv
		var tc := 0.0 if rv.length_squared() < 0.0001 else clampf(-rel.dot(rv) / rv.length_squared(), 0.0, LOOK_AHEAD)
		var then := (rel + rv * tc).length()
		# In the way: coming closer than KEEP_APART, or already that close and ahead.
		var closing := then < keep and then < now - 0.5
		var ahead := now < keep and rel.dot(dir) > 0.3 * now
		if not (closing or ahead):
			continue
		var behind := od.dot(dir) > 0.5 and rel.dot(dir) > 0.0
		if not arrived and not behind and not pet and _rank(o) < rank:
			continue  # the other gives way (but whoever walks behind another keeps back)
		follow = behind
		blocker = o
		break
	if blocker == null:
		n.waited = 0.0
		return false
	if n.waited > WAIT_MAX:
		return false
	if follow:
		n.waited += delta
		return true
	var cell := layout.site.cell_of(blocker.position)
	var arrived_b: bool = blocker.position.distance_to(blocker.target) <= PersonView.ARRIVED or float(blocker.waited) >= STOOD
	if cell == n.walked_round and arrived_b:
		return false  # already going round them
	if not arrived_b:
		# Giving way to someone walking: a step that takes this one off their way goes on.
		var a0: Vector2 = blocker.position
		var a1: Vector2 = a0 + _heading(blocker) * HouseSite.CELL.x * 3.0
		var d0 := Geometry2D.get_closest_point_to_segment(n.position, a0, a1).distance_to(n.position)
		var p1: Vector2 = n.position + dir * 4.0
		var d1 := Geometry2D.get_closest_point_to_segment(p1, a0, a1).distance_to(p1)
		if d1 > d0 + 1.0:
			return false
	if cell != n.walked_round and n.round_age >= DETOUR_GAP:
		var avoid := {cell: true}
		avoid[layout.site.cell_of(blocker.position + _heading(blocker) * HouseSite.CELL.y)] = true
		var r := layout.site.detour(n.position, n.target, avoid)
		var longer := _length(n.position, r[1], n.target) - _length(n.position, n.path, n.target)
		if r[0] and longer < DETOUR_MAX and _clears(n.position, r[1], n.target, blocker.position):
			_set_way(n, r[1], cell)
			return false
	if not arrived_b and n.round_age >= DETOUR_GAP * 0.5:
		# No way round (a narrow passage), and they keep coming: the one giving way steps
		# aside into a free cell beside, off the other's way, and goes on from there.
		var aside := _aside(n, blocker)
		if aside.x != INF:
			var way := PackedVector2Array([aside])
			way.append_array(layout.site.route(aside, n.target))
			_set_way(n, way, cell)
			return false
	n.waited += delta
	return true


static func _set_way(n: Node2D, way: PackedVector2Array, round_cell: Vector2i) -> void:
	n.path = way
	n._path_goal = n.target
	n._path_from = n.position
	n.walked_round = round_cell
	n.round_age = 0.0


## A free cell's middle next to `n` that is at least KEEP_APART off the line `o` walks (or off
## `o`, standing), the furthest such; else the cell behind `n`, away from `o` (backing off out
## of a doorway); Vector2(INF, INF) when there is none.
func _aside(n: Node2D, o: Node2D) -> Vector2:
	var site := layout.site
	var c := site.cell_of(n.position)
	var a: Vector2 = o.position
	var b: Vector2 = a + _heading(o) * HouseSite.CELL.x * 3.0
	var best := Vector2(INF, INF)
	var best_d := KEEP_APART
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var q: Vector2i = c + d
		if not site.walkable(q) or not site.step_open(c, q):
			continue
		var p := site.centre(q)
		if not site.can_stop(p) or not site.clear_line(n.position, p):
			continue
		var dist := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if dist >= best_d:
			best_d = dist
			best = p
	if best.x != INF:
		return best
	# Nowhere beside (a doorway): back off a cell, away from them.
	var far := n.position.distance_to(a) + HouseSite.CELL.y * 0.5
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = c + d
		var p := site.centre(q)
		if site.walkable(q) and site.step_open(c, q) and site.can_stop(p) and site.clear_line(n.position, p) and p.distance_to(a) > far:
			far = p.distance_to(a)
			best = p
	return best


## Whether the way from `from` through `pts` to `to` keeps KEEP_APART * 0.8 from `p` over its
## first two legs (a way round that does not really go round is no way round).
static func _clears(from: Vector2, pts: PackedVector2Array, to: Vector2, p: Vector2) -> bool:
	var at := from
	for i in mini(pts.size() + 1, 2):
		var nxt := pts[i] if i < pts.size() else to
		if Geometry2D.get_closest_point_to_segment(p, at, nxt).distance_to(p) < KEEP_APART * 0.8:
			return false
		at = nxt
	return true


## The length of the way from `from` through `pts` to `to`.
static func _length(from: Vector2, pts: PackedVector2Array, to: Vector2) -> float:
	var at := from
	var total := 0.0
	for p in pts:
		total += at.distance_to(p)
		at = p
	return total + at.distance_to(to)


## Which way `n` walks now (a unit vector; zero standing).
static func _heading(n: Node2D) -> Vector2:
	var next: Vector2 = n.path[0] if not n.path.is_empty() else n.target
	var d: Vector2 = next - n.position
	return d.normalized() if d.length() > 0.5 else Vector2.ZERO


## Who gives way to whom: the earlier born (lower uid) goes first.
static func _rank(n: Node2D) -> int:
	if n is PersonView:
		return -int((n as PersonView).person.uid)
	if n is PetView:
		return -100000 - int((n as PetView).pet.uid)
	return 0


## How near (screen pixels) two pieces' pictures come for `_order_furniture` to order them.
const ORDER_REACH := 64.0


## Pieces of furniture whose pictures overlap are put in footprint order: one standing wholly
## in front of another (east of its east edge or south of its south edge) is drawn after it,
## whatever their middles and seat lifts say. Moves a piece just past the one it must cover;
## a few passes settle it.
func _order_furniture(order: Array) -> void:
	var w := session.world if session != null else null
	if w == null:
		return
	var pieces: Array = []
	for o in order:
		if o is PropPiece and (o as PropPiece).object_uid >= 0:
			var obj := w.object((o as PropPiece).object_uid)
			if not obj.is_empty():
				pieces.append([o, layout.object_rect(obj, w.pack), stage_box(o)])
	for pass_i in 4:
		var moved := false
		for a in pieces:
			for b in pieces:
				# Pieces close enough that one body can overlap both are put in order too
				# (someone standing between them is drawn after the one and before the other).
				if a == b or not (a[2] as Rect2).grow(ORDER_REACH).intersects(b[2]):
					continue
				# a in front of b, but drawn first: move a just past b.
				if _rect_side(a[1], b[1]) == 1:
					var ia := order.find(a[0])
					var ib := order.find(b[0])
					if ia < ib:
						order.remove_at(ia)
						order.insert(ib, a[0])
						moved = true
		if not moved:
			break


## Whether footprint `a` stands in front of `b` (1), behind it (-1) or neither surely (0:
## they overlap). Off a corner (north-east or south-west of it), both: as for someone standing
## there (`foot_side`), the side it stands further off wins, so a mover between the two
## (south of one, north of the other) can be drawn between them.
static func _rect_side(a: Rect2, b: Rect2) -> int:
	var front := a.position.x >= b.end.x or a.position.y >= b.end.y
	var behind := a.end.x <= b.position.x or a.end.y <= b.position.y
	if front and not behind:
		return 1
	if behind and not front:
		return -1
	if front and behind:
		var ahead := maxf(a.position.x - b.end.x, a.position.y - b.end.y)
		var back := maxf(b.position.x - a.end.x, b.position.y - a.end.y)
		if ahead != back:
			return 1 if ahead > back else -1
	return 0


## Where a person or animal `n` (sort depth `d`) goes into `order` (back to front). Only what
## overlaps its body on the screen matters: a piece of furniture it stands in front of (east
## of the footprint's east edge or south of its south edge) is drawn before it, one it stands
## behind after it, whatever the pieces' middles say (a long piece's middle can be nearer the
## camera than someone at its front end); the seat or bed it sits or lies on is under it; a
## back wall likewise by its side; everything else by depth. When these disagree, the sides
## of footprints and walls win over depth; when even those disagree, its own depth wins.
func _slot(order: Array, deps: Array, boxes: Array, n: Node2D, d: float) -> int:
	var natural := deps.bsearch(d, false)
	var body := mover_box(n)
	var lo := -1
	var hi := order.size()
	# Sides from footprints and back walls are sure; the rest (by depth) give way to them.
	var lo_sure := -1
	var hi_sure := order.size()
	var w := session.world if session != null else null
	var seat := -1
	if n is PersonView:
		seat = (n as PersonView).seat_uid()
	elif n is PetView and (n as PetView).pet != null:
		seat = int((n as PetView).pet.current.get("object_uid", -1))
	# Whatever the seat or bed itself is drawn over, so is whoever sits or lies on it (a body
	# lying along a bed reaches over towards the wall the bed stands against).
	var seat_i := -1
	if seat >= 0:
		for i in order.size():
			if order[i] is PropPiece and (order[i] as PropPiece).object_uid == seat:
				seat_i = i
				break
	for i in order.size():
		var box: Rect2 = boxes[i]
		if box.size == Vector2.ZERO or not box.intersects(body):
			continue
		var o: Node2D = order[i]
		var side := 0
		if o is PropPiece and (o as PropPiece).object_uid >= 0 and w != null:
			var obj := w.object((o as PropPiece).object_uid)
			if not obj.is_empty():
				var fr := layout.object_rect(obj, w.pack)
				var on := (o as PropPiece).object_uid == seat or (skin != null and skin.step_over(str(obj.type)))
				side = 1 if on and fr.grow(2.0).has_point(n.position) else foot_side(n.position, fr, 2.0)
		elif o is IsoWall and (o as IsoWall).role == "wall" and (o as IsoWall).tall:
			side = foot_side(n.position, (o as IsoWall).plan_rect(), 2.0)
		if side == -1 and i < seat_i:
			continue
		if side == 1:
			lo_sure = maxi(lo_sure, i)
		elif side == -1:
			hi_sure = mini(hi_sure, i)
		else:
			side = 1 if float(deps[i]) <= d else -1
		if side == 1:
			lo = maxi(lo, i)
		else:
			hi = mini(hi, i)
	if lo < hi:
		return clampi(natural, lo + 1, hi)
	if lo_sure < hi_sure:
		return clampi(natural, lo_sure + 1, hi_sure)
	return natural


## Whether someone standing at plan point `p` is in front of footprint `r` (1: east of its
## east edge or south of its south edge), behind it (-1: west or north) or neither surely (0:
## over it). Off a corner, both: the side it stands further off wins.
static func foot_side(p: Vector2, r: Rect2, reach := 8.0) -> int:
	var front := p.x - reach >= r.end.x or p.y - reach >= r.end.y
	var behind := p.x + reach <= r.position.x or p.y + reach <= r.position.y
	if front and not behind:
		return 1
	if behind and not front:
		return -1
	if front and behind:
		# Off a corner (south-west or north-east of it): the side it stands further off wins.
		var ahead := maxf(p.x - r.end.x, p.y - r.end.y)
		var back := maxf(r.position.x - p.x, r.position.y - p.y)
		return 1 if ahead > back else -1
	return 0


## The object types people step over (`PackSkin.step_over`), as a set.
func step_over_types(w: World) -> Dictionary:
	var out := {}
	if skin != null and skin.enabled:
		for t in w.pack.object_types:
			if skin.step_over(str(t)):
				out[str(t)] = true
	return out


## A person's or animal's body on the view (this node's unscaled coordinates).
func mover_box(n: Node2D) -> Rect2:
	var foot := proj * n.position
	if n is PersonView:
		var pv := n as PersonView
		if pv.body_pose() == "sleep":
			if iso and pv.pictured():
				return Rect2(foot + pv.lie_rect().position, pv.lie_rect().size)
			var len := pv.body_size().y
			return Rect2(foot + pv.lie_point() - Vector2(len * 0.5, 16), Vector2(len, 32))
		var b := pv.body_size()
		var h := pv.drawn_height() + pv.seat_lift()
		return Rect2(foot + Vector2(-b.x * 0.5, -h), Vector2(b.x, h + 4.0))
	if n is PetView:
		var pb := (n as PetView).body()
		return Rect2(foot + Vector2(-pb.x * 0.5, -pb.y), Vector2(pb.x, pb.y + 4.0))
	return Rect2()


## What a standing node covers on the view: a picture's rect, a wall's box, a body.
func stage_box(n: Node2D) -> Rect2:
	if n is PropPiece:
		var p := n as PropPiece
		return Rect2(proj * p.position + p.rect.position, p.rect.size)
	if n is IsoWall:
		return (n as IsoWall).cover_box()
	if n is PersonView or n is PetView:
		return mover_box(n)
	return Rect2()


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
	_sync_visitor(w)
	_sync_props()
	queue_redraw()


## The visitor of a doctor service (`ServiceSystem` "doctor") while one comes, works or
## leaves; null otherwise.
var visitor: VisitorView = null
var _visitor_service := ""
## Seconds before the kernel's arrival that the visitor turns up at the gate and starts
## walking in (about the walk across the yard).
const VISITOR_LEAD := 15


## Brings the visitor in at the gate as the visit draws near, keeps it beside the patient
## while the visit lasts, and sends it back out to the gate once the visit is over.
func _sync_visitor(w: World) -> void:
	if w == null or w.phase == "invalid":
		return
	var d := w.doctor
	if not d.is_empty():
		var sid := str(d.get("service", ""))
		var examining := str(d.get("phase", "")) == "examining"
		if visitor == null and (examining or int(d.get("at", 0)) - w.now <= VISITOR_LEAD):
			visitor = VisitorView.new()
			visitor.house = self
			_place(visitor)
			_visitor_service = sid
			visitor.goal = _gate_pos(w, sid)
			visitor.setup(VisitorView.stand_in(w, sid), session)
			visitor.position = visitor.goal
		if visitor != null:
			visitor.leaving = false
			visitor.goal = _bedside(w, int(d.get("person", -1)))
			visitor.busy_text = session.strings.t("visitor.examining" if examining else "visitor.coming")
			visitor.refresh()
	elif visitor != null:
		if not visitor.leaving:
			visitor.leaving = true
			visitor.busy_text = ""
			visitor.goal = _gate_pos(w, _visitor_service)
		visitor.refresh()


## Where a doctor service's visitor comes in: the middle of its `enters_from` room, else the
## way people come into the house.
func _gate_pos(w: World, sid: String) -> Vector2:
	var room := str(w.pack.services.get(sid, {}).get("enters_from", ""))
	if room != "" and layout.room_rect(room).size != Vector2.ZERO:
		return layout.room_rect(room).get_center()
	for id in w.pack.rooms:
		if id in w.rooms_built and not bool(w.pack.rooms[id].get("outdoor", false)):
			return layout.room_rect(id).get_center()
	return Vector2.ZERO


## Beside the person `uid` (a cell over from where they are headed, as someone looking after
## them stands); the gate when they are not in the house.
func _bedside(w: World, uid: int) -> Vector2:
	if not people.has(uid):
		return _gate_pos(w, _visitor_service)
	var them: Vector2 = (people[uid] as PersonView).base_target
	if layout.site.enabled:
		return layout.stop_point(them + Vector2(HouseSite.CELL.x, 0), {layout.site.cell_of(them): true})
	return them + Vector2(PersonView.BODY.x, 0)


## The visitor says `text` over its head (the diagnosis).
func visitor_say(text: String) -> void:
	if visitor != null and text != "":
		visitor.speak(text)


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
		# An animal lying or standing about keeps its spot: people take the cells beside it.
		for pid in pets:
			var a: PetView = pets[pid]
			if a.position.distance_to(a.target) <= PersonView.ARRIVED and not layout.site.blocked.has(layout.site.cell_of(a.position)):
				cells[layout.site.cell_of(a.position)] = true
		var seated := {}  # object uid -> how many sit or lie on it already
		var beds := _bed_slots(order, w)
		for uid in order:
			var pv: PersonView = people[uid]
			var t := pv.base_target
			if pv.on_object and w != null and beds.has(uid):
				# Lying: each in their place across the bed, got onto from its edge in turn.
				var br := layout.object_rect(pv.use_object, w.pack)
				t.x = minf(br.position.x + 14.0 + float(beds[uid]) * BED_STEP, br.end.x - 14.0)
				pv.target = t
				continue
			if pv.on_object and w != null:
				# Side by side along the piece, within its width.
				var r := layout.object_rect(pv.use_object, w.pack)
				var k := int(seated.get(int(pv.use_object.uid), 0))
				seated[int(pv.use_object.uid)] = k + 1
				var steps := [0.0, -1.0, 1.0, -2.0, 2.0]
				t.x = clampf(t.x + float(steps[mini(k, 4)]) * 34.0, r.position.x + 14.0, r.end.x - 14.0)
				pv.target = t
				continue
			var clash := false
			for dx in [-HouseSite.FEET, 0.0, HouseSite.FEET]:
				clash = clash or cells.has(layout.site.cell_of(t + Vector2(dx, 0)))
			if clash:
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


## Getting onto a bed one after another: this far apart along its edge (plan pixels; more
## than ClipProbe.NEAR, so two getting in are not one in the other's room).
const BED_STEP := 36.0


## Who lies on which bed (`PackSkin.bed`, the 45° view) in which place: {person uid: slot}.
## A sleeper keeps the place they have; a newcomer takes the lowest one free. Each view is
## told its bed, place, rank among those on the bed (by place) and how many there are.
func _bed_slots(order: Array, w: World) -> Dictionary:
	var out := {}
	if w == null or skin == null or not iso:
		return out
	var by_bed := {}  # bed uid -> [person uid]
	for uid in order:
		var pv: PersonView = people[uid]
		var lies := pv.on_object and pv.action_pose == "sleep" and not pv.use_object.is_empty() \
			and not skin.bed(str(pv.use_object.get("type", ""))).is_empty()
		if not lies:
			pv.bed_uid = -1
			pv.bed_slot = -1
			continue
		var b := int(pv.use_object.uid)
		if pv.bed_uid != b:
			pv.bed_uid = b
			pv.bed_slot = -1
		if not by_bed.has(b):
			by_bed[b] = []
		by_bed[b].append(uid)
	for b in by_bed:
		var list: Array = by_bed[b]
		var taken := {}
		for uid in list:
			var pv: PersonView = people[uid]
			if pv.bed_slot >= 0 and not taken.has(pv.bed_slot):
				taken[pv.bed_slot] = true
			else:
				pv.bed_slot = -1
		for uid in list:
			var pv: PersonView = people[uid]
			if pv.bed_slot < 0:
				var k := 0
				while taken.has(k):
					k += 1
				pv.bed_slot = k
				taken[k] = true
		var slots: Array = list.map(func(u): return people[u].bed_slot)
		slots.sort()
		for uid in list:
			var pv: PersonView = people[uid]
			pv.bed_rank = slots.find(pv.bed_slot)
			pv.bed_n = list.size()
			out[uid] = pv.bed_slot
	return out


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
						ground.queue_redraw()
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
	layout.site.set_furniture(layout.furniture_cells(w, step_over_types(w)))
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
	if visitor != null:
		visitor.tick(delta)
		if visitor.leaving and visitor.arrived() and visitor.say == "":
			stage.remove_child(visitor)
			visitor.queue_free()
			visitor = null
	_fade_walls()
	_sort_stage()
	_follow_step(delta)
	if _labels != null:
		_labels.queue_redraw()
	if guide_left > 0.0:
		guide_left -= delta
		_guide_t += delta
		if guide_left <= 0.0:
			clear_guide()
		else:
			_redraw_marks()


## Marks objects `objects` and animals `pets` (uids) as where to take someone, for
## GUIDE_SECONDS; the view pans to the first object when it is off the house area.
func show_guide(objects: Array, pet_uids := []) -> void:
	guide_objects = objects.duplicate()
	guide_pets = pet_uids.duplicate()
	guide_left = GUIDE_SECONDS if not (guide_objects.is_empty() and guide_pets.is_empty()) else 0.0
	_guide_t = 0.0
	_redraw_marks()


func clear_guide() -> void:
	guide_objects = []
	guide_pets = []
	guide_left = 0.0
	_redraw_marks()


func _redraw_marks() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


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
	if _labels != null:
		_labels.queue_redraw()  # an animal shows its name while hovered


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
	elif event is InputEventMouseMotion:
		point_at(event.position)


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
	# Picked up by the sim before the person on screen got there: it lies there until they do.
	for pv in people.values():
		var item: Vector2 = (pv as PersonView).fetch_item()
		var pic: Texture2D = (pv as PersonView).held_picture()
		if item.x != INF and pic != null:
			draw_texture_rect(pic, PackSkin.fit_rect(pic, proj * item + Vector2(0, 4), Vector2(30, 30)), false)
	_draw_marks(w)
	if _overlay != null:
		_overlay.queue_redraw.call_deferred()
		_sync_props.call_deferred()
		return
	_draw_hover(w, self)
	_draw_ghost(w, self)


## Where each pictured person's label block goes, and each pictured animal's that shows one
## (uid -> its bottom middle, this node's coordinates: the view's in the 45° view): over
## their head, pushed up past any block it would overlap. The selected one's block stays
## put, then whoever stands further south (in front) keeps theirs.
const LABEL_GAP := 2.0
func label_spots() -> Dictionary:
	var entries: Array = []
	for uid in people:
		var pv: PersonView = people[uid]
		if pv.pictured() and pv.visible:
			var foot := proj * pv.position
			entries.append({"uid": uid, "size": pv.label_size(), "at": foot + pv.label_anchor(), "sel": pv.selected, "y": foot.y})
	if visitor != null and visitor.pictured():
		var vf := proj * visitor.position
		entries.append({"uid": VisitorView.UID, "size": visitor.label_size(), "at": vf + visitor.label_anchor(), "sel": false, "y": vf.y})
	for uid in pets:
		var av: PetView = pets[uid]
		if av.pictured() and av.visible and av.shows_label():
			var foot := proj * av.position
			entries.append({"uid": uid, "size": av.label_size(), "at": foot + av.label_anchor(), "sel": av.selected, "y": foot.y})
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


## The person or animal a `label_spots` uid belongs to (people and animals share one uid
## count), or null.
func label_owner(uid: int) -> Node2D:
	if uid == VisitorView.UID and visitor != null:
		return visitor
	if people.has(uid):
		return people[uid]
	return pets.get(uid)


func _draw_labels() -> void:
	var spots := label_spots()
	for uid in spots:
		label_owner(uid).draw_label(_labels, spots[uid])
	_draw_place_name()


## The 45° view writes no names on the floor: the place under the pointer (an unbuilt room,
## a place out on the map) shows its name, with the price when it is still to build, on a
## plate over its middle. Built rooms inside the compound show nothing.
var pointed_room := ""
func point_at(screen: Vector2) -> void:
	_see_cursor(screen)
	var room := ""
	if iso and session != null and session.world != null and session.world.phase != "invalid":
		var hit := layout.pos_to_cell(world_pos(screen))
		if not hit.is_empty():
			room = str(hit.room)
	if place_label(room) == "":
		room = ""
	if room != pointed_room:
		pointed_room = room
		if _labels != null:
			_labels.queue_redraw()
	var who := person_at(world_pos(screen)) if session != null and session.world != null else -1
	if who != pointed_person:
		pointed_person = who
		_redraw_marks()


## The hover words for `room`: "<name> · <price>" unbuilt, the name for a place out on the map,
## "" for a built room (or no room).
func place_label(room: String) -> String:
	var w := session.world if session != null else null
	if room == "" or w == null or not w.pack.rooms.has(room):
		return ""
	var r: Dictionary = w.pack.rooms[room]
	var name := str(r.get("name", ""))
	if not room in w.rooms_built:
		return "%s · %s" % [name, session.strings.t("money").replace("{n}", str(int(r.get("build_cost", 0))))]
	return name if bool(r.get("outside", false)) else ""


func _draw_place_name() -> void:
	var text := place_label(pointed_room)
	if text == "" or _pressed:
		return
	var font := ThemeDB.fallback_font
	var at := proj * layout.room_rect(pointed_room).get_center() + Vector2(0, -16)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 20.0
	var plate := Rect2(at.x - tw * 0.5, at.y - 26, tw, 26)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FFF4DF", 0.94)
	box.border_color = Color("#4A3424", 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(9)
	_labels.draw_style_box(box, plate)
	_labels.draw_string(font, Vector2(plate.position.x, plate.position.y + 18), text, HORIZONTAL_ALIGNMENT_CENTER, tw, 15, Color("#4A3424"))


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
	_draw_guide(w, ci)
	if hover.is_empty() and people.has(pointed_person):
		var ppv: PersonView = people[pointed_person]
		var pbody := ppv.body_size()
		_draw_hover_hint(w, ci, Rect2(proj * ppv.position - Vector2(pbody.x * 0.5, pbody.y), pbody), pointed_person)
	if upright.size != Vector2.ZERO:
		ci.draw_rect(upright.grow(2), Color(1.0, 0.85, 0.2), false, 3.0)
	elif rect.size != Vector2.ZERO and iso:
		var d := IsoMath.diamond(rect.grow(2))
		d.append(d[0])
		ci.draw_polyline(d, Color(1.0, 0.85, 0.2), 3.0)
	elif rect.size != Vector2.ZERO:
		ci.draw_rect(rect.grow(2), Color(1.0, 0.85, 0.2), false, 3.0)


## The marks of `show_guide`: a pulsing tomato outline round each object (its footprint) or
## animal, and a small arrow bobbing above it.
func _draw_guide(w: World, ci: CanvasItem) -> void:
	if guide_left <= 0.0:
		return
	var pulse := 0.55 + 0.45 * sin(_guide_t * TAU / 0.9)
	var col := Color(ViewWidgets.ACCENT, pulse)
	for uid in guide_objects:
		var o := w.object(int(uid))
		if o.is_empty():
			continue
		var rect := layout.object_rect(o, w.pack)
		var top := Vector2(rect.get_center().x, rect.position.y)
		if iso:
			var d := IsoMath.diamond(rect.grow(3))
			d.append(d[0])
			ci.draw_polyline(d, col, 4.0, true)
			top = Vector2((d[1].x + d[3].x) * 0.5, d[0].y)
			var piece: PropPiece = props.get(int(uid))
			if piece != null and piece.tex != null:
				var r := Rect2(proj * piece.position + piece.rect.position, piece.rect.size)
				top = Vector2(r.get_center().x, r.position.y)
		else:
			ci.draw_rect(rect.grow(3), col, false, 4.0)
		_guide_arrow(ci, top)
	for uid in guide_pets:
		if pets.has(int(uid)):
			var pv: PetView = pets[int(uid)]
			var pr := pv.rect()
			var r2 := Rect2(proj * pv.position + (pr.position - pv.position), pr.size)
			ci.draw_rect(r2.grow(3), col, false, 3.0)
			_guide_arrow(ci, Vector2(r2.get_center().x, r2.position.y))


## A small arrow pointing down at `tip` (just above it), bobbing.
func _guide_arrow(ci: CanvasItem, tip: Vector2) -> void:
	var y := tip.y - 6.0 - 4.0 * (0.5 + 0.5 * sin(_guide_t * TAU / 0.9))
	var pts := PackedVector2Array([Vector2(tip.x - 9, y - 14), Vector2(tip.x + 9, y - 14), Vector2(tip.x, y)])
	ci.draw_colored_polygon(pts, ViewWidgets.ACCENT)
	pts.append(pts[0])
	ci.draw_polyline(pts, ViewWidgets.INK, 2.0, true)


## Under the pointed-at person with a thought bubble: how to answer it (`NeedBubble.hint`).
func _draw_hover_hint(w: World, ci: CanvasItem, body: Rect2, uid: int) -> void:
	var text := hover_hint(uid)
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 13
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var plate := Rect2(Vector2(body.get_center().x - tw * 0.5 - 8.0, body.end.y + 6.0), Vector2(tw + 16.0, 22.0))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(NeedBubble.CREAM, 0.96)
	box.border_color = Color(ViewWidgets.ACCENT, 0.9)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	ci.draw_style_box(box, plate)
	ci.draw_string(font, Vector2(plate.position.x + 8.0, plate.position.y + 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ViewWidgets.INK)


## The words shown under person `uid` while hovered ("" for none).
func hover_hint(uid: int) -> String:
	var w := session.world if session != null else null
	if w == null:
		return ""
	var p := w.person(uid)
	return NeedBubble.hint(w, session.strings, p) if p != null else ""


func _dashed(rect: Rect2, color: Color) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	for seg in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		draw_dashed_line(seg[0], seg[1], color, 2.0, 8.0)
