extends TestCase
## The pack's art (`art.json`): pictures where the pack declares them, the whitebox drawing
## everywhere else; a pack without art.json (_smoke) has a disabled skin and draws as before.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_skin_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


func _main(pack: String) -> Main:
	var m := Main.create(pack, _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _done(m: Main) -> void:
	Engine.get_main_loop().root.remove_child(m)
	m.free()


func _art(text: String) -> String:
	var d := _clean_dir()
	var f := FileAccess.open(d + "art.json", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return d + "art.json"


func test_smoke_has_no_skin_and_draws_blocks():
	var skin := PackSkin.new(Pack.load_dir("res://packs/_smoke"))
	assert_true(not skin.enabled)
	assert_true(skin.errors.is_empty())
	assert_eq(skin.ground_tile(), {})
	assert_eq(skin.object_sprite("fridge"), null)
	assert_eq(skin.person_look("adult", "male"), {})
	var m := _main("_smoke")
	assert_true(not m.house.skin.enabled)
	assert_true(m.house.props.is_empty())
	assert_true(m.house.scenery.is_empty())
	assert_eq(m.house.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	for uid in m.house.people:
		var pv: PersonView = m.house.people[uid]
		assert_true(not pv.pictured())
		assert_eq(pv.body_size(), PersonView.BODY)
	_done(m)


func test_qijia_art_all_loads():
	var skin := PackSkin.new(Pack.load_dir("res://packs/qijia"))
	assert_true(skin.enabled)
	for name in skin._table("sprites"):
		assert_true(skin.sprite(name) != null, "sprite " + name)
	for name in skin._table("tiles"):
		assert_true(not skin.tile(name).is_empty(), "tile " + name)
	assert_true(skin.errors.is_empty(), str(skin.errors))


func test_qijia_declares_and_falls_back():
	var skin := PackSkin.new(Pack.load_dir("res://packs/qijia"))
	assert_true(not skin.ground_tile().is_empty())
	assert_true(not skin.compound_tile().is_empty())
	assert_true(not skin.floor_tile("hall").is_empty())
	assert_eq(skin.floor_tile("yard"), {}, "the yard shows the compound ground")
	assert_true(skin.object_sprite("kang") != null)
	# Every qijia object has a picture now; an undeclared type still falls back to a block.
	assert_true(skin.object_sprite("bookshelf") != null)
	assert_eq(skin.object_sprite("no_such_type"), null, "no art: a block")
	assert_true(skin.mess_sprite("dirt") != null)
	assert_eq(skin.mess_sprite("snow_cover"), null)
	assert_true(skin.collectible_sprite("egg") != null)
	assert_true(skin.collectible_sprite("purse") != null)
	assert_eq(skin.collectible_sprite("no_such_type"), null)
	assert_eq(skin.decor_rule("#a8d8e6"), {"hide": true}, "colour keys match in any case")
	assert_eq(skin.decor_rule("#123456"), {})
	assert_true(not skin.scenery().is_empty())
	assert_true(not skin.wall_tile("house").is_empty())
	assert_true(skin.wall_sprite("gate") != null)
	assert_eq(skin.unwell().need, "health")


func test_people_pick_art_by_stage_and_sex():
	var skin := PackSkin.new(Pack.load_dir("res://packs/qijia"))
	assert_eq(skin.person_look("adult", "male").height, 90.0)
	assert_eq(skin.person_look("adult", "female").height, 86.0)
	assert_eq(skin.person_look("elder", "female").height, 74.0)
	assert_eq(skin.person_look("child", "male").height, 62.0)
	assert_true(skin.person_look("adult", "male").tex != skin.person_look("adult", "female").tex)
	assert_eq(skin.person_look("ghost", "male"), {})


func test_missing_or_broken_art_falls_back():
	var skin := PackSkin.new(null, _art('{"sprites": {"a": "nope.png"}, "objects": {"kang": "a"}, "tiles": {"t": {"file": "nope.png"}}, "ground": "t"}'))
	assert_true(skin.enabled)
	assert_eq(skin.object_sprite("kang"), null)
	assert_eq(skin.ground_tile(), {})
	assert_true(not skin.errors.is_empty())
	var bad := PackSkin.new(null, _art("{nope"))
	assert_true(not bad.enabled)
	assert_true(not bad.errors.is_empty())
	var none := PackSkin.new(null, "user://no_such_dir/art.json")
	assert_true(not none.enabled)
	assert_true(none.errors.is_empty())


func test_fit_rect_stands_on_its_foot():
	var tex: Texture2D = PackSkin.new(Pack.load_dir("res://packs/qijia")).sprite("kang")
	var r := PackSkin.fit_rect(tex, Vector2(100, 200), Vector2(120, 500))
	assert_near(r.end.y, 200.0)
	assert_near(r.get_center().x, 100.0)
	assert_near(r.size.x, 120.0)
	assert_near(r.size.x / r.size.y, float(tex.get_width()) / tex.get_height())


func test_qijia_house_stands_pictures_and_people():
	var m := _main("qijia")
	var house := m.house
	var w := m.session.world
	assert_true(house.skin.enabled)
	assert_eq(house.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert_true(not house.scenery.is_empty())
	var pictured := 0
	for o in w.objects:
		if house.skin.object_sprite(str(o.type)) != null:
			pictured += 1
			assert_true(house.props.has(int(o.uid)), str(o.type))
			var piece: PropPiece = house.props[int(o.uid)]
			var r := house.layout.object_rect(o, w.pack)
			# The 45° view: the piece stands at the middle of its footprint (what it sorts by),
			# the picture upright on the footprint's bottom corner and as wide as its diamond,
			# or, at its real size, shrunk about the footprint's middle; seats and beds sort a
			# little further back (someone on them is drawn over them).
			assert_eq(piece.position, r.get_center(), "stands on its footprint")
			var d := IsoMath.diamond(r)
			var foot := IsoMath.to_view(piece.position)
			var k := house.fill(o, r)
			assert_near(foot.y + piece.rect.end.y, foot.y + (d[2].y - foot.y) * k + 6.0, 0.01, "on the bottom corner")
			assert_true(piece.rect.size.x <= d[1].x - d[3].x + 0.01, str(o.type))
			assert_eq(piece.sort_bias < HouseView.FURNITURE_BIAS, house.skin.sat_on(str(o.type)), str(o.type))
	assert_eq(house.props.size(), pictured)
	assert_true(pictured > 0)
	for p in house.walls:
		assert_true(p.skin == house.skin)
	for uid in house.people:
		var pv: PersonView = house.people[uid]
		assert_true(pv.pictured())
		var body := pv.body_size()
		assert_true(body.y >= 40.0 and body.y <= 90.0, str(body))
		# The head of the taller picture is clickable, above the old block (upright on the
		# screen, over the feet).
		var feet := house.to_screen(pv.position)
		var k := house.scale.x
		assert_true(pv.hit(house.world_pos(feet + Vector2(0, -body.y + 6) * k)))
		assert_true(not pv.hit(house.world_pos(feet + Vector2(0, -body.y - 12) * k)))
		assert_true(not pv.hit(house.world_pos(feet + Vector2(body.x, 0) * k)))
	_done(m)


func test_unwell_mark_follows_the_need_threshold():
	var m := _main("qijia")
	var pv: PersonView = m.house.people.values()[0]
	pv.person.needs["health"] = 30.0
	pv.refresh()
	assert_true(pv._unwell)
	pv.person.needs["health"] = 90.0
	pv.refresh()
	assert_true(not pv._unwell)
	_done(m)


func test_props_follow_objects_moved_and_removed():
	var m := _main("qijia")
	var house := m.house
	var w := m.session.world
	var o: Dictionary = {}
	for x in w.objects:
		if house.props.has(int(x.uid)):
			o = x
			break
	assert_true(not o.is_empty())
	var before: Rect2 = house.props[int(o.uid)].rect
	w.objects.erase(o)
	house.refresh()
	assert_true(not house.props.has(int(o.uid)))
	var moved := o.duplicate()
	moved.x = int(o.x) + 1
	w.objects.append(moved)
	house.refresh()
	assert_true(house.props.has(int(o.uid)))
	# In the 45° view the piece moves with its footprint: a cell east is half a diamond right
	# and down on the screen; the picture keeps its place round the foot.
	var piece: PropPiece = house.props[int(o.uid)]
	var spot := house.iso_picture(moved, piece.tex, w)
	assert_eq(piece.rect, spot.rect)
	assert_eq(piece.rect, before)
	assert_eq(piece.position, house.layout.object_rect(moved, w.pack).get_center())
	_done(m)


## Each look of the pack draws its own rigs at its own height, every look has a portrait and
## words, and a grown-up look's body (feet to neck) is as big as the father's within 8 %.
func test_people_wear_their_looks():
	var m := _main("qijia")
	var skin := m.house.skin
	var w := m.session.world
	var father := skin.person_look("adult", "male")
	var fr: CutoutRig = father.rig
	var neck := func(look: Dictionary) -> float:
		var r: CutoutRig = look.rig
		var k: float = float(look.height) / r.height
		var wd := r.world({})
		return (-(wd["leg_upper"] as Transform2D).origin.y + r._by_id["torso"].size.y) * k
	var base: float = neck.call(father)
	for e in LookSystem.looks(w.pack):
		var id := str(e["id"])
		var look := skin.person_look(str(e["stage"]), str(e["sex"]), id)
		assert_eq(str(look.get("look", "")), id)
		assert_true(look.has("rig_front") and look.has("rig_back"), id)
		assert_true(skin.portrait(id) != null, id)
		assert_true(str(skin.look_text(id).get("name", "")) != "", id)
		if str(e["stage"]) == "adult" and str(e["sex"]) == "male":
			var n: float = neck.call(look)
			assert_true(absf(n / base - 1.0) < 0.08, "%s body %.1f vs father %.1f" % [id, n, base])
	# Whoever lives in the house is drawn in their look.
	for uid in m.house.people:
		var pv: PersonView = m.house.people[uid]
		if pv.person.look != "" and pv.person.look != LookSystem.CHILD:
			assert_eq(str(pv._look.get("look", "")), pv.person.look)
	# No look (old saves): the stage's entry.
	assert_eq(skin.person_look("adult", "male", ""), father)
	_done(m)
