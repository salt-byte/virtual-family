class_name ArrangeMode
extends Node
## Arrange mode: buy, place, move and sell furniture and build rooms. A banner on top says
## where you are, a column on the right lists the furniture, and the house shows a ghost under
## the pointer (HouseView draws it from `ghost()`). Reads the World; every change goes through
## session commands. No drawing happens here.

const LAYER := 4
const COLUMN_WIDTH := 280.0
const COLUMN_TOP := 100.0
const MARGIN := 14.0
const BANNER_TOP := 56.0
const CONFIRM_WIDTH := 380.0

var main: Main
var session: GameSession
var active := false
## The kind of furniture in hand ("" for nothing); for a picked-up piece this is its kind.
var held_type := ""
## Uid of the piece picked up from the house; -1 when nothing or a new piece is in hand.
var held_uid := -1

var _layer: CanvasLayer
var _root: Control
var _banner: PanelContainer
var _banner_label: Label
var _column: PanelContainer
var _box: VBoxContainer
var _confirm: Control
var _confirm_box: VBoxContainer
var _buttons: Dictionary = {}  # id -> Button
var _confirm_room := ""
var _hover_pos := Vector2.ZERO
var _has_hover := false
var _press_picked := false
var _press_room := ""
var _signature := ""


func setup(m: Main) -> void:
	main = m
	session = m.session
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.theme = ViewWidgets.panel_theme()
	_layer.add_child(_root)

	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = BANNER_TOP
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", ViewWidgets.card_style(8.0))
	_banner_label = ViewWidgets.label(session.strings.t("arrange.banner"))
	_banner.add_child(_banner_label)
	_root.add_child(_banner)

	_column = PanelContainer.new()
	_column.anchor_left = 1.0
	_column.anchor_right = 1.0
	_column.anchor_top = 0.0
	_column.anchor_bottom = 1.0
	_column.offset_left = -COLUMN_WIDTH - 12.0
	_column.offset_right = -12.0
	_column.offset_top = COLUMN_TOP
	_column.offset_bottom = -(Hud.BAR_HEIGHT + 12.0)
	_column.mouse_filter = Control.MOUSE_FILTER_STOP
	_column.add_theme_stylebox_override("panel", ViewWidgets.card_style(MARGIN))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_column.add_child(_box)
	_root.add_child(_column)

	_confirm = Control.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CONFIRM_WIDTH
	card.add_theme_stylebox_override("panel", ViewWidgets.card_style(24.0))
	center.add_child(card)
	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 12)
	card.add_child(_confirm_box)
	_root.add_child(_confirm)


## True while the build confirmation covers the house.
func blocks_input() -> bool:
	return active and _confirm_room != ""


func enter() -> void:
	if active:
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "" or main.panels.opened() != "":
		return
	main.drag.cancel()
	active = true
	_root.visible = true
	_signature = ""
	refresh()


func exit() -> void:
	if not active:
		return
	_clear_hold()
	_confirm_room = ""
	_has_hover = false
	active = false
	_root.visible = false
	_signature = ""
	main.house.queue_redraw()


## Called every tick: an overlay or the end of the game closes the mode; a held piece that
## no longer exists leaves the hand; the column is rebuilt when what it shows changed.
func refresh() -> void:
	if not active:
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
		exit()
		return
	if held_uid >= 0 and w.object(held_uid).is_empty():
		_clear_hold()
	var sig := "%d|%s|%d|%s" % [w.money, held_type, held_uid, _confirm_room]
	if sig != _signature:
		_signature = sig
		_rebuild()


func pick_type(type: String) -> void:
	if not active or not session.world.pack.object_types.has(type) or HouseSystem.is_fixed(session.world, type) \
			or bool(session.world.pack.object_types[type].get("keepsake", false)):
		return
	held_type = type
	held_uid = -1
	# The last pointer spot was over the house before the catalogue click; no ghost until
	# the pointer is back over the house.
	_has_hover = false
	refresh()


func pick_object(uid: int) -> void:
	if not active:
		return
	var o := session.world.object(uid)
	if o.is_empty():
		return
	held_type = str(o["type"])
	held_uid = uid
	refresh()


func cancel_held() -> void:
	_clear_hold()
	refresh()


func hover(world_pos: Vector2) -> void:
	_hover_pos = world_pos
	_has_hover = true
	main.house.queue_redraw()


