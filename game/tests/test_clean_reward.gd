extends TestCase
## A clean house pays (qijia's `clean_reward`; see `MessSystem.clean`).


func _w() -> World:
	var w := TestKit.world("qijia")
	w.money = 0
	return w


func test_cleaning_the_last_mess_pays_once_a_day():
	var w := _w(); var p := TestKit.adult(w)
	var a := MessSystem.spawn(w, "dirt"); var b := MessSystem.spawn(w, "dirt")
	MessSystem.clean(w, a, p.uid)
	assert_eq(w.money, 0, "one mess still left")
	w.drain_events()
	MessSystem.clean(w, b, p.uid)
	assert_eq(w.money, 15)
	var ev := w.drain_events().filter(func(e): return e.type == "clean_reward")
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0].person), p.uid); assert_eq(int(ev[0].amount), 15)
	# Messy and clean again the same day: no second pay.
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"), p.uid)
	assert_eq(w.money, 15)
	# The next local day pays again.
	w.set_time(w.now + 86400, 0)
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"), p.uid)
	assert_eq(w.money, 30)


func test_the_day_follows_the_local_clock():
	var w := _w(); TestKit.adult(w)
	w.set_time(1767312000 - 600, 0)  # 23:50 UTC
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"))
	assert_eq(w.money, 15)
	w.set_time(1767312000 + 600, 0)  # 00:10 the next day
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"))
	assert_eq(w.money, 30)
	w.set_time(1767312000 + 1200, 3600)  # 01:20 local the same day
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"))
	assert_eq(w.money, 30)


func test_people_sweeping_on_their_own_get_paid():
	var w := _w(); var p := TestKit.adult(w)
	MessSystem.spawn(w, "dirt")
	AutonomySystem.start(w, p, "sweep", -1)
	w.advance(float(AutonomySystem.duration_s(w, w.pack.actions["sweep"])))
	assert_eq(w.messes.size(), 0)
	assert_true(w.drain_events().any(func(e): return e.type == "clean_reward" and e.person == p.uid))


func test_smoke_pack_pays_nothing():
	var w := TestKit.world(); TestKit.adult(w); w.money = 0
	MessSystem.clean(w, MessSystem.spawn(w, "trash"))
	assert_eq(w.money, 0)
	assert_eq(w.clean_paid_day, -1)
	assert_true(not w.to_dict().has("clean_paid_day"))


func test_the_paid_day_survives_a_save_and_old_saves_pay_again():
	var w := _w(); TestKit.adult(w)
	MessSystem.clean(w, MessSystem.spawn(w, "dirt"))
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, d)
	assert_eq(back.clean_paid_day, w.clean_paid_day)
	MessSystem.clean(back, MessSystem.spawn(back, "dirt"))
	assert_eq(back.money, 15)
	d.erase("clean_paid_day")
	var old := World.from_dict(w.pack, d)
	assert_true(old != null)
	MessSystem.clean(old, MessSystem.spawn(old, "dirt"))
	assert_eq(old.money, 30)


func test_validator_checks_the_amount():
	var p := Pack.load_dir("res://packs/qijia")
	p.config["clean_reward"] = {"amount": -3}
	assert_true(PackValidator.validate(p).any(func(e): return e.begins_with("pack.json: qijia: clean_reward")))
