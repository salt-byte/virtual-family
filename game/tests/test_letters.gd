extends TestCase
## Letters to the player (`LetterSystem`): who writes what and in which hand, how often,
## answering them, what an absence leaves, saving, and a pack without letters.


## A living qijia household (one adopted grown-up) with every minor letter certain.
func _q(seed := 11) -> World:
	var w := BalanceRun.setup("qijia", seed)
	var c: Dictionary = w.pack.config["letters"]
	c["chance"] = {"thanks": 1.0, "ask": 1.0, "sad": 1.0, "ill": 1.0}
	w.drain_events()
	return w


func _head(w: World) -> Person:
	return w.people[0]


## One more person of the house: `age` years, in livelihood `track`, with `likes`.
func _member(w: World, given: String, age: float, track := "farming", likes: Array = []) -> Person:
	var p := FamilySystem.make_person(w, [age, age])
	p.given = given
	p.family = _head(w).family
	p.track = track if age >= 18.0 else ""
	p.likes = likes
	p.dislikes = []
	w.add_person(p)
	return p


func _step(w: World) -> void:
	w.advance(float(w.step_s))


func _last(w: World) -> Dictionary:
	return w.letters.back() if not w.letters.is_empty() else {}


func _kinds(w: World) -> Array:
	return w.letters.map(func(l): return str(l["kind"]))


func _no_slot_left(l: Dictionary) -> bool:
	var all := str(l["text"]) + str(l["sign"]) + str(l["writer"])
	for ch in l["choices"]:
		all += str(ch["label"])
	return not all.contains("{") and not all.contains("}")


func test_smoke_pack_has_no_letters_and_runs_as_before():
	var w := BalanceRun.setup("_smoke", 3)
	assert_true(not LetterSystem.enabled(w.pack))
	assert_true(w._letter_watch.is_empty())
	var s := w.catch_up(6 * 3600)
	w.advance(3 * 3600)
	assert_true(w.letters.is_empty())
	assert_true(w._letter_news.is_empty())
	assert_eq(s["letters"], [])
	assert_true(not w.to_dict().has("letters"))


func test_qijia_loads_letters_and_its_settings():
	var w := _q()
	assert_true(w.pack.is_valid(), str(w.pack.errors))
	assert_true(LetterSystem.enabled(w.pack))
	assert_true(w.pack.letters.size() >= 40)
	var kinds := {}
	for t in w.pack.letters.values():
		kinds[str(t["kind"])] = true
	for k in LetterSystem.KINDS:
		assert_true(kinds.has(k), "a template for " + k)


func test_every_template_uses_only_slots_its_kind_fills():
	var common := ["name", "full", "scribe", "who", "who_full"]
	var by_kind := {"thanks": ["wish"], "ask": ["wish"], "sad": [], "depressed": [], "ill": [],
		"birth": ["child"], "death": ["dead", "dead_full", "age"], "married": ["spouse", "spouse_full"],
		"took_up": ["job", "alt"], "pet_ran": ["pet", "pet_kind"], "pet_back": ["pet", "pet_kind"],
		"proposal": ["match", "match_full", "match_kind", "age", "savings", "target"], "kin": [], "story": []}
	var pack := Pack.load_dir("res://packs/qijia")
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for id in pack.letters:
		var t: Dictionary = pack.letters[id]
		var ok: Array = common + by_kind[str(t["kind"])]
		var texts := [str(t["text"]), str(t["sign"]), str(t["from"])]
		for ch in t["choices"]:
			texts.append(str(ch["label"]))
		for h in pack.cfg("letters")["hands"]:
			texts.append(str(h["sign"]))
		for s in texts:
			for m in re.search_all(s):
				assert_true(ok.has(m.get_string(1)), "%s uses {%s}" % [id, m.get_string(1)])


