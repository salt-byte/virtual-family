class_name PetSystem
extends RefCounted
## Animals of the household (only with a pets.json and the pack's `pets` config). A kind in
## pets.json says what the animal is called, what it costs, how fast its needs drain, where
## it likes to be and what it does there (its own small action table), what it wishes for
## and what good it does while it is well kept (`perks`). The `pets` config names the needs
## every pet has (`needs`, like needs.json) and which of them is food, fondness, cleanliness
## and health (`food_need`, `love_need`, `clean_need`, `health_need`), plus the rules below.
##
## - A pet comes by `buy_pet` (its kind's `price`; a kind with a `perch` needs an object of
##   that type in the house first and does everything there), or as a stray at the gate: once
##   per game hour (once the house is lived in: `adopted_once`) with `stray_chance_per_hour`
##   a `stray` kind turns up (`world.pet_offer`)
##   and waits `stray_ttl_hours` for `answer_stray`. At most `max` pets live at home.
## - Its needs drain by its kind's `drains` per hour. People look after it with actions that
##   name a `pet` target (see `AutonomySystem`); the player can drag someone onto it or use an
##   item with a `pet` field on it.
## - At or below `run_below` food or fondness for `run_after_hours`, it runs away; children
##   (`grief`) are sad for a while. Away, it may come back by itself after
##   `come_back_after_hours` (`come_back_chance_per_hour`); after `gone_after_hours` it is
##   gone for good ("lost").
## - It falls ill with `illness_chance_per_day` (times `dirty_illness_factor` while its
##   cleanliness is below `dirty_below`); ill, its health drains `sick_drain_per_hour` until a
##   cure (an item or an action that `cures`) or death ("illness"). It dies of old age at its
##   lifespan. Pets age `age_rate` times as fast as people (their years are their own).
## - Well kept (`content`: at home, healthy, food and fondness at least `content_above`) it
##   cheers the people of `cheer.stages` and does its kind's `perks`: `guard` lengthens how
##   long things lie about before they are carried off, `save` gives back a share of a stock
##   whenever some is used up.
## - While the player is away nothing harsh happens: no running away (the clocks stand
##   still), no new strays, wishes or grief, and needs (health too) stay at least at
##   `offline_need_floor`. Ageing goes on, so a pet may die of old age.
## Dead and lost pets stay in `world.pets` (alive false) as the household's record.


static func enabled(pack: Pack) -> bool:
	if pack.pets.is_empty():
		return false
	var c = pack.cfg("pets")
	return c is Dictionary and (c as Dictionary).get("needs") is Array


static func cfg(pack: Pack) -> Dictionary:
	var c = pack.cfg("pets")
	return c if c is Dictionary else {}


## The `pets.needs` entries ([] with pets off).
static func need_list(pack: Pack) -> Array:
	var n = cfg(pack).get("needs", [])
	return n if n is Array else []


static func _num(c: Dictionary, key: String, d: float) -> float:
	var v = c.get(key, d)
	return float(v) if (v is int or v is float) else d


## The pet need playing `role` ("food_need", "love_need", "clean_need", "health_need"); "".
static func role(pack: Pack, which: String) -> String:
	return str(cfg(pack).get(which, ""))


static func kind_of(pack: Pack, pet: Pet) -> Dictionary:
	return pack.pets.get(pet.kind, {})


## The pet action with this id ({} when unknown), looked up over every kind.
static func action(pack: Pack, id: String) -> Dictionary:
	if pack.pet_actions.is_empty():
		for k in pack.pets.values():
			for a in k.get("actions", []):
				if a is Dictionary:
					pack.pet_actions[str(a.get("id", ""))] = a
	return pack.pet_actions.get(id, {})


static func find(world: World, uid: int) -> Pet:
	for p in world.pets:
		if p.uid == uid:
			return p
	return null


## How many pets live at home now.
static func at_home(world: World) -> int:
	var n := 0
	for p in world.pets:
		if p.home():
			n += 1
	return n


## The kinds of pet at home as ",kind,kind," (pets list order, each once), each need a pet
## of that kind has below `care_below` as "kind.need,", and "!" at the end while one of them
## is ill; "" when none is home. Care actions are filtered by it (see
## `AutonomySystem._pet_fits`): one that gives no need that is low now waits.
static func home_key(world: World) -> String:
	_cache(world)
	return world._pet_cache[2]


