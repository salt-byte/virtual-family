extends TestCase
## Old stories: unlocking, fragments turning up and being kept, the three finales, save/load.

func _home() -> World:
	var w := World.new(Pack.load_dir("res://packs/qijia"), 5)
	w.set_time(1767268800, 0)   # noon
	w.command({"type": "adopt"})
	w.pack.config["wish_chance_per_hour"] = 0.0
	w.stock["food"] = 50
	return w


## Spawns and picks every fragment of `sid` (each in its turn).
func _find_all(w: World, sid: String) -> void:
	var p := w.people[0]
	var guard := 0
	while StorySystem.next_fragment(w, sid).size() > 0 and guard < 20:
		guard += 1
		for c in w.collectibles.duplicate():
			if c.has("story"):
				w.collectibles.erase(c)
		var uid := StorySystem.spawn_fragment(w, sid)
		var c := CollectibleSystem.find(w, uid)
		assert_eq(str(c.get("story", "")), sid)
		CollectibleSystem.collect(w, p, uid)


func test_smoke_has_no_stories_and_saves_no_story_key():
	var w := TestKit.world("_smoke")
	TestKit.adult(w)
	w.adopted_once = true
	w.advance(3600)
	assert_true(w.stories.is_empty())
	assert_true(not w.to_dict().has("stories"))
	assert_eq(StorySystem.marks(w), [])


func test_qijia_has_three_house_stories_three_by_chance_with_texts():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(p.stories.size(), 6)
	var n := 0
	for st in p.stories.values():
		for f in st.fragments:
			assert_true(str(f.text).length() >= 10 and str(f.text).length() <= 90, str(f.id))
			n += 1
	assert_eq(n, 28)


func test_unlocks():
	var w := _home()
	w.advance(60)
	assert_true(w.stories.has("embroidered_shoe"))
	assert_true(not w.stories.has("little_shadow"))
	assert_true(not w.stories.has("scholar_silver"))
	w.money = 5000
	w.command({"type": "build_room", "room": "study"})
	var grand := TestKit.adult(w, 1.0)
	grand.generation = 2
	w.advance(60)
	assert_true(w.stories.has("scholar_silver"))
	assert_true(w.stories.has("little_shadow"))


func test_fragments_come_in_order_in_the_story_places_and_are_kept_not_sold():
	var w := _home()
	w.advance(60)
	var p := w.people[0]
	var money := w.money
	var uid := StorySystem.spawn_fragment(w)
	var c := CollectibleSystem.find(w, uid)
	assert_eq(c.type, "half_sampler")
	assert_true(c.room in ["well", "yard", "gate"])
	assert_eq(StorySystem.spawn_fragment(w) >= 0, true)   # spawn itself does not refuse...
	w.collectibles = w.collectibles.filter(func(x): return x.uid == uid)
	w.drain_events()
	CollectibleSystem.collect(w, p, uid)
	assert_eq(w.money, money)
	assert_eq(w.stories["embroidered_shoe"]["found"], ["half_sampler"])
	assert_true(w.collection.is_empty())
	var evs := w.drain_events()
	assert_true(evs.any(func(e): return e.type == "fragment_found" and e.fragment == "half_sampler"))
	assert_eq(StorySystem.next_fragment(w, "embroidered_shoe")["id"], "yun_hairpin")


func test_step_keeps_one_fragment_at_a_time_and_fragments_do_not_fill_the_cap():
	var w := _home()
	w.pack.config["story_interval_min"] = 1
	w.advance(10 * 60)
	var frags := w.collectibles.filter(func(c): return c.has("story"))
	assert_eq(frags.size(), 1)
	assert_eq(CollectibleSystem._ordinary_count(w), w.collectibles.size() - 1)


func test_night_only_fragments_wait_for_the_night():
	var w := _home()
	var g := TestKit.adult(w, 1.0)
	g.generation = 2
	w.advance(60)
	w.stories.erase("embroidered_shoe")
	assert_eq(StorySystem.spawn_fragment(w), -1, "noon")
	w.set_time(w.now + 9 * 3600, 0)   # 21:00
	assert_true(StorySystem.spawn_fragment(w) >= 0)


func test_collectibles_keep_to_their_places():
	var w := _home()
	for i in 30:
		var uid := CollectibleSystem.spawn(w, "purse")
		assert_eq(CollectibleSystem.find(w, uid).room, "gate")
	for i in 30:
		var uid := CollectibleSystem.spawn(w, "coins")
		assert_true(w.pack.rooms[CollectibleSystem.find(w, uid).room].outdoor)


