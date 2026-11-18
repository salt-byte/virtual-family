class_name MessSystem
extends RefCounted
## Mess in the house: random spawns, a per-step penalty on everyone alive, and cleaning.
## A mess is "claimed" while a living person's current action targets it.


static func step(world: World, dt: float) -> void:
	_apply_penalties(world, dt)
	for id in world.pack.mess_types:
		var per_step := float(world.pack.mess_types[id].get("spawn_per_day", 0)) / 1440.0 * (dt / 60.0)
		# A type that never appears by itself (it comes from something else) draws nothing.
		if per_step > 0.0 and world.rng.chance(per_step):
			spawn(world, str(id))


## Adds one mess of `type` and returns its uid, or -1 when the type is unknown or no suitable
## room exists. `room` "" picks a random built room of the matching kind (outdoor or indoor),
## never a place `outside` the house. `at` (inside `room`) puts it on that cell instead of a
## random one.
static func spawn(world: World, type: String, room := "", at := Vector2i(-1, -1)) -> int:
	var mt: Dictionary = world.pack.mess_types.get(type, {})
	if mt.is_empty():
		return -1
	var outdoor := bool(mt.get("outdoor", false))
	if room == "" or not world.rooms_built.has(room):
		var ok: Array = world.rooms_built.filter(func(r): return bool(world.pack.rooms[r]["outdoor"]) == outdoor \
			and not bool(world.pack.rooms[r]["outside"]))
		if ok.is_empty():
			return -1
		room = str(world.rng.pick(ok))
	var r: Dictionary = world.pack.rooms[room]
	var uid := world.next_uid()
	if at.x < 0 or at.y < 0 or at.x >= int(r["w"]) or at.y >= int(r["h"]):
		at = Vector2i(world.rng.randi_range(0, int(r["w"]) - 1), world.rng.randi_range(0, int(r["h"]) - 1))
	world.messes.append({"uid": uid, "type": type, "room": room, "x": at.x, "y": at.y})
	world.emit("mess_spawned", {"uid": uid, "kind": type, "room": room})
	return uid


## Removes a mess and counts it. Unknown uids are ignored. `by` is the uid of whoever
## cleaned it (-1: nobody in particular). The last mess gone pays the pack's `clean_reward`,
## at most once per local day.
static func clean(world: World, uid: int, by := -1) -> void:
	for i in world.messes.size():
		if world.messes[i].uid != uid:
			continue
		world.messes.remove_at(i)
		world.stats["mess_cleaned"] = int(world.stats["mess_cleaned"]) + 1
		world.emit("mess_cleaned", {"uid": uid})
		if world.messes.is_empty():
			world.stats["all_clean"] = int(world.stats["all_clean"]) + 1
			_reward(world, by)
		return


## The pay for a house made clean: `clean_reward.amount` coins, once per local day.
static func _reward(world: World, by: int) -> void:
	var amount := int(world.pack.cfg("clean_reward").get("amount", 0))
	if amount <= 0:
		return
	var day := floori(float(world.now + world.utc_offset) / 86400.0)
	if day == world.clean_paid_day:
		return
	world.clean_paid_day = day
	EconomySystem.earn(world, amount, "clean")
	world.emit("clean_reward", {"amount": amount, "person": by})


## The mess with this uid, or {} when missing.
static func find(world: World, uid: int) -> Dictionary:
	for m in world.messes:
		if m.uid == uid:
			return m
	return {}


## True when a living person other than `except` is on their way to / cleaning this mess.
static func claimed_by_other(world: World, uid: int, except: Person) -> bool:
	return AutonomySystem.target_claimed(world, uid, "mess", except)


## First mess of `type` (stable order) that nobody but `p` has claimed, else -1.
static func first_free(world: World, type: String, p: Person) -> int:
	for m in world.messes:
		if m.type == type and not claimed_by_other(world, m.uid, p):
			return m.uid
	return -1


static func _apply_penalties(world: World, dt: float) -> void:
	var floor_v := float(world.pack.cfg("offline_need_floor"))
	for m in world.messes:
		var penalty: Dictionary = world.pack.mess_types[m.type].get("penalty", {})
		for p in world.people:
			if not p.alive:
				continue
			for nid in penalty:
				if p.needs.has(nid):
					p.needs[nid] = clampf(float(p.needs[nid]) - absf(float(penalty[nid])) * dt / 3600.0, 0.0, 100.0)
					if world.offline:
						p.needs[nid] = maxf(float(p.needs[nid]), floor_v)
