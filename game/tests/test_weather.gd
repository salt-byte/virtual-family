extends TestCase
## Seasons and weather (qijia's `seasons`; see `WeatherSystem`).

## 2026-01-01 12:00 UTC: a multiple of qijia's 4-hour year, so the first hour is spring.
const YEAR_START := 1767268800


func _w(hour_into_year := 0.0) -> World:
	var w := TestKit.world("qijia")
	w.set_time(YEAR_START + int(hour_into_year * 3600.0), 0)
	return w


## Sets the weather and marks this slot as rolled, so the next steps keep it.
func _set_weather(w: World, weather: String) -> void:
	w.weather = weather
	w.weather_slot = w.now / (int(w.pack.cfg("seasons")["change_min"]) * 60)
	if bool(WeatherSystem.weather_entry(w.pack, weather).get("wet", false)):
		w.wet_until = w.now + 5400


func test_four_seasons_in_four_hours():
	var p := Pack.load_dir("res://packs/qijia")
	var got: Array = []
	for q in 4:
		got.append(WeatherSystem.season_at(p, YEAR_START + q * 3600 + 1800)["id"])
	assert_eq(got, ["spring", "summer", "autumn", "winter"])
	assert_eq(WeatherSystem.season_at(p, YEAR_START + 4 * 3600)["id"], "spring")


func test_smoke_pack_has_no_seasons():
	var w := TestKit.world("_smoke"); TestKit.adult(w)
	assert_true(not WeatherSystem.enabled(w.pack))
	w.advance(3600)
	assert_eq(w.weather, ""); assert_eq(w.season, ""); assert_eq(w.weather_slot, -1)
	assert_true(not w.to_dict().has("weather"))


func test_weather_is_rolled_once_per_slot_and_is_the_same_for_the_same_seed():
	var a := _w(); var b := _w()
	TestKit.adult(a); TestKit.adult(b)
	var seq_a: Array = []; var seq_b: Array = []
	for i in 16:
		a.advance(900); b.advance(900)
		seq_a.append(a.weather); seq_b.append(b.weather)
	assert_eq(seq_a, seq_b)
	assert_true(seq_a.all(func(x): return x != ""))


func test_catch_up_gives_the_same_weather_as_playing_through():
	var a := _w(); var b := _w()
	TestKit.adult(a); TestKit.adult(b)
	a.catch_up(3 * 3600)
	b.offline = true; b.advance(3 * 3600); b.offline = false; b.drain_events()
	assert_eq(a.weather, b.weather)
	assert_eq(a.to_dict(), b.to_dict())


func test_each_season_draws_from_its_own_weather():
	var w := _w(); TestKit.adult(w)
	var by_season := {}
	for i in 4 * 4 * 6:  # six years of 15-minute slots
		w.offline = true
		w.advance(900)
		var s: Dictionary = by_season.get(w.season, {})
		s[w.weather] = int(s.get(w.weather, 0)) + 1
		by_season[w.season] = s
	assert_true(not by_season["spring"].has("snowfall") and not by_season["spring"].has("thunderstorm"), str(by_season))
	assert_true(not by_season["winter"].has("drizzle") and not by_season["winter"].has("thunderstorm"), str(by_season))
	assert_true(by_season["winter"].has("snowfall"), str(by_season))
	assert_true(by_season["summer"].has("thunderstorm"), str(by_season))
	assert_true(by_season["spring"].get("drizzle", 0) > by_season["autumn"].get("drizzle", 0), str(by_season))


func test_rain_keeps_people_in():
	var w := _w(); var p := TestKit.adult(w)
	var a: Dictionary = w.pack.actions["pound_laundry"]  # at the river, outside the house
	var b: Dictionary = w.pack.actions["fan_in_shade"]  # in the yard
	var c: Dictionary = w.pack.actions["mend_clothes"]  # indoors
	_set_weather(w, "clear")
	var dry := [WeatherSystem.action_factor(w, a, 2), WeatherSystem.action_factor(w, b, 1), WeatherSystem.action_factor(w, c, 0)]
	_set_weather(w, "drizzle")
	assert_eq(WeatherSystem.place_kind(w.pack, a), 2)
	assert_eq(WeatherSystem.place_kind(w.pack, b), 1)
	assert_eq(WeatherSystem.place_kind(w.pack, c), 0)
	assert_true(WeatherSystem.action_factor(w, a, 2) < dry[0] * 0.3)
	assert_true(WeatherSystem.action_factor(w, b, 1) < dry[1] * 0.5)
	assert_eq(WeatherSystem.action_factor(w, c, 0), dry[2])
	assert_true(AutonomySystem._score(w, p, a) < AutonomySystem._score(w, p, c))


func test_rain_only_things_wait_for_rain():
	var w := _w(); var p := TestKit.adult(w)
	_set_weather(w, "clear")
	assert_eq(AutonomySystem.can_do(w, p, "watch_rain_under_eaves", -1), "weather")
	assert_true(AutonomySystem.candidates(w, p).all(func(c): return c.action != "watch_rain_under_eaves"))
	_set_weather(w, "drizzle")
	assert_eq(AutonomySystem.can_do(w, p, "watch_rain_under_eaves", -1), "")
	assert_true(AutonomySystem.candidates(w, p).any(func(c): return c.action == "watch_rain_under_eaves"))