## Fills `world._pet_cache` for this step (pets only change between steps or by being added).
static func _cache(world: World) -> void:
	var c := world._pet_cache
	if c[0] == world.now and c[1] == world.pets.size():
		return
	c[0] = world.now
	c[1] = world.pets.size()
	c[2] = _home_key(world)
	c[3] = _room_now(world)


static func _home_key(world: World) -> String:
	var key := ""
	var ill := false
	var line := _num(cfg(world.pack), "care_below", 101.0)
	for p in world.pets:
		if p.home():
			if not key.contains("," + p.kind + ","):
				key += ("," if key == "" else "") + p.kind + ","
			for n in p.needs:
				var part: String = p.kind + "." + str(n) + ","
				if float(p.needs[n]) < line and not key.contains("," + part):
					key += part
			ill = ill or p.sick
	return key + ("!" if ill and key != "" else "")


## Pet need id -> the most any pet at home lacks of it (100 - its value), plus "" -> 1 so the
## result is never empty.
static func room_now(world: World) -> Dictionary:
	_cache(world)
	return world._pet_cache[3]


static func _room_now(world: World) -> Dictionary:
	var out := {"": 1.0}
	for p in world.pets:
		if p.home():
			for n in p.needs:
				out[n] = maxf(float(out.get(n, 0.0)), 100.0 - float(p.needs[n]))
	return out


## The most a care action giving `ids` by `gains` (curing, with `cures`) can score for any pet
## at home, by `room_now`: never below what `best_target` finds.
static func gain_bound(world: World, ids: Array[String], gains: Array[float], cures: bool, room: Dictionary) -> float:
	var g := 0.0
	for k in ids.size():
		var r := float(room.get(ids[k], 0.0))
		g += minf(gains[k], r) * r / 100.0
	if cures:
		g += _num(cfg(world.pack), "cure_gain", 50.0)
	return g


## True when a pet of `kind` lives at home.
static func has_kind(world: World, kind: String) -> bool:
	for p in world.pets:
		if p.home() and p.kind == kind:
			return true
	return false


## At home, healthy, and its food and fondness at least `content_above`.
static func content(world: World, pet: Pet) -> bool:
	if not pet.home() or pet.sick:
		return false
	var line := _num(cfg(world.pack), "content_above", 50.0)
	for w in ["food_need", "love_need"]:
		var n := role(world.pack, w)
		if n != "" and float(pet.needs.get(n, 0.0)) < line:
			return false
	return true


# --- arrival ---

## A new pet of `kind`, at home from now on; `how` is "bought" or "stray". `given` "" picks
## a name from the kind's `names` that no living pet has.
static func add(world: World, kind: String, how: String, given := "", age := -1.0) -> Pet:
	var k: Dictionary = world.pack.pets[kind]
	var p := Pet.new()
	p.uid = world.next_uid()
	p.kind = kind
	p.given = given if given != "" else _pick_name(world, k)
	p.age = age if age >= 0.0 else _range(world, k.get("age", [1, 2]))
	p.lifespan = _range(world, k.get("lifespan", [10, 14]))
	for n in need_list(world.pack):
		p.needs[str(n["id"])] = float(n.get("start", 80))
	p.how = how
	p.came_at = world.now
	world.pets.append(p)
	world.emit("pet_arrived", {"pet": p.uid, "how": how})
	return p


static func _pick_name(world: World, k: Dictionary) -> String:
	var names: Array = (k.get("names", []) as Array).filter(func(n):
		return not world.pets.any(func(q: Pet): return q.alive and q.given == str(n)))
	if names.is_empty():
		return str(k.get("name", ""))
	return str(world.rng.pick(names))


static func _range(world: World, r: Variant) -> float:
	if not r is Array or (r as Array).size() != 2:
		return 1.0
	return float(r[0]) + world.rng.randf() * (float(r[1]) - float(r[0]))


## "" when a pet of `kind` may come to live here now, else why not.
static func can_take(world: World, kind: String) -> String:
	if not enabled(world.pack) or not world.pack.pets.has(kind):
		return "no_pet_kind"
	if at_home(world) >= int(_num(cfg(world.pack), "max", 2.0)):
		return "too_many_pets"
	var perch := str(world.pack.pets[kind].get("perch", ""))
	if perch != "" and not world.objects.any(func(o): return o.type == perch):
		return "no_perch"
	return ""


