class_name WeatherSystem
extends RefCounted
## Seasons and weather (off while the pack's `seasons` is empty).
##
## The year (`hours_per_year`) is split evenly into the seasons of `seasons.list`, counted
## from the unix epoch, so the season is a pure function of the clock. The weather is rolled
## through `world.rng` once per slot of `seasons.change_min` minutes (the slot is also a pure
## function of the clock): with chance `persist` it stays, else it is drawn from the
## season's `weather` weights. A replayed absence therefore rolls once per slot crossed and
## gives the same weather as playing through it.
##
## What it changes (all pack data):
## - actions: `seasons` / `weather` (only then), `not_wet` (not while the ground is wet),
##   and a score factor: the weather's `outdoor` / `outside` factor for actions done outdoors
##   at home / at a place outside the house (not for work, nor for actions made for that
##   weather), times
##   every `boost` of the season and the weather whose key is the action's id, object type
##   or one of its tags (see `action_factor`);
## - messes: the season's and the weather's `messes` and, while the ground is wet (during a
##   `wet` weather and `dry_hours` after it), `wet_messes`, each as spawns per day; a mess
##   type with `seasons` is gone once the season is not among them;
## - yields: an action's `yields` times the season's `yields` factor for that stock.


static func enabled(pack: Pack) -> bool:
	var s = pack.cfg("seasons")
	return s is Dictionary and not (s as Dictionary).is_empty()


static func _cfg(pack: Pack) -> Dictionary:
	return pack.cfg("seasons")


## The season entry for the world's clock ({} with seasons off).
static func season_at(pack: Pack, now: int) -> Dictionary:
	if not enabled(pack):
		return {}
	var list: Array = _cfg(pack)["list"]
	var year := float(pack.cfg("hours_per_year")) * 3600.0
	var len := year / float(list.size())
	var i := int(fposmod(float(now), year) / len)
	return list[clampi(i, 0, list.size() - 1)]


## The weather entry by id ({} for none or unknown).
static func weather_entry(pack: Pack, id: String) -> Dictionary:
	if id == "" or not enabled(pack):
		return {}
	for w in _cfg(pack)["weather"]:
		if str(w["id"]) == id:
			return w
	return {}


static func wet(world: World) -> bool:
	return world.now < world.wet_until


## The constants `step` needs, worked out once per pack: {on, year, len, list, change_s,
## dry_s, wet_rates, rates: "season|weather" -> [[mess type, spawns per second], ...]}.
static func _prep(pack: Pack) -> Dictionary:
	if not pack.weather_prep.is_empty():
		return pack.weather_prep
	var on := enabled(pack)
	var out := {"on": on}
	if on:
		var c := _cfg(pack)
		var list: Array = c["list"]
		out["list"] = list
		out["year"] = float(pack.cfg("hours_per_year")) * 3600.0
		out["len"] = float(out["year"]) / float(list.size())
		out["change_s"] = int(c["change_min"]) * 60
		out["dry_s"] = int(float(c.get("dry_hours", 0.0)) * 3600.0)
		out["wet_rates"] = _rates(c.get("wet_messes", {}))
	pack.weather_prep = out
	return out


## [[type, spawns per second], ...] in key order.
static func _rates(per_day: Dictionary) -> Array:
	var out: Array = []
	for t in per_day:
		out.append([str(t), float(per_day[t]) / 86400.0])
	return out


static func step(world: World, dt: float) -> void:
	var prep := _prep(world.pack)
	if not prep["on"]:
		return
	var list: Array = prep["list"]
	var season: Dictionary = list[clampi(int(fposmod(float(world.now), prep["year"]) / prep["len"]), 0, list.size() - 1)]
	var sid := str(season["id"])
	if sid != world.season:
		var first := world.season == ""
		world.season = sid
		_melt(world)
		if not first:
			world.emit("season_changed", {"season": sid})
	var slot := world.now / int(prep["change_s"])
	if slot != world.weather_slot:
		world.weather_slot = slot
		_roll(world, season)
	var key := sid + "|" + world.weather
	var r = prep.get(key)
	if r == null:
		var wx := weather_entry(world.pack, world.weather)
		var both := _rates(season.get("messes", {}))
		both.append_array(_rates(wx.get("messes", {})))
		r = [bool(wx.get("wet", false)), both]
		prep[key] = r
	if r[0]:
		world.wet_until = world.now + int(prep["dry_s"])
	for e in r[1]:
		if world.rng.chance(float(e[1]) * dt):
			MessSystem.spawn(world, e[0])
	if world.now < world.wet_until:
		for e in prep["wet_rates"]:
			if world.rng.chance(float(e[1]) * dt):
				MessSystem.spawn(world, e[0])


