extends TestCase
const P := "user://test_save.json"
const SMOKE := "res://packs/_smoke"

func _played() -> World:
	var w := World.new(Pack.load_dir(SMOKE), 9); w.set_time(1767268800, 0)
	w.command({type = "adopt"}); w.money = 2000
	w.command({type = "place", object_type = "fridge", room = "main", x = 0, y = 0})
	w.command({type = "buy", item = "groceries", qty = 2}); w.offline = true; w.advance(5 * 3600); w.offline = false
	w.drain_events(); return w

## Pending proposal, a sick person, a mess, a collectible and someone mid-action.
func _busy() -> World:
	var w := _played()
	var guard := 0
	while not w.command({type = "praise", person = w.people[0].uid}).ok and guard < 600:
		w.advance(60); guard += 1
	assert_true(w.command({type = "build_room", room = "study"}).ok)
	w.offline = true; w.advance(16 * 60); w.offline = false
	CollectibleSystem.spawn(w)
	MessSystem.spawn(w, w.pack.mess_types.keys()[0])
	w.people[0].illness = str(w.pack.illnesses.keys()[0])
	guard = 0
	while w.people[0].current.is_empty() and guard < 600:
		w.advance(60); guard += 1
	w.drain_events(); return w

func _through_json(d: Dictionary) -> Dictionary:
	var j := JSON.new()
	assert_eq(j.parse(JSON.stringify(d)), OK)
	return j.data

func _write(text: String) -> void:
	var f := FileAccess.open(P, FileAccess.WRITE); f.store_string(text); f.close()