## Where the piece in hand would sit with the pointer at `pos`: the cell under the pointer is
## the piece's middle, pulled back inside the room. {} when `pos` is over no room.
func _target(pos: Vector2) -> Dictionary:
	var w := session.world
	var cell := main.house.layout.pos_to_cell(pos)
	if cell.is_empty() or held_type == "":
		return {}
	var t: Dictionary = w.pack.object_types[held_type]
	var r: Dictionary = w.pack.rooms[cell.room]
	var x := clampi(int(cell.x) - (int(t["w"]) - 1) / 2, 0, maxi(0, int(r["w"]) - int(t["w"])))
	var y := clampi(int(cell.y) - (int(t["h"]) - 1) / 2, 0, maxi(0, int(r["h"]) - int(t["h"])))
	return {"room": cell.room, "x": x, "y": y}


func can_drop() -> bool:
	if not active or held_type == "" or not _has_hover:
		return false
	var t := _target(_hover_pos)
	if t.is_empty():
		return false
	var w := session.world
	if HouseSystem.can_place(w, held_type, t.room, t.x, t.y, held_uid) != "":
		return false
	return held_uid >= 0 or w.money >= int(w.pack.object_types[held_type]["price"])


## What the house draws under the pointer: {type, uid, room, x, y, w, h, ok}; {} for nothing.
func ghost() -> Dictionary:
	if not active or held_type == "" or not _has_hover:
		return {}
	var t := _target(_hover_pos)
	if t.is_empty():
		return {}
	var ot: Dictionary = session.world.pack.object_types[held_type]
	return {"type": held_type, "uid": held_uid, "room": t.room, "x": t.x, "y": t.y,
		"w": int(ot["w"]), "h": int(ot["h"]), "ok": can_drop()}


## Puts the piece in hand at `world_pos`: a `place` for a new piece, a `move` for a picked-up
## one. On failure the piece stays in hand. `{}` when nothing is in hand.
func drop(world_pos: Vector2) -> Dictionary:
	if not active or held_type == "":
		return {}
	hover(world_pos)
	var t := _target(world_pos)
	if t.is_empty():
		return {"ok": false, "error": "no_room"}
	var cmd := {"room": t.room, "x": t.x, "y": t.y}
	if held_uid >= 0:
		cmd["type"] = "move"
		cmd["object"] = held_uid
	else:
		cmd["type"] = "place"
		cmd["object_type"] = held_type
	var type := held_type
	main.hud.mute("wrong_area")
	var r := session.command(cmd)
	main.hud.unmute()
	if r.get("ok", false):
		_clear_hold()
		refresh()
	elif str(r.get("error", "")) == "wrong_area":
		var where := "where.outdoor" if bool(session.world.pack.object_types[type]["outdoor"]) else "where.indoor"
		main.hud.toast(session.strings.error("wrong_area", {"where": session.strings.t(where)}))
	return r


## What selling the piece in hand brings in; 0 when none is in hand.
func refund() -> int:
	if held_uid < 0:
		return 0
	var w := session.world
	return int(int(w.pack.object_types[held_type]["price"]) * float(w.pack.cfg("sell_back_ratio")))


func sell_held() -> Dictionary:
	if not active or held_uid < 0:
		return {}
	var r := session.command({"type": "sell_object", "object": held_uid})
	if r.get("ok", false):
		_clear_hold()
		refresh()
	return r


## Shows the "really build this?" card for an unbuilt room.
func ask_build(room: String) -> void:
	var w := session.world
	if not active or not w.pack.rooms.has(room) or w.rooms_built.has(room):
		return
	_confirm_room = room
	refresh()


## Builds the room now (what the card's confirm button does).
func build(room: String) -> Dictionary:
	var r := session.command({"type": "build_room", "room": room})
	_confirm_room = ""
	refresh()
	return r


# ---- pointer input, forwarded by HouseView while the mode is active ----

## A press on the house. True when it picked a piece up (a drag then carries it); false lets a
## drag pan the house, also while a piece is in hand.
func house_press(pos: Vector2) -> bool:
	_press_picked = false
	_press_room = ""
	hover(pos)
	if held_type != "":
		return false
	var hit := main.house.layout.pick(session.world, pos, true)
	if str(hit.kind) == "object" and HouseSystem.is_fixed(session.world, str(session.world.object(int(hit.uid)).get("type", ""))):
		main.hud.toast(session.strings.error("fixed"))  # part of the house: it stays where it is
		return false
	if str(hit.kind) == "object":
		pick_object(int(hit.uid))
		_press_picked = true
		return true
	var room := str(hit.room)
	if room != "" and not session.world.rooms_built.has(room):
		_press_room = room
	return false


