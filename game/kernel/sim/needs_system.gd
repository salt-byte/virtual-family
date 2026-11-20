class_name NeedsSystem
extends RefCounted
## Drains needs, ages people, and ends lives (neglect while online, old age always).


## [need ids, their drains per hour, then for the needs with a `when_empty`: their ids, the
## need each drains, and by how much an hour, then need id -> position in the ids, and the
## positions of the `when_empty` ids and of the needs they drain (-1: not a pack need), then
## `_busy_table`], in
## pack order; built once per pack (a pack's needs do not change once worlds use it).
static func _table(pack: Pack) -> Array:
	if pack.needs_table.size() < 9 or (pack.needs_table[0] as PackedStringArray).size() != pack.needs.size():
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
		var pos := {}
		for k in ids.size():
			pos[ids[k]] = k
		var e_pos := PackedInt32Array()
		var o_pos := PackedInt32Array()
		for k in e_ids.size():
			e_pos.append(int(pos.get(e_ids[k], -1)))
			o_pos.append(int(pos.get(e_others[k], -1)))
		pack.needs_table = [ids, drains, e_ids, e_others, e_rates, pos, e_pos, o_pos, _busy_table(pack)]
	return pack.needs_table


## What the needs' `extra_drain` and `low` add, worked out once per pack:
## {on, by_action: action id -> [[need, per hour], ...], wet: [[need, per hour], ...],
## low: [[need, below, {other need: per hour}, illness factor], ...]}. `on` is false when
## no need has either (every pack before they existed): then nothing here runs.
##
## An `extra_drain` rule {per_hour, ...} drains its need faster while doing an action it
## fits: `work`, `cleans`, `picks`, `tends`, `pet` or `eats` (true: actions of that sort),
## `actions` (ids) or `tags` (any of them); any one of these is enough. A rule with
## `wet: true` instead fits any action out of doors while the weather is wet.
## `low` {below, drain, illness_factor}: while the need is below `below`, `drain` takes
## from other needs per hour and the chance of falling ill is multiplied by the factor
## (neither while the player is away).
static func _busy_table(pack: Pack) -> Dictionary:
	var by_action := {}
	var wet: Array = []
	var low: Array = []
	for nid in pack.needs:
		var n: Dictionary = pack.needs[nid]
		for r in n.get("extra_drain", []):
			var rate := float(r.get("per_hour", 0.0))
			if rate == 0.0:
				continue
			if bool(r.get("wet", false)):
				wet.append([str(nid), rate])
				continue
			for aid in pack.actions:
				if rule_fits(r, pack.actions[aid]):
					if not by_action.has(aid):
						by_action[aid] = []
					by_action[aid].append([str(nid), rate])
		var lo: Dictionary = n.get("low", {})
		if not lo.is_empty():
			low.append([str(nid), float(lo.get("below", 0.0)), lo.get("drain", {}), float(lo.get("illness_factor", 1.0))])
	var outdoors := {}  # action id -> true for those done out of doors (for `wet` rules)
	if not wet.is_empty():
		for aid in pack.actions:
			if WeatherSystem.place_kind(pack, pack.actions[aid]) > 0:
				outdoors[aid] = true
	return {"on": not (by_action.is_empty() and wet.is_empty() and low.is_empty()),
		"by_action": by_action, "wet": wet, "low": low, "outdoors": outdoors}


## Whether an `extra_drain` rule (not a wet one) fits action `a`.
static func rule_fits(r: Dictionary, a: Dictionary) -> bool:
	if bool(r.get("work", false)) and not (a["work"] as Dictionary).is_empty():
		return true
	if bool(r.get("cleans", false)) and str(a["cleans"]) != "":
		return true
	if bool(r.get("picks", false)) and bool(a["picks"]):
		return true
	if bool(r.get("tends", false)) and not (a.get("tends", {}) as Dictionary).is_empty():
		return true
	if bool(r.get("pet", false)) and not (a.get("pet", {}) as Dictionary).is_empty() and not bool(a["pet"].get("watch", false)):
		return true
	if bool(r.get("eats", false)) and not (a.get("eats", []) as Array).is_empty():
		return true
	if (r.get("actions", []) as Array).has(a["id"]):
		return true
	for t in r.get("tags", []):
		if (a.get("tags", []) as Array).has(t):
			return true
	return false


