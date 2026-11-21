class_name AskSystem
extends RefCounted
## Asks (a pack's optional asks.json): small, short-lived requests a person makes of the
## player, shown as a bubble over their head. Each person holds at most one, on top of any
## wish. An ask first waits for the player (`wait`, `wait_s` real seconds); help in that
## window gives its `joy` to the praise need and a thank-you (the wave of a granted wish).
## Ignored, it costs `ignored` of the praise need and the person either deals with it
## themselves (`self`: kinds "need" and "do", for up to `ask_self_s` seconds) or lets it go.
## Kinds:
## - "need": formed when `need` falls below `below` (the lowest such need first); met by a
##   drag to anything that raises it, or an item that does; while waiting, the person does
##   not choose such actions on their own; afterwards they score `ask_self_factor` times
##   higher until one is started (their own choice: the weaker `self_factor` gains). It ends
##   quietly once the need is back above `above`. It is not formed while the player has
##   them at something that raises the need, and such a fix meets it when it ends.
## - "praise": met by a praise.
## - "hold": met by any drag (being picked up and set down by the player).
## - "item": met by using one of `items` on them.
## - "do": met by a drag (or an outing) to one of `actions`; while waiting they do not choose
##   those themselves, afterwards they score higher as for a need.
## Every kind but "need" forms by chance: `ask_chance_per_hour` (looked at every
## `ask_check_s` seconds), weighted by `weight`, doubled by a liked tag in `likes` and ruled
## out by a disliked one. Nobody asks while asleep (a `slow` action), out, thanking, as a
## baby (or a stage outside `stages`), within `ask_gap_s` of their last ask ending, nor for
## an ask within `ask_again_s` after it last went unanswered; the depressed only ask
## for needs. While the player is away nobody forms an ask and an ask that is waiting goes
## straight to dealing with it, unpenalised. A pack without asks draws no randomness here
## and changes nothing.

const KINDS := ["need", "praise", "hold", "item", "do"]


static func enabled(pack: Pack) -> bool:
	return not pack.asks.is_empty()


## The ask `p` holds right now as its pack entry, or {}.
static func current(world: World, p: Person) -> Dictionary:
	if p.ask.is_empty():
		return {}
	return world.pack.asks.get(str(p.ask["id"]), {})


## True while `p`'s ask still waits for the player.
static func waiting(p: Person) -> bool:
	return not p.ask.is_empty() and str(p.ask.get("phase", "")) == "wait"


static func step(world: World, dt: float) -> void:
	var pack := world.pack
	if pack.asks.is_empty():
		return
	var check := maxi(int(pack.cfg("ask_check_s")), 1)
	var look := world.now % check < maxi(int(dt), 1)
	for p in world.people:
		if not p.alive:
			continue
		if not p.ask.is_empty():
			_advance(world, p)
		elif look and not world.offline:
			_maybe_form(world, p, check)


## The waiting ask runs out, the dealing with it runs out, or the need came back up.
static func _advance(world: World, p: Person) -> void:
	var e := current(world, p)
	if e.is_empty():
		p.ask = {}
		return
	var kind := str(e["kind"])
	if kind == "need" and float(p.needs.get(str(e["need"]), 100.0)) >= above(e):
		_end(world, p, "ask_done", false)
		return
	var phase := str(p.ask["phase"])
	if phase == "wait" and (world.offline or world.now >= int(p.ask["until"])):
		# While the player is away nobody waits for them: no loss, no word of it.
		var ignored := not world.offline
		if ignored:
			_add_mood(world, p, -float(e.get("ignored", world.pack.cfg("ask_ignored"))))
		if kind == "need" or kind == "do":
			p.ask["phase"] = "self"
			p.ask["until"] = world.now + int(world.pack.cfg("ask_self_s"))
			if ignored:
				world.emit("ask_ignored", {"person": p.uid, "ask": str(e["id"])})
		else:
			_end(world, p, "ask_expired" if ignored else "ask_done", ignored)
	elif phase == "self" and world.now >= int(p.ask["until"]):
		_end(world, p, "ask_expired", true)


