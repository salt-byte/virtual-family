class_name EconomySystem
extends RefCounted
## Money and livelihoods: hourly salary, work bonus, progress and levels, and the shop.
## Every coin in or out goes through `spend` / `earn`; `world.money` stays an int and never
## drops below zero.


## Pays each working-age person one of 24 hourly parts of their level's daily income.
static func step(world: World, _dt: float) -> void:
	if world.now % 3600 != 0:
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
		world.emit("income", {"uid": p.uid, "amount": pay, "source": "salary"})


## False (and nothing taken) when there is not enough money.
static func spend(world: World, amount: int) -> bool:
	if amount < 0 or amount > world.money:
		return false
	world.money -= amount
	return true


static func earn(world: World, amount: int, source: String) -> void:
	if amount <= 0:
		return
	world.money += amount
	world.emit("income", {"amount": amount, "source": source})


## Called when a `work` action ends: coin bonus always, progress only when fit to work.
static func on_work_finished(world: World, p: Person, minutes: int) -> void:
	var lvl := _level(world, p)
	if lvl.is_empty():
		return
	var bonus := int(float(lvl["work_bonus_per_hour"]) * minutes / 60.0)
	if bonus > 0:
		world.money += bonus
		world.emit("income", {"uid": p.uid, "amount": bonus, "source": "work"})
	if not _fit_to_work(world, p):
		return
	p.progress += float(minutes) * p.aptitude
	var need := int(lvl["progress_to_next"])
	var levels: Array = world.pack.livelihoods[p.track]["levels"]
	if need > 0 and p.progress >= need and p.level < levels.size() - 1:
		p.level += 1
		p.progress = 0.0
		world.emit("level_up", {"uid": p.uid, "track": p.track, "level": p.level})


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