## The factor on `p`'s chance of falling ill from their needs that are low (1.0: none, and
## always while the player is away). The step uses the value kept on the person at the
## start of each game minute (`Person.ill_factor`).
static func illness_factor(world: World, p: Person) -> float:
	var f := 1.0
	if world.offline:
		return f
	var busy: Dictionary = _table(world.pack)[8]
	for l in busy["low"]:
		var v = p.needs.get(l[0])
		if v != null and float(v) < float(l[1]):
			f *= float(l[3])
	return f


## The drains `extra_drain` and `low` add over `dt` seconds, from what `p` is doing now (see
## `_busy_table`). Runs once per game minute (the needs change slowly; the hot step stays
## as it was), and keeps `p.ill_factor` up to date.
static func _busy(world: World, p: Person, busy: Dictionary, dt: float, raining: bool) -> void:
	p.ill_factor = illness_factor(world, p)
	var needs := p.needs
	if not p.current.is_empty():
		var list = busy["by_action"].get(p.current["action"])
		if list != null:
			for r in list:
				var v = needs.get(r[0])
				if v != null:
					needs[r[0]] = clampf(float(v) - float(r[1]) * dt / 3600.0, 0.0, 100.0)
		if raining and busy["outdoors"].has(p.current["action"]):
			for r in busy["wet"]:
				var v = needs.get(r[0])
				if v != null:
					needs[r[0]] = clampf(float(v) - float(r[1]) * dt / 3600.0, 0.0, 100.0)
	if world.offline:
		return
	for l in busy["low"]:
		var v = needs.get(l[0])
		if v == null or float(v) >= float(l[1]):
			continue
		var drain: Dictionary = l[2]
		for o in drain:
			var ov = needs.get(o)
			if ov != null:
				needs[o] = clampf(float(ov) - float(drain[o]) * dt / 3600.0, 0.0, 100.0)


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
	var busy: Dictionary = t[8]
	var busy_on := bool(busy["on"])
	# The busy drains run on the step that starts a game minute, for the whole minute.
	if busy_on and world.now % 60 >= int(dt):
		busy_on = false
	var busy_dt := maxf(dt, 60.0)
	var raining := busy_on and not (busy["wet"] as Array).is_empty() \
			and bool(WeatherSystem.weather_entry(pack, world.weather).get("wet", false))
	var empty_pos: PackedInt32Array = t[6]
	var other_pos: PackedInt32Array = t[7]
	var praise_pos := int((t[5] as Dictionary).get(praise_need, -1))
	var n := ids.size()
	# Each person's pack needs are worked on in `vals` (by position in `ids`; `here` 0 where
	# the person lacks that need) and written back once: the same arithmetic in the same order
	# as reading and writing the dictionary at every stage.
	var vals := PackedFloat64Array()
	vals.resize(n)
	var here := PackedByteArray()
	here.resize(n)
	for p in world.people:
		if not p.alive:
			continue
		var needs := p.needs
		var held := 0
		for k in n:
			var nv = needs.get(ids[k])
			if nv != null:
				vals[k] = clampf(float(nv) - drains[k] * dt / 3600.0, 0.0, 100.0)
				here[k] = 1
				held += 1
			else:
				here[k] = 0
		if praise_pos >= 0:
			if here[praise_pos] == 1:
				vals[praise_pos] = clampf(vals[praise_pos] - praise_drain, 0.0, 100.0)
		elif praise_need != "" and needs.has(praise_need):
			needs[praise_need] = clampf(float(needs[praise_need]) - praise_drain, 0.0, 100.0)
		for k in empty_ids.size():
			var ep := empty_pos[k]
			var ev = (vals[ep] if here[ep] == 1 else null) if ep >= 0 else needs.get(empty_ids[k])
			if ev == null or float(ev) > 0.0:
				continue
			var op := other_pos[k]
			if op >= 0:
				if here[op] == 1:
					vals[op] = clampf(vals[op] - empty_rates[k] * dt / 3600.0, 0.0, 100.0)
			else:
				var ov = needs.get(empty_others[k])
				if ov != null:
					needs[empty_others[k]] = clampf(float(ov) - empty_rates[k] * dt / 3600.0, 0.0, 100.0)
		var offline := world.offline
		for k in n:
			if here[k] == 1:
				needs[ids[k]] = maxf(vals[k], floor_v) if offline else vals[k]
		if offline and needs.size() != held:  # needs that are not the pack's
			for nid in needs:
				needs[nid] = maxf(float(needs[nid]), floor_v)
		if busy_on:
			_busy(world, p, busy, busy_dt, raining)
			if offline:
				for nid in needs:
					needs[nid] = maxf(float(needs[nid]), floor_v)
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
