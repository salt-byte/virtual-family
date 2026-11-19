class_name LetterSystem
extends RefCounted
## Letters to the player (a pack's optional letters.json with its `letters` settings in
## pack.json; off without them, and then nothing here draws randomness). Things that happen
## in the house become letters: the kernel watches a few events (`WATCH`), picks a template
## of the matching kind, fills its {slots} and keeps the finished letter in `world.letters`.
##
## Kinds and who writes them:
## - "thanks" (a wish granted), "ask" (a wish for a thing formed), "sad" / "depressed" (a low
##   mood set in), "ill" (fell ill), "took_up" (came of age and took up a livelihood): the
##   person themself
## - "birth": a parent; "death": the spouse, else a child, a parent, anyone left;
##   "married": the one who was already in the house; "pet_ran" / "pet_back": a child if
##   there is one, else a grown-up
## - "proposal" (a proposal arrived), "kin" (now and then, `kin_chance_per_day`) and "story"
##   (an old story unlocked, reached its finale or ended; templates name `story` and `on`):
##   someone from outside, named by the template's `from` and `sign`
## Minor kinds (`MINOR`) come only by their `chance`, at least `min_gap_min` apart and while
## fewer than `unread_max` letters wait unread; the rest always come.
##
## A family member's hand is the first of the settings' `hands` that fits them (`stages`,
## and `tracks` or `likes` when given). A hand with `scribe` cannot write: the letter is
## taken down by a member who can (grown-ups first) or by `scribe_outside`, and its `sign`
## may name them as {scribe}. Templates may limit themselves to hands (`hand`), and to facts
## (`if`: gender, cause, relation, hungry, wish_kind).
##
## A letter's `choices` hold resolved effects (`EFFECTS`); the player answers with the
## command `answer_letter` {letter, choice} and marks one read with `read_letter` {letter}.
## "later" only marks the letter read and keeps it open. Letters written while the player
## was away are cut to the `offline_max` most important (`trim_new`).

## Kind -> importance (higher survives an absence; see `trim_new`).
const KINDS := {"death": 100, "birth": 90, "married": 85, "proposal": 80, "took_up": 70,
	"story": 65, "pet_ran": 60, "pet_back": 55, "depressed": 50, "ill": 40, "ask": 30,
	"sad": 25, "kin": 20, "thanks": 10}
const MINOR := {"thanks": true, "ask": true, "sad": true, "ill": true, "kin": true}
## Event types that may turn into letters (`World.emit` queues these).
const WATCH := {"wish_granted": true, "wish_formed": true, "mood_changed": true, "fell_ill": true,
	"born": true, "person_died": true, "married": true, "took_up": true, "pet_ran_away": true,
	"pet_came_back": true, "proposal_arrived": true, "story_unlocked": true, "story_finale": true,
	"story_done": true}
const EFFECTS := ["none", "later", "mood", "wish_keep", "wish_drop", "answer_proposal",
	"change_track", "money"]
const STORY_ON := ["unlocked", "finale", "done"]
## Wish kinds a person may write to ask for.
const ASKABLE := {"item": true, "object": true, "room": true, "pet": true}


static func enabled(pack: Pack) -> bool:
	var c = pack.cfg("letters")
	return not pack.letters.is_empty() and c is Dictionary and not (c as Dictionary).is_empty()


static func cfg(pack: Pack) -> Dictionary:
	var c = pack.cfg("letters")
	return c if c is Dictionary else {}


static func _num(c: Dictionary, key: String, d: float) -> float:
	var v = c.get(key, d)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else d


## Turns the queued events into letters, and once an hour may bring a letter from kin.
static func step(world: World, dt: float) -> void:
	if world._letter_news.is_empty() and world.now % 3600 >= int(dt):
		return
	if not enabled(world.pack):
		world._letter_news = []
		return
	var news := world._letter_news
	world._letter_news = []
	if world.phase != "living":
		return
	for e in news:
		_on_event(world, e)
	if world.now % 3600 < int(dt):
		_maybe_kin(world)


