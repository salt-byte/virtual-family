class_name BalanceRun
extends RefCounted
## Headless balance runs: many households, each looked after by a conscientious caretaker,
## summarised in one Dictionary. Works for any pack; it only relies on the pack having a
## "food" stock item, medicines that `cure` its illnesses and a treat that lifts "happy".
## Reads live World fields (never `to_dict()`, whose floats are encoded for saving).

## 2026-01-01 08:00 UTC: every run starts on a morning.
const START_UNIX := 1767254400
const FOOD_STOCK := "food"
const MOOD_NEED := "happy"
const LOW_FOOD := 3
const LOW_MOOD := 30.0
## Money the caretaker keeps back before buying what someone wishes for; furniture wishes
## need this much more again.
const WISH_RESERVE := 300
const FURNITURE_RESERVE := 400
## Money the caretaker keeps back before buying another bed so a couple can have a child.
const BED_RESERVE := 1000
## A baby whose need for food is below this gets someone dragged over to feed it.
const BABY_HUNGRY := 35.0

## False: the caretaker leaves the animals alone (no strays taken, none bought for a wish,
## no medicine, no treats).
static var look_after_pets := true

## Beds the caretaker has bought since the last `run` began.
static var beds_bought := 0

## Times the caretaker sent someone out for a wish since the last `run` began.
static var sent_out := 0


## A world that is already living: one adopted person and one of each object type (the
## pack's starting furniture first, the missing types placed for free on the first spot
## `HouseSystem.can_place` accepts: rooms in pack order, then row by row; fixed types only
## come with their rooms).
static func setup(pack_id: String, seed: int) -> World:
	return setup_pack(Pack.load_dir("res://packs/" + pack_id), seed)


## `setup` for an already loaded (possibly tweaked) pack.
static func setup_pack(pack: Pack, seed: int) -> World:
	var w := World.new(pack, seed)
	w.set_time(START_UNIX, 0)
	w.command({"type": "adopt"})
	var owned := {}
	for o in w.objects:
		owned[o["type"]] = true
	for type in w.pack.object_types:
		if not owned.has(type):
			_place_first_fit(w, str(type))
	return w


