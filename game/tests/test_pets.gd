extends TestCase
## Animals of the household (`PetSystem`, qijia's pets.json).


func _q(seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	w.adopted_once = true
	for o in w.pack.cfg("start_objects"):
		w.add_object(str(o["type"]), str(o["room"]), int(o["x"]), int(o["y"]))
	for room in w.rooms_built.duplicate():
		HouseSystem.place_props(w, room)
	return w


func _dog(w: World) -> Pet:
	return PetSystem.add(w, "dog", "bought")


## Tops up a lone grown-up's needs, so long runs test the animals, not the larder.
func _keep_alive(w: World, p: Person) -> void:
	for n in p.needs:
		p.needs[n] = 90.0
	p.age = 30.0


func _events(w: World, type: String) -> Array:
	return w.drain_events().filter(func(e): return e.type == type)


func test_smoke_pack_has_no_pets_and_saves_no_pet_keys():
	var w := TestKit.world("_smoke")
	TestKit.adult(w)
	assert_true(not PetSystem.enabled(w.pack))
	w.advance(6 * 3600)
	assert_true(w.pets.is_empty() and w.pet_offer.is_empty())
	var d := w.to_dict()
	for k in ["pets", "pet_offer", "pet_saved", "pet_grief_until"]:
		assert_true(not d.has(k), k)
	assert_eq(w.command({"type": "buy_pet", "kind": "dog"}).error, "no_pet_kind")


func test_buying_a_pet_spends_money_and_a_bird_needs_its_cage_first():
	var w := _q()
	TestKit.adult(w)
	w.money = 500
	var r := w.command({"type": "buy_pet", "kind": "dog"})
	assert_true(r.ok)
	assert_eq(w.money, 500 - int(w.pack.pets["dog"]["price"]))
	var dog := PetSystem.find(w, int(r.pet))
	assert_eq(dog.kind, "dog")
	assert_true(dog.home() and dog.given in w.pack.pets["dog"]["names"])
	assert_eq(w.command({"type": "buy_pet", "kind": "bird"}).error, "no_perch")
	assert_true(w.add_object("bird_cage", "hall", 0, 0) >= 0)
	assert_true(w.command({"type": "buy_pet", "kind": "bird"}).ok)
	assert_true(w.command({"type": "buy_pet", "kind": "cat"}).ok)
	assert_eq(w.command({"type": "buy_pet", "kind": "cat"}).error, "too_many_pets")


func test_a_stray_waits_at_the_gate_to_be_taken_in_or_shooed():
	var w := _q()
	TestKit.adult(w)
	w.pet_offer = {"kind": "dog", "given": "大黄", "age": 3.0, "expires_at": w.now + 3600}
	var r := w.command({"type": "answer_stray", "accept": true})
	assert_true(r.ok)
	var dog := PetSystem.find(w, int(r.pet))
	assert_eq(dog.how, "stray")
	assert_eq(dog.given, "大黄")
	assert_near(dog.age, 3.0)
	assert_true(w.pet_offer.is_empty())
	w.pet_offer = {"kind": "cat", "given": "花花", "age": 2.0, "expires_at": w.now + 3600}
	assert_true(w.command({"type": "answer_stray", "accept": false}).ok)
	assert_true(w.pet_offer.is_empty())
	assert_eq(w.pets.size(), 1)
	assert_eq(w.command({"type": "answer_stray", "accept": true}).error, "no_stray")


func test_strays_turn_up_by_themselves_now_and_then():
	var w := _q()
	var p := TestKit.adult(w)
	w.pack.config["pets"]["stray_chance_per_hour"] = 0.2  # qijia's 0.01 is too rare for a short test
	var seen := false
	for h in 48:
		_keep_alive(w, p)
		w.advance(3600)
		if not _events(w, "stray_arrived").is_empty():
			seen = true
			break
	assert_true(seen, "a stray came within two days")


func test_a_hungry_neglected_dog_runs_away_and_the_children_miss_it():
	var w := _q()
	TestKit.adult(w)
	var child := TestKit.adult(w, 8.0)
	var dog := _dog(w)
	dog.needs["belly"] = 0.0
	var happy0 := float(child.needs["happy"])
	var ran := false
	for m in 14 * 60:
		w.advance(60)
		if not dog.home():
			ran = true
			break
	assert_true(ran, "ran away within 14 hours")
	assert_eq(dog.state, "away")
	assert_true(dog.alive)
	assert_true(float(child.needs["happy"]) < happy0, "the child is sad")
	assert_true(w.pet_grief_until > w.now)
	assert_true(not PetSystem.has_kind(w, "dog"))


func test_a_pet_that_is_away_never_runs_away_again():
	var w := _q()
	var p := TestKit.adult(w)
	var dog := _dog(w)
	w.pack.config["pets"]["come_back_chance_per_hour"] = 0.0
	dog.needs["belly"] = 0.0
	var ran := 0
	for h in 40:
		_keep_alive(w, p)
		w.advance(3600)
		ran += _events(w, "pet_ran_away").size()
	assert_eq(ran, 1)
	assert_eq(dog.state, "away")


func test_a_runaway_may_come_back_by_itself_and_is_lost_for_good_after_a_while():
	var w := _q()
	var p := TestKit.adult(w)
	var dog := _dog(w)
	dog.state = "away"
	dog.away_since = w.now
	var back := false
	for h in 90:
		_keep_alive(w, p)
		w.advance(3600)
		if dog.home():
			back = true
			break
	assert_true(back, "came back within 90 hours (chance 0.06 an hour after 8)")
	assert_true(float(dog.needs["belly"]) >= 50.0)
	var cat := PetSystem.add(w, "cat", "bought")
	cat.state = "away"
	cat.away_since = w.now
	w.pack.config["pets"]["come_back_chance_per_hour"] = 0.0
	for h in 97:
		_keep_alive(w, p)
		w.advance(3600)
	w.pack.config["pets"]["come_back_chance_per_hour"] = 0.06
	assert_true(not cat.alive)
	assert_eq(cat.cause, "lost")


func test_a_sick_pet_left_alone_dies_and_stays_on_the_record():
	var w := _q()
	TestKit.adult(w)
	var dog := _dog(w)
	dog.sick = true
	dog.needs["vigor"] = 5.0
	w.advance(3 * 3600)
	assert_true(not dog.alive)
	assert_eq(dog.cause, "illness")
	assert_eq(w.pets.size(), 1)
	assert_eq(PetSystem.at_home(w), 0)


func test_medicine_or_the_doctor_cures_a_sick_pet():
	var w := _q()
	TestKit.adult(w)
	var dog := _dog(w)
	dog.sick = true
	w.money = 100
	assert_true(w.command({"type": "buy", "item": "pet_medicine"}).ok)
	assert_eq(w.command({"type": "use_item", "item": "pet_medicine", "pet": dog.uid}).error, "")
	assert_true(not dog.sick)
	# Someone in the doctor's line doses it themselves.
	var doc := TestKit.adult(w)
	doc.track = "medicine"
	dog.sick = true
	var r := w.command({"type": "drag", "person": doc.uid, "pet": dog.uid})
	assert_eq(r.get("action", ""), "dose_sick_pet")
	for i in 60:
		w.advance(5)
	assert_true(not dog.sick)


func test_nothing_harsh_happens_to_a_pet_while_the_player_is_away():
	var w := _q()
	TestKit.adult(w)
	var dog := _dog(w)
	dog.needs["belly"] = 0.0
	dog.needs["fondness"] = 0.0
	var cat := PetSystem.add(w, "cat", "bought")
	cat.sick = true
	cat.needs["vigor"] = 20.0
	var s := w.catch_up(48 * 3600)
	assert_true(dog.home(), "no running away offline")
	assert_true(cat.alive, "no death from illness offline")
	assert_true(float(cat.needs["vigor"]) >= float(w.pack.cfg("offline_need_floor")))
	assert_eq(s.pets_died, [])
	assert_true(dog.age > 0.5, "it got older")


func test_old_age_goes_on_while_away():
	var w := _q()
	TestKit.adult(w)
	var dog := _dog(w)
	dog.age = dog.lifespan - 0.2  # pets age at the pack's age_rate (0.4): 2 h
	var s := w.catch_up(4 * 3600)
	assert_true(not dog.alive)
	assert_eq(dog.cause, "old_age")
	assert_eq(s.pets_died.size(), 1)


func test_dragging_someone_onto_a_pet_looks_after_it():
	var w := _q()
	var p := TestKit.adult(w)
	var dog := _dog(w)
	dog.needs["fondness"] = 10.0
	var r := w.command({"type": "drag", "person": p.uid, "pet": dog.uid})
	assert_true(r.ok)
	assert_eq(r.action, "scratch_pet")
	assert_eq(int(p.current.target_uid), dog.uid)
	assert_true(dog.current.is_empty(), "it keeps still while scratched")
	for i in 60:
		w.advance(5)
	assert_true(float(dog.needs["fondness"]) >= 35.0, str(dog.needs["fondness"]))
	assert_eq(w.command({"type": "drag", "person": p.uid, "pet": 99999}).error, "no_target")


func test_people_look_after_pets_by_themselves():
	var w := BalanceRun.family_of_four("qijia", 2)
	var dog := _dog(w)
	dog.needs["fondness"] = 15.0
	dog.needs["coat"] = 10.0
	var cared := {}
	for m in 6 * 60:
		w.advance(60)
		for e in _events(w, "pet_cared"):
			cared[e.action] = true
	assert_true(cared.has("wash_dog"), str(cared))
	assert_true(cared.has("scratch_pet") or cared.has("play_with_pet"), str(cared))
	assert_true(float(dog.needs["coat"]) > 50.0)


func test_a_wish_for_a_dog_comes_true_when_one_moves_in():
	var w := _q()
	var p := TestKit.adult(w)
	p.wish = {"id": "want_dog", "expires_at": w.now + 3600}
	w.money = 500
	w.command({"type": "buy_pet", "kind": "dog"})
	w.advance(60)
	assert_true(p.wish.is_empty())
	assert_true(not _events(w, "wish_granted").is_empty())


func test_a_pet_wish_comes_true_by_its_item():
	var w := _q()
	TestKit.adult(w)
	var dog := _dog(w)
	dog.wish = {"id": "dog_bone", "expires_at": w.now + 3600}
	dog.needs["fondness"] = 40.0
	w.money = 100
	w.command({"type": "buy", "item": "pork_bone"})
	assert_eq(w.command({"type": "use_item", "item": "pork_bone", "pet": dog.uid}).error, "")
	assert_true(dog.wish.is_empty())
	assert_true(dog.thanks_until > w.now)
	assert_true(float(dog.needs["fondness"]) >= 80.0)
	w.command({"type": "buy", "item": "pork_bone"})
	var cat := PetSystem.add(w, "cat", "bought")
	assert_eq(w.command({"type": "use_item", "item": "pork_bone", "pet": cat.uid}).error, "wrong_pet")
	assert_eq(w.command({"type": "use_item", "item": "sugar_figure", "pet": cat.uid}).error, "no_item")


func test_pets_form_wishes_of_their_own():
	var w := _q()
	TestKit.adult(w)
	var cat := PetSystem.add(w, "cat", "bought")
	var formed := false
	for h in 48:
		w.advance(3600)
		if not _events(w, "pet_wish_formed").is_empty():
			formed = true
			break
	assert_true(formed)


func test_eaten_dishes_leave_scraps_for_the_dog():
	var w := _q()
	var p := TestKit.adult(w)
	var d := DishSystem.serve(w, "greens")
	DishSystem.eat(w, d)
	DishSystem.eat(w, d)
	assert_eq(int(w.stock.get("scraps", 0)), 1)
	assert_true(p.alive)


func test_a_dog_licks_the_bowls_left_out():
	var w := _q()  # nobody lives here yet, so nobody clears the bowls away first
	var dog := _dog(w)
	var m := MessSystem.spawn(w, "bowls", "hall")
	var licked := false
	for i in 4 * 720:  # four hours: its own doings last minutes to a couple of hours
		dog.needs["belly"] = minf(float(dog.needs["belly"]), 30.0)
		w.advance(5)
		if MessSystem.find(w, m).get("licked", false):
			licked = true
			break
	assert_true(licked)


func test_a_content_cat_saves_grain_and_a_content_dog_guards_the_yard():
	var w := _q()
	TestKit.adult(w)
	w.stock["food"] = 10
	var cat := PetSystem.add(w, "cat", "bought")
	cat.needs["fondness"] = 90.0
	for i in 4:
		PetSystem.on_consumed(w, "food", 1)
	assert_eq(int(w.stock["food"]), 11, "a quarter of four units back")
	assert_eq(_events(w, "pet_saved").size(), 1)
	var before := CollectibleSystem._ttl_s(w)
	var dog := _dog(w)
	dog.needs["fondness"] = 90.0
	assert_eq(CollectibleSystem._ttl_s(w), int(before * 1.5))
	dog.needs["belly"] = 10.0
	assert_eq(CollectibleSystem._ttl_s(w), before, "only a content dog guards")


func test_a_content_pet_cheers_the_children():
	var a := _q(4)
	var b := _q(4)
	for w in [a, b]:
		TestKit.adult(w, 8.0)
		w.people[0].needs["happy"] = 50.0
	var dog := _dog(b)
	dog.needs["fondness"] = 100.0
	PetSystem._cheer(b, PetSystem.cfg(b.pack), 3600.0)
	assert_near(float(b.people[0].needs["happy"]), 51.0)
	assert_true(PetSystem.content(b, dog))


func test_save_round_trip_keeps_pets_and_old_saves_still_load():
	var w := _q()
	TestKit.adult(w)
	var dog := _dog(w)
	dog.sick = true
	dog.wish = {"id": "dog_bone", "expires_at": w.now + 99}
	var gone := PetSystem.add(w, "cat", "stray")
	PetSystem.die(w, gone, "old_age")
	w.pet_offer = {"kind": "cat", "given": "阿狸", "age": 2.5, "expires_at": w.now + 600}
	w.pet_saved = {"food": 0.5}
	w.advance(600)
	var d := w.to_dict()
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(back != null)
	assert_eq(back.to_dict(), d)
	assert_eq(back.pets.size(), 2)
	assert_eq(back.pets[1].cause, "old_age")
	var old := d.duplicate(true)
	for k in ["pets", "pet_offer", "pet_saved", "pet_grief_until"]:
		old.erase(k)
	var o := World.from_dict(w.pack, old)
	assert_true(o != null and o.pets.is_empty())
	var bad := d.duplicate(true)
	bad["pets"][0]["kind"] = "dragon"
	assert_eq(WorldSave.restore(w.pack, bad).error, "pack_changed")


func test_validator_catches_bad_pet_data():
	var p := Pack.load_dir("res://packs/qijia")
	p.pets["dog"]["perch"] = "no_such_thing"
	p.actions["scratch_pet"]["pet"] = {"kinds": ["dragon"], "needs": {"belly": 5}}
	var errs := PackValidator.validate(p)
	assert_true(errs.any(func(e): return e.contains("perch")), str(errs))
	assert_true(errs.any(func(e): return e.contains("dragon")), str(errs))


# --- liveliness ---

## Watched (online), an awake dog and cat move on to something else every 15-60 s or so:
## no awake action outlasts a minute and a half, and in ten minutes each does several things.
func test_an_awake_pet_moves_on_to_something_new_within_a_minute():
	var w := BalanceRun.family_of_four("qijia", 3)  # noon
	var dog := _dog(w)
	var cat := PetSystem.add(w, "cat", "bought")
	var started := {dog.uid: w.now, cat.uid: w.now}
	var last := {dog.uid: "", cat.uid: ""}
	var count := {dog.uid: 0, cat.uid: 0}
	var longest := {dog.uid: 0, cat.uid: 0}
	for i in 10 * 12:
		w.advance(5)
		for p in [dog, cat]:
			var a := str(p.current.get("action", ""))
			if a == last[p.uid]:
				continue
			var act := PetSystem.action(w.pack, str(last[p.uid]))
			if last[p.uid] != "" and not act.get("rest", false):
				longest[p.uid] = maxi(int(longest[p.uid]), w.now - int(started[p.uid]))
			last[p.uid] = a
			started[p.uid] = w.now
			count[p.uid] = int(count[p.uid]) + 1
	for p in [dog, cat]:
		assert_true(int(count[p.uid]) >= 8, "%s changed %d times in 10 min" % [p.kind, count[p.uid]])
		assert_true(int(longest[p.uid]) <= 90, "%s kept one awake action %d s" % [p.kind, longest[p.uid]])
	# Every awake action of the three kinds lasts at most a minute watched.
	for k in ["dog", "cat", "bird"]:
		for a in w.pack.pets[k]["actions"]:
			if not a["rest"] and not a["sick"]:
				assert_true(PetSystem.duration_s(w, a, false) <= 60, a["id"])


## During a catch-up pets keep the slow pace (fewer choices, nobody sees them); an action
## begun then takes no longer than the watched pace once the player is back. What an action
## does per hour stays the same either way.
func test_pets_go_slow_during_a_catch_up_and_catch_up_when_watched_again():
	var w := _q()
	var dog := _dog(w)
	var nap: Dictionary = PetSystem.action(w.pack, "dog_sleep")
	assert_eq(PetSystem.duration_s(w, nap, false), 240)
	assert_eq(PetSystem.duration_s(w, nap, true), 2400)
	w.offline = true
	w.advance(5)
	assert_true(dog.current.get("slow", false), str(dog.current))
	dog.current["remaining_s"] = 2400
	w.offline = false
	w.advance(5)
	assert_true(not dog.current.has("slow"))
	var a := PetSystem.action(w.pack, str(dog.current["action"]))
	assert_true(int(dog.current["remaining_s"]) <= PetSystem.duration_s(w, a, false), str(dog.current))
	# Effects scale with the pace: per hour the same, online or off.
	var wash: Dictionary = PetSystem.action(w.pack, "cat_kang")  # whole steps either way
	var online := PetSystem.effect_factor(w, wash) / float(PetSystem.duration_s(w, wash, false))
	w.offline = true
	var offline := PetSystem.effect_factor(w, wash) / float(PetSystem.duration_s(w, wash, true))
	assert_near(online, offline, online * 0.05)
	assert_eq(PetSystem.effect_factor(w, PetSystem.action(w.pack, "dog_mud_roll")), 1.0, "rationed by the clock")
	assert_eq(PetSystem.effect_factor(w, PetSystem.action(w.pack, "dog_lick_bowls")), 1.0, "rationed by the bowls")


## The dog runs to the gate when someone comes back from an outing, and (now and then) to
## whoever the player sets down; never while it is sick. Reactions are never picked alone.
func test_the_dog_greets_people_coming_home_and_people_the_player_moves():
	var w := _q()
	var p := TestKit.adult(w)
	var dog := _dog(w)
	w.advance(5)
	w.drain_events()
	PetSystem.notice(w, "back", p)
	assert_eq(str(dog.current.get("action", "")), "dog_greet_gate")
	assert_eq(str(dog.current.get("room", "")), "gate")
	assert_eq(_events(w, "pet_reacted").size(), 1)
	# A real outing coming back does it too.
	dog.current = {}
	assert_true(w.command({"type": "go_out", "person": p.uid, "action": "go_to_market"}).ok)
	w.drain_events()
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["go_to_market"]))
	assert_true(_events(w, "pet_reacted").size() >= 1)
	# Dropped somewhere by the player: the dog comes up to them (chance 1 for the test).
	for a in w.pack.pets["dog"]["actions"]:
		if a["id"] == "dog_greet":
			a["chance"] = 1.0
	_keep_alive(w, p)
	AutonomySystem.cancel(w, p)
	var stove: int = w.objects.filter(func(o): return o.type == "stove")[0].uid
	var r := w.command({"type": "drag", "person": p.uid, "object": stove})
	assert_true(r.ok, str(r))
	assert_eq(str(dog.current.get("action", "")), "dog_greet")
	assert_eq(int(dog.current.get("follow", -1)), p.uid)
	# Sick, it stays where it is.
	dog.current = {}
	dog.sick = true
	PetSystem.notice(w, "back", p)
	assert_true(dog.current.is_empty())
	dog.sick = false
	var picked := false
	for i in 400:
		w.advance(5)
		picked = picked or str(dog.current.get("action", "")).begins_with("dog_greet")
	assert_true(not picked, "a greeting only comes when something happens")


