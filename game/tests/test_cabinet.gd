extends TestCase
## The keepsake box: pick-ups kept and their extras sold (one of each always stays), the
## stories' midpoint and finale, the stories that come by chance, saving and the offline replay.

const RANDOM := ["peddler_bell", "paper_kite", "ferry_tags"]


func _home(seed := 5) -> World:
	var w := World.new(Pack.load_dir("res://packs/qijia"), seed)
	w.set_time(1767268800, 0)   # noon
	w.command({"type": "adopt"})
	w.pack.config["wish_chance_per_hour"] = 0.0
	w.stock["food"] = 50
	return w


## Jumps to just before the next local midnight and lets the new day begin (when stories
## that come by chance roll their dice).
func _new_day(w: World) -> void:
	w.set_time(w.now + 86400 - posmod(w.now + w.utc_offset, 86400) - 30, w.utc_offset)
	w.advance(60)


func _pick(w: World, kind: String) -> void:
	CollectibleSystem.collect(w, w.people[0], CollectibleSystem.spawn(w, kind))


## Spawns and picks every fragment of `sid` (each in its turn).
func _find_all(w: World, sid: String) -> void:
	var guard := 0
	while not StorySystem.next_fragment(w, sid).is_empty() and guard < 20:
		guard += 1
		_find_next(w, sid)


func _find_next(w: World, sid: String) -> void:
	for c in w.collectibles.duplicate():
		if c.has("story"):
			w.collectibles.erase(c)
	var uid := StorySystem.spawn_fragment(w, sid)
	assert_true(uid >= 0, "a fragment of %s can turn up" % sid)
	CollectibleSystem.collect(w, w.people[0], uid)


func _count(evs: Array, type: String) -> int:
	return evs.filter(func(e): return e.type == type).size()


func test_pickups_go_into_the_box_and_nothing_is_sold_on_the_spot():
	var w := _home()
	var money := w.money
	for i in 3:
		_pick(w, "egg")
	_pick(w, "coins")
	assert_eq(w.money, money)
	assert_eq(w.box, {"egg": 3, "coins": 1})
	assert_eq(w.collection["egg"], 3)
	assert_eq(w.stats["collected"], 4)
	var evs := w.drain_events().filter(func(e): return e.type == "collected")
	assert_eq(evs.size(), 4)
	assert_true(evs.all(func(e): return e.kept and e.value == 0))


func test_duplicates_sell_and_one_of_each_is_kept():
	var w := _home()
	for i in 4:
		_pick(w, "egg")
	for i in 2:
		_pick(w, "bronze_mirror")
	_pick(w, "coins")
	var egg := int(w.pack.collectibles["egg"]["value"])
	var mirror := int(w.pack.collectibles["bronze_mirror"]["value"])
	assert_eq(CollectibleSystem.extras(w, "egg"), 3)
	assert_eq(CollectibleSystem.extras(w, "coins"), 0)
	assert_eq(CollectibleSystem.extras_value(w), 3 * egg + mirror)
	var money := w.money
	var r := w.command({"type": "sell_collectible", "kind": "egg"})
	assert_true(r.ok)
	assert_eq([r.count, r.amount], [1, egg])
	assert_eq([w.box["egg"], w.money], [3, money + egg])
	r = w.command({"type": "sell_collectible", "kind": "egg", "all": true})
	assert_eq([r.count, w.box["egg"], w.money], [2, 1, money + 3 * egg])
	assert_eq(w.command({"type": "sell_collectible", "kind": "egg"}).error, "nothing_to_sell")
	assert_eq(w.command({"type": "sell_collectible", "kind": "coins"}).error, "nothing_to_sell")
	assert_eq(w.command({"type": "sell_collectible", "kind": "nope"}).error, "no_such_thing")
	r = w.command({"type": "sell_collectible"})
	assert_eq([r.count, r.amount], [1, mirror])
	assert_eq(w.box, {"egg": 1, "bronze_mirror": 1, "coins": 1})
	assert_eq(w.command({"type": "sell_collectible"}).error, "nothing_to_sell")
	var sold := w.drain_events().filter(func(e): return e.type == "collectibles_sold")
	assert_eq(sold.size(), 3)


