extends TestCase
## Actions that say where they happen (`rooms`) and fixed furniture that belongs to a room
## (`fixed` object types, room `props`). Built on the _smoke pack, changed in memory.

const SMOKE := "res://packs/_smoke"


## _smoke with: `stare_window` happening in the study (unbuilt) or the yard, a fixed outdoor
## `pump` and a fixed indoor `shelf`, the yard holding a pump prop and the study a shelf prop.
func _pack(stare_rooms := ["study"]) -> Pack:
	var p := Pack.load_dir(SMOKE)
	p.actions["stare_window"]["rooms"] = stare_rooms
	p.object_types["pump"] = {"id": "pump", "name": "Pump", "category": "yard", "price": 0, "w": 1, "h": 1,
		"outdoor": true, "capacity": 1, "fixed": true}
	p.object_types["shelf"] = {"id": "shelf", "name": "Shelf", "category": "study", "price": 0, "w": 2, "h": 1,
		"outdoor": false, "capacity": 1, "fixed": true}
	p.actions["pump_water"] = {"id": "pump_water", "label": "Pump water", "kind": "flavor", "duration_min": 5,
		"object": "pump", "needs": {}, "base": 4, "hours": [], "tags": [], "praiseable": true, "consumes": {},
		"work": {}, "mess": {}, "cleans": "", "picks": false, "requires": {}, "slow": false, "rooms": [],
		"stages": ["child", "adult", "elder"]}
	p.rooms["yard"]["props"] = [{"type": "pump", "x": 7, "y": 5}]
	p.rooms["study"]["props"] = [{"type": "shelf", "x": 0, "y": 0}]
	return p


func _world(p: Pack) -> World:
	var w := World.new(p, 4)
	w.set_time(1767268800, 0)
	return w


func _errs(mutate: Callable) -> Array[String]:
	var p := _pack(["yard"])
	mutate.call(p)
	return PackValidator.validate(p)


func _has(errs: Array[String], prefix: String, part := "") -> bool:
	return errs.any(func(e): return e.begins_with(prefix) and e.contains(part))


func _through_json(d: Dictionary) -> Dictionary:
	var j := JSON.new()
	assert_eq(j.parse(JSON.stringify(d)), OK)
	return j.data


# ---- A: rooms on actions ----

func test_new_fields_default_to_nothing():
	var p := Pack.load_dir(SMOKE)
	for a in p.actions.values():
		assert_eq(a["rooms"], [], a.id)
	for t in p.object_types.values():
		assert_eq(t["fixed"], false, t.id)
	for r in p.rooms.values():
		assert_eq(r["props"], [], r.id)
	assert_eq(PackValidator.validate(_pack(["yard"])), [] as Array[String])


func test_action_in_an_unbuilt_room_only_is_no_place():
	var w := _world(_pack(["study"]))
	w.command({"type": "adopt"})
	var p: Person = w.people[0]
	assert_eq(AutonomySystem.can_do(w, p, "stare_window", -1), "no_place")
	assert_true(not AutonomySystem.candidates(w, p).any(func(c): return c.action == "stare_window"))


func test_action_in_a_built_room_starts_there():
	var w := _world(_pack(["study", "yard"]))
	w.command({"type": "adopt"})
	var p: Person = w.people[0]
	assert_eq(AutonomySystem.can_do(w, p, "stare_window", -1), "")
	assert_true(AutonomySystem.candidates(w, p).any(func(c): return c.action == "stare_window"))
	AutonomySystem.start(w, p, "stare_window", -1)
	assert_eq(p.current.get("room"), "yard")
	w.money = 5000
	assert_true(w.command({"type": "build_room", "room": "study"}).ok)
	var seen := {}
	for i in 40:
		AutonomySystem.start(w, p, "stare_window", -1)
		seen[p.current["room"]] = true
	assert_eq(seen.size(), 2, str(seen))