func test_a_granted_wish_brings_a_thank_you_in_the_writers_hand():
	var w := _q()
	var kid := _member(w, "小满", 8.0)
	kid.wish = {"id": "want_sugar_figure", "expires_at": w.now + 3600}
	WishSystem.grant(w, kid)
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "thanks")
	assert_eq(l["hand"], "child")
	assert_eq(int(l["from"]), kid.uid)
	assert_true(str(l["text"]).contains("想要个糖人"), str(l["text"]))
	assert_eq(l["sign"], "小满")
	assert_true(_no_slot_left(l))
	assert_true((l["choices"] as Array).is_empty(), "a thank-you is only read")
	assert_eq(LetterSystem.unread(w), 1)


func test_a_reader_writes_neatly_and_a_farmer_has_someone_write_for_him():
	var w := _q()
	var head := _head(w)
	head.track = "reading"
	head.likes = []
	var farmer := _member(w, "大柱", 40.0, "farming")
	assert_eq(LetterSystem.hand_of(w, head)["id"], "scholar")
	assert_eq(LetterSystem.hand_of(w, farmer)["id"], "dictated")
	w.emit("fell_ill", {"person": farmer.uid})
	_step(w)
	var l := _last(w)
	assert_eq(l["hand"], "dictated")
	assert_eq(l["sign"], "大柱口述　%s代书" % head.given)
	# Nobody at home who can write: the scribe from outside takes it down.
	head.track = "farming"
	w.letter_minor_at = 0
	w.letters.clear()
	w.emit("fell_ill", {"person": farmer.uid})
	_step(w)
	assert_true(str(_last(w)["sign"]).ends_with("巷口的周先生代书"), str(_last(w)["sign"]))


func test_a_bookish_child_still_writes_like_a_child():
	var w := _q()
	var kid := _member(w, "石头", 9.0, "", ["书痴"])
	assert_eq(LetterSystem.hand_of(w, kid)["id"], "child")
	var grown := _member(w, "砚之", 30.0, "farming", ["书痴"])
	assert_eq(LetterSystem.hand_of(w, grown)["id"], "scholar")


func test_minor_letters_keep_their_distance_and_stop_while_unread_pile_up():
	var w := _q()
	# Only the illness letters this test sends: nothing else of the household writes.
	w.pack.config["letters"]["chance"] = {"thanks": 0.0, "ask": 0.0, "sad": 0.0, "ill": 1.0}
	w.pack.config["letters"]["kin_chance_per_day"] = 0.0
	w.next_proposal_at = w.now + 30 * 86400
	var a := _member(w, "青禾", 30.0, "medicine")
	w.emit("fell_ill", {"person": a.uid})
	_step(w)
	w.emit("fell_ill", {"person": a.uid})
	_step(w)
	assert_eq(w.letters.size(), 1, "the second came within min_gap_min")
	w.advance(26 * 60)
	w.emit("fell_ill", {"person": a.uid})
	_step(w)
	assert_eq(w.letters.size(), 2, str(w.letters.map(func(l): return [l["kind"], l["t"], l["from"]])))
	w.advance(26 * 60)
	w.emit("fell_ill", {"person": a.uid})
	_step(w)
	w.advance(26 * 60)
	w.emit("fell_ill", {"person": a.uid})
	_step(w)
	assert_eq(w.letters.size(), 3, "unread_max 3 stops the fourth")
	w.command({"type": "read_letter", "letter": int(w.letters[0]["id"])})
	w.emit("fell_ill", {"person": a.uid})
	_step(w)
	assert_eq(w.letters.size(), 4)


func test_important_news_always_comes():
	var w := _q()
	var a := _member(w, "青禾", 30.0, "medicine")
	var b := _member(w, "长庚", 60.0, "farming")
	a.spouse = b.uid
	b.spouse = a.uid
	w.letter_minor_at = w.now
	for i in 4:
		w.letters.append({"id": w.letter_next, "t": w.now, "kind": "thanks", "template": "", "from": 0, "about": 0,
			"writer": "", "hand": "", "text": "", "sign": "", "choices": [], "answer": -1, "read": false})
		w.letter_next += 1
	w.kill_person(b, "old_age")
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "death")
	assert_eq(int(l["from"]), a.uid, "the spouse writes")
	assert_true(str(l["text"]).contains("长庚"), str(l["text"]))
	assert_true(_no_slot_left(l))


