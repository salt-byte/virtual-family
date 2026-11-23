class_name CareTray
extends PanelContainer
## What the house has in store for the one in the bar, as quick buttons in a tray just above
## the bar's right end (the market panel's last tab, the things in store, was the only way
## before, and nobody found it):
## - an animal (pet or livestock): each item in store it can be given (`items.json` `pet`,
##   its kinds), with the count, "喂它" for food and "给它用" for the rest (the animal
##   medicine only while it is ill); the larder stock its care actions use (小米, 谷糠: the
##   family feeds that, so it is shown as how much is left); "叫人来喂", which sends the
##   nearest free family member to look after it (as if dropped on it); and "去<market>买",
##   which opens the market on the tab where its food is sold, when nothing for it is in store;
## - a person: each item in store that does them good (snacks, clothes, books; the medicines
##   only while they are seen to be ill, each marked "对症" or "不对症" as the kernel's
##   `IllnessSystem.remedies` says: the view never reads the illness), "给他用" / "给她用";
##   while they are seen to be ill also "叫<name>来瞧" (a family member in the livelihood
##   that treats, as if dropped on them), the stock that treating uses, and "请<visitor>"
##   (the market's doctor service, with its price now), or how far the visitor has got.
## An item button can also be dragged onto a person or an animal in the house.
## The choice is made here (`options`, plain data, also for tests); the bar carries it out.

signal chosen(entry: Dictionary)
## An item button let go away from the tray: `screen` is where.
signal dropped(entry: Dictionary, screen: Vector2)

const WORDS := {"care.feed": "喂它", "care.use_pet": "给它用", "care.use_m": "给他用", "care.use_f": "给她用",
	"care.call": "叫人来喂", "care.shop": "去{shop}买", "care.stock": "存 {n}", "care.nobody": "一时没人腾得出手",
	"care.head": "家里有的", "care.doctor": "请{visitor} · {money}", "care.doctor_wait": "{visitor}在路上了",
	"care.doctor_here": "{visitor}正在瞧", "care.treat": "叫{name}来瞧", "care.fits": "对症", "care.unfit": "不对症"}
## Pixels the pointer must move with an item held before it counts as a drag.
const DRAG_FROM := 8.0

var _row: HBoxContainer
var _scroll: ScrollContainer
var _sig := ""
var _entries: Array[Dictionary] = []
var _buttons: Array[Button] = []
## The item being dragged out of the tray: its entry, where the press began, the floating label.
var _held := {}
var _held_from := Vector2.ZERO
var _dragging := false
var _ghost: Label


static func word(strings: ViewStrings, key: String) -> String:
	return strings.t(key) if strings != null and strings.has(key) else str(WORDS[key])


## An item's name without its leading measure word ("一根猪棒骨" -> "猪棒骨").
static func short_name(name: String) -> String:
	if name.length() >= 4 and name.begins_with("一"):
		return name.substr(2)
	return name


