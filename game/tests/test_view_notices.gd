extends TestCase
## "Waiting for you" (design/UI_PLAN.md): everything that wants the player shows as a labelled
## notice in the top-left corner, and a click opens the card that answers it. Also the
## adoption picker, the market's tabs and the bar's status chips.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main(pack := "qijia", adopt := true) -> Main:
	n += 1
	var d := "user://test_view_notices_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create(pack, d, _clock)
	Engine.get_main_loop().root.add_child(m)
	# No old stories: a fragment card would outrank the cards these tests open.
	m.session.world.pack.stories = {}
	if adopt:
		m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _done(m: Main) -> void:
	m.get_parent().remove_child(m)
	m.free()


func _ids(m: Main) -> Array:
	return m.hud.notices().map(func(x): return x["id"])


## A proposal brought by the matchmaker's letter.
func _proposal(m: Main) -> Dictionary:
	var w := m.session.world
	w.next_proposal_at = w.now
	w.advance(60)
	m.session._dispatch_events()
	m.tick(0.016)
	return w.proposals[0]


func test_nothing_waits_in_a_quiet_house():
	var m := _main()
	assert_eq(m.hud.notices().size(), 0, str(_ids(m)))
	assert_eq(m.hud.notice_text(), "")
	_done(m)


func test_no_notices_before_anyone_is_taken_in():
	var m := _main("qijia", false)
	assert_eq(m.session.world.phase, "adopting")
	assert_eq(m.hud.notices().size(), 0)
	_done(m)


func test_a_proposal_shows_who_came_and_for_whom_and_opens_its_card():
	var m := _main()
	var w := m.session.world
	var pr := _proposal(m)
	var l: Dictionary = w.letters.back()
	assert_eq(l["kind"], "proposal")
	var id := "proposal:%d" % int(pr["id"])
	assert_true(id in _ids(m), str(_ids(m)))
	# One notice for the proposal and its letter, naming the writer and the one it is for.
	assert_true(not ("letter:%d" % int(l["id"])) in _ids(m), str(_ids(m)))
	var text := m.hud.notice_text()
	assert_true(text.contains(str(l["writer"])), text)
	assert_true(text.contains(m.session.strings.person_name(w.people[0])), text)
	assert_true(text.contains("说亲"), text)
	# The family button no longer carries a dot: the notice says it in words.
	assert_true(not m.hud.bar_text().contains("●"))
	m.panels.open("shop")
	assert_true(m.hud.press_notice(id))
	m.tick(0.016)
	assert_eq(m.panels.opened(), "", "the panel makes way")
	assert_eq(m.overlays.current(), "proposal")
	m.overlays.press("btn.decline")
	m.tick(0.016)
	assert_true(not id in _ids(m), "answered, the notice goes")
	_done(m)


func test_a_stray_at_the_gate_is_a_notice_that_opens_its_card():
	var m := _main()
	var w := m.session.world
	w.pet_offer = {"kind": "cat", "given": "花花", "age": 2.0, "expires_at": w.now + 3600}
	m.tick(0.016)
	assert_true("stray:0" in _ids(m))
	assert_true(m.hud.notice_text().contains(str(w.pack.pets["cat"]["name"])), m.hud.notice_text())
	assert_eq(m.overlays.current(), "", "it waits for the player")
	m.hud.press_notice("stray:0")
	assert_eq(m.overlays.current(), "stray")
	m.overlays.press("btn.shoo")
	m.tick(0.016)
	assert_true(not "stray:0" in _ids(m))
	_done(m)


func test_an_unread_letter_then_a_letter_waiting_for_an_answer():
	var m := _main()
	var w := m.session.world
	var l := {"id": w.letter_next, "t": w.now, "kind": "kin", "template": "t", "from": 0, "about": 0,
		"writer": "表舅", "hand": "", "text": "捎来几十文。", "sign": "表舅",
		"choices": [{"label": "收下", "effect": {"type": "money", "amount": 10}},
			{"label": "回头再说", "effect": {"type": "later"}}], "answer": -1, "read": false}
	w.letter_next += 1
	w.letters.append(l)
	m.tick(0.016)
	var id := "letter:%d" % int(l["id"])
	assert_true(id in _ids(m), str(_ids(m)))
	assert_true(m.hud.notice_text().contains("表舅"))
	m.hud.press_notice(id)
	m.tick(0.016)
	assert_eq(m.letters.opened(), "letter")
	assert_true(bool(l["read"]))
	# Read but unanswered: it now waits for an answer.
	m.letters.press("choice.1")
	m.letters.press("btn.close")
	m.tick(0.016)
	assert_true(("reply:%d" % int(l["id"])) in _ids(m), str(_ids(m)))
	m.hud.press_notice("reply:%d" % int(l["id"]))
	m.letters.press("choice.0")
	m.letters.press("btn.close")
	m.tick(0.016)
	assert_true(m.hud.notices().is_empty(), str(_ids(m)))
	_done(m)