## The pointer let go: a piece this press picked up is dropped when it was dragged and stays in
## hand after a click; a piece already in hand is placed by a click (a drag only panned);
## a plain click on an unbuilt room asks to build it.
func house_release(pos: Vector2, moved: bool) -> void:
	if _press_picked:
		if moved and held_type != "":
			drop(pos)
	elif held_type != "":
		if not moved:
			drop(pos)
	elif _press_room != "" and not moved:
		ask_build(_press_room)
	_press_picked = false
	_press_room = ""


# ---- test entry points and UI ----

func has_button(id: String) -> bool:
	return _buttons.has(id)


func is_disabled(id: String) -> bool:
	return not _buttons.has(id) or (_buttons[id] as Button).disabled


## All text of the mode's banner, column and card, joined with newlines; for tests.
func text() -> String:
	var parts: Array[String] = []
	if active:
		_collect(_banner, parts)
		_collect(_column, parts)
		if _confirm_room != "":
			_collect(_confirm, parts)
	return "\n".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	if n is Label or n is Button:
		out.append(n.text)
	for c in n.get_children():
		_collect(c, out)


## Test entry point and button handler; unknown or disabled ids do nothing.
func press(id: String) -> void:
	if is_disabled(id):
		return
	if id == "btn.close":
		exit()
	elif id.begins_with("type:"):
		pick_type(id.substr(5))
	elif id == "btn.sell":
		sell_held()
	elif id == "confirm":
		build(_confirm_room)
	elif id == "cancel":
		_confirm_room = ""
		refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		return
	if _confirm_room != "":
		press("cancel")
	elif held_type != "":
		cancel_held()
	else:
		exit()
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _clear_hold() -> void:
	held_type = ""
	held_uid = -1
	_press_picked = false
	main.house.queue_redraw()


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for c in _confirm_box.get_children():
		_confirm_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var s := session.strings
	var w := session.world
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := ViewWidgets.label(s.t("tab.furniture"))
	title.add_theme_font_size_override("font_size", 20)
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(ViewWidgets.label(s.t("money").replace("{n}", str(w.money))))
	_button("btn.close", s.t("btn.close"), head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var by_cat: Dictionary = {}
	for id in w.pack.object_types:
		if HouseSystem.is_fixed(w, str(id)) or bool(w.pack.object_types[id].get("keepsake", false)):
			continue  # fixed furniture comes with its room; a keepsake is given, never sold
		var cat := str(w.pack.object_types[id].get("category", ""))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(id)
	for cat in by_cat:
		if cat != "":
			list.add_child(ViewWidgets.wrapped(cat))
		for id in by_cat[cat]:
			var t: Dictionary = w.pack.object_types[id]
			var dear: bool = w.money < int(t["price"])
			var row := ViewWidgets.row(list)
			var name_label := ViewWidgets.name_label(str(t["name"]))
			var price_label := ViewWidgets.price_label(s.t("money").replace("{n}", str(int(t["price"]))))
			if dear:
				name_label.modulate = Color(1, 1, 1, 0.45)
				price_label.modulate = Color(1, 1, 1, 0.45)
			row.add_child(name_label)
			row.add_child(price_label)
			_button("type:" + id, s.t("btn.buy"), row).disabled = dear
	if held_uid >= 0:
		var sell := ViewWidgets.row(_box)
		sell.add_child(ViewWidgets.name_label(s.t("arrange.refund").replace("{n}", str(refund()))))
		_button("btn.sell", s.t("btn.sell"), sell)
	_confirm.visible = _confirm_room != ""
	if _confirm_room != "":
		var r: Dictionary = w.pack.rooms[_confirm_room]
		_confirm_box.add_child(ViewWidgets.wrapped(s.t("arrange.build").replace("{room}", str(r["name"]))
			.replace("{cost}", s.t("money").replace("{n}", str(int(r["build_cost"]))))))
		var buttons := ViewWidgets.row(_confirm_box)
		_button("confirm", s.t("btn.confirm"), buttons)
		_button("cancel", s.t("btn.cancel"), buttons)


func _button(id: String, label: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(press.bind(id))
	parent.add_child(b)
	_buttons[id] = b
	return b
