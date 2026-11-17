extends TestCase

func _pack() -> Pack:
	return Pack.load_dir("res://packs/qijia")

func test_rooms_sit_left_to_right_bottom_aligned():
	var l := HouseLayout.new(_pack())
	assert_eq(l.room_rect("hall"), Rect2(0, 0, 384, 216))
	assert_eq(l.room_rect("side"), Rect2(432, 72, 240, 144))
	assert_eq(l.room_rect("yard").position.x, 720.0)

func test_cell_roundtrip_and_outside():
	var l := HouseLayout.new(_pack())
	assert_eq(l.pos_to_cell(l.cell_center("yard", 8, 5)), {"room": "yard", "x": 8, "y": 5})
	assert_eq(l.pos_to_cell(Vector2(400, 10)), {})

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
	var low := {"type": t, "room": "yard", "x": 0, "y": 6 - h}
	assert_eq(l.stand_pos(low, p), l.object_rect(low, p).get_center())
	assert_true(w > 0)

func test_bounds_cover_rooms_and_walls():
	var l := HouseLayout.new(_pack())
	var b := l.bounds()
	for id in ["hall", "side", "yard"]:
		assert_true(b.encloses(l.room_rect(id)), id)
	assert_eq(b.position.y, -HouseLayout.WALL)
	assert_eq(b.end.x, l.room_rect("yard").end.x)
	assert_eq(b.end.y, 216.0)


func test_nearest_room_picks_closest_of_the_given_rooms():
	var pack := Pack.load_dir("res://packs/qijia")
	var l := HouseLayout.new(pack)
	var ids: Array = pack.rooms.keys()
	var r := l.room_rect(ids[0])
	assert_eq(l.nearest_room(r.end + Vector2(5, -5), ids), ids[0])
	assert_eq(l.nearest_room(Vector2.ZERO, []), "")
	assert_eq(l.nearest_room(Vector2.ZERO, [ids[1]]), ids[1])
