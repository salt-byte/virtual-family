class_name Hud
extends CanvasLayer
## The always-on screen (design/UI_PLAN.md): the bottom bar, the "waiting for you" notices in
## the top-left corner, and the toasts. Shows status as words only.
## Bottom bar, left to right: the selected one (their painted portrait when their look has
## one; "在做：" what they are doing, then the name with a small face and the feeling of the
## moment labelled as their mood, age and livelihood, their wish), praise / scold beside
## them, their needs as short meters (`NeedMeters`: the lowest pulses) with any other status
## (out, low mood, with child) as chips, the household's money, larder and sky, and the
## buttons: the main three (family, shop, letters) big with icons, the rest small underneath.
## Switching between people: small ◀ ▶ either side of the portrait, the family strip
## (`FamilyStrip`) just above the bar's left end, and Tab / Shift+Tab or ← / → while nothing
## else has the keyboard. Picking someone at home selects them and the view follows them
## (`Main.select`); someone away on an outing is only shown in the bar, the view stays put.
## What is in store for the one in the bar (food for an animal, snacks or clothes for a
## person) sits as quick buttons in a tray above the bar's right end (`CareTray`); an
## animal's needs show as meters like a person's.
## Reads the World; it writes the praise/scold command, and the tray's use_item / drag (send
## someone to look after an animal) commands, through the session.

signal open(what: String)

const BAR_HEIGHT := 96.0
const TOAST_SECONDS := 3.0
## Toasts on screen at once; the rest wait their turn in order.
const TOAST_VISIBLE := 2
## Toasts on screen and waiting together; past this the oldest is dropped.
const TOAST_MAX := 4
## Events that already show as a notice (Notices): they make no toast as well.
const NOTICE_EVENTS := ["collectible_spawned", "fell_ill", "pet_fell_ill", "pet_ran_away",
	"stray_arrived", "proposal_arrived", "wish_granted", "buyer_arrived"]
const BAR_BUTTONS := ["family", "shop", "goods", "letters", "ledger", "stories", "arrange", "settings"]
## Big buttons with icons on the top row; the rest sit small underneath.
const PRIMARY := ["family", "shop", "goods", "letters"]
const CHIPS_MAX := 4
## Status levels (ViewStrings.LEVELS) that show in the bar.
const LOUD := ["bad", "warn", "info"]
## Notices shown at once; the rest fold into one "还有 n 件" row that opens on a click.
const NOTICES_MAX := 3
## Notices that only tell (no answer wanted): they go FYI_SECONDS after they first show,
## or once clicked.
const FYI := ["pickup", "pickups", "thanks"]
const FYI_SECONDS := 10.0
const NOTICE_WIDTH := 330.0
## A notice card's height: its words on top, how to answer it underneath.
const NOTICE_HEIGHT := 50.0
## Where the toasts start while the festival board shows above them.
const FEST_TOAST_TOP := 82.0
const WHO_WIDTH := 236.0
## The family strip: its gap above the bar, its left edge, and the share of the screen's
## width it may take before its faces shrink (then scroll).
const STRIP_GAP := 6.0
const STRIP_LEFT := 12.0
const STRIP_SHARE := 0.5

var main: Main
var session: GameSession

var _bar: PanelContainer
var _avatar: Portrait
## The painted portrait of the selected one's look, in place of `_avatar` when there is one.
var _face: PersonPortrait
var _face_key := ""
## Who is in the house, faces above the bar's left end; and ◀ ▶ beside the portrait.
var _strip: FamilyStrip
var _prev: Arrow
var _next: Arrow
## Quick buttons for what is in store for the one in the bar.
var _tray: CareTray
var _name: Label
## The feeling of the moment beside the name, labelled as their mood, with a small face.
var _mood_box: HBoxContainer
var _mood_face: NeedMeters.Face
var _mood: Label
var _meters: NeedMeters
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
## "出门": the places the selected person could be sent to (`OutingSystem.options`).
var _go_out: Button
## The festival on: a board top middle, its name in the title face and the time left.
var _fest_box: PanelContainer
var _fest_title: Label
var _fest_left: Label
var _toast_box: VBoxContainer
## On screen first (at most TOAST_VISIBLE, in `_toast_box`), then the waiting ones:
## {text, left, node (null while waiting), click, style}.
var _toasts: Array = []
var _muted := ""
var _notice_box: VBoxContainer
var _notices: Array[Dictionary] = []
var _notice_sig := ""
var _expanded := false
## Seconds the HUD has ticked (for FYI notices); notice id -> when it first showed.
var _clock := 0.0
var _shown_at := {}
var _dismissed := {}
## Uids of the people the view saw fall ill and not yet get better (the kernel's illness
## itself is never read here).
var _sick := {}
## Items that came into store since the goods panel last showed them (item id -> true): their
## cards wear a "新" badge. `_known` is the store as last seen.
var new_goods := {}
var _known := {}
var _known_set := false
## The control blinking to draw the eye after a notice was clicked (`pulse_control`).
var _pulse_tween: Tween
var _pulse_node: Control
var _pulsing := ""
const PULSE_TIMES := 4
const PULSE_COLOR := Color(1.5, 1.15, 0.7)


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


