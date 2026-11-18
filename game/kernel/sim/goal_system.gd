class_name GoalSystem
extends RefCounted
## One-off rewards: every step, each goal not yet done is checked in pack order.


static func step(world: World, _dt: float) -> void:
	if world.phase != "living":
		return
	for id in world.pack.goals:
		if world.goals_done.has(id):
			continue
		var g: Dictionary = world.pack.goals[id]
		if not is_met(world, g):
			continue
		var reward := int(g["reward"])
		EconomySystem.earn(world, reward, "goal")
		world.goals_done.append(str(id))
		world.emit("goal_done", {"goal": id, "reward": reward})


## Whether the goal's `when` condition holds right now. Unknown types are never met.
static func is_met(world: World, goal: Dictionary) -> bool:
	var w: Dictionary = goal.get("when", {})
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
			var owned := world.objects.filter(func(o): return not HouseSystem.is_fixed(world, str(o["type"])))
			return owned.size() >= int(w.get("count", 0))
		"room_built":
			return world.rooms_built.has(str(w.get("room", "")))
		"level_reached":
			return world.people.any(func(p: Person): return p.alive and p.level >= int(w.get("level", 0)))
		"collected":
			return int(world.stats["collected"]) >= int(w.get("count", 0))
	return false