## Command {type: "buy_pet", kind}.
static func buy(world: World, cmd: Dictionary) -> Dictionary:
	var kind := str(cmd.get("kind", ""))
	var why := can_take(world, kind)
	if why != "":
		return Commands.fail(why)
	var price := int(world.pack.pets[kind].get("price", 0))
	if price <= 0:
		return Commands.fail("no_pet_kind")
	if not EconomySystem.spend(world, price):
		return Commands.fail("no_money")
	var p := add(world, kind, "bought")
	return Commands.success({"pet": p.uid})


## Command {type: "answer_stray", accept}: take in the animal at the gate, or shoo it off.
static func answer_stray(world: World, cmd: Dictionary) -> Dictionary:
	if world.pet_offer.is_empty():
		return Commands.fail("no_stray")
	var offer := world.pet_offer
	if not bool(cmd.get("accept", false)):
		world.pet_offer = {}
		world.emit("stray_left", {"kind": str(offer["kind"])})
		return Commands.success()
	var why := can_take(world, str(offer["kind"]))
	if why != "":
		return Commands.fail(why)
	world.pet_offer = {}
	var p := add(world, str(offer["kind"]), "stray", str(offer["given"]), float(offer["age"]))
	return Commands.success({"pet": p.uid})


static func _stray(world: World, c: Dictionary) -> void:
	if not world.pet_offer.is_empty():
		if world.now >= int(world.pet_offer["expires_at"]):
			var kind := str(world.pet_offer["kind"])
			world.pet_offer = {}
			world.emit("stray_left", {"kind": kind})
		return
	if world.offline or not world.adopted_once or at_home(world) >= int(_num(c, "max", 2.0)):
		return
	var kinds: Array = []
	for id in world.pack.pets:
		if bool(world.pack.pets[id].get("stray", false)):
			kinds.append(str(id))
	if kinds.is_empty() or not world.rng.chance(_num(c, "stray_chance_per_hour", 0.0)):
		return
	var kind := str(world.rng.pick(kinds))
	var k: Dictionary = world.pack.pets[kind]
	world.pet_offer = {"kind": kind, "given": _pick_name(world, k),
		"age": _range(world, k.get("stray_age", k.get("age", [1, 2]))),
		"expires_at": world.now + int(_num(c, "stray_ttl_hours", 6.0) * 3600.0)}
	world.emit("stray_arrived", {"kind": kind})


# --- every step ---

static func step(world: World, dt: float) -> void:
	var hour_turned := world.now % 3600 < int(dt)
	if world.pets.is_empty() and not hour_turned:
		return  # nothing to do between the hourly looks for a stray
	var pack := world.pack
	if not enabled(pack):
		return
	var c := cfg(pack)
	if hour_turned:
		_stray(world, c)
	if world.pets.is_empty():
		return
	# Ageing, needs, illness, running off and wishes move once per game minute (on the step
	# that starts one, counting the whole minute); what the pet is doing moves every step.
	if world.now % 60 < int(dt):
		var md := maxf(dt, 60.0)
		var age_step := md / (float(pack.cfg("hours_per_year")) * 3600.0) * _num(c, "age_rate", 1.0)
		var health := role(pack, "health_need")
		var cheer := false
		for pet in world.pets:
			if not pet.alive:
				continue
			pet.age += age_step
			if pet.state == "away":
				_away_step(world, pet, c, hour_turned)
				continue
			if pet.age >= pet.lifespan:
				die(world, pet, "old_age")
				continue
			_needs_step(world, pet, c, md)
			if pet.sick and float(pet.needs.get(health, 100.0)) <= 0.0:
				die(world, pet, "illness")
				continue
			if _neglect_step(world, pet, c):
				continue
			if hour_turned:
				_wish_step(world, pet, c)
			elif not pet.wish.is_empty() and world.now >= int(pet.wish["expires_at"]):
				_wish_expire(world, pet, c)
			if not cheer and content(world, pet):
				cheer = true
		if cheer:
			_cheer(world, c, md)
		if world.pet_grief_until > world.now:
			_grieve(world, c, md)
	for pet in world.pets:
		if not pet.home():
			continue
		if pet.thanks_until > world.now or held(world, pet, null):
			pass  # showing its joy, or being looked after: it keeps still
		elif not pet.current.is_empty():
			_progress(world, pet, dt)
		else:
			_choose(world, pet)