func test_a_proposal_letter_can_be_accepted_and_the_wedding_letter_follows():
	var w := _q()
	w.next_proposal_at = w.now
	w.advance(60)
	assert_eq(w.proposals.size(), 1)
	var l := _last(w)
	assert_eq(l["kind"], "proposal")
	assert_eq(l["writer"], "王媒婆")
	assert_eq(l["from"], 0)
	assert_eq((l["choices"] as Array).size(), 3)
	assert_true(str(l["text"]).contains(_head(w).given), str(l["text"]))
	assert_true(_no_slot_left(l))
	var r := w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0})
	assert_true(r.ok, str(r))
	assert_true(w.proposals.is_empty())
	assert_eq(w.people.size(), 2)
	assert_eq(int(l["answer"]), 0)
	assert_true(not LetterSystem.is_open(w, l))
	_step(w)
	assert_eq(_last(w)["kind"], "married")
	var again := w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 1})
	assert_eq(again.error, "answered")


func test_a_proposal_letter_goes_stale_when_the_proposal_is_gone():
	var w := _q()
	w.next_proposal_at = w.now
	w.advance(60)
	var l := _last(w)
	w.command({"type": "answer_proposal", "id": int(w.proposals[0]["id"]), "accept": false})
	assert_true(not LetterSystem.choice_open(w, l, 0))
	assert_eq(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0}).error, "too_late")
	assert_eq(w.command({"type": "answer_letter", "letter": 999, "choice": 0}).error, "no_letter")
	assert_eq(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 7}).error, "no_choice")


func test_answering_a_request_keeps_or_drops_the_wish_and_later_keeps_it_open():
	var w := _q()
	var kid := _member(w, "杏儿", 8.0)
	kid.wish = {"id": "want_cake", "expires_at": w.now + 3600}
	w.emit("wish_formed", {"person": kid.uid, "wish": "want_cake"})
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "ask")
	assert_true(str(l["text"]).contains("想吃块桂花糕"))
	var until := int(kid.wish["expires_at"])
	assert_true(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 2}).ok, "later")
	assert_true(bool(l["read"]))
	assert_eq(int(l["answer"]), -1)
	assert_true(LetterSystem.is_open(w, l))
	var happy0 := float(kid.needs["happy"])
	assert_true(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0}).ok)
	assert_eq(int(kid.wish["expires_at"]), until + 12 * 3600)
	assert_true(float(kid.needs["happy"]) > happy0)
	# A second request, refused: the wish is let go.
	kid.wish = {"id": "want_seeds", "expires_at": w.now + 3600}
	w.letter_minor_at = 0
	w.emit("wish_formed", {"person": kid.uid, "wish": "want_seeds"})
	_step(w)
	var l2 := _last(w)
	assert_true(w.command({"type": "answer_letter", "letter": int(l2["id"]), "choice": 1}).ok)
	assert_true(kid.wish.is_empty())
	assert_eq(kid.wish_last, "want_seeds")


func test_body_and_praise_wishes_bring_no_request():
	var w := _q()
	var a := _member(w, "青禾", 30.0, "medicine")
	w.emit("wish_formed", {"person": a.uid, "wish": "hot_meal"})
	w.emit("wish_formed", {"person": a.uid, "wish": "want_a_good_word"})
	_step(w)
	assert_true(w.letters.is_empty())


func test_a_comforting_reply_to_a_low_letter_lifts_the_mood_and_counts_as_care():
	var w := _q()
	var a := _member(w, "青禾", 30.0, "medicine")
	a.needs["happy"] = 10.0
	a.cared_at = w.now - 20 * 3600
	w.emit("mood_changed", {"person": a.uid, "mood": "depressed", "was": "sad"})
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "depressed")
	assert_true(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0}).ok)
	assert_near(float(a.needs["happy"]), 25.0, 0.5)
	assert_eq(a.cared_at, w.now)