## Runs `families` households (seeds seed0, seed0+1, ...) for `days` simulated days with the
## caretaker acting once per simulated hour.
static func run(pack_id: String, families: int, days: int, seed0: int) -> Dictionary:
	var money: Array[int] = []
	var alive := 0
	var married := 0
	var levels := 0.0
	var living := 0
	var messes := 0
	var deaths := {"neglect": 0, "old_age": 0}
	var seen := {}
	var bags := 0
	var max_bags_day := 0
	var tracks := {}  # livelihood id -> living people following it at the end
	var wishes := {"wish_formed": 0, "wish_granted": 0, "wish_expired": 0}
	var low := {"sad": 0, "depressed": 0}  # people who were ever sad / depressed
	var births := {"conceived": 0, "born": 0, "relative_arrived": 0}
	var gens := {}  # generation -> living people at the end
	var top_gen := 0
	var house_born_took_up := 0
	var unlocked := {}  # story id -> households where it unlocked
	var finished := {}  # story id -> households where it was played to its end
	var babies_end := 0
	var weather_hours := {}  # weather id -> hours it was the weather at the hourly look
	var season_hours := {}  # season id -> hours
	var weather_changes := 0
	var clean_rewards := 0  # times a household was paid for a clean house
	var clean_money := 0
	var weather_only := {}  # action id -> starts, for actions tied to a weather
	var pets := {"pets_arrived": 0, "pets_bought": 0, "strays_taken": 0, "pets_ran_away": 0, "pets_came_back": 0,
		"pets_fell_ill": 0, "pets_cured": 0}
	var pet_deaths := {}  # cause -> pets
	var fond_sum := 0.0
	var pets_home_end := 0
	var festivals := {}  # festival id -> times it began
	var outings := {}  # outing action id -> times someone came back from it
	var festival_actions := {}  # action id -> starts, for actions tied to a festival
	var festival_wishes := {"formed": 0, "granted": 0, "ended": 0}
	var mourned := 0
	var letters := {}  # letter kind -> letters that came
	beds_bought = 0
	sent_out = 0
	for i in families:
		var w := setup(pack_id, seed0 + i)
		var bag_size := _food_bag_size(w)
		var bags_today := 0
		var ever := {}
		for h in days * 24:
			if h % 24 == 0:
				bags_today = 0
			var before := int(w.stock.get(FOOD_STOCK, 0))
			caretake(w)
			if bag_size > 0:
				var n := (int(w.stock.get(FOOD_STOCK, 0)) - before) / bag_size
				bags += n
				bags_today += n
				max_bags_day = maxi(max_bags_day, bags_today)
			# In five-minute strides (the same steps as one hour-long advance): while a festival
			# is on, the caretaker also looks after the festival's wishes.
			for k in 12:
				w.advance(300.0)
				if w.festival != "":
					festival_round(w)
			if w.weather != "":
				weather_hours[w.weather] = int(weather_hours.get(w.weather, 0)) + 1
			if w.season != "":
				season_hours[w.season] = int(season_hours.get(w.season, 0)) + 1
			for e in w.drain_events():
				if e.type == "letter_arrived":
					letters[e.kind] = int(letters.get(e.kind, 0)) + 1
				if e.type == "weather_changed":
					weather_changes += 1
				elif e.type == "clean_reward":
					clean_rewards += 1
					clean_money += int(e.amount)
				if e.type == "festival_started":
					festivals[e.festival] = int(festivals.get(e.festival, 0)) + 1
				elif e.type == "outing_back":
					outings[e.action] = int(outings.get(e.action, 0)) + 1
				elif e.type == "mourned":
					mourned += 1
				if e.type in FESTIVAL_WISH_KEYS and str(w.pack.wishes.get(e.wish, {}).get("festival", "")) != "":
					festival_wishes[FESTIVAL_WISH_KEYS[e.type]] += 1
				if e.type == "action_started":
					seen[e.action] = true
					if not (w.pack.actions[e.action].get("festivals", []) as Array).is_empty():
						festival_actions[e.action] = int(festival_actions.get(e.action, 0)) + 1
					if not (w.pack.actions[e.action].get("weather", []) as Array).is_empty():
						weather_only[e.action] = int(weather_only.get(e.action, 0)) + 1
				elif e.type == "pet_arrived":
					pets["pets_arrived"] += 1
					pets["pets_bought" if str(e.how) == "bought" else "strays_taken"] += 1
				elif e.type == "pet_ran_away":
					pets["pets_ran_away"] += 1
				elif e.type == "pet_came_back":
					pets["pets_came_back"] += 1
				elif e.type == "pet_fell_ill":
					pets["pets_fell_ill"] += 1
				elif e.type == "pet_cured":
					pets["pets_cured"] += 1
				elif e.type == "pet_died":
					pet_deaths[e.cause] = int(pet_deaths.get(e.cause, 0)) + 1
				elif e.type == "person_died":
					deaths[e.cause] = int(deaths.get(e.cause, 0)) + 1
				elif births.has(e.type):
					births[e.type] += 1
				elif e.type == "took_up" and w.person(int(e.person)) != null and w.person(int(e.person)).generation > 0:
					house_born_took_up += 1
				elif wishes.has(e.type):
					wishes[e.type] += 1
				elif e.type == "mood_changed" and low.has(e.mood) and not ever.has("%d%s" % [e.person, e.mood]):
					ever["%d%s" % [e.person, e.mood]] = true
					low[e.mood] += 1
		money.append(w.money)
		if w.people.any(func(p: Person): return p.alive):
			alive += 1
		if w.married:
			married += 1
		for p in w.people:
			top_gen = maxi(top_gen, p.generation)
			if p.alive:
				levels += p.level
				living += 1
				tracks[p.track] = int(tracks.get(p.track, 0)) + 1
				gens[p.generation] = int(gens.get(p.generation, 0)) + 1
				if p.stage(w.pack) == "baby":
					babies_end += 1
		for sid in w.stories:
			unlocked[sid] = int(unlocked.get(sid, 0)) + 1
			if str(w.stories[sid]["stage"]) == "done":
				finished[sid] = int(finished.get(sid, 0)) + 1
		messes += w.messes.size()
		var love := PetSystem.role(w.pack, "love_need")
		for pet in w.pets:
			if pet.home():
				pets_home_end += 1
				fond_sum += float(pet.needs.get(love, 0.0))
	money.sort()
	return {
		"families": families, "alive_at_end": alive,
		"median_money": money[money.size() / 2] if not money.is_empty() else 0,
		"min_money": money.front() if not money.is_empty() else 0,
		"max_money": money.back() if not money.is_empty() else 0,
		"married": married,
		"avg_level": snappedf(levels / living, 0.01) if living > 0 else 0.0,
		"avg_messes": snappedf(float(messes) / families, 0.01) if families > 0 else 0.0,
		"deaths_neglect": int(deaths["neglect"]), "deaths_old_age": int(deaths["old_age"]),
		"distinct_actions": seen.size(),
		"food_bought_per_day": snappedf(float(bags) / (families * days), 0.01) if families * days > 0 else 0.0,
		"max_food_bought_in_a_day": max_bags_day, "livelihoods": tracks,
		"wishes_formed": wishes["wish_formed"], "wishes_granted": wishes["wish_granted"],
		"wishes_expired": wishes["wish_expired"], "people_sad": low["sad"], "people_depressed": low["depressed"], "actions_in_pack": Pack.load_dir("res://packs/" + pack_id).actions.size(),
		"pregnancies": births["conceived"], "births": births["born"], "babies_at_end": babies_end,
		"people_at_end": living, "alive_by_generation": gens, "max_generation": top_gen,
		"house_born_took_up": house_born_took_up, "relatives_arrived": births["relative_arrived"],
		"beds_bought": beds_bought, "stories_unlocked": unlocked, "stories_done": finished,
		"deaths_by_cause": deaths,
		"weather_hours": weather_hours, "season_hours": season_hours, "weather_changes": weather_changes,
		"weather_only_actions": weather_only,
		"clean_rewards": clean_rewards, "clean_reward_money": clean_money,
		"letters_by_kind": letters,
		"letters_per_family_day": snappedf(float(letters.values().reduce(func(a, b): return a + b, 0)) / (families * days), 0.01) if families * days > 0 else 0.0,
		"pets": pets, "pet_deaths_by_cause": pet_deaths, "pets_home_at_end": pets_home_end,
		"pets_avg_fondness": snappedf(fond_sum / pets_home_end, 0.1) if pets_home_end > 0 else 0.0,
		"festivals_seen": festivals, "festival_actions": festival_actions, "festival_wishes": festival_wishes,
		"outings_back": outings, "outings_sent_by_caretaker": sent_out, "mourned": mourned,
	}


