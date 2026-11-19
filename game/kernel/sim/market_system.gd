class_name MarketSystem
extends RefCounted
## The market: everything the household can buy, grouped into sections, and the used-goods
## stall. Theme-neutral: section ids and names, and which section each thing sits in, come
## from the pack.
##
## Pack config `market` (off while empty):
## - `sections`: [{id, name}] in the order the market shows them.
## - `default`: {item, object, room, pet, service} -> section id for entries whose own
##   `market` field is empty (a kind missing here falls into the first section).
## - `secondhand` (optional): {section, refresh_hours, count, price_factor: [lo, hi], from}.
##   Every `refresh_hours` of game time (a slot) the stall is restocked with `count` distinct
##   things drawn with `world.rng` from the buyable items and furniture of the sections in
##   `from`, each at its price times a factor drawn in [lo, hi] (lo above `sell_back_ratio`,
##   so buying used and selling back never pays). The stall is saved; each listing sells once.
##   Used furniture is set down at the first free spot of a built room that takes it.
##
## Without a `market` config the catalogue still works: one section per kind of goods, with
## the kind as id and name ("items", "objects", "rooms", "pets", "services").
##
## world.secondhand: {slot, list: [{n, kind: "item"|"object", id, price, sold}]}; {} before
## the first restock.

const KINDS := ["item", "object", "room", "pet", "service"]
const PLAIN_SECTIONS := {"item": "items", "object": "objects", "room": "rooms", "pet": "pets", "service": "services"}


static func enabled(pack: Pack) -> bool:
	var m = pack.cfg("market")
	return m is Dictionary and (m as Dictionary).get("sections") is Array and not (m["sections"] as Array).is_empty()


static func secondhand_cfg(pack: Pack) -> Dictionary:
	if not enabled(pack):
		return {}
	var sh = pack.cfg("market").get("secondhand", {})
	return sh if sh is Dictionary else {}


## The sections in order: [{id, name}].
static func sections(pack: Pack) -> Array:
	if enabled(pack):
		var out: Array = []
		for s in pack.cfg("market")["sections"]:
			out.append({"id": str(s["id"]), "name": str(s["name"])})
		return out
	var plain: Array = []
	for k in KINDS:
		plain.append({"id": PLAIN_SECTIONS[k], "name": PLAIN_SECTIONS[k]})
	return plain


## The section an entry of `kind` (one of KINDS) with this pack entry belongs in.
static func section_of(pack: Pack, kind: String, entry: Dictionary) -> String:
	if not enabled(pack):
		return PLAIN_SECTIONS[kind]
	var own := str(entry.get("market", ""))
	if own != "":
		return own
	var d: Dictionary = pack.cfg("market").get("default", {})
	if d.has(kind):
		return str(d[kind])
	return str(pack.cfg("market")["sections"][0]["id"])


