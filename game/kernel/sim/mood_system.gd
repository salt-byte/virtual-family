class_name MoodSystem
extends RefCounted
## Low mood that sets in when the praise need stays low: below `mood_low_below` for
## `mood_sad_after_hours` a person turns "sad", and once it has been low for
## `mood_depressed_after_hours` in all they are "depressed". Depression is not an illness and
## no medicine touches it: it lifts back to sadness after the need has stayed at or above
## `mood_recover_above` for `mood_recover_hours`, and sadness clears after
## `mood_sad_recover_hours` more. While the need sits between the two lines neither clock
## runs, and while the player is away the low clock stands still (people do not sink into
## depression unseen). While depressed `mood_depressed_drain` drains needs faster; the other
## effects live where they apply (no work progress, no new wishes, a different choice of
## actions). Off when `mood_low_below` is 0 or the pack has no praise need; draws no
## randomness.


## The player paid attention to `p` (praise, something used on them, a wish granted).
static func cared(world: World, p: Person) -> void:
	if p != null:
		p.cared_at = world.now
		p.mood_cap = 100.0


## Sets `p.mood_cap` to the ceiling at the start of the current game minute.
static func refresh_cap(world: World, p: Person) -> void:
	p.mood_cap = ceiling_at(world, p, world.now - posmod(world.now, 60))


## The highest the praise need may rise through `p`'s own actions now: 100 unless they have
## gone without attention for longer than `mood_care_hours`.
static func ceiling(world: World, p: Person) -> float:
	return ceiling_at(world, p, world.now)


static func ceiling_at(world: World, p: Person, t: int) -> float:
	var hours := float(world.pack.cfg("mood_care_hours"))
	if hours <= 0.0 or p.cared_at <= 0:
		return 100.0
	var over := float(t - p.cared_at) / 3600.0 - hours
	if over <= 0.0:
		return 100.0
	return maxf(100.0 - over * float(world.pack.cfg("mood_neglect_per_hour")), float(world.pack.cfg("mood_neglect_floor")))


static func enabled(pack: Pack) -> bool:
	return float(pack.cfg("mood_low_below")) > 0.0 and str(pack.cfg("praise_need")) != ""


## Runs once per game minute (on the step that starts one), counting a whole minute.
static func step(world: World, dt: float) -> void:
	if world.now % 60 >= int(dt):
		return
	var pack := world.pack
	if not enabled(pack):
		return
	dt = maxf(dt, 60.0)
	var need := str(pack.cfg("praise_need"))
	var low := float(pack.cfg("mood_low_below"))
	var high := float(pack.cfg("mood_recover_above"))
	var sad_after := int(float(pack.cfg("mood_sad_after_hours")) * 3600.0)
	var deep_after := int(float(pack.cfg("mood_depressed_after_hours")) * 3600.0)
	var recover := int(float(pack.cfg("mood_recover_hours")) * 3600.0)
	var sad_recover := int(float(pack.cfg("mood_sad_recover_hours")) * 3600.0)
	var drain: Dictionary = pack.cfg("mood_depressed_drain")
	var floor_v := float(pack.cfg("offline_need_floor"))
	for p in world.people:
		if not p.alive or not p.needs.has(need):
			continue
		if p.cared_at <= 0:
			p.cared_at = world.now
		refresh_cap(world, p)
		var v := float(p.needs[need])
		if v < low:
			p.mood_ok_s = 0
			if not world.offline:
				p.mood_low_s += int(dt)
		elif v >= high:
			p.mood_low_s = 0
			if p.mood != "":
				p.mood_ok_s += int(dt)
		match p.mood:
			"":
				if p.mood_low_s >= sad_after:
					_change(world, p, "sad")
			"sad":
				if p.mood_low_s >= deep_after:
					_change(world, p, "depressed")
				elif p.mood_ok_s >= sad_recover:
					_change(world, p, "")
			"depressed":
				if p.mood_ok_s >= recover:
					_change(world, p, "sad")
				else:
					for n in drain:
						if p.needs.has(n):
							var nv := float(p.needs[n]) - float(drain[n]) * dt / 3600.0
							if world.offline:
								nv = maxf(nv, minf(floor_v, float(p.needs[n])))
							p.needs[n] = clampf(nv, 0.0, 100.0)


static func _change(world: World, p: Person, mood: String) -> void:
	var was := p.mood
	p.mood = mood
	p.mood_ok_s = 0
	if mood == "":
		p.mood_low_s = 0
	world.emit("mood_changed", {"person": p.uid, "mood": mood, "was": was})