## Where an ask of kind "need" counts as met: its `above`, else 15 over `below` (at most 100).
static func above(e: Dictionary) -> float:
	var a = e.get("above")
	return float(a) if a != null else minf(float(e["below"]) + 15.0, 100.0)


static func _end(world: World, p: Person, event: String, unanswered: bool) -> void:
	var id := str(p.ask["id"])
	p.ask = {}
	p.ask_last_t = world.now
	# Not met: that ask stays away a while, whatever comes in between.
	for k in p.ask_again.keys():
		if int(p.ask_again[k]) <= world.now:
			p.ask_again.erase(k)
	if unanswered:
		p.ask_again[id] = world.now + int(world.pack.cfg("ask_again_s"))
	else:
		p.ask_again.erase(id)
	world.emit(event, {"person": p.uid, "ask": id})


static func _add_mood(world: World, p: Person, amount: float) -> void:
	var need := str(world.pack.cfg("praise_need"))
	if need != "" and p.needs.has(need):
		p.needs[need] = clampf(float(p.needs[need]) + amount, 0.0, 100.0)


## Whether `p` could ask anything now (not asleep, out, thanking, a baby, nor too soon).
static func _free_to_ask(world: World, p: Person) -> bool:
	if p.thanking(world.now) or world.now < p.ask_last_t + int(world.pack.cfg("ask_gap_s")):
		return false
	if p.stage(world.pack) == "baby" or OutingSystem.away(world, p):
		return false
	return p.current.is_empty() or not bool(world.pack.actions[p.current["action"]].get("slow", false))


static func _maybe_form(world: World, p: Person, check: int) -> void:
	if not _free_to_ask(world, p):
		return
	var pack := world.pack
	var stage := p.stage(pack)
	# A need first: the one furthest below its line.
	var best := ""
	var best_d := 0.0
	for id in pack.asks:
		var e: Dictionary = pack.asks[id]
		if str(e["kind"]) != "need" or not _stage_ok(e, stage) or world.now < int(p.ask_again.get(id, 0)):
			continue
		var v = p.needs.get(str(e["need"]))
		if v == null or AutonomySystem.raising(world, p, str(e["need"]), true):
			continue  # (no asking for a bath from inside one)
		var d := float(e["below"]) - float(v)
		if d > best_d:
			best = str(id)
			best_d = d
	if best != "":
		_form(world, p, best)
		return
	var chance := float(pack.cfg("ask_chance_per_hour")) * float(check) / 3600.0
	if chance <= 0.0 or p.mood == "depressed":
		return
	var ids: Array = []
	var weights: Array = []
	for id in pack.asks:
		var e: Dictionary = pack.asks[id]
		if str(e["kind"]) == "need" or not _stage_ok(e, stage) or world.now < int(p.ask_again.get(id, 0)):
			continue
		var weight := float(e["weight"])
		var disliked := false
		for t in e["likes"]:
			if p.dislikes.has(t):
				disliked = true
			elif p.likes.has(t):
				weight *= 2.0
		if disliked or (str(e["kind"]) == "do" and not _any_doable(world, p, e["actions"])):
			continue
		ids.append(id)
		weights.append(weight)
	if ids.is_empty() or not world.rng.chance(chance):
		return
	_form(world, p, str(world.rng.weighted_pick(ids, weights)))


static func _stage_ok(e: Dictionary, stage: String) -> bool:
	var stages: Array = e["stages"]
	return stages.is_empty() or stages.has(stage)


## True when `p` could start one of `actions` now.
static func _any_doable(world: World, p: Person, actions: Array) -> bool:
	for a in actions:
		if AutonomySystem.can_do(world, p, str(a), -1) == "":
			return true
	return false


static func _form(world: World, p: Person, id: String) -> void:
	var e: Dictionary = world.pack.asks[id]
	var wait := int(e.get("wait_s", world.pack.cfg("ask_wait_s")))
	p.ask = {"id": id, "phase": "wait", "until": world.now + wait}
	world.emit("ask_formed", {"person": p.uid, "ask": id})


