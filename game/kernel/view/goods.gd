class_name Goods
extends RefCounted
## The goods panel's contents ("家当"): everything the household has in store, as cards in
## groups, each saying whether it can be given to the one in the bar now and why not.
## Plain data (`cards`, also for tests); `Panels` draws it.
## Groups, in order: food, medicine, book, clothes, toys, pets (for the animals: their own
## items and the larder stock their care uses), misc (the rest of the larder). An item's group
## comes from the pack's words first ("goods.item.<id>", then "goods.cat.<category>" naming a
## group id), else from what it is: for an animal, a medicine, raises the food need, larder
## stock, raises only the praise need (a toy), else misc.

const GROUPS := ["food", "medicine", "book", "clothes", "toys", "pets", "misc"]
const WORDS := {"goods.all": "全部", "goods.group.food": "吃的", "goods.group.medicine": "药",
	"goods.group.book": "书", "goods.group.clothes": "衣裳", "goods.group.toys": "玩意儿",
	"goods.group.pets": "牲口宠物用的", "goods.group.misc": "杂物", "goods.use": "给{name}用",
	"goods.pick": "选一个人再给", "goods.why.stock": "家里干活自己用", "goods.why.for_pet": "这是给牲口的",
	"goods.why.not_for": "{name}用不上", "goods.why.not_ill": "没病不用吃药", "goods.why.away": "人出门了",
	"goods.why.no_use": "用不上", "goods.new": "新", "goods.none": "家里还什么都没有，去商店看看。",
	"goods.bought": "买了{item}，放进了家当", "goods.look": "看看"}


static func word(strings: ViewStrings, key: String) -> String:
	return strings.t(key) if strings != null and strings.has(key) else str(WORDS[key])


## The items `p`'s wish or waiting ask names (to offer them first).
static func wanted_by(world: World, p: Person) -> Array:
	var out: Array = []
	if p == null:
		return out
	var w := WishSystem.current(world, p)
	if str(w.get("kind", "")) == "item":
		out.append(str(w.get("item", "")))
	var a := AskSystem.current(world, p)
	if str(a.get("kind", "")) == "item":
		out.append_array(a.get("items", []))
	return out


## The group id of item `id`.
static func group_of(pack: Pack, strings: ViewStrings, id: String) -> String:
	var it: Dictionary = pack.items.get(id, {})
	for key in ["goods.item." + id, "goods.cat." + str(it.get("category", ""))]:
		if strings != null and strings.has(key) and GROUPS.has(strings.t(key)):
			return strings.t(key)
	var pet = it.get("pet", {})
	if pet is Dictionary and not (pet as Dictionary).is_empty():
		return "medicine" if bool(pet.get("cures", false)) else "pets"
	if str(it.get("cures", "")) != "":
		return "medicine"
	var stock: Dictionary = it.get("stock", {})
	if not stock.is_empty():
		return "pets" if _feeds_animals(pack, stock) else "misc"
	var needs: Dictionary = it.get("needs", {})
	if needs.has(_food_need(pack)):
		return "food"
	var praise := str(pack.cfg("praise_need"))
	if not needs.is_empty() and needs.keys().all(func(n): return str(n) == praise):
		return "toys"
	return "misc"


## The need that eating a dish raises most ("" when the pack has no meals).
static func _food_need(pack: Pack) -> String:
	var best := ""
	var most := 0.0
	for aid in pack.actions:
		var a: Dictionary = pack.actions[aid]
		if AutonomySystem.target_kind(a) != AutonomySystem.TARGET_DISH:
			continue
		var needs: Dictionary = a["needs"]
		for n in needs:
			if float(needs[n]) > most:
				most = float(needs[n])
				best = str(n)
	return best


