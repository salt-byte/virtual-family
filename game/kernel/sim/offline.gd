class_name Offline
extends RefCounted
## Replays the time the player was away and sums it up as a "while you were away" summary.


## Simulates up to `offline_cap_hours` of `elapsed_seconds` with the offline floor on.
## Events that were already queued stay queued; those the replay produces go into the summary.
static func catch_up(world: World, elapsed_seconds: float) -> Dictionary:
	if world.phase != "living" or elapsed_seconds <= 0.0:
		return zero_summary(world)
	var summary := _empty()
	var cap := int(world.pack.cfg("offline_cap_hours")) * 3600
	var seconds := minf(elapsed_seconds, float(cap))
	var t0 := world.now
	var money0 := world.money
	var held := world.drain_events()
	var was_offline := world.offline
	world.offline = true
	world.advance(seconds)
	world.offline = was_offline
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
		"proposals_waiting": 0, "goals_done": [], "messes_now": 0, "game_over": false}
