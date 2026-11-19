class_name BirthSystem
extends RefCounted
## Pregnancy and birth, configured by the pack's `births` object (off while it is empty, and
## then nothing here draws randomness). Keys, all optional:
## - `fertile_age` [from, to]: the wife's age range (years) in which a couple may conceive
## - `chance_per_day`: chance (0..1) that a couple conceives within a day of the sim clock,
##   times the mood factor (average praise need / 100) and the health factor (lower vital
##   need / 100); none while either is ill or depressed. Tried once an hour.
## - `pregnancy_years`: how long a pregnancy lasts, in years of the pack's clock
## - `beds`: object type ids whose `capacity` adds up to the places to sleep. Everyone alive
##   takes one place and so does every child on the way; with no place left, nobody conceives
##   (the event `births_blocked` says so once each time it starts to block).
## - `surname_from`: "father" (default) or "mother", whose family name the child takes
## - `avoid_tag`: an action tag the pregnant leave alone (heavy work)
## - `drain`: need id -> extra drain per hour while pregnant
## - `guardian`: true to have a relative (a new grown-up) arrive when the last grown-up dies
##   and only children are left
## A child is born as a Person aged 0 with `generation` one above the higher of the parents'
## and `mother` / `father` set; spouses are linked by `FamilySystem.answer_proposal`.

const DEFAULT_FERTILE := [18, 40]


static func enabled(pack: Pack) -> bool:
	var b = pack.cfg("births")
	return b is Dictionary and not (b as Dictionary).is_empty()


static func _b(pack: Pack) -> Dictionary:
	return pack.cfg("births")


static func step(world: World, dt: float) -> void:
	var pack := world.pack
	if not enabled(pack) or world.phase != "living":
		return
	var drain = null  # read on the first pregnancy (usually there is none)
	var floor_v := 0.0
	var due: Array[Person] = []
	for p in world.people:
		if not p.alive or p.pregnant_until <= 0:
			continue
		if world.now >= p.pregnant_until:
			due.append(p)
			continue
		if drain == null:
			drain = _b(pack).get("drain", {})
			floor_v = float(pack.cfg("offline_need_floor"))
		for n in drain:
			if p.needs.has(n):
				var nv := float(p.needs[n]) - float(drain[n]) * dt / 3600.0
				if world.offline:
					nv = maxf(nv, minf(floor_v, float(p.needs[n])))
				p.needs[n] = clampf(nv, 0.0, 100.0)
	for m in due:
		give_birth(world, m)
	if world.now / 3600 != (world.now - int(dt)) / 3600:  # an hour boundary was crossed
		_try_conceive(world)


## The husband of `w` when the two of them could have a child now (both alive and married to
## each other, she in the fertile range and not with child already); else null.
static func fertile_husband(world: World, w: Person) -> Person:
	if not w.alive or w.gender != "female" or w.pregnant_until > 0 or w.spouse <= 0:
		return null
	var r: Array = _b(world.pack).get("fertile_age", DEFAULT_FERTILE)
	if w.age < float(r[0]) or w.age >= float(r[1]):
		return null
	var h := world.person(w.spouse)
	if h == null or not h.alive or h.spouse != w.uid:
		return null
	return h


## Places to sleep left: the beds' capacity minus everyone alive and every child on the way.
static func free_places(world: World) -> int:
	var beds: Array = _b(world.pack).get("beds", [])
	var cap := 0
	for o in world.objects:
		if beds.has(o.type):
			cap += int(world.pack.object_types.get(o.type, {}).get("capacity", 1))
	var used := 0
	for p in world.people:
		if p.alive:
			used += 2 if p.pregnant_until > 0 else 1
	return cap - used


## True when some couple could have a child but the beds have no place for one.
static func blocked(world: World) -> bool:
	if not enabled(world.pack) or free_places(world) > 0:
		return false
	for p in world.people:
		if fertile_husband(world, p) != null:
			return true
	return false


