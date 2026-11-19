class_name Hud
extends CanvasLayer
## The bottom bar, the praise/scold buttons and the toasts. Shows status as words only.
## Reads the World; the only thing it writes is the praise/scold command through the session.

signal open(what: String)

const BAR_HEIGHT := 96.0
const TOAST_SECONDS := 3.0
const TOAST_MAX := 4
const BAR_BUTTONS := ["family", "shop", "ledger", "stories", "arrange", "settings"]

var main: Main
var session: GameSession

var _bar: PanelContainer
var _avatar: ColorRect
var _name: Label
var _line: Label
var _doing: Label
var _status: Label
var _wish: Label
var _money: Label
var _stock: Label
var _sky: Label
var _buttons: Dictionary = {}  # id -> Button
var _praise: Button
var _scold: Button
var _toast_box: VBoxContainer
var _toasts: Array = []  # {text, left, label}
var _muted := ""


func setup(m: Main) -> void:
	main = m
	session = m.session
	_build()
	session.command_failed.connect(func(code: String):
		if code != _muted:
			toast(session.strings.error(code)))
	session.event.connect(_on_event)
	# A typo in the pack's ui.json would otherwise go unnoticed: say so once, at launch.
	if not session.strings.errors.is_empty():
		toast(session.strings.errors[0])
	refresh()


func _build() -> void:
	var s := session.strings
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ViewWidgets.hud_theme()
	add_child(root)

	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.custom_minimum_size.y = BAR_HEIGHT
	_bar.offset_top = -BAR_HEIGHT
	root.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_bar.add_child(row)

	_avatar = ColorRect.new()
	_avatar.custom_minimum_size = Vector2(56, 56)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_avatar)
	var who := VBoxContainer.new()
	who.custom_minimum_size.x = 150
	row.add_child(who)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	_line = Label.new()
	_line.add_theme_color_override("font_color", ViewWidgets.INK.lightened(0.2))
	who.add_child(_name)
	who.add_child(_line)
	_doing = Label.new()
	_doing.custom_minimum_size.x = 220
	_doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_doing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_doing)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_status)
	_wish = Label.new()
	_wish.visible = false
	mid.add_child(_wish)
	var cash := VBoxContainer.new()
	cash.alignment = BoxContainer.ALIGNMENT_CENTER
	cash.add_theme_constant_override("separation", 0)
	cash.custom_minimum_size.x = 110
	row.add_child(cash)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 20)
	_stock = Label.new()
	_sky = Label.new()
	cash.add_child(_sky)
	cash.add_child(_money)
	cash.add_child(_stock)
	for id in BAR_BUTTONS:
		var b := Button.new()
		b.text = s.t("btn." + id)
		b.pressed.connect(press.bind(id))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size.y = 44
		row.add_child(b)
		_buttons[id] = b

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.position = Vector2(12, 12)
	root.add_child(top)
	_scold = Button.new()
	_scold.text = s.t("btn.scold")
	_scold.pressed.connect(press.bind("scold"))
	ViewWidgets.round_button(_scold, ViewWidgets.CREAM, ViewWidgets.WOOD)
	top.add_child(_scold)
	_praise = Button.new()
	_praise.text = s.t("btn.praise")
	_praise.pressed.connect(press.bind("praise"))
	ViewWidgets.round_button(_praise, ViewWidgets.CREAM, ViewWidgets.ACCENT)
	top.add_child(_praise)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_top = 12
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)


## Swallows the toast for one expected failure code until `unmute()`.
func mute(code: String) -> void:
	_muted = code


func unmute() -> void:
	_muted = ""


func _living() -> bool:
	var w := session.world
	return w != null and w.phase == "living"


## The animal shown in the bar, or null.
func _selected_pet() -> Pet:
	if not _living() or main.selected_pet < 0:
		return null
	var pet := PetSystem.find(session.world, main.selected_pet)
	return pet if pet != null and pet.home() else null


func _selected() -> Person:
	if not _living() or main.selected_pet >= 0:
		return null
	var p := session.world.person(main.selected)
	return p if p != null and p.alive else null