static func _on_event(world: World, e: Dictionary) -> void:
	match str(e["type"]):
		"wish_granted":
			var p := world.person(int(e["person"]))
			if p != null and p.alive:
				_write(world, "thanks", p, p, {"wish": _wish_text(world, str(e["wish"]))})
		"wish_formed":
			var p := world.person(int(e["person"]))
			var w: Dictionary = world.pack.wishes.get(str(e["wish"]), {})
			if p != null and p.alive and ASKABLE.has(str(w.get("kind", ""))) and _may_minor(world, "ask"):
				_write(world, "ask", p, p, {"wish": str(w["text"])}, {"wish_kind": str(w["kind"])},
					{"person": p.uid, "wish": str(e["wish"])})
		"mood_changed":
			var p := world.person(int(e["person"]))
			var mood := str(e["mood"])
			if p != null and p.alive and (mood == "sad" and str(e["was"]) == "" or mood == "depressed"):
				_write(world, mood, p, p, {}, {}, {"person": p.uid})
		"fell_ill":
			var p := world.person(int(e["person"]))
			if p != null and p.alive:
				_write(world, "ill", p, p, {}, {}, {"person": p.uid})
		"born":
			var child := world.person(int(e["person"]))
			if child != null:
				var parents: Array = []
				for uid in [child.mother, child.father]:
					var q := world.person(int(uid))
					if q != null and q.alive:
						parents.append(q)
				if not parents.is_empty():
					var writer: Person = world.rng.pick(parents)
					_write(world, "birth", writer, child, {"child": child.given}, {"gender": child.gender})
		"person_died":
			_on_death(world, world.person(int(e["person"])), str(e["cause"]))
		"married":
			var newcomer := world.person(int(e["person"]))
			if newcomer != null:
				var head := world.person(newcomer.spouse)
				var writer := head if head != null and head.alive else newcomer
				_write(world, "married", writer, newcomer, {"spouse": newcomer.given,
					"spouse_full": newcomer.family + newcomer.given}, {"gender": newcomer.gender})
		"took_up":
			_on_took_up(world, world.person(int(e["person"])))
		"pet_ran_away", "pet_came_back":
			_on_pet(world, PetSystem.find(world, int(e["pet"])), str(e["type"]) == "pet_ran_away",
				bool(e.get("hungry", false)))
		"proposal_arrived":
			_on_proposal(world, int(e["id"]))
		"story_unlocked", "story_finale", "story_done":
			var on := str(e["type"]).trim_prefix("story_")
			_write(world, "story", null, null, {}, {}, {}, str(e["story"]), on)


static func _wish_text(world: World, id: String) -> String:
	return str(world.pack.wishes.get(id, {}).get("text", ""))


static func _on_death(world: World, dead: Person, cause: String) -> void:
	if dead == null:
		return
	var writer: Person = null
	var relation := "other"
	var sp := world.person(dead.spouse)
	if sp != null and sp.alive and _can_hold_pen(world, sp):
		writer = sp
		relation = "spouse"
	if writer == null:
		for q in world.people:
			if q.alive and (q.mother == dead.uid or q.father == dead.uid) and _can_hold_pen(world, q):
				writer = q
				relation = "child"
				break
	if writer == null:
		for uid in [dead.mother, dead.father]:
			var q := world.person(int(uid))
			if q != null and q.alive and _can_hold_pen(world, q):
				writer = q
				relation = "parent"
				break
	if writer == null:
		for q in world.people:
			if q.alive and _can_hold_pen(world, q):
				writer = q
				break
	if writer == null:
		return
	_write(world, "death", writer, dead, {"dead": dead.given, "dead_full": dead.family + dead.given,
		"age": str(int(dead.age))}, {"cause": cause, "relation": relation, "gender": dead.gender})


static func _on_took_up(world: World, p: Person) -> void:
	if p == null or not p.alive or p.track == "":
		return
	var others: Array = []
	for lid in world.pack.livelihoods:
		if str(lid) != p.track:
			others.append(str(lid))
	var alt := str(world.rng.pick(others)) if not others.is_empty() else ""
	var slots := {"job": _job(world, p.track), "alt": _job(world, alt)}
	_write(world, "took_up", p, p, slots, {}, {"person": p.uid, "track": p.track, "alt": alt})


static func _job(world: World, track: String) -> String:
	return str(world.pack.livelihoods.get(track, {}).get("name", ""))


static func _on_pet(world: World, pet: Pet, ran: bool, hungry: bool) -> void:
	if pet == null:
		return
	var young: Array = []
	var grown: Array = []
	for q in world.people:
		if q.alive and _can_hold_pen(world, q):
			(young if q.stage(world.pack) == "child" else grown).append(q)
	var pool := young if not young.is_empty() else grown
	if pool.is_empty():
		return
	var writer: Person = world.rng.pick(pool)
	var kind := str(world.pack.pets.get(pet.kind, {}).get("name", ""))
	_write(world, "pet_ran" if ran else "pet_back", writer, null, {"pet": pet.given, "pet_kind": kind},
		{"hungry": hungry})


