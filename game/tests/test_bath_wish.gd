extends TestCase
## "I just gave him a bath and he still says he wants one": a bath the player gives meets the
## bath wish and the bath ask the moment it ends (thank-you and all), the bubble and the
## wish line say nothing of it while they sit in the water, and neither comes back soon.


## One grown-up of a fresh qijia family, every need at 90, food in the larder; no chance
## illness, no mood wishes and no asks by chance.
func _home(seed := 1) -> World:
	var w := BalanceRun.setup("qijia", seed)
	w.pack.config["illness_daily_chance"] = 0.0
	w.pack.config["wish_chance_per_hour"] = 0.0
	w.pack.config["ask_chance_per_hour"] = 0.0
	var p := w.people[0]
	p.current = {}
	p.wish = {}
	p.ask = {}
	for n in w.pack.needs:
		p.needs[n] = 90.0
	w.stock["food"] = 50
	w.drain_events()
	return w


func _object(w: World, type: String) -> int:
	for o in w.objects:
		if o.type == type:
			return int(o.uid)
	if type == "well_head":
		HouseSystem.place_props(w, "well", true)
	else:
		for room in w.rooms_built:
			var r: Dictionary = w.pack.rooms[room]
			for y in int(r["h"]):
				for x in int(r["w"]):
					var uid := w.add_object(type, room, x, y)
					if uid >= 0:
						return uid
	for o in w.objects:
		if o.type == type:
			return int(o.uid)
	return -1


## Lets `p` get dirty on their own until they hold the bath wish and the bath ask.
func _dirty(w: World, p: Person) -> void:
	p.needs["clean"] = 20.0
	for i in 60:
		if not p.wish.is_empty() and not p.ask.is_empty():
			break
		w.advance(float(w.step_s))
	assert_eq(str(p.wish.get("id", "")), "want_bath")
	assert_eq(str(p.ask.get("id", "")), "grubby")
	w.drain_events()


func _types(events: Array) -> Array:
	return events.map(func(e): return str(e.type) + ":" + str(e.get("wish", e.get("ask", e.get("action", "")))))


## Steps until `p` is no longer doing `action`; returns every event on the way, and fails
## the test if the wish was granted (or shown) before the bath ended.
func _bathe(w: World, p: Person, action: String) -> Array:
	var s := ViewStrings.new(w.pack)
	var seen: Array = []
	for i in 40:
		if p.current.is_empty() or str(p.current["action"]) != action:
			break
		assert_eq(s.wish_text(p, w), "", "no wish line from inside the bath")
		assert_true(NeedBubble.of(w, p).is_empty(), "no bubble from inside the bath: " + str(NeedBubble.of(w, p)))
		w.advance(float(w.step_s))
		var evs := _types(w.drain_events())
		if not evs.has("action_finished:" + action):
			assert_true(not evs.has("wish_granted:want_bath"), "granted midway, before the bath ended")
		seen.append_array(evs)
	return seen


func _gives_a_bath(object_type: String, action: String) -> void:
	var w := _home()
	var p := w.people[0]
	_dirty(w, p)
	assert_true(not p.current.is_empty(), "busy with something else when dragged")
	var r := w.command({"type": "drag", "person": p.uid, "object": _object(w, object_type)})
	assert_true(r.ok, str(r))
	assert_eq(str(r.action), action)
	assert_true(_types(w.drain_events()).has("ask_helped:grubby"), "the drag meets the ask")
	assert_true(p.ask.is_empty())
	var evs := _bathe(w, p, action)
	var done := evs.find("action_finished:" + action)
	assert_true(done >= 0, str(evs))
	assert_true(evs.find("wish_granted:want_bath") > done, "granted the moment the bath ends: " + str(evs))
	assert_true(p.wish.is_empty())
	assert_true(p.thanking(w.now), "the thank-you")
	assert_true(float(p.needs["clean"]) > 95.0, str(p.needs["clean"]))
	var s := ViewStrings.new(w.pack)
	assert_eq(s.wish_text(p, w), "")
	assert_true(NeedBubble.of(w, p).is_empty())
	# Neither comes back for a good while: two hours of an ordinary day.
	for i in 2 * 3600 / w.step_s:
		w.advance(float(w.step_s))
		var later := _types(w.drain_events())
		assert_true(not later.has("wish_formed:want_bath") and not later.has("ask_formed:grubby"), str(later))
		if not p.wish.is_empty() and str(p.wish["id"]) == "want_bath":
			break


func test_a_bath_in_the_tub_grants_the_wish_when_it_ends():
	_gives_a_bath("washtub", "bathe_in_tub")


func test_a_bath_at_the_well_grants_the_wish_when_it_ends():
	_gives_a_bath("well_head", "bathe_at_well")


