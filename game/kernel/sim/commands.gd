class_name Commands
extends RefCounted
## Player commands: the only way the view layer acts on the sim. Every handler is
## `Callable(world, cmd) -> {ok: bool, error: String, ...}`; later tasks register more here.

## Seconds after an action ends during which it can still be praised or scolded.
const JUDGE_WINDOW_S := 60
const HABIT_MIN := 0.25
const HABIT_MAX := 3.0

static var handlers: Dictionary = {
	"drag": Commands._drag,
	"praise": Commands._praise,
	"scold": Commands._scold,
	"buy": Commands._buy,
	"use_item": Commands._use_item,
	"place": HouseSystem.place,
	"move": HouseSystem.move,
	"sell_object": HouseSystem.sell,
	"build_room": HouseSystem.build_room,
	"adopt": FamilySystem.adopt,
	"reroll": FamilySystem.reroll,
	"answer_proposal": FamilySystem.answer_proposal,
	"change_track": LivelihoodSystem.change_track,
	"receive_visitor": StorySystem.receive_visitor,
	"sell_collectible": CollectibleSystem.sell,
	"buy_pet": PetSystem.buy,
	"answer_stray": PetSystem.answer_stray,
	"sell_pet": LivestockSystem.sell,
	"answer_buyer": LivestockSystem.answer_buyer,
	"go_out": OutingSystem.go_out,
	"read_letter": LetterSystem.read,
	"answer_letter": LetterSystem.answer,
	"buy_service": ServiceSystem.buy,
	"buy_secondhand": MarketSystem.buy_used,
	"open_ticket": ServiceSystem.open_ticket,
	"dismiss_candidate": ServiceSystem.dismiss_candidate,
}


static func fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func success(extra := {}) -> Dictionary:
	var r := {"ok": true, "error": ""}
	r.merge(extra)
	return r


static func _drag(world: World, cmd: Dictionary) -> Dictionary:
	var result := _try_drag(world, cmd)
	# Dropping a sick, idle person shows their symptom, whether or not the drag worked.
	var p := world.person(int(cmd.get("person", -1)))
	if p != null:
		# The player brought them to a fix the player leads: it pays in full (see
		# `AutonomySystem.self_factor`).
		if result.ok and not p.current.is_empty() \
				and AutonomySystem.player_led(world.pack.actions[p.current["action"]]):
			p.current["led"] = true
		IllnessSystem.show_symptom(world, p)
		if result.ok:
			PetSystem.notice(world, "dragged", p)
	return result


static func _try_drag(world: World, cmd: Dictionary) -> Dictionary:
	var p := world.person(int(cmd.get("person", -1)))
	if p == null:
		return fail("no_person")
	if OutingSystem.away(world, p):
		return fail("away")
	if cmd.has("mess"):
		return _drag_to_mess(world, p, int(cmd["mess"]))
	if cmd.has("collectible"):
		return _drag_to_collectible(world, p, int(cmd["collectible"]))
	if cmd.has("story"):
		return _drag_to_story(world, p, str(cmd["story"]))
	if cmd.has("tend"):
		return _drag_to_baby(world, p, int(cmd["tend"]))
	if cmd.has("treat"):
		return _drag_to_patient(world, p, int(cmd["treat"]))
	if cmd.has("pet"):
		return _drag_to_pet(world, p, int(cmd["pet"]))
	var object_uid := int(cmd.get("object", -1))
	var o := world.object(object_uid)
	if o.is_empty():
		return fail("no_object")
	var action_id := str(cmd.get("action", ""))
	if action_id == "":
		var meal := _eat_at(world, p, object_uid)
		if meal != "":
			return success({"action": meal})
		var pick := _pick_object_action(world, p, o)
		if pick.error != "":
			return fail(pick.error)
		action_id = pick.action
	elif str(world.pack.actions.get(action_id, {}).get("object", "")) != str(o["type"]):
		return fail("no_action")
	var reason := AutonomySystem.can_do(world, p, action_id, object_uid)
	if reason != "":
		return fail(reason)
	AutonomySystem.start(world, p, action_id, object_uid)
	return success({"action": action_id})