## True when someone other than `except` is looking after `pet` right now (`held_by`,
## dropped once that person has moved on to something else).
static func held(world: World, pet: Pet, except: Person) -> bool:
	if pet.held_by < 0:
		return false
	var q := world.person(pet.held_by)
	if q == null or not q.alive or int(q.current.get("target_uid", -1)) != pet.uid:
		pet.held_by = -1
		return false
	return q != except


## Sets every pet's `held_by` from what people are doing (after loading a save).
static func rebuild_held(world: World) -> void:
	for q in world.people:
		var t := int(q.current.get("target_uid", -1))
		if not q.alive or t < 0:
			continue
		var pet := find(world, t)
		if pet != null and not (world.pack.actions.get(str(q.current["action"]), {}).get("pet", {}) as Dictionary).is_empty():
			pet.held_by = q.uid


static func _needs_step(world: World, pet: Pet, c: Dictionary, dt: float) -> void:
	var pack := world.pack
	var k := kind_of(pack, pet)
	var drains: Dictionary = k.get("drains", {})
	for n in drains:
		if pet.needs.has(n):
			pet.needs[n] = clampf(float(pet.needs[n]) - float(drains[n]) * dt / 3600.0, 0.0, 100.0)
	var health := role(pack, "health_need")
	if pet.sick:
		if health != "" and pet.needs.has(health):
			pet.needs[health] = clampf(float(pet.needs[health]) - _num(c, "sick_drain_per_hour", 3.0) * dt / 3600.0, 0.0, 100.0)
	else:
		if health != "" and pet.needs.has(health):
			pet.needs[health] = clampf(float(pet.needs[health]) + _num(c, "heal_per_hour", 2.0) * dt / 3600.0, 0.0, 100.0)
		var chance := _num(c, "illness_chance_per_day", 0.0) / 86400.0 * dt
		var clean := role(pack, "clean_need")
		if clean != "" and float(pet.needs.get(clean, 100.0)) < _num(c, "dirty_below", 30.0):
			chance *= _num(c, "dirty_illness_factor", 1.0)
		if chance > 0.0 and world.rng.chance(chance):
			pet.sick = true
			world.emit("pet_fell_ill", {"pet": pet.uid})
	if world.offline:
		var floor_v := float(pack.cfg("offline_need_floor"))
		for n in pet.needs:
			pet.needs[n] = maxf(float(pet.needs[n]), floor_v)


## Once a game minute: counts how long food and fondness have been at the run line and sends
## the pet off when one of them has been there `run_after_hours`. True when it ran away.
static func _neglect_step(world: World, pet: Pet, c: Dictionary) -> bool:
	if world.offline:
		return false  # the clocks stand still while the player is away
	var line := _num(c, "run_below", 10.0)
	var food := role(world.pack, "food_need")
	var love := role(world.pack, "love_need")
	pet.hungry_s = pet.hungry_s + 60 if food != "" and float(pet.needs.get(food, 100.0)) <= line else 0
	pet.lonely_s = pet.lonely_s + 60 if love != "" and float(pet.needs.get(love, 100.0)) <= line else 0
	var after := int(_num(c, "run_after_hours", 12.0) * 3600.0)
	if pet.hungry_s < after and pet.lonely_s < after:
		return false
	pet.state = "away"
	pet.away_since = world.now
	pet.current = {}
	pet.wish = {}
	pet.thanks_until = 0
	world.emit("pet_ran_away", {"pet": pet.uid, "hungry": pet.hungry_s >= after})
	_start_grief(world, c)
	return true


static func _away_step(world: World, pet: Pet, c: Dictionary, hour_turned: bool) -> void:
	var away := world.now - pet.away_since
	if pet.age >= pet.lifespan or away >= int(_num(c, "gone_after_hours", 96.0) * 3600.0):
		die(world, pet, "lost")
		return
	if not hour_turned or away < int(_num(c, "come_back_after_hours", 6.0) * 3600.0):
		return
	if world.rng.chance(_num(c, "come_back_chance_per_hour", 0.0)):
		pet.state = "home"
		pet.away_since = 0
		pet.hungry_s = 0
		pet.lonely_s = 0
		var back := _num(c, "come_back_at", 50.0)
		for w in ["food_need", "love_need"]:
			var n := role(world.pack, w)
			if n != "" and pet.needs.has(n):
				pet.needs[n] = maxf(float(pet.needs[n]), back)
		world.emit("pet_came_back", {"pet": pet.uid})