static func _roll(world: World, season: Dictionary) -> void:
	var weights: Dictionary = season["weather"]
	var was := world.weather
	if was != "" and weights.has(was) and world.rng.chance(float(_cfg(world.pack).get("persist", 0.0))):
		return
	var ids: Array = weights.keys()
	var ws: Array = ids.map(func(k): return float(weights[k]))
	world.weather = str(world.rng.weighted_pick(ids, ws))
	if world.weather != was:
		world.emit("weather_changed", {"weather": world.weather, "season": world.season})


## Messes of a type tied to other seasons go away (melted snow, rotted leaves); not counted
## as cleaned.
static func _melt(world: World) -> void:
	var i := 0
	while i < world.messes.size():
		var seasons = world.pack.mess_types.get(world.messes[i].type, {}).get("seasons", [])
		if seasons is Array and not (seasons as Array).is_empty() and not (seasons as Array).has(world.season):
			world.messes.remove_at(i)
		else:
			i += 1


## The score factor of action `a` now: 0 when it cannot happen in this season / weather /
## wetness, else the product of the weather's outdoor factor (by `kind`: 0 indoors or
## anywhere, 1 outdoors at home, 2 at a place outside the house) and the matching boosts.
## Exactly 1.0 with seasons off.
static func action_factor(world: World, a: Dictionary, kind: int) -> float:
	if not enabled(world.pack):
		return 1.0
	var season := season_at(world.pack, world.now)
	return factor_for(world.pack, a, kind, season, weather_entry(world.pack, world.weather), wet(world))


static func factor_for(pack: Pack, a: Dictionary, kind: int, season: Dictionary, wx: Dictionary, is_wet: bool) -> float:
	var only_s: Array = a.get("seasons", [])
	if not only_s.is_empty() and not only_s.has(season.get("id", "")):
		return 0.0
	var only_w: Array = a.get("weather", [])
	if not only_w.is_empty() and not only_w.has(wx.get("id", "")):
		return 0.0
	if bool(a.get("not_wet", false)) and is_wet:
		return 0.0
	var f := 1.0
	var work = a.get("work")
	# A livelihood's work goes on whatever the sky does; pastimes give way to the weather.
	if only_w.is_empty() and (work == null or (work as Dictionary).is_empty()):
		if kind == 1:
			f *= float(wx.get("outdoor", 1.0))
		elif kind == 2:
			f *= float(wx.get("outside", 1.0))
	var keys: Array = [str(a["id"]), str(a.get("object", ""))]
	keys.append_array(a.get("tags", []))
	for boost in [season.get("boost", {}), wx.get("boost", {})]:
		for k in keys:
			if k != "" and (boost as Dictionary).has(k):
				f *= float(boost[k])
	return f


## Where an action happens for the weather: 1 outdoors at home (an outdoor object, or rooms
## that are all outdoor), 2 at places outside the house (rooms all `outside`), 0 otherwise.
static func place_kind(pack: Pack, a: Dictionary) -> int:
	var obj := str(a.get("object", ""))
	if obj != "":
		return 1 if bool(pack.object_types.get(obj, {}).get("outdoor", false)) else 0
	var rooms: Array = a.get("rooms", [])
	if rooms.is_empty():
		return 0
	var all_outside := true
	for r in rooms:
		var room: Dictionary = pack.rooms.get(r, {})
		if not bool(room.get("outdoor", false)):
			return 0
		if not bool(room.get("outside", false)):
			all_outside = false
	return 2 if all_outside else 1


## The factor the season puts on what an action `yields` of `stock`.
static func yield_factor(world: World, stock: String) -> float:
	if not enabled(world.pack):
		return 1.0
	return float(season_at(world.pack, world.now).get("yields", {}).get(stock, 1.0))


## "season|weather|wet" for caches; "" with seasons off.
static func key(world: World) -> String:
	if not enabled(world.pack):
		return ""
	return "%s|%s|%s" % [season_at(world.pack, world.now).get("id", ""), world.weather, wet(world)]