## `follows: "anyone"` trails somebody at home, never someone out on an outing.
func test_the_dog_tags_along_after_someone_at_home():
	var w := _q()
	var p := TestKit.adult(w)
	var q := TestKit.adult(w)
	assert_true(w.command({"type": "go_out", "person": q.uid, "action": "go_to_market"}).ok)
	var who := PetSystem._followable(w, "anyone")
	assert_eq(who.size(), 1)
	assert_eq((who[0] as Person).uid, p.uid)


func test_validator_catches_bad_lively_pet_fields():
	var p := Pack.load_dir("res://packs/qijia")
	assert_eq(PackValidator.validate(p), [] as Array[String])
	var a: Dictionary = p.pets["dog"]["actions"][0]
	a["on"] = "sunrise"
	a["pace"] = "moonwalk"
	a["trot"] = -1
	a["chance"] = 2
	p.pets["cat"]["idle"] = "purr"
	p.pets["cat"]["actions"][0]["follows"] = "who"
	p.config["pets"]["offline_action_speed"] = 0
	var errs := PackValidator.validate(p)
	for word in ["on must", "pace must", "trot must", "chance must", "idle must", "follows must", "offline_action_speed"]:
		assert_true(errs.any(func(e): return e.contains(word)), "%s: %s" % [word, errs])
