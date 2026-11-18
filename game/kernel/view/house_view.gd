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
const MIN_SCALE := 0.44
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
var _modulate: CanvasModulate
## With a site plan: the ground under everything, and the standing walls (sorted by y with
## the people). Null / empty without one.
var ground: HouseGround
var walls: Array[WallPiece] = []
var _site_version := -1
## Moving further than this between press and release is a drag, not a click.
const CLICK_SLOP := 6.0

signal person_clicked(uid: int)

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
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	if layout.site.enabled:
		y_sort_enabled = true
		ground = HouseGround.new()
		ground.house = self
		ground.z_index = -1
		add_child(ground)
	scale = Vector2.ONE * start_scale(_view_size())
	position = _centred()
	if fit_scale(_view_size()) < 1.0:
		var entrance := _entrance_rect()
		if entrance.size != Vector2.ZERO:
			position = _area_centre() - entrance.get_center() * scale
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
	var b := layout.bounds()
	var room := Vector2(viewport_size.x, viewport_size.y - BOTTOM_BAR) - Vector2.ONE * FIT_MARGIN * 2.0
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return 1.0
	return clampf(minf(room.x / b.size.x, room.y / b.size.y), MIN_SCALE, MAX_SCALE)


## The scale the house opens at: the fitted scale for a house that fits at scale 1 or more,
## else 1 (a big house is shown life-size and panned).
func start_scale(viewport_size: Vector2) -> float:
	return clampf(maxf(fit_scale(viewport_size), 1.0), MIN_SCALE, MAX_SCALE)


## The smallest zoom the wheel reaches: the whole house in view, but never above 1.
func min_zoom(viewport_size: Vector2) -> float:
	return minf(fit_scale(viewport_size), 1.0)


## The middle of the area above the bottom bar (screen).
func _area_centre() -> Vector2:
	var v := _view_size()
	return Vector2(v.x, v.y - BOTTOM_BAR) * 0.5


## Where this node sits so the house is centred above the bottom bar at the current scale.
func _centred() -> Vector2:
	return _area_centre() - layout.bounds().get_center() * scale


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
	var under := world_pos(screen)
	scale = Vector2.ONE * s
	position = screen - under * s
	pan(Vector2.ZERO)


func _refit() -> void:
	zoom_to(start_scale(_view_size()))


## A point in the house's coordinates -> the screen.
func to_screen(house: Vector2) -> Vector2:
	return transform * house


## A point on the screen -> the house's coordinates.
func world_pos(screen: Vector2) -> Vector2:
	return transform.affine_inverse() * screen


## Moves the house by `by` (screen pixels), clamped so that every point of the house can be
## brought to the middle of the house area and no further; on an axis where the scaled house
## is smaller than the area it stays centred.
func pan(by: Vector2) -> void:
	var b := layout.bounds()
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
		for p in w.people:
			if p.alive:
				alive[p.uid] = p
	for uid in people.keys():
		if not alive.has(uid):
			if uid == follow_uid:
				follow_uid = -1
			people[uid].queue_free()
			remove_child(people[uid])
			people.erase(uid)
	for uid in alive:
		if not people.has(uid):
			var pv := PersonView.new()
			add_child(pv)
			pv.setup(alive[uid], session)
			people[uid] = pv
	var taken: Array = []
	for uid in people:
		var pv: PersonView = people[uid]
		pv.refresh()
		var t := pv.base_target
		var n := 0
		while taken.any(func(o: Vector2): return o.distance_to(t) < 1.0):
			n += 1
			t = pv.base_target + Vector2(SPREAD * n, 0)
		taken.append(t)
		pv.target = t
	if w != null and w.phase != "invalid":
		_modulate.color = Color.WHITE.lerp(NIGHT_COLOR, night_amount(w.local_hour()))
		_update_site(w)
	queue_redraw()


## Rebuilds the walls and redraws the ground when the rooms built changed.
func _update_site(w: World) -> void:
	if ground == null:
		return
	layout.site.update(w.built_set())
	if layout.site.version == _site_version:
		return
	_site_version = layout.site.version
	for p in walls:
		remove_child(p)
		p.queue_free()
	walls = WallPiece.build_all(layout.site)
	for p in walls:
		add_child(p)
	ground.queue_redraw()


## Walls go see-through while someone stands behind them.
func _fade_walls() -> void:
	if walls.is_empty():
		return
	var feet: Array = []
	for uid in people:
		feet.append(people[uid].position)
	for p in walls:
		p.fade_for(feet)


func tick(delta: float) -> void:
	_edge_scroll(delta)
	for uid in people:
		people[uid].tick(delta)
	_fade_walls()
	_follow_step(delta)


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
		if pv.hit(wpos) and pv.position.y >= best_y:
			best = uid
			best_y = pv.position.y
	return best


func set_hover(h: Dictionary) -> void:
	hover = h
	queue_redraw()


