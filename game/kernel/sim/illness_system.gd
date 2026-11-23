class_name IllnessSystem
extends RefCounted
## Random illness, per-step drain while sick, and cures. Events never name the illness:
## the player must recognise it from the symptom action and pick the matching medicine.


static func step(world: World, dt: float) -> void:
	var pack := world.pack
	# Per-minute chance scaled to the step (x1.0 at 60 s steps, so those draw exactly as before).
	var chance := float(pack.cfg("illness_daily_chance")) / 1440.0 * (dt / 60.0)
	chance *= world.blessing_illness
	var floor_v := -1.0  # read for the first one who is ill (usually nobody)
	for p in world.people:
		if not p.alive:
			continue
		if p.illness == "":
			if p.stage(pack) != "baby" and not pack.illnesses.is_empty() and world.rng.chance(chance * (1.0 if world.offline else p.ill_factor)):
				infect(world, p, _pick_illness(world))
			continue
		var drain: Dictionary = pack.illnesses[p.illness]["drain"]
		for nid in drain:
			if p.needs.has(nid):
				p.needs[nid] = clampf(float(p.needs[nid]) - absf(float(drain[nid])) * dt / 3600.0, 0.0, 100.0)
		if world.offline:
			if floor_v < 0.0:
				floor_v = float(pack.cfg("offline_need_floor"))
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


## The items that cure `p`'s illness, in pack order ([] for the healthy, the dead and anyone
## away). The view asks this to mark the fitting medicine: it never reads the illness itself.
static func remedies(world: World, p: Person) -> Array[String]:
	var out: Array[String] = []
	if p == null or not p.alive or p.illness == "" or OutingSystem.away(world, p):
		return out
	for id in world.pack.items:
		if str(world.pack.items[id].get("cures", "")) == p.illness:
			out.append(str(id))
	return out


## What someone who knows medicine says about illness `id` (its `diagnosis`; "" for none).
static func diagnosis(pack: Pack, id: String) -> String:
	return str(pack.illnesses.get(id, {}).get("diagnosis", ""))


## True for an action that treats a sick member of the family (`treats`).
static func treats(a: Dictionary) -> bool:
	return bool(a.get("treats", false))


## Whether `q` can be treated now by `healer`: alive, ill, at home, not the healer, and not
## already being treated by someone else.
static func treatable(world: World, q: Person, healer: Person) -> bool:
	return q != null and q != healer and q.alive and q.illness != "" and not OutingSystem.away(world, q) \
		and not AutonomySystem.target_claimed(world, q.uid, AutonomySystem.TARGET_PATIENT, healer)


## The sick person `healer` would treat: of those `treatable`, the one with the lowest vital
## need (the first such on a tie); -1 for none.
static func patient_for(world: World, healer: Person) -> int:
	var vital := str(world.pack.cfg("vital_need"))
	var best := -1
	var low := INF
	for q in world.people:
		if q.illness == "" or not treatable(world, q, healer):
			continue
		var v := float(q.needs.get(vital, 100.0))
		if v < low:
			low = v
			best = q.uid
	return best


## A treating action finished: the patient is told what ails them (`diagnosed`) and is cured.
static func treated(world: World, healer: Person, uid: int) -> void:
	var q := world.person(uid)
	if q == null or not q.alive or q.illness == "":
		return
	world.emit("diagnosed", {"person": q.uid, "by": healer.uid, "line": diagnosis(world.pack, q.illness)})
	cure(world, q)
	world.emit("treated", {"person": q.uid, "by": healer.uid})
