class_name IllnessSystem
extends RefCounted
## Random illness, per-step drain while sick, and cures. Events never name the illness:
## the player must recognise it from the symptom action and pick the matching medicine.


static func step(world: World, dt: float) -> void:
	var pack := world.pack
	var chance := float(pack.cfg("illness_daily_chance")) / 1440.0
	var floor_v := float(pack.cfg("offline_need_floor"))
	for p in world.people:
		if not p.alive:
			continue
		if p.illness == "":
			if p.stage(pack) != "baby" and not pack.illnesses.is_empty() and world.rng.chance(chance):
				infect(world, p, _pick_illness(world))
			continue
		var drain: Dictionary = pack.illnesses[p.illness]["drain"]
		for nid in drain:
			if p.needs.has(nid):
				p.needs[nid] = clampf(float(p.needs[nid]) - absf(float(drain[nid])) * dt / 3600.0, 0.0, 100.0)
		if world.offline:
			for nid in drain:
				if p.needs.has(nid):
					p.needs[nid] = maxf(float(p.needs[nid]), floor_v)


static func _pick_illness(world: World) -> String:
	var ids: Array = world.pack.illnesses.keys()
	var weights: Array = ids.map(func(id): return float(world.pack.illnesses[id]["weight"]))
	return str(world.rng.weighted_pick(ids, weights))


## Makes a living, healthy person ill. Does nothing for the dead or the already sick.
static func infect(world: World, p: Person, illness_id: String) -> void:
	if not p.alive or p.illness != "" or not world.pack.illnesses.has(illness_id):
		return
	p.illness = illness_id
	world.emit("fell_ill", {"person": p.uid})


## Makes `p` healthy. An action that only the sick may do (`requires` an illness or
## `sick: true`) is cancelled, so the cured do not stay in the sick bed.
static func cure(world: World, p: Person) -> void:
	if p.illness == "":
		return
	p.illness = ""
	if not p.current.is_empty():
		var req: Dictionary = world.pack.actions[p.current["action"]]["requires"]
		if req.has("illness") or bool(req.get("sick", false)):
			AutonomySystem.cancel(world, p)
	world.stats["cured"] = int(world.stats["cured"]) + 1
	world.emit("cured", {"person": p.uid})


## If `p` is alive, sick and idle, starts the symptom action of their illness.
static func show_symptom(world: World, p: Person) -> void:
	if not p.alive or p.illness == "" or not p.current.is_empty():
		return
	AutonomySystem.start(world, p, str(world.pack.illnesses[p.illness]["symptom_action"]), -1)
