class_name CarrySystem
extends RefCounted
## Carrying what was picked up or swept to where it belongs. A collectible type or a mess
## type with `stow` (an object type) is not settled where it lay: when the picking or
## cleaning action is done, the one who did it carries it to the nearest object of that
## type in a built room (the second leg of the same action: `Person.current` keeps the
## action id and gets `carry`), and only when they put it down does it count: a
## collectible goes into the box (or, with `stock`, into that stock), litter pays its
## `scrap`. A pack (or a house) without such an object settles at once, as before.
## Called away on the way (`drop`), they let it fall where they are: a collectible lies
## there again, a mess spills there again.
##
## The leg's length is a pure function of the plan: the cells between where the thing lay
## and the object, walked at `carry.cell_s` seconds a cell, plus `carry.drop_s` to put it
## down, in whole steps. The view walks the same way at its own pace (see `PersonView`).
##
## `Person.current.carry`: {kind ("collectible" / "mess"), type, uid (what it was), room, x,
## y (where it lay), total_s (the leg's length), plus `c` (the collectible itself) for a
## collectible}. Events: carry_started {person, kind, type, to (object uid)}, carried
## {person, kind, type, to}, carry_dropped {person, kind, type, room, x, y}.


## The object type `kind` ("collectible" / "mess") of `type` is carried to ("" for none).
static func stow_type(pack: Pack, kind: String, type: String) -> String:
	var table: Dictionary = pack.collectibles if kind == "collectible" else pack.mess_types
	return str(table.get(type, {}).get("stow", ""))


## The site cell of a spot (room-local cell x, y of a room with a plan position).
static func site_cell(pack: Pack, room: String, x: int, y: int) -> Vector2i:
	var r: Dictionary = pack.rooms.get(room, {})
	return Vector2i(int(r.get("x", 0)) + x, int(r.get("y", 0)) + y)


## The uid of the nearest object of `type` in a built room to the spot (-1 for none).
static func destination(world: World, type: String, room: String, x: int, y: int) -> int:
	var from := site_cell(world.pack, room, x, y)
	var best := -1
	var best_d := INF
	for o in world.objects:
		if str(o.type) != type or not world.rooms_built.has(str(o.room)):
			continue
		var d := _cells(from, site_cell(world.pack, str(o.room), int(o.x), int(o.y)))
		if d < best_d:
			best_d = d
			best = int(o.uid)
	return best


static func _cells(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))


## Seconds of the leg from the spot to object `uid`: walk plus putting it down, whole steps.
static func leg_s(world: World, room: String, x: int, y: int, uid: int) -> int:
	var o := world.object(uid)
	var c: Dictionary = world.pack.cfg("carry")
	var cells := _cells(site_cell(world.pack, room, x, y), site_cell(world.pack, str(o.room), int(o.x), int(o.y)))
	var s := cells * float(c.get("cell_s", 0.5)) + float(c.get("drop_s", 3.0))
	return maxi(ceili(s / world.step_s), 1) * world.step_s


## When the action `p` just finished picked up collectible `c` (already off the ground) or
## cleaned mess `m`: starts the carry leg and returns true, or returns false (nowhere to
## take it; the caller settles at once).
static func begin(world: World, p: Person, action_id: String, kind: String, thing: Dictionary, led := false) -> bool:
	if not p.alive:
		return false
	var type := str(thing.get("type", ""))
	var stow := stow_type(world.pack, kind, type)
	if stow == "":
		return false
	var room := str(thing.get("room", ""))
	var to := destination(world, stow, room, int(thing.get("x", 0)), int(thing.get("y", 0)))
	if to < 0:
		return false
	var total := leg_s(world, room, int(thing.get("x", 0)), int(thing.get("y", 0)), to)
	var carry := {"kind": kind, "type": type, "uid": int(thing.get("uid", -1)), "room": room,
		"x": int(thing.get("x", 0)), "y": int(thing.get("y", 0)), "total_s": total}
	if kind == "collectible":
		carry["c"] = thing.duplicate(true)
	p.current = {"action": action_id, "object_uid": to, "target_uid": -1, "remaining_s": total, "carry": carry}
	if led:
		p.current["led"] = true
	world.emit("carry_started", {"person": p.uid, "kind": kind, "type": type, "to": to})
	return true


## One step of a carry leg: counts down, and settles when it is done.
static func progress(world: World, p: Person, dt: float) -> void:
	var cur := p.current
	cur["remaining_s"] = int(cur["remaining_s"]) - int(dt)
	if int(cur["remaining_s"]) > 0:
		return
	var carry: Dictionary = cur["carry"]
	var to := int(cur.get("object_uid", -1))
	p.current = {}
	_settle(world, p, carry)
	world.emit("carried", {"person": p.uid, "kind": str(carry.kind), "type": str(carry.type), "to": to})


static func _settle(world: World, p: Person, carry: Dictionary) -> void:
	if str(carry.kind) == "collectible":
		CollectibleSystem.settle(world, p, carry.get("c", {}))
	else:
		MessSystem.scrap(world, str(carry.type), p.uid)


## Called away while carrying: the thing falls where they are now (along the way from where
## it lay to the object, by the share of the leg walked), in a built room; else where it
## lay. A collectible lies there again (with the time it had left), a mess spills again.
static func drop(world: World, p: Person) -> void:
	var cur := p.current
	var carry: Dictionary = cur.get("carry", {})
	if carry.is_empty():
		return
	var spot := _spot_on_the_way(world, carry, int(cur.get("object_uid", -1)), int(cur.get("remaining_s", 0)))
	var kind := str(carry.kind)
	if kind == "collectible":
		var c: Dictionary = (carry.get("c", {}) as Dictionary).duplicate(true)
		if not c.is_empty():
			c["room"] = spot[0]
			c["x"] = spot[1]
			c["y"] = spot[2]
			world.collectibles.append(c)
	else:
		MessSystem.spawn(world, str(carry.type), spot[0], Vector2i(spot[1], spot[2]))
	world.emit("carry_dropped", {"person": p.uid, "kind": kind, "type": str(carry.type),
		"room": spot[0], "x": spot[1], "y": spot[2]})


## [room, x, y]: the built-room cell nearest the point the share walked of the leg reaches.
static func _spot_on_the_way(world: World, carry: Dictionary, to: int, remaining: int) -> Array:
	var room := str(carry.room)
	var here := [room, int(carry.x), int(carry.y)]
	var o := world.object(to)
	if o.is_empty():
		return here
	var drop_s := float(world.pack.cfg("carry").get("drop_s", 3.0))
	var walk := maxf(float(carry.total_s) - drop_s, 1.0)
	var share := clampf((float(carry.total_s) - float(remaining)) / walk, 0.0, 1.0)
	var a := site_cell(world.pack, room, int(carry.x), int(carry.y))
	var b := site_cell(world.pack, str(o.room), int(o.x), int(o.y))
	var at := Vector2i(roundi(lerpf(a.x, b.x, share)), roundi(lerpf(a.y, b.y, share)))
	var best := here
	var best_d := INF
	for rid in world.rooms_built:
		var r: Dictionary = world.pack.rooms[rid]
		var lx := clampi(at.x - int(r.x), 0, int(r.w) - 1)
		var ly := clampi(at.y - int(r.y), 0, int(r.h) - 1)
		var d := _cells(at, Vector2i(int(r.x) + lx, int(r.y) + ly))
		if d < best_d:
			best_d = d
			best = [str(rid), lx, ly]
	return best