## A small ◀ / ▶ beside the portrait: a wood triangle on a cream pill; a click steps
## through the family (`cycle`).
class Arrow:
	extends Control
	var step := 1
	var hud: Hud
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 34)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _set_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			accept_event()
			if hud != null:
				hud.cycle(step)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bg := StyleBoxFlat.new()
		bg.bg_color = ViewWidgets.BUTTON.lightened(0.25) if _hover else ViewWidgets.CREAM
		bg.border_color = ViewWidgets.WOOD
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(int(size.x * 0.5))
		draw_style_box(bg, r)
		var c := size * 0.5
		var h := 6.0
		var tip := 3.5 * float(step)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-tip, -h), c + Vector2(-tip, h), c + Vector2(tip, 0)]),
			ViewWidgets.ACCENT if _hover else ViewWidgets.WOOD)


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

	# The selected one, with ◀ ▶ either side to step through the family.
	var face_box := HBoxContainer.new()
	face_box.add_theme_constant_override("separation", 2)
	row.add_child(face_box)
	_prev = Arrow.new()
	_prev.step = -1
	_prev.hud = self
	_prev.tooltip_text = s.t("bar.prev") if s.has("bar.prev") else "上一位"
	face_box.add_child(_prev)
	_avatar = Portrait.new()
	_avatar.custom_minimum_size = Vector2(62, 62)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face_box.add_child(_avatar)
	_face = PersonPortrait.make(null, null, null, Vector2(62, 62))
	_face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_face.visible = false
	face_box.add_child(_face)
	_next = Arrow.new()
	_next.step = 1
	_next.hud = self
	_next.tooltip_text = s.t("bar.next") if s.has("bar.next") else "下一位"
	face_box.add_child(_next)
	var who := VBoxContainer.new()
	who.custom_minimum_size.x = WHO_WIDTH
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	row.add_child(who)
	# First line, the biggest: what they are doing ("在做：...").
	_doing = _one_line(18, ViewWidgets.INK)
	who.add_child(_doing)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	who.add_child(head)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 16)
	ViewWidgets.use_title_font(_name)
	head.add_child(_name)
	# Their mood: a small face, the word "心情" quiet, then the feeling of the moment.
	_mood_box = HBoxContainer.new()
	_mood_box.add_theme_constant_override("separation", 3)
	_mood_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_mood_box)
	_mood_face = NeedMeters.Face.new()
	_mood_box.add_child(_mood_face)
	var tag := Label.new()
	tag.text = s.t("bar.mood")
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", ViewWidgets.MUTED)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mood_box.add_child(tag)
	_mood = Label.new()
	_mood.add_theme_font_size_override("font_size", 14)
	_mood.add_theme_color_override("font_color", ViewWidgets.WOOD)
	_mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mood_box.add_child(_mood)
	_line = Label.new()
	_line.add_theme_color_override("font_color", ViewWidgets.MUTED)
	_line.add_theme_font_size_override("font_size", 12)
	_line.clip_text = true
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(_line)
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
	_go_out = Button.new()
	_go_out.text = s.t("btn.go_out")
	_go_out.pressed.connect(press.bind("go_out"))
	ViewWidgets.small_button(_go_out)
	_go_out.custom_minimum_size.y = 30
	_go_out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	judge.add_child(_go_out)

	# Their needs as meters, then any other status as chips.
	_meters = NeedMeters.new()
	row.add_child(_meters)
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
	ViewWidgets.use_title_font(_money)
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

	# The family strip, just above the bar's left end.
	_strip = FamilyStrip.new()
	_strip.anchor_left = 0.0
	_strip.anchor_right = 0.0
	_strip.anchor_top = 1.0
	_strip.anchor_bottom = 1.0
	_strip.offset_left = STRIP_LEFT
	_strip.offset_bottom = -(BAR_HEIGHT + STRIP_GAP)
	_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_strip.visible = false
	_strip.picked.connect(switch_to)
	root.add_child(_strip)

	# What is in store for them, above the bar's right end.
	_tray = CareTray.new()
	_tray.anchor_left = 1.0
	_tray.anchor_right = 1.0
	_tray.anchor_top = 1.0
	_tray.anchor_bottom = 1.0
	_tray.offset_right = -STRIP_LEFT
	_tray.offset_bottom = -(BAR_HEIGHT + STRIP_GAP)
	_tray.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tray.visible = false
	_tray.chosen.connect(use_care)
	_tray.dropped.connect(drop_care)
	root.add_child(_tray)

	# Waiting for you: the top-left corner.
	_notice_box = VBoxContainer.new()
	_notice_box.position = Vector2(12, 12)
	_notice_box.custom_minimum_size.x = NOTICE_WIDTH
	_notice_box.add_theme_constant_override("separation", 5)
	_notice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notice_box)

	# The festival board, top middle (the toasts drop below it while it shows).
	_fest_box = PanelContainer.new()
	_fest_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fest_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fest_box.offset_top = 10
	_fest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var board := ViewWidgets.chip_style(ViewWidgets.ACCENT, ViewWidgets.INK)
	board.set_corner_radius_all(14)
	board.set_border_width_all(2)
	board.content_margin_left = 16
	board.content_margin_right = 16
	board.content_margin_top = 6
	board.content_margin_bottom = 6
	board.shadow_color = Color(0.29, 0.2, 0.14, 0.3)
	board.shadow_size = 4
	board.shadow_offset = Vector2(0, 2)
	_fest_box.add_theme_stylebox_override("panel", board)
	var fest_col := VBoxContainer.new()
	fest_col.add_theme_constant_override("separation", 0)
	fest_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fest_box.add_child(fest_col)
	_fest_title = Label.new()
	_fest_title.add_theme_font_size_override("font_size", 24)
	_fest_title.add_theme_color_override("font_color", ViewWidgets.CREAM)
	_fest_title.add_theme_color_override("font_outline_color", ViewWidgets.INK)
	_fest_title.add_theme_constant_override("outline_size", 5)
	_fest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ViewWidgets.use_title_font(_fest_title)
	fest_col.add_child(_fest_title)
	_fest_left = Label.new()
	_fest_left.add_theme_font_size_override("font_size", 13)
	_fest_left.add_theme_color_override("font_color", ViewWidgets.CREAM)
	_fest_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fest_col.add_child(_fest_left)
	_fest_box.visible = false
	root.add_child(_fest_box)

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
	for c in [_avatar, _name, _line, _doing, _chips, _meters]:
		c.visible = have
	_face.visible = false
	_mood_box.visible = false
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
		_doing.text = s.t("bar.doing").replace("{text}", _doing_text(p))
		var feel := FeelingSystem.now(w, p)
		_mood_box.visible = feel != ""
		_mood.text = feel
		_mood_face.value = float(p.needs.get(str(w.pack.cfg("praise_need")), 70.0)) if p.mood == "" else 10.0
		# Only what is not a need: the needs have their meters.
		chips = s.status_chips(p, w).filter(func(c): return str(c["need"]) == "")
		_meters.show_person(p, w.pack)
		_avatar.color = PersonView.FEMALE if p.gender == "female" else (PersonView.MALE if p.gender == "male" else PersonView.OTHER)
		_avatar.initial = p.given.left(1)
		_show_face(p)
	if pet != null:
		_name.text = s.pet_name(pet, w)
		_line.text = s.pet_line(pet, w)
		_doing.text = s.t("bar.doing").replace("{text}", s.pet_doing(pet, w))
		# Its needs as meters, like a person's; the chips keep what is not a need (ill).
		chips = s.pet_chips(pet, w).filter(func(c): return str(c["need"]) == "")
		_meters.set_entries(pet_meters(pet))
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
	_go_out.visible = p != null and p.stage(w.pack) != "baby"
	_go_out.disabled = p != null and OutingSystem.away(w, p)
	var fest := s.festival_banner(w) if w != null else {"banner": "", "left": ""}
	_fest_box.visible = fest["banner"] != ""
	_fest_title.text = fest["banner"]
	_fest_left.text = fest["left"]
	_toast_box.offset_top = FEST_TOAST_TOP if _fest_box.visible else 12.0
	_track_new_goods(w)
	_refresh_notices()
	_refresh_switcher()
	_refresh_tray(p, pet)


