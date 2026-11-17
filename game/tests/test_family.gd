extends TestCase
func _fresh() -> World:
	var w := World.new(Pack.load_dir("res://packs/_smoke"), 5); w.set_time(1767268800, 0); return w
func test_new_world_is_adopting_with_candidate_and_time_frozen():
	var w := _fresh(); assert_eq(w.phase, "adopting"); assert_true(not w.candidate.is_empty())
	w.advance(3600); assert_eq(w.now, 1767268800)
func test_candidate_within_ranges():
	var w := _fresh(); var c := w.candidate
	assert_true(c.age >= 22.0 and c.age <= 29.0); assert_true(w.pack.livelihoods.has(c.track))
	for t in c.likes: assert_true(t not in c.dislikes)
func test_reroll_changes_candidate():
	var w := _fresh(); var first := w.candidate.duplicate(true); w.command({type = "reroll"})
	assert_true(w.candidate != first)
func test_adopt_starts_living():
	var w := _fresh(); assert_true(w.command({type = "adopt"}).ok)
	assert_eq(w.phase, "living"); assert_eq(w.people.size(), 1); assert_eq(w.money, int(w.pack.cfg("start_money")))
func test_proposal_arrives_then_expires_without_penalty():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; var m := w.money
	w.advance(15 * 60 + 60); assert_eq(w.proposals.size(), 1)
	w.advance(24 * 3600 + 60)
	assert_true(w.drain_events().any(func(e): return e.type == "proposal_expired")); assert_true(w.money >= m)
func test_first_decline_brings_next_in_45_min_then_daily():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; w.advance(15 * 60 + 60)
	w.command({type = "answer_proposal", id = w.proposals[0].id, accept = false})
	w.advance(44 * 60); assert_eq(w.proposals.size(), 0); w.advance(2 * 60); assert_eq(w.proposals.size(), 1)
	w.command({type = "answer_proposal", id = w.proposals[0].id, accept = false})
	w.advance(23 * 3600); assert_eq(w.proposals.size(), 0); w.advance(3600 + 60); assert_eq(w.proposals.size(), 1)
func test_accept_marries_and_pools_money():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; w.advance(3600 + 60)
	var pr: Dictionary = w.proposals[0]; var m := w.money
	assert_true(w.command({type = "answer_proposal", id = pr.id, accept = true}).ok)
	assert_eq(w.people.size(), 2); assert_true(w.married); assert_eq(w.money, m + int(pr.savings))
	assert_eq(w.people[1].family, w.people[0].family); assert_true(w.people[1].gender != w.people[0].gender)
	w.advance(48 * 3600); assert_eq(w.proposals.size(), 0)
func test_decline_removes():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; w.advance(3600 + 60)
	w.command({type = "answer_proposal", id = w.proposals[0].id, accept = false}); assert_eq(w.proposals.size(), 0); assert_eq(w.people.size(), 1)
func test_command_gating_by_phase():
	var w := _fresh()
	assert_eq(w.command({type = "praise", person = 1}).error, "not_running")
	assert_eq(w.command({type = "answer_proposal", id = 1, accept = true}).error, "not_running")
	w.command({type = "adopt"})
	assert_eq(w.command({type = "adopt"}).error, "not_adopting"); assert_eq(w.command({type = "reroll"}).error, "not_adopting")
	w.phase = "over"
	assert_eq(w.command({type = "adopt"}).error, "not_running"); assert_eq(w.command({type = "buy", item = "x"}).error, "not_running")
func test_unknown_proposal_id_errors():
	var w := _fresh(); w.command({type = "adopt"})
	assert_eq(w.command({type = "answer_proposal", id = 999, accept = true}).error, "no_proposal")
func test_arrival_and_married_events_and_opposite_gender():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; w.advance(15 * 60 + 60)
	var pr: Dictionary = w.proposals[0]
	assert_true(w.drain_events().any(func(e): return e.type == "proposal_arrived" and e.id == pr.id))
	assert_true(pr.person.gender != w.people[0].gender)
	assert_true(pr.savings >= 0 and pr.savings <= int(w.pack.cfg("start_money")))
	w.command({type = "answer_proposal", id = pr.id, accept = true})
	assert_true(w.drain_events().any(func(e): return e.type == "married" and e.person == w.people[1].uid))
func test_no_proposal_with_two_adults():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; TestKit.adult(w)
	w.advance(3600); assert_eq(w.proposals.size(), 0)
func test_game_over_reroll_keeps_money_and_resets_people():
	var w := _fresh(); w.command({type = "adopt"}); w.offline = true; w.advance(3600 + 60)
	w.command({type = "answer_proposal", id = w.proposals[0].id, accept = true})
	w.money = 777; w.kill_person(w.people[0], "x"); w.kill_person(w.people[1], "x"); assert_eq(w.phase, "over")
	assert_true(w.command({type = "reroll"}).ok)
	assert_eq(w.phase, "adopting"); assert_eq(w.people.size(), 0); assert_true(not w.married)
	assert_true(not w.candidate.is_empty()); assert_eq(w.money, 777)
	w.command({type = "adopt"}); assert_eq(w.money, 777); assert_eq(w.phase, "living")
func test_testkit_world_stays_living_without_candidate():
	var w := TestKit.world(); assert_eq(w.phase, "living"); assert_true(w.candidate.is_empty())

func test_first_adoption_furnishes_the_house_once():
	var w := World.new(Pack.load_dir("res://packs/qijia"), 1)
	w.set_time(1767254400, 0)
	w.command({"type": "adopt"})
	var n := w.objects.size()
	assert_true(n >= 5)
	assert_eq(w.money, 200)                       # the starting furniture is free
	w.kill_person(w.people[0], "old_age")
	w.command({"type": "reroll"})
	w.command({"type": "adopt"})
	assert_eq(w.objects.size(), n)

func test_pack_without_start_objects_adopts_into_an_empty_house():
	var w := _fresh(); w.command({type = "adopt"})
	var p := w.pack
	assert_eq(w.objects.size(), (p.cfg("start_objects") as Array).size())
