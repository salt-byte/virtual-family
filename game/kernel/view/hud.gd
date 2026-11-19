class_name Hud
extends CanvasLayer
## The always-on screen (design/UI_PLAN.md): the bottom bar, the "waiting for you" notices in
## the top-left corner, and the toasts. Shows status as words only.
## Bottom bar, left to right: the selected one (portrait, name, age and livelihood, what they
## are doing, their wish), praise / scold beside them, their status words as chips (only the
## ones that are wrong are loud), the household's money, larder and sky, and the buttons:
## the main three (family, shop, letters) big with icons, the rest small underneath.
## Reads the World; the only thing it writes is the praise/scold command through the session.

signal open(what: String)

const BAR_HEIGHT := 96.0
const TOAST_SECONDS := 3.0
const TOAST_MAX := 4
const BAR_BUTTONS := ["family", "shop", "letters", "ledger", "stories", "arrange", "settings"]
## Big buttons with icons on the top row; the rest sit small underneath.
const PRIMARY := ["family", "shop", "letters"]
const CHIPS_MAX := 4
## Status levels (ViewStrings.LEVELS) that show in the bar.
const LOUD := ["bad", "warn", "info"]
## Notices shown at once; the rest are counted under them.
const NOTICES_MAX := 5
const NOTICE_WIDTH := 300.0
const WHO_WIDTH := 250.0

var main: Main
var session: GameSession

var _bar: PanelContainer
var _avatar: Portrait
var _name: Label
var _line: Label
var _doing: Label
var _wish: Label
var _chips: HFlowContainer
var _chip_sig := ""
var _money: Label
var _stock: Label
var _sky: Label
var _cash_icons: Array[HudIcon] = []
var _buttons: Dictionary = {}  # id -> Button
var _praise: Button
var _scold: Button
var _toast_box: VBoxContainer
var _toasts: Array = []  # {text, left, label}
var _muted := ""
var _notice_box: VBoxContainer
var _notices: Array[Dictionary] = []
var _notice_sig := ""
## Uids of the people the view saw fall ill and not yet get better (the kernel's illness
## itself is never read here).
var _sick := {}