## Marks what came into store since the last look as new (not what a loaded save holds).
func _track_new_goods(w: World) -> void:
	if w == null or w.phase != "living":
		return
	for id in w.inventory:
		var n := int(w.inventory[id])
		if _known_set and n > int(_known.get(id, 0)):
			new_goods[str(id)] = true
		elif n <= 0:
			new_goods.erase(str(id))
	_known = w.inventory.duplicate()
	_known_set = true


## `p`'s painted portrait in place of the coloured round, when their look has one (an old
## save's "" look gets the view's stand-in, `ViewLooks`).
func _show_face(p: Person) -> void:
	var skin := _skin()
	var look := ViewLooks.of(p, session.world.pack)
	var key := "%d|%s" % [p.uid, look]
	if key != _face_key:
		_face_key = key
		_face.person = p
		_face.skin = skin
		_face.pack = session.world.pack
		_face.look = look
		_face._portrait = _face.portrait()
	_face.visible = _face._portrait != null
	_avatar.visible = not _face.visible


func _skin() -> PackSkin:
	return main.house.skin if main.house != null and "skin" in main.house else null


# --- Switching between people ------------------------------------------------------------

## The living people of the house, in the world's order (whoever is away included).
func family() -> Array[Person]:
	var out: Array[Person] = []
	if not _living():
		return out
	for p in session.world.people:
		if p.alive:
			out.append(p)
	return out


## Shows `uid` in the bar. Someone at home is selected and the view follows them (a smooth
## pan, `HouseView.follow`); someone away on an outing is shown without moving the view.
func switch_to(uid: int) -> void:
	var p := session.world.person(uid) if _living() else null
	if p == null or not p.alive:
		return
	if OutingSystem.away(session.world, p):
		main.select(uid, false)
		if main.house != null:
			main.house.unfollow()
	else:
		main.select(uid)


