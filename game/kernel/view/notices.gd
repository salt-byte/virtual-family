class_name Notices
extends RefCounted
## "Waiting for you": everything in the household that wants the player, as a list of short
## notices for the stack in the top-left corner. Each is {id, kind, text, tone, target}:
## - `id` "<kind>:<uid>" stays the same while the thing waits (tests and clicks use it)
## - `tone` "decide" (an answer is wanted), "trouble" (someone is in a bad way), "soft" (a
##   wish, a thank-you, an animal gone off) or "pickup" (something on the ground)
## - `target` the uid the click acts on (proposal id, letter id, person, animal, collectible)
## - `hint` one short line saying how to answer it ("" for none), `act` the button on the
##   notice that answers it at once ({id, text}, {} for none) and `guide` what the click
##   points at ({pulse, objects, pets, shop}), see `how`
## Most urgent first (ORDER). Reads the World only; what a click does is Main's business.
## Never reads a person's illness: the sick are the ones the view saw fall ill (`sick`).

## Kind -> rank (lower comes first) and tone.
const ORDER := {"proposal": 0, "stray": 1, "buyer": 2, "reply": 3, "letter": 4, "letters": 5, "ill": 6,
	"need": 7, "ask": 8, "pet_ill": 9, "pet_hungry": 10, "pet_away": 11, "thanks": 12, "pickup": 13, "pickups": 14,
	"wish": 15}
const TONE := {"proposal": "decide", "stray": "decide", "buyer": "decide", "reply": "decide", "letter": "decide",
	"letters": "decide", "ill": "trouble", "need": "trouble", "ask": "soft", "pet_ill": "trouble",
	"pet_hungry": "trouble", "pet_away": "soft", "thanks": "soft", "pickup": "pickup", "pickups": "pickup", "wish": "soft"}
## Icon per kind (HudIcon).
const ICON := {"proposal": "proposal", "stray": "stray", "buyer": "stray", "reply": "reply", "letter": "letter",
	"letters": "letters", "ill": "ill", "need": "need", "ask": "wish", "pet_ill": "ill", "pet_hungry": "need",
	"pet_away": "pet_away", "thanks": "thanks", "pickup": "pickup", "pickups": "pickup", "wish": "wish"}
## The one line under a notice that says how to answer it, for the kinds whose answer is
## the card the click opens (the rest work it out in `how`).
const CARD_HOW := {"proposal": "how.proposal_card", "stray": "how.stray_card", "buyer": "how.buyer_card",
	"letter": "how.letter_card", "reply": "how.reply_card", "letters": "how.letters_card",
	"pet_away": "how.pet_away", "pickup": "how.pickup", "pickups": "how.pickup"}
## Letters and pickups listed one by one up to this many; more fold into one notice.
const FOLD := 2
## Wish kinds the player can do something about.
const ACTIONABLE_WISH := {"item": true, "object": true, "room": true, "pet": true, "praise": true}


