class_name LivelihoodSystem
extends RefCounted
## Which livelihood a person follows. A pack with several livelihoods lets each one say what
## it suits (`affinity`: action ids and/or action tags). Grown-ups who arrive get the one
## their liked tags point to; children get none, count what they do, and at coming of age
## take up the one that best fits what they did most. With a single livelihood nothing here
## draws randomness or changes anyone's track. Command: change_track.


## True when the pack offers a choice of livelihoods.
static func has_choice(pack: Pack) -> bool:
	return pack.livelihoods.size() > 1


## livelihood id -> {action id: how many of its affinity entries that action matches}
## (an entry matches an action by id or by one of the action's tags). Built once per pack.
static func _affinity_table(pack: Pack) -> Dictionary:
	if pack.affinity_table.size() == pack.livelihoods.size():
		return pack.affinity_table
	var out := {}
	for lid in pack.livelihoods:
		var aff = pack.livelihoods[lid].get("affinity", [])
		var per := {}
		if aff is Array:
			for aid in pack.actions:
				var tags: Array = pack.actions[aid].get("tags", [])
				var n := 0
				for entry in aff:
					if str(entry) == str(aid) or tags.has(entry):
						n += 1
				if n > 0:
					per[str(aid)] = n
		out[lid] = per
	pack.affinity_table = out
	return out


## The livelihood ids with the highest score, in pack order.
static func _best(scores: Dictionary) -> Array:
	var best: Array = []
	var top := -INF
	for lid in scores:
		var s := float(scores[lid])
		if s > top:
			top = s
			best = [lid]
		elif s == top:
			best.append(lid)
	return best


## Livelihoods that best fit a childhood tally (action id -> count), in pack order.
static func best_for_childhood(pack: Pack, tally: Dictionary) -> Array:
	var table := _affinity_table(pack)
	var scores := {}
	for lid in pack.livelihoods:
		var per: Dictionary = table[lid]
		var s := 0.0
		for aid in tally:
			s += float(per.get(aid, 0)) * float(tally[aid])
		scores[lid] = s
	return _best(scores)


## Livelihoods that best fit a person's tags: each affinity entry among `likes` counts one
## up, each among `dislikes` one down. In pack order.
static func best_for_likes(pack: Pack, likes: Array, dislikes: Array) -> Array:
	var scores := {}
	for lid in pack.livelihoods:
		var s := 0
		var aff = pack.livelihoods[lid].get("affinity", [])
		if aff is Array:
			for entry in aff:
				if likes.has(entry):
					s += 1
				if dislikes.has(entry):
					s -= 1
		scores[lid] = s
	return _best(scores)


## One of `options`; draws randomness only when there is more than one.
static func _pick(world: World, options: Array) -> String:
	if options.size() == 1:
		return str(options[0])
	return str(world.rng.pick(options))


## The track for a grown-up who arrives with these tags (pack with a choice only).
static func track_for_likes(world: World, likes: Array, dislikes: Array) -> String:
	return _pick(world, best_for_likes(world.pack, likes, dislikes))


## Counts a finished action toward a child's tally (pack with a choice only).
static func on_finished(world: World, p: Person, action_id: String) -> void:
	if not has_choice(world.pack) or p.stage(world.pack) != "child":
		return
	p.childhood[action_id] = int(p.childhood.get(action_id, 0)) + 1


## A person just became an adult: with a choice of livelihoods, take up the best fit for
## their childhood, from the bottom level.
static func come_of_age(world: World, p: Person) -> void:
	if not has_choice(world.pack):
		return
	p.track = _pick(world, best_for_childhood(world.pack, p.childhood))
	p.level = 0
	p.progress = 0.0
	p.work_carry = 0.0
	world.emit("took_up", {"person": p.uid, "track": p.track})


## The age (years) at which the "adult" stage starts; -1 when the pack has none.
static func adult_age(pack: Pack) -> float:
	for s in pack.cfg("stages"):
		if str(s.get("id", "")) == "adult":
			return float(s["from"])
	return -1.0


## Player command {person, track}: an adult or elder starts over in another livelihood.
static func change_track(world: World, cmd: Dictionary) -> Dictionary:
	var p := world.person(int(cmd.get("person", -1)))
	if p == null:
		return Commands.fail("no_person")
	if not p.alive:
		return Commands.fail("dead")
	if not (p.stage(world.pack) in ["adult", "elder"]):
		return Commands.fail("stage")
	var track := str(cmd.get("track", ""))
	if not world.pack.livelihoods.has(track):
		return Commands.fail("no_track")
	if track == p.track:
		return Commands.fail("same_track")
	if not p.current.is_empty() and not (world.pack.actions[p.current["action"]]["work"] as Dictionary).is_empty():
		AutonomySystem.cancel(world, p)
	p.track = track
	p.level = 0
	p.progress = 0.0
	p.work_carry = 0.0
	world.emit("changed_track", {"person": p.uid, "track": track})
	return Commands.success()
