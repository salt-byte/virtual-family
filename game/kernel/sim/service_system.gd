class_name ServiceSystem
extends RefCounted
## Services and upgrades sold at the market (optional services.json). Every entry has a
## `kind`, a `name` and a `price`; `requires` ({object: type}) keeps it off the counter until
## the house has such an object. Kinds:
##
## - "adopt": another person joins the household. Buying it (free) puts a candidate on offer
##   (`world.candidate`, made like the first adoptee, aged `age` or the pack's `adopt_age`);
##   the `adopt` command takes them in and pays `price` + `price_step` x (people adopted this
##   way so far); `reroll` shows someone else, `dismiss_candidate` sends them off. Not while
##   `max_people` (0: no limit) are alive. The newcomer takes the household's family name.
## - "speed": the clock runs `factor` times as fast for `hours` of real time (bought again it
##   adds up, to at most `max_hours` ahead). See `World.sync`: the sim clock runs ahead of
##   the real one by `world.clock_lead`; absences are replayed at the same pace while it
##   lasts, under the same `offline_cap_hours` of game time.
## - "yield" (once): every action that yields a stock named in `bonus` yields that much more.
## - "drops" (once): things to pick up (and story fragments) turn up `factor` times as often.
## - "lottery": a ticket, drawn `draw_hours` of game time later with `world.rng`: the first
##   of `prizes` ([{chance, amount}], each tried in turn on one roll) whose cumulative chance
##   covers the roll wins its amount, else nothing. The winnings are paid when it is drawn; the
##   ticket stays in `world.tickets` until the player opens it (`open_ticket`). At most
##   `max_tickets` wait to be drawn.
## - "helper": a hired hand for `days` days (bought again it adds up, to at most `max_days`
##   ahead). At each local hour in `hours` while hired, every mess in the house is cleared
##   and, when `cooks` names a dish that may be served and the stock holds what `consumes`
##   asks, that dish is put out.
##
## world.services_bought: service id -> times bought (adoptions: people taken in).

const KINDS := ["adopt", "speed", "yield", "drops", "lottery", "helper"]
const ONCE := ["yield", "drops"]


static func enabled(pack: Pack) -> bool:
	return not pack.services.is_empty()


static func times(world: World, id: String) -> int:
	return int(world.services_bought.get(id, 0))


## What buying service `id` costs now.
static func price(world: World, id: String) -> int:
	var sv: Dictionary = world.pack.services.get(id, {})
	if sv.is_empty():
		return 0
	var p := int(sv["price"])
	if str(sv["kind"]) == "adopt":
		p += int(sv["price_step"]) * times(world, id)
	return p


## The sim clock as the real clock would show it.
static func real_now(world: World) -> float:
	return float(world.now) + world._acc - float(world.clock_lead)


## "" when service `id` can be bought now, else why not (see `MarketSystem.catalogue`).
static func why_not(world: World, id: String) -> String:
	var sv: Dictionary = world.pack.services.get(id, {})
	if sv.is_empty():
		return "no_service"
	var kind := str(sv["kind"])
	var req: Dictionary = sv["requires"]
	if req.has("object") and not world.objects.any(func(o): return o.type == str(req["object"])):
		return "needs_object"
	if kind in ONCE and times(world, id) > 0:
		return "owned"
	match kind:
		"adopt":
			if not world.candidate.is_empty():
				return "pending"
			var cap := int(sv.get("max_people", 0))
			if cap > 0 and world.people.filter(func(p: Person): return p.alive).size() >= cap:
				return "full"
		"speed":
			var left := float(world.speed_until) - real_now(world)
			if left + float(sv["hours"]) * 3600.0 > float(sv.get("max_hours", sv["hours"])) * 3600.0 + 0.5:
				return "max"
		"lottery":
			if world.tickets.filter(func(t): return int(t.amount) < 0).size() >= int(sv.get("max_tickets", 1)):
				return "max"
		"helper":
			var ahead := float(world.helper_until - world.now) / 86400.0
			if maxf(ahead, 0.0) + float(sv["days"]) > float(sv.get("max_days", sv["days"])) + 0.0001:
				return "max"
	if world.money < price(world, id):
		return "no_money"
	return ""


## Command {type: "buy_service", service}.
static func buy(world: World, cmd: Dictionary) -> Dictionary:
	var id := str(cmd.get("service", ""))
	var why := why_not(world, id)
	if why != "":
		return Commands.fail(why)
	var sv: Dictionary = world.pack.services[id]
	var kind := str(sv["kind"])
	if kind == "adopt":  # paid when the candidate is taken in
		world.adopt_service = id
		_new_candidate(world)
		return Commands.success()
	if not EconomySystem.spend(world, price(world, id)):
		return Commands.fail("no_money")
	world.services_bought[id] = times(world, id) + 1
	var out := {}
	match kind:
		"speed":
			var start := maxf(float(world.speed_until), ceilf(real_now(world)))
			world.speed_until = int(start) + int(float(sv["hours"]) * 3600.0)
			world.speed_factor = float(sv["factor"])
			out["until"] = world.speed_until
		"lottery":
			var t := {"id": world.ticket_next, "service": id, "draw_at": world.now + int(float(sv["draw_hours"]) * 3600.0), "amount": -1}
			world.ticket_next += 1
			world.tickets.append(t)
			out["ticket"] = int(t.id)
		"helper":
			world.helper_until = maxi(world.helper_until, world.now) + int(float(sv["days"]) * 86400.0)
			world.helper_service = id
			out["until"] = world.helper_until
	world.emit("service_bought", {"service": id})
	return Commands.success(out)