## Steps `step` (+1 next, -1 back) through the family from the one in the bar, round the
## ends. With an animal in the bar it starts from the person last shown.
func cycle(step: int) -> void:
	var fam := family()
	if fam.size() < 2 and not (fam.size() == 1 and main.selected_pet >= 0):
		return
	var at := -1
	for i in fam.size():
		if fam[i].uid == main.selected:
			at = i
	var to := 0 if at < 0 else posmod(at + (0 if main.selected_pet >= 0 else step), fam.size())
	switch_to(fam[to].uid)


## Tab / Shift+Tab and ← / → step through the family while nothing else has the keyboard
## (no focused control, no panel or overlay over the house).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	var step := 0
	if k == KEY_TAB:
		step = -1 if (event as InputEventKey).shift_pressed else 1
	elif k == KEY_LEFT:
		step = -1
	elif k == KEY_RIGHT:
		step = 1
	if step == 0 or not _living() or main.is_house_blocked():
		return
	var vp := get_viewport()
	if vp != null and vp.gui_get_focus_owner() != null:
		return
	cycle(step)
	if vp != null:
		vp.set_input_as_handled()


## For the strip: {away, dot} for person `uid`. The dot is tomato while they are ill or a
## need has gone bad (their notice), wood while an ask or a wish waits (their bubble, or
## the wish's notice); transparent for nothing.
func switcher_info(uid: int) -> Dictionary:
	var w := session.world
	var p := w.person(uid)
	var away := p != null and OutingSystem.away(w, p)
	var dot := Color(0, 0, 0, 0)
	var kinds := {}
	for n in _notices:
		if int(n.get("target", -1)) == uid:
			kinds[str(n["kind"])] = true
	if kinds.has("ill") or kinds.has("need"):
		dot = ViewWidgets.ACCENT
	elif kinds.has("wish") or (p != null and not NeedBubble.of(w, p).is_empty()):
		dot = ViewWidgets.WOOD
	return {"away": away, "dot": dot}


func _refresh_switcher() -> void:
	var fam := family()
	var many := fam.size() >= 2
	_prev.visible = many
	_next.visible = many
	_strip.visible = many
	if not many:
		return
	var vw := _strip.get_viewport_rect().size.x if _strip.is_inside_tree() else 1280.0
	_strip.show_people(fam, main.selected if main.selected_pet < 0 else -1, switcher_info, _skin(),
		session.world.pack, session.strings, vw * STRIP_SHARE - STRIP_LEFT)
	var ms := _strip.get_combined_minimum_size()
	_strip.offset_top = -(BAR_HEIGHT + STRIP_GAP) - ms.y
	_strip.offset_right = STRIP_LEFT + ms.x


## An animal's needs for the meters: [{id, name, value}] in the pack's order.
func pet_meters(pet: Pet) -> Array:
	var out: Array = []
	for n in PetSystem.need_list(session.world.pack):
		var nid := str(n.get("id", ""))
		if pet.needs.has(nid):
			out.append({"id": nid, "name": str(n.get("short", n.get("name", nid))), "value": float(pet.needs[nid])})
	return out


func _refresh_tray(p: Person, pet: Pet) -> void:
	var entries := CareTray.options(session.world, p, pet, session.strings, p != null and _sick.has(p.uid)) if _living() else ([] as Array[Dictionary])
	var arranging: bool = main.arrange != null and main.arrange.active
	_tray.visible = not entries.is_empty() and not arranging
	if not _tray.visible:
		return
	var vw := _tray.get_viewport_rect().size.x if _tray.is_inside_tree() else 1280.0
	_tray.show_entries(entries, session.strings, vw * (1.0 - STRIP_SHARE) - STRIP_LEFT * 2.0)
	var ms := _tray.get_combined_minimum_size()
	_tray.offset_top = -(BAR_HEIGHT + STRIP_GAP) - ms.y
	_tray.offset_left = -STRIP_LEFT - ms.x


## Whether the view saw `uid` fall ill and not yet get better.
func seen_sick(uid: int) -> bool:
	return _sick.has(uid)


## The tray; for tests.
func tray() -> CareTray:
	return _tray


## Carries out a tray choice (`CareTray.options`): uses the item, sends someone to look after
## the animal, or opens the market where its food is sold.
func use_care(e: Dictionary) -> void:
	match str(e.get("kind", "")):
		"use":
			var cmd := {"type": "use_item", "item": str(e["item"])}
			if e.has("pet"):
				cmd["pet"] = int(e["pet"])
			else:
				cmd["person"] = int(e["person"])
			var r := session.command(cmd)
			if r.get("ok", false):
				var view = main.house.pets.get(int(e["pet"])) if e.has("pet") else main.house.people.get(int(e["person"]))
				if view != null:
					view.float_text_up(str(e["name"]))
		"call":
			call_carer(int(e["pet"]))
		"treat":
			session.command({"type": "drag", "person": int(e["healer"]), "treat": int(e["person"])})
		"doctor":
			call_doctor(int(e["person"]))
		"all":
			main.arrange.exit()
			main.letters.close()
			main.settings.close()
			main.panels.open("goods")
		"shop":
			open.emit("shop")
			var tab := Panels.MARKET_TAB + str(e.get("tab", ""))
			main.panels.press(tab if main.panels.has_button(tab) else "tab.pets")
	refresh()


