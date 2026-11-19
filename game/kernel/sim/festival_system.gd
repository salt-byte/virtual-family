class_name FestivalSystem
extends RefCounted
## Feast days (a pack's optional festivals.json; needs seasons). Each festival sits at a
## fixed stretch of one season: from `from` to `to`, as shares of that season (0 its first
## moment, 1 its end), so like the season it is a pure function of the clock. While one is
## on:
## - actions that list it in `festivals` can be done (and only then), and its `boost`
##   multiplies the score of actions whose id, object type or one of whose tags is a key
##   (see `action_factor`; `AutonomySystem` reads the same through `boosts`);
## - wishes that name it (`festival`) can be formed; when it begins, everyone who holds no
##   wish forms one of them with chance `wish_chance` (not while the player is away, not
##   babies, the depressed or those asleep); such a wish ends with the festival, unpenalised;
## - shop items that list it in `festivals` can be bought (and only then).
## Events: festival_started / festival_ended {festival}. A pack without festivals draws no
## randomness here and changes nothing.


static func enabled(pack: Pack) -> bool:
	return not pack.festivals.is_empty() and WeatherSystem.enabled(pack)


## [[start second of the year, end second, festival id], ...] in pack order, built once.
static func _calendar(pack: Pack) -> Array:
	if not pack.festival_prep.is_empty() or not enabled(pack):
		return pack.festival_prep
	var list: Array = pack.cfg("seasons")["list"]
	var year := float(pack.cfg("hours_per_year")) * 3600.0
	var len := year / float(list.size())
	var out: Array = []
	for id in pack.festivals:
		var f: Dictionary = pack.festivals[id]
		for i in list.size():
			if str(list[i]["id"]) == str(f.get("season", "")):
				out.append([len * (i + float(f["from"])), len * (i + float(f["to"])), str(id)])
	pack.festival_prep = out
	return out


## The id of the festival on at unix time `now` ("" for none, or without festivals).
static func id_at(pack: Pack, now: int) -> String:
	var cal := _calendar(pack)
	if cal.is_empty():
		return ""
	var t := fposmod(float(now), float(pack.cfg("hours_per_year")) * 3600.0)
	for c in cal:
		if t >= float(c[0]) and t < float(c[1]):
			return c[2]
	return ""


## The festival on now, as its pack entry ({} for none).
static func current(world: World) -> Dictionary:
	return world.pack.festivals.get(id_at(world.pack, world.now), {})


## Seconds until the festival on now ends (0 when none is on).
static func seconds_left(world: World) -> int:
	var cal := _calendar(world.pack)
	var t := fposmod(float(world.now), float(world.pack.cfg("hours_per_year")) * 3600.0)
	for c in cal:
		if t >= float(c[0]) and t < float(c[1]):
			return ceili(float(c[1]) - t)
	return 0


## The festivals in the order they come round in a year, from the start of the first
## season: [{id, start_s, end_s}] with seconds from the year's start.
static func calendar(pack: Pack) -> Array:
	var out: Array = []
	for c in _calendar(pack):
		out.append({"id": c[2], "start_s": int(c[0]), "end_s": int(c[1])})
	out.sort_custom(func(a, b): return a.start_s < b.start_s)
	return out


## The score factor festival `fest` ("" for none) puts on action `a`: 0 when the action
## lists `festivals` and `fest` is not among them, else the product of the festival's
## `boost` entries keyed by the action's id, object type or one of its tags.
static func action_factor(pack: Pack, a: Dictionary, fest: String) -> float:
	var only: Array = a.get("festivals", [])
	if not only.is_empty() and not only.has(fest):
		return 0.0
	if fest == "":
		return 1.0
	var boost: Dictionary = pack.festivals.get(fest, {}).get("boost", {})
	if boost.is_empty():
		return 1.0
	var f := 1.0
	var keys: Array = [str(a["id"]), str(a.get("object", ""))]
	keys.append_array(a.get("tags", []))
	for k in keys:
		if k != "" and boost.has(k):
			f *= float(boost[k])
	return f


## Festival `fest`'s boost per action of `AutonomySystem._table` (by `Info.idx`), built once
## per pack and festival; an empty array when it boosts nothing.
static func boosts(pack: Pack, fest: String) -> PackedFloat64Array:
	if fest == "":
		return PackedFloat64Array()
	var cached = pack.festival_boosts.get(fest)
	if cached != null:
		return cached
	var out := PackedFloat64Array()
	if not (pack.festivals.get(fest, {}).get("boost", {}) as Dictionary).is_empty():
		for i in AutonomySystem._table(pack):
			var a: Dictionary = pack.actions[i.id]
			out.append(action_factor(pack, a, fest))
	pack.festival_boosts[fest] = out
	return out


## The highest of `boosts(pack, fest)` (at least 1): how far the festival can lift a score
## past the bounds `AutonomySystem` works out without it.
static func max_boost(pack: Pack, fest: String) -> float:
	var cached = pack.festival_boosts.get("#" + fest)
	if cached != null:
		return cached
	var m := 1.0
	for b in boosts(pack, fest):
		m = maxf(m, b)
	pack.festival_boosts["#" + fest] = m
	return m


## Whether an action, an item or anything else that lists `festivals` can happen now: yes
## when the list is empty, else only while one of them is on.
static func allows(world: World, festivals: Array) -> bool:
	return festivals.is_empty() or festivals.has(id_at(world.pack, world.now))


static func step(world: World, _dt: float) -> void:
	if world.pack.festivals.is_empty():
		return
	var id := id_at(world.pack, world.now)
	if id == world.festival:
		return
	var was := world.festival
	world.festival = id
	if was != "":
		WishSystem.end_festival(world, was)
		world.emit("festival_ended", {"festival": was})
	if id != "":
		world.emit("festival_started", {"festival": id})
		WishSystem.start_festival(world, id)
