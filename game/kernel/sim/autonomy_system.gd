class_name AutonomySystem
extends RefCounted
## The action table in motion: idle people score what they can do and pick one; running
## actions pay out their need effects step by step. Commands (drag, chores, illness) reuse
## `can_do` / `start` / `cancel`. Object occupancy is derived from `Person.current`, so a
## cancelled, finished or dead person frees their object by simply no longer holding it.


static func step(world: World, dt: float) -> void:
	for p in world.people:
		if not p.alive or p.thanks_until > world.now:
			continue  # someone thanking the player pauses whatever they were doing
		if not p.current.is_empty():
			_progress(world, p, dt)
		elif p.stage(world.pack) != "baby" or not _stage_table(world.pack, "baby").is_empty():
			_choose(world, p)  # babies only in a pack that gives them things to do


## The constant parts of one action, read once per pack so the hot path does no
## dictionary lookups of constants (see `_table`).
class Info:
	var id := ""
	var stages: Array = []
	var object := ""
	var has_work := false
	var track := ""
	var requires: Dictionary = {}
	var has_requires := false
	var kind := ""
	var consumes: Dictionary = {}
	var has_consumes := false
	var base := 0.0
	var need_ids: Array[String] = []
	## max(effect, 0) of each need in `need_ids`, as `_score` uses it
	var need_gains: Array[float] = []
	var tags: Array = []
	var has_hours := false
	var hours: Array = []
	## `hours` as floats, and whether the window wraps past midnight
	var hour_from := 0.0
	var hour_to := 0.0
	var hours_wrap := false
	## slow with an `hours` window: it ends as soon as the hour is outside the window
	var slow_in_hours := false
	## the rooms an action without an object happens in ([]: anywhere)
	var rooms: Array = []
	var has_rooms := false
	## the story this action completes ("": none); only possible while its finale is open
	var story := ""
	var has_story := false
	## slow_in_hours or has_story: one test in the hot loop for the rare special cases
	var gated := false
	## true when `requires` names a mood: such actions are not damped for the depressed
	var mood_req := false
	var mood := ""
	## what the action does for the baby it is aimed at (`tends`): need ids and amounts
	var tend_ids: Array[String] = []
	var tend_gains: Array[float] = []
	## carries the pack's births `avoid_tag`: the pregnant leave it alone
	var avoid := false
	## `requires.pregnant`: 1 only while pregnant, 0 only while not, -1 either way
	var preg := -1
	## true for an action that cares for a baby (`tends`): `kind` is TARGET_PERSON
	var tend := false
	## `object` != "" and `kind` != "" (bool tests are cheaper than string ones in the hot loop)
	var has_object := false
	var has_kind := false
	## position in `_table` (indexes `_flags`)
	var idx := 0
	## the `capacity` of the object type (1 without an object)
	var capacity := 1
	## the dish this action puts out ("": none); only while another may be served
	var serves := ""
	var has_serves := false
	## where it happens for the weather (`WeatherSystem.place_kind`)
	var place_kind := 0
	## `object` as an index into `pack.autonomy_obj_types` (-1: no object)
	var obj_ix := -1
	## `need_ids` as indexes into the pack's needs (`pack.autonomy_need_ids`)
	var need_ix := PackedInt32Array()
	## the mess type it cleans ("": none)
	var cleans := ""
	## the most its needs (or the baby's) can add to `base`: the sum of the positive gains
	var gain_max := 0.0
	## `requires` is only `need_below` (the usual case): the needs by index and their lines
	var req_fast := false
	var req_ix := PackedInt32Array()
	var req_below := PackedFloat64Array()
	## true for an action that looks after a pet (`pet`): `kind` is TARGET_PET; the pet kinds
	## it suits ([]: any), the pet needs it gives and whether it cures
	var pet := false
	var pet_kinds: Array = []
	var pet_ids: Array[String] = []
	var pet_gains: Array[float] = []
	var pet_cures := false
	## `gain_max` without the pet's part (the person's own gains)
	var self_gain := 0.0


## The pack's actions as `Info`, in pack order, built on first use and kept on the pack
## (a pack's content does not change once worlds use it).
static func _table(pack: Pack) -> Array:
	if pack.autonomy_table.size() == pack.actions.size() and not pack.autonomy_table.is_empty():
		return pack.autonomy_table
	var out: Array = []
	var avoid_tag := _avoid_tag(pack)
	var obj_ix := {}  # object type -> index, in order of first use
	var need_ix := {}  # need id -> index, in pack order
	for n in pack.needs:
		need_ix[str(n)] = need_ix.size()
	for id in pack.actions:
		var a: Dictionary = pack.actions[id]
		var i := Info.new()
		i.idx = out.size()
		i.id = str(id)
		i.stages = a["stages"]
		i.object = str(a["object"])
		var work: Dictionary = a["work"]
		i.has_work = not work.is_empty()
		i.track = str(work.get("track", ""))
		i.requires = a["requires"]
		i.has_requires = not i.requires.is_empty()
		i.kind = target_kind(a)
		i.consumes = a["consumes"]
		i.has_consumes = not i.consumes.is_empty()
		i.base = float(a.get("base", 0))
		for n in a["needs"]:
			i.need_ids.append(str(n))
			i.need_gains.append(maxf(float(a["needs"][n]), 0.0))
		i.tags = a.get("tags", [])
		i.hours = a.get("hours", [])
		i.has_hours = not i.hours.is_empty()
		if i.has_hours:
			i.hour_from = float(i.hours[0])
			i.hour_to = float(i.hours[1])
			i.hours_wrap = i.hour_from > i.hour_to
		i.slow_in_hours = bool(a.get("slow", false)) and i.has_hours
		i.rooms = a.get("rooms", [])
		i.has_rooms = not i.rooms.is_empty()
		i.story = str(a.get("completes_story", ""))
		i.has_story = i.story != ""
		i.place_kind = WeatherSystem.place_kind(pack, a)
		i.cleans = str(a["cleans"])
		if i.object != "":
			if not obj_ix.has(i.object):
				obj_ix[i.object] = obj_ix.size()
			i.obj_ix = obj_ix[i.object]
		for n in i.need_ids:
			i.need_ix.append(need_ix.get(n, -1))
		var nb = i.requires.get("need_below")
		if i.requires.size() == 1 and nb is Dictionary:
			i.req_fast = true
			for n in nb:
				i.req_ix.append(need_ix.get(str(n), -1))
				i.req_below.append(float(nb[n]))
		i.serves = str(a.get("serves", ""))
		i.has_serves = i.serves != ""
		i.gated = i.slow_in_hours or i.has_story or i.has_serves
		i.mood_req = i.requires.has("mood")
		i.mood = str(i.requires.get("mood", ""))
		var tends: Dictionary = a.get("tends", {})
		for n in tends:
			i.tend_ids.append(str(n))
			i.tend_gains.append(maxf(float(tends[n]), 0.0))
		i.avoid = avoid_tag != "" and i.tags.has(avoid_tag)
		i.tend = not i.tend_ids.is_empty()
		var pt = a.get("pet")
		if pt is Dictionary and not (pt as Dictionary).is_empty():
			i.pet = true
			i.pet_kinds = pt.get("kinds", [])
			i.pet_cures = bool(pt.get("cures", false))
			var pn: Dictionary = pt.get("needs", {})
			for n in pn:
				i.pet_ids.append(str(n))
				i.pet_gains.append(maxf(float(pn[n]), 0.0))
				i.gain_max += maxf(float(pn[n]), 0.0)
			if i.pet_cures:
				i.gain_max += PetSystem._num(PetSystem.cfg(pack), "cure_gain", 50.0)
		for g in i.need_gains:
			i.gain_max += g
			i.self_gain += g
		for g in i.tend_gains:
			i.gain_max += g
		i.has_object = i.object != ""
		if i.has_object:
			i.capacity = int(pack.object_types.get(i.object, {}).get("capacity", 1))
		i.has_kind = i.kind != ""
		if i.requires.has("pregnant"):
			i.preg = 1 if bool(i.requires["pregnant"]) else 0
		out.append(i)
	pack.autonomy_table = out
	pack.autonomy_obj_types = obj_ix
	pack.autonomy_need_ids = PackedStringArray(need_ix.keys())
	pack.autonomy_by_stage = {}
	pack.autonomy_by_stage_track = {}
	pack.autonomy_flags = {}
	pack.autonomy_index = {}
	for i: Info in out:
		pack.autonomy_index[i.id] = i.idx
	pack.autonomy_whole_hours = out.all(func(i: Info):
		return not i.has_hours or (i.hour_from == floorf(i.hour_from) and i.hour_to == floorf(i.hour_to)))
	var bits := PackedInt32Array()
	var bases := PackedFloat64Array()
	var gmax := PackedFloat64Array()
	var oixs := PackedInt32Array()
	var capas := PackedInt32Array()
	for i: Info in out:
		bits.append((_B_GATED if i.gated else 0) | (_B_OBJECT if i.has_object else 0) \
			| (_B_WORK if i.has_work else 0) | (_B_REQ if i.has_requires else 0) \
			| (_B_TEND if i.tend else 0) | (_B_PET if i.pet else 0) | (_B_MOOD if i.mood_req else 0) \
			| (_B_KIND if i.has_kind else 0) | (_B_CONSUMES if i.has_consumes else 0) \
			| (_B_NEEDS if not i.need_ix.is_empty() else 0) | (_B_CLEANS if i.cleans != "" else 0))
		bases.append(i.base)
		gmax.append(i.gain_max)
		oixs.append(i.obj_ix)
		capas.append(i.capacity)
	pack.autonomy_soa = [bits, bases, gmax, oixs, capas]
	return out


