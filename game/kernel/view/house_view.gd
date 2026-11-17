class_name HouseView
extends Node2D
## Draws the house (rooms, furniture, messes, collectibles) and keeps one PersonView per
## living person. Panning moves this node. Reads the World, never writes it.

const VIEW_SIZE := Vector2(1280, 720)
const BOTTOM_BAR := 96.0
const KEEP_VISIBLE := 120.0
const SPREAD := 20.0
const NIGHT_COLOR := Color(0.45, 0.5, 0.7)

var session: GameSession
var layout: HouseLayout
var people: Dictionary = {}  # uid -> PersonView
var _modulate: CanvasModulate
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
	var b := layout.bounds()
	var area := Vector2(VIEW_SIZE.x, VIEW_SIZE.y - BOTTOM_BAR)
	position = area * 0.5 - b.get_center()
	pan(Vector2.ZERO)


func world_pos(screen: Vector2) -> Vector2:
	return screen - position


func pan(by: Vector2) -> void:
	var b := layout.bounds()
	var lo := Vector2(KEEP_VISIBLE - b.end.x, KEEP_VISIBLE - b.end.y)
	var hi := Vector2(VIEW_SIZE.x - KEEP_VISIBLE - b.position.x, VIEW_SIZE.y - KEEP_VISIBLE - b.position.y)
	position = (position + by).clamp(lo, hi)


func refresh() -> void:
	var w := session.world
	var alive := {}
	if w != null and w.phase != "invalid":
		for p in w.people:
			if p.alive:
				alive[p.uid] = p
	for uid in people.keys():
		if not alive.has(uid):
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
	queue_redraw()


func tick(delta: float) -> void:
	for uid in people:
		people[uid].tick(delta)


## The uid of the person under a point in the house's coordinates (the one drawn on top
## wins), or -1.
func person_at(wpos: Vector2) -> int:
	var best := -1
	var best_y := -INF
	for uid in people:
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
	if _arrange_on():
		# A press that did not pick a piece up pans once it moves past the slop, also with a
		# piece in hand; the ghost keeps following the pointer.
		if _pressed:
			_last = screen
			if not _moved:
				if screen.distance_to(_press_at) > CLICK_SLOP:
					_moved = true
					if not _arranging:
						pan(screen - _press_at)
			elif not _arranging:
				pan(relative)
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
			pan(screen - _press_at)
			return
	if drag != null and drag.dragging >= 0:
		drag.move(world_pos(screen))
	else:
		pan(relative)


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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _arrange_on():
		arrange.cancel_held()
	elif event is InputEventMouseMotion and _pressed:
		if not button_down.call():
			# The release went to a HUD control; finish where the pointer last was.
			release(_last)
		else:
			move(event.position, event.relative)
	elif event is InputEventMouseMotion and _arrange_on():
		arrange.hover(world_pos(event.position))


func _draw() -> void:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return
	var font := ThemeDB.fallback_font
	for id in w.pack.rooms:
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
		draw_rect(rect.grow(-2), Color.from_hsv(hue, 0.4, 0.82, faded))
		draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 + 4), str(t.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(0.15, 0.15, 0.15))
	for m in w.messes:
		var at := layout.cell_center(str(m.room), int(m.x), int(m.y))
		draw_rect(Rect2(at - Vector2(8, 6), Vector2(16, 12)), Color(0.45, 0.3, 0.18))
		_small_name(font, at, thing_name(w.pack.mess_types, str(m.type)))
	for c in w.collectibles:
		var at := layout.cell_center(str(c.room), int(c.x), int(c.y))
		draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), Color(0.95, 0.8, 0.2))
		_small_name(font, at, thing_name(w.pack.collectibles, str(c.type)))
	_draw_hover(w)
	_draw_ghost(w)


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
		"object":
			var o := w.object(int(hover.uid))
			if not o.is_empty():
				rect = layout.object_rect(o, w.pack)
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