## The round portrait of the selected one: their colour, the first character of their name,
## a tomato ring (the colour of "selected").
class Portrait:
	extends Control
	var color := Color.GRAY:
		set(v):
			color = v
			queue_redraw()
	var initial := "":
		set(v):
			initial = v
			queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r - 1.0, ViewWidgets.ACCENT)
		draw_circle(c, r - 4.0, ViewWidgets.CREAM)
		draw_circle(c, r - 7.0, color)
		if initial != "":
			var font := get_theme_default_font()
			var fs := int(r * 0.95)
			var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(c.x - w * 0.5, c.y + fs * 0.36)
			draw_string_outline(font, at, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, ViewWidgets.INK)
			draw_string(font, at, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ViewWidgets.CREAM)


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
	row.add_theme_constant_override("separation", 12)
	_bar.add_child(row)

	# The selected one.
	_avatar = Portrait.new()
	_avatar.custom_minimum_size = Vector2(62, 62)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_avatar)
	var who := VBoxContainer.new()
	who.custom_minimum_size.x = WHO_WIDTH
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	row.add_child(who)
	# First line, the biggest: how they are right now (follows what they are doing).
	_doing = _one_line(19, ViewWidgets.INK)
	who.add_child(_doing)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	who.add_child(head)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 16)
	head.add_child(_name)
	_line = Label.new()
	_line.add_theme_color_override("font_color", ViewWidgets.MUTED)
	_line.add_theme_font_size_override("font_size", 13)
	_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line.clip_text = true
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_line)
	_wish = _one_line(13, ViewWidgets.WOOD)
	_wish.visible = false
	who.add_child(_wish)

	# Praise and scold, beside the one they are for.
	var judge := HBoxContainer.new()
	judge.add_theme_constant_override("separation", 6)
	judge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(judge)
	_praise = Button.new()
	_praise.text = s.t("btn.praise")
	_praise.pressed.connect(press.bind("praise"))
	ViewWidgets.round_button(_praise, ViewWidgets.CREAM, ViewWidgets.ACCENT)
	judge.add_child(_praise)
	_scold = Button.new()
	_scold.text = s.t("btn.scold")
	_scold.pressed.connect(press.bind("scold"))
	ViewWidgets.round_button(_scold, ViewWidgets.CREAM, ViewWidgets.WOOD)
	judge.add_child(_scold)

	# Their status words.
	_chips = HFlowContainer.new()
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 5)
	row.add_child(_chips)

	# The household: sky, money, larder.
	var cash := VBoxContainer.new()
	cash.alignment = BoxContainer.ALIGNMENT_CENTER
	cash.add_theme_constant_override("separation", 0)
	cash.custom_minimum_size.x = 124
	row.add_child(cash)
	_sky = _cash_line(cash, "sky", 14)
	_money = _cash_line(cash, "coin", 20)
	_stock = _cash_line(cash, "grain", 14)

	# The buttons: the main three on top, the rest small underneath.
	var grid := VBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 5)
	row.add_child(grid)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	top_row.alignment = BoxContainer.ALIGNMENT_END
	grid.add_child(top_row)
	var low_row := HBoxContainer.new()
	low_row.add_theme_constant_override("separation", 5)
	low_row.alignment = BoxContainer.ALIGNMENT_END
	grid.add_child(low_row)
	for id in BAR_BUTTONS:
		var big: bool = id in PRIMARY
		var b := _icon_button(s.t("btn." + id), id, big)
		b.pressed.connect(press.bind(id))
		(top_row if big else low_row).add_child(b)
		_buttons[id] = b
	_buttons["letters"].visible = false

	# Waiting for you: the top-left corner.
	_notice_box = VBoxContainer.new()
	_notice_box.position = Vector2(12, 12)
	_notice_box.custom_minimum_size.x = NOTICE_WIDTH
	_notice_box.add_theme_constant_override("separation", 5)
	_notice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notice_box)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_top = 12
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)


