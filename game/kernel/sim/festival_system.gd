class_name FestivalSystem
extends RefCounted
## Feast days (a pack's optional festivals.json). A festival is placed one of two ways:
## - on the real calendar: `dates` lists the local dates it begins on ("YYYY-MM-DD", the
##   pack writes out the years it covers) and `days` how many whole local days it lasts
##   (default 1), from local midnight; it needs no seasons;
## - in the game's year: at a fixed stretch of one season, from `from` to `to` as shares of
##   that season (0 its first moment, 1 its end); this needs seasons.
## Either way it is a pure function of the clock (and, for dates, the world's utc_offset).
## While one is on:
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
	if pack.festivals.is_empty():
		return false
	if WeatherSystem.enabled(pack):
		return true
	for f in pack.festivals.values():
		if not dated(f):
			return false
	return true


## Whether festival entry `f` sits on the real calendar (it has `dates`).
static func dated(f: Dictionary) -> bool:
	return f.get("dates") is Array and not (f["dates"] as Array).is_empty()


## Local seconds since the epoch at the midnight that begins local date "YYYY-MM-DD"
## (-1 when it is not such a date).
static func date_start(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return -1
	var m := int(parts[1])
	var d := int(parts[2])
	if m < 1 or m > 12 or d < 1 or d > 31:
		return -1
	# Days since 1970-01-01 in the proleptic Gregorian calendar (Hinnant's days_from_civil).
	var y := int(parts[0]) - (1 if m <= 2 else 0)
	var era := floori(y / 400.0)
	var yoe := y - era * 400
	var doy := (153 * (m + (-3 if m > 2 else 9)) + 2) / 5 + d - 1
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return (era * 146097 + doe - 719468) * 86400


## {year: [[start s of the year, end s, id], ...], dates: [[local start s, local end s, id],
## ...] sorted by start}, built once.
static func _calendar(pack: Pack) -> Dictionary:
	if not pack.festival_prep.is_empty() or not enabled(pack):
		return pack.festival_prep
	var year_spans: Array = []
	var date_spans: Array = []
	var list: Array = pack.cfg("seasons").get("list", []) if WeatherSystem.enabled(pack) else []
	var year := float(pack.cfg("hours_per_year")) * 3600.0
	var len := year / float(maxi(list.size(), 1))
	for id in pack.festivals:
		var f: Dictionary = pack.festivals[id]
		if dated(f):
			var span := maxi(int(f.get("days", 1)), 1) * 86400
			for d in f["dates"]:
				var s := date_start(str(d))
				if s >= 0:
					date_spans.append([s, s + span, str(id)])
			continue
		for i in list.size():
			if str(list[i]["id"]) == str(f.get("season", "")):
				year_spans.append([len * (i + float(f["from"])), len * (i + float(f["to"])), str(id)])
	date_spans.sort_custom(func(a, b): return a[0] < b[0])
	pack.festival_prep = {"year": year_spans, "dates": date_spans}
	return pack.festival_prep


## The span [start, end, id] on at unix time `now` with utc offset `offset`, and how far
## into it the clock is as [span, t] ([] for none).
static func _on(pack: Pack, now: int, offset: int) -> Array:
	var cal := _calendar(pack)
	if cal.is_empty():
		return []
	if not (cal["dates"] as Array).is_empty():
		var local := float(now + offset)
		for c in cal["dates"]:
			if local < float(c[0]):
				break
			if local < float(c[1]):
				return [c, local]
	if not (cal["year"] as Array).is_empty():
		var t := fposmod(float(now), float(pack.cfg("hours_per_year")) * 3600.0)
		for c in cal["year"]:
			if t >= float(c[0]) and t < float(c[1]):
				return [c, t]
	return []


## The id of the festival on at unix time `now` ("" for none, or without festivals);
## `offset` is the local utc offset in seconds, which dated festivals go by.
static func id_at(pack: Pack, now: int, offset := 0) -> String:
	var on := _on(pack, now, offset)
	return str(on[0][2]) if not on.is_empty() else ""


## The festival on now, as its pack entry ({} for none).
static func current(world: World) -> Dictionary:
	return world.pack.festivals.get(id_at(world.pack, world.now, world.utc_offset), {})


## Seconds until the festival on now ends (0 when none is on).
static func seconds_left(world: World) -> int:
	var on := _on(world.pack, world.now, world.utc_offset)
	return ceili(float(on[0][1]) - float(on[1])) if not on.is_empty() else 0


## The dated festivals' spans that begin within [from_unix, to_unix) for utc offset
## `offset`: [{id, start_unix, end_unix}] by start.
static func dates_between(pack: Pack, from_unix: int, to_unix: int, offset := 0) -> Array:
	var out: Array = []
	var cal := _calendar(pack)
	if cal.is_empty():
		return out
	for c in cal["dates"]:
		var s := int(c[0]) - offset
		if s >= from_unix and s < to_unix:
			out.append({"id": c[2], "start_unix": s, "end_unix": int(c[1]) - offset})
	return out


## The festivals placed in the game's year, in the order they come round, from the start of
## the first season: [{id, start_s, end_s}] with seconds from the year's start (dated
## festivals are not among them, see `dates_between`).
static func calendar(pack: Pack) -> Array:
	var out: Array = []
	var cal := _calendar(pack)
	if cal.is_empty():
		return out
	for c in cal["year"]:
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
	return festivals.is_empty() or festivals.has(id_at(world.pack, world.now, world.utc_offset))


static func step(world: World, _dt: float) -> void:
	if world.pack.festivals.is_empty():
		return
	var id := id_at(world.pack, world.now, world.utc_offset)
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
