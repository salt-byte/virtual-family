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
## Empty when idle; otherwise {action, object_uid, target_uid, remaining_s}.
var current: Dictionary = {}
var last_action := ""
var last_action_t := 0


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


## Life stage id, from the pack's `stages` thresholds (years).
func stage(pack: Pack) -> String:
	var result := ""
	for s in pack.cfg("stages"):
		if age >= float(s["from"]):
			result = str(s["id"])
	return result


func to_dict() -> Dictionary:
	return {
		"uid": uid, "given": given, "family": family, "gender": gender, "age": age,
		"lifespan": lifespan, "alive": alive, "needs": needs.duplicate(true),
		"likes": likes.duplicate(true), "dislikes": dislikes.duplicate(true),
		"habits": habits.duplicate(true), "praise_times": praise_times.duplicate(true),
		"track": track, "level": level, "progress": progress, "aptitude": aptitude, "work_carry": work_carry,
		"illness": illness, "current": current.duplicate(true),
		"last_action": last_action, "last_action_t": last_action_t,
	}


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
	return p