func test_many_letters_fold_into_one_notice_that_opens_the_box():
	var m := _main()
	var w := m.session.world
	for i in 4:
		w.letters.append({"id": w.letter_next, "t": w.now, "kind": "thanks", "template": "t", "from": 0,
			"about": 0, "writer": "写信人%d" % i, "hand": "", "text": "好", "sign": "", "choices": [],
			"answer": -1, "read": false})
		w.letter_next += 1
	m.tick(0.016)
	var kinds := m.hud.notices().map(func(x): return x["kind"])
	assert_eq(kinds.count("letter"), Notices.FOLD)
	assert_true("letters:0" in _ids(m))
	m.hud.press_notice("letters:0")
	assert_eq(m.letters.opened(), "box")
	_done(m)


func test_someone_falling_ill_or_at_their_worst_is_a_notice_that_selects_them():
	var m := _main()
	var w := m.session.world
	var a := w.people[0]
	var b := FamilySystem.make_person(w, [20, 20])
	w.add_person(b)
	m.tick(0.016)
	w.emit("fell_ill", {"person": a.uid})
	m.session._dispatch_events()
	b.needs["fed"] = 5.0
	m.tick(0.016)
	assert_true(("ill:%d" % a.uid) in _ids(m), str(_ids(m)))
	assert_true(("need:%d" % b.uid) in _ids(m), str(_ids(m)))
	assert_true(m.hud.notice_text().contains(str(b.status(w.pack)["fed"])), m.hud.notice_text())
	m.hud.press_notice("need:%d" % b.uid)
	assert_eq(m.selected, b.uid)
	w.emit("cured", {"person": a.uid})
	m.session._dispatch_events()
	m.tick(0.016)
	assert_true(not ("ill:%d" % a.uid) in _ids(m))
	_done(m)


func test_a_runaway_animal_and_a_thank_you_are_notices():
	var m := _main()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	dog.state = "away"
	var p := w.people[0]
	p.thanks_until = w.now + 600
	m.tick(0.016)
	assert_true(("pet_away:%d" % dog.uid) in _ids(m), str(_ids(m)))
	assert_true(("thanks:%d" % p.uid) in _ids(m), str(_ids(m)))
	m.hud.press_notice("pet_away:%d" % dog.uid)
	assert_eq(m.panels.opened(), "family")
	_done(m)


func test_something_on_the_ground_is_a_sky_blue_notice_that_takes_the_view_there():
	var m := _main()
	var w := m.session.world
	var uid := CollectibleSystem.spawn(w)
	m.tick(0.016)
	var id := "pickup:%d" % uid
	assert_true(id in _ids(m), str(_ids(m)))
	var notice: Dictionary = m.hud.notices()[_ids(m).find(id)]
	assert_eq(notice["tone"], "pickup")
	m.house.pan(Vector2(300, 200))
	m.hud.press_notice(id)
	var c := CollectibleSystem.find(w, uid)
	var at := m.house.to_screen(m.house.layout.cell_center(str(c.room), int(c.x), int(c.y)))
	assert_true(at.distance_to(Vector2(1280, 720 - HouseView.BOTTOM_BAR) * 0.5) < 1.0, str(at))
	_done(m)


func test_decisions_come_first_and_the_rest_are_counted():
	var m := _main()
	var w := m.session.world
	for i in 6:
		var q := FamilySystem.make_person(w, [20, 20])
		w.add_person(q)
		q.needs["fed"] = 2.0
	w.pet_offer = {"kind": "cat", "given": "花花", "age": 2.0, "expires_at": w.now + 3600}
	m.tick(0.016)
	assert_eq(m.hud.notices()[0]["kind"], "stray", "a decision before trouble")
	assert_true(m.hud.notices().size() > Hud.NOTICES_MAX)
	var more := m.session.strings.t("notice.more").replace("{n}", str(m.hud.notices().size() - Hud.NOTICES_MAX))
	assert_true(m.hud.notice_text().contains(more), m.hud.notice_text())
	_done(m)