## The player met `p`'s ask: its joy, a thank-you, and the attention counts as care.
static func helped(world: World, p: Person) -> void:
	var e := current(world, p)
	_add_mood(world, p, float(e.get("joy", 0.0)))
	p.thanks_until = world.now + WishSystem.thanks_seconds(world)
	p.share = {}
	MoodSystem.cared(world, p)
	_end(world, p, "ask_helped", false)


## After a player command that worked (`World.command`): whether it met someone's ask.
static func on_command(world: World, type: String, cmd: Dictionary) -> void:
	if world.pack.asks.is_empty() or not type in ["drag", "praise", "use_item", "go_out"]:
		return
	var p := world.person(int(cmd.get("person", -1)))
	if p == null or p.ask.is_empty() or not p.alive:
		return
	var e := current(world, p)
	var met := false
	match str(e.get("kind", "")):
		"need":
			if type == "use_item":
				var item: Dictionary = world.pack.items.get(str(cmd.get("item", "")), {})
				met = float((item.get("needs", {}) as Dictionary).get(str(e["need"]), 0.0)) > 0.0
			elif type != "praise" and not p.current.is_empty():
				met = float((world.pack.actions[p.current["action"]]["needs"] as Dictionary).get(str(e["need"]), 0.0)) > 0.0
		"praise":
			met = type == "praise"
		"hold":
			met = type == "drag"
		"item":
			met = type == "use_item" and (e["items"] as Array).has(str(cmd.get("item", "")))
		"do":
			met = (type == "drag" or type == "go_out") and not p.current.is_empty() \
					and (e["actions"] as Array).has(str(p.current["action"]))
	if met:
		helped(world, p)


## `p` finished action `action_id` (`led`: the player brought them to it): a need ask that
## the action raised is met by the player there and then, with the thank-you. (An ask the
## drag itself met ended already; this is one that came up while they were at it.)
static func on_action_finished(world: World, p: Person, action_id: String, led: bool) -> void:
	var e := current(world, p)
	if led and str(e.get("kind", "")) == "need" \
			and float((world.pack.actions[action_id]["needs"] as Dictionary).get(str(e["need"]), 0.0)) > 0.0:
		helped(world, p)


## `p` just chose action `action_id` on their own: dealing with their ask themselves ends it.
static func on_chosen(world: World, p: Person, action_id: String) -> void:
	if p.ask.is_empty() or str(p.ask["phase"]) != "self":
		return
	var ix = world.pack.autonomy_index.get(action_id)
	if ix != null and fixers(world.pack, str(p.ask["id"])).has(int(ix)):
		_end(world, p, "ask_self", false)


## By `AutonomySystem` index (`Info.idx`), the actions that meet ask `id` when the person does
## them: for a need, those that raise it; for "do", its actions; none for the rest. Kept on
## the pack.
static func fixers(pack: Pack, id: String) -> PackedInt32Array:
	var c = pack.ask_fixers.get(id)
	if c != null:
		return c
	AutonomySystem._table(pack)  # fills `autonomy_index`
	var out := PackedInt32Array()
	var e: Dictionary = pack.asks.get(id, {})
	for aid in pack.actions:
		var ix = pack.autonomy_index.get(aid)
		if ix == null:
			continue
		var a: Dictionary = pack.actions[aid]
		match str(e.get("kind", "")):
			"need":
				if float((a["needs"] as Dictionary).get(str(e["need"]), 0.0)) > 0.0:
					out.append(int(ix))
			"do":
				if (e["actions"] as Array).has(aid):
					out.append(int(ix))
	pack.ask_fixers[id] = out
	return out


## The factor on the scores of `fixers` for `p` now: 0 while their ask waits for the player,
## `ask_self_factor` while they deal with it, 1 without an ask.
static func fix_factor(pack: Pack, p: Person) -> float:
	if p.ask.is_empty():
		return 1.0
	return 0.0 if str(p.ask["phase"]) == "wait" else float(pack.cfg("ask_self_factor"))
