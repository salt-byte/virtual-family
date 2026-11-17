class_name Hud
extends CanvasLayer
## The bottom bar, the praise/scold buttons and the toasts. Shows status as words only.
## Reads the World; the only thing it writes is the praise/scold command through the session.

signal open(what: String)

const BAR_HEIGHT := 96.0
const TOAST_SECONDS := 3.0
const TOAST_MAX := 4
const BAR_BUTTONS := ["family", "shop", "ledger", "arrange", "settings"]

var main: Main
var session: GameSession

var _bar: PanelContainer
var _avatar: ColorRect
var _name: Label
var _line: Label
var _doing: Label
var _status: Label
var _money: Label
var _stock: Label
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
	row.add_child(_avatar)
	var who := VBoxContainer.new()
	who.custom_minimum_size.x = 150
	row.add_child(who)
	_name = Label.new()
	_line = Label.new()
	who.add_child(_name)
	who.add_child(_line)
	_doing = Label.new()
	_doing.custom_minimum_size.x = 220
	row.add_child(_doing)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_status)
	var cash := VBoxContainer.new()
	cash.custom_minimum_size.x = 110
	row.add_child(cash)
	_money = Label.new()
	_stock = Label.new()
	cash.add_child(_money)
	cash.add_child(_stock)
	for id in BAR_BUTTONS:
		var b := Button.new()
		b.text = s.t("btn." + id)
		b.pressed.connect(press.bind(id))
		row.add_child(b)
		_buttons[id] = b

	var top := HBoxContainer.new()
	top.position = Vector2(12, 12)
	root.add_child(top)
	_scold = Button.new()
	_scold.text = s.t("btn.scold")
	_scold.pressed.connect(press.bind("scold"))
	top.add_child(_scold)
	_praise = Button.new()
	_praise.text = s.t("btn.praise")
	_praise.pressed.connect(press.bind("praise"))
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


func _selected() -> Person:
	if not _living():
		return null
	var p := session.world.person(main.selected)
	return p if p != null and p.alive else null


func refresh() -> void:
	var w := session.world
	var s := session.strings
	var living := _living()
	var p := _selected()
	var have := p != null
	for c in [_avatar, _name, _line, _doing, _status, _stock]:
		c.visible = have if c != _stock else living
	for id in _buttons:
		_buttons[id].visible = living or id == "settings"
	_money.visible = w != null and w.phase != "invalid"
	if _money.visible:
		_money.text = s.t("money").replace("{n}", str(w.money))
	if living:
		var total := 0
		for k in w.stock:
			total += int(w.stock[k])
		_stock.text = s.t("stock").replace("{n}", str(total))
	if have:
		_name.text = s.person_name(p)
		_line.text = s.person_line(p, w)
		_doing.text = _doing_text(p)
		_status.text = s.status_line(p, w)
		_avatar.color = PersonView.FEMALE if p.gender == "female" else (PersonView.MALE if p.gender == "male" else PersonView.OTHER)
	var waiting := living and not w.proposals.is_empty()
	_buttons["family"].text = ("● " if waiting else "") + s.t("btn.family")
	var off := judge_disabled()
	_praise.disabled = off
	_scold.disabled = off
	_praise.visible = living
	_scold.visible = living


## The "what they are doing" sentence, with how far along it is when that is worth showing
## (not while idle, not for slow things like sleeping).
func _doing_text(p: Person) -> String:
	var s := session.strings
	var text := s.doing(p, session.world)
	var pv: PersonView = main.house.people.get(p.uid) if main.house != null else null
	if pv == null or p.current.is_empty() or pv.slow():
		return text
	var pct := int(pv.progress() * 100.0)
	return s.t("doing.progress").format({"text": text, "pct": pct})


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
	var text := session.strings.event(e, session.world)
	if text != "":
		toast(text)


func toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color.WHITE)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
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