static func collect(w: World, s: ViewStrings, sick: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if w == null or w.phase != "living":
		return out
	var from := _proposal_writers(w)
	for pr in w.proposals:
		var target := w.person(int(pr.get("for", -1)))
		var id := int(pr["id"])
		var text := s.t("notice.proposal_any")
		if target != null and from.has(id):
			text = s.t("notice.proposal_from").format({"writer": from[id], "name": s.person_name(target)})
		elif target != null:
			text = s.t("notice.proposal").replace("{name}", s.person_name(target))
		_add(out, "proposal", id, text)
	if not w.pet_offer.is_empty():
		var k: Dictionary = w.pack.pets.get(str(w.pet_offer.get("kind", "")), {})
		_add(out, "stray", 0, s.t("notice.stray").replace("{kind}", str(k.get("name", ""))))
	if not w.pet_buyer.is_empty():
		var sold := PetSystem.find(w, int(w.pet_buyer.get("pet", -1)))
		if sold != null and sold.home():
			_add(out, "buyer", sold.uid, s.t("notice.buyer").replace("{name}", sold.given)
				.replace("{money}", s.t("money").replace("{n}", str(int(w.pet_buyer["price"])))))
	_letters(out, w, s)
	for p in w.people:
		if not p.alive:
			continue
		if sick.has(p.uid):
			var ill_text := s.t("ev.fell_ill").replace("{name}", s.person_name(p))
			if int(w.doctor.get("person", -1)) == p.uid:
				ill_text = s.t("notice.doctor_wait").replace("{name}", s.person_name(p)) \
					.replace("{visitor}", s.visitor_name(w, str(w.doctor.get("service", ""))))
			_add(out, "ill", p.uid, ill_text, _how_ill(w, s, p))
		var worst := _worst(s.status_chips(p, w))
		if not worst.is_empty():
			_add(out, "need", p.uid, s.t("notice.need").format({"name": s.person_name(p), "word": worst["word"]}),
				how_need(w, s, p, str(worst["need"])))
		var bubble := NeedBubble.of(w, p)
		if str(bubble.get("kind", "")) == "ask" and bool(bubble["waiting"]):
			var ask := AskSystem.current(w, p)
			# A need's ask while that need already has its notice: the notice says it.
			if not (str(ask.get("kind", "")) == "need" and not worst.is_empty()):
				_add(out, "ask", p.uid, s.t("notice.ask").format({"name": s.person_name(p), "text": str(bubble["text"])}),
					how_entry(w, s, p, ask))
		if p.thanking(w.now) and ShareSystem.text(w, p) == "":  # telling what they earned: a toast says it
			_add(out, "thanks", p.uid, s.t("notice.thanks").replace("{name}", s.person_name(p)))
		var wish := WishSystem.current(w, p)
		if not wish.is_empty() and ACTIONABLE_WISH.has(str(wish.get("kind", ""))) and not p.thanking(w.now):
			_add(out, "wish", p.uid, s.t("notice.wish").format({"name": s.person_name(p), "text": str(wish.get("text", ""))}),
				how_entry(w, s, p, wish))
	for pet in w.pets:
		if pet.home() and pet.sick:
			_add(out, "pet_ill", pet.uid, s.t("ev.pet_fell_ill").replace("{name}", pet.given), _how_pet(w, s, pet, true))
		elif pet.home() and not (PetSystem.wish_of(w, pet).get("below", {}) as Dictionary).is_empty():
			# Calling for food: the player answers by dragging someone to it (or its trough).
			_add(out, "pet_hungry", pet.uid, s.t("notice.pet_hungry").replace("{name}", pet.given)
				.replace("{text}", s.pet_wish_text(pet, w)), _how_pet(w, s, pet, false))
		elif pet.alive and pet.state == "away":
			_add(out, "pet_away", pet.uid, s.t("notice.pet_away").replace("{name}", pet.given))
	_pickups(out, w, s)
	for n in out:
		if str(n["hint"]) == "" and CARD_HOW.has(n["kind"]):
			n["hint"] = s.t(CARD_HOW[n["kind"]])
	return _sorted(out)


static func _add(out: Array[Dictionary], kind: String, target: int, text: String, how := {}) -> void:
	out.append({"id": "%s:%d" % [kind, target], "kind": kind, "text": text, "tone": TONE[kind],
		"icon": ICON[kind], "target": target, "hint": str(how.get("hint", "")),
		"act": how.get("act", {}), "guide": how.get("guide", {})})


static func _sorted(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ranks := ORDER.values()
	ranks.sort()
	for r in ranks:
		for n in list:
			if ORDER[n["kind"]] == r:
				out.append(n)
	return out


## The loudest status chip that is at a need's worst ("bad"): {need, word}; {} when none is.
static func _worst(chips: Array[Dictionary]) -> Dictionary:
	for c in chips:
		if c["level"] == "bad" and str(c["need"]) != "":
			return {"need": str(c["need"]), "word": str(c["word"])}
	return {}


## Proposal id -> the writer of the letter that brought it.
static func _proposal_writers(w: World) -> Dictionary:
	var out := {}
	for l in w.letters:
		var pid := _proposal_of(l)
		if pid >= 0:
			out[pid] = str(l["writer"])
	return out


## The proposal a letter is about (one of its choices answers it), or -1.
static func _proposal_of(l: Dictionary) -> int:
	for ch in l.get("choices", []):
		var eff: Dictionary = ch.get("effect", {})
		if str(eff.get("type", "")) == "answer_proposal":
			return int(eff.get("proposal", -1))
	return -1


## True while some choice of the letter that does something (not "later", not "none") can
## still be taken.
static func _wants_reply(w: World, l: Dictionary) -> bool:
	if int(l.get("answer", -1)) >= 0:
		return false
	var choices: Array = l.get("choices", [])
	for i in choices.size():
		var type := str(choices[i]["effect"].get("type", ""))
		if type != "later" and type != "none" and LetterSystem.choice_open(w, l, i):
			return true
	return false


## Unread letters and letters waiting for an answer, newest first, one notice per writer and
## kind: two unread letters from one person are "X来了 2 封信，还没拆", which opens the
## newest. A proposal letter is left to the proposal's own notice while the proposal waits.
## More than FOLD writers fold into one notice that opens the letter box.
static func _letters(out: Array[Dictionary], w: World, s: ViewStrings) -> void:
	if not LetterSystem.enabled(w.pack):
		return
	var waiting := {}
	for pr in w.proposals:
		waiting[int(pr["id"])] = true
	var found: Array[Dictionary] = []
	var by_key := {}
	for i in range(w.letters.size() - 1, -1, -1):
		var l: Dictionary = w.letters[i]
		if waiting.has(_proposal_of(l)):
			continue
		var kind := ""
		if not bool(l["read"]):
			kind = "letter"
		elif _wants_reply(w, l):
			kind = "reply"
		else:
			continue
		var key := kind + "|" + str(l["writer"])
		if by_key.has(key):
			by_key[key]["n"] = int(by_key[key]["n"]) + 1
		else:
			by_key[key] = {"kind": kind, "id": int(l["id"]), "writer": str(l["writer"]), "n": 1}
			found.append(by_key[key])
	for k in mini(found.size(), FOLD):
		var f: Dictionary = found[k]
		var text_key := "notice.%s_n" % f["kind"] if int(f["n"]) > 1 else "notice.%s" % f["kind"]
		_add(out, f["kind"], f["id"], s.t(text_key).format({"writer": f["writer"], "n": f["n"]}))
	if found.size() > FOLD:
		var rest := 0
		for k in range(FOLD, found.size()):
			rest += int(found[k]["n"])
		_add(out, "letters", 0, s.t("notice.letters").replace("{n}", str(rest)))


## Things lying on the ground for the player to pick up; more than FOLD fold into one.
static func _pickups(out: Array[Dictionary], w: World, s: ViewStrings) -> void:
	if w.collectibles.size() > FOLD:
		_add(out, "pickups", int(w.collectibles[0]["uid"]), s.t("notice.pickups").replace("{n}", str(w.collectibles.size())))
		return
	for c in w.collectibles:
		var room = w.pack.rooms.get(str(c.get("room", "")), {})
		var name := str(room.get("name", "")) if room is Dictionary else ""
		_add(out, "pickup", int(c["uid"]), s.t("notice.pickup").replace("{room}", name))


# --- How to answer ----------------------------------------------------------------------

## How the player meets ask or wish `e` of `p` (`MeetWay`), told in the pack's words:
## {hint, act, guide}. `act` is the notice's own button ({id, text}; ids "praise:<uid>",
## "use:<uid>:<item>", "shop:<section>", "go_out:<uid>"), `guide` what a click on the notice
## points at: `pulse` a control of the bar ("praise", "go_out", "tray:<kind>:<item>"),
## `objects` / `pets` uids to mark in the house, `shop` a market section to open.
static func how_entry(w: World, s: ViewStrings, p: Person, e: Dictionary) -> Dictionary:
	var m := MeetWay.of(w, e, p)
	var ta := _ta(s, p)
	var shop := s.t("btn.shop")
	match str(m["way"]):
		"praise":
			return _praise_how(s, p)
		"item":
			var have: Array = m["have"]
			if not have.is_empty():
				var item := str(have[0])
				return {"hint": s.t("how.item_have").format({"item": _item_name(w, item), "ta": ta}),
					"act": {"id": "use:%d:%s" % [p.uid, item], "text": s.t("how.act_use").replace("{ta}", ta)},
					"guide": {"pulse": "tray:use:" + item}}
			var items: Array = m["items"]
			return {"hint": s.t("how.item_buy").format({"item": _item_name(w, str(items[0]) if not items.is_empty() else ""),
					"ta": ta, "shop": shop}),
				"act": {"id": "shop:" + str(m["section"]), "text": s.t("how.act_shop").replace("{shop}", shop)},
				"guide": {"shop": str(m["section"])}}
		"drag_to":
			return _drag_how(w, s, p, m)
		"drag":
			return {"hint": s.t("how.hold").replace("{ta}", ta)}
		"go_out":
			return {"hint": s.t("how.go_out").format({"ta": ta, "btn": s.t("btn.go_out")}),
				"act": {"id": "go_out:%d" % p.uid, "text": s.t("how.act_go_out").replace("{ta}", ta)},
				"guide": {"pulse": "go_out"}}
		"pet":
			var pet := PetSystem.find(w, int(m["pets"][0]))
			return {"hint": s.t("how.to_pet").format({"ta": ta, "pet": pet.given if pet != null else ""}),
				"guide": {"pets": m["pets"]}}
		"self":
			return {"hint": s.t("how.self").replace("{ta}", ta)}
		"buy":
			var thing := _thing_name(w, str(m["what"]), str(m["id"]))
			return {"hint": s.t("how.buy").format({"thing": thing, "shop": shop}),
				"act": {"id": "shop:" + str(m["section"]), "text": s.t("how.act_look").replace("{shop}", shop)},
				"guide": {"shop": str(m["section"])}}
		"proposal":
			return {"hint": s.t("how.proposal")}
		"wait":
			return {"hint": s.t("how.wait")}
	return {}


## How to help `p` out of need `need` at its worst: a praise for the praise need, else a drag
## to what raises it (`MeetWay.for_need`).
static func how_need(w: World, s: ViewStrings, p: Person, need: String) -> Dictionary:
	if need != "" and need == str(w.pack.cfg("praise_need")):
		return _praise_how(s, p)
	return _drag_how(w, s, p, MeetWay.for_need(w, need, p))


static func _praise_how(s: ViewStrings, p: Person) -> Dictionary:
	var ta := _ta(s, p)
	return {"hint": s.t("how.praise").format({"ta": ta, "btn": s.t("btn.praise")}),
		"act": {"id": "praise:%d" % p.uid, "text": s.t("how.act_praise").replace("{ta}", ta)},
		"guide": {"pulse": "praise"}}


static func _drag_how(w: World, s: ViewStrings, p: Person, m: Dictionary) -> Dictionary:
	var ta := _ta(s, p)
	var types: Array = m.get("objects", [])
	if types.is_empty():
		return {"hint": s.t("how.self").replace("{ta}", ta)}
	var names: Array[String] = []
	for t in types:
		names.append(str(w.pack.object_types.get(str(t), {}).get("name", t)))
	var place := s.t("how.or").join(names)
	var uids: Array = m.get("uids", [])
	if not uids.is_empty():
		return {"hint": s.t("how.drag_to").format({"ta": ta, "place": place}), "guide": {"objects": uids}}
	var shop := s.t("btn.shop")
	var section := MarketSystem.section_of(w.pack, "object", w.pack.object_types.get(str(types[0]), {}))
	return {"hint": s.t("how.drag_none").format({"place": place, "shop": shop}),
		"act": {"id": "shop:" + section, "text": s.t("how.act_look").replace("{shop}", shop)},
		"guide": {"shop": section}}


## A person seen to be ill: the doctor (the notice's own button) or the right medicine.
static func _how_ill(w: World, s: ViewStrings, p: Person) -> Dictionary:
	var sid := ServiceSystem.first_of(w.pack, "doctor")
	var ta := _ta(s, p)
	if sid == "":
		return {"hint": s.t("how.ill_plain").replace("{ta}", ta), "guide": {"pulse": "tray:use:"}}
	return {"hint": s.t("how.ill").format({"ta": ta, "visitor": s.visitor_name(w, sid)}),
		"guide": {"pulse": "tray:doctor:"}}


## An animal calling for food (`ill` false) or ill: what is in store for it, else someone
## sent to it (food) or the market (medicine).
static func _how_pet(w: World, s: ViewStrings, pet: Pet, ill: bool) -> Dictionary:
	var opts := CareTray.options(w, null, pet, s)
	var feed := CareTray.word(s, "care.feed")
	var hint := s.t("how.pet_ill" if ill else "how.pet_hungry").format(
		{"feed": feed, "call": CareTray.word(s, "care.call"), "shop": s.t("btn.shop")})
	for e in opts:
		var item := str(e.get("item", ""))
		var cure := bool(w.pack.items.get(item, {}).get("pet", {}).get("cures", false))
		if str(e["kind"]) == "use" and cure == ill:
			return {"hint": hint, "act": {"id": "feed:%d:%s" % [pet.uid, item], "text": str(e["text"])},
				"guide": {"pulse": "tray:use:" + item}}
	if not ill:
		for e in opts:
			if str(e["kind"]) == "call":
				return {"hint": hint, "act": {"id": "call:%d" % pet.uid, "text": str(e["text"])},
					"guide": {"pulse": "tray:call:"}}
		return {"hint": hint}
	for id in w.pack.items:
		var t = w.pack.items[id].get("pet", {})
		if t is Dictionary and bool(t.get("cures", false)):
			var kinds: Array = t.get("kinds", [])
			if kinds.is_empty() or kinds.has(pet.kind):
				var section := MarketSystem.section_of(w.pack, "item", w.pack.items[id])
				return {"hint": hint, "act": {"id": "shop:" + section,
					"text": CareTray.word(s, "care.shop").replace("{shop}", s.t("btn.shop"))}, "guide": {"shop": section}}
	return {"hint": hint}


static func _ta(s: ViewStrings, p: Person) -> String:
	return s.t("how.ta_f") if p != null and p.gender == "female" else s.t("how.ta_m")


static func _item_name(w: World, id: String) -> String:
	return CareTray.short_name(str(w.pack.items.get(id, {}).get("name", id)))


static func _thing_name(w: World, what: String, id: String) -> String:
	var table: Dictionary = {"object": w.pack.object_types, "room": w.pack.rooms, "pet": w.pack.pets}.get(what, {})
	var e = table.get(id, {})
	return str(e.get("name", id)) if e is Dictionary else id
