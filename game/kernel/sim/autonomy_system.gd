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


## The constant parts of one action, read once per pack so the hot path does no
## dictionary lookups of constants (see `_table`).
class Info:
	var id := ""
	var stages: Array = []
	var object := ""
	var has_work := false
	var track := ""
	var requires: Dictionary = {}
	var has_requires := false
	var kind := ""
	var consumes: Dictionary = {}
	var has_consumes := false
	var base := 0.0
	var need_ids: Array[String] = []
	## max(effect, 0) of each need in `need_ids`, as `_score` uses it
	var need_gains: Array[float] = []
	var tags: Array = []
	var has_hours := false
	var hours: Array = []
	## `hours` as floats, and whether the window wraps past midnight
	var hour_from := 0.0
	var hour_to := 0.0
	var hours_wrap := false
	## slow with an `hours` window: it ends as soon as the hour is outside the window
	var slow_in_hours := false
	## the rooms an action without an object happens in ([]: anywhere)
	var rooms: Array = []
	var has_rooms := false


## The pack's actions as `Info`, in pack order, built on first use and kept on the pack
## (a pack's content does not change once worlds use it).
static func _table(pack: Pack) -> Array:
	if pack.autonomy_table.size() == pack.actions.size() and not pack.autonomy_table.is_empty():
		return pack.autonomy_table
	var out: Array = []
	for id in pack.actions:
		var a: Dictionary = pack.actions[id]
		var i := Info.new()
		i.id = str(id)
		i.stages = a["stages"]
		i.object = str(a["object"])
		var work: Dictionary = a["work"]
		i.has_work = not work.is_empty()
		i.track = str(work.get("track", ""))
		i.requires = a["requires"]
		i.has_requires = not i.requires.is_empty()
		i.kind = target_kind(a)
		i.consumes = a["consumes"]
		i.has_consumes = not i.consumes.is_empty()
		i.base = float(a.get("base", 0))
		for n in a["needs"]:
			i.need_ids.append(str(n))
			i.need_gains.append(maxf(float(a["needs"][n]), 0.0))
		i.tags = a.get("tags", [])
		i.hours = a.get("hours", [])
		i.has_hours = not i.hours.is_empty()
		if i.has_hours:
			i.hour_from = float(i.hours[0])
			i.hour_to = float(i.hours[1])
			i.hours_wrap = i.hour_from > i.hour_to
		i.slow_in_hours = bool(a.get("slow", false)) and i.has_hours
		i.rooms = a.get("rooms", [])
		i.has_rooms = not i.rooms.is_empty()
		out.append(i)
	pack.autonomy_table = out
	pack.autonomy_by_stage = {}
	return out


## `_table` cut down to the actions open to `stage`, in pack order.
static func _stage_table(pack: Pack, stage: String) -> Array:
	var all := _table(pack)
	if not pack.autonomy_by_stage.has(stage):
		pack.autonomy_by_stage[stage] = all.filter(func(i: Info): return stage in i.stages)
	return pack.autonomy_by_stage[stage]


