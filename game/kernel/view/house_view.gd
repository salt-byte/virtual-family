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

var _dragging := false
var _press_uid := -1
var _press_at := Vector2.ZERO
var _moved := false


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_moved = false
			_press_at = event.position
			_press_uid = person_at(world_pos(event.position))
		else:
			if _dragging and _press_uid >= 0 and not _moved:
				person_clicked.emit(_press_uid)
			_dragging = false
			_press_uid = -1
	elif event is InputEventMouseMotion and _dragging:
		if not _moved and event.position.distance_to(_press_at) > CLICK_SLOP:
			_moved = true
		# Dragging a person comes later; until then a drag always pans.
		if _moved:
			pan(event.relative)


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
	for o in w.objects:
		var t: Dictionary = w.pack.object_types.get(str(o.type), {})
		var rect := layout.object_rect(o, w.pack)
		var hue := float(hash(str(t.get("category", ""))) % 360) / 360.0
		draw_rect(rect.grow(-2), Color.from_hsv(hue, 0.4, 0.82))
		draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 + 4), str(t.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(0.15, 0.15, 0.15))
	for m in w.messes:
		draw_rect(Rect2(layout.cell_center(str(m.room), int(m.x), int(m.y)) - Vector2(8, 6), Vector2(16, 12)), Color(0.45, 0.3, 0.18))
	for c in w.collectibles:
		draw_rect(Rect2(layout.cell_center(str(c.room), int(c.x), int(c.y)) - Vector2(6, 6), Vector2(12, 12)), Color(0.95, 0.8, 0.2))


func _dashed(rect: Rect2, color: Color) -> void:
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	for seg in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		draw_dashed_line(seg[0], seg[1], color, 2.0, 8.0)