## The caretaker's hourly round: accept any proposal and any visitor's gift, sell the extras
## in the keepsake box, keep food stocked, give the right
## medicine to the sick and a treat to the gloomy, and grant the wishes it can: a wished-for
## shop item when the money stays above WISH_RESERVE, a praise when there is something to
## praise, a wished-for piece of furniture with FURNITURE_RESERVE more in hand. Rooms are
## never built for a wish. A body wish it meets by dragging the person to a fix the player
## leads (`_lead_to_fix`: a bath); so too a need the pack's asks name once its meter is below
## the ask's line (`_mind_meters`: a bath, a nap), whether or not the ask is up at that moment.
## Otherwise it drags only to feed a baby, never scolds, and furnishes only for a wish.
static func caretake(w: World) -> void:
	if w.phase != "living":
		return
	if not w.proposals.is_empty():
		w.command({"type": "answer_proposal", "id": w.proposals[0]["id"], "accept": true})
	for sid in StorySystem.visitors(w):
		w.command({"type": "receive_visitor", "story": sid})
	if CollectibleSystem.keeps(w.pack):
		w.command({"type": "sell_collectible"})
	var food := _first_item(w, func(it): return (it["stock"] as Dictionary).has(FOOD_STOCK))
	if food != "" and int(w.stock.get(FOOD_STOCK, 0)) < LOW_FOOD:
		w.command({"type": "buy", "item": food})
	for p in w.people:
		if not p.alive:
			continue
		if p.illness != "":
			var ill := p.illness
			_give(w, p, _first_item(w, func(it): return it["cures"] == ill))
		if float(p.needs.get(MOOD_NEED, 100.0)) < LOW_MOOD:
			_give(w, p, _first_item(w, func(it): return it["cures"] == "" and (it["stock"] as Dictionary).is_empty() \
					and (it["needs"] as Dictionary).has(MOOD_NEED)))
		_grant_wish(w, p)
		_mind_meters(w, p)
	_care_for_babies(w)
	_buy_bed_if_needed(w)
	care_for_pets(w)