func _cleanup() -> void:
	for p in [P, P + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func test_roundtrip_identical():
	var w := _played(); var r := World.from_dict(w.pack, w.to_dict()); assert_eq(r.to_dict(), w.to_dict())
func test_json_roundtrip_identical_types():
	for w in [_played(), _busy()]:
		var r := World.from_dict(w.pack, _through_json(w.to_dict()))
		assert_true(r != null); assert_eq(r.to_dict(), w.to_dict())
func test_busy_world_has_the_interesting_state():
	var w := _busy()
	assert_eq(w.proposals.size(), 1); assert_true(w.people[0].illness != "")
	assert_eq(w.messes.size() >= 1, true); assert_true(w.collectibles.size() >= 1)
	assert_true(not w.people[0].current.is_empty())
	assert_true(not w.income_carry.is_empty()); assert_true(not w.people[0].habits.is_empty())
	assert_true(not w.people[0].praise_times.is_empty()); assert_true(w.rooms_built.has("study"))
	assert_true(not w.goals_done.is_empty()); assert_true(w.people[0].track != "")
func test_loaded_world_continues_identically():
	var a := _played(); var b := World.from_dict(a.pack, a.to_dict())
	a.advance(3 * 3600); b.advance(3 * 3600); assert_eq(a.to_dict(), b.to_dict())
func test_loaded_through_file_continues_identically():
	for make in [Callable(self, "_played"), Callable(self, "_busy")]:
		var a: World = make.call()
		assert_true(SaveStore.save(a, P))
		var b: World = SaveStore.load(a.pack, P).world
		_cleanup()
		assert_true(b != null)
		for i in 3:
			var cmds := [{type = "buy", item = "groceries", qty = 1}, {type = "praise", person = a.people[0].uid}]
			for c in cmds:
				a.command(c.duplicate()); b.command(c.duplicate())
			a.advance(2 * 3600 + 17); b.advance(2 * 3600 + 17)
			assert_eq(a.to_dict(), b.to_dict())
		var pr: Array = a.proposals
		if not pr.is_empty():
			var c := {type = "answer_proposal", id = pr[0].id, accept = true}
			assert_eq(a.command(c.duplicate()).ok, b.command(c.duplicate()).ok)
			a.advance(3600); b.advance(3600); assert_eq(a.to_dict(), b.to_dict())
func test_loaded_world_is_not_offline_and_has_no_events():
	var w := _played(); w.offline = true; w.emit("x")
	var r := World.from_dict(w.pack, w.to_dict()); assert_true(not r.offline); assert_eq(r.drain_events().size(), 0)
func test_to_dict_is_a_deep_copy():
	var w := _busy(); var d := w.to_dict(); var before := w.to_dict()
	d["money"] = 1; d["people"][0]["needs"]["fed"] = -5.0; d["objects"][0]["x"] = 99; d["proposals"].clear()
	assert_eq(w.to_dict(), before)
	var r := World.from_dict(w.pack, before); before["objects"][0]["x"] = 77; before["people"].clear()
	assert_eq(r.to_dict(), w.to_dict())
func test_file_roundtrip():
	var w := _played(); assert_true(SaveStore.save(w, P))
	var r := SaveStore.load(w.pack, P); assert_eq(r.error, ""); assert_eq(r.world.to_dict(), w.to_dict())
	assert_true(not FileAccess.file_exists(P + ".tmp")); _cleanup()
func test_missing_file():
	assert_eq(SaveStore.load(Pack.load_dir(SMOKE), "user://nope.json").error, "missing")
func test_corrupt_file_reported_and_left_alone():
	_write("{not json")
	assert_eq(SaveStore.load(Pack.load_dir(SMOKE), P).error, "corrupt")
	assert_eq(FileAccess.get_file_as_string(P), "{not json"); _cleanup()
func test_unknown_version():
	var w := _played(); var d := w.to_dict(); d["version"] = 999
	_write(JSON.stringify(d))
	assert_eq(SaveStore.load(w.pack, P).error, "version"); _cleanup()
func test_pack_mismatch():
	var w := _played(); var d := w.to_dict(); d["pack_id"] = "other"
	_write(JSON.stringify(d))
	assert_eq(SaveStore.load(w.pack, P).error, "pack_mismatch"); _cleanup()
func test_valid_json_wrong_shape_is_corrupt():
	_write("[1,2,3]"); assert_eq(SaveStore.load(Pack.load_dir(SMOKE), P).error, "corrupt")
	var d := _played().to_dict(); d.erase("money"); _write(JSON.stringify(d))
	assert_eq(SaveStore.load(Pack.load_dir(SMOKE), P).error, "corrupt"); _cleanup()
func test_load_does_not_touch_file():
	var w := _played(); SaveStore.save(w, P); var before := FileAccess.get_file_as_string(P)
	SaveStore.load(w.pack, P); assert_eq(FileAccess.get_file_as_string(P), before); _cleanup()
func test_from_dict_rejects_bad_input_with_null():
	var w := _busy(); var good := w.to_dict()
	var bad: Array[Dictionary] = []
	for k in good.keys():
		var d := good.duplicate(true); d.erase(k); bad.append(d)
	var d1 := good.duplicate(true); d1["version"] = 2; bad.append(d1)
	var d2 := good.duplicate(true); d2["pack_id"] = "zzz"; bad.append(d2)
	var d3 := good.duplicate(true); d3["people"] = {}; bad.append(d3)
	var d4 := good.duplicate(true); d4["money"] = "lots"; bad.append(d4)
	var d5 := good.duplicate(true); d5["people"][0].erase("needs"); bad.append(d5)
	var d6 := good.duplicate(true); d6["objects"][0]["x"] = "a"; bad.append(d6)
	var d7 := good.duplicate(true); d7["rng"] = {}; bad.append(d7)
	var d8 := good.duplicate(true); d8["phase"] = "dancing"; bad.append(d8)
	var d9 := good.duplicate(true); d9["stock"] = []; bad.append(d9)
	var d10 := good.duplicate(true); d10["proposals"][0]["person"] = 3; bad.append(d10)
	for d in bad:
		assert_true(World.from_dict(w.pack, d) == null)
func test_save_failure_leaves_existing_file_untouched():
	var w := _played(); assert_true(SaveStore.save(w, P)); var before := FileAccess.get_file_as_string(P)
	assert_true(not SaveStore.save(w, "user://no_such_dir/x.json"))
	assert_eq(FileAccess.get_file_as_string(P), before); _cleanup()
func test_save_overwrites_existing():
	var w := _played(); _write("old"); assert_true(SaveStore.save(w, P))
	assert_eq(SaveStore.load(w.pack, P).error, ""); _cleanup()
func test_missing_room_in_placed_entries_is_rejected():
	var w := _busy(); var d := w.to_dict(); d["objects"][0].erase("room")
	assert_true(World.from_dict(w.pack, d) == null)
	var d2 := w.to_dict(); d2["messes"][0].erase("room"); assert_true(World.from_dict(w.pack, d2) == null)
func test_missing_or_unknown_room_in_collectibles_is_rejected():
	var w := _busy(); var d := w.to_dict(); d["collectibles"][0].erase("room")
	assert_true(World.from_dict(w.pack, d) == null)
	var d2 := w.to_dict(); d2["collectibles"][0]["room"] = "no_such_room"
	assert_true(World.from_dict(w.pack, d2) == null)
func test_malformed_float_marker_is_rejected():
	var w := _played(); var d := w.to_dict(); d["people"][0]["age"] = {"$f": "abc"}
	assert_true(World.from_dict(w.pack, d) == null)
func test_missing_need_and_non_string_tags_rejected():
	# A need missing from a save (one the pack gained since) is filled in at its start.
	var w := _busy(); var d := w.to_dict(); var gone: String = w.pack.needs.keys()[0]
	d["people"][0]["needs"].erase(gone)
	var back := World.from_dict(w.pack, d)
	assert_true(back != null)
	assert_near(float(back.people[0].needs[gone]), float(w.pack.needs[gone]["start"]))
	var d2 := w.to_dict(); d2["people"][0]["likes"] = [3]; assert_true(World.from_dict(w.pack, d2) == null)
func test_out_of_range_digit_strings_rejected_silently():
	var big := "99999999999999999999"
	var w := _busy()
	var d := w.to_dict(); d["seed"] = big; assert_true(World.from_dict(w.pack, d) == null)
	var d2 := w.to_dict(); d2["rng"]["seed"] = big; assert_true(World.from_dict(w.pack, d2) == null)
	var d3 := w.to_dict(); d3["rng"]["state"] = "-" + big; assert_true(World.from_dict(w.pack, d3) == null)
	var d4 := w.to_dict(); d4["people"][0]["age"] = {"$f": big}; assert_true(World.from_dict(w.pack, d4) == null)
	var d5 := w.to_dict(); d5["income_carry"] = {big: 1}; assert_true(World.from_dict(w.pack, d5) == null)
	var d6 := w.to_dict(); d6["rng"]["state"] = "9223372036854775807"; assert_true(World.from_dict(w.pack, d6) != null)
func test_uid_counter_must_exceed_uids_in_use():
	var w := _busy(); var d := w.to_dict(); d["next_uid"] = 1; assert_true(World.from_dict(w.pack, d) == null)
	var top := 0
	for p in w.people: top = maxi(top, p.uid)
	for pr in w.proposals: top = maxi(top, pr.id)
	var d2 := w.to_dict(); d2["next_uid"] = top; assert_true(World.from_dict(w.pack, d2) == null)
	var d3 := w.to_dict(); d3["next_uid"] = top + 100; assert_true(World.from_dict(w.pack, d3) != null)
## A save written before a pack content update: each kind of vanished id gives "pack_changed".
func test_save_naming_removed_pack_content_is_pack_changed():
	var w := _busy(); w.inventory["cold_pill"] = 1; w.people[0].last_action = "eat"
	assert_true(SaveStore.save(w, P))
	var p0 := w.people[0]
	var removals := {
		"actions": p0.current["action"], "object_types": "fridge", "rooms": "study",
		"items": "cold_pill", "needs": w.pack.needs.keys()[0], "illnesses": p0.illness,
		"mess_types": w.messes[0].type, "collectibles": w.collectibles[0].type,
		"goals": w.goals_done[0], "livelihoods": p0.track,
	}
	assert_eq(SaveStore.load(Pack.load_dir(SMOKE), P).error, "")
	for key in removals:
		var pack := Pack.load_dir(SMOKE)
		var table: Dictionary = pack.get(key)
		assert_true(table.has(removals[key]), key)
		table.erase(removals[key])
		var r := SaveStore.load(pack, P)
		assert_eq(r.error, "pack_changed", key); assert_true(r.world == null, key)
	# A pack that gained a need still loads the save: everyone gets the new need at its start.
	var added := Pack.load_dir(SMOKE); added.needs["extra_need"] = added.needs.values()[0].duplicate()
	added.needs["extra_need"]["id"] = "extra_need"
	var ra := SaveStore.load(added, P)
	assert_eq(ra.error, "", "pack gained a need")
	assert_near(float(ra.world.people[0].needs["extra_need"]), float(added.needs["extra_need"]["start"]))
	_cleanup()
func test_acc_must_be_below_the_largest_step():
	var w := _played()
	for acc in [-1.0, 60.0, 61.0]:
		w._acc = acc; assert_true(World.from_dict(w.pack, w.to_dict()) == null, str(acc))
	w._acc = 59.5; assert_true(World.from_dict(w.pack, w.to_dict()) != null)
	# qijia steps 5 s, but a save written when it stepped 60 s may hold up to 59.x s: that
	# loads, and the next advance folds it into whole steps.
	var q: World = BalanceRun.setup("qijia", 3)
	for acc in [-1.0, 60.0]:
		q._acc = acc; assert_true(World.from_dict(q.pack, q.to_dict()) == null, str(acc))
	q._acc = 59.0
	var r := World.from_dict(q.pack, q.to_dict())
	assert_true(r != null)
	var t0 := r.now
	r.advance(1.0)
	assert_eq(r.now, t0 + 60); assert_true(r._acc < 5.0, str(r._acc))

## A qijia save as the kernel wrote it before actions ran on the fast clock: no
## `work_carry`, a study running with its old 60-minute `remaining_s`, a 37.5 s partial step.
## The study is cut to its new length: it finishes within two minutes of play, not an hour.
func test_save_from_before_the_fast_clock_loads_and_plays_on():
	var w: World = BalanceRun.setup("qijia", 4)
	var p: Person = w.people[0]
	p.track = "reading"
	var desk := -1
	for o in w.objects:
		if o.type == "desk": desk = o.uid
	p.current = {"action": "study", "object_uid": desk, "target_uid": -1, "remaining_s": 3600}
	w._acc = 37.5
	var d := _through_json(w.to_dict())
	for pd in d["people"]:
		pd.erase("work_carry")
	var r := World.from_dict(w.pack, d)
	assert_true(r != null)
	var q: Person = r.people[0]
	assert_eq(q.work_carry, 0.0)
	assert_eq(int(q.current["remaining_s"]), 3600)
	r.drain_events()
	var t0 := r.now
	while str(q.current.get("action", "")) == "study" and r.now - t0 < 600:
		r.advance(5.0)
	assert_true(r.now - t0 <= 120, "study ran %d s after loading" % (r.now - t0))
	assert_eq(q.last_action, "study")
	assert_true(r.drain_events().any(func(e): return e.type == "action_finished" and e.action == "study"))
	r.advance(3600.0)
	assert_true(q.alive)

func test_save_without_work_carry_loads_with_zero():
	var w := _played(); var d := w.to_dict()
	for pd in d["people"]:
		pd.erase("work_carry")
	var r := World.from_dict(w.pack, d)
	assert_true(r != null); assert_eq(r.people[0].work_carry, 0.0)
	var d2 := w.to_dict(); d2["people"][0]["work_carry"] = "x"
	assert_true(World.from_dict(w.pack, d2) == null)

## `work_carry` is a fraction of a coin: a save holding a value outside [0, 1) is corrupt.
func test_work_carry_out_of_range_is_rejected():
	var w := _played()
	for v in [-0.01, 1.0, 2.5, -1]:
		var d := _through_json(w.to_dict()); d["people"][0]["work_carry"] = v
		assert_eq(WorldSave.restore(w.pack, d).error, "corrupt", str(v))
	for v in [0, 0.0, 0.5, 0.999]:
		var d := _through_json(w.to_dict()); d["people"][0]["work_carry"] = v
		assert_true(World.from_dict(w.pack, d) != null, str(v))

## `recent_actions` is saved; an older save without it starts from `last_action`; a save
## naming an action the pack no longer has is pack_changed, a non-array is corrupt.
func test_recent_actions_round_trip_and_old_saves_derive_them():
	var w: World = BalanceRun.setup("qijia", 5)
	w.advance(600.0)
	var p: Person = w.people[0]
	assert_true(not p.recent_actions.is_empty())
	var r := World.from_dict(w.pack, _through_json(w.to_dict()))
	assert_eq(r.people[0].recent_actions, p.recent_actions)
	var d := _through_json(w.to_dict())
	d["people"][0].erase("recent_actions")
	var old := World.from_dict(w.pack, d)
	assert_eq(old.people[0].recent_actions, [p.last_action])
	d["people"][0]["last_action"] = ""
	assert_eq(World.from_dict(w.pack, d).people[0].recent_actions, [])
	var bad := _through_json(w.to_dict()); bad["people"][0]["recent_actions"] = "study"
	assert_eq(WorldSave.restore(w.pack, bad).error, "corrupt")
	var gone := _through_json(w.to_dict()); gone["people"][0]["recent_actions"] = ["no_such_action"]
	assert_eq(WorldSave.restore(w.pack, gone).error, "pack_changed")

## A save from before the pack built more rooms from the start gains them on load (after
## the saved ones, in pack order); a room the pack no longer has is still pack_changed.
func test_old_save_gains_rooms_the_pack_now_builds_from_the_start():
	var w := World.new(Pack.load_dir("res://packs/qijia"), 3); w.set_time(1767268800, 0)
	w.command({type = "adopt"})
	var d := _through_json(w.to_dict())
	d["rooms_built"] = ["yard", "hall"]
	var r := WorldSave.restore(w.pack, d)
	assert_eq(r.error, "")
	# every room qijia builds from the start, in pack order after the saved ones (the five
	# places outside the compound wall came later and are always there, so they join too)
	assert_eq(r.world.rooms_built, ["yard", "hall", "bedroom", "kitchen", "woodshed", "well", "gate", "coop_run",
		"riverside", "bamboo_grove", "field_ridge", "hill_path", "village_tree"] as Array[String])
	d["rooms_built"] = ["yard", "hall", "attic"]
	assert_eq(WorldSave.restore(w.pack, d).error, "pack_changed")

func test_smoke_save_rooms_built_round_trips_unchanged():
	var w := _busy()
	var r := WorldSave.restore(w.pack, _through_json(w.to_dict()))
	assert_eq(r.world.rooms_built, w.rooms_built)

## The connected house once shrank the side room (8x7 to 6x6). A save from a layout where a
## room was bigger still loads: furniture that no longer fits moves to a free spot of the same room, a mess
## or a thing lying about moves inside it.
func test_save_from_the_old_layout_loads_with_things_moved_inside_shrunk_rooms():
	var w := World.new(Pack.load_dir("res://packs/qijia"), 3); w.set_time(1767268800, 0)
	w.command({type = "adopt"})
	w.money = 5000
	assert_true(w.command({type = "build_room", room = "side"}).ok)
	var d := _through_json(w.to_dict())
	var uid := int(d["next_uid"])
	# Cells past the side room's far corner, as a save from a bigger layout would have them.
	var rw := int(w.pack.rooms["side"]["w"])
	var rh := int(w.pack.rooms["side"]["h"])
	d["objects"].append({"uid": uid, "type": "stool", "room": "side", "x": rw + 1, "y": rh})
	d["messes"].append({"uid": uid + 1, "type": w.pack.mess_types.keys()[0], "room": "side", "x": rw + 1, "y": rh})
	d["collectibles"].append({"uid": uid + 2, "type": "egg", "room": "side", "x": rw + 1, "y": rh, "expires_at": w.now + 600})
	d["next_uid"] = uid + 3
	var money := int(d["money"])
	var r := WorldSave.restore(w.pack, d)
	assert_eq(r.error, "")
	var stool: Dictionary = r.world.object(uid)
	assert_true(not stool.is_empty())
	assert_eq(HouseSystem.can_place(r.world, "stool", "side", int(stool.x), int(stool.y), uid), "")
	assert_eq(r.world.money, money)
	for list in [r.world.messes, r.world.collectibles]:
		for m in list:
			if m.room == "side":
				assert_true(int(m.x) < rw and int(m.y) < rh, str(m))
