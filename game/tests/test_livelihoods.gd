extends TestCase
## Choosing a livelihood at coming of age, changing it, and the pack data behind it.

const START_BUILT_NOTE := "rooms built at the start"


## _smoke with a second livelihood: "office" likes the action stare_window, "craft" likes
## the tag "food" (carried by eat) and the action watch_tv.
func _two_pack() -> Pack:
	var pk := Pack.load_dir("res://packs/_smoke")
	pk.livelihoods["office"]["affinity"] = ["stare_window"]
	var craft: Dictionary = pk.livelihoods["office"].duplicate(true)
	craft["id"] = "craft"
	craft["name"] = "Craft"
	craft["affinity"] = ["food", "watch_tv"]
	pk.livelihoods["craft"] = craft
	return pk


func _world(pk: Pack, seed := 1) -> World:
	var w := World.new(pk, seed)
	w.set_time(1767268800, 0)
	w.phase = "living"
	w.candidate = {}
	return w


func _child(w: World, age := 10.0) -> Person:
	var p := TestKit.adult(w, age)
	p.track = ""
	return p


func _adult_from(w: World) -> float:
	for s in w.pack.cfg("stages"):
		if str(s["id"]) == "adult":
			return float(s["from"])
	return 18.0


func test_child_finishing_an_action_is_tallied_only_with_several_livelihoods():
	var w := _world(_two_pack())
	var c := _child(w)
	var a := TestKit.adult(w)
	for p in [c, a]:
		p.current = {"action": "stare_window", "object_uid": -1, "target_uid": -1, "remaining_s": 0}
		AutonomySystem._finish(w, p)
	assert_eq(c.childhood, {"stare_window": 1})
	assert_eq(a.childhood, {})
	var s := TestKit.world()
	var sc := _child(s)
	sc.current = {"action": "stare_window", "object_uid": -1, "target_uid": -1, "remaining_s": 0}
	AutonomySystem._finish(s, sc)
	assert_eq(sc.childhood, {})


func test_coming_of_age_takes_up_the_best_matching_livelihood():
	var w := _world(_two_pack())
	var c := _child(w, _adult_from(w) - 0.0001)
	c.childhood = {"eat": 2, "watch_tv": 1, "stare_window": 2}  # craft 3, office 2
	c.level = 2
	c.progress = 5.0
	w.offline = true
	w.drain_events()
	w.advance(float(w.step_s) * 2)
	assert_eq(c.track, "craft")
	assert_eq(c.level, 0)
	assert_eq(c.progress, 0.0)
	var took := w.drain_events().filter(func(e): return e.type == "took_up")
	assert_eq(took.size(), 1)
	assert_eq(int(took[0].person), c.uid)
	assert_eq(str(took[0].track), "craft")


func test_coming_of_age_tie_is_an_rng_pick_among_the_best():
	var w := _world(_two_pack(), 7)
	var c := _child(w)
	c.childhood = {"eat": 1, "stare_window": 1}
	var copy := SimRng.new()
	copy.set_state(w.rng.get_state())
	LivelihoodSystem.come_of_age(w, c)
	var expect := str(copy.pick(["office", "craft"]))
	assert_eq(c.track, expect)
	assert_eq(w.rng.get_state(), copy.get_state())


func test_coming_of_age_with_no_data_picks_among_all():
	var seen := {}
	for seed in 20:
		var w := _world(_two_pack(), seed)
		var c := _child(w)
		LivelihoodSystem.come_of_age(w, c)
		seen[c.track] = true
	assert_eq(seen.size(), 2)


func test_single_livelihood_pack_draws_no_rng_and_keeps_the_track():
	var w := TestKit.world()
	var c := _child(w)
	c.track = "office"
	c.level = 1
	var before := w.rng.get_state()
	LivelihoodSystem.come_of_age(w, c)
	assert_eq(w.rng.get_state(), before)
	assert_eq(c.track, "office")
	assert_eq(c.level, 1)
	assert_true(not w.drain_events().any(func(e): return e.type == "took_up"))


func test_people_made_as_children_wait_for_a_livelihood_with_several():
	var w := _world(_two_pack())
	assert_eq(FamilySystem.make_person(w, [6, 12]).track, "")
	assert_true(w.pack.livelihoods.has(FamilySystem.make_person(w, [22, 29]).track))
	var s := TestKit.world()
	assert_eq(FamilySystem.make_person(s, [6, 12]).track, "office")


func test_adults_get_the_livelihood_their_likes_point_to():
	var pk := _two_pack()
	assert_eq(LivelihoodSystem.best_for_likes(pk, ["food"], []), ["craft"])
	assert_eq(LivelihoodSystem.best_for_likes(pk, [], ["food"]), ["office"])
	assert_eq(LivelihoodSystem.best_for_likes(pk, [], []), ["office", "craft"])
	for seed in 30:
		var w := World.new(Pack.load_dir("res://packs/qijia"), seed)
		var c := Person.from_dict(w.candidate)
		assert_true(c.track in LivelihoodSystem.best_for_likes(w.pack, c.likes, c.dislikes), "%s %s" % [c.likes, c.track])


func test_change_track_resets_and_emits():
	var w := _world(_two_pack())
	var p := TestKit.adult(w)
	p.track = "office"
	p.level = 2
	p.progress = 40.0
	p.work_carry = 0.5
	w.add_object("desk", "main", 0, 0)
	p.current = {"action": "work_desk", "object_uid": w.objects[-1].uid, "target_uid": -1, "remaining_s": 60}
	w.drain_events()
	assert_true(w.command({type = "change_track", person = p.uid, track = "craft"}).ok)
	assert_eq(p.track, "craft")
	assert_eq(p.level, 0)
	assert_eq(p.progress, 0.0)
	assert_eq(p.work_carry, 0.0)
	assert_true(p.current.is_empty(), "the old trade's work stops")
	var ev := w.drain_events().filter(func(e): return e.type == "changed_track")
	assert_eq(ev.size(), 1)
	assert_eq(str(ev[0].track), "craft")