## `Info` flags by `Info.idx` (`pack.autonomy_soa`), so the hot loop of `candidates` reads
## one packed int instead of a property per test (a property read of another object is a
## lookup by name in GDScript).
const _B_GATED := 1
const _B_OBJECT := 2
const _B_WORK := 4
const _B_REQ := 8
const _B_TEND := 16
const _B_PET := 32
const _B_MOOD := 64
const _B_KIND := 128
const _B_CONSUMES := 256
const _B_NEEDS := 512
const _B_CLEANS := 1024


## By object type index (`Info.obj_ix`): the uids of the world's objects of that type, in
## `objects` order. Kept on the world while the objects list is the same array with the same
## size and last uid (objects are only appended with new uids or removed).
static func _objects_by_type(world: World) -> Array:
	var objs := world.objects
	var n := objs.size()
	var last := int(objs[n - 1].uid) if n > 0 else -1
	var c := world._by_type_ctx
	if not c.is_empty() and is_same(c[0], objs) and c[1] == n and c[2] == last:
		return c[3]
	var ixs := world.pack.autonomy_obj_types
	var out: Array = []
	for k in ixs.size():
		out.append([])
	for o in objs:
		var ix = ixs.get(o.type)
		if ix != null:
			out[ix].append(o.uid)
	world._by_type_ctx = [objs, n, last, out]
	return out


## "likes|dislikes|" of `p`, kept on the person until either list is replaced.
static func _person_key(p: Person) -> String:
	if not (is_same(p._key_likes, p.likes) and is_same(p._key_dislikes, p.dislikes)):
		p._key_likes = p.likes
		p._key_dislikes = p.dislikes
		p._key = "%s|%s|" % [p.likes, p.dislikes]
	return p._key


## "hour|rooms built|season|weather|wet" for `_flags`, kept on the world while none of them
## can have changed (same clock, offset, rooms list, weather and wet-until).
static func _world_key(world: World, hour: float) -> String:
	var c := world._flags_ctx
	if c.is_empty() or c[0] != world.now or c[1] != world.utc_offset or not is_same(c[2], world.rooms_built) \
			or c[3] != world.rooms_built.size() or c[4] != world.weather or c[5] != world.wet_until:
		var hkey: Variant = int(hour) if world.pack.autonomy_whole_hours else hour
		var key := "%s|%s|%s" % [hkey, world.rooms_built, WeatherSystem.key(world)]
		world._flags_ctx = [world.now, world.utc_offset, world.rooms_built, world.rooms_built.size(),
			world.weather, world.wet_until, key]
		return key
	return c[6]


const _F_TAGS := 1  ## a tag of the action is among the person's likes or dislikes
const _F_HOURS := 2  ## the hour is outside the action's `hours`
const _F_NOWHERE := 4  ## the action names rooms and none of them is built
const _F_OFF := 8  ## the season, weather or wet ground rules the action out (factor 0)


