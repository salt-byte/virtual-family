class_name ServiceSystem
extends RefCounted
## Services and upgrades sold at the market (optional services.json). Every entry has a
## `kind`, a `name` and a `price`; `requires` ({object: type}) keeps it off the counter until
## the house has such an object. Kinds:
##
## - "adopt": another person joins the household. Buying it (free) puts candidates on offer
##   the way the first adoption does (`world.candidates`, `FamilySystem.new_candidate`, aged
##   `age` or the pack's `adopt_age`); `adopt {pick}` takes one in and pays `price` +
##   `price_step` x (people adopted this way so far); `reroll` brings a new lot,
##   `dismiss_candidate` sends them all off. Not while
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
## - "doctor": someone who knows medicine comes to a sick member of the family. Bought with
##   `buy_service {service, person}` (without a person, or for one who is not ill, the first
##   sick person at home): `price` is paid at once, `night_price` instead while the local
##   hour is in `night_hours` ([from, to), wrapping past midnight). The visit
##   (`world.doctor` {person, service, phase, at, fee}) is "coming" for `arrive_seconds`,
##   then "examining" for `exam_seconds`; then the illness is named (`doctor_diagnosed` with
##   the illness's `diagnosis` as `line`, or `well_line` when they got better meanwhile),
##   cured, `restores` ({need: amount}) is added, and the visitor leaves (`doctor_left`).
##   When called, the patient starts `patient_action` if they can (lying down to wait).
##   One visit at a time. Nobody visits while the player is away: a visit still on when an
##   absence is replayed is called off and the fee given back (`doctor_cancelled`); so is
##   one whose patient died or went out before the visitor came. `visitor`, `look` and
##   `enters_from` (a room: where the visitor comes in) are for the view.
##
## world.services_bought: service id -> times bought (adoptions: people taken in).

const KINDS := ["adopt", "speed", "yield", "drops", "lottery", "helper", "doctor"]
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
	elif str(sv["kind"]) == "doctor" and sv.has("night_price") and night(world, sv):
		p = int(sv["night_price"])
	return p


## Whether the local hour is in a doctor service's `night_hours`.
static func night(world: World, sv: Dictionary) -> bool:
	var nh: Array = sv.get("night_hours", [])
	return nh.size() == 2 and AutonomySystem._in_hours(world.local_hour(), nh)


## The first service of `kind` in pack order ("" for none).
static func first_of(pack: Pack, kind: String) -> String:
	for id in pack.services:
		if str(pack.services[id]["kind"]) == kind:
			return str(id)
	return ""


## Who a doctor would see if called for `uid` now: that person when they are alive, ill and
## at home, else the first such person of the family; -1 for nobody.
static func patient(world: World, uid := -1) -> int:
	var p := world.person(uid)
	if p != null and p.alive and p.illness != "" and not OutingSystem.away(world, p):
		return uid
	for q in world.people:
		if q.alive and q.illness != "" and not OutingSystem.away(world, q):
			return q.uid
	return -1


## The sim clock as the real clock would show it.
static func real_now(world: World) -> float:
	return float(world.now) + world._acc - float(world.clock_lead)


## "" when service `id` can be bought now, else why not (see `MarketSystem.catalogue`). For a
## doctor `person` is who it would be for (-1: anyone ill).
static func why_not(world: World, id: String, person := -1) -> String:
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
		"doctor":
			if not world.doctor.is_empty():
				return "doctor_coming"
			if patient(world, person) < 0:
				return "nobody_ill"
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
	var why := why_not(world, id, int(cmd.get("person", -1)))
	if why != "":
		return Commands.fail(why)
	var sv: Dictionary = world.pack.services[id]
	var kind := str(sv["kind"])
	if kind == "adopt":  # paid when the candidate is taken in
		world.adopt_service = id
		_new_candidate(world)
		return Commands.success()
	var fee := price(world, id)
	if not EconomySystem.spend(world, fee):
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
		"doctor":
			var uid := patient(world, int(cmd.get("person", -1)))
			world.doctor = {"person": uid, "service": id, "phase": "coming",
				"at": world.now + int(float(sv.get("arrive_seconds", 0))), "fee": fee}
			_wait_in_bed(world, sv, world.person(uid))
			world.emit("doctor_called", {"person": uid, "service": id, "at": int(world.doctor["at"]), "fee": fee})
			out["person"] = uid
	world.emit("service_bought", {"service": id})
	return Commands.success(out)


static func _new_candidate(world: World) -> void:
	var sv: Dictionary = world.pack.services[world.adopt_service]
	var age = sv.get("age", world.pack.cfg("adopt_age"))
	FamilySystem.new_candidate(world, age)


## `reroll` while living: a new lot is on offer.
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
	world.candidates = []
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
	world.candidates = []
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


## The patient lies down to wait (`patient_action`) when they can.
static func _wait_in_bed(world: World, sv: Dictionary, p: Person) -> void:
	var pa := str(sv.get("patient_action", ""))
	if p == null or pa == "" or (not p.current.is_empty() and str(p.current["action"]) == pa):
		return
	if AutonomySystem.can_do(world, p, pa, -1) == "":
		AutonomySystem.start(world, p, pa, -1)


## Moves a doctor's visit on (see the "doctor" kind).
static func _doctor_step(world: World) -> void:
	var d := world.doctor
	var sv: Dictionary = world.pack.services.get(str(d["service"]), {})
	var p := world.person(int(d["person"]))
	if world.offline or sv.is_empty():
		_doctor_off(world, "doctor_cancelled")
		return
	if world.now < int(d["at"]):
		return
	if p == null or not p.alive or OutingSystem.away(world, p):
		_doctor_off(world, "doctor_cancelled")
		return
	if str(d["phase"]) == "coming":
		d["phase"] = "examining"
		d["at"] = world.now + int(float(sv.get("exam_seconds", 0)))
		_wait_in_bed(world, sv, p)
		world.emit("doctor_arrived", {"person": p.uid, "service": str(d["service"])})
		if world.now < int(d["at"]):
			return
	var line := IllnessSystem.diagnosis(world.pack, p.illness) if p.illness != "" else str(sv.get("well_line", ""))
	world.emit("doctor_diagnosed", {"person": p.uid, "service": str(d["service"]), "line": line, "was_ill": p.illness != ""})
	IllnessSystem.cure(world, p)
	var rs: Dictionary = sv.get("restores", {})
	for n in rs:
		if p.needs.has(n):
			p.needs[n] = clampf(float(p.needs[n]) + float(rs[n]), 0.0, 100.0)
	MoodSystem.cared(world, p)
	world.doctor = {}
	world.emit("doctor_left", {"person": p.uid, "service": str(d["service"])})


## Calls the visit off and gives the fee back.
static func _doctor_off(world: World, why: String) -> void:
	var d := world.doctor
	world.doctor = {}
	if int(d.get("fee", 0)) > 0:
		world.money += int(d["fee"])
	world.emit(why, {"person": int(d.get("person", -1)), "service": str(d.get("service", "")), "refund": int(d.get("fee", 0))})


## Draws tickets that are due, sends the hired hand round at its hours and moves a doctor's
## visit on.
static func step(world: World, dt: float) -> void:
	if not world.doctor.is_empty():
		_doctor_step(world)
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
