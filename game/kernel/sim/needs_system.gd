class_name NeedsSystem
extends RefCounted
## Drains needs, ages people, and ends lives (neglect while online, old age always).


## [need ids, their drains per hour, then for the needs with a `when_empty`: their ids, the
## need each drains, and by how much an hour], in pack order; built once per pack (a pack's
## needs do not change once worlds use it).
static func _table(pack: Pack) -> Array:
	if pack.needs_table.is_empty() or (pack.needs_table[0] as PackedStringArray).size() != pack.needs.size():
		var ids := PackedStringArray()
		var drains := PackedFloat64Array()
		var e_ids := PackedStringArray()
		var e_others := PackedStringArray()
		var e_rates := PackedFloat64Array()
		for nid in pack.needs:
			ids.append(str(nid))
			drains.append(float(pack.needs[nid]["drain_per_hour"]))
			var we: Dictionary = pack.needs[nid]["when_empty"]
			if not we.is_empty():
				e_ids.append(str(nid))
				e_others.append(str(we["need"]))
				e_rates.append(float(we["per_hour"]))
		pack.needs_table = [ids, drains, e_ids, e_others, e_rates]
	return pack.needs_table


static func step(world: World, dt: float) -> void:
	var pack := world.pack
	var vital := str(pack.cfg("vital_need"))
	var floor_v := float(pack.cfg("offline_need_floor"))
	var age_per_step := dt / (float(pack.cfg("hours_per_year")) * 3600.0)
	var praise_need := str(pack.cfg("praise_need"))
	var praise_drain := float(pack.cfg("praise_decay_per_hour")) * dt / 3600.0
	var grown := LivelihoodSystem.adult_age(pack) if LivelihoodSystem.has_choice(pack) else -1.0
	var t := _table(pack)
	var ids: PackedStringArray = t[0]
	var drains: PackedFloat64Array = t[1]
	var empty_ids: PackedStringArray = t[2]
	var empty_others: PackedStringArray = t[3]
	var empty_rates: PackedFloat64Array = t[4]
	for p in world.people:
		if not p.alive:
			continue
		var needs := p.needs
		for k in ids.size():
			var nv = needs.get(ids[k])
			if nv != null:
				needs[ids[k]] = clampf(float(nv) - drains[k] * dt / 3600.0, 0.0, 100.0)
		if praise_need != "" and needs.has(praise_need):
			needs[praise_need] = clampf(float(needs[praise_need]) - praise_drain, 0.0, 100.0)
		for k in empty_ids.size():
			var ev = needs.get(empty_ids[k])
			if ev == null or float(ev) > 0.0:
				continue
			var ov = needs.get(empty_others[k])
			if ov != null:
				needs[empty_others[k]] = clampf(float(ov) - empty_rates[k] * dt / 3600.0, 0.0, 100.0)
		if world.offline:
			for nid in p.needs:
				p.needs[nid] = maxf(float(p.needs[nid]), floor_v)
		var was := p.age
		p.age += age_per_step
		if grown >= 0.0 and was < grown and p.age >= grown:
			LivelihoodSystem.come_of_age(world, p)
		if p.look != "" and world.pack.stage_of(was) != world.pack.stage_of(p.age):
			LookSystem.ensure(world, p)  # grown up or grown old: a look for the new stage
		if vital != "" and p.needs.has(vital) and float(p.needs[vital]) <= 0.0:
			world.kill_person(p, "neglect")
		elif p.age >= p.lifespan:
			world.kill_person(p, "old_age")
