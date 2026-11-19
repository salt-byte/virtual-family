class_name StorySystem
extends RefCounted
## Old stories of the house (a pack's optional stories.json). A story unlocks on a condition
## (`unlock.type`: "start" after the first adoption, "generation_at_least" with
## `generation`, "room_built" with `room`); then its fragments turn up one at a time, in
## order, as special collectibles (a collectible entry with a `story` key whose `type` is the
## fragment id) in the story's places, rarer than ordinary finds. A picked fragment is kept,
## never sold. Once all are found the finale opens (`finale.kind`):
## - "visitor_gift": a visitor waits at the gate; `receive_visitor` takes `money` and adds the
##   keepsake object type `object` to the house
## - "offering": the action that `completes_story` this story (on an object) becomes
##   possible; when someone finishes it the story is done and its `blessing` holds for good
## - "dig": a marked cell (`room`, `x`, `y`) appears; dragging someone onto it starts the
##   action that `completes_story` it, which pays `money` when finished
## World state: `world.stories` story id -> {found: [fragment ids], stage}, stage "open",
## "finale" or "done"; a story missing there is still locked. A pack without stories draws
## no randomness here.

const UNLOCKS := ["start", "generation_at_least", "room_built"]
const FINALES := ["visitor_gift", "offering", "dig"]


## Runs once per game minute (on the step that starts one), as if a minute had passed.
static func step(world: World, dt: float) -> void:
	if world.now % 60 >= int(dt):
		return
	var pack := world.pack
	if pack.stories.is_empty() or world.phase != "living":
		return
	dt = maxf(dt, 60.0)
	for sid in pack.stories:
		if not world.stories.has(sid) and _unlock_met(world, pack.stories[sid]["unlock"]):
			world.stories[sid] = {"found": [], "stage": "open"}
			world.emit("story_unlocked", {"story": sid})
	if _fragment_lying(world) or _waiting(world).is_empty():
		return
	if world.rng.chance(1.0 / float(pack.cfg("story_interval_min")) * (dt / 60.0) * ServiceSystem.drop_factor(world)):
		spawn_fragment(world)


static func _unlock_met(world: World, u: Dictionary) -> bool:
	match str(u.get("type", "")):
		"start":
			return world.adopted_once
		"generation_at_least":
			var n := int(u.get("generation", 0))
			return world.people.any(func(p: Person): return p.generation >= n)
		"room_built":
			return world.rooms_built.has(str(u.get("room", "")))
	return false


static func _fragment_lying(world: World) -> bool:
	for c in world.collectibles:
		if c.has("story"):
			return true
	return false


## The story ids whose next fragment may turn up now (open, a fragment left, its hours).
static func _waiting(world: World) -> Array:
	var out: Array = []
	var hour := world.local_hour()
	for sid in world.stories:
		if str(world.stories[sid]["stage"]) != "open":
			continue
		var f := next_fragment(world, sid)
		if f.is_empty():
			continue
		var hours: Array = f.get("hours", world.pack.stories[sid].get("hours", []))
		if hours.size() == 2 and not AutonomySystem._in_hours(hour, hours):
			continue
		out.append(sid)
	return out


## The first fragment of the story not found yet, or {}.
static func next_fragment(world: World, sid: String) -> Dictionary:
	var st: Dictionary = world.stories.get(sid, {})
	var found: Array = st.get("found", [])
	for f in world.pack.stories[sid]["fragments"]:
		if not found.has(str(f["id"])):
			return f
	return {}


## The fragment entry `fid` of story `sid`, or {}.
static func fragment(pack: Pack, sid: String, fid: String) -> Dictionary:
	for f in pack.stories.get(sid, {}).get("fragments", []):
		if str(f["id"]) == fid:
			return f
	return {}


## Puts the next fragment of a waiting story on the ground and returns its uid; -1 when no
## story waits or there is nowhere to put it. Places: the fragment's `rooms`, else the
## story's, that are built; else any built outdoor room. `only`: that story or nothing.
static func spawn_fragment(world: World, only := "") -> int:
	var waiting := _waiting(world)
	if only != "":
		waiting = waiting.filter(func(s): return s == only)
	if waiting.is_empty():
		return -1
	var sid := str(waiting[0]) if waiting.size() == 1 else str(world.rng.pick(waiting))
	var f := next_fragment(world, sid)
	var story: Dictionary = world.pack.stories[sid]
	var wanted: Array = f.get("rooms", story.get("rooms", []))
	var rooms: Array = wanted.filter(func(r): return world.rooms_built.has(r))
	if rooms.is_empty():
		rooms = world.rooms_built.filter(func(r): return bool(world.pack.rooms[r]["outdoor"]))
	if rooms.is_empty():
		return -1
	var room := str(world.rng.pick(rooms))
	var r: Dictionary = world.pack.rooms[room]
	var uid := world.next_uid()
	world.collectibles.append({"uid": uid, "type": str(f["id"]), "story": sid, "room": room,
		"x": world.rng.randi_range(0, int(r["w"]) - 1), "y": world.rng.randi_range(0, int(r["h"]) - 1),
		"expires_at": world.now + int(world.pack.cfg("story_ttl_min")) * 60})
	world.emit("collectible_spawned", {"uid": uid, "kind": str(f["id"]), "room": room, "story": sid})
	return uid