## Dropped on a table with food on it: starts the first action that eats one of the dishes
## there (pack order) and returns its id; "" when there is none `p` can do.
static func _eat_at(world: World, p: Person, object_uid: int) -> String:
	for d in world.dishes:
		if int(d.object_uid) != object_uid:
			continue
		for aid in world.pack.actions:
			var a: Dictionary = world.pack.actions[aid]
			if not (a["eats"] as Array).has(d.type) or AutonomySystem.can_do(world, p, aid, -1) != "":
				continue
			if DishSystem.first_free(world, [d.type], p) != int(d.uid):
				continue
			AutonomySystem.start(world, p, aid, -1, int(d.uid))
			return str(aid)
	return ""


## {action, error}: the first action of object `o`'s type that `p` can do on it now, else
## why not: "dead"; the reason of the first action fit for `p`'s stage (so an object in use
## by someone else gives "busy"); "stage" when no action suits the stage; "no_action" when
## the type has no actions.
static func _pick_object_action(world: World, p: Person, o: Dictionary) -> Dictionary:
	var first_reason := ""
	var stage_only := false
	# A fix the player leads (a bath, a rest) comes first when it would do `p` some good:
	# the one that gives most of what they lack, pack order on a tie.
	var led := _best_led_action(world, p, o)
	if led != "":
		return {"action": led, "error": ""}
	# A story's finale on this object comes first while it is open.
	for id in world.pack.actions:
		var a: Dictionary = world.pack.actions[id]
		if str(a.get("completes_story", "")) != "" and str(a["object"]) == str(o["type"]) \
				and AutonomySystem.can_do(world, p, id, int(o["uid"])) == "":
			return {"action": id, "error": ""}
	for id in world.pack.actions:
		if str(world.pack.actions[id]["object"]) != str(o["type"]):
			continue
		var why := AutonomySystem.can_do(world, p, id, int(o["uid"]))
		match why:
			"":
				return {"action": id, "error": ""}
			"dead":
				return {"action": "", "error": why}
			"stage":
				stage_only = true
			_:
				if first_reason == "":
					first_reason = why
	if first_reason == "":
		first_reason = "stage" if stage_only else "no_action"
	return {"action": "", "error": first_reason}


## Of the player-led actions (`AutonomySystem.player_led`) on object `o`'s type that `p` can
## do there now, the one whose full gains would give `p` the most ("" for none that gives
## anything).
static func _best_led_action(world: World, p: Person, o: Dictionary) -> String:
	var best := ""
	var best_g := 0.0
	for id in world.pack.actions:
		var a: Dictionary = world.pack.actions[id]
		if str(a["object"]) != str(o["type"]) or not AutonomySystem.player_led(a):
			continue
		var g := 0.0
		for n in a["needs"]:
			if p.needs.has(n):
				var room := 100.0 - float(p.needs[n])
				g += minf(maxf(float(a["needs"][n]), 0.0), room) * room / 100.0
		if g > best_g and AutonomySystem.can_do(world, p, id, int(o["uid"])) == "":
			best = str(id)
			best_g = g
	return best


static func _drag_to_mess(world: World, p: Person, mess_uid: int) -> Dictionary:
	var m := MessSystem.find(world, mess_uid)
	if m.is_empty():
		return fail("no_target")
	if MessSystem.claimed_by_other(world, mess_uid, p):
		return fail("busy")
	var first_reason := "no_action"
	for id in world.pack.actions:
		if str(world.pack.actions[id]["cleans"]) != str(m["type"]):
			continue
		var why := AutonomySystem.can_do(world, p, id, -1)
		if why == "":
			AutonomySystem.start(world, p, id, -1, mess_uid)
			return success({"action": id})
		if first_reason == "no_action":
			first_reason = why
	return fail(first_reason)


static func _drag_to_collectible(world: World, p: Person, uid: int) -> Dictionary:
	if CollectibleSystem.find(world, uid).is_empty():
		return fail("no_target")
	if CollectibleSystem.claimed_by_other(world, uid, p):
		return fail("busy")
	var first_reason := "no_action"
	for id in world.pack.actions:
		if not bool(world.pack.actions[id]["picks"]):
			continue
		var why := AutonomySystem.can_do(world, p, id, -1)
		if why == "":
			AutonomySystem.start(world, p, id, -1, uid)
			return success({"action": id})
		if first_reason == "no_action":
			first_reason = why
	return fail(first_reason)