func _arrange_on() -> bool:
	return arrange != null and arrange.active


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
	_pressed = false
	_press_uid = -1
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
		var t: Dictionary = w.pack.object_types.get(str(o.type), {})
		var rect := layout.object_rect(o, w.pack)
		var hue := float(hash(str(t.get("category", ""))) % 360) / 360.0
		var faded := 0.35 if int(o.uid) == lifted else 1.0
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
	for m in w.messes:
		var at := layout.cell_center(str(m.room), int(m.x), int(m.y))
		var mt: Dictionary = w.pack.mess_types.get(str(m.type), {})
		if str(mt.get("look", "")) == "patch":
			# Lying over the ground (snow): a wide soft patch, a smaller one on top.
			var c := pack_color(mt, MESS_COLOR)
			draw_colored_polygon(HouseGround._ellipse(Rect2(at - HouseLayout.CELL * Vector2(1.1, 0.55), HouseLayout.CELL * Vector2(2.2, 1.1))), Color(c, 0.85))
			draw_colored_polygon(HouseGround._ellipse(Rect2(at - HouseLayout.CELL * Vector2(0.6, 0.35), HouseLayout.CELL * Vector2(1.3, 0.6))), c.lightened(0.3))
		else:
			draw_rect(Rect2(at - Vector2(8, 6), Vector2(16, 12)), pack_color(mt, MESS_COLOR))
		_small_name(font, at, thing_name(w.pack.mess_types, str(m.type)))
	for c in w.collectibles:
		var at := layout.cell_center(str(c.room), int(c.x), int(c.y))
		if c.has("story"):
			# An old thing of the house: a pale scrap, turned on its corner.
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)]), Color(0.93, 0.88, 0.74))
			draw_polyline(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0), at + Vector2(0, -8)]), Color(0.55, 0.4, 0.25), 1.5)
		else:
			draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), Color(0.95, 0.8, 0.2))
		_small_name(font, at, session.strings.thing_name(c, w))
	_draw_marks(w)
	_draw_hover(w)
	_draw_ghost(w)


## Cooked food on the table it was served to: bowls side by side on the top face, each in
## the dish's `color`, with one dot under it per portion left (whitebox until the art).
func _draw_dishes(w: World) -> void:
	var on_object := {}  # object uid -> how many dishes already drawn on it
	for d in w.dishes:
		var o := w.object(int(d.object_uid))
		if o.is_empty():
			continue
		var n := int(on_object.get(int(d.object_uid), 0))
		on_object[int(d.object_uid)] = n + 1
		var rect := layout.object_rect(o, w.pack)
		var at := Vector2(rect.position.x + 22.0 + n * 38.0, rect.position.y + 18.0)
		var dt: Dictionary = w.pack.dishes.get(str(d.type), {})
		draw_colored_polygon(HouseGround._ellipse(Rect2(at - Vector2(14, 8), Vector2(28, 16))), Color(0.97, 0.96, 0.93))
		draw_colored_polygon(HouseGround._ellipse(Rect2(at - Vector2(10, 5), Vector2(20, 10))), pack_color(dt, DISH_COLOR))
		draw_arc(at, 14.0, 0.0, TAU, 20, Color(0.35, 0.3, 0.25), 1.5)
		for k in int(d.portions):
			draw_circle(at + Vector2(-8 + k * 8, 13), 2.5, Color(0.35, 0.3, 0.25))


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
		var at := layout.cell_center(str(m.room), int(m.x), int(m.y))
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


## A small dark label under a marker centred at `at`.
func _small_name(font: Font, at: Vector2, text: String) -> void:
	if text == "":
		return
	var width := HouseLayout.CELL.x * 2.0
	draw_string(font, at + Vector2(-width * 0.5, 18), text, HORIZONTAL_ALIGNMENT_CENTER, width, 10, Color(0.15, 0.12, 0.1))


## The piece in hand under the pointer: green where it can go, red where it cannot.
func _draw_ghost(w: World) -> void:
	if not _arrange_on():
		return
	var g := arrange.ghost()
	if g.is_empty():
		return
	var rect := Rect2(layout.cell_to_pos(str(g.room), int(g.x), int(g.y)), Vector2(int(g.w), int(g.h)) * HouseLayout.CELL)
	var color := Color(0.3, 0.85, 0.35) if g.ok else Color(0.9, 0.25, 0.25)
	draw_rect(rect.grow(-2), Color(color, 0.45))
	draw_rect(rect.grow(-2), color, false, 2.0)


func _draw_hover(w: World) -> void:
	var rect := Rect2()
	match str(hover.get("kind", "")):
		"person":
			if people.has(int(hover.uid)):
				var pv: PersonView = people[int(hover.uid)]
				rect = Rect2(pv.position - Vector2(PersonView.BODY.x * 0.5, PersonView.BODY.y), PersonView.BODY)
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
	if rect.size != Vector2.ZERO:
		draw_rect(rect.grow(2), Color(1.0, 0.85, 0.2), false, 3.0)


func _dashed(rect: Rect2, color: Color) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	for seg in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		draw_dashed_line(seg[0], seg[1], color, 2.0, 8.0)