static func _on_proposal(world: World, id: int) -> void:
	var pr: Dictionary = {}
	for q in world.proposals:
		if int(q["id"]) == id:
			pr = q
	if pr.is_empty():
		return
	var match_p := Person.from_dict(pr["person"])
	var target := world.person(int(pr.get("for", -1)))
	if target == null:
		target = FamilySystem.proposal_target(world)
	var words: Dictionary = cfg(world.pack).get("words", {})
	var slots := {"match": match_p.given, "match_full": match_p.family + match_p.given,
		"match_kind": str(words.get(match_p.gender, "")), "age": str(int(match_p.age)),
		"savings": str(int(pr["savings"])), "target": target.given if target != null else ""}
	_write(world, "proposal", null, target, slots, {"gender": match_p.gender}, {"proposal": id})


static func _maybe_kin(world: World) -> void:
	var chance := _num(cfg(world.pack), "kin_chance_per_day", 0.0) / 24.0
	if chance <= 0.0 or not _may_minor(world, "kin") or not world.rng.chance(chance):
		return
	var head: Person = null
	for q in world.people:
		if q.alive and q.stage(world.pack) in ["adult", "elder"]:
			head = q
			break
	if head == null:
		return
	_write(world, "kin", null, head, {}, {}, {}, "", "", true)


## Whether a minor letter of `kind` may come now (no randomness).
static func _may_minor(world: World, kind: String) -> bool:
	if not MINOR.has(kind):
		return true
	var c := cfg(world.pack)
	if world.now - world.letter_minor_at < int(_num(c, "min_gap_min", 20.0) * 60.0) and world.letter_minor_at > 0:
		return false
	var unread := 0
	for l in world.letters:
		if not bool(l["read"]):
			unread += 1
	return unread < int(_num(c, "unread_max", 3.0))


## True when `p` is past the baby stage (babies neither write nor dictate).
static func _can_hold_pen(world: World, p: Person) -> bool:
	return p.age >= world.pack.baby_until()


## The first hand in the settings that fits `p` ({} when none does).
static func hand_of(world: World, p: Person) -> Dictionary:
	var stage := p.stage(world.pack)
	for h in cfg(world.pack).get("hands", []):
		var stages: Array = h.get("stages", [])
		if not stages.is_empty() and not stages.has(stage):
			continue
		var tracks: Array = h.get("tracks", [])
		var likes: Array = h.get("likes", [])
		if tracks.is_empty() and likes.is_empty():
			return h
		if tracks.has(p.track) or likes.any(func(t): return p.likes.has(t)):
			return h
	return {}


## Who writes for `p`: a member who can write (grown-ups before children), else the
## settings' `scribe_outside`.
static func _scribe(world: World, p: Person) -> String:
	var child_pen := ""
	for q in world.people:
		if q == p or not q.alive or not _can_hold_pen(world, q):
			continue
		var h := hand_of(world, q)
		if h.is_empty() or bool(h.get("scribe", false)):
			continue
		if q.stage(world.pack) in ["adult", "elder"]:
			return q.given
		if child_pen == "":
			child_pen = q.given
	return child_pen if child_pen != "" else str(cfg(world.pack).get("scribe_outside", ""))