## An item dragged out of the tray and let go over the house: used on the person or animal
## under the pointer (whoever it suits; the kernel says no otherwise). False when nobody is
## there.
func drop_care(e: Dictionary, screen: Vector2) -> bool:
	if main.house == null or str(e.get("kind", "")) != "use" or main.is_house_blocked():
		return false
	var at := main.house.world_pos(screen)
	var cmd := {"type": "use_item", "item": str(e["item"])}
	var pet := main.house.pet_at(at)
	var who := main.house.person_at(at) if pet < 0 else -1
	if pet >= 0:
		cmd["pet"] = pet
	elif who >= 0:
		cmd["person"] = who
	else:
		return false
	var r := session.command(cmd)
	if r.get("ok", false):
		var view = main.house.pets.get(pet) if pet >= 0 else main.house.people.get(who)
		if view != null:
			view.float_text_up(str(e["name"]))
	refresh()
	return true


## "请郎中" (the pack's doctor service, `ServiceSystem` "doctor") for the sick person `uid`:
## the command's result.
func call_doctor(uid: int) -> Dictionary:
	var sid := ServiceSystem.first_of(session.world.pack, "doctor")
	if sid == "":
		return {}
	var r := session.command({"type": "buy_service", "service": sid, "person": uid})
	refresh()
	return r


## "叫人来喂": the nearest family member at home who can look after the animal now (the idle
## ones first) is sent to it, as if the player had dropped them on it. Uid of who went, or -1
## (then a toast says nobody is free).
func call_carer(pet_uid: int) -> int:
	var w := session.world
	var pet := PetSystem.find(w, pet_uid)
	if pet == null or not pet.home():
		return -1
	var where: Vector2 = main.house.pets[pet_uid].position if main.house != null and main.house.pets.has(pet_uid) else Vector2.ZERO
	var ranked: Array = []
	for p in family():
		if OutingSystem.away(w, p) or PetSystem.held(w, pet, p) or not _can_care(w, p, pet):
			continue
		var pv = main.house.people.get(p.uid) if main.house != null else null
		var d: float = (pv.position as Vector2).distance_to(where) if pv != null else 0.0
		ranked.append([p.uid, (0.0 if p.current.is_empty() else 100000.0) + d])
	ranked.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	for r in ranked:
		var res := session.command({"type": "drag", "person": int(r[0]), "pet": pet_uid})
		if res.get("ok", false):
			return int(r[0])
	if ranked.is_empty():
		toast(CareTray.word(session.strings, "care.nobody"))
	return -1


## Whether `p` could start some care action for `pet` now (`Commands._drag_to_pet`'s test,
## asked first so a refusal does not toast for everyone tried).
func _can_care(w: World, p: Person, pet: Pet) -> bool:
	for id in w.pack.actions:
		var a: Dictionary = w.pack.actions[id]
		if AutonomySystem.target_kind(a) != AutonomySystem.TARGET_PET or not PetSystem.suits(a, pet):
			continue
		var why := AutonomySystem.can_do(w, p, str(id), -1)
		if why == "" or why == "no_target":
			return true
	return false


## The family strip; for tests.
func strip() -> FamilyStrip:
	return _strip


## The ◀ (-1) or ▶ (+1) beside the portrait; for tests.
func arrow(step: int) -> Control:
	return _prev if step < 0 else _next


## The meters on show: [{id, name, value}]; for tests.
func meters() -> Array:
	return _meters.entries if _meters.visible else []


## The need whose meter pulses ("" for none); for tests.
func pulsing_need() -> String:
	return _meters.pulsing() if _meters.visible else ""


## The status words that need the player, as chips, the loudest first, at most CHIPS_MAX: a
## heavy word filled tomato, a worrying one ringed tomato, news (carrying a child) ringed
## wood. For a person only what is not a need comes here (the needs have their meters); for
## an animal its need words too, and with nothing wrong one quiet line says all is well.
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
	if shown.is_empty() and not chips.is_empty() and not _meters.visible:
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


## The bar's first line, how `p` is right now: the kernel's feeling of the moment
## (`FeelingSystem.now`: dragged to work "干活呢 · 有点累", just bathed "清清爽爽"), or what
## they are doing in a pack without feelings.
func feeling_now(p: Person) -> String:
	var feel := FeelingSystem.now(session.world, p)
	if feel != "":
		return feel
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


## The bar button `id` (the letter view takes "letters" as its box button; "go_out" is the
## one beside praise and scold).
func button(id: String) -> Button:
	if id == "go_out":
		return _go_out
	return _buttons.get(id)


