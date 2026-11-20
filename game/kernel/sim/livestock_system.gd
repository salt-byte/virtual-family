class_name LivestockSystem
extends RefCounted
## Animals kept for what they give: a pets.json kind with a `livestock` block. They ride on
## `PetSystem` (the same needs, own actions, wishes, illness, care by people, saves), but:
##
## - They live in a pen (`pen`: a room). One can be had only once its pen is built, and a pen
##   holds at most `pen_max` animals (all kinds that name it together). They do not count
##   towards `pets.max`, never run off, never come as strays, cheer nobody and leave no grief.
## - `weight` ({start: [from, to], gain_per_day, lose_per_day, fed_above, hungry_below, min,
##   max}): while its food need is at least `fed_above` (and it is well) it puts weight on;
##   below `hungry_below` it loses some (not while the player is away).
## - `grows_into` ({kind, age} or {kind, weight}): at that age (its own years) or weight it
##   becomes that kind, keeping its name, needs and weight.
## - `sell` ({per_weight, min_weight} or {price}): what it fetches (command `sell_pet`); the
##   pack's `pets.buyer` ({kinds, chance_per_hour, ttl_hours, factor}) sends someone by now
##   and then who offers `factor` times that for the heaviest of `kinds` that would sell
##   (`world.pet_buyer`, answered with `answer_buyer`).
## - `lays` ({collectible, per_day, fed_above, max_lying}): fed and well, it drops a
##   collectible of that type in its pen now and then (while fewer than `max_lying` of them
##   lie about).
## - `young` ({kind, chance_per_day, hours, count: [from, to], fed_above, min_weight}): fed and
##   well, with room in the pen, it may start carrying young; `hours` later `count` animals of
##   `kind` join the pen (as many as there is room for). Meanwhile a kind with actions marked
##   `brood` does only those (a hen sitting on her eggs).
## - `sick_when_hungry`: below `hungry_below` it falls ill that many times as often.
## While the player is away nothing harsh happens: no weight is lost, it does not die of old
## age, no buyer calls. Randomness only through `world.rng`, drawn only where an animal could
## do the thing.

## Animals born in this step, added once the step's loop over the pets is done: [[kind, pen]].
static var _pending: Array = []


static func block(pack: Pack, kind: String) -> Dictionary:
	var b = pack.pets.get(kind, {}).get("livestock", {})
	return b if b is Dictionary else {}


static func is_livestock(pack: Pack, kind: String) -> bool:
	return not block(pack, kind).is_empty()


static func of(pack: Pack, pet: Pet) -> Dictionary:
	return block(pack, pet.kind)


static func _num(c: Dictionary, key: String, d: float) -> float:
	var v = c.get(key, d)
	return float(v) if (v is int or v is float) else d


## The pen of a livestock kind ("" for none).
static func pen_of(pack: Pack, kind: String) -> String:
	return str(block(pack, kind).get("pen", ""))


## How many animals live in `pen` now.
static func in_pen(world: World, pen: String) -> int:
	var n := 0
	for p in world.pets:
		if p.home() and pen_of(world.pack, p.kind) == pen:
			n += 1
	return n


## "" when an animal of the livestock `kind` may come now, else why not ("no_pen",
## "pen_full").
static func can_take(world: World, kind: String) -> String:
	var b := block(world.pack, kind)
	var pen := str(b.get("pen", ""))
	if pen != "" and not world.rooms_built.has(pen):
		return "no_pen"
	if in_pen(world, pen) >= int(_num(b, "pen_max", 1.0)):
		return "pen_full"
	return ""


## A new animal of a livestock kind just came: its starting weight.
static func on_added(world: World, pet: Pet) -> void:
	var wt: Dictionary = of(world.pack, pet).get("weight", {})
	if wt.is_empty() or pet.weight > 0.0:
		return
	pet.weight = PetSystem._range(world, wt.get("start", [10, 10]))