func _one_line(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = WHO_WIDTH
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _cash_line(parent: Control, icon: String, font_size: int) -> Label:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	var i := HudIcon.make(icon, 22.0 if font_size >= 20 else 17.0)
	line.add_child(i)
	_cash_icons.append(i)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	if font_size < 20:
		l.add_theme_color_override("font_color", ViewWidgets.INK.lightened(0.15))
	line.add_child(l)
	return l


## A bar button with a drawn icon left of its words; `big` for the main three.
func _icon_button(text: String, id: String, big: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var side := 22.0 if big else 15.0
	var left := 38.0 if big else 27.0
	if big:
		b.custom_minimum_size.y = 42
		b.add_theme_font_size_override("font_size", 17)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var bg := ViewWidgets.BUTTON
			match state:
				"hover":
					bg = bg.lightened(0.25)
				"pressed":
					bg = bg.darkened(0.08)
				"disabled":
					bg = Color(0.9, 0.88, 0.84)
			var st := ViewWidgets.button_style(bg, state == "pressed")
			st.content_margin_left = left
			st.content_margin_right = 13
			b.add_theme_stylebox_override(state, st)
	else:
		b.custom_minimum_size.y = 26
		ViewWidgets.small_button(b)
		for state in ["normal", "hover", "pressed", "disabled"]:
			(b.get_theme_stylebox(state) as StyleBoxFlat).content_margin_left = left
	var icon := HudIcon.make(id, side)
	icon.position = Vector2(left - side - 5.0, 0.0)
	b.add_child(icon)
	b.resized.connect(func(): icon.position.y = (b.size.y - side) * 0.5 - (1.0 if big else 0.5))
	return b


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
	for c in [_avatar, _name, _line, _doing, _chips]:
		c.visible = have
	for id in _buttons:
		if id != "letters":   # the letter view decides about its own button
			_buttons[id].visible = living or id == "settings"
	# The old-stories box only for a pack that has stories.
	_buttons["stories"].visible = living and w != null and not w.pack.stories.is_empty()
	_money.visible = w != null and w.phase != "invalid"
	if _money.visible:
		_money.text = s.t("money").replace("{n}", str(w.money))
	_cash_icons[1].visible = _money.visible
	var sky := s.sky_line(w) if living else ""
	_sky.visible = sky != ""
	_cash_icons[0].visible = _sky.visible
	_sky.text = sky
	_stock.visible = living
	_cash_icons[2].visible = living
	if living:
		var total := 0
		for k in w.stock:
			total += int(w.stock[k])
		_stock.text = s.t("stock").replace("{n}", str(total))
	var chips: Array[Dictionary] = []
	if p != null:
		_name.text = s.person_name(p)
		_line.text = s.person_line(p, w) if s.job_line(p) == "" else s.t("bar.age_job").format(
			{"age": s.person_line(p, w).split(" · ")[0], "job": s.job_line(p)})
		_doing.text = feeling_now(p)
		chips = s.status_chips(p, w)
		_avatar.color = PersonView.FEMALE if p.gender == "female" else (PersonView.MALE if p.gender == "male" else PersonView.OTHER)
		_avatar.initial = p.given.left(1)
	if pet != null:
		_name.text = s.pet_name(pet, w)
		_line.text = s.pet_line(pet, w)
		_doing.text = s.t("bar.doing").replace("{text}", s.pet_doing(pet, w))
		chips = s.pet_chips(pet, w)
		_avatar.color = HouseView.pack_color(PetSystem.kind_of(w.pack, pet), PetView.FALLBACK)
		_avatar.initial = pet.given.left(1)
	_fill_chips(chips)
	var wish := s.wish_text(p, w) if p != null else (s.pet_wish_text(pet, w) if pet != null else "")
	_wish.visible = wish != ""
	_wish.text = s.t("wish.line").replace("{text}", wish)
	var off := judge_disabled()
	_praise.disabled = off
	_scold.disabled = off
	_praise.visible = living
	_scold.visible = living
	_refresh_notices()


## The status words that need the player, as chips, the loudest first, at most CHIPS_MAX: a
## heavy word filled tomato, a worrying one ringed tomato, news (carrying a child) ringed
## wood. Words for needs that are fine or nearly fine are left out; with none left, one
## quiet line says all is well.
func _fill_chips(chips: Array[Dictionary]) -> void:
	var shown: Array[Dictionary] = []
	for c in chips:
		if c["level"] in LOUD and shown.size() < CHIPS_MAX:
			shown.append(c)
	var sig := str(shown) + str(chips.is_empty())
	if sig == _chip_sig:
		return
	_chip_sig = sig
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	if shown.is_empty() and not chips.is_empty():
		var fine := Label.new()
		fine.text = session.strings.t("status.fine")
		fine.add_theme_color_override("font_color", ViewWidgets.MUTED)
		fine.set_meta("level", "ok")
		_chips.add_child(fine)
	for c in shown:
		var level := str(c["level"])
		var bg: Color = {"bad": ViewWidgets.ACCENT, "warn": ViewWidgets.CREAM, "info": ViewWidgets.CREAM,
			"mild": ViewWidgets.PALE, "ok": ViewWidgets.PALE}[level]
		var edge: Color = {"bad": ViewWidgets.ACCENT, "warn": ViewWidgets.ACCENT, "info": ViewWidgets.WOOD,
			"mild": Color(0, 0, 0, 0), "ok": Color(0, 0, 0, 0)}[level]
		var ink: Color = {"bad": ViewWidgets.CREAM, "warn": ViewWidgets.ACCENT, "info": ViewWidgets.WOOD,
			"mild": ViewWidgets.INK, "ok": ViewWidgets.MUTED}[level]
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", ViewWidgets.chip_style(bg, edge))
		chip.set_meta("level", level)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		chip.add_child(line)
		if str(c["name"]) != "":
			var n := Label.new()
			n.text = str(c["name"])
			n.add_theme_font_size_override("font_size", 12)
			n.add_theme_color_override("font_color", ink if level == "bad" else ViewWidgets.MUTED)
			n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(n)
		var word := Label.new()
		word.text = str(c["word"])
		word.add_theme_font_size_override("font_size", 15)
		word.add_theme_color_override("font_color", ink)
		line.add_child(word)
		_chips.add_child(chip)


## The levels of the chips on show, in order; for tests.
func chip_levels() -> Array[String]:
	var out: Array[String] = []
	for c in _chips.get_children():
		out.append(str(c.get_meta("level")))
	return out


## HOOK (branch player-loop): the bar's first line, how `p` is right now. The kernel's
## "feeling now" sentence (driven by the current action: dragged to work they say they
## are working / worn out) replaces this placeholder, which says what they are doing.
func feeling_now(p: Person) -> String:
	return session.strings.t("bar.doing").replace("{text}", _doing_text(p))


## The "what they are doing" sentence (the plate's progress line shows how far along).
func _doing_text(p: Person) -> String:
	var s := session.strings
	var pv: PersonView = main.house.people.get(p.uid) if main.house != null else null
	# The person's plate holds the previous action's words through the short idle gap
	# between two actions; the bar says the same.
	return pv.doing_text() if pv != null else s.doing(p, session.world)


func judge_disabled() -> bool:
	return _selected() == null


## The bar button `id` (the letter view takes "letters" as its box button).
func button(id: String) -> Button:
	return _buttons.get(id)


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


# --- Waiting for you ---------------------------------------------------------------------

## What waits for the player now (see Notices), most urgent first.
func notices() -> Array[Dictionary]:
	return _notices


## The notices on show, one line each; for tests.
func notice_text() -> String:
	var parts: Array[String] = []
	_collect(_notice_box, parts)
	return "\n".join(parts)


## Clicks the notice with this id (also the test entry point); false when none has it.
func press_notice(id: String) -> bool:
	for n in _notices:
		if n["id"] == id:
			main.open_notice(n)
			return true
	return false


func _refresh_notices() -> void:
	_notices = Notices.collect(session.world, session.strings, _sick)
	var sig := ""
	for n in _notices:
		sig += "%s=%s|" % [n["id"], n["text"]]
	if sig == _notice_sig:
		return
	_notice_sig = sig
	for c in _notice_box.get_children():
		_notice_box.remove_child(c)
		c.queue_free()
	_notice_box.visible = not _notices.is_empty()
	if _notices.is_empty():
		return
	var s := session.strings
	var head := Label.new()
	head.text = "%s · %d" % [s.t("notice.head"), _notices.size()]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", ViewWidgets.CREAM)
	head.add_theme_color_override("font_outline_color", ViewWidgets.INK)
	head.add_theme_constant_override("outline_size", 6)
	_notice_box.add_child(head)
	for i in mini(_notices.size(), NOTICES_MAX):
		_notice_box.add_child(_notice_card(_notices[i]))
	if _notices.size() > NOTICES_MAX:
		var more := Label.new()
		more.text = s.t("notice.more").replace("{n}", str(_notices.size() - NOTICES_MAX))
		more.add_theme_font_size_override("font_size", 14)
		more.add_theme_color_override("font_color", ViewWidgets.CREAM)
		more.add_theme_color_override("font_outline_color", ViewWidgets.INK)
		more.add_theme_constant_override("outline_size", 5)
		_notice_box.add_child(more)


## One notice: an icon on a coloured disc, the words, a little arrow; the whole card clicks.
## Decisions and trouble carry the tomato edge, pickups the sky blue, the rest wood.
func _notice_card(n: Dictionary) -> Button:
	var tone := str(n["tone"])
	var edge: Color = {"decide": ViewWidgets.ACCENT, "trouble": ViewWidgets.ACCENT,
		"pickup": ViewWidgets.SKY, "soft": ViewWidgets.WOOD}[tone]
	var b := Button.new()
	b.custom_minimum_size = Vector2(NOTICE_WIDTH, 38)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var st := StyleBoxFlat.new()
		st.bg_color = ViewWidgets.CREAM if state == "normal" else (ViewWidgets.CREAM.lightened(0.4) if state == "hover" else ViewWidgets.PALE)
		st.border_color = ViewWidgets.INK
		st.set_border_width_all(2)
		st.border_width_left = 7
		st.border_color = edge if tone != "soft" else ViewWidgets.WOOD
		st.set_corner_radius_all(12)
		st.shadow_color = Color(0.29, 0.2, 0.14, 0.3)
		st.shadow_size = 4
		st.shadow_offset = Vector2(0, 2)
		b.add_theme_stylebox_override(state, st)
	b.pressed.connect(press_notice.bind(str(n["id"])))
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 14
	line.offset_right = -10
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)
	line.add_child(HudIcon.make(str(n["icon"]), 22.0))
	var l := Label.new()
	l.text = str(n["text"])
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ViewWidgets.INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(l)
	var arrow := Label.new()
	arrow.text = "›"
	arrow.add_theme_font_size_override("font_size", 20)
	arrow.add_theme_color_override("font_color", edge)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(arrow)
	return b


func _on_event(e: Dictionary) -> void:
	var type := str(e.get("type", ""))
	if type == "fell_ill":
		_sick[int(e["person"])] = true
	elif type == "cured" or type == "person_died":
		_sick.erase(int(e["person"]))
	if type == "pet_wish_granted" and main.house != null and main.house.pets.has(int(e.get("pet", -1))):
		var pet := PetSystem.find(session.world, int(e["pet"]))
		if pet != null:
			main.house.pets[pet.uid].float_text_up(str(PetSystem.kind_of(session.world.pack, pet).get("thanks", "")))
	if type == "clean_reward" and main.house != null and main.house.people.has(int(e.get("person", -1))):
		# The coins float up over whoever swept the last of it.
		main.house.people[int(e["person"])].float_text_up(session.strings.t("float.clean_reward").replace("{n}", str(int(e["amount"]))))
	var text := session.strings.event(e, session.world)
	if text == "":
		return
	if type == "collectible_spawned" and main.house != null:
		# Clicking it takes the view to where the thing lies.
		var uid := int(e.get("uid", -1))
		toast(text, func(): main.house.look_at_collectible(uid))
	else:
		toast(text)


# --- Toasts ------------------------------------------------------------------------------

## HOOK (branch player-loop): someone shows off what they earned (a line such as "今天挣了三十文！" from the
## pack). The words float up over them, and a gold pill with a coin stays at the top a little
## longer than a plain toast.
func earned(person: int, text: String) -> void:
	if main.house != null and main.house.people.has(person):
		main.house.people[person].float_text_up(text)
	toast(text, Callable(), "earn")


## Shows `text` at the top for a few seconds; with `on_click` the pill can be clicked (it
## then calls it and goes away). `style` "earn" is the gold pill with a coin (`earned`).
func toast(text: String, on_click := Callable(), style := "") -> void:
	# A cream pill with a sky-blue dot on the left (ART_DIRECTION section 4).
	var earn := style == "earn"
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ViewWidgets.INK)
	l.add_theme_font_size_override("font_size", 18 if earn else 16)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FFE9A8") if earn else ViewWidgets.CREAM
	box.border_color = Color("#C98A1E") if earn else ViewWidgets.INK
	box.set_border_width_all(3 if earn else 2)
	box.set_corner_radius_all(18)
	box.set_content_margin_all(8)
	box.content_margin_left = 14
	box.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if earn:
		line.add_child(HudIcon.make("coin", 24.0))
	else:
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
	var entry := {"text": text, "left": TOAST_SECONDS * (1.5 if earn else 1.0), "node": panel, "click": on_click}
	if on_click.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				click_toast(_toasts.find(entry)))
	_toasts.append(entry)
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


## Clicks the toast at `i` (also the test entry point): runs what it was given and closes it.
## False when it has nothing to do on a click.
func click_toast(i: int) -> bool:
	if i < 0 or i >= _toasts.size():
		return false
	var c: Callable = _toasts[i].get("click", Callable())
	if not c.is_valid():
		return false
	_drop(i)
	c.call()
	return true


func toasts() -> Array[String]:
	var out: Array[String] = []
	for t in _toasts:
		out.append(str(t["text"]))
	return out