## Screen rects the HUD covers at the top (the notices, the festival board, the toasts),
## for things in the scene that should keep clear of them (the letter bird).
func top_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in [_notice_box, _fest_box, _toast_box]:
		if c.visible and c.is_inside_tree():
			var r: Rect2 = (c as Control).get_global_rect()
			if r.size.x > 0.0 and r.size.y > 0.0:
				out.append(r.grow(8.0))
	# The notices may unfold: keep clear of where three of them sit even while fewer show.
	if _notice_box.visible:
		out.append(Rect2(_notice_box.position, Vector2(NOTICE_WIDTH, (NOTICE_HEIGHT + 6.0) * (NOTICES_MAX + 1) + 30.0)).grow(8.0))
	return out


## The festival board's words ("" while no festival is on); for tests.
func festival_text() -> String:
	return "%s %s" % [_fest_title.text, _fest_left.text] if _fest_box.visible else ""


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
	elif what == "go_out":
		if _selected() != null:
			open.emit("go_out")
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
			if n["kind"] in FYI:
				_dismissed[id] = true   # seen: a passing notice goes once clicked
			main.open_notice(n)
			return true
	return false


## Opens or folds the notices beyond the first NOTICES_MAX (the "还有 n 件" row).
func toggle_notices() -> void:
	_expanded = not _expanded
	_notice_sig = ""
	_refresh_notices()


## True while the folded notices are shown.
func notices_expanded() -> bool:
	return _expanded


func _refresh_notices() -> void:
	var all := Notices.collect(session.world, session.strings, _sick)
	# A passing notice (FYI) stays FYI_SECONDS from when it first showed, or until clicked.
	var live := {}
	_notices = []
	for n in all:
		var id := str(n["id"])
		live[id] = true
		if n["kind"] in FYI:
			if not _shown_at.has(id):
				_shown_at[id] = _clock
			if _dismissed.has(id) or _clock - float(_shown_at[id]) >= FYI_SECONDS:
				continue
		_notices.append(n)
	for id in _shown_at.keys():
		if not live.has(id):
			_shown_at.erase(id)
			_dismissed.erase(id)
	if _notices.size() <= NOTICES_MAX:
		_expanded = false
	var sig := "%s|%s" % [_expanded, session.world == null or session.world.doctor.is_empty()]
	for n in _notices:
		sig += "%s=%s/%s/%s|" % [n["id"], n["text"], n.get("hint", ""), (n.get("act", {}) as Dictionary).get("text", "")]
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
	ViewWidgets.use_title_font(head)
	_notice_box.add_child(head)
	var shown := _notices.size() if _expanded else mini(_notices.size(), NOTICES_MAX)
	for i in shown:
		_notice_box.add_child(_notice_card(_notices[i]))
	if _notices.size() > NOTICES_MAX:
		var more := Button.new()
		more.text = s.t("notice.fold") if _expanded else s.t("notice.more").replace("{n}", str(_notices.size() - NOTICES_MAX))
		ViewWidgets.small_button(more)
		more.focus_mode = Control.FOCUS_NONE
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more.pressed.connect(toggle_notices)
		_notice_box.add_child(more)


## The small "请郎中" button on a sick person's notice (null without a doctor service or while
## a visit is on: the notice's words then say the visitor is on the way).
func _doctor_chip(uid: int) -> Button:
	var w := session.world
	var sid := ServiceSystem.first_of(w.pack, "doctor")
	if sid == "" or not w.doctor.is_empty():
		return null
	var b := Button.new()
	b.text = session.strings.t("notice.doctor").replace("{visitor}", session.strings.visitor_name(w, sid))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	ViewWidgets.round_button(b, ViewWidgets.ACCENT, ViewWidgets.CREAM)
	for state in ["normal", "hover", "pressed"]:
		var st := b.get_theme_stylebox(state) as StyleBoxFlat
		if st != null:
			st.set_content_margin_all(3)
			st.content_margin_left = 9
			st.content_margin_right = 9
			st.border_width_bottom = 2
	b.pressed.connect(func(): call_doctor(uid))
	b.set_meta("doctor_for", uid)
	return b


## The small button on a notice that answers it at once (`Notices` `act`).
func _act_chip(notice_id: String, act: Dictionary) -> Button:
	var b := Button.new()
	b.text = str(act["text"])
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	ViewWidgets.round_button(b, ViewWidgets.CREAM, ViewWidgets.ACCENT)
	for state in ["normal", "hover", "pressed"]:
		var st := b.get_theme_stylebox(state) as StyleBoxFlat
		if st != null:
			st.set_content_margin_all(3)
			st.content_margin_left = 9
			st.content_margin_right = 9
			st.border_width_bottom = 2
	b.pressed.connect(func(): notice_act(notice_id))
	b.set_meta("act_for", notice_id)
	return b


