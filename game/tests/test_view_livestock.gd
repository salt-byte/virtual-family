extends TestCase
## Livestock in the view: hens in the coop from the start, pigs bought and sold at the
## market's livestock section, a pig asleep in its lying picture, the buyer's card, a hungry
## pig calling as a notice; no plates on the animals until hovered or selected, short call
## bubbles, the pens' fences, the coop picture to the hens' scale and scenery clear of the pens.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_view_livestock_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	return m


func _done(m: Main) -> void:
	m.get_parent().remove_child(m)
	m.free()


func _sty(m: Main) -> void:
	var w := m.session.world
	w.money += 500
	assert_true(m.session.command({"type": "build_room", "room": "pigsty"}).ok)


## Lets the views walk where they are going.
func _settle(m: Main, pv: PetView) -> void:
	for i in 900:
		m.tick(1.0 / 30.0)
		if pv.pose() != "walking":
			break


func test_the_hens_that_came_with_the_house_stand_in_the_coop():
	var m := _main()
	var w := m.session.world
	var hens := w.pets.filter(func(p): return p.kind == "hen")
	assert_eq(hens.size(), 2)
	for h in hens:
		assert_true(m.house.pets.has(h.uid))
		var pv: PetView = m.house.pets[h.uid]
		assert_true(not pv._look.is_empty(), "the hen picture")
		assert_near(pv.body().y, 28.0, 0.5)
	_done(m)


func test_piglets_are_bought_and_grown_pigs_sold_at_the_livestock_stall():
	var m := _main()
	var w := m.session.world
	w.money = 1000
	m.panels.open("shop")
	m.panels.press("market:livestock")
	assert_true(m.panels.is_disabled("buy_pet:piglet"), "no pigsty yet")
	assert_true(m.panels.text().contains("先盖猪圈"), m.panels.text())
	m.panels.close()
	_sty(m)
	m.panels.open("shop")
	m.panels.press("market:livestock")
	m.panels.press("buy_pet:piglet")
	var pig: Pet = w.pets.filter(func(p): return p.kind == "piglet")[0]
	assert_true(m.panels.has_button("buy:bran"))
	assert_true(not m.panels.has_button("sell_pet:%d" % pig.uid), "too light to sell")
	pig.kind = "pig"
	pig.weight = 110.0
	m.panels.refresh()
	assert_true(m.panels.has_button("sell_pet:%d" % pig.uid))
	assert_true(m.panels.text().contains("110 斤"), m.panels.text())
	var before := w.money
	m.panels.press("sell_pet:%d" % pig.uid)
	assert_eq(w.money, before + 264)
	assert_true(not pig.alive)
	m.panels.close()
	m.panels.open("family")
	assert_true(m.panels.text().contains("养肥卖了"), m.panels.text())
	_done(m)


func test_a_pig_asleep_shows_its_lying_picture_in_the_pen():
	var m := _main()
	var w := m.session.world
	_sty(m)
	var pig := PetSystem.add(w, "pig", "bought")
	pig.weight = 90.0
	m.tick(0.016)
	var pv: PetView = m.house.pets[pig.uid]
	var standing := pv.body()
	assert_near(standing.y, 44.0, 0.5)
	pig.current = {"action": "pig_sleep", "remaining_s": 99999, "room": "pigsty"}
	m.tick(0.016)
	_settle(m, pv)
	assert_true(pv.lying())
	assert_near(pv.body().y, 29.0, 0.5)
	assert_true(pv.body().x > standing.x * 0.6, "a lying pig is long and low")
	assert_true(m.house.layout.room_rect("pigsty").grow(1.0).has_point(pv.position), "inside the pigsty")
	assert_true(m.session.strings.pet_line(pig, w).contains("90 斤"), m.session.strings.pet_line(pig, w))
	_done(m)


