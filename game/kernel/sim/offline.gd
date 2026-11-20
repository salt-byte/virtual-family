class_name Offline
extends RefCounted
## Replays the time the player was away and sums it up as a "while you were away" summary.


## Simulates up to `offline_cap_hours` of `elapsed_seconds` with the offline floor on.
## Events that were already queued stay queued; those the replay produces go into the summary.
## The same replay can be run a slice at a time with a `CatchUpJob`; the result is identical.
static func catch_up(world: World, elapsed_seconds: float) -> Dictionary:
	var job := CatchUpJob.new(world, elapsed_seconds)
	job.run(-1)
	return job.finish()


## The summary of a finished replay: `t0`, `money0` and `held` (the events queued before it)
## as they were when it began; requeues `held` and drains everything the replay produced.
static func summarize(world: World, elapsed_seconds: float, t0: int, money0: int, letters: Array,
		held: Array) -> Dictionary:
	var summary := _empty()
	var cap := int(world.pack.cfg("offline_cap_hours")) * 3600
	summary["letters"] = letters
	var events := world.drain_events()
	world.requeue_events(held)
	summary["capped"] = elapsed_seconds > float(cap)
	summary["game_over"] = world.phase == "over"
	summary["simulated_seconds"] = world.now - t0
	summary["years_passed"] = float(world.now - t0) / (float(world.pack.cfg("hours_per_year")) * 3600.0)
	summary["money_delta"] = world.money - money0
	for e in events:
		match e.type:
			"person_died": summary["deaths"].append({"person": e.person, "cause": e.cause})
			"fell_ill": summary["illnesses"].append(e.person)
			"level_up": summary["level_ups"].append({"person": e.person, "level": e.level})
			"proposal_expired": summary["proposals_expired"] += 1
			"goal_done": summary["goals_done"].append(e.goal)
			"fragment_found": summary["fragments"].append({"story": e.story, "fragment": e.fragment})
			"story_done": summary["stories_done"].append(e.story)
			"born": summary["births"].append(e.person)
			"relative_arrived": summary["relatives"].append(e.person)
			"pet_died": summary["pets_died"].append({"pet": e.pet, "cause": e.cause})
			"pet_fell_ill": summary["pets_ill"].append(e.pet)
			"pet_came_back": summary["pets_back"].append(e.pet)
			"pet_cured": summary["pets_cured"].append(e.pet)
			"festival_started": summary["festivals"].append(e.festival)
			"outing_back": summary["outings"].append({"person": e.person, "action": e.action, "item": e.item, "text": e.text})
			"lottery_drawn": summary["lottery"].append({"ticket": e.ticket, "amount": e.amount})
	summary["proposals_waiting"] = world.proposals.size()
	summary["messes_now"] = world.messes.size()
	return summary


## The summary of an absence in which nothing was simulated (still reports what is waiting).
static func zero_summary(world: World) -> Dictionary:
	var summary := _empty()
	summary["proposals_waiting"] = world.proposals.size()
	summary["messes_now"] = world.messes.size()
	return summary


static func _empty() -> Dictionary:
	return {"simulated_seconds": 0, "capped": false, "years_passed": 0.0, "money_delta": 0,
		"deaths": [], "illnesses": [], "level_ups": [], "proposals_expired": 0,
		"proposals_waiting": 0, "goals_done": [], "messes_now": 0, "game_over": false,
		"fragments": [], "stories_done": [], "births": [], "relatives": [],
		"pets_died": [], "pets_ill": [], "pets_back": [], "pets_cured": [], "festivals": [], "outings": [],
		"letters": [], "lottery": []}
