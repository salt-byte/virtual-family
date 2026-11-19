class_name Panels
extends CanvasLayer
## Pop-up panels above the HUD: the shop (goods, and what the household holds), goals and
## collection, and the family list. One at a time, centred, closed by `btn.close` or Esc.
## Reads the World; everything it changes goes through session commands.

const LAYER := 5
const PANEL_WIDTH := 560.0
const BODY_HEIGHT := 340.0
const MARGIN := 24.0
const DONE_MARK := "✓ "
const UNKNOWN := "？"

var main: Main
var session: GameSession

var _root: Control
var _card: PanelContainer
var _box: VBoxContainer
var _buttons: Dictionary = {}  # id -> Button
var _kind := ""
var _tab := ""
var _signature := ""
## In the family panel: uid of the person whose livelihood is being changed (-1: none).
var _changing := -1


func setup(m: Main) -> void:
	main = m
	session = m.session
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.theme = ViewWidgets.panel_theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.16, 0.11, 0.07, 0.4)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	_card = panel
	panel.custom_minimum_size.x = PANEL_WIDTH
	panel.add_theme_stylebox_override("panel", ViewWidgets.card_style(MARGIN))
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)


## One of "", "shop", "ledger", "family", "stories", "go_out" (where the selected person
## could be sent).
func opened() -> String:
	return _kind


## True while a panel covers the house.
func blocks_input() -> bool:
	return _kind != ""


## Opens a panel; ignored for an unknown name, while an overlay shows or outside a running game.
func open(what: String) -> void:
	if not what in ["shop", "ledger", "family", "stories", "go_out"]:
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
		return
	if what == "go_out":
		var p := w.person(main.selected)
		if p == null or not p.alive or main.selected_pet >= 0:
			return
	_kind = what
	_changing = -1
	_tab = _tabs()[0] if not _tabs().is_empty() else ""
	_signature = ""
	refresh()


func close() -> void:
	if _kind == "":
		return
	_kind = ""
	_tab = ""
	_changing = -1
	_signature = ""
	_rebuild()


func _tabs() -> Array:
	match _kind:
		"shop":
			var ids := []
			for t in _market_tabs(session.world):
				ids.append(t["id"])
			ids.append("tab.inventory")
			return ids
		"ledger":
			return ["tab.goals", "tab.collection"]
	return []


func _unhandled_key_input(event: InputEvent) -> void:
	if _kind != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## All text of the open panel, joined with newlines; for tests.
func text() -> String:
	var parts: Array[String] = []
	_collect(_box, parts)
	return "\n".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label or c is Button:
			out.append(c.text)
		_collect(c, out)


func has_button(id: String) -> bool:
	return _buttons.has(id)


func is_disabled(id: String) -> bool:
	return not _buttons.has(id) or (_buttons[id] as Button).disabled


func button_node(id: String) -> Button:
	return _buttons.get(id)


## Test entry point and button handler; unknown or disabled ids do nothing. In the shop
## "tab.items" stands for the first goods tab and "tab.pets" for the one with the animals.
func press(id: String) -> void:
	if _kind == "shop" and id in ["tab.items", "tab.pets"]:
		id = _market_tab_for(id)
	if is_disabled(id):
		return
	if id == "btn.close":
		close()
	elif id in _tabs():
		_tab = id
		_signature = ""
		refresh()
	elif id.begins_with("go:"):
		var r := session.command({"type": "go_out", "person": main.selected, "action": id.substr(3)})
		if r.get("ok", false):
			close()
		else:
			refresh()
	elif id.begins_with("buy:"):
		session.command({"type": "buy", "item": id.substr(4)})
		refresh()
	elif id.begins_with("use:"):
		if main.selected_pet >= 0:
			session.command({"type": "use_item", "item": id.substr(4), "pet": main.selected_pet})
		else:
			session.command({"type": "use_item", "item": id.substr(4), "person": main.selected})
		refresh()
	elif id.begins_with("buy_pet:"):
		session.command({"type": "buy_pet", "kind": id.substr(8)})
		refresh()
	elif id.begins_with("pet:"):
		close()
		main.select_pet(int(id.substr(4)))
	elif id.begins_with("person:"):
		main.select(int(id.substr(7)))
		close()
	elif id == "stray":
		close()
		main.overlays.open_stray()
	elif id == "proposal":
		close()
		main.overlays.open_proposal()
	elif id == "go_arrange":
		close()
		main.arrange.enter()
	elif id.begins_with("change:"):
		_changing = int(id.substr(7))
		refresh()
	elif id == "change.cancel":
		_changing = -1
		refresh()
	elif id.begins_with("track:"):
		session.command({"type": "change_track", "person": _changing, "track": id.substr(6)})
		_changing = -1
		refresh()