func test_the_buyer_waits_as_a_notice_and_a_card_sells_the_pig():
	var m := _main()
	var w := m.session.world
	_sty(m)
	var pig := PetSystem.add(w, "pig", "bought")
	pig.weight = 130.0
	w.pet_buyer = {"pet": pig.uid, "price": 359, "expires_at": w.now + 3600}
	m.tick(0.016)
	assert_eq(m.overlays.current(), "", "the buyer waits for the player")
	assert_true(m.hud.notices().any(func(x): return x["kind"] == "buyer"), m.hud.notice_text())
	m.open_notice({"kind": "buyer", "target": pig.uid})
	assert_eq(m.overlays.current(), "buyer")
	assert_true(m.overlays.text().contains("猪贩子"), m.overlays.text())
	assert_true(m.overlays.text().contains(pig.given), m.overlays.text())
	var before := w.money
	m.overlays.press("btn.sell_to_buyer")
	assert_eq(w.money, before + 359)
	assert_true(not pig.alive)
	assert_eq(m.overlays.current(), "")
	_done(m)


func test_a_hungry_pig_calls_and_the_notice_selects_it():
	var m := _main()
	var w := m.session.world
	_sty(m)
	var pig := PetSystem.add(w, "piglet", "bought")
	pig.needs["belly"] = 5.0
	clk["unix"] += 120.0
	m.tick(0.016)
	assert_true(not pig.wish.is_empty())
	var hungry := m.hud.notices().filter(func(x): return x["kind"] == "pet_hungry")
	assert_eq(hungry.size(), 1, m.hud.notice_text())
	m.open_notice(hungry[0])
	assert_eq(m.selected_pet, pig.uid)
	assert_true(m.house.pets[pig.uid].wish_bubble() != "")
	clk["unix"] -= 120.0
	_done(m)


func test_animals_wear_no_plate_until_hovered_or_selected():
	var m := _main()
	var w := m.session.world
	var hen: Pet = w.pets.filter(func(p): return p.kind == "hen")[0]
	var pv: PetView = m.house.pets[hen.uid]
	assert_eq(pv.plate_text(), "")
	assert_true(not pv.shows_label())
	assert_true(not m.house.label_spots().has(hen.uid), "no plate by default")
	m.house.set_hover({"kind": "pet", "uid": hen.uid})
	assert_eq(pv.plate_text(), hen.given + "（母鸡）")
	assert_true(m.house.label_spots().has(hen.uid), "the name while hovered")
	m.house.set_hover({})
	m.select_pet(hen.uid)
	assert_true(pv.plate_text().begins_with(hen.given) and " · " in pv.plate_text(), pv.plate_text())
	assert_true(m.house.label_spots().has(hen.uid))
	_done(m)


func test_a_call_is_a_short_bubble_alone_and_the_whole_text_is_in_the_notice():
	var m := _main()
	var w := m.session.world
	_sty(m)
	var pig := PetSystem.add(w, "piglet", "bought")
	pig.needs["belly"] = 5.0
	clk["unix"] += 120.0
	m.tick(0.016)
	var pv: PetView = m.house.pets[pig.uid]
	assert_eq(pv.wish_bubble(), "饿了")
	assert_eq(pv._bubble.icon, "bowl")
	assert_eq(pv.plate_text(), "", "the bubble alone, no name")
	assert_true(m.house.label_spots().has(pig.uid))
	assert_near(pv.label_size().x, NeedBubble.size_of(pv._bubble).x, 0.5)
	var hungry := m.hud.notices().filter(func(x): return x["kind"] == "pet_hungry")
	assert_true(str(hungry[0]["text"]).contains("拿鼻子顶空槽子"), str(hungry[0]))
	clk["unix"] -= 120.0
	_done(m)


func test_many_animals_plates_keep_clear_of_each_other():
	var m := _main()
	var w := m.session.world
	_sty(m)
	for i in 3:
		PetSystem.add(w, "piglet", "bought")
	m.tick(0.016)
	var at := m.house.layout.cell_center("pigsty", 3, 2)
	for p in w.pets:
		var pv: PetView = m.house.pets[p.uid]
		pv.position = at + Vector2(randf_range(-4, 4), randf_range(-3, 3))
		p.needs["belly"] = 5.0
	clk["unix"] += 120.0
	m.tick(0.016)
	for p in w.pets:
		m.house.pets[p.uid].position = at
	var spots := m.house.label_spots()
	var rects: Array = []
	for uid in spots:
		var size: Vector2 = m.house.label_owner(uid).label_size()
		rects.append(Rect2(spots[uid] - Vector2(size.x * 0.5, size.y), size))
	assert_true(rects.size() >= 4, "every hungry animal calls")
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_true(not (rects[i] as Rect2).intersects(rects[j]), "bubbles %d and %d overlap" % [i, j])
	clk["unix"] -= 120.0
	_done(m)


