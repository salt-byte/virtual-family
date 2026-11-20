extends TestCase
## Livestock (`LivestockSystem` on top of `PetSystem`; qijia's pigs and hens).


func _q(seed := 1) -> World:
	var w := TestKit.world("qijia", seed)
	w.adopted_once = true
	for o in w.pack.cfg("start_objects"):
		w.add_object(str(o["type"]), str(o["room"]), int(o["x"]), int(o["y"]))
	for room in w.rooms_built.duplicate():
		HouseSystem.place_props(w, room)
	return w


## A world with the pigsty built (and its trough set down).
func _sty(seed := 1) -> World:
	var w := _q(seed)
	w.rooms_built.append("pigsty")
	HouseSystem.place_props(w, "pigsty")
	return w


func _keep_alive(p: Person) -> void:
	for n in p.needs:
		p.needs[n] = 90.0


func _events(w: World, type: String) -> Array:
	return w.drain_events().filter(func(e): return e.type == type)


func _feed(pet: Pet, v := 95.0) -> void:
	pet.needs["belly"] = v


func test_hens_come_with_the_house_on_the_first_adoption():
	var w := TestKit.world("qijia")
	w.phase = "adopting"
	w.candidate = FamilySystem.make_person(w, w.pack.cfg("adopt_age")).to_dict()
	assert_true(w.command({"type": "adopt"}).ok)
	var hens := w.pets.filter(func(p): return p.kind == "hen")
	assert_eq(hens.size(), 2)
	assert_eq(hens[0].how, "start")
	assert_eq(PetSystem.at_home(w), 0, "livestock are not pets for the pets' limit")
	assert_eq(LivestockSystem.in_pen(w, "coop_run"), 2)


func test_a_piglet_needs_the_pigsty_built_and_the_pen_holds_three():
	var w := _q()
	TestKit.adult(w)
	w.money = 2000
	assert_eq(w.command({"type": "buy_pet", "kind": "piglet"}).error, "no_pen")
	assert_true(w.command({"type": "build_room", "room": "pigsty"}).ok)
	for i in 3:
		assert_true(w.command({"type": "buy_pet", "kind": "piglet"}).ok, "piglet %d" % i)
	assert_eq(w.command({"type": "buy_pet", "kind": "piglet"}).error, "pen_full")
	assert_eq(w.money, 2000 - 500 - 3 * 90)
	# The pets keep their own limit beside the pen.
	assert_true(w.command({"type": "buy_pet", "kind": "dog"}).ok)
	var pig := w.pets[0]
	assert_true(pig.weight >= 14.0 and pig.weight <= 18.0, str(pig.weight))
	# The market lists them under the livestock section, and says why when the pen is full.
	var sec := {}
	for s in MarketSystem.catalogue(w):
		if s.id == "livestock":
			sec = s
	var piglet: Dictionary = (sec.entries as Array).filter(func(e): return e.kind == "pet" and e.id == "piglet")[0]
	assert_eq(piglet.why, "pen_full")
	assert_true((sec.entries as Array).any(func(e): return e.kind == "item" and e.id == "bran"))


func test_an_old_save_with_the_pigsty_built_has_no_pigs_and_loads():
	var w := _sty()
	TestKit.adult(w)
	var d := w.to_dict()
	d.erase("pets")
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(back != null)
	assert_true(back.rooms_built.has("pigsty") and back.pets.is_empty())
	back.advance(3600)
	assert_true(back.pets.is_empty(), "nothing comes by itself")


func test_a_fed_piglet_puts_on_weight_and_grows_into_a_pig():
	var w := _sty()
	var p := TestKit.adult(w)
	var pig := PetSystem.add(w, "piglet", "bought")
	pig.weight = 10.0
	var name := pig.given
	for h in 24:
		_keep_alive(p)
		_feed(pig)
		w.advance(3600)
	assert_near(pig.weight, 38.0, 1.0, "28 a day while fed")
	assert_eq(pig.kind, "piglet")
	pig.weight = 44.99
	_feed(pig)
	w.drain_events()
	w.advance(600)
	assert_eq(pig.kind, "pig")
	assert_eq(pig.given, name)
	assert_eq(_events(w, "pet_grew").size(), 1)
	assert_true(pig.weight >= 44.99)


