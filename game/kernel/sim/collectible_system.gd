class_name CollectibleSystem
extends RefCounted
## Things that drop outdoors: random spawns, expiry, and pick-up settlement.
## A collectible is "claimed" while a living person's picking action targets it.
## With `collect_keep` (pack.json) every find goes into the box (`World.box`, kind -> count)
## and the player sells the extras with the command `sell_collectible`, keeping one of each;
## a collectible with `keepsake` never sells (and with weight 0 never drops: a story gives it).


## Expires old drops, then maybe spawns one while below the cap.
static func step(world: World, dt: float) -> void:
	_expire(world)
	# One drop per `collectible_interval_min` on average, per minute scaled to the step.
	if _ordinary_count(world) < int(world.pack.cfg("collectible_max")) \
			and world.rng.chance(1.0 / float(world.pack.cfg("collectible_interval_min")) * (dt / 60.0) * ServiceSystem.drop_factor(world)):
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
## the type is unknown or there is no outdoor room. `in_room` (built) puts it there instead
## (an egg laid in the pen).
static func spawn(world: World, type := "", in_room := "") -> int:
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
	var room := in_room if in_room != "" and world.rooms_built.has(in_room) else str(world.rng.pick(rooms))
	var r: Dictionary = world.pack.rooms[room]
	var uid := world.next_uid()
	world.collectibles.append({"uid": uid, "type": type, "room": room,
		"x": world.rng.randi_range(0, int(r["w"]) - 1), "y": world.rng.randi_range(0, int(r["h"]) - 1),
		"expires_at": world.now + _ttl_s(world)})
	world.emit("collectible_spawned", {"uid": uid, "kind": type, "room": room})
	return uid


## How long a new drop lies about: `collectible_ttl_min`, longer while a well-kept pet
## guards the house (see `PetSystem.guard_factor`).
static func _ttl_s(world: World) -> int:
	var s := int(world.pack.cfg("collectible_ttl_min")) * 60
	if not world.pets.is_empty():
		s = int(float(s) * PetSystem.guard_factor(world))
	return s


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


## Settles a finished pick-up. Kept (`keeps`): it goes into the box. Otherwise the first of
## each type goes into the collection for free and duplicates pay their value. A collectible
## that has already gone is ignored.
static func collect(world: World, p: Person, uid: int) -> void:
	var c := find(world, uid)
	if c.is_empty():
		return
	world.collectibles.erase(c)
	settle(world, p, c)


## Settles collectible `c`, already off the ground (picked up, or carried to where it is
## kept: see `CarrySystem`). With `stock` (a stock id) it goes into the larder instead of
## the box.
static func settle(world: World, p: Person, c: Dictionary) -> void:
	if c.is_empty():
		return
	var uid := int(c.get("uid", -1))
	if c.has("story"):
		StorySystem.found(world, p, c)
		return
	var type := str(c["type"])
	if not world.pack.collectibles.has(type):
		return
	var value := int(world.pack.collectibles[type]["value"])
	var first := int(world.collection.get(type, 0)) == 0
	world.stats["collected"] = int(world.stats["collected"]) + 1
	world.collection[type] = int(world.collection.get(type, 0)) + 1
	var stock := str(world.pack.collectibles[type].get("stock", ""))
	if stock != "":
		world.stock[stock] = int(world.stock.get(stock, 0)) + 1
		world.emit("collected", {"uid": uid, "kind": type, "value": 0, "first": first, "person": p.uid, "stocked": stock})
		return
	if keeps(world.pack):
		world.box[type] = int(world.box.get(type, 0)) + 1
		world.emit("collected", {"uid": uid, "kind": type, "value": 0, "first": first, "person": p.uid, "kept": true})
		return
	if first:
		value = 0
	else:
		EconomySystem.earn(world, value, "collect", p.uid)
	world.emit("collected", {"uid": uid, "kind": type, "value": value, "first": first, "person": p.uid})


## True when the pack keeps what is picked up (`collect_keep`).
static func keeps(pack: Pack) -> bool:
	return bool(pack.cfg("collect_keep"))


## How many of `kind` in the box could be sold: all but one (none of a keepsake).
static func extras(world: World, kind: String) -> int:
	if bool(world.pack.collectibles.get(kind, {}).get("keepsake", true)):
		return 0
	return maxi(0, int(world.box.get(kind, 0)) - 1)


## What all the extras in the box would fetch now.
static func extras_value(world: World) -> int:
	var total := 0
	for kind in world.box:
		total += extras(world, str(kind)) * int(world.pack.collectibles.get(kind, {}).get("value", 0))
	return total


## Player command {kind, all}: sells extras from the box at their `value`, always keeping one
## of each kind. With `kind`: one of that kind, or every extra of it with `all`; without
## `kind`, every extra in the box.
static func sell(world: World, cmd: Dictionary) -> Dictionary:
	if not keeps(world.pack):
		return Commands.fail("no_box")
	var kinds: Array = world.box.keys()
	var all := true
	if cmd.has("kind"):
		var kind := str(cmd["kind"])
		if not world.pack.collectibles.has(kind):
			return Commands.fail("no_such_thing")
		if bool(world.pack.collectibles[kind]["keepsake"]):
			return Commands.fail("keepsake")
		kinds = [kind]
		all = bool(cmd.get("all", false))
	var count := 0
	var amount := 0
	for kind in kinds:
		var n := extras(world, str(kind))
		if not all:
			n = mini(n, 1)
		if n <= 0:
			continue
		world.box[kind] = int(world.box[kind]) - n
		count += n
		amount += n * int(world.pack.collectibles[kind]["value"])
	if count == 0:
		return Commands.fail("nothing_to_sell")
	EconomySystem.earn(world, amount, "collect")
	world.emit("collectibles_sold", {"kind": str(cmd.get("kind", "")), "count": count, "amount": amount})
	return Commands.success({"count": count, "amount": amount})


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
