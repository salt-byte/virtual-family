class_name FamilySystem
extends RefCounted
## The game's beginning and its matchmaker: candidates to adopt, then marriage proposals
## while exactly one unmarried adult lives in the house. Commands: adopt, reroll, answer_proposal.


## A random person with a pack name, a livelihood track at level 0 (see `LivelihoodSystem`
## for packs with several), and start-value needs.
static func make_person(world: World, age_range: Array) -> Person:
	var names := world.pack.names
	var p := Person.new()
	p.gender = str(world.rng.pick(["male", "female"]))
	p.given = str(world.rng.pick(names.get(p.gender, [])))
	p.family = str(world.rng.pick(names.get("family", [])))
	p.age = _range_f(world, age_range)
	var choose := LivelihoodSystem.has_choice(world.pack)
	if not choose:
		p.track = str(world.rng.pick(world.pack.livelihoods.keys()))
	p.level = 0
	p.aptitude = 0.6 + world.rng.randf() * 0.8
	var tags: Array = (names.get("tags", []) as Array).duplicate()
	p.likes = _take_tags(world, tags)
	p.dislikes = _take_tags(world, tags)
	# With a choice of livelihoods a grown-up arrives with the one their tags point to;
	# a child has none until coming of age.
	if choose and p.age >= LivelihoodSystem.adult_age(world.pack):
		p.track = LivelihoodSystem.track_for_likes(world, p.likes, p.dislikes)
	p.lifespan = _range_f(world, world.pack.cfg("lifespan"))
	for nid in world.pack.needs:
		p.needs[nid] = float(world.pack.needs[nid]["start"])
	return p


## Draws 0-2 tags out of `pool`, removing them so likes and dislikes never overlap.
static func _take_tags(world: World, pool: Array) -> Array:
	var out := []
	for i in world.rng.randi_range(0, mini(2, pool.size())):
		var t = world.rng.pick(pool)
		pool.erase(t)
		out.append(t)
	return out


static func _range_f(world: World, r: Array) -> float:
	return float(r[0]) + world.rng.randf() * (float(r[1]) - float(r[0]))


static func new_candidate(world: World) -> void:
	world.candidate = make_person(world, world.pack.cfg("adopt_age")).to_dict()


static func reroll(world: World, _cmd: Dictionary) -> Dictionary:
	if world.phase == "over":
		world.people.clear()
		world.proposals.clear()
		world.income_carry.clear()
		world.married = false
		world.declined_once = false
		world.phase = "adopting"
	new_candidate(world)
	return Commands.success()


static func adopt(world: World, _cmd: Dictionary) -> Dictionary:
	var p := Person.from_dict(world.candidate)
	world.add_person(p)
	world.candidate = {}
	if not world.adopted_once:
		world.adopted_once = true
		world.money = int(world.pack.cfg("start_money"))
		for o in world.pack.cfg("start_objects"):
			world.add_object(str(o["type"]), str(o["room"]), int(o["x"]), int(o["y"]))
		for room in world.rooms_built.duplicate():
			HouseSystem.place_props(world, room)
	world.phase = "living"
	world.next_proposal_at = world.now + int(world.pack.cfg("proposal_first_min")) * 60
	return Commands.success({"person": p.uid})


static func answer_proposal(world: World, cmd: Dictionary) -> Dictionary:
	var id := int(cmd.get("id", -1))
	var idx := -1
	for i in world.proposals.size():
		if int(world.proposals[i]["id"]) == id:
			idx = i
	if idx < 0:
		return Commands.fail("no_proposal")
	var pr: Dictionary = world.proposals[idx]
	if not bool(cmd.get("accept", false)):
		world.proposals.remove_at(idx)
		var minutes := int(world.pack.cfg("proposal_interval_hours")) * 60
		if not world.declined_once:
			world.declined_once = true
			minutes = int(world.pack.cfg("proposal_after_decline_min"))
		world.next_proposal_at = world.now + minutes * 60
		return Commands.success()
	var spouse := Person.from_dict(pr["person"])
	var head := _lone_adult(world)
	if head != null:
		spouse.family = head.family
	world.add_person(spouse)
	EconomySystem.earn(world, int(pr["savings"]), "savings")
	world.married = true
	world.proposals.clear()
	world.emit("married", {"person": spouse.uid})
	WishSystem.on_married(world, head)
	return Commands.success({"person": spouse.uid})


static func step(world: World, _dt: float) -> void:
	if world.phase != "living":
		return
	for pr in world.proposals.duplicate():
		if world.now >= int(pr["expires_at"]):
			world.proposals.erase(pr)
			world.next_proposal_at = world.now + int(world.pack.cfg("proposal_interval_hours")) * 3600
			world.emit("proposal_expired", {"id": pr["id"]})
	if world.married or not world.proposals.is_empty() or world.now < world.next_proposal_at:
		return
	var head := _lone_adult(world)
	if head == null:
		return
	var person := make_person(world, world.pack.cfg("adopt_age"))
	person.gender = "female" if head.gender == "male" else "male"
	person.given = str(world.rng.pick(world.pack.names.get(person.gender, [])))
	var id := world.next_uid()
	world.proposals.append({
		"id": id, "person": person.to_dict(),
		"savings": world.rng.randi_range(0, int(world.pack.cfg("start_money"))),
		"expires_at": world.now + int(world.pack.cfg("proposal_ttl_hours")) * 3600,
	})
	world.emit("proposal_arrived", {"id": id})


## The only living adult (stage adult or elder), or null when there are none or several.
static func _lone_adult(world: World) -> Person:
	var found: Person = null
	for p in world.people:
		if not p.alive or p.stage(world.pack) not in ["adult", "elder"]:
			continue
		if found != null:
			return null
		found = p
	return found