func test_the_pigsty_has_a_fence_with_a_gate_and_the_coop_run_a_closed_south_side():
	var m := _main()
	var site := m.house.layout.site
	# The coop run's south side is a fence from the start; the pigsty's west side once built.
	for x in range(39, 45):
		assert_eq(site.h_walls.get(Vector2i(x, 19), ""), HouseSite.FENCE)
	assert_true(not site.v_walls.has(Vector2i(39, 22)), "no pen rails before the pigsty is built")
	_sty(m)
	m.tick(0.016)
	var gaps := 0
	for y in range(19, 25):
		assert_eq(site.v_walls.get(Vector2i(39, y), ""), HouseSite.FENCE)
		if site.v_free(Vector2i(39, y)):
			gaps += 1
	assert_eq(gaps, 1, "one gate in the pigsty's fence")
	# People walk in through it to the trough; elsewhere the rails stop them.
	assert_true(site.step_open(Vector2i(38, 21), Vector2i(39, 21)), "the gate")
	assert_true(not site.step_open(Vector2i(38, 23), Vector2i(39, 23)))
	assert_true(not site.step_open(Vector2i(41, 18), Vector2i(41, 19)), "the coop run and the pigsty apart")
	var from := m.house.layout.cell_center("veg_plot", 3, 3)
	var to := m.house.layout.cell_center("pigsty", 2, 2)
	var way := site.route(from, to)
	way.append(to)
	var at := from
	for p in way:
		assert_true(not site.crosses_wall(at, p), "a way into the pen through the gate")
		at = p
	_done(m)


func test_the_coop_picture_and_the_live_hens_are_drawn_to_one_scale():
	var m := _main()
	var w := m.session.world
	var coop := {}
	for o in w.objects:
		if o.type == "coop":
			coop = o
	var piece: PropPiece = m.house.props[int(coop.uid)]
	# The coop picture's painted hen stands about 0.6 of the picture's height.
	var painted := piece.rect.size.y * 0.6
	var hen: Pet = w.pets.filter(func(p): return p.kind == "hen")[0]
	var live: float = m.house.pets[hen.uid].body().y
	assert_true(absf(painted - live) <= live * 0.2, "painted hen %.0f px, live hen %.0f px" % [painted, live])
	_done(m)


func test_no_standing_scenery_hides_the_pens_or_the_gate():
	var m := _main()
	var w := m.session.world
	w.money += 5000
	for id in ["pigsty", "veg_plot"]:
		m.session.command({"type": "build_room", "room": id})
	m.tick(0.016)
	var l := m.house.layout
	for piece in m.house.scenery:
		var img := piece.tex.get_image()
		if img.is_compressed():
			img.decompress()
		var at := IsoMath.to_view(piece.position)
		var rect := Rect2(at + piece.rect.position, piece.rect.size)
		var depth := at.y
		for room in ["pigsty", "coop_run", "gate"]:
			var r := l.room_rect(room)
			for i in int(r.size.x / 24.0):
				for j in int(r.size.y / 18.0):
					var p := IsoMath.to_view(r.position + Vector2(i * 24.0 + 12.0, j * 18.0 + 9.0))
					if p.y >= depth:
						continue
					for lift in [5.0, 35.0, 70.0]:
						var q := p - Vector2(0, lift)
						if not rect.has_point(q):
							continue
						var u := int((q.x - rect.position.x) / rect.size.x * img.get_width())
						var v := int((q.y - rect.position.y) / rect.size.y * img.get_height())
						assert_true(img.get_pixel(u, v).a < 0.5, "a picture at %s covers %s" % [piece.position, room])
	_done(m)