func test_wet_ground_needs_no_watering_and_dries_later():
	var w := _w(); var p := TestKit.adult(w)
	w.add_object("garden", "yard", 8, 0)
	w.set_time(YEAR_START + 4 * 3600 * 10 + 4 * 3600, 0)  # spring again, 16:00 local
	_set_weather(w, "drizzle")
	assert_eq(AutonomySystem.can_do(w, p, "water_garden", -1), "weather")
	_set_weather(w, "clear")
	w.wet_until = w.now + 60
	assert_eq(AutonomySystem.can_do(w, p, "water_garden", -1), "weather")
	w.wet_until = w.now
	assert_eq(AutonomySystem.can_do(w, p, "water_garden", -1), "")


func test_rain_leaves_mud_indoors():
	var w := _w(); TestKit.adult(w)
	_set_weather(w, "drizzle")
	w.offline = true
	w.pack.config["seasons"]["persist"] = 1.0
	w.advance(4 * 3600)
	var mud := w.messes.filter(func(m): return m.type == "mud")
	assert_true(mud.size() > 0 or w.stats["mess_cleaned"] > 0)
	for m in mud:
		assert_true(not bool(w.pack.rooms[m.room]["outdoor"]))


func test_snow_covers_the_yard_and_melts_in_spring():
	var w := _w(3.0); TestKit.adult(w)
	_set_weather(w, "snowfall")
	w.pack.config["seasons"]["persist"] = 1.0
	w.advance(10)  # first step: the season is noted
	for i in 30:
		MessSystem.spawn(w, "snow_cover")
	var snow := w.messes.filter(func(m): return m.type == "snow_cover")
	assert_true(snow.size() >= 20)
	for m in snow:
		assert_true(bool(w.pack.rooms[m.room]["outdoor"]) and not bool(w.pack.rooms[m.room]["outside"]))
	w.offline = true
	w.advance(3600)  # into spring
	assert_eq(w.season, "spring")
	assert_eq(w.messes.filter(func(m): return m.type == "snow_cover").size(), 0)


func test_snow_falls_into_the_yard_by_itself():
	var w := _w(3.0)
	_set_weather(w, "snowfall")
	w.pack.config["seasons"]["persist"] = 1.0
	w.advance(3500)
	assert_true(w.messes.any(func(m): return m.type == "snow_cover"))


func test_autumn_drops_leaves():
	var w := _w(2.0)
	w.pack.config["seasons"]["list"][2]["messes"]["leaves"] = 600  # plenty, so an hour shows some
	w.advance(3500)
	assert_eq(w.season, "autumn")
	assert_true(w.messes.any(func(m): return m.type == "leaves"))


func test_children_build_a_snowman_only_in_snow():
	var w := _w(3.0); var kid := TestKit.adult(w, 8.0)
	_set_weather(w, "clear")
	assert_eq(AutonomySystem.can_do(w, kid, "build_snowman", -1), "weather")
	_set_weather(w, "snowfall")
	assert_eq(AutonomySystem.can_do(w, kid, "build_snowman", -1), "")
	var grown := TestKit.adult(w)
	assert_eq(AutonomySystem.can_do(w, grown, "build_snowman", -1), "stage")


func test_spring_greens_grow_faster_and_winter_has_none():
	for q in [[0.5, 2], [1.5, 1], [3.5, 0]]:
		var w := _w(q[0]); var p := TestKit.adult(w)
		w.add_object("garden", "yard", 8, 0)
		_set_weather(w, "clear")
		AutonomySystem.start(w, p, "pick_greens", -1)
		w.advance(float(AutonomySystem.duration_s(w, w.pack.actions["pick_greens"])))
		assert_eq(int(w.stock.get("greens", 0)), q[1], "hour %s" % q[0])


func test_winter_draws_people_to_the_stove_and_kang():
	var w := _w(3.5); var p := TestKit.adult(w)
	_set_weather(w, "clear")
	var heat: Dictionary = w.pack.actions["heat_kang"]
	var fan: Dictionary = w.pack.actions["fan_in_shade"]
	var winter := [WeatherSystem.action_factor(w, heat, 0), WeatherSystem.action_factor(w, fan, 1)]
	var s := _w(1.5); _set_weather(s, "clear")
	assert_true(winter[0] > WeatherSystem.action_factor(s, heat, 0) * 5.0)
	assert_true(winter[1] < WeatherSystem.action_factor(s, fan, 1) * 0.1)


func test_weather_survives_a_save_and_old_saves_roll_anew():
	var w := _w(); TestKit.adult(w)
	w.advance(60)
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var back := World.from_dict(w.pack, d)
	assert_eq(back.weather, w.weather); assert_eq(back.weather_slot, w.weather_slot)
	assert_eq(back.to_dict(), w.to_dict())
	d.erase("weather")
	var old := World.from_dict(w.pack, d)
	assert_true(old != null)
	assert_eq(old.weather, "")
	old.advance(10)
	assert_true(old.weather != "")


func test_validator_checks_seasons():
	var p := Pack.load_dir("res://packs/qijia")
	p.config["seasons"]["list"][0]["weather"]["hail"] = 2
	p.actions["build_snowman"]["weather"] = ["blizzard"]
	p.mess_types["snow_cover"]["seasons"] = ["monsoon"]
	var errs := PackValidator.validate(p)
	assert_true(errs.has("pack.json: qijia: seasons.list spring: weather 'hail' must be a weather id with a weight above 0"), str(errs))
	assert_true(errs.has("actions.json: build_snowman: weather: 'blizzard' is not in the pack's seasons"), str(errs))
	assert_true(errs.has("messes.json: snow_cover: seasons: 'monsoon' is not in the pack's seasons"), str(errs))
