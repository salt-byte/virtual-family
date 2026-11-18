extends TestCase
## Births: conception, pregnancy, birth, babies and their care, beds, generations, the wish for a
## child, house-born children marrying, and a relative arriving when only children are left.

## A qijia household at noon: the adopted head, married through a proposal, food in stock,
## no wishes.
func _couple(seed := 5) -> World:
	var w := World.new(Pack.load_dir("res://packs/qijia"), seed)
	w.set_time(1767268800, 0)
	w.command({"type": "adopt"})
	w.pack.config["wish_chance_per_hour"] = 0.0
	w.stock["food"] = 50
	w.next_proposal_at = w.now
	w.advance(60)
	w.command({"type": "answer_proposal", "id": w.proposals[0].id, "accept": true})
	for p in w.people:
		p.age = 25.0
	return w


func _wife(w: World) -> Person:
	for p in w.people:
		if p.gender == "female" and p.spouse != 0:
			return p
	return null


func _husband(w: World) -> Person:
	return w.person(_wife(w).spouse)


func _babies(w: World) -> Array:
	return w.people.filter(func(p: Person): return p.alive and p.stage(w.pack) == "baby")


func test_smoke_has_no_births():
	var w := TestKit.world("_smoke")
	assert_true(not BirthSystem.enabled(w.pack))
	var a := TestKit.adult(w)
	var b := TestKit.adult(w)
	a.gender = "male"
	b.gender = "female"
	a.spouse = b.uid
	b.spouse = a.uid
	w.advance(48 * 3600)
	assert_eq(w.people.size(), 2)
	assert_eq(b.pregnant_until, 0)


func test_wedding_links_the_couple():
	var w := _couple()
	var wife := _wife(w)
	assert_true(wife != null)
	var h := _husband(w)
	assert_eq(h.spouse, wife.uid)
	assert_eq(BirthSystem.fertile_husband(w, wife), h)


func test_conceives_then_gives_birth_to_a_house_born_child():
	var w := _couple()
	w.pack.config["births"]["chance_per_day"] = 1.0
	var wife := _wife(w)
	var h := _husband(w)
	h.family = "柳"
	wife.needs["happy"] = 100.0
	h.needs["happy"] = 100.0
	w.advance(3600)
	assert_true(wife.pregnant(), "conceived within the hour")
	assert_eq(wife.pregnant_by, h.uid)
	assert_true(w.drain_events().any(func(e): return e.type == "conceived" and e.person == wife.uid))
	# 0.75 year at 4 hours a year: due three hours after conceiving.
	assert_eq(wife.pregnant_until - w.now <= 3 * 3600, true)
	w.advance(3 * 3600 + 60)
	assert_true(not wife.pregnant())
	var kids := w.people.filter(func(p: Person): return p.mother == wife.uid)
	assert_eq(kids.size(), 1)
	var c: Person = kids[0]
	assert_eq(c.father, h.uid)
	assert_eq(c.family, "柳")
	assert_eq(c.generation, 1)
	assert_true(c.age < 0.1)
	assert_eq(c.stage(w.pack), "baby")
	assert_true((w.pack.names[c.gender] as Array).has(c.given))
	assert_eq(c.track, "")
	assert_true(w.drain_events().any(func(e): return e.type == "born" and e.person == c.uid and e.mother == wife.uid))


func test_no_child_from_a_sick_or_gloomy_couple_or_outside_the_fertile_years():
	var w := _couple()
	w.pack.config["births"]["chance_per_day"] = 1.0
	var wife := _wife(w)
	var h := _husband(w)
	h.illness = "chill"
	assert_eq(BirthSystem.hourly_chance(w, wife, h), 0.0)
	h.illness = ""
	h.mood = "depressed"
	assert_eq(BirthSystem.hourly_chance(w, wife, h), 0.0)
	h.mood = ""
	wife.needs["happy"] = 50.0
	h.needs["happy"] = 50.0
	assert_near(BirthSystem.hourly_chance(w, wife, h), 0.5)
	wife.age = 41.0
	assert_true(BirthSystem.fertile_husband(w, wife) == null)
	wife.age = 17.0
	assert_true(BirthSystem.fertile_husband(w, wife) == null)


