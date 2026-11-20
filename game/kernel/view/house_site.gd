class_name HouseSite
extends RefCounted
## The ground plan of a pack that has a `site` in pack.json: one map of cells on which the
## rooms sit, the walls that grow from them (rooms share walls, walls take no cells), the
## openings in those walls, and where a person can walk. Pure geometry, no drawing.
##
## Walls are edges between cells. An east-west edge is keyed Vector2i(cell x, line y): it
## separates cell (x, y - 1) from cell (x, y). A north-south edge is keyed Vector2i(line x,
## cell y): it separates (x - 1, y) from (x, y).
##
## Which walls stand depends on the rooms built, so `update` takes the built set and
## rebuilds only when it changed.

const CELL := Vector2(48, 36)
## Edge kinds.
const HOUSE := "house"
const COMPOUND := "compound"
const FENCE := "fence"
## A straight walk keeps this far (pixels) from walls on either side.
const CLEARANCE := 9.0

var enabled := false
var size := Vector2i.ZERO
var compound := Rect2i()
var has_compound := false
var ground := Color(0.77, 0.84, 0.59)
var compound_ground := Color(0.89, 0.76, 0.58)
## Pack data, as given: [{x, y, along, len}] (a fence may name a `room`: it stands only while
## that room is built) and decor dictionaries.
var doors: Array = []
var fences: Array = []
var decor: Array = []

## Walls standing now: edge -> kind. Open doors: edge -> true (the wall entry stays).
var h_walls: Dictionary = {}
var v_walls: Dictionary = {}
var h_open: Dictionary = {}
var v_open: Dictionary = {}
## Cells nobody walks on (unbuilt indoor rooms, solid decor, furniture): Vector2i -> true.
var blocked: Dictionary = {}
## Cells under furniture, as the view last set them (`set_furniture`): Vector2i -> true.
var furniture: Dictionary = {}
## Bumped on every rebuild, so drawing can tell the plan changed.
var version := 0

var _rooms: Dictionary = {}       # room id -> Rect2i
var _indoor: Dictionary = {}      # room id -> bool
var _room_at: Dictionary = {}     # Vector2i -> room id
var _built: Dictionary = {}       # room id -> true, as last updated
var _key := "\n"
var _astar := AStar2D.new()


func _init(pack: Pack) -> void:
	var s = pack.config.get("site", {}) if pack != null else {}
	if not (s is Dictionary and s.get("w") is int and s.get("h") is int and s["w"] > 0 and s["h"] > 0):
		return
	enabled = true
	size = Vector2i(s["w"], s["h"])
	if s.get("ground") is String and Color.html_is_valid(s["ground"]):
		ground = Color.html(s["ground"])
	var c = s.get("compound")
	if c is Dictionary and c.get("x") is int and c.get("y") is int and c.get("w") is int and c.get("h") is int:
		has_compound = true
		compound = Rect2i(c["x"], c["y"], c["w"], c["h"])
		if c.get("ground") is String and Color.html_is_valid(c["ground"]):
			compound_ground = Color.html(c["ground"])
	doors = _openings(s.get("doors", []))
	fences = _openings(s.get("fences", []))
	for d in s.get("decor", []):
		if d is Dictionary and d.get("color") is String and Color.html_is_valid(d["color"]):
			decor.append(d)
	for id in pack.rooms:
		var r = pack.rooms[id]
		if not (r is Dictionary and r.get("x") is int and r.get("y") is int and r.get("w") is int and r.get("h") is int):
			continue
		var rect := Rect2i(r["x"], r["y"], r["w"], r["h"])
		_rooms[id] = rect
		_indoor[id] = not bool(r.get("outdoor", false))
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_room_at[Vector2i(x, y)] = id


static func _openings(list) -> Array:
	var out: Array = []
	if list is Array:
		for d in list:
			if d is Dictionary and d.get("x") is int and d.get("y") is int and d.get("len") is int and d.get("along") in ["x", "y"]:
				out.append(d)
	return out


