class_name MeetWay
extends RefCounted
## How the player meets an ask (`AskSystem`) or a wish (`WishSystem`), in the kernel's own
## terms, for a view that wants to tell the player what to do. Reads the World only.
## `of(world, entry, p)` gives {way, ...} by the entry's kind:
## - "praise": a praise ({way: "praise"})
## - "hold": any drag of the person ({way: "drag"})
## - "item": using one of `items` on them; `have` the ones in store, `section` the market
##   section the first is sold in
## - "need": a drag to something that raises `need` ({way: "drag_to"}, see `for_need`)
## - "do": `go_out` (some of its actions are outings or happen away from the house:
##   `actions` those), else "drag_to" (`objects` / `uids` where its actions are done), else
##   "pet" (a drag to an animal of the house: `pets` their uids), else "self" (they go on
##   their own)
## - "object" / "room" / "pet": "buy" with `what` (the kind), `id` and the market `section`
## - "married": "proposal" (a match comes by its own proposal); "baby": "wait"
## Anything else: {way: ""}.

## Object types listed for a need: the best ones, those that raise it at least this share of
## what the best raises, at most `MAX_TYPES`.
const SHARE := 0.5
const MAX_TYPES := 2


static func of(world: World, e: Dictionary, p: Person = null) -> Dictionary:
	if world == null or e.is_empty():
		return {"way": ""}
	var pack := world.pack
	match str(e.get("kind", "")):
		"praise":
			return {"way": "praise"}
		"hold":
			return {"way": "drag"}
		"item":
			var items: Array = e.get("items", []) if e.has("items") else [str(e.get("item", ""))]
			var have: Array = []
			for id in items:
				if int(world.inventory.get(str(id), 0)) > 0:
					have.append(str(id))
			var first: Dictionary = pack.items.get(str(items[0]) if not items.is_empty() else "", {})
			return {"way": "item", "items": items, "have": have,
				"section": MarketSystem.section_of(pack, "item", first) if not first.is_empty() else ""}
		"need":
			return for_need(world, str(e.get("need", "")), p)
		"do":
			return _do(world, e.get("actions", []), p)
		"object", "room", "pet":
			var kind := str(e["kind"])
			var id := str(e.get(kind, ""))
			var table: Dictionary = {"object": pack.object_types, "room": pack.rooms, "pet": pack.pets}[kind]
			var entry = table.get(id, {})
			return {"way": "buy", "what": kind, "id": id,
				"section": MarketSystem.section_of(pack, kind, entry if entry is Dictionary else {})}
		"married":
			return {"way": "proposal"}
		"baby":
			return {"way": "wait"}
	return {"way": ""}


## A drag to something that raises need `need` for `p` (null: anyone): {way: "drag_to",
## need, objects: the object types, best first (see `SHARE`), uids: the objects of those
## types standing in built rooms now}. A dish's table counts: an action that eats a dish
## counts for the types the dishes are set out on.
static func for_need(world: World, need: String, p: Person = null) -> Dictionary:
	var pack := world.pack
	var stage := p.stage(pack) if p != null else ""
	var gain := {}
	for aid in pack.actions:
		var a: Dictionary = pack.actions[aid]
		var g := float((a["needs"] as Dictionary).get(need, 0.0))
		if g <= 0.0 or not _stage_ok(a, stage) or not (a["work"] as Dictionary).is_empty():
			continue
		var types: Array = []
		if str(a["object"]) != "":
			types.append(str(a["object"]))
		elif AutonomySystem.target_kind(a) == AutonomySystem.TARGET_DISH:
			for d in a["eats"]:
				for t in pack.dishes.get(str(d), {}).get("on", []):
					types.append(str(t))
		for t in types:
			gain[t] = maxf(float(gain.get(t, 0.0)), g)
	return _ranked(world, {"way": "drag_to", "need": need}, gain)


static func _do(world: World, actions: Array, p: Person) -> Dictionary:
	var pack := world.pack
	var stage := p.stage(pack) if p != null else ""
	var sent: Array = []
	var gain := {}
	var to_pet := false
	for aid in actions:
		var a: Dictionary = pack.actions.get(str(aid), {})
		if a.is_empty() or not _stage_ok(a, stage):
			continue
		if OutingSystem.sendable(pack, a):
			sent.append(str(aid))
		elif str(a["object"]) != "":
			gain[str(a["object"])] = 1.0
		elif AutonomySystem.target_kind(a) == AutonomySystem.TARGET_PET:
			to_pet = true
	if not sent.is_empty():
		return {"way": "go_out", "actions": sent}
	if not gain.is_empty():
		var out := _ranked(world, {"way": "drag_to"}, gain)
		if not (out["uids"] as Array).is_empty() or not to_pet:
			return out
	if to_pet:
		var uids: Array = []
		for pet in world.pets:
			if pet.home():
				uids.append(pet.uid)
		if not uids.is_empty():
			return {"way": "pet", "pets": uids}
	return {"way": "self"}


## `out` with `objects` (the types of `gain`, best first, within `SHARE` of the best, at most
## `MAX_TYPES`, those standing in the house before those that do not) and `uids`.
static func _ranked(world: World, out: Dictionary, gain: Dictionary) -> Dictionary:
	var present := {}
	for o in world.objects:
		if gain.has(str(o.type)) and world.rooms_built.has(str(o.room)):
			present[str(o.type)] = true
	var types: Array = gain.keys()
	types.sort_custom(func(a, b):
		if present.has(a) != present.has(b):
			return present.has(a)
		if float(gain[a]) != float(gain[b]):
			return float(gain[a]) > float(gain[b])
		return str(a) < str(b))
	var best := 0.0
	for t in types:
		best = maxf(best, float(gain[t]))
	var kept: Array = []
	for t in types:
		if kept.size() < MAX_TYPES and float(gain[t]) >= best * SHARE:
			kept.append(t)
	var uids: Array = []
	for o in world.objects:
		if kept.has(str(o.type)) and world.rooms_built.has(str(o.room)):
			uids.append(int(o.uid))
	out["objects"] = kept
	out["uids"] = uids
	return out


static func _stage_ok(a: Dictionary, stage: String) -> bool:
	var stages: Array = a.get("stages", [])
	return stage == "" or stages.is_empty() or stages.has(stage)