## Ends a pet's life (`cause`: "old_age", "illness", "lost"); it stays on the record.
static func die(world: World, pet: Pet, cause: String) -> void:
	if not pet.alive:
		return
	pet.alive = false
	pet.cause = cause
	pet.died_at = world.now
	pet.current = {}
	pet.wish = {}
	world.emit("pet_died", {"pet": pet.uid, "cause": cause})
	if cause != "lost":
		_start_grief(world, cfg(world.pack))


static func _start_grief(world: World, c: Dictionary) -> void:
	if world.offline:
		return
	var g = c.get("grief", {})
	if not g is Dictionary or (g as Dictionary).is_empty():
		return
	var need := str(g.get("need", ""))
	var stages: Array = g.get("stages", [])
	for p in world.people:
		if p.alive and p.needs.has(need) and (stages.is_empty() or stages.has(p.stage(world.pack))):
			p.needs[need] = clampf(float(p.needs[need]) - _num(g, "now", 0.0), 0.0, 100.0)
	world.pet_grief_until = world.now + int(_num(g, "hours", 0.0) * 3600.0)


static func _grieve(world: World, c: Dictionary, dt: float) -> void:
	var g = c.get("grief", {})
	if not g is Dictionary:
		return
	_shift(world, g, -_num(g, "per_hour", 0.0) * dt / 3600.0)


static func _cheer(world: World, c: Dictionary, dt: float) -> void:
	var ch = c.get("cheer", {})
	if not ch is Dictionary or (ch as Dictionary).is_empty():
		return
	_shift(world, ch, _num(ch, "per_hour", 0.0) * dt / 3600.0)


## Moves `g.need` of the living people of `g.stages` by `by`.
static func _shift(world: World, g: Dictionary, by: float) -> void:
	if by == 0.0:
		return
	var need := str(g.get("need", ""))
	var stages: Array = g.get("stages", [])
	var floor_v := float(world.pack.cfg("offline_need_floor"))
	for p in world.people:
		if not p.alive or not p.needs.has(need):
			continue
		if not stages.is_empty() and not stages.has(p.stage(world.pack)):
			continue
		var v := clampf(float(p.needs[need]) + by, 0.0, 100.0)
		if world.offline and by < 0.0:
			v = maxf(v, minf(floor_v, float(p.needs[need])))
		p.needs[need] = v


# --- the pet's own doings ---

## The rooms `a` may happen in that are built ([] for none or when it names none).
static func _rooms_for(world: World, a: Dictionary) -> Array:
	var rooms: Array = a.get("rooms", [])
	return rooms.filter(func(r): return world.rooms_built.has(r))


## The first object of `type` in the house ({} for none).
static func _object_of(world: World, type: String) -> Dictionary:
	for o in world.objects:
		if o.type == type:
			return o
	return {}


## The object an action of this pet happens at: the action's own `object`, else its kind's
## `perch` when the action names no rooms ("" when neither).
static func _object_type(pet_kind: Dictionary, a: Dictionary) -> String:
	var t := str(a.get("object", ""))
	if t == "" and (a.get("rooms", []) as Array).is_empty() and str(a.get("follows", "")) == "" \
			and str(a.get("scraps", "")) == "":
		t = str(pet_kind.get("perch", ""))
	return t