## Per action of `_table` (by `Info.idx`), the `_F_*` bits for someone with these likes and
## dislikes at this hour in a house with these rooms built, in this season and weather, and
## the weather's score factor (`WeatherSystem.action_factor`): the tests `candidates` would
## otherwise repeat for every action on every choice. With whole-hour windows only (the
## usual case) the hour bits hold for the whole hour, so the result is kept on the pack.
## Returns [flags: PackedByteArray, factors: PackedFloat64Array, cache for `_live` and
## `_live_by_cap`, score caps: PackedFloat64Array, plain scores: PackedFloat64Array] and, once
## `_live_by_cap` has worked it out, the order of the actions by their caps.
static func _flags(world: World, p: Person, hour: float) -> Array:
	var pack := world.pack
	var table := _table(pack)
	var key := _person_key(p) + _world_key(world, hour)
	var f = pack.autonomy_flags.get(key)
	if f != null:
		return f
	# The parts that do not depend on the person are worked out once for everyone here and
	# now, those that only depend on the likes once per person.
	var wkey := "@" + _world_key(world, hour)
	var wp = pack.autonomy_flags.get(wkey)
	if wp == null:
		wp = _world_flags(world, table, hour)
		pack.autonomy_flags[wkey] = wp
	var pkey := "~" + _person_key(p)
	var pp = pack.autonomy_flags.get(pkey)
	if pp == null:
		pp = _person_flags(p, table)
		pack.autonomy_flags[pkey] = pp
	var wbits: PackedByteArray = wp[0]
	var factors: PackedFloat64Array = wp[1]
	var pbits: PackedByteArray = pp[0]
	var pm: PackedFloat64Array = pp[1]
	var out := PackedByteArray()
	out.resize(table.size())
	var mult := PackedFloat64Array()
	mult.resize(table.size())
	for k in table.size():
		var b := wbits[k] | pbits[k]
		out[k] = b
		var m := pm[k]
		if b & _F_HOURS:
			m *= 0.1
		mult[k] = m * factors[k]
	# For a plain action (no flag bits in `autonomy_soa` but maybe an object: no needs, target,
	# test or stock) the score before habits, damping and low mood, worked out as `candidates`
	# does.
	var kb: PackedInt32Array = pack.autonomy_soa[0]
	var plain := PackedFloat64Array()
	plain.resize(table.size())
	for i: Info in table:
		var k := i.idx
		if kb[k] & ~_B_OBJECT != 0:
			continue
		var sc := i.base + 0.0
		var b := out[k]
		if b & _F_TAGS:
			for t in i.tags:
				if t in p.likes:
					sc *= 1.5
				if t in p.dislikes:
					sc *= 0.5
		if b & _F_HOURS:
			sc *= 0.1
		if factors[k] != 1.0:
			sc *= factors[k]
		plain[k] = sc
	if pack.autonomy_flags.size() > 4096:
		pack.autonomy_flags = {}
	var both := [out, factors, {}, mult, plain]  # the third: stage-track key -> `_live` list
	pack.autonomy_flags[key] = both
	return both


## `_flags`' bits and weather factors that hold for everyone here and now: [bits, factors].
static func _world_flags(world: World, table: Array, hour: float) -> Array:
	var pack := world.pack
	var built := world.built_set()
	var out := PackedByteArray()
	out.resize(table.size())
	var factors := _weather_factors(world, table)
	for i: Info in table:
		var b := 0
		if i.has_hours and not _in_hours(hour, i.hours):
			b |= _F_HOURS
		if not i.has_object and i.has_rooms:
			var somewhere := false
			for r in i.rooms:
				if built.has(r):
					somewhere = true
					break
			if not somewhere:
				b |= _F_NOWHERE
		if factors[i.idx] == 0.0:
			b |= _F_OFF
		out[i.idx] = b
	return [out, factors]


## Per action of `_table`, `WeatherSystem.factor_for` in this season and weather and with the
## ground as wet as it is (all 1.0 with seasons off), kept on the pack by `WeatherSystem.key`.
static func _weather_factors(world: World, table: Array) -> PackedFloat64Array:
	var pack := world.pack
	var key := "%" + WeatherSystem.key(world)
	var f = pack.autonomy_flags.get(key)
	if f != null:
		return f
	var factors := PackedFloat64Array()
	factors.resize(table.size())
	factors.fill(1.0)
	if WeatherSystem.enabled(pack):
		var season := WeatherSystem.season_at(pack, world.now)
		var wx := WeatherSystem.weather_entry(pack, world.weather)
		var is_wet := WeatherSystem.wet(world)
		for i: Info in table:
			factors[i.idx] = WeatherSystem.factor_for(pack, pack.actions[i.id], i.place_kind, season, wx, is_wet)
	pack.autonomy_flags[key] = factors
	return factors


## `_flags`' bits and score factors from `p`'s likes and dislikes: [bits, factors].
static func _person_flags(p: Person, table: Array) -> Array:
	var out := PackedByteArray()
	out.resize(table.size())
	var mult := PackedFloat64Array()
	mult.resize(table.size())
	for i: Info in table:
		var m := 1.0
		for t in i.tags:
			if t in p.likes or t in p.dislikes:
				out[i.idx] = _F_TAGS
			if t in p.likes:
				m *= 1.5
			if t in p.dislikes:
				m *= 0.5
		mult[i.idx] = m
	return [out, mult]


## The births `avoid_tag` of the pack ("" for none).
static func _avoid_tag(pack: Pack) -> String:
	var b = pack.cfg("births")
	return str((b as Dictionary).get("avoid_tag", "")) if b is Dictionary else ""


## `_table` cut down to the actions open to `stage`, in pack order.
static func _stage_table(pack: Pack, stage: String) -> Array:
	var all := _table(pack)
	if not pack.autonomy_by_stage.has(stage):
		pack.autonomy_by_stage[stage] = all.filter(func(i: Info): return stage in i.stages)
	return pack.autonomy_by_stage[stage]


## `_stage_table` without the work actions of livelihoods other than `track`, in pack order.
## Actions that require a mood other than `mood` are left out too; so are, for the pregnant,
## the actions they avoid and, for everyone else, those only the pregnant do; and actions that
## care for a baby while there is none (`babies` false), or for a pet while none it suits is
## at home (`pets`: see `PetSystem.home_key`).
static func _stage_track_table(pack: Pack, stage: String, track: String, mood := "", pregnant := false, babies := false, pets := "") -> Array:
	var key := stage + "|" + track + "|" + mood
	if pregnant:
		key += "|p"
	if babies:
		key += "|b"
	if pets != "":
		key += "|q" + pets
	var t = pack.autonomy_by_stage_track.get(key)
	if t == null:
		t = _stage_table(pack, stage).filter(func(i: Info):
			return _open_to(i, track, mood, pregnant, babies) and (not i.pet or _pet_fits(i, pets)))
		pack.autonomy_by_stage_track[key] = t
	return t


## `_stage_track_table`'s tests but the one for pets.
static func _open_to(i: Info, track: String, mood: String, pregnant: bool, babies: bool) -> bool:
	return (not i.has_work or i.track == track) and (not i.mood_req or i.mood == mood) \
		and not (pregnant and i.avoid) and (i.preg < 0 or (i.preg == 1) == pregnant) \
		and (babies or not i.tend)


## By `Info.idx`, 1 for the care actions `_pet_fits` lets through with the pets at home as
## `key` lists them (0 for all other actions), kept on the pack.
static func _pet_mask(pack: Pack, key: String) -> PackedByteArray:
	var k := "!" + key
	var m = pack.autonomy_by_stage_track.get(k)
	if m == null:
		var table := _table(pack)
		m = PackedByteArray()
		m.resize(table.size())
		for i: Info in table:
			if i.pet and _pet_fits(i, key):
				m[i.idx] = 1
		pack.autonomy_by_stage_track[k] = m
	return m