## Rebuilds only when something the panel shows has changed.
func refresh() -> void:
	if _kind == "":
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
		close()
		return
	var sig := _kind + "|" + _tab + "|" + _data_signature(w)
	if sig == _signature:
		return
	_signature = sig
	_rebuild()


func _data_signature(w: World) -> String:
	var s := session.strings
	match _kind:
		"shop":
			var sel := w.person(main.selected)
			var total := 0
			for k in w.stock:
				total += int(w.stock[k])
			var wishes := ""
			for p in w.people:
				if p.alive:
					wishes += str(p.wish)
			var pets := ""
			for pet in w.pets:
				pets += "%d%s%s" % [pet.uid, pet.state, str(pet.wish)]
			return "%d|%d|%s|%s|%s|%d|%s|%d|%s" % [w.money, total, str(w.inventory), s.person_name(sel) if sel != null and sel.alive else "", wishes,
				main.selected_pet, pets, w.objects.size(), w.festival]
		"go_out":
			var who := w.person(main.selected)
			if who == null:
				return ""
			var parts: Array[String] = [str(who.uid)]
			for o in OutingSystem.options(w, who):
				parts.append("%s:%s" % [o["action"], o["why"]])
			return "|".join(parts)
		"stories":
			return str(w.stories)
		"ledger":
			return "%s|%s" % [str(w.goals_done), str(w.collection)]
		"family":
			var parts: Array[String] = [str(w.pet_offer), str(w.proposals.size()), str(_changing), str(BirthSystem.blocked(w))]
			for p in w.people:
				if p.alive:
					parts.append("%d:%s:%s:%s:%d" % [p.uid, s.person_line(p, w), s.status_line(p, w), s.job_line(p), p.spouse])
				else:
					parts.append("%d:dead" % p.uid)
			for pet in w.pets:
				parts.append("p%d:%s:%s:%s" % [pet.uid, pet.state, str(pet.alive), s.pet_status(pet, w)])
			return "|".join(parts)
	return ""


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_root.visible = _kind != ""
	if _kind == "":
		return
	var s := session.strings
	var w := session.world
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := ViewWidgets.label(s.t("btn." + _kind))
	if _kind == "go_out" and w.person(main.selected) != null:
		title.text = s.t("title.go_out").replace("{name}", s.person_name(w.person(main.selected)))
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	if _kind == "shop":
		head.add_child(ViewWidgets.label(s.t("money").replace("{n}", str(w.money))))
	_button("btn.close", s.t("btn.close"), head)
	var tabs := _tabs()
	if not tabs.is_empty():
		# Tabs wrap onto a second line rather than widen the card.
		var row := HFlowContainer.new()
		row.custom_minimum_size.x = PANEL_WIDTH - 2.0 * MARGIN
		_box.add_child(row)
		row.add_theme_constant_override("h_separation", 5)
		row.add_theme_constant_override("v_separation", 5)
		for t in tabs:
			var tb := _button(t, _tab_name(t), row)
			ViewWidgets.small_button(tb)
			tb.custom_minimum_size.y = 30
			tb.disabled = (t == _tab)
			if t == _tab:
				# The open tab: the wood fill reads as "you are here", not as "can't".
				var on := ViewWidgets.chip_style(ViewWidgets.WOOD, ViewWidgets.INK)
				on.set_corner_radius_all(9)
				on.content_margin_left = 8
				on.content_margin_right = 8
				tb.add_theme_stylebox_override("disabled", on)
				tb.add_theme_color_override("font_disabled_color", ViewWidgets.CREAM)
	var scroll := ScrollContainer.new()
	# Two lines of tabs take a little of the list's height so the card stays the same size.
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 2.0 * MARGIN, BODY_HEIGHT - (40.0 if tabs.size() > 4 else 0.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if _kind == "shop" and _tab.begins_with("tab.m:"):
		_fill_market(list, w, _market_tabs(w)[int(_tab.substr(6))])
		return
	match _tab if not _kind in ["family", "stories", "go_out"] else _kind:
		"go_out":
			_fill_go_out(list, w)
		"tab.inventory":
			_fill_inventory(list, w)
		"tab.goals":
			_fill_goals(list, w)
		"tab.collection":
			_fill_collection(list, w)
		"family":
			_fill_family(list, w)
		"stories":
			_fill_stories(list, w)


## The goods tabs of the market, in order: {id "tab.m:<i>", name, cats (item categories it
## holds), pets (the animals for sale are here)}.
## HOOK (branch market): once the kernel lists its catalogue by category (with services
## such as adopting again or doubled time), build the tabs from that list here. Until then
## the pack's ui.json names the tabs (`market.tabs`, comma separated) and files each item
## category under one (`market.cat.<category>`, `market.cat.pets` for the animals); with
## none of that, every item category is a tab of its own.
func _market_tabs(w: World) -> Array[Dictionary]:
	var s := session.strings
	var order: Array[String] = []
	var tabs := {}
	if s.has("market.tabs"):
		for n in s.t("market.tabs").split(","):
			if n.strip_edges() != "":
				order.append(n.strip_edges())
	var place := func(tab_name: String) -> Dictionary:
		if not tabs.has(tab_name):
			tabs[tab_name] = {"name": tab_name, "cats": [], "pets": false}
			if not tab_name in order:
				order.append(tab_name)
		return tabs[tab_name]
	for id in w.pack.items:
		var cat := str(w.pack.items[id].get("category", ""))
		var tab_name := s.t("market.cat." + cat) if s.has("market.cat." + cat) else (cat if cat != "" else s.t("tab.items"))
		var t: Dictionary = place.call(tab_name)
		if not cat in t["cats"]:
			t["cats"].append(cat)
	if PetSystem.enabled(w.pack):
		place.call(s.t("market.cat.pets") if s.has("market.cat.pets") else s.t("shop.pets"))["pets"] = true
	var out: Array[Dictionary] = []
	for i in order.size():
		var t: Dictionary = tabs.get(order[i], {"name": order[i], "cats": [], "pets": false})
		t["id"] = "tab.m:%d" % i
		out.append(t)
	return out


## The tab id `alias` ("tab.items", "tab.pets") stands for.
func _market_tab_for(alias: String) -> String:
	for t in _market_tabs(session.world):
		if alias == "tab.items" and not (t["cats"] as Array).is_empty():
			return t["id"]
		if alias == "tab.pets" and t["pets"]:
			return t["id"]
	return alias


func _tab_name(id: String) -> String:
	if id.begins_with("tab.m:"):
		var tabs := _market_tabs(session.world)
		var i := int(id.substr(6))
		return str(tabs[i]["name"]) if i < tabs.size() else id
	return session.strings.t(id)


## One goods tab: its items by category, its animals, or a note that nothing is in yet. The
## tab that is the arrange catalogue's (`market.arrange_tab`) points there.
func _fill_market(list: VBoxContainer, w: World, tab: Dictionary) -> void:
	var s := session.strings
	if s.has("market.arrange_tab") and tab["name"] == s.t("market.arrange_tab"):
		list.add_child(ViewWidgets.wrapped(s.t("market.arrange_note")))
		_button("go_arrange", s.t("btn.arrange"), list)
	elif (tab["cats"] as Array).is_empty() and not tab["pets"]:
		var none := ViewWidgets.wrapped(s.t("market.empty"))
		none.add_theme_color_override("font_color", ViewWidgets.MUTED)
		list.add_child(none)
	_fill_items(list, w, tab["cats"])
	if tab["pets"]:
		_fill_pet_shop(list, w)


func _fill_items(list: VBoxContainer, w: World, cats: Array) -> void:
	var s := session.strings
	var by_cat: Dictionary = {}
	for id in w.pack.items:
		var cat := str(w.pack.items[id].get("category", ""))
		if not cat in cats:
			continue
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(id)
	for cat in by_cat:
		if cat != "" and by_cat.size() > 1:
			var head := ViewWidgets.wrapped(cat)
			head.add_theme_color_override("font_color", ViewWidgets.WOOD)
			list.add_child(head)
		for id in by_cat[cat]:
			var it: Dictionary = w.pack.items[id]
			var row := ViewWidgets.row(list)
			row.add_child(ViewWidgets.name_label(str(it["name"])))
			var wanted := _wanted_by(w, str(id))
			if wanted != "":
				var mark := ViewWidgets.price_label(s.t("shop.wanted").replace("{name}", wanted))
				mark.add_theme_color_override("font_color", ViewWidgets.ACCENT)
				row.add_child(mark)
			row.add_child(ViewWidgets.price_label(s.t("money").replace("{n}", str(int(it["price"])))))
			var buy := _button("buy:" + id, s.t("btn.buy"), row)
			buy.disabled = w.money < int(it["price"])
			if buy.disabled:
				buy.text = s.t("error.no_money")
			if not Commands.on_sale(w, str(id)):   # a festival's goods: only at their festival
				buy.disabled = true
				buy.text = s.t("error.not_festival")


## Where the selected person could go: the outings (away for a few hours, back with
## something) first, then the places outside the wall; one that cannot be done now is
## greyed with the reason.
func _fill_go_out(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var p := w.person(main.selected)
	if p == null:
		return
	var all := OutingSystem.options(w, p)
	var opts := all.filter(func(o): return o["outing"]) + all.filter(func(o): return not o["outing"])
	if opts.is_empty():
		var none := ViewWidgets.wrapped(s.t("go_out.none"))
		none.add_theme_color_override("font_color", ViewWidgets.MUTED)
		list.add_child(none)
	for o in opts:
		var row := ViewWidgets.row(list)
		row.add_child(ViewWidgets.name_label(str(o["label"])))
		if o["outing"]:
			var note := ViewWidgets.price_label(s.t("go_out.away"))
			note.add_theme_color_override("font_color", ViewWidgets.WOOD)
			row.add_child(note)
		var go := _button("go:" + str(o["action"]), s.t("btn.go_out"), row)
		if str(o["why"]) != "":
			go.disabled = true
			go.text = s.error(str(o["why"]))


## The animals for sale (kinds with a price); one that needs a perch says so until there is one.
func _fill_pet_shop(list: VBoxContainer, w: World) -> void:
	if not PetSystem.enabled(w.pack):
		return
	var s := session.strings
	var heading := false
	for kind in w.pack.pets:
		var k: Dictionary = w.pack.pets[kind]
		if int(k.get("price", 0)) <= 0:
			continue
		if not heading:
			list.add_child(ViewWidgets.wrapped(s.t("shop.pets")))
			heading = true
		var row := ViewWidgets.row(list)
		row.add_child(ViewWidgets.name_label(str(k.get("name", ""))))
		var why := PetSystem.can_take(w, str(kind))
		var wanted := _pet_wanted_by(w, str(kind))
		if why == "no_perch":
			var perch := str(w.pack.object_types.get(str(k.get("perch", "")), {}).get("name", ""))
			row.add_child(ViewWidgets.price_label(s.t("pet.need_perch").replace("{perch}", perch)))
		elif wanted != "":
			var mark := ViewWidgets.price_label(s.t("shop.wanted").replace("{name}", wanted))
			mark.add_theme_color_override("font_color", ViewWidgets.ACCENT)
			row.add_child(mark)
		row.add_child(ViewWidgets.price_label(s.t("money").replace("{n}", str(int(k["price"])))))
		_button("buy_pet:" + str(kind), s.t("btn.buy_pet"), row).disabled = why != "" or w.money < int(k["price"])


## The names of the living people who wish for an animal of this kind, joined.
func _pet_wanted_by(w: World, kind: String) -> String:
	var names: Array[String] = []
	for p in w.people:
		if not p.alive:
			continue
		var wish := WishSystem.current(w, p)
		if str(wish.get("kind", "")) == "pet" and str(wish.get("pet", "")) == kind:
			names.append(session.strings.person_name(p))
	return "、".join(names)


## The names of the living people whose wish is this item, joined; "" for nobody.
func _wanted_by(w: World, item: String) -> String:
	var names: Array[String] = []
	for p in w.people:
		if not p.alive:
			continue
		var wish := WishSystem.current(w, p)
		if str(wish.get("kind", "")) == "item" and str(wish.get("item", "")) == item:
			names.append(session.strings.person_name(p))
	return "、".join(names)


## Each story that has come to light: its title, the fragments found with their text, and
## a placeholder for each one still missing.
func _fill_stories(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	if w.stories.is_empty():
		list.add_child(ViewWidgets.wrapped(s.t("stories.none")))
		return
	for sid in w.pack.stories:
		if not w.stories.has(sid):
			continue
		var title := ViewWidgets.wrapped(s.story_title(sid, w))
		title.add_theme_font_size_override("font_size", 18)
		list.add_child(title)
		var found: Array = w.stories[sid]["found"]
		for f in w.pack.stories[sid]["fragments"]:
			if found.has(str(f["id"])):
				list.add_child(ViewWidgets.wrapped("· " + str(f["name"])))
				var body := ViewWidgets.wrapped("　" + str(f["text"]))
				body.modulate = Color(1, 1, 1, 0.8)
				list.add_child(body)
			else:
				list.add_child(ViewWidgets.wrapped("· " + s.t("stories.locked")))


func _fill_inventory(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var total := 0
	for k in w.stock:
		total += int(w.stock[k])
	list.add_child(ViewWidgets.wrapped(s.t("stock").replace("{n}", str(total))))
	var sel := w.person(main.selected)
	var who := s.person_name(sel) if sel != null and sel.alive else ""
	var pet := PetSystem.find(w, main.selected_pet) if main.selected_pet >= 0 else null
	if pet != null and pet.home():
		who = pet.given
	for id in w.pack.items:
		var count := int(w.inventory.get(id, 0))
		if count <= 0:
			continue
		var row := ViewWidgets.row(list)
		row.add_child(ViewWidgets.name_label("%s × %d" % [str(w.pack.items[id]["name"]), count]))
		var for_pet := not (w.pack.items[id].get("pet", {}) as Dictionary).is_empty()
		var fits := who != "" and for_pet == (pet != null and pet.home())
		_button("use:" + id, s.t("btn.use_on").replace("{name}", who), row).disabled = not fits


func _fill_goals(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var open_ids: Array = []
	var done_ids: Array = []
	for id in w.pack.goals:
		(done_ids if id in w.goals_done else open_ids).append(id)
	for id in open_ids + done_ids:
		var g: Dictionary = w.pack.goals[id]
		var mark := DONE_MARK if id in done_ids else ""
		list.add_child(ViewWidgets.wrapped("%s%s（%s）" % [mark, str(g["text"]), s.t("money").replace("{n}", str(int(g.get("reward", 0))))]))


func _fill_collection(list: VBoxContainer, w: World) -> void:
	for id in w.pack.collectibles:
		list.add_child(ViewWidgets.name_label(str(w.pack.collectibles[id]["name"]) if w.collection.has(id) else UNKNOWN))


func _fill_family(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var who := w.person(_changing)
	if who != null and who.alive:
		_fill_change(list, w, who)
		return
	_changing = -1
	if not w.proposals.is_empty():
		_button("proposal", s.t("title.proposal"), list)
	if not w.pet_offer.is_empty():
		_button("stray", s.t("title.stray"), list)
	if BirthSystem.blocked(w):
		var hint := ViewWidgets.wrapped(s.t("hint.no_bed"))
		hint.add_theme_color_override("font_color", ViewWidgets.ACCENT)
		list.add_child(hint)
	# With births the household spans generations: one heading per generation, the dead
	# greyed out among them. Without births, the living as one list.
	var lineage := BirthSystem.enabled(w.pack)
	var by_gen := {}
	for p in w.people:
		if p.alive or lineage:
			var g := s.shown_generation(p, w) if lineage else 0
			if not by_gen.has(g):
				by_gen[g] = []
			by_gen[g].append(p)
	var gens := by_gen.keys()
	gens.sort()
	for g in gens:
		if lineage:
			var head := ViewWidgets.wrapped(s.generation_label(int(g)))
			head.add_theme_font_size_override("font_size", 17)
			list.add_child(head)
		for p in by_gen[g]:
			if p.alive:
				_family_row(list, w, p, lineage)
			else:
				var dead := ViewWidgets.wrapped("%s  %s" % [s.person_name(p), s.t("family.dead").replace("{n}", str(int(p.age)))])
				dead.modulate = Color(1, 1, 1, 0.45)
				list.add_child(dead)
	_fill_family_pets(list, w)


## The animals: the ones at home as buttons (picking one shows it in the bar), the ones that
## ran off, died or never came back greyed out, as the household's record.
func _fill_family_pets(list: VBoxContainer, w: World) -> void:
	if w.pets.is_empty():
		return
	var s := session.strings
	var head := ViewWidgets.wrapped(s.t("family.pets"))
	head.add_theme_font_size_override("font_size", 17)
	list.add_child(head)
	for pet in w.pets:
		if pet.home():
			var b := _button("pet:%d" % pet.uid, "%s  %s  %s" % [s.pet_name(pet, w), s.pet_line(pet, w), s.pet_status(pet, w)], list)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			var gone := ViewWidgets.wrapped(s.pet_record(pet, w))
			gone.modulate = Color(1, 1, 1, 0.45)
			list.add_child(gone)


## One living person in the family panel: their button, then livelihood (or "too young") and,
## with births, whom they married and whose child they are.
func _family_row(list: VBoxContainer, w: World, p: Person, lineage: bool) -> void:
	var s := session.strings
	var b := _button("person:%d" % p.uid, "%s  %s  %s" % [s.person_name(p), s.person_line(p, w), s.status_line(p, w)], list)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var row := ViewWidgets.row(list)
	if p.stage(w.pack) in ["adult", "elder"]:
		row.add_child(ViewWidgets.name_label("    " + s.job_line(p)))
		_button("change:%d" % p.uid, s.t("btn.change_track"), row)
	else:
		row.add_child(ViewWidgets.name_label("    " + s.t("family.child")))
	if not lineage:
		return
	var ties: Array[String] = []
	var mother := w.person(p.mother)
	var father := w.person(p.father)
	if mother != null and father != null:
		ties.append(s.t("family.parents").format({"father": s.person_name(father), "mother": s.person_name(mother)}))
	var spouse := w.person(p.spouse)
	if spouse != null:
		ties.append(s.t("family.spouse").replace("{name}", s.person_name(spouse)))
	if not ties.is_empty():
		var l := ViewWidgets.wrapped("    " + "　".join(ties))
		l.modulate = Color(1, 1, 1, 0.75)
		list.add_child(l)


## The livelihoods `p` could change to, with what each starts at; picking one changes it.
func _fill_change(list: VBoxContainer, w: World, p: Person) -> void:
	var s := session.strings
	list.add_child(ViewWidgets.wrapped(s.t("title.change_track").replace("{name}", s.person_name(p))))
	list.add_child(ViewWidgets.wrapped(s.t("change.note")))
	for t in w.pack.livelihoods:
		if t == p.track:
			continue
		var job: Dictionary = w.pack.livelihoods[t]
		var first: Dictionary = (job["levels"] as Array)[0]
		var text := s.t("change.option").format({"job": str(job["name"]), "level": str(first["name"]),
			"money": s.t("money").replace("{n}", str(int(first["daily_income"])))})
		var b := _button("track:" + str(t), text, list)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button("change.cancel", s.t("btn.cancel"), list)


## Every label that sits in a row beside other widgets; for layout tests.
func row_labels() -> Array[Label]:
	var out: Array[Label] = []
	_row_labels(_box, out)
	return out


func _row_labels(n: Node, out: Array[Label]) -> void:
	for c in n.get_children():
		if c is Label and n is HBoxContainer:
			out.append(c)
		_row_labels(c, out)


## The card's minimum size as the layout computes it; for layout tests.
func card_size() -> Vector2:
	return _card.get_combined_minimum_size()


func _button(id: String, label: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(press.bind(id))
	parent.add_child(b)
	_buttons[id] = b
	return b
