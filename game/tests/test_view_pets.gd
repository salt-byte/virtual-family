extends TestCase
## Animals in the view: a small shape per pet at home, clicked to show it in the bar,
## a target for a carried person, sold in the shop, on the family record, and the stray card.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_view_pets_%d/" % n
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


func test_a_pet_at_home_gets_a_view_that_goes_when_it_runs_off():
	var m := _main()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	m.tick(0.016)
	assert_true(m.house.pets.has(dog.uid))
	var pv: PetView = m.house.pets[dog.uid]
	assert_true(pv.body().x < PersonView.BODY.x * 1.2, "smaller than a person")
	assert_true(pv.hit(pv.position + Vector2(0, -4)))
	assert_eq(m.house.pet_at(pv.position + Vector2(0, -4)), dog.uid)
	dog.state = "away"
	m.tick(0.016)
	assert_true(not m.house.pets.has(dog.uid))
	_done(m)


func test_clicking_a_pet_shows_it_in_the_bar():
	var m := _main()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	m.tick(0.016)
	m.select_pet(dog.uid)
	m.tick(0.016)
	assert_true(m.hud.bar_text().contains(dog.given), m.hud.bar_text())
	assert_true(m.hud.judge_disabled())
	m.select(w.people[0].uid)
	assert_eq(m.selected_pet, -1)
	_done(m)


func test_carrying_a_person_onto_a_pet_highlights_it_and_starts_care():
	var m := _main()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	dog.needs["fondness"] = 10.0
	m.tick(0.016)
	var pv: PetView = m.house.pets[dog.uid]
	var at := pv.position + Vector2(0, -4)
	var p := w.people[0]
	m.drag.begin(p.uid)
	m.drag.move(at)
	assert_eq(str(m.house.hover.get("kind", "")), "pet")
	assert_eq(int(m.house.hover.get("uid", -1)), dog.uid)
	var r := m.drag.drop(at)
	assert_true(r.get("ok", false), str(r))
	assert_eq(int(p.current.get("target_uid", -1)), dog.uid)
	_done(m)


func test_the_shop_sells_pets_and_the_family_panel_keeps_the_dead():
	var m := _main()
	var w := m.session.world
	w.money = 1000
	m.panels.open("shop")
	assert_true(m.panels.has_button("buy_pet:dog"))
	assert_true(m.panels.is_disabled("buy_pet:bird"), "no cage yet")
	m.panels.press("buy_pet:dog")
	assert_eq(PetSystem.at_home(w), 1)
	m.panels.close()
	var dog := w.pets[0]
	PetSystem.die(w, dog, "old_age")
	m.panels.open("family")
	assert_true(m.panels.text().contains(dog.given), m.panels.text())
	assert_true(m.panels.text().contains("老死"), m.panels.text())
	_done(m)


func test_a_stray_at_the_gate_shows_a_card():
	var m := _main()
	var w := m.session.world
	w.pet_offer = {"kind": "cat", "given": "花花", "age": 2.0, "expires_at": w.now + 3600}
	m.tick(0.016)
	assert_eq(m.overlays.current(), "", "the card waits for the player, like a proposal")
	assert_true(m.hud.bar_text().contains("●"))
	m.panels.open("family")
	m.panels.press("stray")
	assert_eq(m.overlays.current(), "stray")
	m.overlays.press("btn.take_in")
	assert_eq(PetSystem.at_home(w), 1)
	assert_eq(m.overlays.current(), "")
	_done(m)
