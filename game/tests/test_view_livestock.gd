extends TestCase
## Livestock in the view: hens in the coop from the start, pigs bought and sold at the
## market's livestock section, a pig asleep in its lying picture, the buyer's card, and a
## hungry pig calling as a notice.

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
