class_name HouseLayout
extends RefCounted
## Pure geometry of the house view: room arrangement, cell <-> screen conversion and hit
## testing. No rendering. Rooms sit left to right in pack order, bottom-aligned; the
## indoor wall strip sits above the floor rect and is not part of room_rect().

const CELL := Vector2(48, 36)
const GAP := 48.0
const WALL := 30.0

var _rects: Dictionary = {}  # room id -> Rect2 (floor only)
var _indoor: Dictionary = {}
var _order: Array[String] = []

func _init(pack: Pack) -> void:
	var tallest := 0.0
	for id in pack.rooms:
		tallest = maxf(tallest, float(pack.rooms[id].h) * CELL.y)
	var x := 0.0
	for id in pack.rooms:
		var r: Dictionary = pack.rooms[id]
		var size := Vector2(float(r.w) * CELL.x, float(r.h) * CELL.y)
		_rects[id] = Rect2(Vector2(x, tallest - size.y), size)
		_indoor[id] = not bool(r.get("outdoor", false))
		_order.append(id)
		x += size.x + GAP

func room_rect(room: String) -> Rect2:
	return _rects.get(room, Rect2())

func bounds() -> Rect2:
	var out := Rect2()
	var first := true
	for id in _order:
		var r: Rect2 = _rects[id]
		if _indoor[id]:
			r = Rect2(r.position.x, r.position.y - WALL, r.size.x, r.size.y + WALL)
		out = r if first else out.merge(r)
		first = false
	return out

func cell_to_pos(room: String, x: int, y: int) -> Vector2:
	return room_rect(room).position + Vector2(x, y) * CELL

func cell_center(room: String, x: int, y: int) -> Vector2:
	return cell_to_pos(room, x, y) + CELL * 0.5

func pos_to_cell(pos: Vector2) -> Dictionary:
	for id in _order:
		var r: Rect2 = _rects[id]
		if r.has_point(pos):
			var c := ((pos - r.position) / CELL).floor()
			return {"room": id, "x": int(c.x), "y": int(c.y)}
	return {}

func object_rect(o: Dictionary, pack: Pack) -> Rect2:
	var t: Dictionary = pack.object_types.get(str(o.type), {})
	var size := Vector2(float(t.get("w", 1)), float(t.get("h", 1))) * CELL
	return Rect2(cell_to_pos(str(o.room), int(o.x), int(o.y)), size)

func stand_pos(o: Dictionary, pack: Pack) -> Vector2:
	var r := object_rect(o, pack)
	var p := Vector2(r.get_center().x, r.end.y + CELL.y * 0.5)
	if room_rect(str(o.room)).has_point(p):
		return p
	return r.get_center()

func pick(world: World, pos: Vector2) -> Dictionary:
	var hit := pos_to_cell(pos)
	if hit.is_empty():
		return {"kind": "", "uid": -1, "room": ""}
	var room: String = hit.room
	if room in world.rooms_built:
		for c in world.collectibles:
			if c.room == room and c.x == hit.x and c.y == hit.y:
				return {"kind": "collectible", "uid": c.uid, "room": room}
		for m in world.messes:
			if m.room == room and m.x == hit.x and m.y == hit.y:
				return {"kind": "mess", "uid": m.uid, "room": room}
		for o in world.objects:
			if o.room == room and object_rect(o, world.pack).has_point(pos):
				return {"kind": "object", "uid": o.uid, "room": room}
	return {"kind": "room", "uid": -1, "room": room}