## What `pet` could start now: [[action, score, extra]] where extra holds the place.
static func _options(world: World, pet: Pet) -> Array:
	var out: Array = []
	var k := kind_of(world.pack, pet)
	var hour := world.local_hour()
	for a in k.get("actions", []):
		var sick_only := bool(a.get("sick", false))
		if sick_only != pet.sick:
			continue
		var hours: Array = a.get("hours", [])
		if not hours.is_empty() and not AutonomySystem._in_hours(hour, hours):
			continue
		var wx: Array = a.get("weather", [])
		if not wx.is_empty() and not wx.has(world.weather):
			continue
		if bool(a.get("wet", false)) and not WeatherSystem.wet(world):
			continue
		var above: Dictionary = a.get("above", {})
		var low := false
		for n in above:
			if float(pet.needs.get(n, 0.0)) < float(above[n]):
				low = true
		if low:
			continue
		var every := float(a.get("every_hours", 0))
		if every > 0.0 and pet.done_at.has(str(a["id"])) and world.now - int(pet.done_at[str(a["id"])]) < int(every * 3600.0):
			continue
		var extra := {}
		var type := _object_type(k, a)
		if type != "":
			var o := _object_of(world, type)
			if o.is_empty():
				continue
			extra["object_uid"] = int(o.uid)
		elif not (a.get("rooms", []) as Array).is_empty():
			var built := _rooms_for(world, a)
			if built.is_empty():
				continue
			extra["rooms"] = built
		var follows := str(a.get("follows", ""))
		if follows != "":
			var who: Array = world.people.filter(func(q: Person): return q.alive and q.stage(world.pack) == follows)
			if who.is_empty():
				continue
			extra["follow"] = who
		var scraps := str(a.get("scraps", ""))
		if scraps != "":
			var m := -1
			for ms in world.messes:
				if ms.type == scraps and not ms.get("licked", false):
					m = int(ms.uid)
					break
			if m < 0:
				continue
			extra["mess"] = m
		var gain := 0.0
		var needs: Dictionary = a.get("needs", {})
		for n in needs:
			if pet.needs.has(n) and float(needs[n]) > 0.0:
				var room := 100.0 - float(pet.needs[n])
				gain += minf(float(needs[n]), room) * room / 100.0
		var s := float(a.get("base", 1)) + gain
		if str(a.get("id", "")) == pet.last_action:
			s *= 0.2
		if s > 0.0:
			out.append([a, s, extra])
	return out


static func _choose(world: World, pet: Pet) -> void:
	var opts := _options(world, pet)
	if opts.is_empty():
		return
	var weights: Array = opts.map(func(o): return o[1])
	var pick: Array = world.rng.weighted_pick(opts, weights)
	var a: Dictionary = pick[0]
	var extra: Dictionary = pick[2]
	pet.current = {"action": str(a["id"]), "remaining_s": duration_s(world, a)}
	if extra.has("object_uid"):
		pet.current["object_uid"] = int(extra["object_uid"])
	if extra.has("rooms"):
		pet.current["room"] = str(world.rng.pick(extra["rooms"]))
	if extra.has("follow"):
		pet.current["follow"] = int((world.rng.pick(extra["follow"]) as Person).uid)
	if extra.has("mess"):
		pet.current["mess"] = int(extra["mess"])


## Real seconds a pet's action takes: `duration_min` on the pets' own fast clock
## (`pets.action_speed`, else the pack's `action_speed`), in whole steps (at least one).
static func duration_s(world: World, a: Dictionary) -> int:
	var speed := _num(cfg(world.pack), "action_speed", float(world.pack.cfg("action_speed")))
	var s := ceili(float(a["duration_min"]) * 60.0 / maxf(speed, 1.0) - 1e-9)
	return maxi(ceili(float(s) / world.step_s), 1) * world.step_s


static func _progress(world: World, pet: Pet, dt: float) -> void:
	var cur := pet.current
	var rem := int(cur["remaining_s"]) - int(dt)
	cur["remaining_s"] = rem
	var done := rem <= 0
	if not done and cur.has("follow"):
		var q := world.person(int(cur["follow"]))
		done = q == null or not q.alive
	if not done:
		return
	var a := action(world.pack, str(cur.get("action", "")))
	if a.is_empty():
		pet.current = {}
	else:
		_finish(world, pet, a)


static func _finish(world: World, pet: Pet, a: Dictionary) -> void:
	var needs: Dictionary = a.get("needs", {})
	var mess_uid := int(pet.current.get("mess", -1))
	if mess_uid >= 0:
		var m := MessSystem.find(world, mess_uid)
		if m.is_empty() or m.get("licked", false):
			needs = {}  # someone cleared it away first, or another pet got there
		else:
			m["licked"] = true
	for n in needs:
		if pet.needs.has(n):
			pet.needs[n] = clampf(float(pet.needs[n]) + float(needs[n]), 0.0, 100.0)
	var mess: Dictionary = a.get("mess", {})
	if not mess.is_empty() and world.rng.chance(_num(mess, "chance", 0.0)):
		MessSystem.spawn(world, str(mess.get("type", "")), room_of(world, pet))
	var id := str(a["id"])
	pet.current = {}
	pet.last_action = id
	if float(a.get("every_hours", 0)) > 0.0:
		pet.done_at[id] = world.now
	_wish_by_action(world, pet, id)


