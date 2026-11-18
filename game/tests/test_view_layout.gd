extends TestCase

func _pack() -> Pack:
	return Pack.load_dir("res://packs/qijia")

func test_positioned_rooms_sit_where_the_pack_puts_them():
	var l := HouseLayout.new(_pack())
	assert_eq(l.room_rect("hall"), Rect2(7 * 48, 0, 10 * 48, 6 * 36))
	assert_eq(l.room_rect("yard"), Rect2(0, 7 * 36, 15 * 48, 7 * 36))
	assert_eq(l.room_rect("bedroom"), Rect2(0, 0, 6 * 48, 6 * 36))
	assert_eq(l.room_rect("kitchen"), Rect2(18 * 48, 0, 6 * 48, 6 * 36))
	assert_eq(l.room_rect("side"), Rect2(16 * 48, 7 * 36, 8 * 48, 7 * 36))

func test_cell_roundtrip_and_outside():
	var l := HouseLayout.new(_pack())
	var cells := {"bedroom": Vector2i(5, 5), "hall": Vector2i(9, 2), "kitchen": Vector2i(1, 4),
		"yard": Vector2i(14, 6), "side": Vector2i(7, 0)}
	for id in cells:
		var c: Vector2i = cells[id]
		assert_eq(l.pos_to_cell(l.cell_center(id, c.x, c.y)), {"room": id, "x": c.x, "y": c.y}, id)
	# Between the two rows, and between the bedroom and the hall.
	assert_eq(l.pos_to_cell(Vector2(100, 6.5 * 36)), {})
	assert_eq(l.pos_to_cell(Vector2(6.5 * 48, 10)), {})

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
	var low := {"type": t, "room": "yard", "x": 0, "y": 7 - h}
	assert_eq(l.stand_pos(low, p), l.object_rect(low, p).get_center())
	assert_true(w > 0)

func test_bounds_cover_rooms_and_walls():
	var l := HouseLayout.new(_pack())
	var b := l.bounds()
	for id in ["bedroom", "hall", "kitchen", "side", "yard"]:
		assert_true(b.encloses(l.room_rect(id)), id)
	assert_eq(b, Rect2(0, -HouseLayout.WALL, 24 * 48, 14 * 36 + HouseLayout.WALL))


func test_nearest_room_picks_closest_of_the_given_rooms():
	var pack := Pack.load_dir("res://packs/qijia")
	var l := HouseLayout.new(pack)
	var ids: Array = pack.rooms.keys()
	var r := l.room_rect(ids[0])
	assert_eq(l.nearest_room(r.end + Vector2(5, -5), ids), ids[0])
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