func test_the_unborn_and_everyone_take_a_place_on_the_kang():
	var w := _couple()
	w.pack.config["births"]["chance_per_day"] = 1.0
	var wife := _wife(w)
	# One kang sleeps three: the couple and one child on the way.
	assert_eq(BirthSystem.free_places(w), 1)
	BirthSystem.conceive(w, wife, _husband(w))
	assert_eq(BirthSystem.free_places(w), 0)
	w.advance(3 * 3600 + 60)
	assert_eq(_babies(w).size(), 1)
	assert_eq(BirthSystem.free_places(w), 0)
	w.drain_events()
	w.advance(3 * 3600)
	assert_true(not wife.pregnant(), "no place left: no second child")
	var hints := w.drain_events().filter(func(e): return e.type == "births_blocked")
	assert_eq(hints.size(), 1, "the hint comes once")
	assert_true(w.birth_blocked)
	assert_true(w.add_object("kang", "west_room", 0, 0) >= 0 or w.add_object("kang", "hall", 0, 2) >= 0)
	assert_eq(BirthSystem.free_places(w), 3)
	w.advance(3600)
	assert_true(wife.pregnant())
	assert_true(not w.birth_blocked)


func test_pregnant_leave_heavy_work_alone_and_do_pregnancy_things():
	var w := _couple()
	var wife := _wife(w)
	var heavy := "chop_firewood"
	assert_true((w.pack.actions[heavy]["tags"] as Array).has("重活"))
	assert_eq(AutonomySystem.can_do(w, wife, "talk_to_belly", -1), "requires")
	assert_eq(AutonomySystem.can_do(w, wife, heavy, -1), "")
	BirthSystem.conceive(w, wife, _husband(w))
	assert_eq(AutonomySystem.can_do(w, wife, heavy, -1), "requires")
	assert_eq(AutonomySystem.can_do(w, wife, "talk_to_belly", -1), "")
	var ids := AutonomySystem.candidates(w, wife).map(func(c): return c.action)
	assert_true(not ids.has(heavy))
	for id in ids:
		assert_true(not (w.pack.actions[id]["tags"] as Array).has("重活"), id)
	# A little more tired while carrying.
	var e0 := float(wife.needs["energy"])
	var h0 := float(_husband(w).needs["energy"])
	wife.current = {}
	_husband(w).current = {}
	BirthSystem.step(w, 3600.0)
	assert_near(float(wife.needs["energy"]), e0 - 1.0)
	assert_near(float(_husband(w).needs["energy"]), h0)


func test_babies_do_baby_things_and_grown_ups_feed_them():
	var w := _couple()
	var wife := _wife(w)
	BirthSystem.conceive(w, wife, _husband(w))
	w.advance(3 * 3600 + 60)
	var baby: Person = _babies(w)[0]
	var seen := {}
	baby.needs["fed"] = 20.0
	var fed_low := 20.0
	for i in 120:
		w.advance(30)
		if not baby.current.is_empty():
			seen[baby.current["action"]] = true
		fed_low = minf(fed_low, float(baby.needs["fed"]))
	for id in seen:
		assert_eq(w.pack.actions[id]["stages"], ["baby"], id)
	assert_true(seen.size() >= 2, str(seen.keys()))
	assert_true(float(baby.needs["fed"]) > 50.0, "fed by the grown-ups: %.1f" % baby.needs["fed"])


func test_a_baby_left_unfed_dies_of_neglect():
	var w := _couple()
	BirthSystem.conceive(w, _wife(w), _husband(w))
	w.advance(3 * 3600 + 60)
	var baby: Person = _babies(w)[0]
	for p in w.people:
		AutonomySystem.cancel(w, p)
	w.pack.actions["feed_baby"]["stages"] = ["elder"]   # nobody in the house can feed it now
	w.pack.autonomy_table = []
	baby.needs["fed"] = 0.0
	baby.needs["health"] = 5.0
	w.advance(3600)
	assert_true(not baby.alive)
	assert_true(w.drain_events().any(func(e): return e.type == "person_died" and e.person == baby.uid and e.cause == "neglect"))


func test_dragging_a_grown_up_onto_a_baby_cares_for_it():
	var w := _couple()
	BirthSystem.conceive(w, _wife(w), _husband(w))
	w.advance(3 * 3600 + 60)
	var baby: Person = _babies(w)[0]
	var h := _husband(w)
	baby.needs["fed"] = 10.0
	var r := w.command({"type": "drag", "person": h.uid, "tend": baby.uid})
	assert_true(r.ok, str(r))
	assert_eq(r.action, "feed_baby")
	assert_eq(int(h.current["target_uid"]), baby.uid)
	# Someone else is already at it; a baby cannot care; nobody cares for a grown-up this way.
	assert_eq(w.command({"type": "drag", "person": _wife(w).uid, "tend": baby.uid}).error, "busy")
	w.advance(10)
	assert_true(float(baby.needs["fed"]) > 10.0)
	assert_eq(w.command({"type": "drag", "person": baby.uid, "tend": h.uid}).error, "no_target")
	assert_eq(w.command({"type": "drag", "person": h.uid, "tend": _wife(w).uid}).error, "no_target")