## Dropping someone on a baby: of the actions that care for babies (`tends`), the one that
## gives this baby most of what it lacks (pack order on a tie) that `p` can do now.
static func _drag_to_baby(world: World, p: Person, uid: int) -> Dictionary:
	var b := world.person(uid)
	if b == null or b == p or not b.alive or b.stage(world.pack) != "baby":
		return fail("no_target")
	if AutonomySystem.target_claimed(world, uid, "person", p):
		return fail("busy")
	var ranked: Array = []
	for id in world.pack.actions:
		var tends: Dictionary = world.pack.actions[id].get("tends", {})
		if tends.is_empty():
			continue
		var g := 0.0
		for n in tends:
			var room := 100.0 - float(b.needs.get(n, 100.0))
			g += minf(maxf(float(tends[n]), 0.0), room) * room / 100.0
		var j := ranked.size()
		while j > 0 and g > float(ranked[j - 1][1]):
			j -= 1
		ranked.insert(j, [id, g])
	var first_reason := "no_action"
	for r in ranked:
		var why := AutonomySystem.can_do(world, p, str(r[0]), -1)
		if why == "":
			AutonomySystem.start(world, p, str(r[0]), -1, uid)
			return success({"action": str(r[0])})
		if first_reason == "no_action":
			first_reason = why
	return fail(first_reason)


## Dropping someone who knows medicine on a sick member of the family: the first action that
## treats (pack order) that `p` can do now, aimed at them. "not_ill" when they are well
## (or away), "busy" when someone else is already treating them.
static func _drag_to_patient(world: World, p: Person, uid: int) -> Dictionary:
	var q := world.person(uid)
	if q == null or q == p or not q.alive or OutingSystem.away(world, q):
		return fail("no_target")
	if q.illness == "":
		return fail("not_ill")
	if not IllnessSystem.treatable(world, q, p):
		return fail("busy")
	var first_reason := "no_action"
	for id in world.pack.actions:
		if not IllnessSystem.treats(world.pack.actions[id]):
			continue
		var why := AutonomySystem.can_do(world, p, str(id), -1)
		if why == "":
			AutonomySystem.start(world, p, str(id), -1, uid)
			return success({"action": str(id)})
		if first_reason == "no_action":
			first_reason = why
	return fail(first_reason)


## Dropping someone on a pet: of the actions that look after pets and suit this one, the one
## that gives it most of what it lacks (a cure first while it is ill; pack order on a tie)
## that `p` can do now.
static func _drag_to_pet(world: World, p: Person, uid: int) -> Dictionary:
	var pet := PetSystem.find(world, uid)
	if pet == null or not pet.home():
		return fail("no_target")
	if PetSystem.held(world, pet, p):
		return fail("busy")
	var ranked: Array = []
	for id in world.pack.actions:
		var a: Dictionary = world.pack.actions[id]
		if AutonomySystem.target_kind(a) != AutonomySystem.TARGET_PET or not PetSystem.suits(a, pet):
			continue
		var ids: Array[String] = []
		var gains: Array[float] = []
		var needs: Dictionary = a["pet"].get("needs", {})
		for n in needs:
			ids.append(str(n))
			gains.append(maxf(float(needs[n]), 0.0))
		var g := PetSystem._gain_for(pet, ids, gains) + (1000.0 if bool(a["pet"].get("cures", false)) else 0.0)
		var j := ranked.size()
		while j > 0 and g > float(ranked[j - 1][1]):
			j -= 1
		ranked.insert(j, [id, g])
	var first_reason := "no_action"
	for r in ranked:
		var why := AutonomySystem.can_do(world, p, str(r[0]), -1)
		if why == "no_target":
			why = ""  # another pet may be spoken for; this one is free
		if why == "":
			AutonomySystem.start(world, p, str(r[0]), -1, uid)
			return success({"action": str(r[0])})
		if first_reason == "no_action":
			first_reason = why
	return fail(first_reason)


## Dropping someone on a story's dig mark starts the action that completes that story there.
static func _drag_to_story(world: World, p: Person, sid: String) -> Dictionary:
	var mark := {}
	for m in StorySystem.marks(world):
		if m["story"] == sid and m.get("dig", false):
			mark = m
	if mark.is_empty():
		return fail("no_target")
	var id := StorySystem.finale_action(world.pack, sid)
	if id == "":
		return fail("no_action")
	if world.people.any(func(q: Person): return q != p and q.alive and not q.current.is_empty() and q.current["action"] == id):
		return fail("busy")
	var why := AutonomySystem.can_do(world, p, id, -1)
	if why != "":
		return fail(why)
	AutonomySystem.start(world, p, id, -1)
	p.current["room"] = str(mark["room"])
	return success({"action": id})