## The animals the pack gives a new household (`pets.start`: [{kind, count}]), in their pens
## where those are built.
static func start(world: World) -> void:
	if not PetSystem.enabled(world.pack):
		return
	var list = PetSystem.cfg(world.pack).get("start", [])
	if not list is Array:
		return
	for e in list:
		var kind := str(e.get("kind", ""))
		for i in int(e.get("count", 1)):
			if world.pack.pets.has(kind) and PetSystem.can_take(world, kind) == "":
				PetSystem.add(world, kind, "start")


## Once a game minute for an animal at home (`md` seconds): weight, growing up, laying and
## young. Returns true when it became another kind (the rest of its minute is skipped).
static func minute(world: World, pet: Pet, md: float) -> bool:
	var b := of(world.pack, pet)
	var food := PetSystem.role(world.pack, "food_need")
	var fed := float(pet.needs.get(food, 100.0))
	var wt: Dictionary = b.get("weight", {})
	if not wt.is_empty():
		if fed >= _num(wt, "fed_above", 50.0) and not pet.sick:
			pet.weight = minf(pet.weight + _num(wt, "gain_per_day", 0.0) * md / 86400.0, _num(wt, "max", 1e9))
		elif fed < _num(wt, "hungry_below", 0.0) and not world.offline:
			pet.weight = maxf(pet.weight - _num(wt, "lose_per_day", 0.0) * md / 86400.0, minf(_num(wt, "min", 0.0), pet.weight))
	var g: Dictionary = b.get("grows_into", {})
	if not g.is_empty() and world.pack.pets.has(str(g.get("kind", ""))):
		if (g.has("age") and pet.age >= _num(g, "age", 0.0)) or (g.has("weight") and pet.weight >= _num(g, "weight", 0.0)):
			grow(world, pet, str(g["kind"]))
			return true
	var pen := str(b.get("pen", ""))
	var lays: Dictionary = b.get("lays", {})
	if not lays.is_empty() and pet.young_at == 0 and not pet.sick and fed >= _num(lays, "fed_above", 0.0):
		var type := str(lays.get("collectible", ""))
		if world.rng.chance(_num(lays, "per_day", 0.0) * md / 86400.0) and lying(world, type) < int(_num(lays, "max_lying", 3.0)):
			var uid := CollectibleSystem.spawn(world, type, pen)
			if uid >= 0:
				world.emit("pet_laid", {"pet": pet.uid, "collectible": uid, "kind": type})
	var y: Dictionary = b.get("young", {})
	if not y.is_empty() and world.pack.pets.has(str(y.get("kind", ""))):
		if pet.young_at > 0:
			if world.now >= pet.young_at:
				_bring_young(world, pet, y, pen)
		elif not pet.sick and fed >= _num(y, "fed_above", 0.0) and pet.weight >= _num(y, "min_weight", 0.0) \
				and in_pen(world, pen) + _pending.size() < int(_num(b, "pen_max", 1.0)) \
				and world.rng.chance(_num(y, "chance_per_day", 0.0) * md / 86400.0):
			pet.young_at = world.now + int(_num(y, "hours", 24.0) * 3600.0)
			pet.current = {}  # a kind that broods goes and sits now
			world.emit("pet_expecting", {"pet": pet.uid})
	return false


## How many collectibles of `type` lie about.
static func lying(world: World, type: String) -> int:
	var n := 0
	for c in world.collectibles:
		if str(c.type) == type:
			n += 1
	return n


static func _bring_young(world: World, pet: Pet, y: Dictionary, pen: String) -> void:
	pet.young_at = 0
	pet.current = {}
	var r: Array = y.get("count", [1, 1])
	var n := world.rng.randi_range(int(r[0]), int(r[1]))
	var room := int(_num(block(world.pack, pet.kind), "pen_max", 1.0)) - in_pen(world, pen) - _pending.size()
	n = clampi(n, 0, maxi(room, 0))
	for i in n:
		_pending.append(str(y["kind"]))
	world.emit("pet_young", {"pet": pet.uid, "kind": str(y["kind"]), "count": n})


## Adds the animals born during this step's loop (called by `PetSystem.step` after it).
static func flush(world: World) -> void:
	if _pending.is_empty():
		return
	var list := _pending.duplicate()
	_pending.clear()
	for kind in list:
		PetSystem.add(world, str(kind), "born", "", 0.0)