func test_a_keepsake_never_sells():
	var w := _home()
	w.box["old_kite"] = 2
	assert_eq(CollectibleSystem.extras(w, "old_kite"), 0)
	assert_eq(w.command({"type": "sell_collectible", "kind": "old_kite"}).error, "keepsake")
	assert_eq(w.command({"type": "sell_collectible"}).error, "nothing_to_sell")
	assert_eq(w.box["old_kite"], 2)
	# Weight 0: it never turns up on the ground.
	for i in 200:
		var uid := CollectibleSystem.spawn(w)
		assert_true(CollectibleSystem.find(w, uid).type != "old_kite")
		w.collectibles.clear()


func test_smoke_still_sells_duplicates_and_has_no_box():
	var w := TestKit.world("_smoke")
	var p := TestKit.adult(w)
	var money := w.money
	CollectibleSystem.collect(w, p, CollectibleSystem.spawn(w, "coin"))
	CollectibleSystem.collect(w, p, CollectibleSystem.spawn(w, "coin"))
	assert_eq(w.money, money + int(w.pack.collectibles["coin"]["value"]))
	assert_true(w.box.is_empty())
	assert_true(not w.to_dict().has("box"))
	assert_eq(w.command({"type": "sell_collectible"}).error, "no_box")


func test_story_completes_and_its_finale_fires_once():
	var w := _home()
	w.advance(60)
	w.drain_events()
	_find_all(w, "embroidered_shoe")
	var evs := w.drain_events()
	assert_eq(_count(evs, "story_finale"), 1)
	assert_eq(StorySystem.visitors(w), ["embroidered_shoe"])
	# The same piece turning up again (a save from before it was found) changes nothing.
	var c := {"uid": 999, "type": "red_shoe", "story": "embroidered_shoe", "room": "well", "x": 0, "y": 0, "expires_at": w.now + 60}
	w.collectibles.append(c)
	CollectibleSystem.collect(w, w.people[0], 999)
	evs = w.drain_events()
	assert_eq(_count(evs, "story_finale"), 0)
	assert_eq(_count(evs, "story_stirred"), 0)
	assert_true(w.command({"type": "receive_visitor", "story": "embroidered_shoe"}).ok)
	assert_eq(_count(w.drain_events(), "story_done"), 1)


func test_the_story_stirs_once_at_half_its_pieces():
	var w := _home()
	w.advance(60)
	w.drain_events()
	var stirred_at := []
	for i in 6:
		_find_next(w, "embroidered_shoe")
		if _count(w.drain_events(), "story_stirred") > 0:
			stirred_at.append(i + 1)
	assert_eq(stirred_at, [3])
	assert_eq(StorySystem.midpoint(5), 3)
	assert_eq(StorySystem.midpoint(4), 2)
	assert_eq(StorySystem.midpoint(3), 2)
	for sid in w.pack.stories:
		assert_true(str(w.pack.stories[sid].get("midpoint", "")).length() >= 10, sid + " has a midpoint line")


func test_random_stories_unlock_by_chance_one_at_a_time_and_complete():
	var w := _home()
	for sid in RANDOM:
		w.pack.stories[sid]["unlock"]["chance_per_day"] = 1.0e7
	_new_day(w)
	var open := RANDOM.filter(func(sid): return w.stories.has(sid))
	assert_eq(open.size(), 1, "one story by chance at a time")
	_new_day(w)
	assert_eq(RANDOM.filter(func(sid): return w.stories.has(sid)).size(), 1)
	var seen := []
	var guard := 0
	while seen.size() < RANDOM.size() and guard < 10:
		guard += 1
		var sid: String = RANDOM.filter(func(s): return w.stories.has(s) and str(w.stories[s]["stage"]) != "done")[0]
		seen.append(sid)
		var money := w.money
		var fin: Dictionary = w.pack.stories[sid]["finale"]
		w.drain_events()
		# Its pieces turn up in its own places.
		for c in w.collectibles.duplicate():
			if c.has("story"):
				w.collectibles.erase(c)
		var uid := StorySystem.spawn_fragment(w, sid)
		assert_true(CollectibleSystem.find(w, uid).room in w.pack.stories[sid]["rooms"])
		w.collectibles.clear()
		_find_all(w, sid)
		var evs := w.drain_events()
		assert_eq(_count(evs, "story_finale"), 1)
		assert_eq(_count(evs, "story_done"), 1)
		assert_eq(w.stories[sid]["stage"], "done")
		assert_true(w.money >= money + int(fin.get("money", 0)))
		if str(fin.get("keepsake", "")) != "":
			assert_eq(w.box[fin.keepsake], 1)
		_new_day(w)
	assert_eq(seen.size(), 3)
	assert_eq(seen.duplicate().filter(func(s): return seen.count(s) == 1).size(), 3)


