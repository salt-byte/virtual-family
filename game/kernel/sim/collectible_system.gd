class_name CollectibleSystem
extends RefCounted
## Things that drop outdoors: random spawns, expiry, and pick-up settlement.
## A collectible is "claimed" while a living person's picking action targets it.


## Expires old drops, then maybe spawns one while below the cap.
static func step(world: World, dt: float) -> void:
	_expire(world)
	# One drop per `collectible_interval_min` on average, per minute scaled to the step.
	if _ordinary_count(world) < int(world.pack.cfg("collectible_max")) \
			and world.rng.chance(1.0 / float(world.pack.cfg("collectible_interval_min")) * (dt / 60.0)):
		spawn(world)


## Ordinary collectibles on the ground (story fragments do not count toward the cap).
static func _ordinary_count(world: World) -> int:
	var n := 0
	for c in world.collectibles:
		if not c.has("story"):
			n += 1
	return n


## Adds one collectible of `type` ("" picks by weight) in a random built outdoor room (one of
## the type's `rooms` when any of those is built and outdoor) and returns its uid; -1 when
## the type is unknown or there is no outdoor room.
static func spawn(world: World, type := "") -> int:
	var rooms: Array = world.rooms_built.filter(func(r): return bool(world.pack.rooms[r]["outdoor"]))
	if rooms.is_empty() or world.pack.collectibles.is_empty():
		return -1
	if type == "":
		var ids: Array = world.pack.collectibles.keys()
		var weights: Array = ids.map(func(id): return float(world.pack.collectibles[id]["weight"]))
		type = str(world.rng.weighted_pick(ids, weights))
	elif not world.pack.collectibles.has(type):
		return -1
	var preferred: Array = world.pack.collectibles[type].get("rooms", [])
	if not preferred.is_empty():
		var there := rooms.filter(func(r): return preferred.has(r))
		if not there.is_empty():
			rooms = there
	var room := str(world.rng.pick(rooms))
	var r: Dictionary = world.pack.rooms[room]
	var uid := world.next_uid()
	world.collectibles.append({"uid": uid, "type": type, "room": room,
		"x": world.rng.randi_range(0, int(r["w"]) - 1), "y": world.rng.randi_range(0, int(r["h"]) - 1),
		"expires_at": world.now + int(world.pack.cfg("collectible_ttl_min")) * 60})
	world.emit("collectible_spawned", {"uid": uid, "kind": type, "room": room})
	return uid


## The collectible with this uid, or {} when missing.
static func find(world: World, uid: int) -> Dictionary:
	for c in world.collectibles:
		if c.uid == uid:
			return c
	return {}


## True when a living person other than `except` is on their way to / picking this up.
static func claimed_by_other(world: World, uid: int, except: Person) -> bool:
	return AutonomySystem.target_claimed(world, uid, "collectible", except)


## First collectible (stable order) that nobody but `p` has claimed, else -1.
static func first_free(world: World, p: Person) -> int:
	for c in world.collectibles:
		if not claimed_by_other(world, c.uid, p):
			return c.uid
	return -1


## Settles a finished pick-up. The first of each type goes into the collection for free;
## duplicates pay their value. A collectible that has already gone is ignored.
static func collect(world: World, p: Person, uid: int) -> void:
	var c := find(world, uid)
	if c.is_empty():
		return
	world.collectibles.erase(c)
	if c.has("story"):
		StorySystem.found(world, p, c)
		return
	var type := str(c["type"])
	var value := int(world.pack.collectibles[type]["value"])
	var first := int(world.collection.get(type, 0)) == 0
	world.stats["collected"] = int(world.stats["collected"]) + 1
	world.collection[type] = int(world.collection.get(type, 0)) + 1
	if first:
		value = 0
	else:
		EconomySystem.earn(world, value, "collect", p.uid)
	world.emit("collected", {"uid": uid, "kind": type, "value": value, "first": first, "person": p.uid})


static func _expire(world: World) -> void:
	for c in world.collectibles.duplicate():
		if world.now < int(c["expires_at"]):
			continue
		world.collectibles.erase(c)
		for q in world.people:
			if q.alive and not q.current.is_empty() and int(q.current.get("target_uid", -1)) == c.uid \
					and AutonomySystem.target_kind(world.pack.actions[q.current["action"]]) == "collectible":
				AutonomySystem.cancel(world, q)
		world.emit("collectible_expired", {"uid": c.uid})
