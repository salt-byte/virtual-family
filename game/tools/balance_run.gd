class_name BalanceRun
extends RefCounted
## Headless balance runs: many households, each looked after by a conscientious caretaker,
## summarised in one Dictionary. Works for any pack; it only relies on the pack having a
## "food" stock item, medicines that `cure` its illnesses and a treat that lifts "happy".
## Reads live World fields (never `to_dict()`, whose floats are encoded for saving).

## 2026-01-01 08:00 UTC: every run starts on a morning.
const START_UNIX := 1767254400
const FOOD_STOCK := "food"
const MOOD_NEED := "happy"
const LOW_FOOD := 3
const LOW_MOOD := 30.0


## A world that is already living: one adopted person and one of each object type (the
## pack's starting furniture first, the missing types placed for free on the first spot
## `HouseSystem.can_place` accepts: rooms in pack order, then row by row).
static func setup(pack_id: String, seed: int) -> World:
	return setup_pack(Pack.load_dir("res://packs/" + pack_id), seed)


## `setup` for an already loaded (possibly tweaked) pack.
static func setup_pack(pack: Pack, seed: int) -> World:
	var w := World.new(pack, seed)
	w.set_time(START_UNIX, 0)
	w.command({"type": "adopt"})
	var owned := {}
	for o in w.objects:
		owned[o["type"]] = true
	for type in w.pack.object_types:
		if not owned.has(type):
			_place_first_fit(w, str(type))
	return w


## Runs `families` households (seeds seed0, seed0+1, ...) for `days` simulated days with the
## caretaker acting once per simulated hour.
static func run(pack_id: String, families: int, days: int, seed0: int) -> Dictionary:
	var money: Array[int] = []
	var alive := 0
	var married := 0
	var levels := 0.0
	var living := 0
	var messes := 0
	var deaths := {"neglect": 0, "old_age": 0}
	var seen := {}
	for i in families:
		var w := setup(pack_id, seed0 + i)
		for h in days * 24:
			caretake(w)
			w.advance(3600.0)
			for e in w.drain_events():
				if e.type == "action_started":
					seen[e.action] = true
				elif e.type == "person_died":
					deaths[e.cause] = int(deaths.get(e.cause, 0)) + 1
		money.append(w.money)
		if w.people.any(func(p: Person): return p.alive):
			alive += 1
		if w.married:
			married += 1
		for p in w.people:
			if p.alive:
				levels += p.level
				living += 1
		messes += w.messes.size()
	money.sort()
	return {
		"families": families, "alive_at_end": alive,
		"median_money": money[money.size() / 2] if not money.is_empty() else 0,
		"min_money": money.front() if not money.is_empty() else 0,
		"max_money": money.back() if not money.is_empty() else 0,
		"married": married,
		"avg_level": snappedf(levels / living, 0.01) if living > 0 else 0.0,
		"avg_messes": snappedf(float(messes) / families, 0.01) if families > 0 else 0.0,
		"deaths_neglect": int(deaths["neglect"]), "deaths_old_age": int(deaths["old_age"]),
		"distinct_actions": seen.size(), "actions_in_pack": Pack.load_dir("res://packs/" + pack_id).actions.size(),
	}


## The caretaker's hourly round: accept any proposal, keep food stocked, give the right
## medicine to the sick and a treat to the gloomy. Never drags, praises, scolds or furnishes.
static func caretake(w: World) -> void:
	if w.phase != "living":
		return
	if not w.proposals.is_empty():
		w.command({"type": "answer_proposal", "id": w.proposals[0]["id"], "accept": true})
	var food := _first_item(w, func(it): return (it["stock"] as Dictionary).has(FOOD_STOCK))
	if food != "" and int(w.stock.get(FOOD_STOCK, 0)) < LOW_FOOD:
		w.command({"type": "buy", "item": food})
	for p in w.people:
		if not p.alive:
			continue
		if p.illness != "":
			var ill := p.illness
			_give(w, p, _first_item(w, func(it): return it["cures"] == ill))
		if float(p.needs.get(MOOD_NEED, 100.0)) < LOW_MOOD:
			_give(w, p, _first_item(w, func(it): return it["cures"] == "" and (it["stock"] as Dictionary).is_empty() \
					and (it["needs"] as Dictionary).has(MOOD_NEED)))


## Buys one of `item` and uses it on `p`, when there is such an item and the money for it.
static func _give(w: World, p: Person, item: String) -> void:
	if item != "" and w.command({"type": "buy", "item": item}).ok:
		w.command({"type": "use_item", "item": item, "person": p.uid})


## Id of the first pack item (pack order) for which `pred` holds, else "".
static func _first_item(w: World, pred: Callable) -> String:
	for id in w.pack.items:
		if pred.call(w.pack.items[id]):
			return str(id)
	return ""


static func _place_first_fit(w: World, type: String) -> void:
	for room in w.rooms_built:
		var r: Dictionary = w.pack.rooms[room]
		for y in int(r["h"]):
			for x in int(r["w"]):
				if w.add_object(type, room, x, y) >= 0:
					return