func test_a_hungry_pig_loses_weight_and_calls_and_feeding_it_answers():
	var w := _sty()
	var p := TestKit.adult(w)
	var pig := PetSystem.add(w, "pig", "bought")
	pig.weight = 100.0
	pig.needs["belly"] = 10.0
	w.advance(120)
	assert_eq(str(pig.wish.get("id", "")), "pig_hungry")
	var notices := Notices.collect(w, ViewStrings.new(w.pack), {})
	assert_true(notices.any(func(n): return n.kind == "pet_hungry" and int(n.target) == pig.uid))
	for h in 6:
		_keep_alive(p)
		pig.needs["belly"] = 10.0
		w.advance(3600)
	assert_true(pig.weight < 100.0 and pig.weight > 97.0, "10 a day: %.2f" % pig.weight)
	# Dragged onto the trough with bran in store: a bucket of bran water for it.
	w.stock["bran"] = 2
	var trough: Dictionary = w.objects.filter(func(o): return o.type == "trough")[0]
	var r := w.command({"type": "drag", "person": p.uid, "object": int(trough.uid)})
	assert_true(r.ok, str(r))
	assert_true(str(r.action) in ["slop_pigs", "feed_pig_bran"])
	assert_eq(int(p.current["target_uid"]), pig.uid)
	w.drain_events()
	for i in 60:
		w.advance(10)
		if p.current.is_empty():
			break
	assert_true(float(pig.needs["belly"]) >= 50.0)
	assert_true(pig.wish.is_empty())
	assert_eq(_events(w, "pet_wish_granted").size(), 1)


func test_while_away_a_hungry_pig_keeps_its_weight_and_nothing_dies():
	var w := _sty()
	var p := TestKit.adult(w)
	var pig := PetSystem.add(w, "pig", "bought")
	pig.weight = 100.0
	pig.age = pig.lifespan - 0.1
	pig.needs["belly"] = 0.0
	pig.sick = true
	pig.needs["vigor"] = 5.0
	w.offline = true
	for h in 48:
		_keep_alive(p)
		w.advance(3600)
	w.offline = false
	assert_true(pig.home(), "neither old age nor illness while away")
	assert_true(pig.weight >= 100.0)
	assert_true(pig.wish.is_empty(), "no calling while nobody hears")


func test_an_untreated_sick_pig_dies_but_medicine_cures_it():
	var w := _sty()
	var p := TestKit.adult(w)
	var pig := PetSystem.add(w, "pig", "bought")
	var hog := PetSystem.add(w, "pig", "bought")
	for a in [pig, hog]:
		a.sick = true
		a.needs["vigor"] = 20.0
	w.money = 100
	assert_true(w.command({"type": "buy", "item": "pet_medicine"}).ok)
	assert_true(w.command({"type": "use_item", "item": "pet_medicine", "pet": hog.uid}).ok)
	assert_true(not hog.sick)
	w.drain_events()
	for h in 12:
		_keep_alive(p)
		_feed(pig)
		_feed(hog)
		w.advance(3600)
	assert_true(not pig.alive and pig.cause == "illness")
	assert_true(hog.home())
	assert_eq(w.pet_grief_until, 0, "nobody grieves for livestock")


func test_a_grown_pig_sells_at_the_market_and_a_light_one_does_not():
	var w := _sty()
	TestKit.adult(w)
	var pig := PetSystem.add(w, "pig", "bought")
	var runt := PetSystem.add(w, "pig", "bought")
	pig.weight = 120.0
	runt.weight = 80.0
	assert_eq(LivestockSystem.price(w, pig), 288)
	assert_eq(LivestockSystem.price(w, runt), 0)
	var sales: Array = []
	for s in MarketSystem.catalogue(w):
		for e in s.entries:
			if e.kind == "sale":
				sales.append(e)
	assert_eq(sales.size(), 1)
	assert_eq(int(sales[0].id), pig.uid)
	assert_eq(int(sales[0].price), 288)
	var before := w.money
	assert_eq(w.command({"type": "sell_pet", "pet": runt.uid}).error, "not_for_sale")
	assert_true(w.command({"type": sales[0].command.type, "pet": pig.uid}).ok)
	assert_eq(w.money, before + 288)
	assert_true(not pig.alive and pig.cause == "sold")
	assert_eq(LivestockSystem.in_pen(w, "pigsty"), 1)
	assert_eq(w.command({"type": "sell_pet", "pet": pig.uid}).error, "no_pet")


