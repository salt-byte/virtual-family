class_name NeedsSystem
extends RefCounted
## Drains needs, ages people, and ends lives (neglect while online, old age always).


static func step(world: World, dt: float) -> void:
	var pack := world.pack
	var vital := str(pack.cfg("vital_need"))
	var floor_v := float(pack.cfg("offline_need_floor"))
	var age_per_step := dt / (float(pack.cfg("hours_per_year")) * 3600.0)
	var praise_need := str(pack.cfg("praise_need"))
	var praise_drain := float(pack.cfg("praise_decay_per_hour")) * dt / 3600.0
	for p in world.people:
		if not p.alive:
			continue
		for nid in pack.needs:
			if p.needs.has(nid):
				p.needs[nid] = clampf(float(p.needs[nid]) - float(pack.needs[nid]["drain_per_hour"]) * dt / 3600.0, 0.0, 100.0)
		if praise_need != "" and p.needs.has(praise_need):
			p.needs[praise_need] = clampf(float(p.needs[praise_need]) - praise_drain, 0.0, 100.0)
		for nid in pack.needs:
			var we: Dictionary = pack.needs[nid]["when_empty"]
			if we.is_empty() or not p.needs.has(nid) or float(p.needs[nid]) > 0.0:
				continue
			var other := str(we["need"])
			if p.needs.has(other):
				p.needs[other] = clampf(float(p.needs[other]) - float(we["per_hour"]) * dt / 3600.0, 0.0, 100.0)
		if world.offline:
			for nid in p.needs:
				p.needs[nid] = maxf(float(p.needs[nid]), floor_v)
		p.age += age_per_step
		if vital != "" and p.needs.has(vital) and float(p.needs[vital]) <= 0.0:
			world.kill_person(p, "neglect")
		elif p.age >= p.lifespan:
			world.kill_person(p, "old_age")
