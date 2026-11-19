class_name GoalSystem
extends RefCounted
## One-off rewards: every step, each goal not yet done is checked in pack order.


static func step(world: World, _dt: float) -> void:
	if world.phase != "living":
		return
	var t := _table(world.pack)
	var ids: Array = t[0]
	var types: PackedInt32Array = t[1]
	var args: Array = t[2]
	for k in ids.size():
		var id = ids[k]
		if world.goals_done.has(id):
			continue
		# `is_met`, read from the table
		var met := false
		match types[k]:
			_MESS_CLEARED:
				met = int(world.stats["all_clean"]) >= 1
			_CURED:
				met = int(world.stats["cured"]) >= 1
			_MARRIED:
				met = world.married
			_MONEY:
				met = world.money >= args[k]
			_ROOM:
				met = world.rooms_built.has(args[k])
			_COLLECTED:
				met = int(world.stats["collected"]) >= args[k]
			_OTHER:
				met = is_met(world, world.pack.goals[id])
		if not met:
			continue
		var g: Dictionary = world.pack.goals[id]
		var reward := int(g["reward"])
		EconomySystem.earn(world, reward, "goal")
		world.goals_done.append(str(id))
		world.emit("goal_done", {"goal": id, "reward": reward})


const _NEVER := 0
const _MESS_CLEARED := 1
const _CURED := 2
const _MARRIED := 3
const _MONEY := 4
const _ROOM := 5
const _COLLECTED := 6
const _OTHER := 7  ## worked out by `is_met` itself


## The pack's goals for `step`: [ids in pack order, `_*` type of each, its amount / room /
## count], built once per pack (a pack's goals do not change once worlds use it; rebuilt if
## goals are added or the dictionary is replaced).
static func _table(pack: Pack) -> Array:
	var t := pack.goal_table
	if not t.is_empty() and is_same(t[3], pack.goals) and (t[0] as Array).size() == pack.goals.size():
		return t
	var ids: Array = []
	var types := PackedInt32Array()
	var args: Array = []
	for id in pack.goals:
		ids.append(id)
		var w = pack.goals[id].get("when")
		var type := _NEVER
		var arg: Variant = null
		if w is Dictionary:
			match str(w.get("type", "")):
				"mess_cleared":
					type = _MESS_CLEARED
				"cured":
					type = _CURED
				"married":
					type = _MARRIED
				"money_at_least":
					type = _MONEY
					arg = int(w.get("amount", 0))
				"room_built":
					type = _ROOM
					arg = str(w.get("room", ""))
				"collected":
					type = _COLLECTED
					arg = int(w.get("count", 0))
				"objects_owned", "level_reached":
					type = _OTHER
		types.append(type)
		args.append(arg)
	pack.goal_table = [ids, types, args, pack.goals]
	return pack.goal_table


## Whether the goal's `when` condition holds right now. Unknown types are never met.
static func is_met(world: World, goal: Dictionary) -> bool:
	var w = goal.get("when")  # no `{}` default: this runs for every open goal on every step
	if not w is Dictionary:
		return false
	match str(w.get("type", "")):
		"mess_cleared":
			return int(world.stats["all_clean"]) >= 1
		"cured":
			return int(world.stats["cured"]) >= 1
		"married":
			return world.married
		"money_at_least":
			return world.money >= int(w.get("amount", 0))
		"objects_owned":
			# The furniture that is not fixed (`HouseSystem.is_fixed`).
			return _owned(world) >= int(w.get("count", 0))
		"room_built":
			return world.rooms_built.has(str(w.get("room", "")))
		"level_reached":
			var level := int(w.get("level", 0))
			for p in world.people:
				if p.alive and p.level >= level:
					return true
			return false
		"collected":
			return int(world.stats["collected"]) >= int(w.get("count", 0))
	return false


## How many of the world's objects are not fixed, kept on the world while the objects list is
## the same array with the same size and last uid (objects are only appended with new uids or
## removed), so the open furniture goal costs nothing on most steps.
static func _owned(world: World) -> int:
	var objs := world.objects
	var n := objs.size()
	var last := int(objs[n - 1].uid) if n > 0 else -1
	var c := world._owned_ctx
	if not c.is_empty() and is_same(c[0], objs) and c[1] == n and c[2] == last and is_same(c[3], world.pack.object_types):
		return c[4]
	var types := world.pack.object_types
	var owned := 0
	for o in objs:
		var ot = types.get(o["type"])
		if ot == null or not bool(ot.get("fixed", false)):
			owned += 1
	world._owned_ctx = [objs, n, last, types, owned]
	return owned