func test_the_bar_says_all_is_well_when_nothing_is_wrong():
	var m := _main()
	var p := m.session.world.people[0]
	for nid in p.needs:
		p.needs[nid] = 99.0
	m.tick(0.016)
	assert_true(m.hud.bar_text().contains(m.session.strings.t("status.fine")), m.hud.bar_text())
	for word in p.status(m.session.pack).values():
		assert_true(not m.hud.bar_text().contains(word), word)
	_done(m)


func test_earnings_show_off_as_a_gold_toast_and_over_the_earner():
	var m := _main()
	var p := m.session.world.people[0]
	m.hud.earned(p.uid, "今天挣了 30 文！")
	assert_true(m.hud.toasts().has("今天挣了 30 文！"))
	assert_true(m.house.people[p.uid].float_text() != "")
	_done(m)


# --- The adoption picker -------------------------------------------------------------

func test_the_picker_offers_several_people_side_by_side_and_takes_the_one_picked():
	var m := _main("qijia", false)
	var w := m.session.world
	assert_eq(m.overlays.current(), "adopt")
	assert_eq(w.candidates.size(), FamilySystem.CHOICES)
	var third := Person.from_dict(w.candidates[2])
	var text := m.overlays.text()
	for c in w.candidates:
		assert_true(text.contains(str(c["family"]) + str(c["given"])), text)
	m.overlays.press("pick:2")
	m.tick(0.016)
	assert_eq(w.phase, "living")
	assert_eq(w.people.size(), 1)
	assert_eq(w.people[0].given, third.given)
	assert_eq(w.people[0].family, third.family)
	assert_true(w.candidates.is_empty())
	_done(m)


func test_a_candidate_card_falls_back_quietly_without_a_painted_portrait():
	var m := _main("qijia", false)
	var w := m.session.world
	var errors := m.house.skin.errors.size()
	var pp := PersonPortrait.make(Person.from_dict(w.candidates[0]), m.house.skin, w.pack, Vector2(200, 170), "no_such_look")
	assert_eq(pp.look, "no_such_look")
	assert_true(pp.portrait() == null)
	assert_eq(m.house.skin.errors.size(), errors, "a missing portrait is not a broken skin")
	assert_true(not pp.look_for().is_empty(), "the rig stands in")
	pp.free()
	_done(m)


func test_the_extra_candidates_leave_the_world_dice_alone():
	var a := World.new(Pack.load_dir("res://packs/qijia"), 7)
	var b := World.new(Pack.load_dir("res://packs/qijia"), 7)
	assert_eq(a.candidates, b.candidates, "the same seed offers the same people")
	assert_eq(a.candidates.size(), FamilySystem.CHOICES)
	assert_eq(a.candidates[0], a.candidate)
	var s0 := a.rng.get_state()
	FamilySystem.new_candidate(a)
	var with_lot := a.rng.get_state()
	a.rng.set_state(s0)
	FamilySystem.make_person(a, a.pack.cfg("adopt_age"))
	assert_eq(with_lot, a.rng.get_state(), "a lot costs the world's dice what one candidate did")


# --- The market's tabs ---------------------------------------------------------------

func test_the_market_has_the_pack_tabs_in_order_and_the_animals_under_theirs():
	var m := _main()
	m.panels.open("shop")
	var s := m.session.strings
	var names: Array = []
	for t in m.panels._market_tabs(m.session.world):
		names.append(t["name"])
	assert_eq(names, Array(s.t("market.tabs").split(",")))
	var text := m.panels.text()
	for name in names:
		assert_true(text.contains(name), text)
	assert_true(m.panels.has_button("buy:rice"), "food comes first")
	assert_true(not m.panels.has_button("buy_pet:dog"))
	m.panels.press("tab.pets")
	assert_true(m.panels.has_button("buy_pet:dog"))
	assert_true(m.panels.has_button("buy:pork_bone"), "the animals' food sits with them")
	m.panels.press(m.panels._market_tabs(m.session.world)[1]["id"])
	assert_true(m.panels.text().contains(s.t("market.empty")), m.panels.text())
	_done(m)


func test_without_tab_names_every_item_category_is_a_tab():
	var m := _main("_smoke")
	var cats := {}
	for id in m.session.pack.items:
		cats[str(m.session.pack.items[id].get("category", ""))] = true
	var names: Array = []
	for t in m.panels._market_tabs(m.session.world):
		names.append(t["name"])
	assert_eq(names, cats.keys())
	_done(m)