func test_actions_without_rooms_store_no_room_and_draw_nothing():
	var w := _world(Pack.load_dir(SMOKE))
	w.command({"type": "adopt"})
	var p: Person = w.people[0]
	var before: Dictionary = w.rng.get_state()
	AutonomySystem.start(w, p, "stare_window", -1)
	assert_true(not p.current.has("room"))
	assert_eq(w.rng.get_state(), before)


func test_validator_rooms_must_be_pack_rooms_and_not_with_an_object():
	assert_true(_has(_errs(func(p): p.actions["stare_window"]["rooms"] = ["attic"]), "actions.json: stare_window:", "attic"))
	assert_true(_has(_errs(func(p): p.actions["stare_window"]["rooms"] = "yard"), "actions.json: stare_window:", "rooms"))
	assert_true(_has(_errs(func(p): p.actions["eat"]["rooms"] = ["main"]), "actions.json: eat:", "object"))


func test_save_round_trip_keeps_the_room_and_old_current_loads():
	var w := _world(_pack(["yard"]))
	w.command({"type": "adopt"})
	var p: Person = w.people[0]
	AutonomySystem.start(w, p, "stare_window", -1)
	var d := _through_json(w.to_dict())
	var r := WorldSave.restore(w.pack, d)
	assert_eq(r.error, "")
	assert_eq(r.world.people[0].current.get("room"), "yard")
	assert_eq(r.world.to_dict(), w.to_dict())
	var old := d.duplicate(true)
	old["people"][0]["current"].erase("room")
	assert_eq(WorldSave.restore(w.pack, old).error, "")
	var bad := d.duplicate(true)
	bad["people"][0]["current"]["room"] = 5
	assert_eq(WorldSave.restore(w.pack, bad).error, "corrupt")
	var gone := d.duplicate(true)
	gone["people"][0]["current"]["room"] = "attic"
	assert_eq(WorldSave.restore(w.pack, gone).error, "pack_changed")


# ---- B: fixed props ----

func test_props_appear_at_first_adoption_in_built_rooms_only():
	var w := _world(_pack())
	assert_eq(w.objects.size(), 0)
	w.command({"type": "adopt"})
	var pumps := w.objects.filter(func(o): return o.type == "pump")
	assert_eq(pumps.size(), 1)
	assert_eq([pumps[0].room, pumps[0].x, pumps[0].y], ["yard", 7, 5])
	assert_true(not w.objects.any(func(o): return o.type == "shelf"))


func test_prop_appears_when_its_room_is_built_later():
	var w := _world(_pack())
	w.command({"type": "adopt"})
	w.money = 5000
	assert_true(w.command({"type": "build_room", "room": "study"}).ok)
	var shelves := w.objects.filter(func(o): return o.type == "shelf")
	assert_eq(shelves.size(), 1)
	assert_eq([shelves[0].room, shelves[0].x, shelves[0].y], ["study", 0, 0])


func test_fixed_furniture_cannot_be_bought_moved_or_sold():
	var w := _world(_pack())
	w.command({"type": "adopt"})
	w.money = 5000
	assert_eq(w.command({"type": "place", "object_type": "pump", "room": "yard", "x": 0, "y": 0}).error, "fixed")
	var pump: Dictionary = w.objects.filter(func(o): return o.type == "pump")[0]
	assert_eq(w.command({"type": "move", "object": pump.uid, "room": "yard", "x": 0, "y": 0}).error, "fixed")
	assert_eq(w.command({"type": "sell_object", "object": pump.uid}).error, "fixed")
	assert_eq(w.money, 5000)
	assert_eq([pump.room, pump.x, pump.y], ["yard", 7, 5])


func test_fixed_furniture_is_used_like_any_other():
	var w := _world(_pack())
	w.command({"type": "adopt"})
	var p: Person = w.people[0]
	var pump: Dictionary = w.objects.filter(func(o): return o.type == "pump")[0]
	assert_eq(w.command({"type": "drag", "person": p.uid, "object": pump.uid}).get("action"), "pump_water")


