class_name AsksRun
extends RefCounted
## Headless measure of how often the people of a household visibly want something: a real
## household runs for an hour of real play at normal speed (one sim second per real second),
## either untouched or with an attentive player who helps each request about 20 s after it
## shows. A "request" is whatever the view would draw over someone's head: a need bubble
## (`Person.ask`, when the pack has asks) or a wish bubble (`Person.wish`).
##
## Per run it reports: the share of time at least one person shows a request, how many new
## requests came (and the mean gap between them), how each one ended (the player helped, the
## person dealt with it themselves, it ran out, still open at the end) and how long it was
## up, and the household's mean need levels every five minutes.

## 2026-01-01 08:00 UTC; with `UTC_OFFSET` the local clock reads 09:00.
const START_UNIX := 1767254400
const UTC_OFFSET := 3600
## Seconds a request must have been up before the attentive player helps.
const HELP_AFTER_S := 20


## A fresh game: the first adoption (the candidate on offer), the pack's starting furniture
## only, nothing in the larder.
static func fresh(pack: Pack, seed: int) -> World:
	var w := World.new(pack, seed)
	w.set_time(START_UNIX, UTC_OFFSET)
	w.command({"type": "adopt"})
	return w


## Two grown-ups and two children in a furnished house (`BalanceRun.family_of_four`).
static func family(pack: Pack, seed: int) -> World:
	var w := BalanceRun.setup_pack(pack, seed)
	w.set_time(START_UNIX, UTC_OFFSET)
	var spouse := FamilySystem.make_person(w, w.pack.cfg("adopt_age"))
	w.add_person(spouse)
	w.married = true
	for i in 2:
		w.add_person(FamilySystem.make_person(w, [6, 12]))
	w.stock["food"] = 20
	return w


## The request `p` holds in `slot` ("ask" or "wish") now: [key, kind, need] ("" key for
## none). Nothing shows while they are out.
static func slot_of(w: World, p: Person, slot: String) -> Array:
	if not p.alive or OutingSystem.away(w, p):
		return ["", "", ""]
	if slot == "ask":
		if "ask" in p and not (p.get("ask") as Dictionary).is_empty():
			var a: Dictionary = p.get("ask")
			var e: Dictionary = w.pack.get("asks").get(str(a["id"]), {})
			return ["ask:" + str(a["id"]), "ask_" + str(e.get("kind", "")), str(e.get("need", ""))]
		return ["", "", ""]
	if not p.wish.is_empty():
		var wd: Dictionary = w.pack.wishes.get(str(p.wish["id"]), {})
		return ["wish:" + str(p.wish["id"]), str(wd.get("kind", "")), str(wd.get("need", ""))]
	return ["", "", ""]


## One hour (`seconds`) of `w`; `helper` true for the attentive player. Returns the summary.
static func run(w: World, seconds: int, helper: bool) -> Dictionary:
	var open := {}  # "uid|slot" -> {key, kind, need, since, helped, uid}
	var closed: Array = []  # [key, kind, seconds up, how]
	var formed := 0
	var shown_s := 0
	var t := 0
	var samples: Array = []
	var step := w.step_s
	var need_ids: Array = w.pack.needs.keys()
	var helped_by_player := {}  # "uid|key" -> true once the player acted on it
	while t < seconds and w.phase == "living":
		if t % 300 == 0:
			samples.append(_need_means(w, need_ids))
		if helper:
			for k in open.keys():
				var o: Dictionary = open[k]
				var p := w.person(int(o["uid"]))
				if not bool(o["helped"]) and w.now - int(o["since"]) >= HELP_AFTER_S and not p.thanking(w.now):
					o["helped"] = true
					if help(w, p, o):
						helped_by_player["%d|%s" % [p.uid, o["key"]]] = true
		w.advance(float(step))
		t += step
		var ends := {}  # "uid|slot" -> how it ended in this step, from the events
		for e in w.drain_events():
			match str(e.type):
				"wish_granted":
					ends["%d|wish" % int(e.person)] = "granted"
				"ask_helped":
					ends["%d|ask" % int(e.person)] = "granted"
				"wish_expired":
					ends["%d|wish" % int(e.person)] = "expired"
				"ask_expired":
					ends["%d|ask" % int(e.person)] = "expired"
		var any := false
		for p in w.people:
			for slot in ["ask", "wish"]:
				var r := slot_of(w, p, slot)
				var k := "%d|%s" % [p.uid, slot]
				var o: Dictionary = open.get(k, {})
				if not o.is_empty() and str(o["key"]) != r[0]:
					var how := str(ends.get(k, "self"))
					var by_player := helped_by_player.has("%d|%s" % [p.uid, o["key"]])
					if how == "granted" and not by_player:
						how = "self"  # met without the player (a body wish whose need came back up)
					elif how == "self" and by_player:
						how = "granted"
					closed.append([o["key"], o["kind"], w.now - int(o["since"]), how])
					open.erase(k)
					o = {}
				if r[0] != "" and o.is_empty():
					open[k] = {"key": r[0], "kind": r[1], "need": r[2], "since": w.now, "helped": false, "uid": p.uid}
					formed += 1
			if not NeedBubble.of(w, p).is_empty():
				any = true  # what the view draws over their head (see `NeedBubble`)
		if any:
			shown_s += step
	samples.append(_need_means(w, need_ids))
	var by_how := {"granted": [], "self": [], "expired": []}
	var by_kind := {}
	var by_id := {}  # key -> [count, seconds up in all, granted, self, expired]
	for c in closed:
		(by_how[c[3]] as Array).append(int(c[2]))
		by_kind[c[1]] = int(by_kind.get(c[1], 0)) + 1
		var b: Array = by_id.get(c[0], [0, 0, 0, 0, 0])
		b[0] += 1
		b[1] += int(c[2])
		b[{"granted": 2, "self": 3, "expired": 4}[c[3]]] += 1
		by_id[c[0]] = b
	for k in open:
		by_kind[open[k]["kind"]] = int(by_kind.get(open[k]["kind"], 0)) + 1
	var out := {
		"people": w.people.filter(func(p): return p.alive).size(),
		"shown_pct": snappedf(100.0 * shown_s / maxf(t, 1), 0.1),
		"new_requests": formed,
		"mean_gap_s": snappedf(float(t) / formed, 1) if formed > 0 else -1,
		"still_open_at_end": open.size(),
		"by_kind": by_kind,
		"by_id": by_id,
		"needs_every_5_min": samples,
	}
	for how in by_how:
		var l: Array = by_how[how]
		out[how] = {"n": l.size(), "mean_s": snappedf(_mean(l), 1), "median_s": _median(l)}
	return out