func test_a_buyer_comes_for_the_heaviest_pig_and_pays_a_little_more():
	var w := _sty()
	var p := TestKit.adult(w)
	w.pack.config["pets"]["buyer"]["chance_per_hour"] = 1.0
	var pig := PetSystem.add(w, "pig", "bought")
	var fat := PetSystem.add(w, "pig", "bought")
	pig.weight = 105.0
	fat.weight = 140.0
	_feed(pig)
	_feed(fat)
	w.advance(3600)
	assert_eq(int(w.pet_buyer.get("pet", -1)), fat.uid)
	var offer := int(w.pet_buyer["price"])
	assert_true(offer > LivestockSystem.price(w, fat), "%d" % offer)
	var notices := Notices.collect(w, ViewStrings.new(w.pack), {})
	assert_true(notices.any(func(n): return n.kind == "buyer"))
	# Saved and loaded, the offer waits on.
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(back.pet_buyer, w.pet_buyer)
	assert_true(w.command({"type": "answer_buyer", "accept": false}).ok)
	assert_true(w.pet_buyer.is_empty() and fat.home())
	_keep_alive(p)
	w.advance(3600)
	assert_true(not w.pet_buyer.is_empty())
	var before := w.money
	var r := w.command({"type": "answer_buyer", "accept": true})
	assert_true(r.ok)
	assert_eq(w.money, before + int(r.price))
	assert_true(not fat.alive and fat.cause == "sold")
	assert_eq(w.command({"type": "answer_buyer", "accept": true}).error, "no_buyer")


func test_no_buyer_calls_while_the_player_is_away():
	var w := _sty()
	TestKit.adult(w)
	w.pack.config["pets"]["buyer"]["chance_per_hour"] = 1.0
	var pig := PetSystem.add(w, "pig", "bought")
	pig.weight = 140.0
	w.offline = true
	w.advance(3 * 3600)
	assert_true(w.pet_buyer.is_empty())


func test_fed_hens_lay_eggs_in_the_coop_and_hungry_ones_stop():
	var w := _q()
	var p := TestKit.adult(w)
	w.pack.pets["hen"]["livestock"]["lays"]["per_day"] = 96.0  # four an hour, for a short test
	w.pack.pets["hen"]["livestock"]["young"]["chance_per_day"] = 0.0
	var hen := PetSystem.add(w, "hen", "bought")
	w.drain_events()
	_feed(hen)
	w.advance(1800)
	var ev := w.drain_events()
	var laid := ev.filter(func(e): return e.type == "pet_laid")
	assert_true(laid.size() >= 1)
	assert_eq(str(laid[0].kind), "egg")
	var spawned: Array = ev.filter(func(e): return e.type == "collectible_spawned" and int(e.uid) == int(laid[0].collectible))
	assert_eq(str(spawned[0].room), "coop_run", "laid in the coop")
	w.collectibles.clear()
	AutonomySystem.cancel(w, p)
	w.people.clear()  # nobody about to feed her
	for m in 120:
		hen.needs["belly"] = 10.0
		w.advance(60)
	assert_eq(_events(w, "pet_laid").size(), 0, "a hungry hen lays nothing")


