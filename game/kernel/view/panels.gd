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
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
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


## One of "", "shop", "ledger", "family", "stories".
func opened() -> String:
	return _kind


## True while a panel covers the house.
func blocks_input() -> bool:
	return _kind != ""


## Opens a panel; ignored for an unknown name, while an overlay shows or outside a running game.
func open(what: String) -> void:
	if not what in ["shop", "ledger", "family", "stories"]:
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
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
			return ["tab.items", "tab.inventory"]
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


## Test entry point and button handler; unknown or disabled ids do nothing.
func press(id: String) -> void:
	if is_disabled(id):
		return
	if id == "btn.close":
		close()
	elif id in _tabs():
		_tab = id
		_signature = ""
		refresh()
	elif id.begins_with("buy:"):
		session.command({"type": "buy", "item": id.substr(4)})
		refresh()
	elif id.begins_with("use:"):
		session.command({"type": "use_item", "item": id.substr(4), "person": main.selected})
		refresh()
	elif id.begins_with("person:"):
		main.select(int(id.substr(7)))
		close()
	elif id == "proposal":
		close()
		main.overlays.open_proposal()
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
			return "%d|%d|%s|%s|%s" % [w.money, total, str(w.inventory), s.person_name(sel) if sel != null and sel.alive else "", wishes]
		"stories":
			return str(w.stories)
		"ledger":
			return "%s|%s" % [str(w.goals_done), str(w.collection)]
		"family":
			var parts: Array[String] = [str(w.proposals.size()), str(_changing), str(BirthSystem.blocked(w))]
			for p in w.people:
				if p.alive:
					parts.append("%d:%s:%s:%s:%d" % [p.uid, s.person_line(p, w), s.status_line(p, w), s.job_line(p), p.spouse])
				else:
					parts.append("%d:dead" % p.uid)
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
		var row := HBoxContainer.new()
		_box.add_child(row)
		for t in tabs:
			_button(t, s.t(t), row).disabled = (t == _tab)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 2.0 * MARGIN, BODY_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	match _tab if not _kind in ["family", "stories"] else _kind:
		"tab.items":
			_fill_items(list, w)
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


func _fill_items(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var by_cat: Dictionary = {}
	for id in w.pack.items:
		var cat := str(w.pack.items[id].get("category", ""))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(id)
	for cat in by_cat:
		if cat != "":
			list.add_child(ViewWidgets.wrapped(cat))
		for id in by_cat[cat]:
			var it: Dictionary = w.pack.items[id]
			var row := ViewWidgets.row(list)
			row.add_child(ViewWidgets.name_label(str(it["name"])))
			var wanted := _wanted_by(w, str(id))
			if wanted != "":
				var mark := ViewWidgets.price_label(s.t("shop.wanted").replace("{name}", wanted))
				mark.add_theme_color_override("font_color", Color(0.95, 0.6, 0.3))
				row.add_child(mark)
			row.add_child(ViewWidgets.price_label(s.t("money").replace("{n}", str(int(it["price"])))))
			_button("buy:" + id, s.t("btn.buy"), row).disabled = w.money < int(it["price"])


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
	for id in w.pack.items:
		var count := int(w.inventory.get(id, 0))
		if count <= 0:
			continue
		var row := ViewWidgets.row(list)
		row.add_child(ViewWidgets.name_label("%s × %d" % [str(w.pack.items[id]["name"]), count]))
		_button("use:" + id, s.t("btn.use_on").replace("{name}", who), row).disabled = who == ""


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
	if BirthSystem.blocked(w):
		var hint := ViewWidgets.wrapped(s.t("hint.no_bed"))
		hint.add_theme_color_override("font_color", Color(0.95, 0.6, 0.3))
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