func test_coming_of_age_letter_can_send_them_to_another_trade():
	var w := _q()
	var y := _member(w, "望舒", 18.0, "farming")
	w.emit("took_up", {"person": y.uid, "track": "farming"})
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "took_up")
	assert_true(str(l["text"]).contains("种田"), str(l["text"]))
	var alt := str(l["choices"][1]["effect"]["track"])
	assert_true(alt != "farming" and w.pack.livelihoods.has(alt))
	assert_true(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 1}).ok)
	assert_eq(y.track, alt)


func test_a_birth_letter_comes_from_a_parent():
	var w := _q()
	var mum := _member(w, "映雪", 25.0, "peddling")
	var baby := _member(w, "豆豆", 0.0)
	baby.mother = mum.uid
	baby.gender = "female"
	w.emit("born", {"person": baby.uid, "mother": mum.uid, "father": 0})
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "birth")
	assert_eq(int(l["from"]), mum.uid)
	assert_true(str(l["text"]).contains("闺女") and str(l["text"]).contains("豆豆"), str(l["text"]))


func test_a_runaway_pet_letter_is_written_by_a_child():
	var w := _q()
	var kid := _member(w, "小满", 8.0)
	var dog := PetSystem.add(w, "dog", "bought")
	w.drain_events()
	w.emit("pet_ran_away", {"pet": dog.uid, "hungry": true})
	_step(w)
	var l := _last(w)
	assert_eq(l["kind"], "pet_ran")
	assert_eq(int(l["from"]), kid.uid)
	assert_eq(l["template"], "pet_ran_child_hungry")
	assert_true(str(l["text"]).contains(dog.given))


func test_kin_send_money_now_and_then_and_a_gift_can_be_taken():
	var w := _q()
	w.pack.config["letters"]["kin_chance_per_day"] = 24.0
	# Other letters waiting unread must not hold the kin back (in some random streams three
	# arrive first and fill `unread_max`).
	w.pack.config["letters"]["unread_max"] = 99
	var t0 := w.now
	while _kinds(w).find("kin") < 0 and w.now - t0 < 30 * 3600:
		w.advance(3600)
	var l := w.letters[_kinds(w).find("kin")]
	assert_true(str(l["writer"]).contains("远房"), str(l["writer"]))
	var money0 := w.money
	if str(l["template"]) == "kin_gift":
		assert_true(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0}).ok)
		assert_eq(w.money, money0 + 40)
	elif str(l["template"]) == "kin_borrow":
		w.money = 10
		assert_eq(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0}).error, "no_money")
		w.money = 100
		assert_true(w.command({"type": "answer_letter", "letter": int(l["id"]), "choice": 0}).ok)
		assert_eq(w.money, 40)
	else:
		assert_true((l["choices"] as Array).is_empty())


func test_an_old_story_sends_a_letter_when_it_unlocks():
	var w := _q()
	w.emit("story_unlocked", {"story": "scholar_silver"})
	w.emit("story_unlocked", {"story": "embroidered_shoe"})  # no letter for this moment
	_step(w)
	assert_eq(w.letters.size(), 1)
	assert_eq(_last(w)["writer"], "村塾的周先生")
	assert_eq(_last(w)["sign"], "周某　顿首")


func test_an_absence_keeps_only_the_most_important_letters():
	var w := _q()
	var a := _member(w, "青禾", 30.0, "medicine")
	var b := _member(w, "长庚", 30.0, "farming")
	a.spouse = b.uid
	b.spouse = a.uid
	w.pack.config["letters"]["offline_max"] = 2
	w.pack.config["letters"]["min_gap_min"] = 0
	w.pack.config["letters"]["unread_max"] = 99
	# Queue a pile of news for the first step of the catch-up.
	for i in 3:
		w.emit("fell_ill", {"person": a.uid})
	w.emit("story_unlocked", {"story": "scholar_silver"})
	var held := w.drain_events()
	w._letter_news = held.duplicate()
	w.emit("person_died", {"person": b.uid, "cause": "old_age"})
	w.drain_events()
	var s := w.catch_up(600)
	assert_eq((s["letters"] as Array).size(), 2)
	assert_eq(w.letters.size(), 2, str(w.letters.map(func(l): return [l["kind"], l["t"], l["from"]])))
	assert_eq(str(w.letters.filter(func(l): return int(l["id"]) == int(s["letters"][0]))[0]["kind"]), "death")
	assert_eq(str(w.letters.filter(func(l): return int(l["id"]) == int(s["letters"][1]))[0]["kind"]), "story")