static func _praise(world: World, cmd: Dictionary) -> Dictionary:
	var r := _judge(world, cmd, true)
	if r.ok:
		WishSystem.on_praised(world, world.person(int(cmd.get("person", -1))))
	return r


static func _scold(world: World, cmd: Dictionary) -> Dictionary:
	return _judge(world, cmd, false)


static func _judge(world: World, cmd: Dictionary, praise: bool) -> Dictionary:
	var p := world.person(int(cmd.get("person", -1)))
	if p == null:
		return fail("no_person")
	if not p.alive:
		return fail("dead")
	if OutingSystem.away(world, p):
		return fail("away")
	var id := ""
	if not p.current.is_empty():
		id = str(p.current["action"])
	elif p.last_action != "" and world.now - p.last_action_t <= JUDGE_WINDOW_S:
		id = p.last_action
	if id == "":
		return fail("nothing_to_judge")
	if not bool(world.pack.actions[id].get("praiseable", true)):
		return fail("not_praiseable")
	var need := str(world.pack.cfg("praise_need"))
	if praise:
		var window_s := int(world.pack.cfg("praise_window_min")) * 60
		p.praise_times = p.praise_times.filter(func(t): return world.now - int(t) <= window_s)
		if p.praise_times.size() >= int(world.pack.cfg("praise_annoy_count")):
			return fail("annoyed")
		p.praise_times.append(world.now)
		MoodSystem.cared(world, p)
		if need != "" and p.needs.has(need):
			p.needs[need] = clampf(float(p.needs[need]) + float(world.pack.cfg("praise_gain")), 0.0, 100.0)
	var factor := 1.25 if praise else 0.8
	p.habits[id] = clampf(float(p.habits.get(id, 1.0)) * factor, HABIT_MIN, HABIT_MAX)
	return success({"action": id})


static func _buy(world: World, cmd: Dictionary) -> Dictionary:
	var id := str(cmd.get("item", ""))
	var item: Dictionary = world.pack.items.get(id, {})
	if item.is_empty():
		return fail("no_item")
	var qty := int(cmd.get("qty", 1))
	if qty < 1:
		return fail("bad_qty")
	if not on_sale(world, id):
		return fail("not_festival")
	if not EconomySystem.spend(world, int(item["price"]) * qty):
		return fail("no_money")
	MarketSystem.give_item(world, id, qty)
	return success()


## Whether the shop sells item `id` now: an item that lists `festivals` only while one of
## them is on (for the shop to grey out or hide the rest).
static func on_sale(world: World, id: String) -> bool:
	return FestivalSystem.allows(world, world.pack.items.get(id, {}).get("festivals", []))


static func _use_item(world: World, cmd: Dictionary) -> Dictionary:
	if cmd.has("pet"):
		return PetSystem.use_item(world, cmd)
	var id := str(cmd.get("item", ""))
	if int(world.inventory.get(id, 0)) < 1:
		return fail("no_item")
	var p := world.person(int(cmd.get("person", -1)))
	if p == null or not p.alive:
		return fail("no_person")
	if OutingSystem.away(world, p):
		return fail("away")
	var item: Dictionary = world.pack.items[id]
	var cures := str(item["cures"])
	world.inventory[id] = int(world.inventory[id]) - 1
	if cures != "":
		if p.illness != cures:
			return fail("wrong_medicine")  # the item is spent anyway
		IllnessSystem.cure(world, p)
	var needs: Dictionary = item["needs"]
	for n in needs:
		if p.needs.has(n):
			p.needs[n] = clampf(float(p.needs[n]) + float(needs[n]), 0.0, 100.0)
	# Learning from it: progress for a grown-up in that livelihood (when fit to work), a tally
	# toward choosing a livelihood for a child.
	var work: Dictionary = item.get("work", {})
	if not work.is_empty() and p.track == str(work.get("track", "")) and p.stage(world.pack) in ["adult", "elder"] \
			and EconomySystem._fit_to_work(world, p):
		EconomySystem.add_progress(world, p, float(work.get("minutes", 0)))
	if p.stage(world.pack) == "child" and LivelihoodSystem.has_choice(world.pack):
		var tally: Dictionary = item.get("childhood", {})
		for a in tally:
			p.childhood[str(a)] = int(p.childhood.get(str(a), 0)) + int(tally[a])
	MoodSystem.cared(world, p)
	WishSystem.on_item_used(world, p, id)
	return success()
