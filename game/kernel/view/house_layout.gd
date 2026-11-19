class_name HouseLayout
extends RefCounted
## Pure geometry of the house view: room arrangement, cell <-> screen conversion and hit
## testing. No rendering. When the pack gives every room a grid position (`x`, `y` in
## cells) rooms sit there; otherwise they sit left to right in pack order, bottom-aligned.
## The indoor wall strip sits above the floor rect and is not part of room_rect().

const CELL := Vector2(48, 36)
const GAP := 48.0
const WALL := 30.0

## The ground plan (walls, doors, walking) when the pack has a `site`; `site.enabled` false
## otherwise, and everything here behaves as before.
var site: HouseSite
var _rects: Dictionary = {}  # room id -> Rect2 (floor only)
var _indoor: Dictionary = {}
var _order: Array[String] = []

## A broken pack (a room that is not an object, or lacks a numeric w/h) must not raise an
## engine error here: such rooms are left out; the pack error overlay explains the rest.
func _init(pack: Pack) -> void:
	site = HouseSite.new(pack)
	var valid: Array[String] = []
	var tallest := 0.0
	for id in pack.rooms:
		var r = pack.rooms[id]
		if r is Dictionary and _num(r, "w") > 0.0 and _num(r, "h") > 0.0:
			valid.append(str(id))
			tallest = maxf(tallest, _num(r, "h") * CELL.y)
	var positioned := not valid.is_empty() and valid.all(func(id):
		return _whole(pack.rooms[id], "x") and _whole(pack.rooms[id], "y"))
	var x := 0.0
	for id in valid:
		var r: Dictionary = pack.rooms[id]
		var size := Vector2(_num(r, "w") * CELL.x, _num(r, "h") * CELL.y)
		if positioned:
			_rects[id] = Rect2(Vector2(_num(r, "x"), _num(r, "y")) * CELL, size)
		else:
			_rects[id] = Rect2(Vector2(x, tallest - size.y), size)
		_indoor[id] = not bool(r.get("outdoor", false))
		_order.append(id)
		x += size.x + GAP

## Whether `r[key]` is a whole number of at least 0 (a usable grid coordinate).
static func _whole(r: Dictionary, key: String) -> bool:
	var v = r.get(key)
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and v >= 0 and float(v) == floorf(float(v))

static func _num(r: Dictionary, key: String) -> float:
	var v = r.get(key, 0)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0.0

func room_rect(room: String) -> Rect2:
	return _rects.get(room, Rect2())

## The area the view may show: the whole map with a site, else the rooms with their walls.
func bounds() -> Rect2:
	if site.enabled:
		return site.rect()
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

## The room among `rooms` whose floor rect (wall strip included for indoor rooms) is closest
## to `pos`; "" when `rooms` is empty or has no known room.
func nearest_room(pos: Vector2, rooms: Array) -> String:
	var best := ""
	var best_d := INF
	for id in _order:
		if not id in rooms:
			continue
		var r: Rect2 = _rects[id]
		if _indoor[id]:
			r = Rect2(r.position.x, r.position.y - WALL, r.size.x, r.size.y + WALL)
		var c := pos.clamp(r.position, r.end)
		var d := pos.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = id
	return best

func object_rect(o: Dictionary, pack: Pack) -> Rect2:
	var t: Dictionary = pack.object_types.get(str(o.type), {})
	var size := Vector2(float(t.get("w", 1)), float(t.get("h", 1))) * CELL
	return Rect2(cell_to_pos(str(o.room), int(o.x), int(o.y)), size)

## Where a person stands to use `o`. With a site plan: an open cell in front of it, else
## beside or behind it, never on it nor across a wall from it (`HouseSite.use_spot`).
## Without one: just below it, or its middle when that is outside its room.
func stand_pos(o: Dictionary, pack: Pack, taken := {}) -> Vector2:
	var r := object_rect(o, pack)
	if site.enabled and room_rect(str(o.room)).size != Vector2.ZERO:
		return site.use_spot(cells_of(r), taken)
	var p := Vector2(r.get_center().x, r.end.y + CELL.y * 0.5)
	if room_rect(str(o.room)).has_point(p):
		return p
	return r.get_center()

## The map cells a rect in house coordinates covers (a site plan's cells).
static func cells_of(r: Rect2) -> Rect2i:
	return Rect2i(Vector2i((r.position / CELL).round()), Vector2i((r.size / CELL).round()))


## Every cell furniture stands on, in built rooms (Vector2i -> true), for the site plan.
func furniture_cells(world: World) -> Dictionary:
	var out := {}
	for o in world.objects:
		if not str(o.room) in world.rooms_built:
			continue
		var r := cells_of(object_rect(o, world.pack))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out[Vector2i(x, y)] = true
	return out


## Where someone heading for `p` stops (see `HouseSite.stop_point`); `p` without a site.
func stop_point(p: Vector2, taken := {}) -> Vector2:
	return site.stop_point(p, taken) if site.enabled else p


## What is under `pos`: a story's dig mark (with its `story`), a collectible, then a mess,
## then furniture, else the room.
## `furniture_only` (arrange mode) skips messes and collectibles so the piece under them
## can still be picked up.
func pick(world: World, pos: Vector2, furniture_only := false) -> Dictionary:
	var hit := pos_to_cell(pos)
	if hit.is_empty():
		return {"kind": "", "uid": -1, "room": ""}
	var room: String = hit.room
	if room in world.rooms_built:
		if not furniture_only:
			for m in StorySystem.marks(world):
				if m.get("dig", false) and m.room == room and m.x == hit.x and m.y == hit.y:
					return {"kind": "mark", "uid": -1, "room": room, "story": m.story}
		for c in ([] if furniture_only else world.collectibles):
			if c.room == room and c.x == hit.x and c.y == hit.y:
				return {"kind": "collectible", "uid": c.uid, "room": room}
		for m in ([] if furniture_only else world.messes):
			if m.room == room and m.x == hit.x and m.y == hit.y:
				return {"kind": "mess", "uid": m.uid, "room": room}
		for o in world.objects:
			if o.room == room and object_rect(o, world.pack).has_point(pos):
				return {"kind": "object", "uid": o.uid, "room": room}
	return {"kind": "room", "uid": -1, "room": room}
