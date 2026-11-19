class_name LookSystem
extends RefCounted
## Which of the pack's looks a person wears (`Person.look`): a pack may list looks in
## pack.json `looks`: [{id, sex, stage ("adult" | "elder" ...), livelihoods: [track ids]}].
## A newcomer gets one that fits their sex and stage, leaning towards looks whose
## livelihoods include their track; a child is "child" (the stage's own picture) until they
## grow up, then gets a grown-up look, leaning towards the same-sex parent's; a grown-up who
## grows old gets an old look if the pack has one for their sex. "" (old saves, packs without
## looks) is never changed: the view then picks by stage and sex as before. The choice is
## drawn from a generator seeded by the person's own drawn traits, so it is repeatable and
## leaves the world's random sequence untouched.

const CHILD := "child"
## How much more likely a look is when its livelihoods include the person's track, and when
## it is the same-sex parent's.
const TRACK_WEIGHT := 4.0
const PARENT_WEIGHT := 3.0


## The pack's looks, as listed (valid entries only).
static func looks(pack: Pack) -> Array:
	var out: Array = []
	var list = pack.cfg("looks") if pack != null else null
	if not list is Array:
		return out
	for e in list:
		if e is Dictionary and e.get("id") is String and e.get("sex") is String and e.get("stage") is String:
			out.append(e)
	return out


static func entry(pack: Pack, id: String) -> Dictionary:
	for e in looks(pack):
		if str(e["id"]) == id:
			return e
	return {}


## The kind of look `p` should wear now: CHILD before the grown-up stages, else the stage id.
static func wanted(world: World, p: Person) -> String:
	var adult := LivelihoodSystem.adult_age(world.pack)
	if adult >= 0.0 and p.age < adult:
		return CHILD
	return p.stage(world.pack)


## Gives a newcomer a look (packs with looks only). Call once a person's sex and age are set.
static func assign(world: World, p: Person) -> void:
	if looks(world.pack).is_empty():
		return
	p.look = CHILD
	_update(world, p)


## Keeps the look in step with sex and stage; nothing for "" (old saves, packs without looks).
static func ensure(world: World, p: Person) -> void:
	if p.look == "":
		return
	_update(world, p)


static func _update(world: World, p: Person) -> void:
	var want := wanted(world, p)
	if want == CHILD:
		if p.look != CHILD and entry(world.pack, p.look).is_empty():
			p.look = CHILD
		return
	var cur := entry(world.pack, p.look)
	if not cur.is_empty() and str(cur["sex"]) == p.gender and str(cur["stage"]) == want:
		return
	var pool: Array = []
	var weights: Array = []
	var parent := _parent_look(world, p)
	for e in looks(world.pack):
		if str(e["sex"]) != p.gender or str(e["stage"]) != want:
			continue
		var wgt := 1.0
		if p.track != "" and (e.get("livelihoods", []) as Array).has(p.track):
			wgt *= TRACK_WEIGHT
		if str(e["id"]) == parent:
			wgt *= PARENT_WEIGHT
		pool.append(str(e["id"]))
		weights.append(wgt)
	if pool.is_empty():
		# No look of this stage for them (an old person without an old look): keep a grown-up
		# one if they have it, else the stage's own picture.
		if cur.is_empty() or str(cur["sex"]) != p.gender:
			p.look = CHILD
		return
	var rng := SimRng.new(hash("%s|%s|%s|%s|%s|%s" % [p.given, p.family, p.gender, p.aptitude, p.lifespan, want]))
	p.look = str(rng.weighted_pick(pool, weights))


## The same-sex parent's look ("" when none is known).
static func _parent_look(world: World, p: Person) -> String:
	var uid := p.father if p.gender == "male" else p.mother
	if uid <= 0:
		return ""
	for q in world.people:
		if q.uid == uid:
			return q.look
	return ""