## The caretaker's round for animals: takes in a stray while fewer than two live at home, doses a sick pet with the first item
## that cures pets, gives a pet the item it wishes for (money above WISH_RESERVE), and keeps
## two of each stock that the household's care actions for its pets use up, when the shop
## sells it.
static func care_for_pets(w: World) -> void:
	if not look_after_pets or (w.pets.is_empty() and w.pet_offer.is_empty()):
		return
	if not w.pet_offer.is_empty() and PetSystem.at_home(w) < 2:
		w.command({"type": "answer_stray", "accept": true})
	var cure := _first_item(w, func(it): return bool((it["pet"] as Dictionary).get("cures", false)))
	var stocks := {}
	for pet in w.pets:
		if not pet.home():
			continue
		if pet.sick and cure != "" and w.command({"type": "buy", "item": cure}).ok:
			w.command({"type": "use_item", "item": cure, "pet": pet.uid})
		var item := str(PetSystem.wish_of(w, pet).get("item", ""))
		if item != "" and w.money >= int(w.pack.items[item]["price"]) + WISH_RESERVE and w.command({"type": "buy", "item": item}).ok:
			w.command({"type": "use_item", "item": item, "pet": pet.uid})
		for id in w.pack.actions:
			var a: Dictionary = w.pack.actions[id]
			if not (a["pet"] as Dictionary).is_empty() and PetSystem.suits(a, pet):
				for s in a["consumes"]:
					stocks[s] = true
	for s in stocks:
		if s == FOOD_STOCK or int(w.stock.get(s, 0)) >= 2:
			continue
		var it := _first_item(w, func(x): return (x["stock"] as Dictionary).has(s))
		if it != "":
			w.command({"type": "buy", "item": it})


## Wish events -> the key `run` counts festival wishes under.
const FESTIVAL_WISH_KEYS := {"wish_formed": "formed", "wish_granted": "granted", "wish_expired": "ended"}


## A hungry baby nobody is looking after gets the first grown-up who is free to come over.
static func _care_for_babies(w: World) -> void:
	for b in w.people:
		if not b.alive or b.stage(w.pack) != "baby" or float(b.needs.get("fed", 100.0)) >= BABY_HUNGRY:
			continue
		if AutonomySystem.target_claimed(w, b.uid, "person", null):
			continue
		for p in w.people:
			if p.alive and p.stage(w.pack) in ["adult", "elder"] and int(p.current.get("target_uid", -1)) < 0:
				if w.command({"type": "drag", "person": p.uid, "tend": b.uid}).ok:
					break


## With births on, a couple that could have a child but has no place for one gets another
## bed once the money stays above BED_RESERVE.
static func _buy_bed_if_needed(w: World) -> void:
	if not BirthSystem.blocked(w):
		return
	var beds: Array = w.pack.cfg("births").get("beds", [])
	var type := str(beds[0])
	if w.money < int(w.pack.object_types[type]["price"]) + BED_RESERVE:
		return
	for room in w.rooms_built:
		if bool(w.pack.rooms[room].get("outdoor", false)) != bool(w.pack.object_types[type].get("outdoor", false)):
			continue
		var r: Dictionary = w.pack.rooms[room]
		for y in int(r["h"]):
			for x in int(r["w"]):
				if w.command({"type": "place", "object_type": type, "room": room, "x": x, "y": y}).ok:
					beds_bought += 1
					return


## While a festival is on (every five minutes): grants the festival's wishes the caretaker
## can, as `_grant_wish` does.
static func festival_round(w: World) -> void:
	if w.phase != "living":
		return
	for p in w.people:
		if p.alive and str(WishSystem.current(w, p).get("festival", "")) != "":
			_grant_wish(w, p)


