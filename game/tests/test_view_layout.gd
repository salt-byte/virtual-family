extends TestCase

func _pack() -> Pack:
	return Pack.load_dir("res://packs/qijia")

func test_positioned_rooms_sit_where_the_pack_puts_them():
	var l := HouseLayout.new(_pack())
	# The connected house (ART_DIRECTION section 10): the compound's corner sits at map (17, 9).
	assert_eq(l.room_rect("hall"), Rect2(35 * 48, 9 * 36, 15 * 48, 9 * 36))
	assert_eq(l.room_rect("yard"), Rect2(26 * 48, 18 * 36, 25 * 48, 11 * 36))
	assert_eq(l.room_rect("bedroom"), Rect2(50 * 48, 9 * 36, 9 * 48, 9 * 36))
	assert_eq(l.room_rect("kitchen"), Rect2(17 * 48, 18 * 36, 9 * 48, 9 * 36))
	assert_eq(l.room_rect("side"), Rect2(59 * 48, 9 * 36, 9 * 48, 9 * 36))
	assert_eq(l.room_rect("threshing"), Rect2(26 * 48, 29 * 36, 10 * 48, 9 * 36))

func test_cell_roundtrip_and_outside():
	var l := HouseLayout.new(_pack())
	var cells := {"bedroom": Vector2i(5, 5), "hall": Vector2i(9, 2), "kitchen": Vector2i(1, 4),
		"yard": Vector2i(16, 6), "side": Vector2i(5, 0), "gate": Vector2i(7, 5), "west_room": Vector2i(0, 0)}
	for id in cells:
		var c: Vector2i = cells[id]
		assert_eq(l.pos_to_cell(l.cell_center(id, c.x, c.y)), {"room": id, "x": c.x, "y": c.y}, id)
	# Rooms share walls now, so there are no gaps between them: outside the compound wall
	# (north of it, and on the road south of the gate) is no room.
	assert_eq(l.pos_to_cell(Vector2(100, 6.5 * 36)), {})
	assert_eq(l.pos_to_cell(Vector2(42 * 48, 44 * 36)), {})

func test_pick_priority_and_unbuilt_room():
	var w := BalanceRun.setup("qijia", 1)
	var l := HouseLayout.new(w.pack)
	var o: Dictionary = w.objects[0]
	var at := l.object_rect(o, w.pack).get_center()
	assert_eq(l.pick(w, at).kind, "object")
	w.messes.append({"uid": 9001, "type": "dirt", "room": o.room, "x": o.x, "y": o.y})
	assert_eq(l.pick(w, l.cell_center(o.room, o.x, o.y)).uid, 9001)
	assert_eq(l.pick(w, l.room_rect("side").get_center()), {"kind": "room", "uid": -1, "room": "side"})
	assert_eq(l.pick(w, Vector2(-500, -500)).kind, "")

func test_collectible_beats_mess():
	var w := BalanceRun.setup("qijia", 1)
	var l := HouseLayout.new(w.pack)
	var o: Dictionary = w.objects[0]
	w.messes.append({"uid": 9001, "type": "dirt", "room": o.room, "x": o.x, "y": o.y})
	w.collectibles.append({"uid": 9002, "type": "x", "room": o.room, "x": o.x, "y": o.y, "expires_at": 99})
	var p := l.pick(w, l.cell_center(o.room, o.x, o.y))
	assert_eq(p.kind, "collectible")
	assert_eq(p.uid, 9002)