## The map in house coordinates.
func rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size) * CELL)


func room_at(cell: Vector2i) -> String:
	return _room_at.get(cell, "")


## Whether `room` is a built room with a roof (indoor): only those raise walls.
func built_indoor(room: String) -> bool:
	return room != "" and _built.has(room) and _indoor.get(room, false)


## Whether a cell is an unbuilt indoor room (a bare foundation).
func foundation(cell: Vector2i) -> bool:
	var room := room_at(cell)
	return room != "" and _indoor.get(room, false) and not _built.has(room)


## Rebuilds the walls, doors and walking graph when the built rooms changed.
func update(built: Dictionary) -> void:
	if not enabled:
		return
	var ids := built.keys()
	ids.sort()
	var key := ",".join(ids)
	if key == _key:
		return
	_key = key
	_built = built.duplicate()
	_rebuild()


func _rebuild() -> void:
	version += 1
	h_walls = {}
	v_walls = {}
	h_open = {}
	v_open = {}
	blocked = {}
	for id in _rooms:
		if not built_indoor(id):
			continue
		var r: Rect2i = _rooms[id]
		for x in range(r.position.x, r.end.x):
			h_walls[Vector2i(x, r.position.y)] = HOUSE
			h_walls[Vector2i(x, r.end.y)] = HOUSE
		for y in range(r.position.y, r.end.y):
			v_walls[Vector2i(r.position.x, y)] = HOUSE
			v_walls[Vector2i(r.end.x, y)] = HOUSE
	for f in fences:
		# A fence that names a room stands once that room is built (a pen's rails).
		if str(f.get("room", "")) == "" or _built.has(str(f["room"])):
			_mark(f, FENCE)
	if has_compound:
		for x in range(compound.position.x, compound.end.x):
			h_walls[Vector2i(x, compound.position.y)] = COMPOUND
			h_walls[Vector2i(x, compound.end.y)] = COMPOUND
		for y in range(compound.position.y, compound.end.y):
			v_walls[Vector2i(compound.position.x, y)] = COMPOUND
			v_walls[Vector2i(compound.end.x, y)] = COMPOUND
	for d in doors:
		for i in int(d["len"]):
			if d["along"] == "x":
				var e := Vector2i(int(d["x"]) + i, int(d["y"]))
				if h_walls.has(e) and not foundation(e - Vector2i(0, 1)) and not foundation(e):
					h_open[e] = true
			else:
				var e2 := Vector2i(int(d["x"]), int(d["y"]) + i)
				if v_walls.has(e2) and not foundation(e2 - Vector2i(1, 0)) and not foundation(e2):
					v_open[e2] = true
	_block()


## Marks the blocked cells and rebuilds the walking graph (walls unchanged).
func _block() -> void:
	blocked = {}
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if foundation(c) or _decor_solid(c) or furniture.has(c):
				blocked[c] = true
	_build_graph()


## The cells furniture stands on (Vector2i -> true): nobody walks or stops there. Rebuilds
## the walking graph only when the set changed.
func set_furniture(cells: Dictionary) -> void:
	if not enabled:
		return
	var same := cells.size() == furniture.size()
	if same:
		for c in cells:
			if not furniture.has(c):
				same = false
				break
	if same:
		return
	furniture = cells.duplicate()
	if _key != "\n":
		_block()


func _mark(d: Dictionary, kind: String) -> void:
	for i in int(d["len"]):
		if d["along"] == "x":
			h_walls[Vector2i(int(d["x"]) + i, int(d["y"]))] = kind
		else:
			v_walls[Vector2i(int(d["x"]), int(d["y"]) + i)] = kind


func _decor_solid(c: Vector2i) -> bool:
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var solid := false
	for d in decor:
		if not (bool(d.get("solid", false)) or bool(d.get("passable", false))):
			continue
		var r := Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))
		if r.has_point(p):
			solid = bool(d.get("solid", false))
	return solid