func test_letters_survive_a_save_and_an_old_save_loads_without_them():
	var w := _q()
	w.next_proposal_at = w.now
	w.advance(60)
	var kid := _member(w, "杏儿", 8.0)
	kid.wish = {"id": "want_cake", "expires_at": w.now + 3600}
	w.emit("wish_formed", {"person": kid.uid, "wish": "want_cake"})
	_step(w)
	assert_eq(w.letters.size(), 2, str(w.letters.map(func(l): return [l["kind"], l["t"], l["from"]])))
	var d := w.to_dict()
	var back := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(d)))
	assert_true(back != null)
	assert_eq(back.to_dict(), d)
	assert_eq(back.letters.size(), 2)
	assert_eq(typeof(back.letters[0]["id"]), TYPE_INT)
	assert_true(back.command({"type": "answer_letter", "letter": int(back.letters[1]["id"]), "choice": 0}).ok)
	var old := d.duplicate(true)
	old.erase("letters")
	var o := World.from_dict(w.pack, JSON.parse_string(JSON.stringify(old)))
	assert_true(o != null)
	assert_true(o.letters.is_empty())
	assert_eq(o.letter_next, 1)
	var bad := d.duplicate(true)
	bad["letters"]["list"][0]["choices"][0]["effect"]["type"] = "fly"
	assert_eq(WorldSave.restore(w.pack, JSON.parse_string(JSON.stringify(bad)))["error"], "corrupt")


func test_old_letters_are_pruned_read_ones_first():
	var w := _q()
	w.pack.config["letters"]["keep"] = 2
	var a := _member(w, "青禾", 30.0, "medicine")
	w.pack.config["letters"]["min_gap_min"] = 0
	w.pack.config["letters"]["unread_max"] = 99
	for i in 3:
		w.emit("fell_ill", {"person": a.uid})
		_step(w)
		if i == 0:
			w.command({"type": "read_letter", "letter": int(w.letters[0]["id"])})
	assert_eq(w.letters.size(), 2, str(w.letters.map(func(l): return [l["kind"], l["t"], l["from"]])))
	assert_eq(w.letters.map(func(l): return int(l["id"])), [2, 3])


func test_the_validator_checks_letters():
	var p := Pack.load_dir("res://packs/qijia")
	p.letters["bad"] = {"id": "bad", "kind": "gossip", "text": "x", "hand": ["nobody"], "weight": 1.0, "if": {},
		"choices": [{"label": "a", "effect": {"type": "fly"}}], "sign": "", "from": "", "story": "", "on": ""}
	p.letters["lost"] = {"id": "lost", "kind": "story", "text": "x", "hand": [], "weight": 1.0, "if": {},
		"choices": [], "sign": "", "from": "", "story": "nowhere", "on": "later"}
	var errs := "\n".join(PackValidator.validate(p))
	assert_true(errs.contains("kind 'gossip'"), errs)
	assert_true(errs.contains("hand must be"), errs)
	assert_true(errs.contains("effect type 'fly'"), errs)
	assert_true(errs.contains("story 'nowhere'"), errs)
	assert_true(errs.contains("needs a 'from'"), errs)
	var s := Pack.load_dir("res://packs/_smoke")
	s.config["letters"] = {"hands": []}
	assert_true("\n".join(PackValidator.validate(s)).contains("no letters.json"))


func test_a_long_qijia_run_writes_a_few_letters_a_day():
	var w := BalanceRun.family_of_four("qijia", 5)
	var n := 0
	for h in 48:
		BalanceRun.caretake(w)
		w.advance(3600)
		for e in w.drain_events():
			if e.type == "letter_arrived":
				n += 1
	assert_true(n >= 2, "letters came (%d)" % n)
	assert_true(n <= 48 * 3, "never more than a few an hour (%d)" % n)
	for l in w.letters:
		assert_true(_no_slot_left(l), str(l))
