class_name Pet
extends RefCounted
## One animal of the household (a pack's optional pets.json names the kinds; see
## `PetSystem`). Plain data plus a few read helpers; the systems mutate it.

var uid := 0
## The pets.json kind id.
var kind := ""
var given := ""
var age := 0.0
var lifespan := 10.0
## False once it has died (or never came back); it stays in the list for the family record.
var alive := true
## "home" or "away" (ran off; it may come back).
var state := "home"
## pet need id -> 0..100 (the pack's `pets.needs`)
var needs: Dictionary = {}
var sick := false
## Empty when idle; otherwise {action, remaining_s} and, when the action happens somewhere,
## `room` or `object_uid`, and `follow` (the person it trails after).
var current: Dictionary = {}
var last_action := ""
## Action id -> `now` it last finished, for the actions that may only come every so often
## (`every_hours`).
var done_at: Dictionary = {}
## The wish it shows right now: {} for none, else {id, expires_at} (an id from its kind's
## `wishes`).
var wish: Dictionary = {}
var wish_last := ""
## Not saved (rebuilt on load): uid of the person looking after it now, or -1. Checked
## against that person's current action before it counts (see `PetSystem.held`).
var held_by := -1
## `now` until which it shows its joy at a wish come true (0: not).
var thanks_until := 0
## Seconds its food need and its fondness have stayed at or below the pack's run line.
var hungry_s := 0
var lonely_s := 0
## `now` it ran off (0 while at home).
var away_since := 0
## "bought" or "stray": how it came to the house; `came_at` when.
var how := ""
var came_at := 0
## For a pet that is gone: why ("old_age", "illness", "lost") and when.
var cause := ""
var died_at := 0
## Livestock (see `LivestockSystem`): how heavy it is (0 for a kind that keeps no weight), and
## `now` when the young it carries come (0: none on the way).
var weight := 0.0
var young_at := 0


## True while it is at home and alive.
func home() -> bool:
	return alive and state == "home"


## Status words: need id -> the label that applies (the needs of `pets.needs` with labels).
func status(pack: Pack) -> Dictionary:
	var out := {}
	for n in PetSystem.need_list(pack):
		var labels: Array = n.get("labels", [])
		var nid := str(n.get("id", ""))
		if labels.is_empty() or not needs.has(nid):
			continue
		var v := float(needs[nid])
		var text := str(labels[-1]["text"])
		for l in labels:
			if v < float(l["below"]):
				text = str(l["text"])
				break
		out[nid] = text
	return out


func to_dict() -> Dictionary:
	return {
		"uid": uid, "kind": kind, "given": given, "age": age, "lifespan": lifespan, "alive": alive,
		"state": state, "needs": needs.duplicate(true), "sick": sick, "current": current.duplicate(true),
		"last_action": last_action, "done_at": done_at.duplicate(), "wish": wish.duplicate(true), "wish_last": wish_last,
		"thanks_until": thanks_until, "hungry_s": hungry_s, "lonely_s": lonely_s,
		"away_since": away_since, "how": how, "came_at": came_at, "cause": cause, "died_at": died_at,
		"weight": weight, "young_at": young_at,
	}


## Rebuilds a Pet; tolerates JSON round trips where every number is a float.
static func from_dict(d: Dictionary) -> Pet:
	var p := Pet.new()
	p.uid = int(d.get("uid", 0))
	p.kind = str(d.get("kind", ""))
	p.given = str(d.get("given", ""))
	p.age = float(d.get("age", 0.0))
	p.lifespan = float(d.get("lifespan", 10.0))
	p.alive = bool(d.get("alive", true))
	p.state = str(d.get("state", "home"))
	var n: Dictionary = d.get("needs", {})
	for k in n:
		p.needs[str(k)] = float(n[k])
	p.sick = bool(d.get("sick", false))
	var c: Dictionary = d.get("current", {})
	if not c.is_empty():
		p.current = c.duplicate(true)
		for k in ["remaining_s", "object_uid", "follow", "mess"]:
			if p.current.has(k):
				p.current[k] = int(p.current[k])
	p.last_action = str(d.get("last_action", ""))
	var da: Dictionary = d.get("done_at", {})
	for k in da:
		p.done_at[str(k)] = int(da[k])
	var wd: Dictionary = d.get("wish", {})
	if not wd.is_empty():
		p.wish = {"id": str(wd.get("id", "")), "expires_at": int(wd.get("expires_at", 0))}
	p.wish_last = str(d.get("wish_last", ""))
	p.thanks_until = int(d.get("thanks_until", 0))
	p.hungry_s = int(d.get("hungry_s", 0))
	p.lonely_s = int(d.get("lonely_s", 0))
	p.away_since = int(d.get("away_since", 0))
	p.how = str(d.get("how", ""))
	p.came_at = int(d.get("came_at", 0))
	p.cause = str(d.get("cause", ""))
	p.died_at = int(d.get("died_at", 0))
	p.weight = float(d.get("weight", 0.0))  # absent before livestock
	p.young_at = int(d.get("young_at", 0))
	return p
