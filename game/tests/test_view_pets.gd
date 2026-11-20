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
	# With qijia's dog picture (side on) it is longer than a person is wide: compare heights.
	assert_true(pv.body().y < m.house.people.values()[0].body_size().y, "smaller than a person")
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
	m.panels.press("tab.pets")   # the market has category tabs now; animals have their own
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
	# It waits as a labelled notice (was: a dot on the family button).
	assert_true(m.hud.notices().any(func(x): return x["kind"] == "stray"), m.hud.notice_text())
	m.panels.open("family")
	m.panels.press("stray")
	assert_eq(m.overlays.current(), "stray")
	m.overlays.press("btn.take_in")
	assert_eq(PetSystem.at_home(w), 1)
	assert_eq(m.overlays.current(), "")
	_done(m)


# --- liveliness ---

## Puts `pet` at an action that does not end while the test watches (the clock stands still,
## so the world never steps) and lets the view walk there.
func _doing(m: Main, pet: Pet, action: String, extra := {}) -> PetView:
	pet.current = {"action": action, "remaining_s": 99999}
	pet.current.merge(extra)
	m.tick(1.0 / 30.0)
	var pv: PetView = m.house.pets[pet.uid]
	for i in 900:
		if pv.pose() != "walking":
			break
		m.tick(1.0 / 30.0)
	return pv


func test_a_trotting_dog_reaches_spot_after_spot_of_its_yard():
	var m := _main()
	var w := m.session.world
	var dog := PetSystem.add(w, "dog", "bought")
	m.tick(0.016)
	dog.current = {"action": "dog_trot_yard", "remaining_s": 99999, "room": "yard"}
	m.tick(1.0 / 30.0)
	var pv: PetView = m.house.pets[dog.uid]
	assert_true(pv.spots().size() >= 4, str(pv.spots()))
	var reached := {}
	var bounced := false
	for i in 30 * 30:
		m.tick(1.0 / 30.0)
		for j in pv.spots().size():
			if pv.position.distance_to(pv.spots()[j]) <= PetView.ARRIVED:
				reached[j] = true
		bounced = bounced or (pv.pose() == "walking" and pv.bob_offset() < -1.0)
	assert_true(reached.size() >= 4, "reached %d of %d spots" % [reached.size(), pv.spots().size()])
	assert_true(bounced, "it trots with a bounce")
	for s in pv.spots():
		assert_eq(str(m.house.layout.pos_to_cell(s).get("room", "")), "yard")
	_done(m)


func test_a_stalking_cat_keeps_to_the_walls():
	var m := _main()
	var w := m.session.world
	w.pets.clear()
	var cat := PetSystem.add(w, "cat", "bought")
	# The grown-up sits out at the gate, clear of the cat's rooms (a spot a person stands on
	# is moved off the wall; which room they pick depends on the dice, hens and all).
	var p := w.people[0]
	AutonomySystem.start(w, p, "watch_passersby", -1)
	p.current["remaining_s"] = 99999
	m.tick(0.016)
	cat.current = {"action": "cat_stalk_wall", "remaining_s": 99999, "room": "hall"}
	m.tick(1.0 / 30.0)
	var pv: PetView = m.house.pets[cat.uid]
	for i in 20 * 30:
		m.tick(1.0 / 30.0)
	assert_true(pv.spots().size() >= 3)
	for s in pv.spots():
		var c := m.house.layout.pos_to_cell(s)
		var rd: Dictionary = w.pack.rooms[str(c.room)]
		assert_true(int(c.x) == 0 or int(c.y) == 0 or int(c.x) == int(rd.w) - 1 or int(c.y) == int(rd.h) - 1, str(c))
	_done(m)


## Staying put it is never a still picture: the dog wags and breathes, the cat flicks its
## tail, the bird bobs its head, now and then one shuffles; a resting dog lies flatter and
## turns over; the cat leaps up onto the kang and back.
func test_idle_animation_runs_while_an_action_lasts():
	var m := _main()
	var w := m.session.world
	assert_true(w.add_object("bird_cage", "hall", 0, 0) >= 0)
	var dog := PetSystem.add(w, "dog", "bought")
	var cat := PetSystem.add(w, "cat", "bought")
	var bird := PetSystem.add(w, "bird", "bought")
	m.tick(0.016)
	var dv := _doing(m, dog, "dog_bark", {"room": "gate"})
	var cv := _doing(m, cat, "cat_wash", {"room": "hall"})
	var cage: int = w.objects.filter(func(o): return o.type == "bird_cage")[0].uid
	var bv := _doing(m, bird, "bird_talk", {"object_uid": cage})
	var views := [dv, cv, bv]
	var seen := [{}, {}, {}]
	var tilt := [0.0, 0.0, 0.0]
	var lift := [0.0, 0.0, 0.0]
	var at := [dv.position, cv.position, bv.position]
	var facing := [signf(dv.pose_xform().x.x), signf(cv.pose_xform().x.x), signf(bv.pose_xform().x.x)]
	var moved := false
	for i in 20 * 30:
		m.tick(1.0 / 30.0)
		for k in 3:
			var v: PetView = views[k]
			var x := v.pose_xform()
			seen[k][str(x)] = true
			tilt[k] = maxf(tilt[k], absf(x.get_rotation()))
			lift[k] = minf(lift[k], x.origin.y)
			# A step aside, or turning round where it stands.
			moved = moved or v.position.distance_to(at[k]) > 2.0 or signf(x.x.x) != float(facing[k])
	for k in 3:
		assert_true((seen[k] as Dictionary).size() > 40, "%s: %d poses in 20 s" % [views[k].pet.kind, (seen[k] as Dictionary).size()])
	assert_true(tilt[0] > 0.02, "the dog wags")
	assert_true(tilt[1] > 0.03, "the cat flicks its tail")
	assert_true(lift[2] < -1.0, "the bird bobs its head")
	assert_true(moved, "one of them shuffled or turned round in 20 s")
	# Resting: flatter, and it turns over or stretches every so often.
	var pile: int = w.objects.filter(func(o): return o.type == "woodpile")[0].uid
	var rv := _doing(m, dog, "dog_sleep", {"object_uid": pile})
	assert_true(rv.resting())
	var tallest := 0.0
	for i in 30 * 30:
		m.tick(1.0 / 30.0)
		tallest = maxf(tallest, rv.pose_xform().get_scale().y)
	assert_true(rv.turns() >= 1, "turned over in 30 s")
	assert_true(tallest < 1.0, "lies flatter than it stands")
	# Leaping onto the kang and down again.
	var kang: int = w.objects.filter(func(o): return o.type == "kang")[0].uid
	var lv := _doing(m, cat, "cat_hop_kang", {"object_uid": kang})
	var high := 0.0
	for i in 3 * 30:
		m.tick(1.0 / 30.0)
		high = minf(high, lv.bob_offset())
	assert_true(high <= -PetView.LEAP_HIGH + 1.0, str(high))
	_done(m)