## Whether the east-west edge (x, line) lets a person through.
func h_free(e: Vector2i) -> bool:
	return not h_walls.has(e) or h_open.has(e)


func v_free(e: Vector2i) -> bool:
	return not v_walls.has(e) or v_open.has(e)


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func walkable(c: Vector2i) -> bool:
	return _inside(c) and not blocked.has(c)


## Whether one step from cell `a` to the neighbouring cell `b` (also diagonal) is open.
func step_open(a: Vector2i, b: Vector2i) -> bool:
	if not walkable(b):
		return false
	var d := b - a
	if d.x != 0 and d.y != 0:
		var via1 := Vector2i(b.x, a.y)
		var via2 := Vector2i(a.x, b.y)
		return walkable(via1) and walkable(via2) and _straight_open(a, via1) and _straight_open(via1, b) \
			and _straight_open(a, via2) and _straight_open(via2, b)
	return _straight_open(a, b)


func _straight_open(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return v_free(Vector2i(maxi(a.x, b.x), a.y))
	if a.y != b.y:
		return h_free(Vector2i(a.x, maxi(a.y, b.y)))
	return true


func _id(c: Vector2i) -> int:
	return c.y * size.x + c.x


func _build_graph() -> void:
	_astar.clear()
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			_astar.add_point(_id(c), Vector2(c) * CELL + CELL * 0.5)
			if blocked.has(c):
				_astar.set_point_disabled(_id(c), true)
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if blocked.has(c):
				continue
			for d in dirs:
				var n: Vector2i = c + d
				if _inside(n) and step_open(c, n) and step_open(n, c):
					_astar.connect_points(_id(c), _id(n))


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL).floor())


## The points to walk through from `from` to `to`, `to` itself left out: [] when the
## straight line is clear (or no route exists: then the person walks straight, as before).
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not enabled:
		return out
	# From or to a blocked cell (a seat, a bed): out by, and in by, the open cell nearest the
	# point itself (the side of the piece they sit on), never across the rest of the piece.
	var a := cell_of(from)
	var b := cell_of(to)
	if not walkable(a) and not walkable(b) and from.distance_to(to) < CELL.x * 1.5:
		return out  # along the same seat or bed: shuffle over
	# Seats and beds are got on and off from the front (the south side), when it is open.
	var a2 := a if walkable(a) else nearest_open(a, {}, from + Vector2(0, CELL.y * 0.6))
	var b2 := b if walkable(b) else nearest_open(b, {}, to + Vector2(0, CELL.y * 0.6))
	if a2 != a and a2.x >= 0:
		var exit := _edge_point(from, a, a2)
		out.append(exit)
		out.append_array(route(exit, to))
		return out
	if b2 != b and b2.x >= 0:
		var entry := _edge_point(to, b, b2)
		out = route(from, entry)
		out.append(entry)
		return out
	if clear_line(from, to):
		return out
	if a2.x < 0 or b2.x < 0:
		return out
	var pts: Array[Vector2] = []
	if a2 != a:
		pts.append(centre(a2))
	if a2 != b2:
		var ids := _astar.get_id_path(_id(a2), _id(b2))
		if ids.size() < 2:
			return out
		for i in range(1, ids.size() - 1):
			pts.append(_astar.get_point_position(ids[i]))
	if b2 != b:
		pts.append(centre(b2))
	if pts.is_empty():
		return out
	# Pull the string tight: from each corner, go as far along the cells as is clear.
	var anchor := from
	var i := 0
	while i < pts.size() and not clear_line(anchor, to):
		var j := i
		while j + 1 < pts.size() and clear_line(anchor, pts[j + 1]):
			j += 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out


