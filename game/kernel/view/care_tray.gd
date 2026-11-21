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
##   only while they are seen to be ill, and which one fits is still the player's guess),
##   "给他用" / "给她用".
## An item button can also be dragged onto a person or an animal in the house.
## The choice is made here (`options`, plain data, also for tests); the bar carries it out.

signal chosen(entry: Dictionary)
## An item button let go away from the tray: `screen` is where.
signal dropped(entry: Dictionary, screen: Vector2)

const WORDS := {"care.feed": "喂它", "care.use_pet": "给它用", "care.use_m": "给他用", "care.use_f": "给她用",
	"care.call": "叫人来喂", "care.shop": "去{shop}买", "care.stock": "存 {n}", "care.nobody": "一时没人腾得出手",
	"care.head": "家里有的"}
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
## own knowledge, from the "fell ill" event), so the medicines in store are offered. Each is {kind: "use" | "stock" | "call" | "shop",
## text, name, count, item, stock, tab, person, pet}.
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
		out.append({"kind": "use", "item": str(id), "name": short_name(str(it2.get("name", id))), "count": count3,
			"text": word(strings, "care.use_f" if person.gender == "female" else "care.use_m"), "person": person.uid})
	return out


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
		_row.add_child(head)
		for e in entries:
			_row.add_child(_entry_node(e))
	var content := _row.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(minf(content.x, maxf(max_width - 20.0, 80.0)), content.y)


func _entry_node(e: Dictionary) -> Control:
	var kind := str(e["kind"])
	if kind == "stock":
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", ViewWidgets.chip_style(ViewWidgets.PALE, Color(0, 0, 0, 0)))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := Label.new()
		l.text = "%s %s" % [e["name"], e["text"]]
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
	else:
		b.text = str(e["text"])
		if kind == "call":
			ViewWidgets.round_button(b, ViewWidgets.CREAM, ViewWidgets.WOOD)
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