func refresh() -> void:
	var w := session.world
	var s := session.strings
	var living := _living()
	var p := _selected()
	var pet := _selected_pet()
	var have := p != null or pet != null
	for c in [_avatar, _name, _line, _doing, _status, _stock]:
		c.visible = have if c != _stock else living
	for id in _buttons:
		_buttons[id].visible = living or id == "settings"
	# The old-stories box only for a pack that has stories.
	_buttons["stories"].visible = living and w != null and not w.pack.stories.is_empty()
	_money.visible = w != null and w.phase != "invalid"
	if _money.visible:
		_money.text = s.t("money").replace("{n}", str(w.money))
	var sky := s.sky_line(w) if living else ""
	_sky.visible = sky != ""
	_sky.text = sky
	if living:
		var total := 0
		for k in w.stock:
			total += int(w.stock[k])
		_stock.text = s.t("stock").replace("{n}", str(total))
	if p != null:
		_name.text = s.person_name(p)
		_line.text = s.person_line(p, w)
		_doing.text = _doing_text(p)
		_status.text = s.status_line(p, w)
		_avatar.color = PersonView.FEMALE if p.gender == "female" else (PersonView.MALE if p.gender == "male" else PersonView.OTHER)
	if pet != null:
		_name.text = s.pet_name(pet, w)
		_line.text = s.pet_line(pet, w)
		_doing.text = s.pet_doing(pet, w)
		_status.text = s.pet_status(pet, w)
		_avatar.color = HouseView.pack_color(PetSystem.kind_of(w.pack, pet), PetView.FALLBACK)
	var wish := s.wish_text(p, w) if p != null else (s.pet_wish_text(pet, w) if pet != null else "")
	_wish.visible = wish != ""
	_wish.text = s.t("wish.line").replace("{text}", wish)
	var waiting := living and (not w.proposals.is_empty() or not w.pet_offer.is_empty())
	_buttons["family"].text = ("● " if waiting else "") + s.t("btn.family")
	var off := judge_disabled()
	_praise.disabled = off
	_scold.disabled = off
	_praise.visible = living
	_scold.visible = living


## The "what they are doing" sentence (the plate's progress line shows how far along).
func _doing_text(p: Person) -> String:
	var s := session.strings
	var pv: PersonView = main.house.people.get(p.uid) if main.house != null else null
	# The person's plate holds the previous action's words through the short idle gap
	# between two actions; the bar says the same.
	return pv.doing_text() if pv != null else s.doing(p, session.world)


func judge_disabled() -> bool:
	return _selected() == null


## All text visible in the bottom bar, joined; for tests.
func bar_text() -> String:
	var parts: Array[String] = []
	_collect(_bar, parts)
	return " ".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Control and not c.visible:
			continue
		if c is Label or c is Button:
			out.append(c.text)
		_collect(c, out)


## Test entry point and button handler: "praise" | "scold" or a bar button id.
func press(what: String) -> void:
	if what == "praise" or what == "scold":
		_judge(what)
	elif what in BAR_BUTTONS:
		open.emit(what)


func _judge(kind: String) -> void:
	var p := _selected()
	if p == null:
		return
	var r := session.command({"type": kind, "person": p.uid})
	if r.get("ok", false) and main.house.people.has(p.uid):
		main.house.people[p.uid].float_text_up(session.strings.t("btn." + kind))


func _on_event(e: Dictionary) -> void:
	if str(e.get("type", "")) == "pet_wish_granted" and main.house != null and main.house.pets.has(int(e.get("pet", -1))):
		var pet := PetSystem.find(session.world, int(e["pet"]))
		if pet != null:
			main.house.pets[pet.uid].float_text_up(str(PetSystem.kind_of(session.world.pack, pet).get("thanks", "")))
	if str(e.get("type", "")) == "clean_reward" and main.house != null and main.house.people.has(int(e.get("person", -1))):
		# The coins float up over whoever swept the last of it.
		main.house.people[int(e["person"])].float_text_up(session.strings.t("float.clean_reward").replace("{n}", str(int(e["amount"]))))
	var text := session.strings.event(e, session.world)
	if text != "":
		toast(text)


func toast(text: String) -> void:
	# A cream pill with a sky-blue dot on the left (ART_DIRECTION section 4).
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ViewWidgets.INK)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = ViewWidgets.CREAM
	box.border_color = ViewWidgets.INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(18)
	box.set_content_margin_all(8)
	box.content_margin_left = 14
	box.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	var round := StyleBoxFlat.new()
	round.bg_color = ViewWidgets.SKY
	round.set_corner_radius_all(6)
	dot.add_theme_stylebox_override("panel", round)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(dot)
	line.add_child(l)
	panel.add_child(line)
	_toast_box.add_child(panel)
	_toasts.append({"text": text, "left": TOAST_SECONDS, "node": panel})
	while _toasts.size() > TOAST_MAX:
		_drop(0)


func _drop(i: int) -> void:
	var t: Dictionary = _toasts[i]
	_toasts.remove_at(i)
	_toast_box.remove_child(t["node"])
	t["node"].queue_free()


func tick(delta: float) -> void:
	var i := 0
	while i < _toasts.size():
		_toasts[i]["left"] = float(_toasts[i]["left"]) - delta
		if float(_toasts[i]["left"]) <= 0.0:
			_drop(i)
		else:
			i += 1


func toasts() -> Array[String]:
	var out: Array[String] = []
	for t in _toasts:
		out.append(str(t["text"]))
	return out