## Writes a letter of `kind` from `writer` (null: someone outside) about `subject`, when the
## kind may come now and a template fits. `ref` names what its choices act on.
static func _write(world: World, kind: String, writer: Person, subject: Person, slots: Dictionary,
		facts := {}, ref := {}, story := "", on := "", checked := false) -> void:
	if writer != null and not _can_hold_pen(world, writer):
		return
	if not checked and not _may_minor(world, kind):
		return
	var c := cfg(world.pack)
	if MINOR.has(kind) and not checked:
		var chance: Dictionary = c.get("chance", {})
		if not world.rng.chance(_num(chance, kind, 1.0)):
			return
	var hand := {}
	if writer != null:
		hand = hand_of(world, writer)
		if hand.is_empty():
			return
	var ids: Array = []
	var weights: Array = []
	for id in world.pack.letters:
		var t: Dictionary = world.pack.letters[id]
		if str(t["kind"]) != kind or str(t["story"]) != story or str(t["on"]) != on:
			continue
		var hands: Array = t["hand"]
		if writer != null and not hands.is_empty() and not hands.has(str(hand.get("id", ""))):
			continue
		var fits := true
		for k in t["if"]:
			if str(facts.get(k, "")) != str(t["if"][k]):
				fits = false
				break
		if fits:
			ids.append(id)
			weights.append(float(t["weight"]))
	if ids.is_empty():
		return
	var pick := str(ids[0]) if ids.size() == 1 else str(world.rng.weighted_pick(ids, weights))
	var t: Dictionary = world.pack.letters[pick]
	var all := slots.duplicate()
	if writer != null:
		all["name"] = writer.given
		all["full"] = writer.family + writer.given
		if bool(hand.get("scribe", false)):
			all["scribe"] = _scribe(world, writer)
	if subject != null:
		all["who"] = subject.given
		all["who_full"] = subject.family + subject.given
	var sign := str(t["sign"]) if str(t["sign"]) != "" else str(hand.get("sign", ""))
	var choices: Array = []
	for ch in t["choices"]:
		var eff := _resolve(ch["effect"], ref, writer, subject)
		if not eff.is_empty():
			choices.append({"label": str(ch["label"]).format(all), "effect": eff})
	var letter := {"id": world.letter_next, "t": world.now, "kind": kind, "template": str(t["id"]),
		"from": writer.uid if writer != null else 0, "about": subject.uid if subject != null else 0,
		"writer": str(all.get("full", "")) if writer != null else str(t["from"]).format(all),
		"hand": str(hand.get("id", "")), "text": str(t["text"]).format(all), "sign": sign.format(all),
		"choices": choices, "answer": -1, "read": false}
	world.letter_next += 1
	world.letters.append(letter)
	if MINOR.has(kind):
		world.letter_minor_at = world.now
	_prune(world)
	world.emit("letter_arrived", {"letter": int(letter["id"]), "kind": kind})


## A template choice's effect made concrete ({} when it has nothing to act on).
static func _resolve(effect: Dictionary, ref: Dictionary, writer: Person, subject: Person) -> Dictionary:
	var type := str(effect.get("type", "none"))
	var out := {"type": type}
	match type:
		"mood":
			var who := writer if writer != null else subject
			if who == null:
				return {}
			out["person"] = who.uid
			out["amount"] = _num(effect, "amount", 0.0)
		"wish_keep", "wish_drop":
			if not ref.has("wish"):
				return {}
			out["person"] = int(ref["person"])
			out["wish"] = str(ref["wish"])
			out["amount"] = _num(effect, "amount", 0.0)
			if type == "wish_keep":
				out["hours"] = _num(effect, "hours", 0.0)
		"answer_proposal":
			if not ref.has("proposal"):
				return {}
			out["proposal"] = int(ref["proposal"])
			out["accept"] = bool(effect.get("accept", false))
		"change_track":
			if str(ref.get("alt", "")) == "":
				return {}
			out["person"] = int(ref["person"])
			out["from"] = str(ref["track"])
			out["track"] = str(ref["alt"])
		"money":
			out["amount"] = int(_num(effect, "amount", 0.0))
	return out


## Keeps at most `keep` letters: the oldest read ones go first.
static func _prune(world: World) -> void:
	var keep := int(_num(cfg(world.pack), "keep", 300.0))
	while world.letters.size() > keep:
		var gone := 0
		for i in world.letters.size():
			if bool(world.letters[i]["read"]):
				gone = i
				break
		world.letters.remove_at(gone)


## The letter with this id, or {}.
static func find(world: World, id: int) -> Dictionary:
	for l in world.letters:
		if int(l["id"]) == id:
			return l
	return {}


## How many letters wait unread.
static func unread(world: World) -> int:
	var n := 0
	for l in world.letters:
		if not bool(l["read"]):
			n += 1
	return n