## Presses the answer button of the notice with this id (also the test entry point); false
## when that notice has none. "praise:<uid>" praises them, "use:<uid>:<item>" and
## "feed:<pet>:<item>" give what is in store, "call:<pet>" sends someone to the animal,
## "go_out:<uid>" opens where they could go, "shop:<section>" opens the market there.
func notice_act(notice_id: String) -> bool:
	var n := {}
	for x in _notices:
		if x["id"] == notice_id:
			n = x
	var act: Dictionary = n.get("act", {})
	if act.is_empty():
		return false
	var parts := str(act["id"]).split(":")
	var who := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	match parts[0]:
		"praise":
			main.select(who)
			press("praise")
		"use":
			main.select(who)
			use_care({"kind": "use", "item": parts[2], "person": who, "name": Notices._item_name(session.world, parts[2])})
		"feed":
			main.select_pet(who)
			use_care({"kind": "use", "item": parts[2], "pet": who, "name": Notices._item_name(session.world, parts[2])})
		"call":
			main.select_pet(who)
			call_carer(who)
		"go_out":
			main.select(who)
			press("go_out")
		"shop":
			if n.get("kind", "") in ["wish", "ask", "need"]:
				main.select(int(n["target"]))
			elif n.get("kind", "") in ["pet_ill", "pet_hungry"]:
				main.select_pet(int(n["target"]))
			open_market(parts[1])
		_:
			return false
	refresh()
	return true


## Opens the market on section `section` (its first tab when the pack has no such tab).
func open_market(section: String) -> void:
	main.panels.open("shop")
	var tab := Panels.MARKET_TAB + section
	if main.panels.has_button(tab):
		main.panels.press(tab)


## What a click on a notice points at (`Notices` `guide`): pulses a control of the bar, marks
## things in the house, or opens the market.
func guide(g: Dictionary) -> void:
	var pulse := str(g.get("pulse", ""))
	if pulse != "":
		pulse_control(pulse)
	if g.has("objects") or g.has("pets"):
		main.house.show_guide(g.get("objects", []), g.get("pets", []))
	if g.has("shop"):
		open_market(str(g["shop"]))


## Makes control `id` blink a few times to draw the eye: "praise", "go_out", or a tray
## button "tray:<kind>:<item>" (the item may be left out). False when it is not on show.
func pulse_control(id: String) -> bool:
	var c: Control = null
	if id == "praise":
		c = _praise
	elif id == "go_out":
		c = _go_out
	elif id.begins_with("tray:"):
		var parts := id.split(":")
		c = _tray.button_for(parts[1], parts[2] if parts.size() > 2 else "")
	if c == null or not c.visible:
		return false
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		if is_instance_valid(_pulse_node):
			_pulse_node.modulate = Color.WHITE
	_pulsing = id
	_pulse_node = c
	if c.is_inside_tree():
		_pulse_tween = c.create_tween().set_loops(PULSE_TIMES)
		_pulse_tween.tween_property(c, "modulate", PULSE_COLOR, 0.3)
		_pulse_tween.tween_property(c, "modulate", Color.WHITE, 0.3)
		_pulse_tween.finished.connect(func(): _pulsing = "")
	return true


## The control blinking now ("" for none); for tests.
func pulsing() -> String:
	return _pulsing if _pulse_tween != null and _pulse_tween.is_valid() else ""


## The answer button on the notice with this id; null when none shows. For tests.
func act_chip(notice_id: String) -> Button:
	return _find_by_meta(_notice_box, "act_for", notice_id) as Button


## The how-to line under the notice with this id ("" when none shows); for tests.
func notice_hint(notice_id: String) -> String:
	var l := _find_by_meta(_notice_box, "hint_for", notice_id) as Label
	return l.text if l != null else ""


func _find_by_meta(n: Node, key: String, value: String) -> Node:
	if n.has_meta(key) and str(n.get_meta(key)) == value:
		return n
	for c in n.get_children():
		var f := _find_by_meta(c, key, value)
		if f != null:
			return f
	return null


## The "请郎中" button on the notice for `uid`; null when none shows. For tests.
func doctor_chip(uid: int) -> Button:
	for c in _notice_box.get_children():
		var found := _find_meta(c, uid)
		if found != null:
			return found
	return null


func _find_meta(n: Node, uid: int) -> Button:
	if n is Button and n.has_meta("doctor_for") and int(n.get_meta("doctor_for")) == uid:
		return n
	for c in n.get_children():
		var f := _find_meta(c, uid)
		if f != null:
			return f
	return null


