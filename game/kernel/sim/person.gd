class_name Person
extends RefCounted
## One member of the household. Plain data plus a few read helpers; the systems mutate it.

var uid := 0
var given := ""
var family := ""
var gender := ""
var age := 0.0
var lifespan := 70.0
var alive := true
## need id -> 0..100
var needs: Dictionary = {}
var likes: Array = []
var dislikes: Array = []
## action id -> weight (a missing action counts as 1.0)
var habits: Dictionary = {}
## `now` of the last few times this person was praised
var praise_times: Array = []
var track := ""
var level := 0
var progress := 0.0
var aptitude := 1.0
## Fraction of a coin of work bonus earned but not yet paid (0 <= work_carry < 1).
var work_carry := 0.0
## illness id; "" means healthy
var illness := ""
## Empty when idle; otherwise {action, object_uid, target_uid, remaining_s} and, for an
## action that names the rooms it happens in, `room` (the one picked when it started).
var current: Dictionary = {}
var last_action := ""
var last_action_t := 0
## The last few finished action ids, most recent first (at most the pack's `repeat_memory`).
var recent_actions: Array = []
## While a child, in a pack with several livelihoods: action id -> times finished. Read at
## coming of age to choose a livelihood (see `LivelihoodSystem`).
var childhood: Dictionary = {}
## The wish this person has right now: {} for none, else {id, expires_at} (a pack wish id).
var wish: Dictionary = {}
## Id of the last wish that ended (granted or not), so the next one is a different wish.
var wish_last := ""
## `now` until which this person stops to thank the player (0: not thanking). While it lasts
## they do nothing else; the view shows them turned to the screen, waving.
var thanks_until := 0
## The ask this person is making of the player ({} for none, else {id, phase: "wait" |
## "self", until}; see `AskSystem`), `now` when the last one ended (0: never), and ask id ->
## `now` until which an ask that went unanswered does not come again.
var ask: Dictionary = {}
var ask_last_t := 0
var ask_again: Dictionary = {}
## Low mood that has set in: "" (none), "sad", or "depressed" (see `MoodSystem`).
var mood := ""
## Seconds the mood need has stayed below the pack's low line, and above its recovery line.
var mood_low_s := 0
var mood_ok_s := 0
## `now` of the player's last attention to this person (a praise, something used on them, a
## wish granted); 0 until the mood system first sees them.
var cared_at := 0
## Not saved: `MoodSystem.ceiling` as of the start of the current game minute (or the last
## attention), kept so the action hot path needs no lookups. Rebuilt on load.
var mood_cap := 100.0
## Not saved: the likes / dislikes part of `AutonomySystem._flags`' cache key, and the lists
## it was made from.
var _key := ""
var _key_likes: Variant = null
var _key_dislikes: Variant = null
## 0 for someone who came from outside (adopted, married in); a person born in the house is
## one more than the higher of their parents' generations.
var generation := 0
## uid of the person they married (0: never married); kept after that person dies.
var spouse := 0
## uids of the parents of someone born in the house (0: came from outside).
var mother := 0
var father := 0
## `now` at which the baby is due (0: not with child), and the father's uid.
var pregnant_until := 0
var pregnant_by := 0
## Sharing earnings with the player (see `ShareSystem`): the local day the tally is for (-1:
## none yet), what they earned that day, how much of it they have already told the player
## about, `now` of the last time they turned to share, and what they are sharing while the
## wave lasts ({} for nothing: {kind: "money" | "level", n, level}).
var earned_day := -1
var earned := 0
var earned_told := 0
var shared_at := 0
var share: Dictionary = {}
## Not saved: the factor on the chance of falling ill from low needs, as of the start of the
## current game minute (see `NeedsSystem.illness_factor`); 1 until then.
var ill_factor := 1.0
## Which of the pack's looks they wear (`LookSystem`): "" for the stage's own picture as
## before (old saves, packs without looks), "child" until grown up, else a look id.
var look := ""


## Status bar: need id -> the label word that applies to the current value.
func status(pack: Pack) -> Dictionary:
	var out := {}
	for nid in pack.needs:
		var labels: Array = pack.needs[nid].get("labels", [])
		if labels.is_empty():
			continue
		var v := float(needs.get(nid, 0.0))
		var text := str(labels[-1]["text"])
		for l in labels:
			if v < float(l["below"]):
				text = str(l["text"])
				break
		out[nid] = text
	return out


## True while carrying a child (see `BirthSystem`).
func pregnant() -> bool:
	return pregnant_until > 0


## True while thanking the player (see `thanks_until`).
func thanking(now: int) -> bool:
	return thanks_until > now


## Life stage id, from the pack's `stages` thresholds (years).
func stage(pack: Pack) -> String:
	return pack.stage_of(age)


