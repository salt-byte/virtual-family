class_name HouseSystem
extends RefCounted
## Rooms and furniture: where an object may stand, and the commands that build and arrange the house.


## "" when `type` fits at (x, y) in `room`; otherwise why not. `ignore_uid` skips one object
## (the one being moved) in the overlap test.
static func can_place(world: World, type: String, room: String, x: int, y: int, ignore_uid := -1) -> String:
	var t: Dictionary = world.pack.object_types.get(type, {})
	if t.is_empty():
		return "no_object_type"
	var r: Dictionary = world.pack.rooms.get(room, {})
	if r.is_empty():
		return "no_room"
	if not world.rooms_built.has(room):
		return "room_not_built"
	if bool(t["outdoor"]) != bool(r["outdoor"]):
		return "wrong_area"
	var w := int(t["w"])
	var h := int(t["h"])
	if x < 0 or y < 0 or x + w > int(r["w"]) or y + h > int(r["h"]):
		return "out_of_bounds"
	for o in world.objects:
		if int(o["uid"]) == ignore_uid or str(o["room"]) != room:
			continue
		var ot: Dictionary = world.pack.object_types[o["type"]]
		if x < int(o["x"]) + int(ot["w"]) and int(o["x"]) < x + w \
				and y < int(o["y"]) + int(ot["h"]) and int(o["y"]) < y + h:
			return "overlap"
	return ""


static func place(world: World, cmd: Dictionary) -> Dictionary:
	var type := str(cmd.get("object_type", ""))
	var why := can_place(world, type, str(cmd.get("room", "")), int(cmd.get("x", 0)), int(cmd.get("y", 0)))
	if why != "":
		return Commands.fail(why)
	if not EconomySystem.spend(world, int(world.pack.object_types[type]["price"])):
		return Commands.fail("no_money")
	var uid := world.add_object(type, str(cmd["room"]), int(cmd["x"]), int(cmd["y"]))
	return Commands.success({"uid": uid})


static func move(world: World, cmd: Dictionary) -> Dictionary:
	var uid := int(cmd.get("object", -1))
	var o := world.object(uid)
	if o.is_empty():
		return Commands.fail("no_object")
	var room := str(cmd.get("room", ""))
	var x := int(cmd.get("x", 0))
	var y := int(cmd.get("y", 0))
	var why := can_place(world, str(o["type"]), room, x, y, uid)
	if why != "":
		return Commands.fail(why)
	_release_users(world, uid)
	o["room"] = room
	o["x"] = x
	o["y"] = y
	return Commands.success()


static func sell(world: World, cmd: Dictionary) -> Dictionary:
	var uid := int(cmd.get("object", -1))
	var o := world.object(uid)
	if o.is_empty():
		return Commands.fail("no_object")
	_release_users(world, uid)
	var price := int(world.pack.object_types[o["type"]]["price"])
	world.objects.erase(o)
	EconomySystem.earn(world, int(price * float(world.pack.cfg("sell_back_ratio"))), "sell")
	return Commands.success()


static func build_room(world: World, cmd: Dictionary) -> Dictionary:
	var id := str(cmd.get("room", ""))
	if not world.pack.rooms.has(id):
		return Commands.fail("no_room")
	if world.rooms_built.has(id):
		return Commands.fail("already_built")
	if not EconomySystem.spend(world, int(world.pack.rooms[id]["build_cost"])):
		return Commands.fail("no_money")
	world.rooms_built.append(id)
	return Commands.success()


static func _release_users(world: World, object_uid: int) -> void:
	for p in world.people:
		if p.alive and not p.current.is_empty() and int(p.current.get("object_uid", -1)) == object_uid:
			AutonomySystem.cancel(world, p)