static func _need_means(w: World, ids: Array) -> Dictionary:
	var m := {}
	var n := 0
	for p in w.people:
		if not p.alive:
			continue
		n += 1
		for id in ids:
			m[id] = float(m.get(id, 0.0)) + float(p.needs.get(id, 0.0))
	for id in m:
		m[id] = roundi(float(m[id]) / maxi(n, 1))
	return m


static func _mean(l: Array) -> float:
	if l.is_empty():
		return 0.0
	var s := 0.0
	for x in l:
		s += float(x)
	return s / l.size()


static func _median(l: Array) -> int:
	if l.is_empty():
		return 0
	var c := l.duplicate()
	c.sort()
	return int(c[c.size() / 2])


## What an attentive player does about request `o` of `p`: lead them to a fix of a need,
## praise them, pick them up, give a wished-for shop item, or lead them to a wished action.
## True when the player managed to act.
static func help(w: World, p: Person, o: Dictionary) -> bool:
	var kind := str(o["kind"])
	var key := str(o["key"])
	var id := key.substr(key.find(":") + 1)
	var entry: Dictionary = (w.pack.get("asks").get(id, {}) if key.begins_with("ask:") else w.pack.wishes.get(id, {}))
	match kind:
		"need", "ask_need":
			return lead_to_need(w, p, str(o["need"]))
		"praise", "ask_praise":
			return w.command({"type": "praise", "person": p.uid}).ok
		"ask_hold":
			return _carry(w, p)
		"item", "ask_item":
			var items: Array = entry.get("items", [entry.get("item", "")])
			for it in items:
				if w.command({"type": "buy", "item": it}).ok:
					return w.command({"type": "use_item", "item": it, "person": p.uid}).ok
		"do", "ask_do":
			return _lead_to_action(w, p, entry.get("actions", []))
	return false


## Drops `p` somewhere they are not: picked up and set down by an object they can use.
static func _carry(w: World, p: Person) -> bool:
	for o in w.objects:
		if w.command({"type": "drag", "person": p.uid, "object": int(o.uid)}).ok:
			return true
	return false


static func _lead_to_action(w: World, p: Person, actions: Array) -> bool:
	for aid in actions:
		var a: Dictionary = w.pack.actions.get(aid, {})
		if a.is_empty():
			continue
		if AutonomySystem.target_kind(a) == AutonomySystem.TARGET_PET:
			for pet in w.pets:
				if pet.home() and w.command({"type": "drag", "person": p.uid, "pet": pet.uid}).ok:
					return true
			continue
		if a.has("outing") and not (a["outing"] as Dictionary).is_empty():
			if w.command({"type": "go_out", "person": p.uid, "action": aid}).ok:
				return true
			continue
		for o in w.objects:
			if o.type == a["object"] and w.command({"type": "drag", "person": p.uid, "object": int(o.uid), "action": aid}).ok:
				return true
	return false


## Leads `p` to something that raises `need`: a dish on the table for food (buying food
## and leaving it to be cooked when there is none), else the object action that gives the
## most of it.
static func lead_to_need(w: World, p: Person, need: String) -> bool:
	for d in w.dishes:
		if w.command({"type": "drag", "person": p.uid, "object": int(d.object_uid)}).ok \
				and not p.current.is_empty() and float((w.pack.actions[p.current["action"]]["needs"] as Dictionary).get(need, 0.0)) > 0.0:
			return true
	# Like a player: drop them on the object whose action gives most of the need (sleep, which
	# only runs at night, left out) and let the game pick what they do there.
	var best_g := 0.0
	var best_o := -1
	for aid in w.pack.actions:
		var a: Dictionary = w.pack.actions[aid]
		var g := float((a["needs"] as Dictionary).get(need, 0.0))
		if g <= best_g or str(a["object"]) == "" or bool(a.get("slow", false)):
			continue
		for o in w.objects:
			if o.type == a["object"] and AutonomySystem.can_do(w, p, aid, int(o.uid)) == "":
				best_g = g
				best_o = int(o.uid)
				break
	if best_o < 0 and need == "fed" and int(w.stock.get("food", 0)) <= 0:
		if w.command({"type": "buy", "item": "rice"}).ok:
			return lead_to_need(w, p, need)
	if best_o < 0:
		return false
	return w.command({"type": "drag", "person": p.uid, "object": best_o}).ok \
			and not p.current.is_empty() and float((w.pack.actions[p.current["action"]]["needs"] as Dictionary).get(need, 0.0)) > 0.0