func to_dict() -> Dictionary:
	var d := {
		"uid": uid, "given": given, "family": family, "gender": gender, "age": age,
		"lifespan": lifespan, "alive": alive, "needs": needs.duplicate(true),
		"likes": likes.duplicate(true), "dislikes": dislikes.duplicate(true),
		"habits": habits.duplicate(true), "praise_times": praise_times.duplicate(true),
		"track": track, "level": level, "progress": progress, "aptitude": aptitude, "work_carry": work_carry,
		"illness": illness, "current": current.duplicate(true),
		"last_action": last_action, "last_action_t": last_action_t,
		"recent_actions": recent_actions.duplicate(), "childhood": childhood.duplicate(),
		"wish": wish.duplicate(true), "wish_last": wish_last, "thanks_until": thanks_until,
		"mood": mood, "mood_low_s": mood_low_s, "mood_ok_s": mood_ok_s, "generation": generation, "cared_at": cared_at,
		"spouse": spouse, "mother": mother, "father": father,
		"pregnant_until": pregnant_until, "pregnant_by": pregnant_by,
	}
	if look != "":
		d["look"] = look
	# Optional, written only once this person has earned something to share.
	if earned_day >= 0:
		d["earned"] = {"day": earned_day, "n": earned, "told": earned_told, "shared_at": shared_at}
	if not share.is_empty():
		d["share"] = share.duplicate(true)
	# Optional, written only once this person has asked something of the player.
	if not ask.is_empty():
		d["ask"] = ask.duplicate(true)
	if ask_last_t != 0:
		d["ask_last_t"] = ask_last_t
	if not ask_again.is_empty():
		d["ask_again"] = ask_again.duplicate()
	return d


## Rebuilds a Person; tolerates JSON round trips where every number is a float.
static func from_dict(d: Dictionary) -> Person:
	var p := Person.new()
	p.uid = int(d.get("uid", 0))
	p.given = str(d.get("given", ""))
	p.family = str(d.get("family", ""))
	p.gender = str(d.get("gender", ""))
	p.age = float(d.get("age", 0.0))
	p.lifespan = float(d.get("lifespan", 70.0))
	p.alive = bool(d.get("alive", true))
	var n: Dictionary = d.get("needs", {})
	for k in n:
		p.needs[k] = float(n[k])
	p.likes = (d.get("likes", []) as Array).duplicate(true)
	p.dislikes = (d.get("dislikes", []) as Array).duplicate(true)
	var h: Dictionary = d.get("habits", {})
	for k in h:
		p.habits[k] = float(h[k])
	for t in d.get("praise_times", []):
		p.praise_times.append(int(t))
	p.track = str(d.get("track", ""))
	p.level = int(d.get("level", 0))
	p.progress = float(d.get("progress", 0.0))
	p.aptitude = float(d.get("aptitude", 1.0))
	p.work_carry = float(d.get("work_carry", 0.0))  # absent in saves from before it existed
	p.illness = str(d.get("illness", ""))
	var c: Dictionary = d.get("current", {})
	if not c.is_empty():
		p.current = c.duplicate(true)
		for k in ["object_uid", "target_uid"]:
			if p.current.has(k):
				p.current[k] = int(p.current[k])
		if p.current.has("remaining_s"):
			p.current["remaining_s"] = int(p.current["remaining_s"])
	p.last_action = str(d.get("last_action", ""))
	p.last_action_t = int(d.get("last_action_t", 0))
	if d.has("recent_actions"):
		for id in d["recent_actions"]:
			p.recent_actions.append(str(id))
	elif p.last_action != "":  # saves from before it existed: the last action is all we know
		p.recent_actions.append(p.last_action)
	var ch: Dictionary = d.get("childhood", {})  # absent in saves from before it existed
	for k in ch:
		p.childhood[str(k)] = int(ch[k])
	# The rest are absent in saves from before wishes, moods and generations existed.
	var wd: Dictionary = d.get("wish", {})
	if not wd.is_empty():
		p.wish = {"id": str(wd.get("id", "")), "expires_at": int(wd.get("expires_at", 0))}
	p.wish_last = str(d.get("wish_last", ""))
	p.thanks_until = int(d.get("thanks_until", 0))
	p.mood = str(d.get("mood", ""))
	p.mood_low_s = int(d.get("mood_low_s", 0))
	p.mood_ok_s = int(d.get("mood_ok_s", 0))
	p.generation = int(d.get("generation", 0))
	p.cared_at = int(d.get("cared_at", 0))
	# Absent in saves from before births existed.
	p.spouse = int(d.get("spouse", 0))
	p.mother = int(d.get("mother", 0))
	p.father = int(d.get("father", 0))
	p.pregnant_until = int(d.get("pregnant_until", 0))
	p.pregnant_by = int(d.get("pregnant_by", 0))
	# Absent in saves from before sharing existed.
	var ed: Dictionary = d.get("earned", {})
	if not ed.is_empty():
		p.earned_day = int(ed.get("day", -1))
		p.earned = int(ed.get("n", 0))
		p.earned_told = int(ed.get("told", 0))
		p.shared_at = int(ed.get("shared_at", 0))
	var sd: Dictionary = d.get("share", {})
	if not sd.is_empty():
		p.share = {"kind": str(sd.get("kind", "")), "n": int(sd.get("n", 0)), "level": int(sd.get("level", 0))}
	p.look = str(d.get("look", ""))
	# Absent in saves from before asks existed.
	var ad: Dictionary = d.get("ask", {})
	if not ad.is_empty():
		p.ask = {"id": str(ad.get("id", "")), "phase": str(ad.get("phase", "self")), "until": int(ad.get("until", 0))}
	p.ask_last_t = int(d.get("ask_last_t", 0))
	var ag: Dictionary = d.get("ask_again", {})
	for k in ag:
		p.ask_again[str(k)] = int(ag[k])
	return p