## Everything for sale, grouped: [{id, name, entries: [entry]}], sections in pack order and
## entries in pack order within each (used goods last, in their stall order). An entry:
## {kind, id, name, group, price, why, command}
## - kind: "item" | "object" | "room" | "pet" | "service" | "secondhand"
## - id: the pack id (for "secondhand", the listing number `n`; `of` and `ref` then name the
##   kind and pack id of the thing, and `full_price` its new price)
## - group: the entry's own `category` label ("" for none)
## - why: "" when it can be bought now, else the reason ("no_money", "already_built",
##   "owned", "max", "full", "pending", "needs_object", "no_perch", "too_many_pets", "sold",
##   "no_space")
## - command: the command that buys it; for "object" it still needs room, x and y (a place
##   picked by the player), every other one is complete.
## Sections with nothing in them are left out.
static func catalogue(world: World) -> Array:
	var pack := world.pack
	var by_section := {}
	for s in sections(pack):
		by_section[s.id] = []
	for id in pack.items:
		var it: Dictionary = pack.items[id]
		_add(by_section, section_of(pack, "item", it), {"kind": "item", "id": str(id), "name": str(it["name"]),
			"group": str(it.get("category", "")), "price": int(it["price"]),
			"why": "" if world.money >= int(it["price"]) else "no_money",
			"command": {"type": "buy", "item": str(id)}})
	for id in pack.object_types:
		var t: Dictionary = pack.object_types[id]
		if bool(t["fixed"]) or bool(t["keepsake"]):
			continue
		_add(by_section, section_of(pack, "object", t), {"kind": "object", "id": str(id), "name": str(t["name"]),
			"group": str(t.get("category", "")), "price": int(t["price"]),
			"why": "" if world.money >= int(t["price"]) else "no_money",
			"command": {"type": "place", "object_type": str(id)}})
	for id in pack.rooms:
		var r: Dictionary = pack.rooms[id]
		if bool(r["outside"]) or (bool(r["built"]) and int(r["build_cost"]) == 0):
			continue
		var why := ""
		if world.rooms_built.has(str(id)):
			why = "already_built"
		elif world.money < int(r["build_cost"]):
			why = "no_money"
		_add(by_section, section_of(pack, "room", r), {"kind": "room", "id": str(id), "name": str(r["name"]),
			"group": "", "price": int(r["build_cost"]), "why": why,
			"command": {"type": "build_room", "room": str(id)}})
	if PetSystem.enabled(pack):
		for kind in pack.pets:
			var k: Dictionary = pack.pets[kind]
			if int(k["price"]) <= 0:
				continue
			var why := PetSystem.can_take(world, str(kind))
			if why == "" and world.money < int(k["price"]):
				why = "no_money"
			_add(by_section, section_of(pack, "pet", k), {"kind": "pet", "id": str(kind), "name": str(k["name"]),
				"group": "", "price": int(k["price"]), "why": why,
				"command": {"type": "buy_pet", "kind": str(kind)}})
	for id in pack.services:
		var sv: Dictionary = pack.services[id]
		var price := ServiceSystem.price(world, str(id))
		_add(by_section, section_of(pack, "service", sv), {"kind": "service", "id": str(id), "name": str(sv["name"]),
			"group": str(sv.get("category", "")), "desc": str(sv.get("desc", "")), "price": price, "why": ServiceSystem.why_not(world, str(id)),
			"command": {"type": "buy_service", "service": str(id)}})
	var sh := secondhand_cfg(pack)
	if not sh.is_empty():
		for l in world.secondhand.get("list", []):
			var src: Dictionary = (pack.items if l.kind == "item" else pack.object_types).get(l.id, {})
			if src.is_empty():
				continue
			_add(by_section, str(sh["section"]), {"kind": "secondhand", "id": int(l.n), "of": str(l.kind),
				"ref": str(l.id), "name": str(src["name"]), "group": str(src.get("category", "")),
				"price": int(l.price), "full_price": int(src["price"]), "why": _used_why(world, l),
				"command": {"type": "buy_secondhand", "listing": int(l.n)}})
	var out: Array = []
	for s in sections(pack):
		if not (by_section[s.id] as Array).is_empty():
			out.append({"id": s.id, "name": s.name, "entries": by_section[s.id]})
	return out


static func _add(by_section: Dictionary, section: String, entry: Dictionary) -> void:
	if by_section.has(section):
		by_section[section].append(entry)


## `now` (game time) when the stall is next restocked; 0 without a stall.
static func secondhand_refresh_at(world: World) -> int:
	var sh := secondhand_cfg(world.pack)
	if sh.is_empty():
		return 0
	var period := _period_s(sh)
	return (floori(float(world.now) / float(period)) + 1) * period


static func _period_s(sh: Dictionary) -> int:
	return maxi(int(float(sh["refresh_hours"]) * 3600.0), 60)


## Restocks the stall when a new slot has begun (also the first time).
static func step(world: World, _dt: float) -> void:
	var sh := secondhand_cfg(world.pack)
	if sh.is_empty():
		return
	var slot := floori(float(world.now) / float(_period_s(sh)))
	if int(world.secondhand.get("slot", -1)) == slot:
		return
	restock(world, slot)