## A way from `from` to `to` that keeps off `cells` (Vector2i -> true: where someone stands
## in the way) as well, the start and end cells aside: [found, points] (`route`'s points);
## found is false when there is no way round.
func detour(from: Vector2, to: Vector2, cells: Dictionary) -> Array:
	if not enabled:
		return [false, PackedVector2Array()]
	var added: Array[Vector2i] = []
	var skip := [cell_of(from), cell_of(to)]
	for c in cells:
		if _inside(c) and not blocked.has(c) and not c in skip:
			blocked[c] = true
			_astar.set_point_disabled(_id(c), true)
			added.append(c)
	var pts := route(from, to)
	# The way found must keep off the cells all along (route falls back to walking straight
	# when there is no way: that is no way round).
	var ok := not pts.is_empty() or clear_line(from, to)
	var at := from
	for i in pts.size() + 1:
		var nxt := pts[i] if i < pts.size() else to
		var n := int(ceil(at.distance_to(nxt) / 6.0))
		for k in range(1, n + 1):
			if added.has(cell_of(at.lerp(nxt, float(k) / float(n)))):
				ok = false
		at = nxt
	for c in added:
		blocked.erase(c)
		_astar.set_point_disabled(_id(c), false)
	return [ok, pts]


## Whether a straight step from `a` to `b` goes through a closed wall (doors are open; a
## step through a cell corner may go either way round). Furniture does not count.
func crosses_wall(a: Vector2, b: Vector2) -> bool:
	if not enabled:
		return false
	var c := cell_of(a)
	if c == cell_of(b):
		return false
	var n := int(ceil(a.distance_to(b) / 4.0)) + 1
	for i in range(1, n + 1):
		var q := cell_of(a.lerp(b, float(i) / float(n)))
		if q == c:
			continue
		var d := q - c
		if absi(d.x) + absi(d.y) == 1:
			if not edge_free(c, q):
				return true
		else:
			var v1 := Vector2i(q.x, c.y)
			var v2 := Vector2i(c.x, q.y)
			if not ((edge_free(c, v1) and edge_free(v1, q)) or (edge_free(c, v2) and edge_free(v2, q))):
				return true
		c = q
	return false


## Where someone at `p` in blocked cell `c` steps out into open cell `n`: straight across
## the edge between, to the middle of `n` in line with `p`; the middle of `n` when `n` is not
## beside `c` (or a wall stands between).
func _edge_point(p: Vector2, c: Vector2i, n: Vector2i) -> Vector2:
	var d := n - c
	if absi(d.x) + absi(d.y) != 1 or not edge_free(c, n):
		return centre(n)
	var q := centre(n)
	if d.x == 0:
		q.x = clampf(p.x, float(n.x) * CELL.x + STOP_MARGIN_X, float(n.x + 1) * CELL.x - STOP_MARGIN_X)
	else:
		q.y = clampf(p.y, float(n.y) * CELL.y + STOP_MARGIN_Y, float(n.y + 1) * CELL.y - STOP_MARGIN_Y)
	return q


## Whether a straight walk from `a` to `b` crosses no standing wall and no blocked cell, with
## CLEARANCE to spare on both sides (so nobody brushes a door post).
func clear_line(a: Vector2, b: Vector2) -> bool:
	if not enabled:
		return true
	if not _line_ok(a, b):
		return false
	if a.distance_squared_to(b) < 0.0001:
		return true
	var side := (b - a).normalized().orthogonal() * CLEARANCE
	return _line_ok(a + side, b + side) and _line_ok(a - side, b - side)


