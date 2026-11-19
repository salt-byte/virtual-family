class_name FeelingSystem
extends RefCounted
## What a person feels right now, in a few words for the status bar: driven by what they are
## doing this moment and what just happened, so it changes within seconds to minutes (the
## needs' own words change over hours). The words come from the pack's `feelings`: a list of
## rules tried in order, the first whose conditions all hold giving its `text` (a rule with
## no conditions always holds). Conditions:
## - `doing`: [sorts] the current action is any of: "work", "eats" (eats a dish), "slow" (a `slow` action: sleep), "cleans", "picks",
##   "tends", "pet", "daily", "flavor", "trouble"; "idle" for no action
## - `actions`: [ids] the current action is one of these
## - `gains`: need id; the current action raises that need
## - `led`: true / false; the player brought them to what they are doing
## - `just`: [ids] with `within_s` (real seconds, default 120): one of these finished that
##   recently
## - `need_below`: {need: value} every one of them below its value
## - `mood`: "sad" / "depressed" / ""; `sick`, `thanking`, `sharing`, `pregnant`, `wish`:
##   true / false
## Pure reading: draws no randomness and changes nothing. A pack without `feelings` gives "".
## Needs may name `warn_below`: their word is a warning only below it (see `warnings`).


static func now(world: World, p: Person) -> String:
	var rules = world.pack.cfg("feelings")
	if not rules is Array or p == null or not p.alive:
		return ""
	for r in rules:
		if r is Dictionary and holds(world, p, r):
			return str(r.get("text", ""))
	return ""


## Whether every condition of `rule` holds for `p` now.
static func holds(world: World, p: Person, rule: Dictionary) -> bool:
	var a: Dictionary = {}
	a = world.pack.actions.get(str(p.current.get("action", "")), {})
	if rule.has("doing"):
		var any := false
		for sort in rule["doing"]:
			if _is(world, a, str(sort)):
				any = true
				break
		if not any:
			return false
	if rule.has("actions") and (a.is_empty() or not (rule["actions"] as Array).has(a["id"])):
		return false
	if rule.has("gains"):
		if a.is_empty() or float((a["needs"] as Dictionary).get(str(rule["gains"]), 0.0)) <= 0.0:
			return false
	if rule.has("led") and bool(rule["led"]) != bool(p.current.get("led", false)):
		return false
	if rule.has("just"):
		var within := int(rule.get("within_s", 120))
		if not ((rule["just"] as Array).has(p.last_action) and world.now - p.last_action_t <= within):
			return false
	if rule.has("need_below"):
		var nb: Dictionary = rule["need_below"]
		for n in nb:
			if float(p.needs.get(n, 100.0)) >= float(nb[n]):
				return false
	if rule.has("mood") and p.mood != str(rule["mood"]):
		return false
	if rule.has("sick") and bool(rule["sick"]) != (p.illness != ""):
		return false
	if rule.has("thanking") and bool(rule["thanking"]) != p.thanking(world.now):
		return false
	if rule.has("sharing") and bool(rule["sharing"]) != (ShareSystem.text(world, p) != ""):
		return false
	if rule.has("pregnant") and bool(rule["pregnant"]) != p.pregnant():
		return false
	if rule.has("wish") and bool(rule["wish"]) != (not p.wish.is_empty()):
		return false
	return true


static func _is(world: World, a: Dictionary, sort: String) -> bool:
	if a.is_empty():
		return sort == "idle"
	match sort:
		"work":
			return not (a["work"] as Dictionary).is_empty()
		"eats":
			return not (a.get("eats", []) as Array).is_empty()
		"slow":
			return bool(a.get("slow", false))
		"cleans":
			return str(a["cleans"]) != ""
		"picks":
			return bool(a["picks"])
		"tends":
			return not (a.get("tends", {}) as Dictionary).is_empty()
		"pet":
			return not (a.get("pet", {}) as Dictionary).is_empty()
		"daily", "flavor", "trouble":
			return str(a.get("kind", "")) == sort
	return false


## The words of `p`'s needs that are a warning now, in pack order: a need's label word when
## its value is below the need's `warn_below` (without one: below where its last label, the
## fine one, starts).
static func warnings(world: World, p: Person) -> Array[String]:
	var out: Array[String] = []
	var words := p.status(world.pack)
	for nid in world.pack.needs:
		if not words.has(nid) or not p.needs.has(nid):
			continue
		var n: Dictionary = world.pack.needs[nid]
		var line := float(n.get("warn_below", -1.0))
		if line < 0.0:
			var labels: Array = n.get("labels", [])
			line = float(labels[-2]["below"]) if labels.size() >= 2 else 0.0
		if float(p.needs[nid]) < line:
			out.append(str(words[nid]))
	return out