## It becomes `kind` (a chick a hen, a piglet a pig): name, needs and weight stay.
static func grow(world: World, pet: Pet, kind: String) -> void:
	var from := pet.kind
	pet.kind = kind
	pet.current = {}
	pet.last_action = ""
	pet.done_at = {}
	pet.wish = {}
	pet.wish_last = ""
	on_added(world, pet)
	world.emit("pet_grew", {"pet": pet.uid, "from": from, "kind": kind})


## What it fetches now (0 when it would not sell: not at home, no `sell`, too light).
static func price(world: World, pet: Pet) -> int:
	if pet == null or not pet.home():
		return 0
	var s: Dictionary = of(world.pack, pet).get("sell", {})
	if s.is_empty() or pet.weight < _num(s, "min_weight", 0.0):
		return 0
	if s.has("per_weight"):
		return maxi(roundi(pet.weight * _num(s, "per_weight", 0.0)), 0)
	return maxi(int(_num(s, "price", 0.0)), 0)


## Command {type: "sell_pet", pet}: sells an animal at home for its `price`.
static func sell(world: World, cmd: Dictionary) -> Dictionary:
	var pet := PetSystem.find(world, int(cmd.get("pet", -1)))
	if pet == null or not pet.home():
		return Commands.fail("no_pet")
	var p := price(world, pet)
	if p <= 0:
		return Commands.fail("not_for_sale")
	_sold(world, pet, p, "market")
	return Commands.success({"price": p})


static func _sold(world: World, pet: Pet, money: int, to: String) -> void:
	pet.alive = false
	pet.cause = "sold"
	pet.died_at = world.now
	pet.current = {}
	pet.wish = {}
	pet.young_at = 0
	if int(world.pet_buyer.get("pet", -1)) == pet.uid:
		world.pet_buyer = {}
	EconomySystem.earn(world, money, "livestock")
	world.emit("pet_sold", {"pet": pet.uid, "price": money, "to": to})


## Once a game hour: an offer that ran out (or whose animal is gone) is withdrawn; with none
## waiting, while the player is here, a buyer may come for the heaviest animal that would
## sell.
static func buyer_step(world: World, c: Dictionary) -> void:
	var b = c.get("buyer", {})
	if not b is Dictionary or (b as Dictionary).is_empty():
		return
	if not world.pet_buyer.is_empty():
		var had := PetSystem.find(world, int(world.pet_buyer.get("pet", -1)))
		if world.now >= int(world.pet_buyer.get("expires_at", 0)) or had == null or not had.home():
			var uid := int(world.pet_buyer.get("pet", -1))
			world.pet_buyer = {}
			world.emit("buyer_left", {"pet": uid})
		return
	if world.offline:
		return
	var kinds: Array = b.get("kinds", [])
	var best: Pet = null
	for pet in world.pets:
		if (kinds.is_empty() or kinds.has(pet.kind)) and price(world, pet) > 0 \
				and (best == null or pet.weight > best.weight):
			best = pet
	if best == null or not world.rng.chance(_num(b, "chance_per_hour", 0.0)):
		return
	world.pet_buyer = {"pet": best.uid, "price": roundi(float(price(world, best)) * _num(b, "factor", 1.0)),
		"expires_at": world.now + int(_num(b, "ttl_hours", 4.0) * 3600.0)}
	world.emit("buyer_arrived", {"pet": best.uid, "price": int(world.pet_buyer["price"])})


## Command {type: "answer_buyer", accept}: sell to the buyer at the gate, or send them off.
static func answer_buyer(world: World, cmd: Dictionary) -> Dictionary:
	if world.pet_buyer.is_empty():
		return Commands.fail("no_buyer")
	var offer := world.pet_buyer
	var pet := PetSystem.find(world, int(offer.get("pet", -1)))
	if not bool(cmd.get("accept", false)) or pet == null or not pet.home():
		world.pet_buyer = {}
		world.emit("buyer_left", {"pet": int(offer.get("pet", -1))})
		return Commands.success() if bool(cmd.get("accept", false)) == false else Commands.fail("no_pet")
	_sold(world, pet, int(offer["price"]), "buyer")
	return Commands.success({"price": int(offer["price"])})