## The chance that this couple conceives within the next hour.
static func hourly_chance(world: World, w: Person, h: Person) -> float:
	var pack := world.pack
	var per_day := clampf(float(_b(pack).get("chance_per_day", 0.0)), 0.0, 1.0)
	if per_day <= 0.0:
		return 0.0
	for p in [w, h]:
		if p.illness != "" or p.mood == "depressed":
			return 0.0
	var base := 1.0 if per_day >= 1.0 else 1.0 - pow(1.0 - per_day, 1.0 / 24.0)
	var factor := 1.0
	var mood := str(pack.cfg("praise_need"))
	if mood != "":
		factor *= clampf((float(w.needs.get(mood, 100.0)) + float(h.needs.get(mood, 100.0))) / 200.0, 0.0, 1.0)
	var vital := str(pack.cfg("vital_need"))
	if vital != "":
		factor *= clampf(minf(float(w.needs.get(vital, 100.0)), float(h.needs.get(vital, 100.0))) / 100.0, 0.0, 1.0)
	return base * factor


static func _try_conceive(world: World) -> void:
	var stopped := false
	for w in world.people:
		var h := fertile_husband(world, w)
		if h == null:
			continue
		if free_places(world) <= 0:
			stopped = true
			continue
		var c := hourly_chance(world, w, h)
		if c > 0.0 and world.rng.chance(c):
			conceive(world, w, h)
	if stopped and not world.birth_blocked:
		world.emit("births_blocked")
	world.birth_blocked = stopped


## `w` is with child by `h`; the child is due after the pack's `pregnancy_years`.
static func conceive(world: World, w: Person, h: Person) -> void:
	var years := float(_b(world.pack).get("pregnancy_years", 0.75))
	var span := maxi(int(years * float(world.pack.cfg("hours_per_year")) * 3600.0), world.step_s)
	w.pregnant_until = world.now + span
	w.pregnant_by = h.uid if h != null else 0
	world.emit("conceived", {"person": w.uid})


## The child of `m` is born: a new person aged 0 in the house; returns them.
static func give_birth(world: World, m: Person) -> Person:
	var f := world.person(m.pregnant_by)
	var b := _b(world.pack)
	var child := FamilySystem.make_person(world, [0.0, 0.0])
	child.age = 0.0
	# A name nobody alive in the house already has, when the pack has one left.
	var taken := {}
	for p in world.people:
		if p.alive:
			taken[p.given] = true
	if taken.has(child.given):
		var pool: Array = (world.pack.names.get(child.gender, []) as Array).filter(func(n): return not taken.has(str(n)))
		if not pool.is_empty():
			child.given = str(world.rng.pick(pool))
	var from := f if str(b.get("surname_from", "father")) == "father" and f != null else m
	child.family = from.family
	child.generation = maxi(m.generation, f.generation if f != null else 0) + 1
	child.mother = m.uid
	child.father = f.uid if f != null else 0
	world.add_person(child)
	m.pregnant_until = 0
	m.pregnant_by = 0
	world.emit("born", {"person": child.uid, "mother": m.uid, "father": child.father})
	WishSystem.on_birth(world, m)
	if f != null:
		WishSystem.on_birth(world, f)
	return child


## A person just died. With `guardian` on, when nobody grown-up is left but children are, a
## relative of the house arrives to bring them up.
static func on_death(world: World, _dead: Person) -> void:
	if not enabled(world.pack) or not bool(_b(world.pack).get("guardian", false)) or world.phase != "living":
		return
	var young: Array[Person] = []
	for p in world.people:
		if not p.alive:
			continue
		if p.stage(world.pack) in ["adult", "elder"]:
			return
		young.append(p)
	if young.is_empty():
		return
	var r := FamilySystem.make_person(world, world.pack.cfg("adopt_age"))
	var top := 0
	for p in young:
		top = maxi(top, p.generation)
	r.family = young[0].family
	r.generation = maxi(top - 1, 0)
	world.add_person(r)
	world.emit("relative_arrived", {"person": r.uid})


## True when `p` could wish for a child: grown-up, married to someone alive, and the couple
## able to have one (she is in the fertile range and not with child already).
static func could_want_child(world: World, p: Person) -> bool:
	if not enabled(world.pack) or p.spouse <= 0 or not (p.stage(world.pack) in ["adult", "elder"]):
		return false
	var other := world.person(p.spouse)
	if other == null:
		return false
	var w := p if p.gender == "female" else other
	return fertile_husband(world, w) != null