## The room the pet is in by what it is doing ("" when it is idle about the house).
static func room_of(world: World, pet: Pet) -> String:
	if pet.current.has("room"):
		return str(pet.current["room"])
	if pet.current.has("object_uid"):
		return str(world.object(int(pet.current["object_uid"])).get("room", ""))
	if pet.current.has("mess"):
		return str(MessSystem.find(world, int(pet.current["mess"])).get("room", ""))
	return ""


# --- wishes ---

static func _wish_step(world: World, pet: Pet, c: Dictionary) -> void:
	if not pet.wish.is_empty():
		if world.now >= int(pet.wish["expires_at"]):
			_wish_expire(world, pet, c)
		return
	if world.offline or pet.sick:
		return
	var ws: Array = kind_of(world.pack, pet).get("wishes", [])
	var pool: Array = ws.filter(func(w): return str(w.get("id", "")) != pet.wish_last)
	if pool.is_empty() or not world.rng.chance(_num(c, "wish_chance_per_hour", 0.0)):
		return
	var w: Dictionary = world.rng.pick(pool)
	pet.wish = {"id": str(w["id"]), "expires_at": world.now + int(_num(w, "ttl_hours", 8.0) * 3600.0)}
	world.emit("pet_wish_formed", {"pet": pet.uid, "wish": str(w["id"])})


static func _wish_expire(world: World, pet: Pet, c: Dictionary) -> void:
	var id := str(pet.wish["id"])
	pet.wish = {}
	pet.wish_last = id
	var love := role(world.pack, "love_need")
	if not world.offline and love != "" and pet.needs.has(love):
		pet.needs[love] = clampf(float(pet.needs[love]) - _num(c, "wish_miss", 0.0), 0.0, 100.0)
	world.emit("pet_wish_expired", {"pet": pet.uid, "wish": id})


## The wish entry `pet` holds now ({} for none).
static func wish_of(world: World, pet: Pet) -> Dictionary:
	if pet.wish.is_empty():
		return {}
	for w in kind_of(world.pack, pet).get("wishes", []):
		if str(w.get("id", "")) == str(pet.wish["id"]):
			return w
	return {}


static func _grant(world: World, pet: Pet) -> void:
	var w := wish_of(world, pet)
	var id := str(pet.wish.get("id", ""))
	pet.wish = {}
	pet.wish_last = id
	var love := role(world.pack, "love_need")
	if love != "" and pet.needs.has(love):
		pet.needs[love] = clampf(float(pet.needs[love]) + _num(w, "joy", 0.0), 0.0, 100.0)
	pet.thanks_until = world.now + WishSystem.thanks_seconds(world)
	pet.current = {}
	world.emit("pet_wish_granted", {"pet": pet.uid, "wish": id})


static func _wish_by_action(world: World, pet: Pet, action_id: String) -> void:
	var w := wish_of(world, pet)
	if not w.is_empty() and (w.get("actions", []) as Array).has(action_id):
		_grant(world, pet)


# --- people looking after pets ---

## The gain `best_target` found for its pick (read right after the call).
static var target_gain := 0.0


## For a care action that names `kinds` (any kind when empty) and gives the pet needs `ids`
## by `gains` (and cures it, with `cures`): of the pets at home nobody else is looking after,
## the one that lacks most of what it gives (the first on a tie); -1 for none. Sets
## `target_gain`, scored like a need gain (a cure adds the pack's `cure_gain`).
static func best_target(world: World, kinds: Array, ids: Array[String], gains: Array[float], cures: bool, p: Person) -> int:
	var best := -1
	var best_gain := -1.0
	for pet in world.pets:
		if not pet.home():
			continue
		if not kinds.is_empty() and not kinds.has(pet.kind):
			continue
		if cures and not pet.sick:
			continue
		if held(world, pet, p):
			continue
		var g := _gain_for(pet, ids, gains)
		if cures:
			g += _num(cfg(world.pack), "cure_gain", 50.0)
		if g > best_gain:
			best_gain = g
			best = pet.uid
	target_gain = maxf(best_gain, 0.0)
	return best


static func _gain_for(pet: Pet, ids: Array[String], gains: Array[float]) -> float:
	var g := 0.0
	for k in ids.size():
		var nv = pet.needs.get(ids[k])
		if nv != null:
			var room := 100.0 - float(nv)
			g += minf(gains[k], room) * room / 100.0
	return g