func test_fixed_furniture_does_not_count_as_owned():
	var w := _world(_pack())
	w.command({"type": "adopt"})
	var n := w.objects.filter(func(o): return not bool(w.pack.object_types[o.type]["fixed"])).size()
	assert_true(GoalSystem.is_met(w, {"when": {"type": "objects_owned", "count": n}}))
	assert_true(not GoalSystem.is_met(w, {"when": {"type": "objects_owned", "count": n + 1}}))


func test_validator_props_problems():
	var props := func(room: String, list) -> Callable:
		return func(p): p.rooms[room]["props"] = list
	assert_true(_has(_errs(props.call("yard", [{"type": "nope", "x": 0, "y": 0}])), "rooms.json: yard:", "props #0"))
	assert_true(_has(_errs(props.call("main", [{"type": "fridge", "x": 0, "y": 0}])), "rooms.json: main:", "props #0"))
	assert_true(_has(_errs(props.call("yard", [{"type": "pump", "x": 8, "y": 0}])), "rooms.json: yard:", "props #0"))
	assert_true(_has(_errs(props.call("main", [{"type": "pump", "x": 4, "y": 4}])), "rooms.json: main:", "props #0"))
	assert_true(_has(_errs(props.call("yard", [{"type": "pump", "x": 0, "y": 0}, {"type": "pump", "x": 0, "y": 0}])), "rooms.json: yard:", "props #1"))
	assert_true(not _has(_errs(props.call("yard", [{"type": "pump", "x": 0, "y": 0}, {"type": "pump", "x": 0, "y": 0}])), "rooms.json: yard:", "props #0"))
	assert_true(_has(_errs(props.call("main", [{"type": "shelf", "x": 0, "y": 0}])), "rooms.json: main:", "props #0"))  # under the fridge
	assert_true(_has(_errs(props.call("yard", [{"type": "pump"}])), "rooms.json: yard:", "props #0"))
	assert_true(_has(_errs(props.call("yard", "pump")), "rooms.json: yard:", "props"))
	assert_true(_has(_errs(func(p): p.config["start_objects"] = [{"type": "shelf", "room": "main", "x": 4, "y": 4}]), "pack.json:", "fixed"))
	assert_true(_has(_errs(func(p): p.object_types["pump"]["fixed"] = "yes"), "objects.json: pump:", "fixed"))


func test_old_save_gains_props_and_skips_a_blocked_spot():
	var p := _pack()
	p.rooms["main"]["props"] = [{"type": "shelf", "x": 4, "y": 4}]
	p.rooms["yard"]["props"] = [{"type": "pump", "x": 7, "y": 5}]
	var w := _world(p)
	w.command({"type": "adopt"})
	var d := _through_json(w.to_dict())
	d["objects"] = d["objects"].filter(func(o): return not (o["type"] in ["pump", "shelf"]))
	d["objects"].append({"uid": 900, "type": "fridge", "room": "main", "x": 5, "y": 4})  # blocks the shelf
	d["next_uid"] = 901
	d["rooms_built"] = ["main"]  # the yard is backfilled, and its pump placed
	var r := WorldSave.restore(p, d)
	assert_eq(r.error, "")
	var loaded: World = r.world
	assert_eq(loaded.rooms_built, ["main", "yard"] as Array[String])
	assert_eq(loaded.objects.filter(func(o): return o.type == "pump").size(), 1)
	assert_eq(loaded.objects.filter(func(o): return o.type == "shelf").size(), 0)


func test_smoke_save_loads_without_any_backfill():
	var w := _world(Pack.load_dir(SMOKE))
	w.command({"type": "adopt"})
	var d := _through_json(w.to_dict())
	assert_eq(WorldSave.restore(w.pack, d).world.to_dict(), w.to_dict())
