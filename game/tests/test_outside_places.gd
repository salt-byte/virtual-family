extends TestCase
## Places outside the house (rooms with `outside`): always there, open ground, nothing is
## set down there and no mess appears there; each has things done only there, by day; things
## lying about can fall there. People go out for those and come home for the rest.

const QIJIA := "res://packs/qijia"


func _outside(p: Pack) -> Array:
	return p.rooms.keys().filter(func(id): return bool(p.rooms[id]["outside"]))


func test_qijia_has_five_places_outside_the_wall():
	var p := Pack.load_dir(QIJIA)
	assert_true(p.is_valid(), str(p.errors))
	var out := _outside(p)
	assert_eq(out.size(), 5, str(out))
	var site: Dictionary = p.config["site"]
	var c := Rect2i(site["compound"]["x"], site["compound"]["y"], site["compound"]["w"], site["compound"]["h"])
	for id in out:
		var r: Dictionary = p.rooms[id]
		assert_true(r["outdoor"] and r["built"], id)
		assert_true(not c.intersects(Rect2i(r["x"], r["y"], r["w"], r["h"])), "%s lies outside the compound" % id)
	for id in p.rooms:
		if not id in out:
			var r2: Dictionary = p.rooms[id]
			assert_true(c.encloses(Rect2i(r2["x"], r2["y"], r2["w"], r2["h"])), "%s lies inside the compound" % id)


func test_each_outside_place_has_its_own_things_by_day():
	var p := Pack.load_dir(QIJIA)
	for id in _outside(p):
		var only: Array = []
		for a in p.actions.values():
			if (a["rooms"] as Array).has(id):
				assert_eq(a["rooms"], [id], "%s is done only at %s" % [a.id, id])
				only.append(a.id)
				var h: Array = a["hours"]
				assert_true(h.size() == 2 and h[0] >= 6 and h[1] <= 19 and h[0] < h[1], "%s by day: %s" % [a.id, h])
		assert_true(only.size() >= 3, "%s: %s" % [id, only])


func test_nothing_is_set_down_outside_and_no_mess_appears_there():
	var w := BalanceRun.setup("qijia", 4)
	w.money = 5000
	var out := _outside(w.pack)
	for id in out:
		assert_eq(HouseSystem.can_place(w, "stool", id, 0, 0), "wrong_area")
		assert_eq(HouseSystem.can_place(w, "millstone", id, 0, 0), "wrong_area")
		assert_eq(w.command({"type": "place", "object_type": "stool", "room": id, "x": 0, "y": 0}).error, "wrong_area")
	for i in 300:
		for t in w.pack.mess_types:
			MessSystem.spawn(w, str(t))
	for m in w.messes:
		assert_true(not m.room in out, str(m))
	assert_true(w.messes.size() > 0)


func test_things_lying_about_also_fall_outside():
	var w := BalanceRun.setup("qijia", 5)
	var out := _outside(w.pack)
	var seen := {}
	for i in 400:
		var uid := CollectibleSystem.spawn(w)
		var c := CollectibleSystem.find(w, uid)
		if c.room in out:
			seen[c.room] = true
	assert_true(seen.size() >= 3, str(seen))


func test_an_outside_place_must_be_open_ground_without_furniture():
	var p := Pack.load_dir(QIJIA)
	p.rooms["riverside"]["outdoor"] = false
	assert_true(PackValidator.validate(p).has("rooms.json: riverside: an outside place must be outdoor and built"))
	p.rooms["riverside"]["outdoor"] = true
	p.rooms["riverside"]["props"] = [{"type": "well_head", "x": 0, "y": 0}]
	assert_true(PackValidator.validate(p).has("rooms.json: riverside: an outside place has no furniture (props)"))


func test_smoke_has_no_outside_places():
	var p := Pack.load_dir("res://packs/_smoke")
	assert_eq(_outside(p), [])


## By day the household goes out now and then; at night everyone is at home.
func test_people_go_out_by_day_and_sleep_at_home():
	var outside_starts := 0
	var night_outside := 0
	for seed in [1, 2, 3]:
		var w := BalanceRun.family_of_four("qijia", seed)
		var out := _outside(w.pack)
		for h in 30:
			BalanceRun.caretake(w)
			while not w.proposals.is_empty():
				w.command({"type": "answer_proposal", "id": w.proposals[0]["id"], "accept": false})
			w.advance(3600.0)
			var hour := w.local_hour()
			for p in w.people:
				var room := str(p.current.get("room", ""))
				if room in out:
					if hour >= 21.0 or hour < 5.0:
						night_outside += 1
			for e in w.drain_events():
				if e.type == "action_started":
					var a: Dictionary = w.pack.actions.get(str(e.action), {})
					if (a.get("rooms", []) as Array).any(func(r): return r in out):
						outside_starts += 1
	assert_true(outside_starts >= 10, "went out %d times" % outside_starts)
	assert_eq(night_outside, 0)
