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


## One of "", "shop", "ledger", "family".
func opened() -> String:
	return _kind


## True while a panel covers the house.
func blocks_input() -> bool:
	return _kind != ""


## Opens a panel; ignored for an unknown name, while an overlay shows or outside a running game.
func open(what: String) -> void:
	if not what in ["shop", "ledger", "family"]:
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
		return
	_kind = what
	_tab = _tabs()[0] if not _tabs().is_empty() else ""
	_signature = ""
	refresh()


func close() -> void:
	if _kind == "":
		return
	_kind = ""
	_tab = ""
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
			return "%d|%d|%s|%s" % [w.money, total, str(w.inventory), s.person_name(sel) if sel != null and sel.alive else ""]
		"ledger":
			return "%s|%s" % [str(w.goals_done), str(w.collection)]
		"family":
			var parts: Array[String] = [str(w.proposals.size())]
			for p in w.people:
				if p.alive:
					parts.append("%d:%s:%s" % [p.uid, s.person_line(p, w), s.status_line(p, w)])
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
	match _tab if _kind != "family" else "family":
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
			row.add_child(ViewWidgets.price_label(s.t("money").replace("{n}", str(int(it["price"])))))
			_button("buy:" + id, s.t("btn.buy"), row).disabled = w.money < int(it["price"])


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
	if not w.proposals.is_empty():
		_button("proposal", s.t("title.proposal"), list)
	for p in w.people:
		if p.alive:
			var b := _button("person:%d" % p.uid, "%s  %s  %s" % [s.person_name(p), s.person_line(p, w), s.status_line(p, w)], list)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


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