func test_a_hen_sits_on_her_eggs_and_chicks_hatch_and_grow_into_hens():
	var w := _q()
	var p := TestKit.adult(w)
	w.pack.pets["hen"]["livestock"]["young"]["chance_per_day"] = 1440.0  # at once
	w.pack.pets["hen"]["livestock"]["lays"]["per_day"] = 0.0
	var hen := PetSystem.add(w, "hen", "bought")
	_feed(hen)
	w.advance(60)
	assert_true(hen.young_at > 0)
	w.pack.pets["hen"]["livestock"]["young"]["chance_per_day"] = 0.0
	w.advance(30)
	assert_eq(str(hen.current.get("action", "")), "hen_brood")
	w.drain_events()
	for h in 17:
		_keep_alive(p)
		_feed(hen)
		w.advance(3600)
	var chicks := w.pets.filter(func(q): return q.kind == "chick")
	assert_true(chicks.size() >= 2 and chicks.size() <= 3, str(chicks.size()))
	assert_eq(hen.young_at, 0)
	assert_eq(str(chicks[0].how), "born")
	assert_true(LivestockSystem.in_pen(w, "coop_run") <= 6)
	var chick: Pet = chicks[0]
	chick.age = 1.25
	_feed(chick)
	w.advance(60)
	assert_eq(chick.kind, "hen")
	# Saved and loaded with its new kind (its old actions forgotten).
	assert_true(World.from_dict(w.pack, JSON.parse_string(JSON.stringify(w.to_dict()))) != null)


func test_watching_the_pigs_only_happens_with_pigs_and_feeding_counts_as_farm_work():
	var w := _sty()
	var p := TestKit.adult(w)
	p.track = "farming"
	p.level = 0
	var key0 := PetSystem.home_key(w)
	var info: Dictionary = {}
	for i in AutonomySystem._table(w.pack):
		info[i.id] = i
	assert_true(not AutonomySystem._pet_fits(info["watch_pigs_root"], key0))
	var pig := PetSystem.add(w, "piglet", "bought")
	w.advance(5)
	assert_true(AutonomySystem._pet_fits(info["watch_pigs_root"], PetSystem.home_key(w)))
	assert_eq(AutonomySystem.target_kind(w.pack.actions["watch_pigs_root"]), "")
	pig.needs["belly"] = 20.0
	w.stock["scraps"] = 3
	_keep_alive(p)
	var progress := p.progress
	var r := w.command({"type": "drag", "person": p.uid, "pet": pig.uid})
	assert_true(r.ok, str(r))
	for i in 60:
		w.advance(10)
		if p.current.is_empty():
			break
	assert_true(p.progress > progress, "feeding the pigs is farm work for a farmer")


func test_a_dropped_person_feeds_a_hen_and_hens_never_run_off():
	var w := _q()
	var p := TestKit.adult(w)
	var hen := PetSystem.add(w, "hen", "bought")
	hen.needs["belly"] = 5.0
	hen.needs["fondness"] = 5.0
	for h in 30:
		_keep_alive(p)
		hen.needs["belly"] = 5.0
		hen.needs["fondness"] = 5.0
		hen.sick = false
		w.advance(3600)
	assert_true(hen.home(), "livestock never run away")
	var r := w.command({"type": "drag", "person": p.uid, "pet": hen.uid})
	assert_true(r.ok, str(r))
	assert_true(str(r.action) in ["feed_chickens", "catch_caterpillars"], str(r.action))


func test_livestock_settings_are_checked():
	var p := Pack.load_dir("res://packs/qijia")
	p.pets["hen"]["livestock"]["pen"] = "nowhere"
	p.pets["chick"]["livestock"]["grows_into"] = {"kind": "chick", "age": 1}
	p.pets["pig"]["livestock"]["sell"] = {"min_weight": 10}
	p.config["pets"]["buyer"]["kinds"] = ["hen"]
	p.actions["scratch_pig"]["pet"]["watch"] = "yes"
	assert_eq(PackValidator.validate(Pack.load_dir("res://packs/qijia")), [] as Array[String])
	var text := "\n".join(PackValidator.validate(p))
	for word in ["livestock.pen must", "grows_into.kind must", "livestock.sell needs", "buyer.kinds must", "pet.watch must"]:
		assert_true(text.contains(word), word + "\n" + text)