## A fragment was picked up (see `CollectibleSystem.collect`): it is kept, and the last one
## opens the finale.
static func found(world: World, p: Person, c: Dictionary) -> void:
	var sid := str(c["story"])
	var fid := str(c["type"])
	if not world.stories.has(sid):
		return
	var st: Dictionary = world.stories[sid]
	if not (st["found"] as Array).has(fid):
		st["found"].append(fid)
	world.emit("fragment_found", {"uid": int(c["uid"]), "story": sid, "fragment": fid, "person": p.uid})
	if str(st["stage"]) == "open" and next_fragment(world, sid).is_empty():
		st["stage"] = "finale"
		world.emit("story_finale", {"story": sid, "kind": str(world.pack.stories[sid]["finale"]["kind"])})


## True while story `sid` waits for its finale to be played out.
static func finale_open(world: World, sid: String) -> bool:
	return str(world.stories.get(sid, {}).get("stage", "")) == "finale"


static func _done(world: World, sid: String) -> void:
	world.stories[sid]["stage"] = "done"
	world.blessing_illness = illness_factor(world)
	world.emit("story_done", {"story": sid})


## Finishes a story whose finale an action completes (offering, dig): pays its `money`.
static func complete(world: World, sid: String, p: Person) -> void:
	if not finale_open(world, sid):
		return
	var money := int(world.pack.stories[sid]["finale"].get("money", 0))
	EconomySystem.earn(world, money, "story", p.uid)
	_done(world, sid)


## Player command {story}: takes what the visitor of a "visitor_gift" finale brings.
static func receive_visitor(world: World, cmd: Dictionary) -> Dictionary:
	var sid := str(cmd.get("story", ""))
	if not finale_open(world, sid) or str(world.pack.stories[sid]["finale"]["kind"]) != "visitor_gift":
		return Commands.fail("no_visitor")
	var fin: Dictionary = world.pack.stories[sid]["finale"]
	EconomySystem.earn(world, int(fin.get("money", 0)), "story")
	var type := str(fin.get("object", ""))
	var uid := -1
	if type != "":
		uid = _place_first_fit(world, type, str(fin.get("room", "")))
	_done(world, sid)
	return Commands.success({"object": uid})


## Adds `type` for free at the first spot that takes it: `room` first, then the built rooms
## in order, row by row. -1 when it fits nowhere.
static func _place_first_fit(world: World, type: String, room: String) -> int:
	var rooms: Array = world.rooms_built.duplicate()
	if world.rooms_built.has(room):
		rooms.erase(room)
		rooms.push_front(room)
	for rid in rooms:
		var r: Dictionary = world.pack.rooms[rid]
		for y in int(r["h"]):
			for x in int(r["w"]):
				var uid := world.add_object(type, str(rid), x, y)
				if uid >= 0:
					return uid
	return -1


## Story ids waiting for their visitor ("visitor_gift" finale), in pack order.
static func visitors(world: World) -> Array:
	var out: Array = []
	for sid in world.pack.stories:
		if finale_open(world, sid) and str(world.pack.stories[sid]["finale"]["kind"]) == "visitor_gift":
			out.append(sid)
	return out


## The factor on the daily illness chance from the blessings of finished stories.
static func illness_factor(world: World) -> float:
	var f := 1.0
	for sid in world.stories:
		if str(world.stories[sid]["stage"]) == "done":
			f *= float(world.pack.stories[sid]["finale"].get("blessing", {}).get("illness_factor", 1.0))
	return f


## Marks to draw in the house now: {story, look, room, x, y}. A story's `mark` shows while
## it is unlocked and not done (within its `hours`, when given); a "dig" finale's spot shows
## while that finale is open.
static func marks(world: World) -> Array:
	var out: Array = []
	if world.pack.stories.is_empty():
		return out
	var hour := world.local_hour()
	for sid in world.pack.stories:
		if not world.stories.has(sid):
			continue
		var story: Dictionary = world.pack.stories[sid]
		var stage := str(world.stories[sid]["stage"])
		var m: Dictionary = story.get("mark", {})
		if stage != "done" and not m.is_empty() and world.rooms_built.has(str(m["room"])):
			var hours: Array = m.get("hours", [])
			if hours.size() != 2 or AutonomySystem._in_hours(hour, hours):
				out.append({"story": sid, "look": str(m.get("look", "")), "room": str(m["room"]),
					"x": int(m["x"]), "y": int(m["y"])})
		var fin: Dictionary = story["finale"]
		if stage == "finale" and str(fin["kind"]) == "dig":
			out.append({"story": sid, "look": str(fin.get("look", "")), "room": str(fin["room"]),
				"x": int(fin["x"]), "y": int(fin["y"]), "dig": true})
	return out


## The action that completes story `sid`, or "".
static func finale_action(pack: Pack, sid: String) -> String:
	for id in pack.actions:
		if str(pack.actions[id].get("completes_story", "")) == sid:
			return str(id)
	return ""
