class_name WishSystem
extends RefCounted
## Wishes (a pack's optional wishes.json): each person holds at most one. A wish names what
## would please them; the player grants it, and the person's praise need rises by the wish's
## `joy` while they stop to thank the player. Kinds:
## - "item": the player uses that shop item on them (`use_item`)
## - "object": the household owns an object of that type
## - "room": that room is built
## - "praise": the player praises them
## - "married": they marry (only whom the next proposal would be for may wish it)
## - "baby": a child is born to them (only a married grown-up who could have one now)
## - "pet": an animal of that kind (`pet`) lives in the house
## - "need": a body wish, formed when that need falls below `below` and granted once it is
##   back above `above`; it takes the place of any other wish
## - "do": they finish one of the wished `actions` themselves (going to the market, setting
##   off firecrackers); while they hold it those actions score `wish_do_factor` times higher
##   for them, and it does not run out while they are doing one
## A wish that names a `festival` is only formed while that festival is on (see
## `FestivalSystem`, which also hands them out when it begins) and ends with it, unpenalised.
## A mood wish that runs out (`ttl_hours`) costs `wish_miss_penalty` of the praise need; a
## body wish just ends. Babies and the depressed form no wishes, and nobody forms one while
## the player is away. A pack without wishes draws no randomness here.

const KINDS := ["item", "object", "room", "praise", "need", "married", "baby", "pet", "do"]


## Runs once per game minute (on the step that starts one); granting by item or praise
## happens at once through the commands.
static func step(world: World, dt: float) -> void:
	if world.now % 60 >= int(dt):
		return
	var pack := world.pack
	if pack.wishes.is_empty():
		return
	# The looks at forming a wish: mood wishes every `wish_check_min`, body wishes every
	# `need_wish_check_min` (both 60 by default: at the turn of each hour).
	var mood_look := _turned(world, dt, int(pack.cfg("wish_check_min")))
	var body_look := _turned(world, dt, int(pack.cfg("need_wish_check_min")))
	for p in world.people:
		if not p.alive:
			continue
		if not p.wish.is_empty():
			var w: Dictionary = pack.wishes.get(str(p.wish["id"]), {})
			if w.is_empty():
				p.wish = {}
			elif _met(world, p, w):
				grant(world, p)
				continue
			elif str(w["festival"]) != "" and str(w["festival"]) != world.festival:
				_expire(world, p, w, false)
			elif world.now >= int(p.wish["expires_at"]) and not _doing_wished(p, w):
				_expire(world, p, w)
		if (mood_look or body_look) and not world.offline:
			_maybe_form(world, p, body_look, mood_look)


## True on the step that starts a new span of `minutes` game minutes.
static func _turned(world: World, dt: float, minutes: int) -> bool:
	return world.now % (maxi(minutes, 1) * 60) < maxi(int(dt), 60)


## Whether a wish of a kind that is checked by looking at the world holds now.
static func _met(world: World, p: Person, w: Dictionary) -> bool:
	match str(w["kind"]):
		"need":
			return float(p.needs.get(str(w["need"]), 0.0)) >= float(w["above"])
		"object":
			var type := str(w["object"])
			return world.objects.any(func(o): return o.type == type)
		"room":
			return world.rooms_built.has(str(w["room"]))
		"pet":
			return PetSystem.has_kind(world, str(w["pet"]))
	return false


## True while `p` is doing one of the actions their "do" wish `w` asks for.
static func _doing_wished(p: Person, w: Dictionary) -> bool:
	return not p.current.is_empty() and (w["actions"] as Array).has(str(p.current["action"]))


static func _expire(world: World, p: Person, w: Dictionary, penalty := true) -> void:
	var id := str(p.wish["id"])
	p.wish = {}
	p.wish_last = id
	if penalty and str(w["kind"]) != "need" and not world.offline:
		_add_mood(world, p, -float(world.pack.cfg("wish_miss_penalty")))
	world.emit("wish_expired", {"person": p.uid, "wish": id})


static func _add_mood(world: World, p: Person, amount: float) -> void:
	var need := str(world.pack.cfg("praise_need"))
	if need != "" and p.needs.has(need):
		p.needs[need] = clampf(float(p.needs[need]) + amount, 0.0, 100.0)


## Grants `p`'s wish: the praise need rises by its `joy` and they stop to thank the player.
static func grant(world: World, p: Person) -> void:
	if p.wish.is_empty():
		return
	var id := str(p.wish["id"])
	var w: Dictionary = world.pack.wishes.get(id, {})
	p.wish = {}
	p.wish_last = id
	_add_mood(world, p, float(w.get("joy", 0.0)))
	p.thanks_until = world.now + thanks_seconds(world)
	p.share = {}  # the wave is a thank-you now, not news of earnings
	MoodSystem.cared(world, p)
	world.emit("wish_granted", {"person": p.uid, "wish": id})


## How long the thanks lasts in real seconds: `wish_thanks_min` on the fast action clock,
## rounded up to whole steps (at least one).
static func thanks_seconds(world: World) -> int:
	var full := float(world.pack.cfg("wish_thanks_min")) * 60.0 / float(world.pack.cfg("action_speed"))
	return maxi(ceili(full / world.step_s - 1e-9), 1) * world.step_s


## The player used `item` on `p` (successfully): grants an item wish for it.
static func on_item_used(world: World, p: Person, item: String) -> void:
	if _wants(world, p, "item", "item", item):
		grant(world, p)