func test_change_track_errors():
	var w := _world(_two_pack())
	var p := TestKit.adult(w)
	p.track = "office"
	var c := _child(w)
	var d := TestKit.adult(w)
	d.alive = false
	assert_eq(w.command({type = "change_track", person = 999, track = "craft"}).error, "no_person")
	assert_eq(w.command({type = "change_track", person = d.uid, track = "craft"}).error, "dead")
	assert_eq(w.command({type = "change_track", person = c.uid, track = "craft"}).error, "stage")
	assert_eq(w.command({type = "change_track", person = p.uid, track = "nope"}).error, "no_track")
	assert_eq(w.command({type = "change_track", person = p.uid, track = "office"}).error, "same_track")
	var e := TestKit.adult(w, 60.0)
	e.track = "office"
	assert_true(w.command({type = "change_track", person = e.uid, track = "craft"}).ok, "elders may change too")


func test_childhood_tally_saves_and_old_saves_load():
	var w := _world(Pack.load_dir("res://packs/qijia"))
	var c := _child(w)
	c.childhood = {"spin_top": 3, "watch_ants": 1}
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, d)
	assert_true(back != null)
	assert_eq(back.people[0].childhood, {"spin_top": 3, "watch_ants": 1})
	assert_true(back.people[0].childhood["spin_top"] is int)
	var old: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	old["people"][0].erase("childhood")
	var b2 := World.from_dict(w.pack, old)
	assert_true(b2 != null)
	assert_eq(b2.people[0].childhood, {})
	var bad: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	bad["people"][0]["childhood"] = {"spin_top": "x"}
	assert_true(World.from_dict(w.pack, bad) == null)
	var unknown: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	unknown["people"][0]["childhood"] = {"no_such_action": 1}
	assert_true(World.from_dict(w.pack, unknown) == null)


func test_validator_checks_affinity_and_work_places():
	var pk := _two_pack()
	assert_eq(PackValidator.validate(pk), [] as Array[String])
	pk.livelihoods["craft"]["affinity"] = ["no_such_thing"]
	assert_true(PackValidator.validate(pk).any(func(e): return e.begins_with("livelihoods.json: craft:") and e.contains("affinity")))
	pk.livelihoods["craft"]["affinity"] = "food"
	assert_true(PackValidator.validate(pk).any(func(e): return e.begins_with("livelihoods.json: craft:") and e.contains("affinity")))
	var pk2 := _two_pack()
	pk2.actions["work_desk"]["object"] = ""
	assert_true(PackValidator.validate(pk2).any(func(e): return e.begins_with("actions.json: work_desk:")))
	pk2.actions["work_desk"]["rooms"] = ["main"]
	assert_eq(PackValidator.validate(pk2), [] as Array[String])


## ---- qijia data ----

func _qijia() -> Pack:
	return Pack.load_dir("res://packs/qijia")


## Object types present in a fresh household: start objects plus props of start-built rooms.
func _start_objects(pk: Pack) -> Dictionary:
	var out := {}
	for o in pk.cfg("start_objects"):
		out[str(o["type"])] = true
	for r in pk.rooms:
		if bool(pk.rooms[r].get("built", false)):
			for pr in pk.rooms[r]["props"]:
				out[str(pr["type"])] = true
	return out


func test_qijia_has_seven_livelihoods_with_three_levels_and_affinity():
	var pk := _qijia()
	assert_eq(pk.livelihoods.size(), 7)
	for id in ["reading", "farming", "carpentry", "medicine", "embroidery", "tofu", "peddling"]:
		assert_true(pk.livelihoods.has(id), id)
		assert_eq((pk.livelihoods[id]["levels"] as Array).size(), 3, id)
		assert_true(not (pk.livelihoods[id].get("affinity", []) as Array).is_empty(), id)


func test_qijia_every_livelihood_can_work_in_a_fresh_household():
	var pk := _qijia()
	var objs := _start_objects(pk)
	for track in pk.livelihoods:
		var n := 0
		for id in pk.actions:
			var a: Dictionary = pk.actions[id]
			if str(a["work"].get("track", "")) != track:
				continue
			var ok := objs.has(str(a["object"]))
			for r in a["rooms"]:
				if bool(pk.rooms[r].get("built", false)):
					ok = true
			if ok:
				n += 1
		assert_true(n >= 3, "%s has %d work actions in %s" % [track, n, START_BUILT_NOTE])


func test_qijia_work_actions_name_real_tracks_and_suit_grown_ups():
	var pk := _qijia()
	var per := {}
	for id in pk.actions:
		var a: Dictionary = pk.actions[id]
		if a["work"].is_empty():
			continue
		var t := str(a["work"].get("track", ""))
		assert_true(pk.livelihoods.has(t), id)
		assert_eq(a["stages"], ["adult", "elder"], id)
		per[t] = int(per.get(t, 0)) + 1
	for t in pk.livelihoods:
		if t != "reading":
			assert_true(int(per.get(t, 0)) >= 4 and int(per.get(t, 0)) <= 6, "%s has %d" % [t, int(per.get(t, 0))])


func test_qijia_labels_are_short_and_unique():
	var pk := _qijia()
	var seen := {}
	for id in pk.actions:
		var label := str(pk.actions[id]["label"])
		assert_true(label.length() >= 4 and label.length() <= 12, "%s: %s" % [id, label])
		assert_true(not seen.has(label), "repeated label " + label)
		seen[label] = true
