class_name EconomySystem
extends RefCounted
## Money and livelihoods: hourly salary, work bonus, progress and levels, and the shop.
## Every coin in or out goes through `spend` / `earn`; `world.money` stays an int and never
## drops below zero. The one exception is salary, which keeps its own emit path because it
## must emit an `income` event even for a 0-coin hourly part.


## Pays each working-age person one of 24 hourly parts of their level's daily income.
static func step(world: World, _dt: float) -> void:
	if world.now / 3600 == (world.now - World.STEP) / 3600:  # no hour boundary crossed
		return
	for p in world.people:
		if not p.alive or p.track == "" or not (p.stage(world.pack) in ["adult", "elder"]):
			continue
		var lvl := _level(world, p)
		if lvl.is_empty():
			continue
		# `carry` is <= 0: coins paid ahead of schedule, so the 24 parts add up exactly.
		var total := int(lvl["daily_income"]) + int(world.income_carry.get(p.uid, 0))
		var pay := maxi((total + 23) / 24, 0)
		world.income_carry[p.uid] = total - pay * 24
		world.money += pay
		world.emit("income", {"person": p.uid, "amount": pay, "source": "salary"})


## False (and nothing taken) when there is not enough money.
static func spend(world: World, amount: int) -> bool:
	if amount < 0 or amount > world.money:
		return false
	world.money -= amount
	return true


## `person_uid` (>= 0) names the person the income belongs to and goes into the event as
## `person`; income from no one in particular (a goal, a sale) has no `person` key.
static func earn(world: World, amount: int, source: String, person_uid := -1) -> void:
	if amount <= 0:
		return
	world.money += amount
	var e := {"amount": amount, "source": source}
	if person_uid >= 0:
		e["person"] = person_uid
	world.emit("income", e)


## Called when a `work` action ends: coin bonus always, progress only when fit to work.
static func on_work_finished(world: World, p: Person, minutes: int) -> void:
	var lvl := _level(world, p)
	if lvl.is_empty():
		return
	var bonus := int(float(lvl["work_bonus_per_hour"]) * minutes / 60.0)
	earn(world, bonus, "work", p.uid)
	if not _fit_to_work(world, p):
		return
	p.progress += float(minutes) * p.aptitude
	var need := int(lvl["progress_to_next"])
	var levels: Array = world.pack.livelihoods[p.track]["levels"]
	if need > 0 and p.progress >= need and p.level < levels.size() - 1:
		p.level += 1
		p.progress = 0.0
		world.emit("level_up", {"person": p.uid, "track": p.track, "level": p.level})


static func _fit_to_work(world: World, p: Person) -> bool:
	if p.illness != "":
		return false
	var mins: Dictionary = world.pack.cfg("work_needs_min")
	for n in mins:
		if float(p.needs.get(n, 0.0)) < float(mins[n]):
			return false
	return true


## The person's current level entry, or {} when their track or level is unknown.
static func _level(world: World, p: Person) -> Dictionary:
	var track: Dictionary = world.pack.livelihoods.get(p.track, {})
	var levels: Array = track.get("levels", [])
	if p.level < 0 or p.level >= levels.size():
		return {}
	return levels[p.level]