## The cells the segment passes through, exactly, each step checked with `step_open`; a
## segment through a cell corner counts as a diagonal step.
func _line_ok(a: Vector2, b: Vector2) -> bool:
	var p := a / CELL
	var q := b / CELL
	var c := Vector2i(p.floor())
	var end := Vector2i(q.floor())
	var d := q - p
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tdx := absf(1.0 / d.x) if d.x != 0.0 else INF
	var tdy := absf(1.0 / d.y) if d.y != 0.0 else INF
	var tmx := (float(c.x + (1 if sx > 0 else 0)) - p.x) / d.x if d.x != 0.0 else INF
	var tmy := (float(c.y + (1 if sy > 0 else 0)) - p.y) / d.y if d.y != 0.0 else INF
	var guard := 0
	while c != end and guard < 512:
		guard += 1
		var nxt := c
		if absf(tmx - tmy) < 1e-9:
			nxt = c + Vector2i(sx, sy)
			tmx += tdx
			tmy += tdy
		elif tmx < tmy:
			nxt = c + Vector2i(sx, 0)
			tmx += tdx
		else:
			nxt = c + Vector2i(0, sy)
			tmy += tdy
		if minf(tmx, tmy) - minf(tdx, tdy) > 1.0 + 1e-9 and nxt != end:
			break
		if not step_open(c, nxt):
			return false
		c = nxt
	return true


## Every standing wall as runs along one line, for drawing: {along "x"|"y", line, a, b (cells,
## b exclusive), kind}. A run holds one kind; doors inside it are listed by `openings`.
func runs() -> Array:
	var out: Array = []
	for pair in [["x", h_walls], ["y", v_walls]]:
		var along: String = pair[0]
		var walls: Dictionary = pair[1]
		var lines := {}
		for e in walls:
			var line: int = e.y if along == "x" else e.x
			var at: int = e.x if along == "x" else e.y
			if not lines.has(line):
				lines[line] = []
			lines[line].append(at)
		var keys := lines.keys()
		keys.sort()
		for line in keys:
			var cells: Array = lines[line]
			cells.sort()
			var start: int = cells[0]
			var prev: int = cells[0]
			var kind: String = walls[_edge(along, line, start)]
			for k in range(1, cells.size() + 1):
				var c: int = cells[k] if k < cells.size() else -999
				var ck: String = walls[_edge(along, line, c)] if k < cells.size() else ""
				if c == prev + 1 and ck == kind:
					prev = c
					continue
				out.append({"along": along, "line": line, "a": start, "b": prev + 1, "kind": kind})
				if k < cells.size():
					start = c
					prev = c
					kind = ck
	return out


static func _edge(along: String, line: int, at: int) -> Vector2i:
	return Vector2i(at, line) if along == "x" else Vector2i(line, at)


## Whether the edge at cell `at` of this line is an open door.
func is_open(along: String, line: int, at: int) -> bool:
	return h_open.has(Vector2i(at, line)) if along == "x" else v_open.has(Vector2i(line, at))