func test_stand_pos_below_furniture_or_center_when_against_edge():
	var p := _pack()
	var l := HouseLayout.new(p)
	var t: String = p.object_types.keys()[0]
	var h: int = int(p.object_types[t].h)
	var w: int = int(p.object_types[t].w)
	var mid := {"type": t, "room": "yard", "x": 0, "y": 0}
	var r := l.object_rect(mid, p)
	assert_eq(l.stand_pos(mid, p), Vector2(r.get_center().x, r.end.y + l.CELL.y * 0.5))
	# With a site plan nobody stands on the piece itself (it used to fall back to its middle
	# when the cell below was outside its room): no wall stands between the yard's bottom row
	# and the threshing floor below, so the spot below is used.
	var low := {"type": t, "room": "yard", "x": 0, "y": int(p.rooms["yard"]["h"]) - h}
	var lr := l.object_rect(low, p)
	assert_eq(l.stand_pos(low, p), Vector2(lr.get_center().x, lr.end.y + l.CELL.y * 0.5))
	assert_true(not lr.has_point(l.stand_pos(low, p)))
	assert_true(w > 0)

func test_bounds_cover_rooms_and_walls():
	var l := HouseLayout.new(_pack())
	var b := l.bounds()
	for id in _pack().rooms:
		assert_true(b.encloses(l.room_rect(id)), id)
	# With a site plan the bounds are the whole map (84 x 48 cells), not the rooms' extent.
	var site: Dictionary = _pack().config["site"]
	assert_eq(Vector2i(int(site["w"]), int(site["h"])), Vector2i(84, 48))
	assert_eq(b, Rect2(0, 0, 84 * 48, 48 * 36))


func test_nearest_room_picks_closest_of_the_given_rooms():
	var pack := Pack.load_dir("res://packs/qijia")
	var l := HouseLayout.new(pack)
	var ids: Array = pack.rooms.keys()
	var r := l.room_rect(ids[0])
	# Rooms touch now (shared walls); a point just north of the first room is nearest to it.
	assert_eq(l.nearest_room(Vector2(r.get_center().x, r.position.y - 5), ids), ids[0])
	assert_eq(l.nearest_room(Vector2.ZERO, []), "")
	assert_eq(l.nearest_room(Vector2.ZERO, [ids[1]]), ids[1])

func test_furniture_only_pick_skips_messes_and_collectibles():
	var w := BalanceRun.setup("qijia", 1)
	var l := HouseLayout.new(w.pack)
	var o: Dictionary = w.objects[0]
	var at := l.cell_center(o.room, o.x, o.y)
	w.messes.append({"uid": 9001, "type": "dirt", "room": o.room, "x": o.x, "y": o.y})
	w.collectibles.append({"uid": 9002, "type": "egg", "room": o.room, "x": o.x, "y": o.y, "expires_at": 0})
	assert_eq(l.pick(w, at).uid, 9002)
	assert_eq(l.pick(w, at, true), {"kind": "object", "uid": o.uid, "room": o.room})

func test_rooms_without_a_numeric_size_are_left_out_without_errors():
	var p := Pack.load_dir("res://tests/fixtures/sizeless_room_pack")
	assert_true(not p.is_valid())
	var l := HouseLayout.new(p)
	assert_eq(l.room_rect("main").size, Vector2(384, 216))
	assert_eq(l.room_rect("study"), Rect2())
	assert_eq(l.room_rect("yard"), Rect2())
	assert_true(l.bounds().size.x > 0.0)

func test_mess_and_collectible_names_come_from_the_pack():
	var p := _pack()
	assert_eq(HouseView.thing_name(p.mess_types, "dirt"), str(p.mess_types["dirt"]["name"]))
	assert_eq(HouseView.thing_name(p.collectibles, "egg"), str(p.collectibles["egg"]["name"]))
	assert_eq(HouseView.thing_name(p.collectibles, "nope"), "")

func test_smoke_rooms_keep_the_left_to_right_strip():
	var l := HouseLayout.new(Pack.load_dir("res://packs/_smoke"))
	assert_eq(l.room_rect("main"), Rect2(0, 0, 384, 216))
	assert_eq(l.room_rect("study"), Rect2(432, 72, 240, 144))
	assert_eq(l.room_rect("yard"), Rect2(720, 0, 384, 216))
	assert_eq(l.bounds(), Rect2(0, -30, 1104, 246))