## `best_target` for an action's `pet` field.
static func target_for(world: World, a: Dictionary, p: Person) -> int:
	var t: Dictionary = a.get("pet", {})
	var ids: Array[String] = []
	var gains: Array[float] = []
	var needs: Dictionary = t.get("needs", {})
	for n in needs:
		ids.append(str(n))
		gains.append(maxf(float(needs[n]), 0.0))
	return best_target(world, t.get("kinds", []), ids, gains, bool(t.get("cures", false)), p)


## Whether the care action `a` suits this pet (kind, and sickness for a cure).
static func suits(a: Dictionary, pet: Pet) -> bool:
	var t: Dictionary = a.get("pet", {})
	var kinds: Array = t.get("kinds", [])
	if not kinds.is_empty() and not kinds.has(pet.kind):
		return false
	return pet.home() and (not bool(t.get("cures", false)) or pet.sick)


## Person `by` starts looking after the pet: it stops what it was doing.
static func on_tended(world: World, uid: int, by: int) -> void:
	var pet := find(world, uid)
	if pet != null:
		pet.current = {}
		pet.held_by = by


## A care action finished: its `pet.needs` go to the pet, a cure cures it, and a wish for
## that action comes true.
static func cared(world: World, p: Person, uid: int, action_id: String) -> void:
	var pet := find(world, uid)
	if pet == null or not pet.home():
		return
	var t: Dictionary = world.pack.actions.get(action_id, {}).get("pet", {})
	_apply(world, pet, t)
	world.emit("pet_cared", {"pet": pet.uid, "person": p.uid, "action": action_id})
	_wish_by_action(world, pet, action_id)


## Adds `t.needs` to the pet and, with `t.cures`, makes it well.
static func _apply(world: World, pet: Pet, t: Dictionary) -> void:
	var needs: Dictionary = t.get("needs", {})
	for n in needs:
		if pet.needs.has(n):
			pet.needs[n] = clampf(float(pet.needs[n]) + float(needs[n]), 0.0, 100.0)
	if bool(t.get("cures", false)) and pet.sick:
		pet.sick = false
		world.emit("pet_cured", {"pet": pet.uid})


## Command {type: "use_item", item, pet}: an item with a `pet` field used on a pet at home.
static func use_item(world: World, cmd: Dictionary) -> Dictionary:
	var id := str(cmd.get("item", ""))
	if int(world.inventory.get(id, 0)) < 1:
		return Commands.fail("no_item")
	var pet := find(world, int(cmd.get("pet", -1)))
	if pet == null or not pet.home():
		return Commands.fail("no_pet")
	var t = world.pack.items[id].get("pet", {})
	if not t is Dictionary or (t as Dictionary).is_empty():
		return Commands.fail("not_for_pet")
	var kinds: Array = t.get("kinds", [])
	if not kinds.is_empty() and not kinds.has(pet.kind):
		return Commands.fail("wrong_pet")
	world.inventory[id] = int(world.inventory[id]) - 1
	_apply(world, pet, t)
	var w := wish_of(world, pet)
	if str(w.get("item", "")) == id:
		_grant(world, pet)
	return Commands.success()


# --- what a well-kept pet does for the house ---

## The factor on how long things lie about before they are carried off: the highest `guard`
## perk of a content pet (1 without one).
static func guard_factor(world: World) -> float:
	var f := 1.0
	for pet in world.pets:
		var g = kind_of(world.pack, pet).get("perks", {}).get("guard")
		if (g is int or g is float) and float(g) > f and content(world, pet):
			f = float(g)
	return f


## `n` of `stock` were just used up: a content pet with a `save` perk for it gives back its
## share (the fractions add up across uses, so no randomness is drawn).
static func on_consumed(world: World, stock: String, n: int) -> void:
	var share := 0.0
	var by := -1
	for pet in world.pets:
		var s = kind_of(world.pack, pet).get("perks", {}).get("save", {})
		if s is Dictionary and s.has(stock) and float(s[stock]) > share and content(world, pet):
			share = float(s[stock])
			by = pet.uid
	if share <= 0.0:
		return
	var acc := float(world.pet_saved.get(stock, 0.0)) + share * float(n)
	while acc >= 1.0:
		acc -= 1.0
		world.stock[stock] = int(world.stock.get(stock, 0)) + 1
		world.emit("pet_saved", {"pet": by, "stock": stock})
	world.pet_saved[stock] = acc