func centre(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


## Whether nothing stands between cells `a` and `b`, side by side: no wall, or an open door.
func edge_free(a: Vector2i, b: Vector2i) -> bool:
	return _straight_open(a, b)


## Whether any wall (standing or opened as a door) lies on the edge between `a` and `b`.
func edge_walled(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return v_walls.has(Vector2i(maxi(a.x, b.x), a.y))
	return h_walls.has(Vector2i(a.x, maxi(a.y, b.y)))


## The open cell nearest `from` (not counting `from` itself unless it is open), going round
## walls through doors only and over anything else; Vector2i(-1, -1) when none is near.
## `taken` (Vector2i -> true) cells count as not open.
func nearest_open(from: Vector2i, taken := {}, aim := Vector2(INF, INF)) -> Vector2i:
	var seen := {from: true}
	var ring: Array[Vector2i] = [from]
	var target := aim if aim.x != INF else centre(from)
	var home := room_at(from)
	for step in 12:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for c in ring:
			if walkable(c) and not taken.has(c):
				# Another room only when its own has no open cell this near.
				var d := centre(c).distance_squared_to(target) + (0.0 if room_at(c) == home else 1e7)
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
		var next: Array[Vector2i] = []
		for c in ring:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if _inside(n) and not seen.has(n) and _straight_open(c, n):
					seen[n] = true
					next.append(n)
		if next.is_empty():
			break
		ring = next
	return Vector2i(-1, -1)


## How far (pixels) a stop point keeps from a wall line beside it; a stop point's feet span
## this much sideways.
const STOP_MARGIN_X := 20.0
const STOP_MARGIN_Y := 12.0
const FEET := 14.0


## Whether a person can stop at `p`: the cells under their feet (p.x +- FEET) are open, no
## wall stands between them, and `p` keeps STOP_MARGIN from any wall line (doors too: no one
## stops in a doorway).
func can_stop(p: Vector2) -> bool:
	if not enabled:
		return true
	var c := cell_of(p)
	if not walkable(c):
		return false
	for dx in [-FEET, FEET]:
		var o := cell_of(p + Vector2(dx, 0))
		if o != c and (not walkable(o) or edge_walled(c, o)):
			return false
	var lo := Vector2(c) * CELL
	var hi := lo + CELL
	if p.x - lo.x < STOP_MARGIN_X and v_walls.has(Vector2i(c.x, c.y)):
		return false
	if hi.x - p.x < STOP_MARGIN_X and v_walls.has(Vector2i(c.x + 1, c.y)):
		return false
	if p.y - lo.y < STOP_MARGIN_Y and h_walls.has(Vector2i(c.x, c.y)):
		return false
	if hi.y - p.y < STOP_MARGIN_Y and h_walls.has(Vector2i(c.x, c.y + 1)):
		return false
	return true


## Where a person heading for `p` stops: `p` itself when they can stop there, else the middle
## of the nearest open cell (on the same side of the walls). `taken` cells are skipped.
func stop_point(p: Vector2, taken := {}) -> Vector2:
	if not enabled:
		return p
	var c := cell_of(p)
	if can_stop(p) and not taken.has(c):
		return p
	var n := nearest_open(c, taken, p)
	return centre(n) if n.x >= 0 else p


## Where a person stands to use the furniture on cells `r` (map cells): in front of it (the
## row south of it), else beside it, else behind it; always on an open cell with no wall
## between it and the piece. The middle of the front edge when both cells there are open.
func use_spot(r: Rect2i, taken := {}) -> Vector2:
	var front := r.end.y
	var mid_x := float(r.position.x) + float(r.size.x) * 0.5
	var p := Vector2(mid_x * CELL.x, (front + 0.5) * CELL.y)
	if can_stop(p) and not taken.has(cell_of(p)) and not taken.has(cell_of(p + Vector2(-FEET, 0))) and not taken.has(cell_of(p + Vector2(FEET, 0))) and _faces(cell_of(p + Vector2(-FEET, 0)), r) and _faces(cell_of(p + Vector2(FEET, 0)), r):
		return p
	var cands: Array[Vector2i] = []
	var xs: Array = range(r.position.x, r.end.x)
	xs.sort_custom(func(x1, x2): return absf(x1 + 0.5 - mid_x) < absf(x2 + 0.5 - mid_x))
	for x in xs:
		cands.append(Vector2i(x, front))
	for y in range(r.end.y - 1, r.position.y - 1, -1):
		cands.append(Vector2i(r.position.x - 1, y))
		cands.append(Vector2i(r.end.x, y))
	for x in xs:
		cands.append(Vector2i(x, r.position.y - 1))
	for c in cands:
		if _inside(c) and walkable(c) and not taken.has(c) and _faces(c, r):
			return centre(c)
	var n := nearest_open(r.position + r.size / 2, taken)
	return centre(n) if n.x >= 0 else centre(Vector2i(r.position.x, r.end.y))


## Whether cell `c` (outside `r`) touches `r` with no wall between.
func _faces(c: Vector2i, r: Rect2i) -> bool:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = c + d
		if r.has_point(n) and edge_free(c, n):
			return true
	return false