## Whether a care action suits the pets at home as `PetSystem.home_key` lists them: a pet of
## one of its kinds (any, without kinds) lacks one of the needs it gives, or for a cure one
## of them is ill ("!").
static func _pet_fits(i: Info, key: String) -> bool:
	if key == "":
		return false
	if i.pet_cures:
		return key.contains("!")
	for n in i.pet_ids:
		if i.pet_kinds.is_empty():
			if key.contains("." + n + ","):
				return true
		else:
			for k in i.pet_kinds:
				if key.contains("," + str(k) + "." + n + ","):
					return true
	return false


## `_stage_track_table` without the actions `_flags` rules out here and now (no place built
## for them, or the season / weather / wet ground says no), kept with those flags.
static func _live(pack: Pack, flagged: Array, stage: String, track: String, mood: String, pregnant: bool, babies: bool, pets := "") -> Array:
	var key := stage + "|" + track + "|" + mood + ("|p" if pregnant else "") + ("|b" if babies else "") + ("|q" + pets if pets != "" else "")
	var cache: Dictionary = flagged[2]
	var t = cache.get(key)
	if t == null:
		var flags: PackedByteArray = flagged[0]
		t = _stage_track_table(pack, stage, track, mood, pregnant, babies, pets).filter(func(i: Info):
			return flags[i.idx] & (_F_NOWHERE | _F_OFF) == 0)
		cache[key] = t
	return t


## The actions `_flags` leaves possible here and now and `_open_to` lets through (care
## actions for pets whatever pets are at home: `candidates` tests those itself), ordered by
## the most each could score for this person, (`base` + `gain_max`) times the factors
## `_flags` fixed, highest first: [`Info.idx` of each, bounds], where bounds[k] is the
## highest of those from position k on. `candidates` fills its pool from the top and stops
## once no bound left can reach it. The order is worked out once per `_flags` entry and only
## filtered here.
static func _live_by_cap(pack: Pack, flagged: Array, stage: String, track: String, mood: String, pregnant: bool, babies: bool) -> Array:
	var key := "^" + stage + "|" + track + "|" + mood + ("|p" if pregnant else "") + ("|b" if babies else "")
	var cache: Dictionary = flagged[2]
	var t = cache.get(key)
	if t != null:
		return t
	var table := _table(pack)
	var flags: PackedByteArray = flagged[0]
	var mult: PackedFloat64Array = flagged[3]
	if flagged.size() < 6:
		var keyed: Array = []
		for i: Info in table:
			if flags[i.idx] & (_F_NOWHERE | _F_OFF) == 0:
				keyed.append([-(i.base + i.gain_max) * mult[i.idx], i.idx])
		keyed.sort()
		var order := PackedInt32Array()
		for e in keyed:
			order.append(e[1])
		flagged.append(order)
	var by := PackedInt32Array()
	for ix in flagged[5]:
		var i: Info = table[ix]
		if stage in i.stages and _open_to(i, track, mood, pregnant, babies):
			by.append(ix)
	var bounds := PackedFloat64Array()
	bounds.resize(by.size())
	var hi := -INF
	for k in range(by.size() - 1, -1, -1):
		var i: Info = table[by[k]]
		hi = maxf(hi, (i.base + i.gain_max) * mult[i.idx])
		bounds[k] = hi
	t = [by, bounds]
	cache[key] = t
	return t


