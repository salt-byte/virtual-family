class_name ShareSystem
extends RefCounted
## People who earn turn to the screen and tell the player: the same pause and wave as a
## granted wish (`Person.thanks_until`), with what they are sharing in `Person.share` for
## the view's words. Off while the pack's `share` is empty. Keys:
## - `every`: coins. Each person keeps a tally of what they earned today (local day); each
##   time it passes another multiple of `every`, they share the day's total.
## - `gap_min`: real minutes at least between two shares of money by the same person.
## - `level`: true to share every new level of their livelihood (not held back by the gap).
## - `money_text` / `level_text`: the words, with {n} (today's coins) and {level} (the
##   level's name).
## Nobody turns to share in their sleep (a `slow` action), while already waving, or while
## the player is away (what comes in then is counted as told). Draws no randomness.


static func cfg(pack: Pack) -> Dictionary:
	var c = pack.cfg("share")
	return c if c is Dictionary else {}


static func enabled(pack: Pack) -> bool:
	return not cfg(pack).is_empty()


## `amount` coins came in for the person with uid `uid` (salary, work, a sale).
static func on_income(world: World, uid: int, amount: int) -> void:
	if amount <= 0 or uid < 0 or not enabled(world.pack):
		return
	var p := world.person(uid)
	if p == null or not p.alive:
		return
	var day := floori(float(world.now + world.utc_offset) / 86400.0)
	if p.earned_day != day:
		p.earned_day = day
		p.earned = 0
		p.earned_told = 0
	p.earned += amount
	if world.offline:
		p.earned_told = p.earned
		return
	var c := cfg(world.pack)
	var every := maxi(int(c.get("every", 0)), 1)
	if p.earned / every <= p.earned_told / every:
		return
	var gap := int(float(c.get("gap_min", 0)) * 60.0)
	if p.shared_at > 0 and world.now - p.shared_at < gap:
		return
	if _start(world, p, {"kind": "money", "n": p.earned, "level": p.level}):
		p.earned_told = p.earned


## `p` just rose a level in their livelihood.
static func on_level_up(world: World, p: Person) -> void:
	if world.offline or not enabled(world.pack) or not bool(cfg(world.pack).get("level", false)):
		return
	_start(world, p, {"kind": "level", "n": 0, "level": p.level})


## Turns `p` to the screen with `share`; false when they cannot now.
static func _start(world: World, p: Person, share: Dictionary) -> bool:
	if p.thanking(world.now):
		return false
	if not p.current.is_empty() and bool(world.pack.actions[p.current["action"]].get("slow", false)):
		return false
	p.thanks_until = world.now + WishSystem.thanks_seconds(world)
	p.share = share
	p.shared_at = world.now
	world.emit("shared", {"person": p.uid, "kind": share["kind"], "n": share["n"], "level": share["level"]})
	return true


## What `p` is telling the player right now ("" when they are not sharing).
static func text(world: World, p: Person) -> String:
	if p.share.is_empty() or not p.thanking(world.now):
		return ""
	var c := cfg(world.pack)
	var kind := str(p.share.get("kind", ""))
	var level_name := ""
	var levels: Array = world.pack.livelihoods.get(p.track, {}).get("levels", [])
	var lv := int(p.share.get("level", 0))
	if lv >= 0 and lv < levels.size():
		level_name = str(levels[lv].get("name", ""))
	return str(c.get(kind + "_text", "")).format({"n": int(p.share.get("n", 0)), "level": level_name})