## The things the stall draws from: [[kind, id]] in pack order (items, then furniture).
static func _pool(world: World) -> Array:
	var sh := secondhand_cfg(world.pack)
	var from: Array = sh.get("from", [])
	var pool: Array = []
	for id in world.pack.items:
		if from.has(section_of(world.pack, "item", world.pack.items[id])) and int(world.pack.items[id]["price"]) > 0:
			pool.append(["item", str(id)])
	for id in world.pack.object_types:
		var t: Dictionary = world.pack.object_types[id]
		if bool(t["fixed"]) or bool(t["keepsake"]) or int(t["price"]) <= 0:
			continue
		if from.has(section_of(world.pack, "object", t)):
			pool.append(["object", str(id)])
	return pool


## Fills the stall for `slot` with fresh used goods drawn with `world.rng`.
static func restock(world: World, slot: int) -> void:
	var sh := secondhand_cfg(world.pack)
	var pool := _pool(world)
	var lo := float(sh["price_factor"][0])
	var hi := float(sh["price_factor"][1])
	var list: Array = []
	var n := int(world.secondhand.get("next", 1))
	for i in mini(int(sh["count"]), pool.size()):
		var k := world.rng.randi_range(0, pool.size() - 1)
		var pick: Array = pool[k]
		pool.remove_at(k)
		var full := int((world.pack.items if pick[0] == "item" else world.pack.object_types)[pick[1]]["price"])
		var f := lo + world.rng.randf() * (hi - lo)
		list.append({"n": n, "kind": pick[0], "id": pick[1], "price": maxi(1, roundi(float(full) * f)), "sold": false})
		n += 1
	world.secondhand = {"slot": slot, "list": list, "next": n}
	world.emit("secondhand_restocked", {"count": list.size()})


static func _listing(world: World, n: int) -> Dictionary:
	for l in world.secondhand.get("list", []):
		if int(l.n) == n:
			return l
	return {}


static func _used_why(world: World, l: Dictionary) -> String:
	if bool(l.sold):
		return "sold"
	if world.money < int(l.price):
		return "no_money"
	if l.kind == "object" and first_fit(world, str(l.id)).is_empty():
		return "no_space"
	return ""


## The first spot where furniture of `type` fits: built rooms in pack order, then row by row.
## {room, x, y}; {} for nowhere.
static func first_fit(world: World, type: String) -> Dictionary:
	for room in world.pack.rooms:
		if not world.rooms_built.has(str(room)):
			continue
		var r: Dictionary = world.pack.rooms[room]
		for y in int(r["h"]):
			for x in int(r["w"]):
				if HouseSystem.can_place(world, type, str(room), x, y) == "":
					return {"room": str(room), "x": x, "y": y}
	return {}


## Command {type: "buy_secondhand", listing}: buys one thing off the stall. An item goes
## into the household's things (or stock); furniture is set down at `first_fit` (the player
## can move it later). Returns {uid} for furniture.
static func buy_used(world: World, cmd: Dictionary) -> Dictionary:
	var l := _listing(world, int(cmd.get("listing", -1)))
	if l.is_empty():
		return Commands.fail("no_item")
	var why := _used_why(world, l)
	if why != "":
		return Commands.fail(why)
	if not EconomySystem.spend(world, int(l.price)):
		return Commands.fail("no_money")
	l.sold = true
	if l.kind == "item":
		give_item(world, str(l.id), 1)
		return Commands.success()
	var spot := first_fit(world, str(l.id))
	var uid := world.add_object(str(l.id), str(spot.room), int(spot.x), int(spot.y))
	return Commands.success({"uid": uid})


## Adds `qty` of item `id` to what the household holds: its `stock`, or the inventory.
static func give_item(world: World, id: String, qty: int) -> void:
	var stock: Dictionary = world.pack.items[id]["stock"]
	if stock.is_empty():
		world.inventory[id] = int(world.inventory.get(id, 0)) + qty
	else:
		for s in stock:
			world.stock[s] = int(world.stock.get(s, 0)) + int(stock[s]) * qty
