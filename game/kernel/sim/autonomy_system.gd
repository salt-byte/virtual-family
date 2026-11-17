class_name AutonomySystem
extends RefCounted
## The action table in motion: idle people score what they can do and pick one; running
## actions pay out their need effects step by step. Commands (drag, chores, illness) reuse
## `can_do` / `start` / `cancel`. Object occupancy is derived from `Person.current`, so a
## cancelled, finished or dead person frees their object by simply no longer holding it.


static func step(world: World, dt: float) -> void:
	for p in world.people:
		if not p.alive:
			continue
		if not p.current.is_empty():
			_progress(world, p, dt)
		elif p.stage(world.pack) != "baby":
			_choose(world, p)


## Everything `p` could start right now, scored. Order is stable (pack action order).
static func candidates(world: World, p: Person) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in world.pack.actions:
		if can_do(world, p, id, -1) != "":
			continue
		var s := _score(world, p, world.pack.actions[id])
		if s > 0.0:
			var a: Dictionary = world.pack.actions[id]
			var target := MessSystem.first_free(world, str(a["cleans"]), p) if str(a["cleans"]) != "" else -1
			out.append({"action": id, "object_uid": _free_object(world, p, a, -1), "target_uid": target, "score": s})
	return out


## "" when `p` can start the action now, else the first failing reason.
## `object_uid` -1 means "any free object of the action's type".
static func can_do(world: World, p: Person, action_id: String, object_uid: int) -> String:
	if not p.alive:
		return "dead"
	var a: Dictionary = world.pack.actions.get(action_id, {})
	if a.is_empty():
		return "no_action"
	if not (p.stage(world.pack) in a["stages"]):
		return "stage"
	var type := str(a["object"])
	if type != "":
		if object_uid >= 0:
			if str(world.object(object_uid).get("type", "")) != type:
				return "no_object"
		elif not world.objects.any(func(o): return o.type == type):
			return "no_object"
		if _free_object(world, p, a, object_uid) < 0:
			return "busy"
	var work: Dictionary = a["work"]
	if not work.is_empty() and str(work.get("track", "")) != p.track:
		return "wrong_track"
	if not _requires_ok(p, a["requires"]):
		return "requires"
	if str(a["cleans"]) != "" and MessSystem.first_free(world, str(a["cleans"]), p) < 0:
		return "no_target"
	if bool(a["picks"]):
		return "no_target"  # a later task looks for a collectible here
	for item in a["consumes"]:
		if int(world.stock.get(item, 0)) < int(a["consumes"][item]):
			return "no_stock"
	return ""


## Starts an action (no checks: callers use `can_do` first). Replaces whatever `p` was doing.
static func start(world: World, p: Person, action_id: String, object_uid: int, target_uid := -1) -> void:
	cancel(world, p)
	var a: Dictionary = world.pack.actions[action_id]
	var uid := _free_object(world, p, a, object_uid) if str(a["object"]) != "" else -1
	for item in a["consumes"]:
		world.stock[item] = int(world.stock.get(item, 0)) - int(a["consumes"][item])
	p.current = {"action": action_id, "object_uid": uid, "target_uid": target_uid,
		"remaining_s": int(a["duration_min"]) * 60}
	world.emit("action_started", {"uid": p.uid, "action": action_id, "object_uid": uid})


## Drops the current action without any payout; the object becomes free.
static func cancel(world: World, p: Person) -> void:
	if p.current.is_empty():
		return
	world.emit("action_cancelled", {"uid": p.uid, "action": p.current["action"]})
	p.current = {}


static func _progress(world: World, p: Person, dt: float) -> void:
	var a: Dictionary = world.pack.actions[p.current["action"]]
	var frac := dt / (float(a["duration_min"]) * 60.0)
	for n in a["needs"]:
		if p.needs.has(n):
			p.needs[n] = clampf(float(p.needs[n]) + float(a["needs"][n]) * frac, 0.0, 100.0)
	p.current["remaining_s"] = int(p.current["remaining_s"]) - int(dt)
	if int(p.current["remaining_s"]) <= 0:
		_finish(world, p)


## Runs once when an action's time is up.
static func _finish(world: World, p: Person) -> void:
	var id := str(p.current["action"])
	# Later tasks settle `picks` here, before `current` is cleared.
	var action: Dictionary = world.pack.actions[id]
	if str(action["cleans"]) != "":
		MessSystem.clean(world, int(p.current.get("target_uid", -1)))
	var mess: Dictionary = action["mess"]
	if not mess.is_empty() and world.rng.chance(float(mess.get("chance", 0.0))):
		var room := str(world.object(int(p.current.get("object_uid", -1))).get("room", ""))
		MessSystem.spawn(world, str(mess["type"]), room)
	if not action["work"].is_empty():
		EconomySystem.on_work_finished(world, p, int(action["duration_min"]))
	p.current = {}
	p.last_action = id
	p.last_action_t = world.now
	world.emit("action_finished", {"uid": p.uid, "action": id})


static func _choose(world: World, p: Person) -> void:
	var c := candidates(world, p)
	if c.is_empty():
		return
	var idx: Array = range(c.size())
	idx.sort_custom(func(i, j): return c[i].score > c[j].score or (c[i].score == c[j].score and i < j))
	var top: Array = []
	var weights: Array = []
	for i in idx.slice(0, 3):
		top.append(c[i])
		weights.append(c[i].score)
	var pick: Dictionary = world.rng.weighted_pick(top, weights)
	start(world, p, pick.action, pick.object_uid, int(pick.get("target_uid", -1)))


static func _score(world: World, p: Person, a: Dictionary) -> float:
	var gain := 0.0
	for n in a["needs"]:
		if p.needs.has(n):
			gain += minf(maxf(float(a["needs"][n]), 0.0), 100.0 - float(p.needs[n])) * (100.0 - float(p.needs[n])) / 100.0
	var score := (float(a.get("base", 0)) + gain) * float(p.habits.get(a["id"], 1.0))
	for t in a.get("tags", []):
		if t in p.likes:
			score *= 1.5
		if t in p.dislikes:
			score *= 0.5
	var hours: Array = a.get("hours", [])
	if not hours.is_empty() and not _in_hours(world.local_hour(), hours):
		score *= 0.1
	return score


## `[from, to)` in local hours; from > to wraps past midnight.
static func _in_hours(h: float, hours: Array) -> bool:
	var from := float(hours[0])
	var to := float(hours[1])
	if from <= to:
		return h >= from and h < to
	return h >= from or h < to


static func _requires_ok(p: Person, req: Dictionary) -> bool:
	if req.has("sick") and bool(req["sick"]) != (p.illness != ""):
		return false
	if req.has("illness") and p.illness != str(req["illness"]):
		return false
	var below: Dictionary = req.get("need_below", {})
	for n in below:
		if float(p.needs.get(n, 100.0)) >= float(below[n]):
			return false
	return true


## uid of an object of the action's type that is free for `p` (`object_uid` >= 0 asks for that
## exact one), else -1. An object `p` is already using does not count as occupied for them.
static func _free_object(world: World, p: Person, a: Dictionary, object_uid: int) -> int:
	for o in world.objects:
		if o.type != a["object"] or (object_uid >= 0 and o.uid != object_uid):
			continue
		if not _occupied(world, o.uid, p):
			return o.uid
	return -1


static func _occupied(world: World, uid: int, except: Person) -> bool:
	for q in world.people:
		if q != except and q.alive and not q.current.is_empty() and int(q.current.get("object_uid", -1)) == uid:
			return true
	return false