func test_the_second_generation_unlocks_the_little_shadow():
	var w := _couple()
	BirthSystem.conceive(w, _wife(w), _husband(w))
	w.advance(3 * 3600 + 60)
	var child: Person = _babies(w)[0]
	assert_true(not w.stories.has("little_shadow"))
	child.generation = 1
	var grand := Person.new()
	grand.generation = 2
	grand.age = 0.0
	for n in w.pack.needs:
		grand.needs[n] = 80.0
	w.add_person(grand)
	w.advance(120)
	assert_true(w.stories.has("little_shadow"))


func test_wish_for_a_child_is_granted_by_the_birth():
	var w := _couple()
	var wife := _wife(w)
	assert_true(BirthSystem.could_want_child(w, wife))
	assert_true(BirthSystem.could_want_child(w, _husband(w)))
	wife.wish = {"id": "want_baby", "expires_at": w.now + 99999}
	BirthSystem.conceive(w, wife, _husband(w))
	assert_true(not BirthSystem.could_want_child(w, wife), "already with child")
	w.advance(3 * 3600 + 60)
	assert_true(wife.wish.is_empty())
	assert_eq(wife.wish_last, "want_baby")


func test_a_house_born_child_grows_up_takes_up_a_livelihood_and_gets_a_proposal():
	var w := _couple()
	BirthSystem.conceive(w, _wife(w), _husband(w))
	w.advance(3 * 3600 + 60)
	var c: Person = _babies(w)[0]
	c.age = 17.99
	c.childhood = {"trace_characters": 20}
	w.next_proposal_at = w.now
	w.drain_events()
	w.advance(300)
	assert_eq(c.stage(w.pack), "adult")
	assert_eq(c.track, "reading")
	assert_true(w.drain_events().any(func(e): return e.type == "took_up" and e.person == c.uid))
	assert_eq(w.proposals.size(), 1)
	assert_eq(int(w.proposals[0]["for"]), c.uid)
	assert_true(w.proposals[0].person.gender != c.gender)
	assert_true(w.command({"type": "answer_proposal", "id": w.proposals[0].id, "accept": true}).ok)
	var spouse := w.person(c.spouse)
	assert_eq(spouse.spouse, c.uid)
	assert_eq(spouse.family, c.family)
	assert_eq(spouse.generation, 0)


func test_when_the_last_grown_up_dies_a_relative_takes_the_children_in():
	var w := _couple()
	BirthSystem.conceive(w, _wife(w), _husband(w))
	w.advance(3 * 3600 + 60)
	var baby: Person = _babies(w)[0]
	w.drain_events()
	w.kill_person(_husband(w), "old_age")
	assert_eq(w.people.size(), 3)
	w.kill_person(_wife(w), "old_age")
	assert_eq(w.phase, "living")
	var r: Person = w.people[-1]
	assert_true(r.alive and r.stage(w.pack) == "adult")
	assert_eq(r.family, baby.family)
	assert_eq(r.spouse, 0)
	assert_true(w.drain_events().any(func(e): return e.type == "relative_arrived" and e.person == r.uid))
	w.advance(3600)
	assert_true(baby.alive)


func test_births_survive_save_and_old_saves_link_the_couple():
	var w := _couple()
	var wife := _wife(w)
	BirthSystem.conceive(w, wife, _husband(w))
	w.birth_blocked = true
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, d)
	assert_true(back != null)
	assert_eq(back.to_dict(), w.to_dict())
	# A save written before births: no links, no pregnancy keys.
	var old: Dictionary = w.to_dict()
	old.erase("birth_blocked")
	for p in old["people"]:
		for k in ["spouse", "mother", "father", "pregnant_until", "pregnant_by"]:
			p.erase(k)
	var o := World.from_dict(w.pack, old)
	assert_true(o != null)
	var ow := _wife(o)
	assert_true(ow != null)
	assert_eq(o.person(ow.spouse).spouse, ow.uid)
	assert_true(not ow.pregnant())
	# Bad values are refused.
	var bad: Dictionary = w.to_dict()
	bad["people"][0]["spouse"] = -3
	assert_true(World.from_dict(w.pack, bad) == null)


func test_validator_checks_births():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(p.errors, [] as Array[String])
	p.config["births"]["beds"] = ["nope"]
	p.config["births"]["chance_per_day"] = 2
	p.config["births"]["oops"] = 1
	p.actions["feed_baby"]["tends"] = {"nope": 5}
	p.actions["talk_to_belly"]["requires"] = {"pregnant": "yes"}
	var errs := PackValidator.validate(p)
	var all := "\n".join(errs)
	for bit in ["births.beds", "chance_per_day", "oops", "tends key 'nope'", "requires.pregnant"]:
		assert_true(all.contains(bit), bit)