## Everything `p` could start right now, scored. Order is stable (pack action order).
## Gives exactly what `can_do(..., -1)` and `_score` give, action by action, except that a
## slow action with an `hours` window is not chosen outside that window (it would end at
## the very next step, see `_progress`).
## `pool` > 0: only the `pool` best, best first, ties in pack order (what `_choose` needs:
## the same entries a stable sort of the full list by score would put first).
static func candidates(world: World, p: Person, pool := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not p.alive:
		return out
	# On the fast action clock people choose often, so this is the hot path: the stage, hour
	# and settings are worked out once, every constant of an action comes from `_table`, and
	# the free object per type is looked up once.
	var pack := world.pack
	var stage := p.stage(pack)
	var hour := world.local_hour()
	# The damping by `Info.idx` (1.0: none), so the loop needs no lookup by action id:
	# `_repeat_damping`, written straight into the array.
	var table := _table(pack)
	var dmp := PackedFloat64Array()
	dmp.resize(table.size())
	dmp.fill(1.0)
	var memory := int(pack.cfg("repeat_memory"))
	var rf := float(pack.cfg("repeat_factor"))
	if memory == 1:
		var ix = pack.autonomy_index.get(p.last_action)
		if ix != null:
			dmp[ix] = rf
	else:
		var powers := _damp_powers(memory, rf)
		var seen := PackedInt32Array()  # the indexes set so far: an action counts where first found
		for k in mini(memory, p.recent_actions.size()):
			var ix = pack.autonomy_index.get(p.recent_actions[k])
			if ix != null and not seen.has(ix):
				seen.append(ix)
				dmp[ix] = powers[k]
	var low := float(pack.cfg("mood_depressed_factor")) if p.mood == "depressed" else 1.0
	var needs := p.needs
	var habits := p.habits
	var any_habits := not habits.is_empty()
	var likes := p.likes
	var dislikes := p.dislikes
	var pregnant := p.pregnant_until > 0
	var track := p.track
	# By `Info.obj_ix`: the first object of that type free for `p` (-1: none, -2: not looked
	# up yet), and the uids of that type's objects in `objects` order.
	var free := PackedInt32Array()
	free.resize(pack.autonomy_obj_types.size())
	free.fill(-2)
	var by_type := _objects_by_type(world)
	var users := {}  # object uid -> people other than `p` using it (filled on first need)
	# `p`'s needs by the pack's need index (`has` 0 where `p` lacks that need).
	var need_ids := pack.autonomy_need_ids
	var nv_of := PackedFloat64Array()
	nv_of.resize(need_ids.size())
	var has := PackedByteArray()
	has.resize(need_ids.size())
	for k in need_ids.size():
		var v = needs.get(need_ids[k])
		if v != null:
			nv_of[k] = float(v)
			has[k] = 1
	var mess_present := {}  # mess type -> true, filled on first need
	var mess_seen := false
	var flagged := _flags(world, p, hour)
	var flags: PackedByteArray = flagged[0]
	var wfs: PackedFloat64Array = flagged[1]
	var caps: PackedFloat64Array = flagged[3]
	var plain: PackedFloat64Array = flagged[4]
	var top_s := PackedFloat64Array()  # with `pool`: the best scores so far, best first
	var top_i := PackedInt32Array()  # `Info.idx`, object uid and target uid for each of `top_s`
	var top_o := PackedInt32Array()
	var top_t := PackedInt32Array()
	# The cheap yes/no tests come first; only what passes them is scored.
	var pets_home := PetSystem.home_key(world) if not world.pets.is_empty() else ""
	var pet_room = null  # pet need id -> the most any pet at home lacks of it (filled on first need)
	# With a pool the actions come best bound first (`_live_by_cap`), so the pool fills with
	# good scores early and the loop ends when no bound left can beat its worst; `top_s`
	# then orders ties by `Info.idx`, which keeps them in pack order as before.
	var live: PackedInt32Array  # `Info.idx` of the actions to look at, in that order
	var bounds := PackedFloat64Array()
	var pet_ok := PackedByteArray()  # with a pool: `_pet_mask` for the pets at home
	var bmul := 1.000001  # how far habits, low mood and damping can lift a score past its bound
	var any_babies := not world.babies().is_empty()
	if pool > 0:
		var lb := _live_by_cap(pack, flagged, stage, p.track, p.mood, pregnant, any_babies)
		live = lb[0]
		bounds = lb[1]
		pet_ok = _pet_mask(pack, pets_home)
		for h in habits.values():
			bmul = maxf(bmul, 1.000001 * float(h))
		bmul *= maxf(low, 1.0) * maxf(float(pack.cfg("repeat_factor")), 1.0)
	else:
		for i: Info in _live(pack, flagged, stage, p.track, p.mood, pregnant, any_babies, pets_home):
			live.append(i.idx)
	var soa: Array = pack.autonomy_soa
	var kb: PackedInt32Array = soa[0]
	var bases: PackedFloat64Array = soa[1]
	var gmax: PackedFloat64Array = soa[2]
	var oixs: PackedInt32Array = soa[3]
	var capas: PackedInt32Array = soa[4]
	# Once the pool is full: its worst score and that entry's `Info.idx`.
	var full := false
	var worst := 0.0
	var worst_i := 0
	var li := -1
	for ix in live:
		li += 1
		var kbits := kb[ix]
		if pool > 0:
			if full and bounds[li] * bmul <= worst:
				break
			if kbits & _B_PET and pet_ok[ix] == 0:
				continue
		if pool > 0 and kbits & ~_B_OBJECT == 0 and not any_habits:
			# A plain action: its score is `plain` (the arithmetic below, done ahead) damped,
			# and it needs a free object if it names one.
			var ps := plain[ix]
			var pdv := dmp[ix]
			if pdv != 1.0:
				ps *= pdv
			if low != 1.0:
				ps *= low
			if ps <= 0.0:
				continue
			if full and (ps < worst or (ps == worst and ix > worst_i)):
				continue
			var puid := -1
			if kbits & _B_OBJECT:
				var poix := oixs[ix]
				puid = free[poix]
				if puid == -2:
					if users.is_empty():
						users[-1] = 0
						for q in world.people:
							if q != p and q.alive and not q.current.is_empty():
								var ou := int(q.current.get("object_uid", -1))
								users[ou] = int(users.get(ou, 0)) + 1
					puid = -1  # `_first_unoccupied`, written out
					var capacity := capas[ix]
					for ouid in by_type[poix]:
						if int(users.get(ouid, 0)) < capacity:
							puid = ouid
							break
					free[poix] = puid
				if puid < 0:
					continue
			var pj := top_s.size()
			while pj > 0 and (ps > top_s[pj - 1] or (ps == top_s[pj - 1] and ix < top_i[pj - 1])):
				pj -= 1
			top_s.insert(pj, ps)
			top_i.insert(pj, ix)
			top_o.insert(pj, puid)
			top_t.insert(pj, -1)
			if top_s.size() > pool:
				top_s.resize(pool)
				top_i.resize(pool)
				top_o.resize(pool)
				top_t.resize(pool)
			if top_s.size() == pool:
				full = true
				worst = top_s[pool - 1]
				worst_i = top_i[pool - 1]
			continue
		var i: Info = table[ix]
		if kbits & _B_GATED:
			if i.slow_in_hours and not _in_hours(hour, i.hours):
				continue
			if i.has_story and not StorySystem.finale_open(world, i.story):
				continue
			if i.has_serves and not DishSystem.may_serve(world, i.serves):
				continue
		var fl := flags[ix]
		if fl & (_F_NOWHERE | _F_OFF):
			continue
		if full and kbits & _B_PET:
			# Its score can be at most this (damping and low mood only lower it): when that
			# cannot beat the pool, the action is passed over as the full scoring would. The
			# pet's part is bounded by what the pets at home lack now (for other actions the
			# bound `_live_by_cap` gives is as good, and the loop already stops on it).
			if pet_room == null:
				pet_room = PetSystem.room_now(world)
			var gm := i.self_gain + PetSystem.gain_bound(world, i.pet_ids, i.pet_gains, i.pet_cures, pet_room)
			var cap := (bases[ix] + gm) * caps[ix]
			if any_habits:
				cap *= float(habits.get(i.id, 1.0))
			if low > 1.0 and not kbits & _B_MOOD:
				cap *= low
			if cap * 1.000001 <= worst:
				continue
		if kbits & _B_WORK and i.track != track:
			continue
		if kbits & _B_REQ:
			if i.req_fast:  # `_requires_ok` for need_below alone, written out
				var below_ok := true
				var req_ix := i.req_ix
				var req_below := i.req_below
				for k in req_ix.size():
					var nx := req_ix[k]
					if (nv_of[nx] if nx >= 0 and has[nx] == 1 else 100.0) >= req_below[k]:
						below_ok = false
						break
				if not below_ok:
					continue
			elif not _requires_ok(p, i.requires):
				continue
		if kbits & _B_CLEANS and not kbits & (_B_TEND | _B_PET):
			if not mess_seen:
				mess_seen = true
				for m in world.messes:
					mess_present[m.type] = true
			if not mess_present.has(i.cleans):
				continue  # nothing of that kind to clean (`MessSystem.first_free` gives -1)
		var uid := -1
		if kbits & _B_OBJECT:
			var oix := i.obj_ix
			var fu := free[oix]
			if fu == -2:
				if users.is_empty():
					users[-1] = 0
					for q in world.people:
						if q != p and q.alive and not q.current.is_empty():
							var ou := int(q.current.get("object_uid", -1))
							users[ou] = int(users.get(ou, 0)) + 1
				fu = -1  # `_first_unoccupied`, written out
				var capacity := i.capacity
				for ouid in by_type[oix]:
					if int(users.get(ouid, 0)) < capacity:
						fu = ouid
						break
				free[oix] = fu
			uid = fu
			if uid < 0:
				continue
		# The score: `_score`'s arithmetic in the same order, written out here.
		var gain := 0.0
		var target := -1
		if kbits & _B_TEND:
			# Caring for a baby scores by what the baby lacks, not by the carer's own needs.
			target = _tend_target(world, i.tend_ids, i.tend_gains, p)
			if target < 0:
				continue
			gain = _tend_gain
		elif kbits & _B_PET:
			target = PetSystem.best_target(world, i.pet_kinds, i.pet_ids, i.pet_gains, i.pet_cures, p)
			if target < 0:
				continue
			gain = PetSystem.target_gain
		if kbits & _B_NEEDS:
			var need_ix := i.need_ix
			var need_gains := i.need_gains
			for k in need_ix.size():
				var nx := need_ix[k]
				if nx >= 0 and has[nx] == 1:
					var room := 100.0 - nv_of[nx]
					gain += minf(need_gains[k], room) * room / 100.0
		var s := bases[ix] + gain
		if any_habits:  # x1.0 for an action without a habit changes nothing
			s *= float(habits.get(i.id, 1.0))
		if fl != 0:
			if fl & _F_TAGS:
				for t in i.tags:
					if t in likes:
						s *= 1.5
					if t in dislikes:
						s *= 0.5
			if fl & _F_HOURS:
				s *= 0.1
		var wfv := wfs[ix]
		if wfv != 1.0:
			s *= wfv
		var dv := dmp[ix]
		if dv != 1.0:
			s *= dv
		if low != 1.0 and not kbits & _B_MOOD:
			s *= low
		if s <= 0.0:
			continue
		if full and (s < worst or (s == worst and ix > worst_i)):
			continue  # would not make the pool whatever the tests below say
		if kbits & _B_KIND and not kbits & (_B_TEND | _B_PET):
			target = _first_free_target(world, pack.actions[i.id], p)
			if target < 0:
				continue
		if kbits & _B_CONSUMES:
			var ok := true
			for item in i.consumes:
				if int(world.stock.get(item, 0)) < int(i.consumes[item]):
					ok = false
					break
			if not ok:
				continue
		if pool <= 0:
			out.append({"action": i.id, "object_uid": uid, "target_uid": target, "score": s})
			continue
		var j := top_s.size()
		while j > 0 and (s > top_s[j - 1] or (s == top_s[j - 1] and ix < top_i[j - 1])):
			j -= 1
		top_s.insert(j, s)
		top_i.insert(j, ix)
		top_o.insert(j, uid)
		top_t.insert(j, target)
		if top_s.size() > pool:
			top_s.resize(pool)
			top_i.resize(pool)
			top_o.resize(pool)
			top_t.resize(pool)
		if top_s.size() == pool:
			full = true
			worst = top_s[pool - 1]
			worst_i = top_i[pool - 1]
	for k in top_s.size():
		out.append({"action": (table[top_i[k]] as Info).id, "object_uid": top_o[k], "target_uid": top_t[k], "score": top_s[k]})
	return out


## `_free_object` for any object of `type`, with the other users per object counted once.
## `uids` are the objects of that type in `world.objects` order (null: none).
static func _first_unoccupied(pack: Pack, type: String, uids: Variant, users: Dictionary) -> int:
	if uids == null:
		return -1
	var capacity := int(pack.object_types.get(type, {}).get("capacity", 1))
	for uid in uids:
		if int(users.get(uid, 0)) < capacity:
			return uid
	return -1


## action id -> the factor `_score` damps a recent repeat by: with a memory of 1 the last
## action gets `rf`; otherwise an action first found at position k (0 = most recent) of the
## last `memory` gets rf^((memory - k) / memory).
static func _repeat_damping(p: Person, memory: int, rf: float) -> Dictionary:
	var out := {}
	if memory == 1:
		out[p.last_action] = rf
		return out
	var powers := _damp_powers(memory, rf)
	for k in mini(memory, p.recent_actions.size()):
		var id: String = p.recent_actions[k]
		if not out.has(id):
			out[id] = powers[k]
	return out


## rf^((memory - k) / memory) for k = 0 .. memory - 1, worked out once per (memory, rf).
static var _powers_memory := -1
static var _powers_rf := -1.0
static var _powers: Array[float] = []
static func _damp_powers(memory: int, rf: float) -> Array[float]:
	if memory != _powers_memory or rf != _powers_rf:
		_powers = []
		for k in memory:
			_powers.append(pow(rf, float(memory - k) / float(memory)))
		_powers_memory = memory
		_powers_rf = rf
	return _powers


## True when at least one of `rooms` is built.
static func _any_built(world: World, rooms: Array) -> bool:
	for r in rooms:
		if world.rooms_built.has(r):
			return true
	return false


static func _stock_ok(world: World, a: Dictionary) -> bool:
	for item in a["consumes"]:
		if int(world.stock.get(item, 0)) < int(a["consumes"][item]):
			return false
	return true


## "" when `p` can start the action now, else the first failing reason.
## `object_uid` -1 means "any free object of the action's type".
static func can_do(world: World, p: Person, action_id: String, object_uid: int) -> String:
	if not p.alive:
		return "dead"
	var a: Dictionary = world.pack.actions.get(action_id, {})
	if a.is_empty():
		return "no_action"
	if not (p.stage(world.pack) in a["stages"]):
		return "stage"
	var type := str(a["object"])
	if type != "":
		if object_uid >= 0:
			if str(world.object(object_uid).get("type", "")) != type:
				return "no_object"
		elif not world.objects.any(func(o): return o.type == type):
			return "no_object"
		if _free_object(world, p, a, object_uid) < 0:
			return "busy"
	elif not (a["rooms"] as Array).is_empty() and not _any_built(world, a["rooms"]):
		return "no_place"
	var work: Dictionary = a["work"]
	if not work.is_empty() and str(work.get("track", "")) != p.track:
		return "wrong_track"
	if not _requires_ok(p, a["requires"]):
		return "requires"
	if p.pregnant_until > 0 and _avoid_tag(world.pack) != "" and (a.get("tags", []) as Array).has(_avoid_tag(world.pack)):
		return "requires"
	if str(a.get("completes_story", "")) != "" and not StorySystem.finale_open(world, str(a["completes_story"])):
		return "requires"
	if str(a.get("serves", "")) != "" and not DishSystem.may_serve(world, str(a["serves"])):
		return "requires"
	if WeatherSystem.action_factor(world, a, WeatherSystem.place_kind(world.pack, a)) == 0.0:
		return "weather"
	if target_kind(a) != "" and _first_free_target(world, a, p) < 0:
		return "no_target"
	if not _stock_ok(world, a):
		return "no_stock"
	return ""


## What an action aims at: "mess" (`cleans`), "collectible" (`picks`), "person" (`tends`: a
## baby), "dish" (`eats`: cooked food), "pet" (`pet`: an animal of the house) or ""
## (nothing). An action has at most one target kind.
static func target_kind(a: Dictionary) -> String:
	if str(a["cleans"]) != "":
		return "mess"
	if bool(a["picks"]):
		return "collectible"
	var eats = a.get("eats")
	if eats != null and not (eats as Array).is_empty():
		return TARGET_DISH
	var tends = a.get("tends")
	if tends != null and not (tends as Dictionary).is_empty():
		return TARGET_PERSON
	var pet = a.get("pet")
	if pet != null and not (pet as Dictionary).is_empty():
		return TARGET_PET
	return ""


## The target kind of an action that cares for a baby.
const TARGET_PERSON := "person"
## The target kind of an action that eats a dish.
const TARGET_DISH := "dish"
## The target kind of an action that looks after a pet.
const TARGET_PET := "pet"


## The gain `_tend_target` found for its pick (read right after the call).
static var _tend_gain := 0.0


## The baby `p` could care for with an action that tends `ids` by `gains`: of the living
## babies nobody else is caring for, the one that lacks most of what it gives (the first such
## on a tie); -1 for none. Sets `_tend_gain` to that baby's gain, scored like a need gain.
static func _tend_target(world: World, ids: Array[String], gains: Array[float], p: Person) -> int:
	var best := -1
	var best_gain := -1.0
	for b in world.babies():
		if b == p or not b.alive or b.stage(world.pack) != "baby":
			continue
		if target_claimed(world, b.uid, "person", p):
			continue
		var g := 0.0
		for k in ids.size():
			var nv = b.needs.get(ids[k])
			if nv != null:
				var room := 100.0 - float(nv)
				g += minf(gains[k], room) * room / 100.0
		if g > best_gain:
			best_gain = g
			best = b.uid
	_tend_gain = maxf(best_gain, 0.0)
	return best


## `_tend_target` for an action's `tends`.
static func tend_target_for(world: World, a: Dictionary, p: Person) -> int:
	var ids: Array[String] = []
	var gains: Array[float] = []
	var tends: Dictionary = a.get("tends", {})
	for n in tends:
		ids.append(str(n))
		gains.append(maxf(float(tends[n]), 0.0))
	return _tend_target(world, ids, gains, p)


## True when a living person other than `except` is going for target `uid` with an action
## of this `kind`.
static func target_claimed(world: World, uid: int, kind: String, except: Person) -> bool:
	for q in world.people:
		if q == except or not q.alive or q.current.is_empty():
			continue
		if int(q.current.get("target_uid", -1)) == uid and target_kind(world.pack.actions[q.current["action"]]) == kind:
			return true
	return false


## Starts an action (no checks: callers use `can_do` first). Replaces whatever `p` was doing.
## Resolves the action's object (any free one when `object_uid` is -1) and, for a cleaning
## or picking action without an explicit `target_uid`, the first unclaimed target.
static func start(world: World, p: Person, action_id: String, object_uid: int, target_uid := -1) -> void:
	cancel(world, p)
	var a: Dictionary = world.pack.actions[action_id]
	var kind := target_kind(a)
	if target_uid < 0 and kind != "":  # (`_first_free_target` gives -1 without a kind)
		target_uid = _first_free_target(world, a, p)
	var uid := _free_object(world, p, a, object_uid) if str(a["object"]) != "" else -1
	for item in a["consumes"]:
		world.stock[item] = int(world.stock.get(item, 0)) - int(a["consumes"][item])
		if not world.pets.is_empty():
			PetSystem.on_consumed(world, str(item), int(a["consumes"][item]))
	if target_uid >= 0 and not world.pets.is_empty() and kind == TARGET_PET:
		PetSystem.on_tended(world, target_uid, p.uid)
	if uid < 0 and target_uid >= 0 and kind == TARGET_DISH:
		# Eating: at the table (or stove) the dish stands on.
		uid = int(DishSystem.find(world, target_uid).get("object_uid", -1))
	p.current = {"action": action_id, "object_uid": uid, "target_uid": target_uid,
		"remaining_s": duration_s(world, a)}
	var rooms: Array = a.get("rooms", [])
	if not rooms.is_empty() and uid < 0:
		var built := rooms.filter(func(r): return world.rooms_built.has(r))
		if not built.is_empty():
			p.current["room"] = str(world.rng.pick(built))
	world.emit("action_started", {"person": p.uid, "action": action_id, "object": uid, "target": target_uid})


## Real seconds an action takes: `duration_min` minutes divided by the pack's
## `action_speed`, rounded up to whole steps (at least one). `slow` actions (sleep) and a
## speed of 1 keep the full `duration_min`.
static func duration_s(world: World, a: Dictionary) -> int:
	var full := int(a["duration_min"]) * 60
	var speed := float(world.pack.cfg("action_speed"))
	if bool(a.get("slow", false)) or speed == 1.0:
		return full
	var s := ceili(full / speed - 1e-9)
	return maxi(ceili(float(s) / world.step_s), 1) * world.step_s


## Drops the current action without any payout; the object becomes free.
static func cancel(world: World, p: Person) -> void:
	if p.current.is_empty():
		return
	world.emit("action_cancelled", {"person": p.uid, "action": p.current["action"]})
	p.current = {}


## Pays the running action's need effects for `dt` seconds: gains add up to their full
## amount over the action's real duration, costs to the share of `duration_min` it took.
## When the pack speeds actions up, a longer `remaining_s` (from a save written before they
## were sped up) is cut to the action's current length first, so the action finishes within
## that length and pays over it. At speed 1 lengths never changed, and only the last
## `duration_s` seconds of a longer `remaining_s` pay, as always.
static func _progress(world: World, p: Person, dt: float) -> void:
	var cur := p.current
	var pack := world.pack
	var c = pack.autonomy_progress.get(cur["action"])
	if c == null:
		c = _progress_entry(pack, str(cur["action"]))
	var a: Dictionary = c[0]
	# A slow action with an `hours` window (sleep) ends as soon as the local hour is outside
	# it: people get up when the night is over, or when the day/night setting flips.
	if c[1] and not _in_hours(world.local_hour(), c[2]):
		_finish(world, p)
		return
	var speed := float(pack.cfg("action_speed"))
	var dur: int = c[6]
	if c[7] != speed or c[8] != world.step_s:
		dur = duration_s(world, a)
		c[6] = dur
		c[7] = speed
		c[8] = world.step_s
	var remaining := int(cur["remaining_s"])
	if remaining > dur and speed != 1.0:
		remaining = dur
		cur["remaining_s"] = remaining
	var needs: Dictionary = c[3]
	if not needs.is_empty() or c[5]:  # most actions only count down
		var paid := clampf(dt - float(remaining - dur), 0.0, dt)
		var gain_frac := paid / float(dur)
		var cost_frac := paid / (float(a["duration_min"]) * 60.0)
		for n in needs:
			if p.needs.has(n):
				var v := float(needs[n])
				var nv := clampf(float(p.needs[n]) + v * (gain_frac if v >= 0.0 else cost_frac), 0.0, 100.0)
				if v > 0.0 and p.mood_cap < 100.0 and n == pack.cfg("praise_need"):
					# Without the player's attention, one's own doings only lift the mood so far.
					nv = minf(nv, maxf(float(p.needs[n]), p.mood_cap))
				p.needs[n] = nv
		if c[5]:
			var tends: Dictionary = c[4]
			var t := world.person(int(cur.get("target_uid", -1)))
			if t != null and t.alive:
				for n in tends:
					if t.needs.has(n):
						t.needs[n] = clampf(float(t.needs[n]) + float(tends[n]) * gain_frac, 0.0, 100.0)
	remaining -= int(dt)
	cur["remaining_s"] = remaining
	if remaining <= 0:
		_finish(world, p)


## What `_progress` reads of action `id` on every step, kept on the pack (a pack's content
## does not change once worlds use it): [the action, slow with an `hours` window, its hours,
## its needs, its tends, whether it tends, then `duration_s` and the action speed and step
## length it was worked out for].
static func _progress_entry(pack: Pack, id: String) -> Array:
	var a: Dictionary = pack.actions[id]
	var tends = a.get("tends")
	var tending := tends != null and not (tends as Dictionary).is_empty()
	var c := [a, bool(a.get("slow", false)) and not (a["hours"] as Array).is_empty(), a["hours"],
		a["needs"], tends if tending else {}, tending, 0, NAN, 0]
	pack.autonomy_progress[id] = c
	return c


## Runs once when an action's time is up.
static func _finish(world: World, p: Person) -> void:
	var id := str(p.current["action"])
	var action: Dictionary = world.pack.actions[id]
	if str(action["cleans"]) != "":
		MessSystem.clean(world, int(p.current.get("target_uid", -1)), p.uid)
	if bool(action["picks"]):
		CollectibleSystem.collect(world, p, int(p.current.get("target_uid", -1)))
	var eats = action.get("eats")
	if eats != null and not (eats as Array).is_empty():
		DishSystem.eat(world, int(p.current.get("target_uid", -1)))
	if str(action.get("serves", "")) != "":
		DishSystem.serve(world, str(action["serves"]))
	var pet = action.get("pet")
	if pet != null and not (pet as Dictionary).is_empty():
		PetSystem.cared(world, p, int(p.current.get("target_uid", -1)), id)
	var yields = action.get("yields")
	if yields != null and not (yields as Dictionary).is_empty():
		for k in yields:
			var n := roundi(float(yields[k]) * WeatherSystem.yield_factor(world, str(k)))
			world.stock[k] = int(world.stock.get(k, 0)) + n
	var mess: Dictionary = action["mess"]
	if not mess.is_empty() and world.rng.chance(float(mess.get("chance", 0.0))):
		var room := str(world.object(int(p.current.get("object_uid", -1))).get("room", ""))
		MessSystem.spawn(world, str(mess["type"]), room)
	if not action["work"].is_empty():
		EconomySystem.on_work_finished(world, p, duration_s(world, action) / 60.0)
	if str(action.get("completes_story", "")) != "":
		StorySystem.complete(world, str(action["completes_story"]), p)
	p.current = {}
	p.last_action = id
	p.last_action_t = world.now
	p.recent_actions.push_front(id)
	p.recent_actions.resize(mini(p.recent_actions.size(), int(world.pack.cfg("repeat_memory"))))
	LivelihoodSystem.on_finished(world, p, id)
	world.emit("action_finished", {"person": p.uid, "action": id})


## First unclaimed target for the action's kind (-1 when it has none or none is free).
static func _first_free_target(world: World, a: Dictionary, p: Person) -> int:
	match target_kind(a):
		"mess":
			return MessSystem.first_free(world, str(a["cleans"]), p)
		"collectible":
			return CollectibleSystem.first_free(world, p)
		"person":
			return tend_target_for(world, a, p)
		"dish":
			return DishSystem.first_free(world, a["eats"], p)
		"pet":
			return PetSystem.target_for(world, a, p)
	return -1


static func _choose(world: World, p: Person) -> void:
	# A weighted pick among the best few (`choice_pool`), best first.
	var top: Array = candidates(world, p, int(world.pack.cfg("choice_pool")))
	if top.is_empty():
		return
	var weights: Array = []
	for cand in top:
		weights.append(cand.score)
	var pick: Dictionary = world.rng.weighted_pick(top, weights)
	start(world, p, pick.action, pick.object_uid, int(pick.get("target_uid", -1)))


## `hour` is the local hour (negative: read it from the world).
static func _score(world: World, p: Person, a: Dictionary, hour := -1.0) -> float:
	var gain := 0.0
	for n in a["needs"]:
		if p.needs.has(n):
			gain += minf(maxf(float(a["needs"][n]), 0.0), 100.0 - float(p.needs[n])) * (100.0 - float(p.needs[n])) / 100.0
	var score := (float(a.get("base", 0)) + gain) * float(p.habits.get(a["id"], 1.0))
	for t in a.get("tags", []):
		if t in p.likes:
			score *= 1.5
		if t in p.dislikes:
			score *= 0.5
	var hours: Array = a.get("hours", [])
	if not hours.is_empty() and not _in_hours(hour if hour >= 0.0 else world.local_hour(), hours):
		score *= 0.1
	var wf := WeatherSystem.action_factor(world, a, WeatherSystem.place_kind(world.pack, a))
	if wf != 1.0:
		score *= wf
	var memory := int(world.pack.cfg("repeat_memory"))
	if memory == 1:  # the default: only the last action, exactly as before the memory existed
		if str(a["id"]) == p.last_action:
			score *= float(world.pack.cfg("repeat_factor"))
	else:
		# Found at position k (0 = most recent) of the last `memory` actions: repeat_factor
		# to the power (memory - k) / memory, so older repeats are damped less.
		var k := p.recent_actions.find(a["id"])
		if k >= 0 and k < memory:
			score *= pow(float(world.pack.cfg("repeat_factor")), float(memory - k) / float(memory))
	if p.mood == "depressed" and not (a["requires"] as Dictionary).has("mood"):
		score *= float(world.pack.cfg("mood_depressed_factor"))
	return score


## `[from, to)` in local hours; from > to wraps past midnight.
static func _in_hours(h: float, hours: Array) -> bool:
	var from := float(hours[0])
	var to := float(hours[1])
	if from <= to:
		return h >= from and h < to
	return h >= from or h < to


static func _requires_ok(p: Person, req: Dictionary) -> bool:
	if req.has("sick") and bool(req["sick"]) != (p.illness != ""):
		return false
	if req.has("mood") and p.mood != str(req["mood"]):
		return false
	if req.has("illness") and p.illness != str(req["illness"]):
		return false
	if req.has("pregnant") and bool(req["pregnant"]) != (p.pregnant_until > 0):
		return false
	var below: Dictionary = req.get("need_below", {})
	for n in below:
		if float(p.needs.get(n, 100.0)) >= float(below[n]):
			return false
	return true


## uid of an object of the action's type that is free for `p` (`object_uid` >= 0 asks for that
## exact one), else -1. An object `p` is already using does not count as occupied for them.
static func _free_object(world: World, p: Person, a: Dictionary, object_uid: int) -> int:
	var type = a["object"]
	for o in world.objects:
		if (object_uid >= 0 and o.uid != object_uid) or o.type != type:
			continue
		# Occupied when it already has as many other users as its type's `capacity`.
		var uid := int(o.uid)
		var users := 0
		for q in world.people:
			if q != p and q.alive and not q.current.is_empty() and int(q.current.get("object_uid", -1)) == uid:
				users += 1
		if users < int(world.pack.object_types.get(o["type"], {}).get("capacity", 1)):
			return o.uid
	return -1
