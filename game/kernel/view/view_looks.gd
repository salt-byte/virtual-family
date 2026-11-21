class_name ViewLooks
extends RefCounted
## The look a person is DRAWN with (their rig in the house, their portrait in the bar and the
## family strip). Normally that is `Person.look` as the kernel keeps it (`LookSystem`).
##
## Old saves: people made before the pack had looks carry `look == ""`, and the kernel never
## changes that (`LookSystem.ensure` leaves "" alone, and the save is not touched here). The
## view then picks a stand-in, for drawing only:
## - a child (younger than the pack's grown-up age) keeps the stage's own picture (""),
## - a grown-up gets one of the pack's looks (`LookSystem.looks`) of their sex and stage;
##   an old person with no old look of their sex takes one of the grown-up looks (as
##   `LookSystem` keeps a grown-up look then),
## - chosen by a hash of the person's uid, so the same person always gets the same face and
##   rig, across frames, loads and restarts, and nothing in the world or the save changes.
## A pack without looks, or with none for that sex, draws them as before ("").


static func of(p: Person, pack: Pack) -> String:
	if p == null:
		return ""
	if p.look != "" or pack == null:
		return p.look
	return fallback(p, pack)


## The stand-in look for `p` as if their own were "" (see the class notes).
static func fallback(p: Person, pack: Pack) -> String:
	var all := LookSystem.looks(pack)
	if all.is_empty():
		return ""
	var adult := LivelihoodSystem.adult_age(pack)
	if adult >= 0.0 and p.age < adult:
		return ""
	var pool := _pool(all, p.gender, p.stage(pack))
	if pool.is_empty():
		pool = _pool(all, p.gender, "adult")
	if pool.is_empty():
		return ""
	return str(pool[posmod(hash("look|%d" % p.uid), pool.size())])


static func _pool(all: Array, sex: String, stage: String) -> Array:
	var out: Array = []
	for e in all:
		if str(e["sex"]) == sex and str(e["stage"]) == stage:
			out.append(str(e["id"]))
	return out