## Whether choice `i` of `letter` can still be taken: unanswered, and what it acts on is
## still there (the proposal waits, the wish is still held, the person still alive, ...).
static func choice_open(world: World, letter: Dictionary, i: int) -> bool:
	var choices: Array = letter.get("choices", [])
	if int(letter.get("answer", -1)) >= 0 or i < 0 or i >= choices.size():
		return false
	var eff: Dictionary = choices[i]["effect"]
	match str(eff["type"]):
		"mood":
			var p := world.person(int(eff["person"]))
			return p != null and p.alive
		"wish_keep", "wish_drop":
			var p := world.person(int(eff["person"]))
			return p != null and p.alive and str(p.wish.get("id", "")) == str(eff["wish"])
		"answer_proposal":
			return world.proposals.any(func(pr): return int(pr["id"]) == int(eff["proposal"]))
		"change_track":
			var p := world.person(int(eff["person"]))
			return p != null and p.alive and p.track == str(eff["from"])
	return true


## True while some choice of `letter` can still be taken.
static func is_open(world: World, letter: Dictionary) -> bool:
	for i in (letter.get("choices", []) as Array).size():
		if choice_open(world, letter, i):
			return true
	return false


## Command {letter}: marks it read.
static func read(world: World, cmd: Dictionary) -> Dictionary:
	var l := find(world, int(cmd.get("letter", -1)))
	if l.is_empty():
		return Commands.fail("no_letter")
	l["read"] = true
	return Commands.success()


## Command {letter, choice}: answers it with that choice and carries out its effect.
static func answer(world: World, cmd: Dictionary) -> Dictionary:
	var l := find(world, int(cmd.get("letter", -1)))
	if l.is_empty():
		return Commands.fail("no_letter")
	var i := int(cmd.get("choice", -1))
	var choices: Array = l["choices"]
	if i < 0 or i >= choices.size():
		return Commands.fail("no_choice")
	if int(l["answer"]) >= 0:
		return Commands.fail("answered")
	if not choice_open(world, l, i):
		return Commands.fail("too_late")
	var eff: Dictionary = choices[i]["effect"]
	var p := world.person(int(eff.get("person", -1)))
	match str(eff["type"]):
		"later":
			l["read"] = true
			return Commands.success()
		"mood":
			_add_mood(world, p, float(eff["amount"]))
		"wish_keep":
			p.wish["expires_at"] = int(p.wish["expires_at"]) + int(float(eff["hours"]) * 3600.0)
			_add_mood(world, p, float(eff["amount"]))
		"wish_drop":
			p.wish_last = str(p.wish["id"])
			p.wish = {}
			_add_mood(world, p, float(eff["amount"]))
		"answer_proposal":
			var r := world.command({"type": "answer_proposal", "id": int(eff["proposal"]), "accept": bool(eff["accept"])})
			if not r.ok:
				return r
		"change_track":
			var r2 := world.command({"type": "change_track", "person": int(eff["person"]), "track": str(eff["track"])})
			if not r2.ok:
				return r2
		"money":
			var amount := int(eff["amount"])
			if amount < 0 and not EconomySystem.spend(world, -amount):
				return Commands.fail("no_money")
			EconomySystem.earn(world, amount, "letter")
	l["answer"] = i
	l["read"] = true
	world.emit("letter_answered", {"letter": int(l["id"]), "choice": i})
	return Commands.success()


## Moves `p`'s praise need by `amount`; a kind word also counts as attention.
static func _add_mood(world: World, p: Person, amount: float) -> void:
	if p == null or not p.alive:
		return
	var need := str(world.pack.cfg("praise_need"))
	if need != "" and p.needs.has(need):
		p.needs[need] = clampf(float(p.needs[need]) + amount, 0.0, 100.0)
	if amount > 0.0:
		MoodSystem.cared(world, p)


## After an absence: of the letters numbered `first_id` and up, keeps the `offline_max` most
## important (newer first among equals) and returns their ids, most important first.
static func trim_new(world: World, first_id: int) -> Array:
	if not enabled(world.pack):
		return []
	var fresh: Array = world.letters.filter(func(l): return int(l["id"]) >= first_id)
	fresh.sort_custom(func(a, b):
		var pa := int(KINDS.get(str(a["kind"]), 0))
		var pb := int(KINDS.get(str(b["kind"]), 0))
		return pa > pb if pa != pb else int(a["id"]) > int(b["id"]))
	var cap := int(_num(cfg(world.pack), "offline_max", 5.0))
	var kept: Array = []
	var drop := {}
	for k in fresh.size():
		if k < cap:
			kept.append(int(fresh[k]["id"]))
		else:
			drop[int(fresh[k]["id"])] = true
	if not drop.is_empty():
		world.letters.assign(world.letters.filter(func(l): return not drop.has(int(l["id"]))))
	return kept