## The quick choices for `person` or `pet` (one of them null), in order: items to use, larder
## stock (shown, not pressed), "call", "shop". `ill`: the person is seen to be ill (the view's
## own knowledge, from the "fell ill" event), so the medicines in store are offered (with
## `fits`) and the stock treating uses; put first, "doctor" (`service`; "doctor_wait"
## while one is on the way: shown, not pressed) and "treat" (a healer of the family:
## `healer`). Each is
## {kind: "use" | "stock" | "call" | "shop" | "treat" | "doctor" | "doctor_wait", text, name,
## count, item, stock, tab, person, pet, fits, healer, service}.
static func options(world: World, person: Person, pet: Pet, strings: ViewStrings, ill := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	var pack := world.pack
	if pet != null:
		if not pet.home():
			return out
		var shop_item := ""
		for id in pack.items:
			var it: Dictionary = pack.items[id]
			var t = it.get("pet", {})
			if not t is Dictionary or (t as Dictionary).is_empty():
				continue
			var kinds: Array = t.get("kinds", [])
			if not kinds.is_empty() and not kinds.has(pet.kind):
				continue
			var cure := bool(t.get("cures", false))
			if not cure and shop_item == "":
				shop_item = str(id)
			var count := int(world.inventory.get(id, 0))
			if count <= 0 or (cure and not pet.sick):
				continue
			var food := (t.get("needs", {}) as Dictionary).has(PetSystem.role(pack, "food_need")) and not cure
			out.append({"kind": "use", "item": str(id), "name": short_name(str(it.get("name", id))), "count": count,
				"text": word(strings, "care.feed" if food else "care.use_pet"), "pet": pet.uid})
		var cares := false
		var stocks: Array = []
		for aid in pack.actions:
			var a: Dictionary = pack.actions[aid]
			if AutonomySystem.target_kind(a) != AutonomySystem.TARGET_PET:
				continue
			var t2: Dictionary = a.get("pet", {})
			var kinds2: Array = t2.get("kinds", [])
			if not kinds2.is_empty() and not kinds2.has(pet.kind):
				continue
			cares = true
			for k in a.get("consumes", {}):
				if not stocks.has(str(k)):
					stocks.append(str(k))
		var stocked := false
		for k in stocks:
			var src := _stock_item(pack, k)
			if src == "":
				continue   # nothing to buy it with (table scraps): not the player's to stock
			var count2 := int(world.stock.get(k, 0))
			stocked = stocked or count2 > 0
			if shop_item == "":
				shop_item = src
			out.append({"kind": "stock", "stock": k, "item": src, "count": count2,
				"name": short_name(str(pack.items.get(src, {}).get("name", k))),
				"text": word(strings, "care.stock").replace("{n}", str(count2))})
		if cares:
			out.append({"kind": "call", "text": word(strings, "care.call"), "pet": pet.uid})
		var usable := out.any(func(e): return e["kind"] == "use")
		if not usable and not stocked and shop_item != "":
			var market := strings.t("btn.shop") if strings != null else ""
			out.append({"kind": "shop", "text": word(strings, "care.shop").replace("{shop}", market), "item": shop_item,
				"tab": str(pack.items[shop_item].get("market", ""))})
		return out
	if person == null or not person.alive or OutingSystem.away(world, person):
		return out
	var fitting: Array[String] = IllnessSystem.remedies(world, person) if ill else ([] as Array[String])
	for id in pack.items:
		var it2: Dictionary = pack.items[id]
		var count3 := int(world.inventory.get(id, 0))
		if count3 <= 0:
			continue
		var t3 = it2.get("pet", {})
		if t3 is Dictionary and not (t3 as Dictionary).is_empty():
			continue
		var cures := str(it2.get("cures", ""))
		if cures != "" and not ill:
			continue
		if cures == "" and (it2.get("needs", {}) as Dictionary).is_empty():
			continue
		var use := word(strings, "care.use_f" if person.gender == "female" else "care.use_m")
		var e := {"kind": "use", "item": str(id), "name": short_name(str(it2.get("name", id))), "count": count3,
			"text": use, "person": person.uid}
		if cures != "":
			e["fits"] = fitting.has(str(id))
			e["text"] = "%s · %s" % [word(strings, "care.fits" if e["fits"] else "care.unfit"), use]
		out.append(e)
	if ill:
		_sick_options(out, world, person, strings)
		# The family's healer, then the doctor, first: the tray scrolls, and these are the sure
		# ways to have them seen to.
		for kind in [["treat"], ["doctor", "doctor_wait"]]:
			for k in out.size():
				if str(out[k]["kind"]) in kind:
					out.push_front(out.pop_at(k))
					break
	return out


## The ways to have a sick person seen to: a healer of the family, the stock that takes, and
## the doctor service (see `options`).
static func _sick_options(out: Array[Dictionary], world: World, person: Person, strings: ViewStrings) -> void:
	var pack := world.pack
	var healer := healer_for(world, person)
	if healer != null:
		out.append({"kind": "treat", "healer": healer.uid, "person": person.uid,
			"text": word(strings, "care.treat").replace("{name}", strings.person_name(healer) if strings != null else healer.given)})
	var stocks: Array = []
	for aid in (pack.actions if healer != null else {}):
		var a: Dictionary = pack.actions[aid]
		if IllnessSystem.treats(a) and _in_family_track(world, str(a.get("work", {}).get("track", ""))):
			for k in a.get("consumes", {}):
				if not stocks.has(str(k)):
					stocks.append(str(k))
	for k in stocks:
		var src := _stock_item(pack, k)
		if src == "":
			continue
		var n := int(world.stock.get(k, 0))
		out.append({"kind": "stock", "stock": k, "item": src, "count": n,
			"name": short_name(str(pack.items.get(src, {}).get("name", k))),
			"text": word(strings, "care.stock").replace("{n}", str(n))})
	var sid := ServiceSystem.first_of(pack, "doctor")
	if sid == "":
		return
	var visitor := strings.visitor_name(world, sid) if strings != null else ""
	if not world.doctor.is_empty():
		if int(world.doctor.get("person", -1)) == person.uid:
			var key := "care.doctor_here" if str(world.doctor.get("phase", "")) == "examining" else "care.doctor_wait"
			out.append({"kind": "doctor_wait", "service": sid, "person": person.uid, "count": 1,
				"name": visitor, "text": word(strings, key).replace("{visitor}", visitor)})
		return
	var money := strings.t("money").replace("{n}", str(ServiceSystem.price(world, sid))) if strings != null \
		else str(ServiceSystem.price(world, sid))
	out.append({"kind": "doctor", "service": sid, "person": person.uid,
		"text": word(strings, "care.doctor").replace("{visitor}", visitor).replace("{money}", money)})


## A member of the family at home who could treat `person` now (an action that `treats`
## they can start, short of the stock it uses), the idle first; null for nobody.
static func healer_for(world: World, person: Person) -> Person:
	var best: Person = null
	for q in world.people:
		if q == person or not q.alive or OutingSystem.away(world, q):
			continue
		for aid in world.pack.actions:
			if not IllnessSystem.treats(world.pack.actions[aid]):
				continue
			var why := AutonomySystem.can_do(world, q, str(aid), -1)
			if why in ["", "no_stock", "no_target"]:
				if best == null or (not best.current.is_empty() and q.current.is_empty()):
					best = q
				break
	return best


## Whether someone of the family alive and at home follows livelihood `track`.
static func _in_family_track(world: World, track: String) -> bool:
	return track != "" and world.people.any(func(q: Person): return q.alive and q.track == track)


## The item whose purchase fills larder stock `k` ("" for none).
static func _stock_item(pack: Pack, k: String) -> String:
	for id in pack.items:
		if (pack.items[id].get("stock", {}) as Dictionary).has(k):
			return str(id)
	return ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := ViewWidgets.chip_style(Color(ViewWidgets.CREAM, 0.94), ViewWidgets.WOOD)
	st.set_corner_radius_all(14)
	st.content_margin_left = 10
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	add_theme_stylebox_override("panel", st)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_scroll.add_child(_row)


## Shows `entries` (from `options`); `max_width` the room it may take.
func show_entries(entries: Array[Dictionary], strings: ViewStrings, max_width: float) -> void:
	var sig := str(entries)
	if sig != _sig:
		_sig = sig
		_entries = entries
		_buttons.clear()
		for c in _row.get_children():
			_row.remove_child(c)
			c.queue_free()
		var head := Label.new()
		head.text = word(strings, "care.head")
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", ViewWidgets.MUTED)
		head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.visible = entries.any(func(e): return e["kind"] in ["use", "stock"])
		var at := entries.size()  # the heading goes before what is in store
		for k in entries.size():
			if str(entries[k]["kind"]) in ["use", "stock"]:
				at = k
				break
		for k in entries.size():
			if k == at:
				_row.add_child(head)
			_row.add_child(_entry_node(entries[k]))
		if head.get_parent() == null:
			_row.add_child(head)
	var content := _row.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(minf(content.x, maxf(max_width - 20.0, 80.0)), content.y)


func _entry_node(e: Dictionary) -> Control:
	var kind := str(e["kind"])
	if kind == "stock" or kind == "doctor_wait":
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", ViewWidgets.chip_style(ViewWidgets.PALE, Color(0, 0, 0, 0)))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := Label.new()
		l.text = "%s %s" % [e["name"], e["text"]] if kind == "stock" else str(e["text"])
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", ViewWidgets.INK if int(e["count"]) > 0 else ViewWidgets.ACCENT)
		chip.add_child(l)
		return chip
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size.y = 30
	if kind == "use":
		b.text = "%s ×%d · %s" % [e["name"], int(e["count"]), e["text"]]
		ViewWidgets.small_button(b)
		b.mouse_default_cursor_shape = Control.CURSOR_DRAG
		b.gui_input.connect(_item_input.bind(e, b))
		if e.has("fits"):
			if bool(e["fits"]):
				b.add_theme_color_override("font_color", ViewWidgets.ACCENT)
			else:
				b.modulate = Color(1, 1, 1, 0.5)  # greyed: it will not help, though it can still be given
	else:
		b.text = str(e["text"])
		if kind == "call" or kind == "treat":
			ViewWidgets.round_button(b, ViewWidgets.CREAM, ViewWidgets.WOOD)
		elif kind == "doctor":
			ViewWidgets.round_button(b, ViewWidgets.ACCENT, ViewWidgets.CREAM)
		else:
			ViewWidgets.round_button(b, ViewWidgets.CREAM, ViewWidgets.ACCENT)
	b.set_meta("entry", e)
	b.pressed.connect(func():
		if not _dragging:
			chosen.emit(e))
	_buttons.append(b)
	return b


## Pressing an item and moving the pointer drags it; letting go away from the tray drops it
## where the pointer is (the bar then uses it on whoever is there).
func _item_input(ev: InputEvent, e: Dictionary, b: Button) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_held = e
			_held_from = b.get_global_transform() * ev.position
			_dragging = false
		else:
			var at: Vector2 = b.get_global_transform() * ev.position
			var was := _dragging
			_end_drag()
			if was and not get_global_rect().has_point(at):
				dropped.emit(e, at)
	elif ev is InputEventMouseMotion and not _held.is_empty():
		var at2: Vector2 = b.get_global_transform() * ev.position
		if not _dragging and at2.distance_to(_held_from) >= DRAG_FROM:
			_dragging = true
			_ghost = Label.new()
			_ghost.text = str(e["name"])
			_ghost.add_theme_font_size_override("font_size", 15)
			_ghost.add_theme_color_override("font_color", ViewWidgets.INK)
			_ghost.add_theme_color_override("font_outline_color", ViewWidgets.CREAM)
			_ghost.add_theme_constant_override("outline_size", 6)
			_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ghost.top_level = true
			add_child(_ghost)
		if _ghost != null:
			_ghost.global_position = at2 + Vector2(10, -24)


func _end_drag() -> void:
	_held = {}
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	# The button's own `pressed` comes after the release: let it see the drag first.
	set_deferred("_dragging", false)


## The entries on show; for tests.
func entries() -> Array[Dictionary]:
	return _entries


## The button texts on show, in order; for tests.
func texts() -> Array[String]:
	var out: Array[String] = []
	for b in _buttons:
		out.append(b.text)
	return out


## Presses the first entry of `kind` (and `item` when given); false when none is on show.
func press(kind: String, item := "") -> bool:
	for e in _entries:
		if e["kind"] == kind and (item == "" or str(e.get("item", "")) == item):
			chosen.emit(e)
			return true
	return false