## Whether larder stock `stock` is used by an action that looks after an animal.
static func _feeds_animals(pack: Pack, stock: Dictionary) -> bool:
	for aid in pack.actions:
		var a: Dictionary = pack.actions[aid]
		if AutonomySystem.target_kind(a) != AutonomySystem.TARGET_PET:
			continue
		for k in a.get("consumes", {}):
			if stock.has(k):
				return true
	return false


## Every item in store (and the larder stock that comes from an item), as cards in group
## order: {item, name, count, group, stock (bool: larder stock, not given by hand), usable,
## why ("" when usable), fits (only for a medicine given to someone seen ill), wanted}.
## `person` / `pet` is the one in the bar (both null: nobody); `ill` whether the view saw
## `person` fall ill.
static func cards(world: World, strings: ViewStrings, person: Person, pet: Pet, ill := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	var pack := world.pack
	var fitting: Array[String] = IllnessSystem.remedies(world, person) if person != null and ill else ([] as Array[String])
	var wanted := wanted_by(world, person)
	var by_group := {}
	for id in pack.items:
		var it: Dictionary = pack.items[id]
		var stock: Dictionary = it.get("stock", {})
		var count := 0
		if stock.is_empty():
			count = int(world.inventory.get(id, 0))
		else:
			for k in stock:
				count = maxi(count, int(world.stock.get(k, 0)))
		if count <= 0:
			continue
		var c := {"item": str(id), "name": CareTray.short_name(str(it.get("name", id))), "count": count,
			"group": group_of(pack, strings, str(id)), "stock": not stock.is_empty(), "wanted": wanted.has(str(id))}
		c["why"] = _why(world, strings, person, pet, str(id), ill)
		c["usable"] = c["why"] == ""
		if c["usable"] and person != null and str(it.get("cures", "")) != "":
			c["fits"] = fitting.has(str(id))
		if not by_group.has(c["group"]):
			by_group[c["group"]] = []
		by_group[c["group"]].append(c)
	for g in GROUPS:
		for c in by_group.get(g, []):
			out.append(c)
	return out


## Why item `id` cannot be given to the one in the bar now ("" when it can).
static func _why(world: World, strings: ViewStrings, person: Person, pet: Pet, id: String, ill: bool) -> String:
	var it: Dictionary = world.pack.items[id]
	if not (it.get("stock", {}) as Dictionary).is_empty():
		return word(strings, "goods.why.stock")
	var for_pet = it.get("pet", {})
	var pet_item: bool = for_pet is Dictionary and not (for_pet as Dictionary).is_empty()
	if pet != null and pet.home():
		if not pet_item:
			return word(strings, "goods.why.not_for").replace("{name}", pet.given)
		var kinds: Array = for_pet.get("kinds", [])
		if not kinds.is_empty() and not kinds.has(pet.kind):
			return word(strings, "goods.why.not_for").replace("{name}", pet.given)
		if bool(for_pet.get("cures", false)) and not pet.sick:
			return word(strings, "goods.why.not_ill")
		return ""
	if person == null or not person.alive:
		return word(strings, "goods.pick")
	if pet_item:
		return word(strings, "goods.why.for_pet")
	if OutingSystem.away(world, person):
		return word(strings, "goods.why.away")
	if str(it.get("cures", "")) != "":
		return "" if ill else word(strings, "goods.why.not_ill")
	if (it.get("needs", {}) as Dictionary).is_empty() and (it.get("work", {}) as Dictionary).is_empty() \
			and (it.get("childhood", {}) as Dictionary).is_empty():
		return word(strings, "goods.why.no_use")
	return ""


## The groups that have cards, in order.
static func groups(list: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for c in list:
		if not out.has(str(c["group"])):
			out.append(str(c["group"]))
	return out


## The small drawn icon (`NeedBubble.draw_icon`) for an item of group `group`.
static func icon_of(group: String) -> String:
	return {"food": "bowl", "medicine": "pill", "book": "book", "clothes": "cloth", "toys": "ball",
		"pets": "paw", "misc": "box"}.get(group, "box")