## Everything `p` could start right now, scored. Order is stable (pack action order).
## Gives exactly what `can_do(..., -1)` and `_score` give, action by action, except that a
## slow action with an `hours` window is not chosen outside that window (it would end at
## the very next step, see `_progress`).
## `pool` > 0: only the `pool` best, best first, ties in pack order (what `_choose` needs:
## the same entries a stable sort of the full list by score would put first).
static func candidates(world: World, p: Person, pool := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not p.alive:
		return out
	# On the fast action clock people choose often, so this is the hot path: the stage, hour
	# and settings are worked out once, every constant of an action comes from `_table`, and
	# the free object per type is looked up once.
	var pack := world.pack
	var stage := p.stage(pack)
	var hour := world.local_hour()
	var damp := _repeat_damping(p, int(pack.cfg("repeat_memory")), float(pack.cfg("repeat_factor")))
	var needs := p.needs
	var habits := p.habits
	var likes := p.likes
	var dislikes := p.dislikes
	var built := {}
	for r in world.rooms_built:
		built[r] = true
	var free := {}  # object type -> first object of that type free for `p` (-1: none)
	var users := {}  # object uid -> people other than `p` using it (filled on first need)
	# The cheap yes/no tests come first; only what passes them is scored.
	for i: Info in _stage_table(pack, stage):
		if i.slow_in_hours and not _in_hours(hour, i.hours):
			continue
		var uid := -1
		if i.object != "":
			if not free.has(i.object):
				if users.is_empty():
					users[-1] = 0
					for q in world.people:
						if q != p and q.alive and not q.current.is_empty():
							var ou := int(q.current.get("object_uid", -1))
							users[ou] = int(users.get(ou, 0)) + 1
				free[i.object] = _first_unoccupied(world, i.object, users)
			uid = free[i.object]
			if uid < 0:
				continue
		elif i.has_rooms:
			var somewhere := false
			for r in i.rooms:
				if built.has(r):
					somewhere = true
					break
			if not somewhere:
				continue
		if i.has_work and i.track != p.track:
			continue
		if i.has_requires and not _requires_ok(p, i.requires):
			continue
		# The score: `_score`'s arithmetic in the same order, written out here.
		var gain := 0.0
		for k in i.need_ids.size():
			var nv = needs.get(i.need_ids[k])
			if nv != null:
				var room := 100.0 - float(nv)
				gain += minf(i.need_gains[k], room) * room / 100.0
		var s := (i.base + gain) * float(habits.get(i.id, 1.0))
		for t in i.tags:
			if t in likes:
				s *= 1.5
			if t in dislikes:
				s *= 0.5
		if i.has_hours:
			if i.hours_wrap:
				if not (hour >= i.hour_from or hour < i.hour_to):
					s *= 0.1
			elif not (hour >= i.hour_from and hour < i.hour_to):
				s *= 0.1
		var dv = damp.get(i.id)
		if dv != null:
			s *= float(dv)
		if s <= 0.0:
			continue
		var target := -1
		if i.kind != "":
			target = _first_free_target(world, pack.actions[i.id], p)
			if target < 0:
				continue
		if i.has_consumes:
			var ok := true
			for item in i.consumes:
				if int(world.stock.get(item, 0)) < int(i.consumes[item]):
					ok = false
					break
			if not ok:
				continue
		if pool <= 0:
			out.append({"action": i.id, "object_uid": uid, "target_uid": target, "score": s})
			continue
		if out.size() == pool and s <= float(out[pool - 1].score):
			continue
		var j := out.size()
		while j > 0 and s > float(out[j - 1].score):
			j -= 1
		out.insert(j, {"action": i.id, "object_uid": uid, "target_uid": target, "score": s})
		if out.size() > pool:
			out.pop_back()
	return out


## `_free_object` for any object of `type`, with the other users per object counted once.
static func _first_unoccupied(world: World, type: String, users: Dictionary) -> int:
	var capacity := int(world.pack.object_types.get(type, {}).get("capacity", 1))
	for o in world.objects:
		if o.type == type and int(users.get(o.uid, 0)) < capacity:
			return o.uid
	return -1


## action id -> the factor `_score` damps a recent repeat by: with a memory of 1 the last
## action gets `rf`; otherwise an action first found at position k (0 = most recent) of the
## last `memory` gets rf^((memory - k) / memory).
static func _repeat_damping(p: Person, memory: int, rf: float) -> Dictionary:
	var out := {}
	if memory == 1:
		out[p.last_action] = rf
		return out
	for k in mini(memory, p.recent_actions.size()):
		var id: String = p.recent_actions[k]
		if not out.has(id):
			out[id] = pow(rf, float(memory - k) / float(memory))
	return out


## True when at least one of `rooms` is built.
static func _any_built(world: World, rooms: Array) -> bool:
	for r in rooms:
		if world.rooms_built.has(r):
			return true
	return false


static func _stock_ok(world: World, a: Dictionary) -> bool:
	for item in a["consumes"]:
		if int(world.stock.get(item, 0)) < int(a["consumes"][item]):
			return false
	return true


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
	elif not (a["rooms"] as Array).is_empty() and not _any_built(world, a["rooms"]):
		return "no_place"
	var work: Dictionary = a["work"]
	if not work.is_empty() and str(work.get("track", "")) != p.track:
		return "wrong_track"
	if not _requires_ok(p, a["requires"]):
		return "requires"
	if target_kind(a) != "" and _first_free_target(world, a, p) < 0:
		return "no_target"
	if not _stock_ok(world, a):
		return "no_stock"
	return ""


## What an action aims at: "mess" (`cleans`), "collectible" (`picks`) or "" (nothing).
## An action has at most one target kind.
static func target_kind(a: Dictionary) -> String:
	if str(a["cleans"]) != "":
		return "mess"
	if bool(a["picks"]):
		return "collectible"
	return ""


## True when a living person other than `except` is going for target `uid` with an action
## of this `kind`.
static func target_claimed(world: World, uid: int, kind: String, except: Person) -> bool:
	for q in world.people:
		if q == except or not q.alive or q.current.is_empty():
			continue
		if int(q.current.get("target_uid", -1)) == uid and target_kind(world.pack.actions[q.current["action"]]) == kind:
			return true
	return false


## Starts an action (no checks: callers use `can_do` first). Replaces whatever `p` was doing.
## Resolves the action's object (any free one when `object_uid` is -1) and, for a cleaning
## or picking action without an explicit `target_uid`, the first unclaimed target.
static func start(world: World, p: Person, action_id: String, object_uid: int, target_uid := -1) -> void:
	cancel(world, p)
	var a: Dictionary = world.pack.actions[action_id]
	if target_uid < 0:
		target_uid = _first_free_target(world, a, p)
	var uid := _free_object(world, p, a, object_uid) if str(a["object"]) != "" else -1
	for item in a["consumes"]:
		world.stock[item] = int(world.stock.get(item, 0)) - int(a["consumes"][item])
	p.current = {"action": action_id, "object_uid": uid, "target_uid": target_uid,
		"remaining_s": duration_s(world, a)}
	var rooms: Array = a.get("rooms", [])
	if not rooms.is_empty() and uid < 0:
		var built := rooms.filter(func(r): return world.rooms_built.has(r))
		if not built.is_empty():
			p.current["room"] = str(world.rng.pick(built))
	world.emit("action_started", {"person": p.uid, "action": action_id, "object": uid, "target": target_uid})


## Real seconds an action takes: `duration_min` minutes divided by the pack's
## `action_speed`, rounded up to whole steps (at least one). `slow` actions (sleep) and a
## speed of 1 keep the full `duration_min`.
static func duration_s(world: World, a: Dictionary) -> int:
	var full := int(a["duration_min"]) * 60
	var speed := float(world.pack.cfg("action_speed"))
	if bool(a.get("slow", false)) or speed == 1.0:
		return full
	var s := ceili(full / speed - 1e-9)
	return maxi(ceili(float(s) / world.step_s), 1) * world.step_s


## Drops the current action without any payout; the object becomes free.
static func cancel(world: World, p: Person) -> void:
	if p.current.is_empty():
		return
	world.emit("action_cancelled", {"person": p.uid, "action": p.current["action"]})
	p.current = {}


## Pays the running action's need effects for `dt` seconds: gains add up to their full
## amount over the action's real duration, costs to the share of `duration_min` it took.
## When the pack speeds actions up, a longer `remaining_s` (from a save written before they
## were sped up) is cut to the action's current length first, so the action finishes within
## that length and pays over it. At speed 1 lengths never changed, and only the last
## `duration_s` seconds of a longer `remaining_s` pay, as always.
static func _progress(world: World, p: Person, dt: float) -> void:
	var a: Dictionary = world.pack.actions[p.current["action"]]
	# A slow action with an `hours` window (sleep) ends as soon as the local hour is outside
	# it: people get up when the night is over, or when the day/night setting flips.
	if bool(a.get("slow", false)) and not (a["hours"] as Array).is_empty() \
			and not _in_hours(world.local_hour(), a["hours"]):
		_finish(world, p)
		return
	var dur := duration_s(world, a)
	var remaining := int(p.current["remaining_s"])
	if remaining > dur and float(world.pack.cfg("action_speed")) != 1.0:
		remaining = dur
		p.current["remaining_s"] = remaining
	var paid := clampf(dt - float(remaining - dur), 0.0, dt)
	var gain_frac := paid / float(dur)
	var cost_frac := paid / (float(a["duration_min"]) * 60.0)
	for n in a["needs"]:
		if p.needs.has(n):
			var v := float(a["needs"][n])
			p.needs[n] = clampf(float(p.needs[n]) + v * (gain_frac if v >= 0.0 else cost_frac), 0.0, 100.0)
	p.current["remaining_s"] = remaining - int(dt)
	if int(p.current["remaining_s"]) <= 0:
		_finish(world, p)


## Runs once when an action's time is up.
static func _finish(world: World, p: Person) -> void:
	var id := str(p.current["action"])
	var action: Dictionary = world.pack.actions[id]
	if str(action["cleans"]) != "":
		MessSystem.clean(world, int(p.current.get("target_uid", -1)))
	if bool(action["picks"]):
		CollectibleSystem.collect(world, p, int(p.current.get("target_uid", -1)))
	var mess: Dictionary = action["mess"]
	if not mess.is_empty() and world.rng.chance(float(mess.get("chance", 0.0))):
		var room := str(world.object(int(p.current.get("object_uid", -1))).get("room", ""))
		MessSystem.spawn(world, str(mess["type"]), room)
	if not action["work"].is_empty():
		EconomySystem.on_work_finished(world, p, duration_s(world, action) / 60.0)
	p.current = {}
	p.last_action = id
	p.last_action_t = world.now
	p.recent_actions.push_front(id)
	p.recent_actions.resize(mini(p.recent_actions.size(), int(world.pack.cfg("repeat_memory"))))
	world.emit("action_finished", {"person": p.uid, "action": id})


## First unclaimed target for the action's kind (-1 when it has none or none is free).
static func _first_free_target(world: World, a: Dictionary, p: Person) -> int:
	match target_kind(a):
		"mess":
			return MessSystem.first_free(world, str(a["cleans"]), p)
		"collectible":
			return CollectibleSystem.first_free(world, p)
	return -1


static func _choose(world: World, p: Person) -> void:
	# A weighted pick among the best few (`choice_pool`), best first.
	var top: Array = candidates(world, p, int(world.pack.cfg("choice_pool")))
	if top.is_empty():
		return
	var weights: Array = []
	for cand in top:
		weights.append(cand.score)
	var pick: Dictionary = world.rng.weighted_pick(top, weights)
	start(world, p, pick.action, pick.object_uid, int(pick.get("target_uid", -1)))


## `hour` is the local hour (negative: read it from the world).
static func _score(world: World, p: Person, a: Dictionary, hour := -1.0) -> float:
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
	if not hours.is_empty() and not _in_hours(hour if hour >= 0.0 else world.local_hour(), hours):
		score *= 0.1
	var memory := int(world.pack.cfg("repeat_memory"))
	if memory == 1:  # the default: only the last action, exactly as before the memory existed
		if str(a["id"]) == p.last_action:
			score *= float(world.pack.cfg("repeat_factor"))
	else:
		# Found at position k (0 = most recent) of the last `memory` actions: repeat_factor
		# to the power (memory - k) / memory, so older repeats are damped less.
		var k := p.recent_actions.find(a["id"])
		if k >= 0 and k < memory:
			score *= pow(float(world.pack.cfg("repeat_factor")), float(memory - k) / float(memory))
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


## True when the object already has as many other users as its type's `capacity`.
static func _occupied(world: World, uid: int, except: Person) -> bool:
	var users := 0
	for q in world.people:
		if q != except and q.alive and not q.current.is_empty() and int(q.current.get("object_uid", -1)) == uid:
			users += 1
	var o := world.object(uid)
	var capacity := 1
	if not o.is_empty():
		capacity = int(world.pack.object_types.get(o["type"], {}).get("capacity", 1))
	return users >= capacity