func test_visitor_brings_money_and_a_keepsake():
	var w := _home()
	w.advance(60)
	_find_all(w, "embroidered_shoe")
	assert_eq(w.stories["embroidered_shoe"]["stage"], "finale")
	assert_eq(StorySystem.visitors(w), ["embroidered_shoe"])
	var money := w.money
	var r := w.command({"type": "receive_visitor", "story": "embroidered_shoe"})
	assert_true(r.ok)
	assert_eq(w.money, money + 120)
	var o := w.object(int(r.object))
	assert_eq(o.type, "ayun_hoop")
	assert_eq(o.room, "bedroom")
	assert_eq(w.stories["embroidered_shoe"]["stage"], "done")
	assert_eq(w.command({"type": "sell_object", "object": o.uid}).error, "keepsake")
	assert_eq(w.command({"type": "receive_visitor", "story": "embroidered_shoe"}).error, "no_visitor")


func test_offering_at_the_altar_blesses_the_house():
	var w := _home()
	var g := TestKit.adult(w, 30.0)
	g.generation = 2
	w.advance(60)
	assert_true(StorySystem.marks(w).is_empty(), "no shadow at noon")
	w.set_time(w.now + 10 * 3600, 0)   # 22:00
	var m := StorySystem.marks(w)
	assert_eq(m.size(), 1)
	assert_eq(m[0].look, "figure")
	var p := w.people[0]
	var altar := -1
	for o in w.objects:
		if o.type == "altar":
			altar = o.uid
	assert_eq(AutonomySystem.can_do(w, p, "incense_for_douzi", altar), "requires")
	_find_all(w, "little_shadow")
	assert_true(StorySystem.finale_open(w, "little_shadow"))
	p.current = {}
	var r := w.command({"type": "drag", "person": p.uid, "object": altar})
	assert_eq(r.get("action", ""), "incense_for_douzi")
	var guard := 0
	while not p.current.is_empty() and guard < 200:
		w.advance(60); guard += 1
	assert_eq(w.stories["little_shadow"]["stage"], "done")
	assert_near(StorySystem.illness_factor(w), 0.7)
	assert_true(StorySystem.marks(w).is_empty())


func test_dig_at_the_mark_pays_out():
	var w := _home()
	w.money = 5000
	w.command({"type": "build_room", "room": "study"})
	w.advance(60)
	_find_all(w, "scholar_silver")
	var m := StorySystem.marks(w).filter(func(x): return x.get("dig", false))
	assert_eq(m.size(), 1)
	assert_eq([m[0].room, m[0].x, m[0].y], ["yard", 11, 2])
	var p := w.people[0]
	var r := w.command({"type": "drag", "person": p.uid, "story": "scholar_silver"})
	assert_true(r.ok, str(r))
	assert_eq(p.current.room, "yard")
	var money := w.money
	var guard := 0
	while not p.current.is_empty() and guard < 400:
		w.advance(60); guard += 1
	assert_true(w.money >= money + 800)
	assert_eq(w.stories["scholar_silver"]["stage"], "done")
	assert_eq(w.command({"type": "drag", "person": p.uid, "story": "scholar_silver"}).error, "no_target")


func test_nobody_digs_on_their_own():
	var w := _home()
	w.money = 5000
	w.command({"type": "build_room", "room": "study"})
	w.advance(60)
	_find_all(w, "scholar_silver")
	w.drain_events()
	w.advance(3 * 3600)
	assert_true(not w.drain_events().any(func(e): return e.type == "action_started" and e.action == "dig_for_silver"))


func test_stories_survive_save_and_offline():
	var w := _home()
	w.advance(60)
	var uid := StorySystem.spawn_fragment(w)
	CollectibleSystem.collect(w, w.people[0], uid)
	StorySystem.spawn_fragment(w)
	var j := JSON.new()
	j.parse(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, j.data)
	assert_true(back != null)
	assert_eq(back.stories, w.stories)
	assert_eq(back.collectibles, w.collectibles)
	var bad: Dictionary = j.data.duplicate(true)
	bad["stories"]["embroidered_shoe"]["found"] = ["nope"]
	assert_eq(WorldSave.restore(w.pack, bad).error, "pack_changed")
	bad["stories"]["embroidered_shoe"]["stage"] = "lost"
	assert_eq(WorldSave.restore(w.pack, bad).error, "corrupt")
	# Offline: the fragment on the ground is picked up while away and listed.
	var s := back.catch_up(6 * 3600)
	assert_true(s.fragments.any(func(f): return f.fragment == "yun_hairpin"), str(s.fragments))


func test_validator_catches_broken_stories_and_wishes():
	var p := Pack.load_dir("res://packs/qijia")
	p.stories["embroidered_shoe"]["unlock"] = {"type": "someday"}
	p.stories["little_shadow"]["fragments"].append({"id": "half_sampler", "name": "x", "text": "y"})
	p.stories["scholar_silver"]["finale"]["x"] = 99
	p.wishes["want_cake"]["item"] = "nothing"
	p.wishes["hot_meal"]["kind"] = "flying"
	var errs := PackValidator.validate(p)
	for needle in ["unlock.type 'someday'", "fragment id 'half_sampler'", "finale lies outside", "item 'nothing'", "kind 'flying'"]:
		assert_true(errs.any(func(e): return e.contains(needle)), needle + " in " + str(errs))
