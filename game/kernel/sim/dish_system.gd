class_name DishSystem
extends RefCounted
## Cooked food as a thing in the house (only with a dishes.json). An action that `serves` a
## dish puts it on the first object of the dish's `on` types (in that order); actions that
## `eats` it send people over to take a portion each. When the last portion is gone (or the
## dish was left out for `ttl_hours`), what is left becomes a mess of its `leaves` type on
## that spot. A dish is "claimed" by everyone currently going for it; it has room for as many
## eaters as it has portions left.
##
## world.dishes: {uid, type, object_uid, room, x, y, portions, expires_at (0: never)}.


static func enabled(pack: Pack) -> bool:
	return not pack.dishes.is_empty()


## Dishes left out too long go to waste.
static func step(world: World, _dt: float) -> void:
	if world.dishes.is_empty():
		return
	var i := 0
	while i < world.dishes.size():
		var d: Dictionary = world.dishes[i]
		if int(d.expires_at) > 0 and world.now >= int(d.expires_at):
			_clear(world, i, "wasted")
		else:
			i += 1


## How many dishes of `type` are out now.
static func count(world: World, type: String) -> int:
	var n := 0
	for d in world.dishes:
		if d.type == type:
			n += 1
	return n


## True when another dish of `type` may be served (fewer than its `max_out` are out).
static func may_serve(world: World, type: String) -> bool:
	var dt: Dictionary = world.pack.dishes.get(type, {})
	return not dt.is_empty() and count(world, type) < int(dt.get("max_out", 1))


## Puts a fresh dish of `type` on the first object of its `on` types (in that order: the
## table before the stove). Returns its uid, or -1 when the type is unknown or the house has
## none of those objects.
static func serve(world: World, type: String) -> int:
	var dt: Dictionary = world.pack.dishes.get(type, {})
	if dt.is_empty():
		return -1
	var spot := {}
	for t in dt["on"]:
		for o in world.objects:
			if o.type == t:
				spot = o
				break
		if not spot.is_empty():
			break
	if spot.is_empty():
		return -1
	var uid := world.next_uid()
	var ttl := float(dt.get("ttl_hours", 0))
	world.dishes.append({"uid": uid, "type": type, "object_uid": int(spot.uid), "room": str(spot.room),
		"x": int(spot.x), "y": int(spot.y), "portions": int(dt["portions"]),
		"expires_at": world.now + int(ttl * 3600.0) if ttl > 0.0 else 0})
	world.emit("dish_served", {"uid": uid, "kind": type, "object": int(spot.uid)})
	return uid


## The dish with this uid, or {} when missing.
static func find(world: World, uid: int) -> Dictionary:
	for d in world.dishes:
		if d.uid == uid:
			return d
	return {}


## First dish of one of `types` (stable order) with a portion nobody but `p` is going for.
static func first_free(world: World, types: Array, p: Person) -> int:
	for d in world.dishes:
		if not types.has(d.type):
			continue
		var others := 0
		for q in world.people:
			if q != p and q.alive and not q.current.is_empty() and int(q.current.get("target_uid", -1)) == int(d.uid):
				others += 1
		if others < int(d.portions):
			return d.uid
	return -1


## Takes one portion; the last one leaves the empty bowls behind. Unknown uids are ignored.
static func eat(world: World, uid: int) -> void:
	for i in world.dishes.size():
		var d: Dictionary = world.dishes[i]
		if int(d.uid) != uid:
			continue
		d.portions = int(d.portions) - 1
		if int(d.portions) <= 0:
			_clear(world, i, "eaten")
		return


static func _clear(world: World, i: int, how: String) -> void:
	var d: Dictionary = world.dishes[i]
	world.dishes.remove_at(i)
	world.emit("dish_finished", {"uid": int(d.uid), "kind": str(d.type), "how": how})
	var leaves := str(world.pack.dishes.get(d.type, {}).get("leaves", ""))
	if leaves != "" and world.rooms_built.has(str(d.room)):
		MessSystem.spawn(world, leaves, str(d.room), Vector2i(int(d.x), int(d.y)))
