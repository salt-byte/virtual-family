extends TestCase
## Switching between the people of the house from the bar (`Hud`, `FamilyStrip`): the strip of
## faces, the ◀ ▶ beside the portrait and Tab / ← → select someone and the view follows them;
## whoever is out is dimmed and shown without moving the view. Old saves' people without a
## look get a stand-in look for drawing (`ViewLooks`), the same one every time.

var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _clean_dir() -> String:
	n += 1
	var d := "user://test_switcher_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	return d


## The adopted one, a wife and a child.
func _family() -> Main:
	var m := Main.create("qijia", _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	var w := m.session.world
	var wife := FamilySystem.make_person(w, [24, 28])
	wife.gender = "female"
	w.add_person(wife)
	LookSystem.assign(w, wife)
	w.married = true
	var kid := FamilySystem.make_person(w, [7, 9])
	w.add_person(kid)
	LookSystem.assign(w, kid)
	m.tick(0.016)
	m.tick(0.016)
	return m


func _key(m: Main, code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	m.hud._unhandled_input(e)


func test_strip_shows_everyone_and_a_click_selects_and_follows():
	var m := _family()
	var w := m.session.world
	var uids: Array[int] = []
	for p in w.people:
		uids.append(p.uid)
	var strip := m.hud.strip()
	assert_true(strip.visible)
	assert_eq(strip.uids(), uids)
	assert_true(strip.face(uids[0]).selected, "the one in the bar is ringed")
	assert_true(not strip.face(uids[1]).selected)
	# The wife: selected, the view follows her, her face is ringed now.
	assert_true(strip.click(uids[1]))
	assert_eq(m.selected, uids[1])
	assert_eq(m.house.follow_uid, uids[1])
	m.tick(0.016)
	assert_true(strip.face(uids[1]).selected)
	assert_true(not strip.face(uids[0]).selected)
	assert_true(m.hud.bar_text().contains(w.people[1].given))
	# Animals are not in the strip.
	assert_true(not strip.click(9999))
	m.free()


func test_arrows_and_keys_step_through_the_family():
	var m := _family()
	var w := m.session.world
	var a: int = w.people[0].uid
	var b: int = w.people[1].uid
	var c: int = w.people[2].uid
	assert_true(m.hud.arrow(1).visible and m.hud.arrow(-1).visible)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	m.hud.arrow(1)._gui_input(click)
	assert_eq(m.selected, b)
	assert_eq(m.house.follow_uid, b)
	m.hud.arrow(-1)._gui_input(click)
	assert_eq(m.selected, a)
	# Round the ends.
	m.hud.arrow(-1)._gui_input(click)
	assert_eq(m.selected, c)
	assert_eq(m.house.follow_uid, c)
	_key(m, KEY_TAB)
	assert_eq(m.selected, a)
	_key(m, KEY_TAB)
	assert_eq(m.selected, b)
	_key(m, KEY_TAB, true)
	assert_eq(m.selected, a)
	_key(m, KEY_RIGHT)
	assert_eq(m.selected, b)
	_key(m, KEY_LEFT)
	assert_eq(m.selected, a)
	# Not while a panel covers the house.
	m.panels.open("family")
	m.tick(0.016)
	_key(m, KEY_RIGHT)
	assert_eq(m.selected, a)
	m.free()


func test_one_person_has_no_strip_and_no_arrows():
	var m := Main.create("qijia", _clean_dir(), _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	assert_true(not m.hud.strip().visible)
	assert_true(not m.hud.arrow(1).visible)
	m.free()


func test_someone_out_is_dimmed_and_shown_without_moving_the_view():
	var m := _family()
	var w := m.session.world
	var me: Person = w.people[0]
	var wife: Person = w.people[1]
	var r := w.command({"type": "go_out", "person": wife.uid, "action": "go_to_market"})
	assert_true(r.ok, str(r))
	m.select(me.uid)
	m.tick(0.016)
	var f := m.hud.strip().face(wife.uid)
	assert_true(f.away)
	assert_eq(f.caption, FamilyStrip.word(m.session.strings, "bar.away"))
	assert_true(not m.hud.strip().face(me.uid).away)
	var pan := m.house.position
	assert_true(m.hud.strip().click(wife.uid))
	assert_eq(m.selected, wife.uid, "her status shows in the bar")
	assert_eq(m.house.follow_uid, -1, "the view does not chase someone who is out")
	m.tick(0.1)
	assert_eq(m.house.position, pan)
	m.free()


func test_a_dot_marks_someone_with_a_wish_or_an_illness():
	var m := _family()
	var w := m.session.world
	var wife: Person = w.people[1]
	assert_eq(m.hud.switcher_info(wife.uid)["dot"].a, 0.0)
	m.hud._on_event({"type": "fell_ill", "person": wife.uid})
	m.tick(0.016)
	assert_eq(m.hud.switcher_info(wife.uid)["dot"], ViewWidgets.ACCENT)
	assert_eq(m.hud.strip().face(wife.uid).dot, ViewWidgets.ACCENT)
	m.free()


func test_old_save_people_get_a_stable_look_for_drawing():
	var m := _family()
	var w := m.session.world
	var me: Person = w.people[0]
	var kid: Person = w.people[2]
	me.look = ""   # as in a save from before the looks
	var pick := ViewLooks.of(me, w.pack)
	assert_true(pick != "", "a grown-up gets a stand-in")
	var e := LookSystem.entry(w.pack, pick)
	assert_eq(str(e["sex"]), me.gender)
	assert_eq(str(e["stage"]), me.stage(w.pack))
	for i in 5:
		assert_eq(ViewLooks.of(me, w.pack), pick)
	# The same uid in a loaded copy picks the same; the kernel's look stays "".
	var copy := Person.from_dict(me.to_dict())
	assert_eq(ViewLooks.of(copy, w.pack), pick)
	assert_eq(me.look, "")
	# Different people are spread over the looks (not all the same face).
	var seen := {}
	for uid in range(100, 140):
		var q := Person.from_dict(me.to_dict())
		q.uid = uid
		seen[ViewLooks.of(q, w.pack)] = true
	assert_true(seen.size() > 1, str(seen))
	# A child keeps the stage's own picture; an own look is never replaced.
	kid.look = ""
	assert_eq(ViewLooks.of(kid, w.pack), "")
	w.people[1].look = "adult_6"
	assert_eq(ViewLooks.of(w.people[1], w.pack), "adult_6")
	# The bar shows the stand-in's painted face (not the coloured round), the house its rig.
	m.select(me.uid)
	m.house.refresh()
	m.tick(0.016)
	assert_true(m.hud._face.visible, "a painted face, not the round with a character")
	assert_eq(m.hud._face.look, pick)
	assert_true(m.hud.strip().face(me.uid).tex != null)
	assert_eq(str(m.house.people[me.uid]._look.get("look", "")), pick)
	m.free()


func test_bar_and_strip_fit_at_1280_and_the_strip_shrinks_when_narrow():
	var m := _family()
	var w := m.session.world
	for i in 4:
		var q := FamilySystem.make_person(w, [20, 60])
		w.add_person(q)
		LookSystem.assign(w, q)
	m.tick(0.016)
	var strip := m.hud.strip()
	assert_eq(strip.uids().size(), 7)
	assert_eq(strip.face_size(), FamilyStrip.FACE)
	var bar: Control = m.hud._bar
	var row: Control = bar.get_child(0)
	assert_true(row.get_combined_minimum_size().x <= 1280.0 - 32.0, str(row.get_combined_minimum_size()))
	var sr := Rect2(Vector2(strip.offset_left, 720.0 + strip.offset_top),
		Vector2(strip.offset_right - strip.offset_left, strip.offset_bottom - strip.offset_top))
	assert_true(sr.end.y <= 720.0 - Hud.BAR_HEIGHT, str(sr))
	assert_true(sr.end.x <= 640.0, str(sr))
	# A narrow window: the faces get smaller to fit.
	strip.show_people(m.hud.family(), m.selected, m.hud.switcher_info, null, w.pack, m.session.strings, 260.0)
	assert_true(strip.face_size() < FamilyStrip.FACE)
	assert_true(strip.get_combined_minimum_size().x <= 260.0 + 2.0, str(strip.get_combined_minimum_size()))
	m.free()


# --- What is in store, as quick buttons (`CareTray`) ---------------------------------------

func test_a_selected_dog_shows_its_needs_and_food_in_store_to_feed():
	var m := _family()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	dog.needs["belly"] = 20.0
	w.inventory["pork_bone"] = 2
	w.inventory["dried_fish"] = 1   # the cat's: not offered to the dog
	m.tick(0.016)
	m.select_pet(dog.uid)
	m.tick(0.016)
	var ids: Array = m.hud.meters().map(func(e): return e["id"])
	assert_true(ids.has("belly"), str(ids))
	var tray := m.hud.tray()
	assert_true(tray.visible)
	var texts := tray.texts()
	assert_true(texts.any(func(t): return t.contains("猪棒骨") and t.contains("×2") and t.contains("喂它")), str(texts))
	assert_true(not texts.any(func(t): return t.contains("小鱼干")), str(texts))
	assert_true(texts.has(CareTray.word(m.session.strings, "care.call")), str(texts))
	assert_true(not tray.entries().any(func(e): return e["kind"] == "shop"), "food is in store")
	var before := float(dog.needs["belly"])
	assert_true(tray.press("use", "pork_bone"))
	assert_eq(int(w.inventory["pork_bone"]), 1)
	assert_true(float(dog.needs["belly"]) > before)
	m.free()


func test_call_sends_the_nearest_free_family_member_to_the_animal():
	var m := _family()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	dog.needs["fondness"] = 10.0
	dog.needs["belly"] = 10.0
	for p in w.people:
		AutonomySystem.cancel(w, p)
	m.tick(0.016)
	m.select_pet(dog.uid)
	m.tick(0.016)
	assert_true(m.hud.tray().press("call"))
	var went := w.people.filter(func(p): return int(p.current.get("target_uid", -1)) == dog.uid)
	assert_eq(went.size(), 1, "one of the family is looking after it")
	m.free()


func test_nothing_in_store_offers_the_market_on_the_animals_tab():
	var m := _family()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	w.inventory.erase("pork_bone")
	m.tick(0.016)
	m.select_pet(dog.uid)
	m.tick(0.016)
	var tray := m.hud.tray()
	var go := CareTray.word(m.session.strings, "care.shop").replace("{shop}", m.session.strings.t("btn.shop"))
	assert_true(tray.texts().has(go), str(tray.texts()))
	assert_true(tray.press("shop"))
	assert_eq(m.panels.opened(), "shop")
	assert_true(m.panels.text().contains("猪棒骨"), m.panels.text())
	m.free()


func test_livestock_shows_its_feed_stock_and_a_call():
	var m := _family()
	var w := m.session.world
	var pig := PetSystem.add(w, "pig", "bought")
	w.stock["bran"] = 3
	m.tick(0.016)
	m.select_pet(pig.uid)
	m.tick(0.016)
	var es: Array = m.hud.tray().entries()
	var stock := es.filter(func(e): return e["kind"] == "stock" and e["stock"] == "bran")
	assert_eq(stock.size(), 1, str(es))
	assert_eq(int(stock[0]["count"]), 3)
	assert_eq(str(stock[0]["name"]), "谷糠")
	assert_true(es.any(func(e): return e["kind"] == "call"))
	assert_true(not es.any(func(e): return e["kind"] == "shop"), "bran in store")
	m.free()


func test_a_selected_person_gets_the_snacks_and_clothes_in_store():
	var m := _family()
	var w := m.session.world
	var me: Person = w.people[0]
	w.inventory["sugar_figure"] = 1
	w.inventory["new_clothes"] = 1
	w.inventory["pork_bone"] = 1    # for the dog, not for people
	w.inventory["ginger_pill"] = 1  # a medicine for an illness they do not have
	me.needs["happy"] = 20.0
	m.select(me.uid)
	m.tick(0.016)
	var items: Array = m.hud.tray().entries().map(func(e): return e["item"])
	assert_true(items.has("sugar_figure") and items.has("new_clothes"), str(items))
	assert_true(not items.has("pork_bone") and not items.has("ginger_pill"), str(items))
	assert_true(m.hud.tray().press("use", "sugar_figure"))
	assert_eq(int(w.inventory["sugar_figure"]), 0)
	assert_true(float(me.needs["happy"]) > 20.0)
	# Seen to be ill: the medicines in store are offered (which one fits is the player's guess).
	m.hud._on_event({"type": "fell_ill", "person": me.uid})
	m.tick(0.016)
	items = m.hud.tray().entries().map(func(e): return e["item"])
	assert_true(items.has("ginger_pill"), str(items))
	m.free()


func test_an_item_dragged_onto_someone_in_the_house_is_used_on_them():
	var m := _family()
	var w := m.session.world
	var wife: Person = w.people[1]
	for p in w.people:
		AutonomySystem.cancel(w, p)
	w.inventory["sugar_figure"] = 1
	m.tick(0.016)
	var pv: PersonView = m.house.people[wife.uid]
	pv.target = pv.position
	var at := m.house.to_screen(pv.position + Vector2(0, -20))
	var e: Dictionary = {"kind": "use", "item": "sugar_figure", "name": "糖人", "person": w.people[0].uid}
	assert_eq(m.house.person_at(m.house.world_pos(at)), wife.uid)
	assert_true(m.hud.drop_care(e, at))
	assert_eq(int(w.inventory["sugar_figure"]), 0)
	m.free()
