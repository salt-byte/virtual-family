extends TestCase
## Wishes: forming, granting (with the thanks), expiring, and who never wishes.

## A qijia world with one adult and wishes forming every hour (chance 1).
func _home(seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	w.pack.config["wish_chance_per_hour"] = 1.0
	w.pack.config["wish_check_min"] = 60  # one look an hour: chance 1 means a wish at the hour
	w.adopted_once = true
	TestKit.adult(w)
	return w


## Advances to just past the next hour boundary.
func _next_hour(w: World) -> void:
	w.advance(float(3600 - posmod(w.now, 3600)) + float(w.step_s))


func _wish_of(w: World, kind: String) -> String:
	for id in w.pack.wishes:
		if w.pack.wishes[id]["kind"] == kind:
			return id
	return ""


func test_smoke_has_no_wishes_and_nobody_forms_one():
	var w := TestKit.world("_smoke")
	var p := TestKit.adult(w)
	w.advance(6 * 3600)
	assert_true(w.pack.wishes.is_empty())
	assert_true(p.wish.is_empty())


func test_qijia_has_wishes_of_every_kind():
	var p := Pack.load_dir("res://packs/qijia")
	var kinds := {}
	for w in p.wishes.values():
		kinds[w.kind] = true
		assert_true(str(w.text).length() <= 10, w.text)
	for k in WishSystem.KINDS:
		assert_true(kinds.has(k), k)


func test_a_wish_forms_at_the_hour():
	var w := _home()
	var p := w.people[0]
	_next_hour(w)
	assert_true(not p.wish.is_empty())
	assert_true(w.pack.wishes.has(p.wish.id))
	assert_true(int(p.wish.expires_at) > w.now)
	assert_true(w.drain_events().any(func(e): return e.type == "wish_formed" and e.person == p.uid))


func test_item_wish_granted_by_using_the_item():
	var w := _home()
	var p := w.people[0]
	p.wish = {"id": "want_sugar_figure", "expires_at": w.now + 3600}
	p.needs["happy"] = 20.0
	w.money = 100
	assert_true(w.command({"type": "buy", "item": "sugar_figure"}).ok)
	assert_true(w.command({"type": "use_item", "item": "sugar_figure", "person": p.uid}).ok)
	var joy := float(w.pack.wishes["want_sugar_figure"]["joy"])
	assert_near(float(p.needs["happy"]), 20.0 + 30.0 + joy)
	assert_true(p.wish.is_empty())
	assert_eq(p.wish_last, "want_sugar_figure")
	assert_true(p.thanking(w.now))
	assert_true(w.drain_events().any(func(e): return e.type == "wish_granted" and e.wish == "want_sugar_figure"))


func test_other_item_does_not_grant():
	var w := _home()
	var p := w.people[0]
	p.wish = {"id": "want_sugar_figure", "expires_at": w.now + 3600}
	w.money = 100
	w.command({"type": "buy", "item": "osmanthus_cake"})
	w.command({"type": "use_item", "item": "osmanthus_cake", "person": p.uid})
	assert_eq(p.wish.id, "want_sugar_figure")


func test_thanks_lasts_two_fast_minutes_and_pauses_the_action():
	var w := _home()
	var p := w.people[0]
	w.advance(60)
	var guard := 0
	while p.current.is_empty() and guard < 100:
		w.advance(60); guard += 1
	p.wish = {"id": _wish_of(w, "praise"), "expires_at": w.now + 3600}
	var rem := int(p.current.remaining_s)
	var r := w.command({"type": "praise", "person": p.uid})
	assert_true(r.ok)
	assert_true(p.wish.is_empty())
	# 2 game minutes at action_speed 30 = 4 s, rounded up to one 5 s step.
	assert_eq(p.thanks_until - w.now, 5)
	w.advance(w.step_s - 1)
	assert_eq(int(p.current.remaining_s), rem, "paused while thanking")
	w.advance(w.step_s * 2)
	assert_true(not p.thanking(w.now))


func test_praise_wish_needs_a_successful_praise():
	var w := _home()
	var p := w.people[0]
	p.wish = {"id": _wish_of(w, "praise"), "expires_at": w.now + 3600}
	p.current = {}
	p.last_action = ""
	assert_true(not w.command({"type": "praise", "person": p.uid}).ok)
	assert_true(not p.wish.is_empty())


func test_body_wish_comes_first_and_is_granted_when_the_need_recovers():
	var w := _home()
	var p := w.people[0]
	p.wish = {"id": "want_cake", "expires_at": w.now + 99999}
	p.needs["fed"] = 20.0
	_next_hour(w)
	assert_eq(p.wish.id, "hot_meal")
	p.needs["fed"] = 70.0
	w.drain_events()
	w.advance(60)
	assert_true(p.wish.is_empty())
	assert_true(w.drain_events().any(func(e): return e.type == "wish_granted" and e.wish == "hot_meal"))


func test_object_and_room_wishes_are_granted_by_the_house():
	var w := _home()
	var p := w.people[0]
	w.money = 5000
	p.wish = {"id": "want_garden", "expires_at": w.now + 99999}
	assert_true(w.command({"type": "place", "object_type": "garden", "room": "yard", "x": 3, "y": 4}).ok)
	w.advance(60)
	assert_true(p.wish.is_empty())
	p.thanks_until = 0
	p.wish = {"id": "want_study", "expires_at": w.now + 99999}
	assert_true(w.command({"type": "build_room", "room": "study"}).ok)
	w.advance(60)
	assert_true(p.wish.is_empty())


func test_object_already_owned_is_not_wished_for():
	var w := _home()
	var p := w.people[0]
	w.money = 5000
	w.command({"type": "place", "object_type": "garden", "room": "yard", "x": 3, "y": 4})
	for i in 40:
		_next_hour(w)
		if not p.wish.is_empty():
			assert_true(p.wish.id != "want_garden")
			p.wish = {}


func test_expired_mood_wish_costs_mood_but_body_wish_does_not():
	var w := _home()
	var p := w.people[0]
	w.pack.config["wish_chance_per_hour"] = 0.0
	p.wish = {"id": "want_cake", "expires_at": w.now + w.step_s}
	p.needs["happy"] = 60.0
	w.advance(60)
	assert_true(p.wish.is_empty())
	assert_near(float(p.needs["happy"]), 50.0, 0.2)
	assert_true(w.drain_events().any(func(e): return e.type == "wish_expired"))
	p.needs["fed"] = 20.0
	p.needs["happy"] = 60.0
	p.wish = {"id": "hot_meal", "expires_at": w.now + w.step_s}
	w.advance(60)
	assert_true(p.wish.is_empty() or p.wish.id == "hot_meal")
	assert_near(float(p.needs["happy"]), 60.0, 0.2)


func test_babies_the_depressed_and_the_absent_form_no_wishes():
	var w := _home()
	var p := w.people[0]
	var baby := TestKit.adult(w, 0.5)
	p.mood = "depressed"
	_next_hour(w)
	assert_true(p.wish.is_empty())
	assert_true(baby.wish.is_empty())
	p.mood = ""
	w.offline = true
	_next_hour(w)
	w.offline = false
	assert_true(p.wish.is_empty())
	_next_hour(w)
	assert_true(not p.wish.is_empty())


func test_disliked_tags_are_never_wished():
	var w := _home(3)
	var p := w.people[0]
	p.dislikes = ["嘴馋"]
	p.likes = []
	for i in 60:
		_next_hour(w)
		if not p.wish.is_empty():
			var tags: Array = w.pack.wishes[p.wish.id]["likes"]
			assert_true(not tags.has("嘴馋"), p.wish.id)
			p.wish = {}
		p.needs["fed"] = 80.0
		p.needs["energy"] = 80.0
		p.needs["health"] = 100.0


func test_wish_and_thanks_survive_save_and_old_saves_load():
	var w := _home()
	var p := w.people[0]
	p.wish = {"id": "want_cake", "expires_at": w.now + 100}
	p.thanks_until = w.now + 5
	p.wish_last = "want_seeds"
	var d := w.to_dict()
	var j := JSON.new()
	j.parse(JSON.stringify(d))
	var back := World.from_dict(w.pack, j.data)
	assert_true(back != null)
	assert_eq(back.people[0].wish, p.wish)
	assert_eq(back.people[0].thanks_until, p.thanks_until)
	assert_eq(back.people[0].wish_last, "want_seeds")
	var old: Dictionary = j.data.duplicate(true)
	for k in ["wish", "wish_last", "thanks_until", "mood", "mood_low_s", "mood_ok_s", "generation"]:
		old["people"][0].erase(k)
	var o := World.from_dict(w.pack, old)
	assert_true(o != null)
	assert_true(o.people[0].wish.is_empty())
	var bad: Dictionary = j.data.duplicate(true)
	bad["people"][0]["wish"] = {"id": "no_such_wish", "expires_at": 5}
	assert_eq(WorldSave.restore(w.pack, bad).error, "pack_changed")
	bad["people"][0]["wish"] = {"id": 3}
	assert_eq(WorldSave.restore(w.pack, bad).error, "corrupt")


func test_a_book_teaches_a_reader_and_counts_for_a_child():
	var w := _home()
	var p := w.people[0]
	p.track = "reading"
	p.level = 0
	p.progress = 0.0
	p.aptitude = 1.0
	w.money = 500
	w.command({"type": "buy", "item": "shijing"})
	assert_true(w.command({"type": "use_item", "item": "shijing", "person": p.uid}).ok)
	assert_near(p.progress, 60.0)
	var kid := TestKit.adult(w, 8.0)
	w.command({"type": "buy", "item": "sanzijing"})
	w.command({"type": "use_item", "item": "sanzijing", "person": kid.uid})
	assert_eq(int(kid.childhood.get("trace_characters", 0)), 3)
	var farmer := TestKit.adult(w)
	farmer.track = "farming"
	w.command({"type": "buy", "item": "shijing"})
	w.command({"type": "use_item", "item": "shijing", "person": farmer.uid})
	assert_near(farmer.progress, 0.0)


func test_married_wish_is_granted_by_the_wedding():
	var w := _home()
	var p := w.people[0]
	p.wish = {"id": "want_family", "expires_at": w.now + 99999}
	w.next_proposal_at = w.now
	w.advance(60)
	assert_true(not w.proposals.is_empty())
	assert_true(w.command({"type": "answer_proposal", "id": w.proposals[0].id, "accept": true}).ok)
	assert_true(p.wish.is_empty())
	assert_true(p.thanking(w.now))