func test_random_stories_turn_up_at_the_packs_odds():
	# Only the stories' own clock, minute by minute, for six days (a roll a day for each, at 0.3): one
	# comes to light, and
	# its first piece turns up on the ground.
	var w := _home(11)
	w.pack.config["story_interval_min"] = 1.0e9
	for i in 6 * 1440:
		w.now += 60
		StorySystem.step(w, 60.0)
	var got := RANDOM.filter(func(sid): return w.stories.has(sid))
	assert_eq(got.size(), 1, str(w.stories.keys()))
	w.collectibles.clear()
	var uid := StorySystem.spawn_fragment(w, str(got[0]))
	assert_eq(str(CollectibleSystem.find(w, uid).get("story", "")), str(got[0]))
	# The balance runs (20 days, 3 households) see them too; see `BalanceRun` stories_done.


func test_box_survives_save_and_old_saves_keep_one_of_each():
	var w := _home()
	for i in 3:
		_pick(w, "egg")
	_pick(w, "hairpin")
	w.box["old_kite"] = 1
	var j := JSON.new()
	j.parse(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, j.data)
	assert_true(back != null)
	assert_eq(back.box, w.box)
	assert_eq(back.to_dict(), w.to_dict())
	# A save from before the box: what was found once is kept once; the rest stays sold.
	var old: Dictionary = j.data.duplicate(true)
	old.erase("box")
	var was := World.from_dict(w.pack, old)
	assert_eq(was.box, {"egg": 1, "hairpin": 1})
	var bad: Dictionary = j.data.duplicate(true)
	bad["box"]["nothing"] = 1
	assert_eq(WorldSave.restore(w.pack, bad).error, "pack_changed")
	bad = j.data.duplicate(true)
	bad["box"]["egg"] = -1
	assert_eq(WorldSave.restore(w.pack, bad).error, "corrupt")


func test_offline_pickups_go_into_the_box_unsold():
	var w := _home()
	w.advance(60)
	var collected := int(w.stats["collected"])
	var larder := int(w.stock.get("greens", 0)) + int(w.stock.get("herbs", 0))
	var s := w.catch_up(8 * 3600)
	var gained := int(w.stats["collected"]) - collected
	assert_true(gained > 0, "something was picked up while away")
	var kept := 0
	for k in w.box:
		kept += int(w.box[k])
	# What is eaten or used (greens, herbs) goes into the larder instead of the box (and may
	# have been cooked or used meanwhile: at most that many).
	var stocked := int(w.stock.get("greens", 0)) + int(w.stock.get("herbs", 0)) - larder
	assert_true(kept <= gained and kept + stocked <= gained, "%d kept, %d stocked, %d picked" % [kept, stocked, gained])
	assert_true(kept >= gained / 2, "most finds go into the box: %d of %d" % [kept, gained])
	assert_true(not w.drain_events().any(func(e): return e.type == "collectibles_sold"))
	assert_true(s.has("fragments"))


func test_validator_knows_the_new_keys():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(PackValidator.validate(p), [])
	p.stories["peddler_bell"]["unlock"]["chance_per_day"] = 0
	p.stories["paper_kite"]["finale"]["keepsake"] = "egg"
	p.stories["ferry_tags"]["midpoint"] = 3
	p.collectibles["egg"]["keepsake"] = "yes"
	p.config["collect_keep"] = 1
	var errs := PackValidator.validate(p)
	for needle in ["chance_per_day", "keepsake 'egg'", "midpoint must be a text", "keepsake must be true or false", "collect_keep"]:
		assert_true(errs.any(func(e): return e.contains(needle)), needle + " in " + str(errs))
