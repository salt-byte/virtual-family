class_name OutingSystem
extends RefCounted
## Going out. An action with an `outing` takes the person away from the house: they walk out
## to where it happens (its `rooms`, normally the gate), are away for its length, and come
## back with one of `outing.returns` ({item, text}; the item may be left out): picked through
## `world.rng` when there are several, the item goes into the inventory and the text (with
## {name} for the person) is the line for the diary. The action's own `needs` pay as usual.
## People pick an outing on their own like any action, a "do" wish can ask for one, and the
## player can send someone (command go_out).
##
## While away nobody can drag, praise, scold or give anything to that person (error
## "requires"; `away` tells a view why).
## Events: outing_back {person, action, item, text}.


static func is_outing(a: Dictionary) -> bool:
	var o = a.get("outing")
	return o is Dictionary and not (o as Dictionary).is_empty()


## True while `p` is away on an outing.
static func away(world: World, p: Person) -> bool:
	if p == null or not p.alive or p.current.is_empty():
		return false
	return is_outing(world.pack.actions.get(str(p.current["action"]), {}))


## Whether the player can send someone to do `a`: an outing, or an action that happens only
## at places outside the house.
static func sendable(pack: Pack, a: Dictionary) -> bool:
	return is_outing(a) or (str(a.get("object", "")) == "" and WeatherSystem.place_kind(pack, a) == 2 \
		and (a.get("work", {}) as Dictionary).is_empty())


## What `p` could be sent out to do, for a button list: [{action, label, outing, why}] in
## pack order, over the actions of `p`'s stage that `sendable` accepts; `why` is "" when they
## can go now, else the reason `go_out` would give.
static func options(world: World, p: Person) -> Array:
	var out: Array = []
	if p == null:
		return out
	var stage := p.stage(world.pack)
	for id in world.pack.actions:
		var a: Dictionary = world.pack.actions[id]
		if not sendable(world.pack, a) or not (a["stages"] as Array).has(stage):
			continue
		if not FestivalSystem.allows(world, a["festivals"]):
			continue  # a festival's outing is only offered while the festival is on
		out.append({"action": str(id), "label": str(a["label"]), "outing": is_outing(a), "why": _why(world, p, str(id))})
	return out


## "" when `p` can be sent to do `action_id` now, else why not: no_person / dead /
## no_action / requires (away already, or outside the action's `hours`) or a reason of
## `AutonomySystem.can_do` (a festival's outing out of its festival is "requires" too).
static func _why(world: World, p: Person, action_id: String) -> String:
	if p == null:
		return "no_person"
	if not p.alive:
		return "dead"
	if away(world, p):
		return "requires"
	var a: Dictionary = world.pack.actions.get(action_id, {})
	if a.is_empty() or not sendable(world.pack, a):
		return "no_action"
	var hours: Array = a["hours"]
	if not hours.is_empty() and not AutonomySystem._in_hours(world.local_hour(), hours):
		return "requires"
	return AutonomySystem.can_do(world, p, action_id, -1)


## Player command {person, action}: `p` drops what they are doing and goes.
static func go_out(world: World, cmd: Dictionary) -> Dictionary:
	var p := world.person(int(cmd.get("person", -1)))
	var id := str(cmd.get("action", ""))
	var why := _why(world, p, id)
	if why != "":
		return Commands.fail(why)
	AutonomySystem.start(world, p, id, -1)
	return Commands.success({"action": id})


## `p` is back from the outing `action_id`: what they bring is picked and kept.
static func come_back(world: World, p: Person, action_id: String) -> void:
	var returns: Array = world.pack.actions[action_id]["outing"].get("returns", [])
	if returns.is_empty():
		return
	var r: Dictionary = returns[0] if returns.size() == 1 else world.rng.pick(returns)
	var item := str(r.get("item", ""))
	if item != "":
		world.inventory[item] = int(world.inventory.get(item, 0)) + 1
	world.emit("outing_back", {"person": p.uid, "action": action_id, "item": item, "text": str(r.get("text", ""))})