func test_an_interrupted_bath_keeps_the_wish_and_shows_it_again():
	var w := _home()
	var p := w.people[0]
	_dirty(w, p)
	assert_true(w.command({"type": "drag", "person": p.uid, "object": _object(w, "washtub")}).ok)
	w.advance(float(w.step_s))
	var r := w.command({"type": "drag", "person": p.uid, "object": _object(w, "stool")})
	assert_true(r.ok, str(r))
	assert_true(not str(p.current.get("action", "")).begins_with("bathe_"))
	assert_true(not _types(w.drain_events()).has("wish_granted:want_bath"))
	assert_eq(str(p.wish.get("id", "")), "want_bath")
	w.advance(10.0)  # past the ask's thank-you
	var s := ViewStrings.new(w.pack)
	assert_eq(s.wish_text(p, w), "身上黏糊糊，想洗个澡")
	assert_eq(str(NeedBubble.of(w, p).get("text", "")), "身上黏糊糊，想洗个澡")


func test_a_bath_while_they_see_to_the_ask_themselves_still_meets_it():
	var w := _home()
	var p := w.people[0]
	_dirty(w, p)
	# The 75 seconds ran out: they mean to see to it themselves now.
	for i in 30:
		if str(p.ask.get("phase", "")) == "self":
			break
		w.advance(float(w.step_s))
	assert_eq(str(p.ask.get("phase", "")), "self")
	w.drain_events()
	assert_true(w.command({"type": "drag", "person": p.uid, "object": _object(w, "well_head")}).ok)
	assert_true(_types(w.drain_events()).has("ask_helped:grubby"))
	assert_true(p.ask.is_empty())
	var evs := _bathe(w, p, "bathe_at_well")
	assert_true(evs.has("wish_granted:want_bath"), str(evs))


func test_a_bath_after_the_ask_lapsed_still_grants_the_wish():
	var w := _home()
	var p := w.people[0]
	_dirty(w, p)
	p.ask = {"id": "grubby", "phase": "self", "until": w.now}
	w.advance(float(w.step_s))
	assert_true(p.ask.is_empty(), "the ask went unanswered")
	assert_true(p.ask_again.has("grubby"))
	w.drain_events()
	assert_true(w.command({"type": "drag", "person": p.uid, "object": _object(w, "washtub")}).ok)
	var evs := _bathe(w, p, "bathe_in_tub")
	assert_true(evs.has("wish_granted:want_bath"), str(evs))
	assert_true(p.thanking(w.now))


func test_no_ask_or_wish_for_a_bath_forms_inside_one():
	var w := _home()
	var p := w.people[0]
	p.needs["clean"] = 3.0
	p.ask_last_t = 0
	# Dropped in the tub just before the look at body wishes (every `need_wish_check_min`)
	# and with nothing keeping an ask away: the old code formed both mid-bath.
	var look := int(w.pack.cfg("need_wish_check_min")) * 60
	while (w.now + w.step_s) % look != 0:
		w.advance(float(w.step_s))
	p.wish = {}
	p.ask = {}
	w.drain_events()
	assert_true(w.command({"type": "drag", "person": p.uid, "object": _object(w, "washtub")}).ok)
	var evs := _bathe(w, p, "bathe_in_tub")
	assert_true(not evs.has("wish_formed:want_bath"), str(evs))
	assert_true(not evs.has("ask_formed:grubby"), str(evs))
	assert_true(float(p.needs["clean"]) > 80.0)


func test_a_led_fix_meets_the_wish_even_short_of_its_line():
	var w := _home()
	var p := w.people[0]
	w.pack.actions["bathe_at_well"]["needs"]["clean"] = 30.0  # a poor wash
	p.needs["clean"] = 10.0
	p.wish = {"id": "want_bath", "expires_at": w.now + 3600}
	assert_true(w.command({"type": "drag", "person": p.uid, "object": _object(w, "well_head")}).ok)
	var evs := _bathe(w, p, "bathe_at_well")
	assert_true(float(p.needs["clean"]) < 75.0, str(p.needs["clean"]))
	assert_true(evs.has("wish_granted:want_bath"), str(evs))
	# Of their own accord, the same short wash does not.
	var v := _home()
	var q := v.people[0]
	v.pack.actions["change_clothes"]["needs"]["clean"] = 10.0
	q.needs["clean"] = 10.0
	q.wish = {"id": "want_bath", "expires_at": v.now + 3600}
	AutonomySystem.start(v, q, "change_clothes", _object(v, "clothesline"))
	v.drain_events()
	for i in 20:
		if q.current.is_empty():
			break
		v.advance(float(v.step_s))
	assert_true(not _types(v.drain_events()).has("wish_granted:want_bath"))
	assert_eq(str(q.wish.get("id", "")), "want_bath")


func test_clean_clothes_from_the_shop_grant_the_wish_at_once():
	var w := _home()
	var p := w.people[0]
	p.needs["clean"] = 34.0
	p.wish = {"id": "want_bath", "expires_at": w.now + 3600}
	w.money = 100
	assert_true(w.command({"type": "buy", "item": "spare_clothes"}).ok)
	w.drain_events()
	assert_true(w.command({"type": "use_item", "person": p.uid, "item": "spare_clothes"}).ok)
	assert_true(float(p.needs["clean"]) >= 75.0)
	assert_true(_types(w.drain_events()).has("wish_granted:want_bath"))
	assert_true(p.wish.is_empty() and p.thanking(w.now))