static func _grant_wish(w: World, p: Person) -> void:
	if not p.alive:
		return
	var wish := WishSystem.current(w, p)
	match str(wish.get("kind", "")):
		"do":
			# Send them out for an outing; for anything else, buy what it uses up.
			for id in wish["actions"]:
				var a: Dictionary = w.pack.actions[id]
				if OutingSystem.sendable(w.pack, a):
					if str(p.current.get("action", "")) != str(id) and w.command({"type": "go_out", "person": p.uid, "action": id}).ok:
						sent_out += 1
					return
				for s in a["consumes"]:
					if int(w.stock.get(s, 0)) < int(a["consumes"][s]):
						var it := _first_item(w, func(x): return (x["stock"] as Dictionary).has(s))
						if it != "" and w.money >= int(w.pack.items[it]["price"]) + WISH_RESERVE:
							w.command({"type": "buy", "item": it})
		"item":
			var item := str(wish["item"])
			if w.money >= int(w.pack.items[item]["price"]) + WISH_RESERVE:
				_give(w, p, item)
		"praise":
			w.command({"type": "praise", "person": p.uid})
		"pet":
			var kind := str(wish["pet"])
			if look_after_pets and w.money >= int(w.pack.pets[kind].get("price", 0)) + WISH_RESERVE:
				w.command({"type": "buy_pet", "kind": kind})
		"need":
			_lead_to_fix(w, p, str(wish["need"]))
		"object":
			var type := str(wish["object"])
			if w.money >= int(w.pack.object_types[type]["price"]) + FURNITURE_RESERVE:
				for room in w.rooms_built:
					var r: Dictionary = w.pack.rooms[room]
					for y in int(r["h"]):
						for x in int(r["w"]):
							if w.command({"type": "place", "object_type": type, "room": room, "x": x, "y": y}).ok:
								return


## A body wish the person cannot fix well alone: drags them to the first object where a
## player-led action (`AutonomySystem.player_led`) raises `need` (a bath for a dirty one, a
## rest on the bed for a tired one). Leaves alone someone already doing something that
## raises it (asleep, say).
## What the bar's meters show the player once an hour: a need the pack's asks name, below the
## ask's line, is led to a fix the player leads (packs without asks: nothing).
static func _mind_meters(w: World, p: Person) -> void:
	if not "asks" in w.pack or OutingSystem.away(w, p):
		return
	for id in w.pack.get("asks"):
		var e: Dictionary = w.pack.get("asks")[id]
		if str(e["kind"]) == "need" and float(p.needs.get(str(e["need"]), 100.0)) < float(e["below"]):
			_lead_to_fix(w, p, str(e["need"]))
			return


static func _lead_to_fix(w: World, p: Person, need: String) -> void:
	if not p.current.is_empty() and float((w.pack.actions[p.current["action"]]["needs"] as Dictionary).get(need, 0.0)) > 0.0:
		return
	for id in w.pack.actions:
		var a: Dictionary = w.pack.actions[id]
		if str(a["object"]) == "" or not AutonomySystem.player_led(a) or float((a["needs"] as Dictionary).get(need, 0.0)) <= 0.0:
			continue
		for o in w.objects:
			if o.type == a["object"] and AutonomySystem.can_do(w, p, id, int(o.uid)) == "":
				if w.command({"type": "drag", "person": p.uid, "object": int(o.uid)}).ok:
					return


## Food units one purchase of the caretaker's food item adds (0 when the pack has none).
static func _food_bag_size(w: World) -> int:
	var food := _first_item(w, func(it): return (it["stock"] as Dictionary).has(FOOD_STOCK))
	return int(w.pack.items[food]["stock"][FOOD_STOCK]) if food != "" else 0


## Buys one of `item` and uses it on `p`, when there is such an item and the money for it.
static func _give(w: World, p: Person, item: String) -> void:
	if item != "" and w.command({"type": "buy", "item": item}).ok:
		w.command({"type": "use_item", "item": item, "person": p.uid})


## Id of the first pack item (pack order) for which `pred` holds, else "".
static func _first_item(w: World, pred: Callable) -> String:
	for id in w.pack.items:
		if pred.call(w.pack.items[id]):
			return str(id)
	return ""


static func _place_first_fit(w: World, type: String) -> void:
	if HouseSystem.is_fixed(w, type) or bool(w.pack.object_types[type].get("keepsake", false)):
		return  # fixed furniture comes with its room, a keepsake with its story
	for room in w.rooms_built:
		var r: Dictionary = w.pack.rooms[room]
		for y in int(r["h"]):
			for x in int(r["w"]):
				if w.add_object(type, room, x, y) >= 0:
					return


## A realistic household for timing: `setup`'s adopted adult, a spouse and two children
## (made like any adopted person), with food in the larder.
static func family_of_four(pack_id: String, seed: int) -> World:
	var w := setup(pack_id, seed)
	var spouse := FamilySystem.make_person(w, w.pack.cfg("adopt_age"))
	w.add_person(spouse)
	w.married = true
	for i in 2:
		w.add_person(FamilySystem.make_person(w, [6, 12]))
	w.stock[FOOD_STOCK] = 20
	return w