static func _new_candidate(world: World) -> void:
	var sv: Dictionary = world.pack.services[world.adopt_service]
	var age = sv.get("age", world.pack.cfg("adopt_age"))
	world.candidate = FamilySystem.make_person(world, age).to_dict()


## `reroll` while living: someone else is on offer.
static func reroll_candidate(world: World) -> Dictionary:
	if world.candidate.is_empty() or not world.pack.services.has(world.adopt_service):
		return Commands.fail("no_candidate")
	_new_candidate(world)
	return Commands.success()


## Command {type: "dismiss_candidate"}: the one on offer goes away; nothing is paid.
static func dismiss_candidate(world: World, _cmd: Dictionary) -> Dictionary:
	if world.candidate.is_empty() or world.phase != "living":
		return Commands.fail("no_candidate")
	world.candidate = {}
	world.adopt_service = ""
	return Commands.success()


## `adopt` while living: pays and takes the candidate in.
static func adopt_candidate(world: World) -> Dictionary:
	var id := world.adopt_service
	if world.candidate.is_empty() or not world.pack.services.has(id):
		return Commands.fail("no_candidate")
	var sv: Dictionary = world.pack.services[id]
	var cap := int(sv.get("max_people", 0))
	if cap > 0 and world.people.filter(func(q: Person): return q.alive).size() >= cap:
		return Commands.fail("full")
	if not EconomySystem.spend(world, price(world, id)):
		return Commands.fail("no_money")
	var p := Person.from_dict(world.candidate)
	var head: Person = null
	for q in world.people:
		if q.alive and q.stage(world.pack) in ["adult", "elder"]:
			head = q
			break
	if head != null:
		p.family = head.family
		p.generation = head.generation + (1 if p.stage(world.pack) in ["baby", "child"] else 0)
	world.add_person(p)
	world.candidate = {}
	world.adopt_service = ""
	world.services_bought[id] = times(world, id) + 1
	MoodSystem.cared(world, p)
	world.emit("adopted", {"person": p.uid, "service": id})
	return Commands.success({"person": p.uid})


## Command {type: "open_ticket", ticket}: the player looks at a drawn ticket; it is then put
## away. Returns {amount}.
static func open_ticket(world: World, cmd: Dictionary) -> Dictionary:
	var id := int(cmd.get("ticket", -1))
	for i in world.tickets.size():
		var t: Dictionary = world.tickets[i]
		if int(t.id) != id:
			continue
		if int(t.amount) < 0:
			return Commands.fail("not_drawn")
		world.tickets.remove_at(i)
		return Commands.success({"amount": int(t.amount)})
	return Commands.fail("no_ticket")


## How many extra units of `stock` an action that yields it gives (upgrades bought).
static func yield_bonus(world: World, stock: String) -> int:
	if world.services_bought.is_empty():
		return 0
	var n := 0
	for id in world.services_bought:
		var sv: Dictionary = world.pack.services.get(id, {})
		if str(sv.get("kind", "")) == "yield":
			n += int(sv.get("bonus", {}).get(stock, 0))
	return n


## The factor on how often things to pick up turn up (upgrades bought).
static func drop_factor(world: World) -> float:
	if world.services_bought.is_empty():
		return 1.0
	var f := 1.0
	for id in world.services_bought:
		var sv: Dictionary = world.pack.services.get(id, {})
		if str(sv.get("kind", "")) == "drops":
			f *= float(sv.get("factor", 1.0))
	return f


## Draws tickets that are due and sends the hired hand round at its hours.
static func step(world: World, dt: float) -> void:
	if not world.tickets.is_empty():
		for t in world.tickets:
			if int(t.amount) < 0 and world.now >= int(t.draw_at):
				_draw(world, t)
	if world.helper_until > 0 and world.now - int(dt) < world.helper_until:
		var sv: Dictionary = world.pack.services.get(world.helper_service, {})
		if sv.is_empty():
			return
		var h1 := floori(float(world.now + world.utc_offset) / 3600.0)
		var h0 := floori(float(world.now - int(dt) + world.utc_offset) / 3600.0)
		if h1 != h0 and (sv.get("hours", []) as Array).has(posmod(h1, 24)):
			_help(world, sv)
		if world.now >= world.helper_until:
			world.helper_until = 0
			world.helper_service = ""
			world.emit("helper_left")


static func _draw(world: World, t: Dictionary) -> void:
	var sv: Dictionary = world.pack.services.get(str(t.service), {})
	var roll := world.rng.randf()
	var won := 0
	var acc := 0.0
	for pr in sv.get("prizes", []):
		acc += float(pr["chance"])
		if roll < acc:
			won = int(pr["amount"])
			break
	t.amount = won
	if won > 0:
		EconomySystem.earn(world, won, "lottery")
	world.emit("lottery_drawn", {"ticket": int(t.id), "amount": won})


static func _help(world: World, sv: Dictionary) -> void:
	var cleaned := 0
	if bool(sv.get("cleans", false)):
		while not world.messes.is_empty():
			MessSystem.clean(world, int(world.messes[0].uid))
			cleaned += 1
	var cooked := ""
	var dish := str(sv.get("cooks", ""))
	if dish != "" and DishSystem.may_serve(world, dish):
		var needs: Dictionary = sv.get("consumes", {})
		var ok := true
		for s in needs:
			if int(world.stock.get(s, 0)) < int(needs[s]):
				ok = false
		if ok and DishSystem.serve(world, dish) >= 0:
			for s in needs:
				world.stock[s] = int(world.stock[s]) - int(needs[s])
			cooked = dish
	world.emit("helper_came", {"cleaned": cleaned, "cooked": cooked})