## One notice: an icon on a coloured disc, the words, a little arrow; the whole card clicks.
## Decisions and trouble carry the tomato edge, pickups the sky blue, the rest wood.
func _notice_card(n: Dictionary) -> Button:
	var tone := str(n["tone"])
	var edge: Color = {"decide": ViewWidgets.ACCENT, "trouble": ViewWidgets.ACCENT,
		"pickup": ViewWidgets.SKY, "soft": ViewWidgets.WOOD}[tone]
	var b := Button.new()
	b.custom_minimum_size = Vector2(NOTICE_WIDTH, NOTICE_HEIGHT if str(n.get("hint", "")) != "" else 38.0)
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
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", -2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var l := Label.new()
	l.text = str(n["text"])
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ViewWidgets.INK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(l)
	if str(n.get("hint", "")) != "":
		# How to answer it, small and quiet under the words.
		var h := Label.new()
		h.text = str(n["hint"])
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", ViewWidgets.MUTED)
		h.clip_text = true
		h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_meta("hint_for", str(n["id"]))
		words.add_child(h)
	if str(n["kind"]) == "ill":
		var call := _doctor_chip(int(n["target"]))
		if call != null:
			line.add_child(call)
	var act: Dictionary = n.get("act", {})
	if not act.is_empty():
		line.add_child(_act_chip(str(n["id"]), act))
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
	if type == "doctor_diagnosed" and main.house != null:
		main.house.visitor_say(str(e.get("line", "")))
	if type == "fell_ill":
		_sick[int(e["person"])] = true
	elif type == "cured" or type == "person_died":
		_sick.erase(int(e["person"]))
	if type == "pet_wish_granted" and main.house != null and main.house.pets.has(int(e.get("pet", -1))):
		var pet := PetSystem.find(session.world, int(e["pet"]))
		if pet != null:
			main.house.pets[pet.uid].float_text_up(str(PetSystem.kind_of(session.world.pack, pet).get("thanks", "")))
	if type == "shared":
		# Someone turned to the screen to tell what they earned (`ShareSystem`).
		var who := session.world.person(int(e.get("person", -1)))
		if who != null:
			earned(who.uid, ShareSystem.format(session.world, who, e))
		return
	if type == "clean_reward" and main.house != null and main.house.people.has(int(e.get("person", -1))):
		# The coins float up over whoever swept the last of it.
		main.house.people[int(e["person"])].float_text_up(session.strings.t("float.clean_reward").replace("{n}", str(int(e["amount"]))))
	# What shows as a notice is not told twice.
	if type in NOTICE_EVENTS:
		return
	var text := session.strings.event(e, session.world)
	if text != "":
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
## At most TOAST_VISIBLE are on screen; the rest wait their turn. The same words already on
## screen or waiting are not added again.
func toast(text: String, on_click := Callable(), style := "") -> void:
	for t in _toasts:
		if t["text"] == text:
			return
	var earn := style == "earn"
	_toasts.append({"text": text, "left": TOAST_SECONDS * (1.5 if earn else 1.0), "node": null,
		"click": on_click, "style": style})
	while _toasts.size() > TOAST_MAX:
		_drop(0)
	_show_waiting()


## Puts waiting toasts on screen while there is room, oldest first.
func _show_waiting() -> void:
	var on := 0
	for t in _toasts:
		if t["node"] != null:
			on += 1
	for t in _toasts:
		if on >= TOAST_VISIBLE:
			return
		if t["node"] == null:
			t["node"] = _toast_pill(t)
			_toast_box.add_child(t["node"])
			on += 1


## The pill for one toast: cream with a sky-blue dot (ART_DIRECTION section 4), or gold with
## a coin for earnings.
func _toast_pill(entry: Dictionary) -> PanelContainer:
	var earn: bool = entry["style"] == "earn"
	var l := Label.new()
	l.text = entry["text"]
	l.add_theme_color_override("font_color", ViewWidgets.INK)
	l.add_theme_font_size_override("font_size", 17 if earn else 15)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FFE9A8") if earn else ViewWidgets.CREAM
	box.border_color = Color("#C98A1E") if earn else ViewWidgets.INK
	box.set_border_width_all(3 if earn else 2)
	box.set_corner_radius_all(16)
	box.set_content_margin_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 14
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if earn:
		line.add_child(HudIcon.make("coin", 22.0))
	else:
		var dot := Panel.new()
		var round := StyleBoxFlat.new()
		round.bg_color = ViewWidgets.SKY
		round.set_corner_radius_all(6)
		dot.add_theme_stylebox_override("panel", round)
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(dot)
	line.add_child(l)
	panel.add_child(line)
	var c: Callable = entry["click"]
	if c.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				click_toast(_toasts.find(entry)))
	return panel


func _drop(i: int) -> void:
	var t: Dictionary = _toasts[i]
	_toasts.remove_at(i)
	if t["node"] != null:
		_toast_box.remove_child(t["node"])
		t["node"].queue_free()


## Counts down the toasts on screen (the waiting ones keep their time) and the passing
## notices' clock.
func tick(delta: float) -> void:
	_clock += delta
	var i := 0
	while i < _toasts.size():
		if _toasts[i]["node"] == null:
			i += 1
			continue
		_toasts[i]["left"] = float(_toasts[i]["left"]) - delta
		if float(_toasts[i]["left"]) <= 0.0:
			_drop(i)
		else:
			i += 1
	_show_waiting()


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
	_show_waiting()
	return true


## Every toast on screen or waiting, oldest first.
func toasts() -> Array[String]:
	var out: Array[String] = []
	for t in _toasts:
		out.append(str(t["text"]))
	return out


## The toasts on screen now; for tests.
func visible_toasts() -> Array[String]:
	var out: Array[String] = []
	for t in _toasts:
		if t["node"] != null:
			out.append(str(t["text"]))
	return out
