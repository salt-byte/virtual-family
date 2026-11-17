class_name Commands
extends RefCounted
## Player commands: the only way the view layer acts on the sim. Every handler is
## `Callable(world, cmd) -> {ok: bool, error: String, ...}`; later tasks register more here.

## Seconds after an action ends during which it can still be praised or scolded.
const JUDGE_WINDOW_S := 60
const HABIT_MIN := 0.25
const HABIT_MAX := 3.0

static var handlers: Dictionary = {
	"drag": Commands._drag,
	"praise": Commands._praise,
	"scold": Commands._scold,
}


static func fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func success(extra := {}) -> Dictionary:
	var r := {"ok": true, "error": ""}
	r.merge(extra)
	return r


static func _drag(world: World, cmd: Dictionary) -> Dictionary:
	var p := world.person(int(cmd.get("person", -1)))
	if p == null:
		return fail("no_person")
	var object_uid := int(cmd.get("object", -1))
	var o := world.object(object_uid)
	if o.is_empty():
		return fail("no_object")
	var action_id := str(cmd.get("action", ""))
	if action_id == "":
		var first_reason := "no_action"
		var first := true
		for id in world.pack.actions:
			if str(world.pack.actions[id]["object"]) != str(o["type"]):
				continue
			var why := AutonomySystem.can_do(world, p, id, object_uid)
			if why == "":
				action_id = id
				break
			if first:
				first_reason = why
				first = false
		if action_id == "":
			return fail(first_reason)
	var reason := AutonomySystem.can_do(world, p, action_id, object_uid)
	if reason != "":
		return fail(reason)
	AutonomySystem.start(world, p, action_id, object_uid)
	return success({"action": action_id})


static func _praise(world: World, cmd: Dictionary) -> Dictionary:
	return _judge(world, cmd, true)


static func _scold(world: World, cmd: Dictionary) -> Dictionary:
	return _judge(world, cmd, false)


static func _judge(world: World, cmd: Dictionary, praise: bool) -> Dictionary:
	var p := world.person(int(cmd.get("person", -1)))
	if p == null:
		return fail("no_person")
	if not p.alive:
		return fail("dead")
	var id := ""
	if not p.current.is_empty():
		id = str(p.current["action"])
	elif p.last_action != "" and world.now - p.last_action_t <= JUDGE_WINDOW_S:
		id = p.last_action
	if id == "":
		return fail("nothing_to_judge")
	if not bool(world.pack.actions[id].get("praiseable", true)):
		return fail("not_praiseable")
	var need := str(world.pack.cfg("praise_need"))
	if praise:
		var window_s := int(world.pack.cfg("praise_window_min")) * 60
		p.praise_times = p.praise_times.filter(func(t): return world.now - int(t) <= window_s)
		if p.praise_times.size() >= int(world.pack.cfg("praise_annoy_count")):
			return fail("annoyed")
		p.praise_times.append(world.now)
		if need != "" and p.needs.has(need):
			p.needs[need] = clampf(float(p.needs[need]) + float(world.pack.cfg("praise_gain")), 0.0, 100.0)
	var factor := 1.25 if praise else 0.8
	p.habits[id] = clampf(float(p.habits.get(id, 1.0)) * factor, HABIT_MIN, HABIT_MAX)
	return success({"action": id})
