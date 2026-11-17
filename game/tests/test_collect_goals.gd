extends TestCase
func test_first_pickup_goes_to_collection_duplicate_pays():
	var w := TestKit.world(); var p := TestKit.adult(w); w.money = 0; var dur: int = w.pack.actions["pick_up"]["duration_min"] * 60
	var uid := CollectibleSystem.spawn(w, "coin")
	assert_true(w.command({type = "drag", person = p.uid, collectible = uid}).ok); w.advance(dur)
	assert_eq(w.money, 0); assert_eq(w.collection["coin"], 1); assert_eq(w.collectibles.size(), 0)
	uid = CollectibleSystem.spawn(w, "coin"); w.command({type = "drag", person = p.uid, collectible = uid}); w.advance(dur)
	assert_eq(w.money, int(w.pack.collectibles["coin"]["value"])); assert_eq(w.collection["coin"], 2)
func test_collectible_expires():
	var w := TestKit.world(); CollectibleSystem.spawn(w, "coin"); w.advance(61 * 60)
	assert_true(w.drain_events().any(func(e): return e.type == "collectible_expired"))
func test_never_exceeds_max():
	var w := TestKit.world(); w.offline = true; w.advance(86400)
	assert_true(w.collectibles.size() <= int(w.pack.cfg("collectible_max")))
func test_goal_pays_once():
	var w := TestKit.world(); var p := TestKit.adult(w); w.money = 0; var uid := MessSystem.spawn(w, "trash")
	w.command({type = "drag", person = p.uid, mess = uid})
	w.advance(w.pack.actions["take_out_trash"]["duration_min"] * 60 + 60)
	var reward := 0
	for g in w.pack.goals.values(): if g.when.type == "mess_cleared": reward = int(g.reward)
	assert_true(reward > 0); assert_eq(w.money, reward)
	var uid2 := MessSystem.spawn(w, "trash"); w.command({type = "drag", person = p.uid, mess = uid2})
	w.advance(w.pack.actions["take_out_trash"]["duration_min"] * 60 + 60); assert_eq(w.money, reward)
func test_drag_unknown_collectible_is_no_target():
	var w := TestKit.world(); var p := TestKit.adult(w)
	assert_eq(w.command({type = "drag", person = p.uid, collectible = 99}).error, "no_target")
func test_second_person_cannot_take_claimed_collectible():
	var w := TestKit.world(); var a := TestKit.adult(w); var b := TestKit.adult(w); var uid := CollectibleSystem.spawn(w, "coin")
	w.command({type = "drag", person = a.uid, collectible = uid})
	assert_eq(w.command({type = "drag", person = b.uid, collectible = uid}).error, "busy")
func test_expiry_cancels_the_pickup():
	var w := TestKit.world(); var p := TestKit.adult(w); var uid := CollectibleSystem.spawn(w, "coin")
	w.command({type = "drag", person = p.uid, collectible = uid})
	w.collectibles[0]["expires_at"] = w.now + 60; w.advance(60)
	assert_true(p.current.is_empty()); assert_eq(w.stats["collected"], 0)
func test_no_outdoor_room_no_spawn():
	var w := TestKit.world(); w.rooms_built = w.rooms_built.filter(func(r): return not bool(w.pack.rooms[r]["outdoor"]))
	assert_eq(CollectibleSystem.spawn(w, ""), -1)
func test_collected_goal_and_not_evaluated_when_over():
	var w := TestKit.world(); TestKit.adult(w); w.money = 0
	w.pack.goals["g"] = {"id": "g", "reward": 7, "when": {"type": "money_at_least", "amount": 1}}
	w.phase = "over"; GoalSystem.step(w, 60.0); assert_eq(w.goals_done.size(), 0)
	w.phase = "living"; w.money = 1; GoalSystem.step(w, 60.0); assert_eq(w.money, 8); assert_true(w.goals_done.has("g"))
