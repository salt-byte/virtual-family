class_name Notices
extends RefCounted
## "Waiting for you": everything in the household that wants the player, as a list of short
## notices for the stack in the top-left corner. Each is {id, kind, text, tone, target}:
## - `id` "<kind>:<uid>" stays the same while the thing waits (tests and clicks use it)
## - `tone` "decide" (an answer is wanted), "trouble" (someone is in a bad way), "soft" (a
##   wish, a thank-you, an animal gone off) or "pickup" (something on the ground)
## - `target` the uid the click acts on (proposal id, letter id, person, animal, collectible)
## Most urgent first (ORDER). Reads the World only; what a click does is Main's business.
## Never reads a person's illness: the sick are the ones the view saw fall ill (`sick`).

## Kind -> rank (lower comes first) and tone.
const ORDER := {"proposal": 0, "stray": 1, "buyer": 2, "reply": 3, "letter": 4, "letters": 5, "ill": 6,
	"need": 7, "pet_ill": 8, "pet_hungry": 9, "pet_away": 10, "thanks": 11, "pickup": 12, "pickups": 13, "wish": 14}
const TONE := {"proposal": "decide", "stray": "decide", "buyer": "decide", "reply": "decide", "letter": "decide",
	"letters": "decide", "ill": "trouble", "need": "trouble", "pet_ill": "trouble", "pet_hungry": "trouble",
	"pet_away": "soft", "thanks": "soft", "pickup": "pickup", "pickups": "pickup", "wish": "soft"}
## Icon per kind (HudIcon).
const ICON := {"proposal": "proposal", "stray": "stray", "buyer": "stray", "reply": "reply", "letter": "letter",
	"letters": "letters", "ill": "ill", "need": "need", "pet_ill": "ill", "pet_hungry": "need", "pet_away": "pet_away",
	"thanks": "thanks", "pickup": "pickup", "pickups": "pickup", "wish": "wish"}
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
			_add(out, "ill", p.uid, ill_text)
		var worst := _worst(s.status_chips(p, w))
		if worst != "":
			_add(out, "need", p.uid, s.t("notice.need").format({"name": s.person_name(p), "word": worst}))
		if p.thanking(w.now) and ShareSystem.text(w, p) == "":  # telling what they earned: a toast says it
			_add(out, "thanks", p.uid, s.t("notice.thanks").replace("{name}", s.person_name(p)))
		var wish := WishSystem.current(w, p)
		if not wish.is_empty() and ACTIONABLE_WISH.has(str(wish.get("kind", ""))) and not p.thanking(w.now):
			_add(out, "wish", p.uid, s.t("notice.wish").format({"name": s.person_name(p), "text": str(wish.get("text", ""))}))
	for pet in w.pets:
		if pet.home() and pet.sick:
			_add(out, "pet_ill", pet.uid, s.t("ev.pet_fell_ill").replace("{name}", pet.given))
		elif pet.home() and not (PetSystem.wish_of(w, pet).get("below", {}) as Dictionary).is_empty():
			# Calling for food: the player answers by dragging someone to it (or its trough).
			_add(out, "pet_hungry", pet.uid, s.t("notice.pet_hungry").replace("{name}", pet.given)
				.replace("{text}", s.pet_wish_text(pet, w)))
		elif pet.alive and pet.state == "away":
			_add(out, "pet_away", pet.uid, s.t("notice.pet_away").replace("{name}", pet.given))
	_pickups(out, w, s)
	return _sorted(out)


static func _add(out: Array[Dictionary], kind: String, target: int, text: String) -> void:
	out.append({"id": "%s:%d" % [kind, target], "kind": kind, "text": text, "tone": TONE[kind],
		"icon": ICON[kind], "target": target})


static func _sorted(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ranks := ORDER.values()
	ranks.sort()
	for r in ranks:
		for n in list:
			if ORDER[n["kind"]] == r:
				out.append(n)
	return out


## The loudest status word that is at a need's worst ("bad"); "" when none is.
static func _worst(chips: Array[Dictionary]) -> String:
	for c in chips:
		if c["level"] == "bad" and str(c["need"]) != "":
			return str(c["word"])
	return ""


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
