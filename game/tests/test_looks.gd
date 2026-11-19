extends TestCase
## Looks (pack.json `looks`, LookSystem): who wears which; old saves and packs without looks
## keep "" and draw as before.


func _qijia(seed := 3) -> World:
	var w := World.new(Pack.load_dir("res://packs/qijia"), seed)
	w.set_time(1767268800, 0)
	return w


func test_smoke_has_no_looks_and_saves_stay_as_they_were():
	var w := TestKit.world("_smoke")
	var p := FamilySystem.make_person(w, [25, 25])
	assert_eq(p.look, "")
	assert_true(not p.to_dict().has("look"), "no new key in old-style saves")
	assert_true(LookSystem.looks(w.pack).is_empty())


func test_a_newcomer_gets_a_look_of_their_sex_and_stage():
	var w := _qijia()
	for i in 40:
		var p := FamilySystem.make_person(w, [20, 40])
		var e := LookSystem.entry(w.pack, p.look)
		assert_true(not e.is_empty(), p.look)
		assert_eq(str(e["sex"]), p.gender)
		assert_eq(str(e["stage"]), "adult")
	# The candidate to adopt carries it, so the adoption card can show the portrait.
	assert_true(str(w.candidate.get("look", "")) != "")


func test_the_choice_is_repeatable_and_leaves_the_world_dice_alone():
	var a := _qijia(9)
	var b := _qijia(9)
	var pa := FamilySystem.make_person(a, [25, 30])
	var pb := FamilySystem.make_person(b, [25, 30])
	assert_eq(pa.look, pb.look)
	# Choosing a look draws nothing from world.rng: the next draw matches a world where the
	# look is chosen again.
	LookSystem.assign(a, pa)
	assert_eq(a.rng.randf(), b.rng.randf())


func test_looks_lean_towards_the_livelihood():
	var w := _qijia()
	var hits := 0
	var n := 0
	for i in 200:
		var p := FamilySystem.make_person(w, [25, 30])
		p.gender = "male"
		p.track = "farming"
		p.look = "child"
		LookSystem.ensure(w, p)
		n += 1
		if p.look == "adult_1":
			hits += 1
	# 4 male looks, the farmer's weighted 4: about 4 / 7 of them.
	assert_true(hits > n * 0.4, "%d of %d" % [hits, n])


func test_a_child_grows_into_a_look_and_an_old_one_into_an_old_look():
	var w := _qijia()
	w.command({"type": "adopt"})
	var p := FamilySystem.make_person(w, [5, 5])
	p.gender = "female"
	LookSystem.assign(w, p)
	assert_eq(p.look, LookSystem.CHILD)
	w.add_person(p)
	p.age = LivelihoodSystem.adult_age(w.pack) - 0.0001
	w.offline = true
	w.advance(3600 * 2)
	var e := LookSystem.entry(w.pack, p.look)
	assert_eq(str(e.get("stage", "")), "adult", p.look)
	assert_eq(str(e["sex"]), "female")
	var old := 0.0
	for st in w.pack.cfg("stages"):
		if str(st["id"]) == "elder":
			old = float(st["from"])
	p.age = old - 0.0001
	w.advance(3600 * 2)
	assert_eq(p.look, "elder_2", "the old woman's look")


func test_a_wrong_look_after_a_change_of_sex_is_put_right_and_saved():
	var w := _qijia()
	var p := FamilySystem.make_person(w, [25, 30])
	p.gender = "female" if p.gender == "male" else "male"
	LookSystem.ensure(w, p)
	assert_eq(str(LookSystem.entry(w.pack, p.look)["sex"]), p.gender)
	var back := Person.from_dict(p.to_dict())
	assert_eq(back.look, p.look)
	# Someone from an old save has no look and keeps none.
	var legacy := Person.from_dict(p.to_dict().merged({"look": ""}, true))
	LookSystem.ensure(w, legacy)
	assert_eq(legacy.look, "")