## `p` just married: grants a "married" wish.
static func on_married(world: World, p: Person) -> void:
	if p != null and _wants(world, p, "married", "", ""):
		grant(world, p)


## A child was just born to `p`: grants a "baby" wish.
static func on_birth(world: World, p: Person) -> void:
	if p != null and _wants(world, p, "baby", "", ""):
		grant(world, p)


## `p` finished action `action_id`: grants a "do" wish that asks for it.
static func on_action_finished(world: World, p: Person, action_id: String) -> void:
	var w := current(world, p)
	if str(w.get("kind", "")) == "do" and (w["actions"] as Array).has(action_id):
		grant(world, p)


## The actions `p`'s wish asks them to do ([] unless it is a "do" wish).
static func wished_actions(world: World, p: Person) -> Array:
	var w: Dictionary = world.pack.wishes.get(str(p.wish.get("id", "")), {})
	return w["actions"] if str(w.get("kind", "")) == "do" else []


## Festival `fid` began: everyone without a wish who could form one forms one of its
## wishes with chance `wish_chance` (not babies, the depressed, those asleep, nor while the
## player is away).
static func start_festival(world: World, fid: String) -> void:
	if world.offline or world.pack.wishes.is_empty():
		return
	var chance := float(world.pack.festivals[fid].get("wish_chance", 0.0))
	for p in world.people:
		if not p.alive or not p.wish.is_empty() or p.stage(world.pack) == "baby" or p.mood == "depressed":
			continue
		if not p.current.is_empty() and bool(world.pack.actions[p.current["action"]].get("slow", false)):
			continue
		var pool := _eligible(world, p, false, fid)
		if pool.is_empty() or not world.rng.chance(chance):
			continue
		_form(world, p, pool)


## Festival `fid` is over: the wishes that named it end, unpenalised.
static func end_festival(world: World, fid: String) -> void:
	for p in world.people:
		var w := current(world, p)
		if p.alive and not w.is_empty() and str(w["festival"]) == fid:
			_expire(world, p, w, false)


## The player praised `p`: grants a praise wish.
static func on_praised(world: World, p: Person) -> void:
	if _wants(world, p, "praise", "", ""):
		grant(world, p)


static func _wants(world: World, p: Person, kind: String, key: String, value: String) -> bool:
	if p.wish.is_empty():
		return false
	var w: Dictionary = world.pack.wishes.get(str(p.wish["id"]), {})
	return str(w.get("kind", "")) == kind and (key == "" or str(w.get(key, "")) == value)


## The wish `p` holds right now as its pack entry, or {}.
static func current(world: World, p: Person) -> Dictionary:
	if p.wish.is_empty():
		return {}
	return world.pack.wishes.get(str(p.wish["id"]), {})


## `body`: look for a body wish; `mood`: look for a mood wish (the chance per hour scaled
## to `wish_check_min`).
static func _maybe_form(world: World, p: Person, body_look := true, mood_look := true) -> void:
	var pack := world.pack
	if p.stage(pack) == "baby" or p.mood == "depressed":
		return
	var held := current(world, p)
	if str(held.get("kind", "")) == "need":
		return
	# A body wish comes first, also in place of a mood wish.
	if body_look:
		var body := _eligible(world, p, true)
		if not body.is_empty():
			_form(world, p, body)
			return
	if not held.is_empty() or not mood_look:
		return
	var look := float(pack.cfg("wish_check_min")) / 60.0
	if not world.rng.chance(float(pack.cfg("wish_chance_per_hour")) * look):
		return
	var mood := _eligible(world, p, false)
	if not mood.is_empty():
		_form(world, p, mood)


## [ids, weights] of the wishes `p` could form now: body wishes (`body`) or the others;
## with `only_festival`, just the wishes of that festival.
static func _eligible(world: World, p: Person, body: bool, only_festival := "") -> Array:
	var ids: Array = []
	var weights: Array = []
	var stage := p.stage(world.pack)
	for id in world.pack.wishes:
		var w: Dictionary = world.pack.wishes[id]
		var kind := str(w["kind"])
		var fest := str(w["festival"])
		# The same wish twice running is passed over, except a festival's: that comes round
		# again only a year later.
		if (kind == "need") != body or (not body and id == p.wish_last and fest == ""):
			continue
		if (fest != "" and fest != world.festival) or (only_festival != "" and fest != only_festival):
			continue
		var stages: Array = w["stages"]
		if not stages.is_empty() and not stages.has(stage):
			continue
		var weight := float(w["weight"])
		var disliked := false
		for t in w["likes"]:
			if p.dislikes.has(t):
				disliked = true
			elif p.likes.has(t):
				weight *= 2.0
		if disliked or weight <= 0.0:
			continue
		match kind:
			"need":
				if float(p.needs.get(str(w["need"]), 100.0)) >= float(w["below"]):
					continue
			"object", "room", "pet":
				if _met(world, p, w):
					continue
			"married":
				if FamilySystem.proposal_target(world) != p:
					continue
			"baby":
				if not BirthSystem.could_want_child(world, p):
					continue
		ids.append(id)
		weights.append(weight)
	return [] if ids.is_empty() else [ids, weights]


static func _form(world: World, p: Person, pool: Array) -> void:
	var id := str(world.rng.weighted_pick(pool[0], pool[1]))
	var w: Dictionary = world.pack.wishes[id]
	p.wish = {"id": id, "expires_at": world.now + int(float(w["ttl_hours"]) * 3600.0)}
	world.emit("wish_formed", {"person": p.uid, "wish": id})
