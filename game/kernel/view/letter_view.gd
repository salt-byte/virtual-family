class_name LetterView
extends Node
## Letters in the view: a carrier bird that lands on the compound wall while a letter waits
## unread (a little tube tied to its leg), the open letter on a sheet of paper with its
## choices, and the letter box (every letter kept, newest first). The bird sits on its own
## layer above the house, the box button in the bottom bar (`Hud`), the paper above the
## panels. Unread letters and letters waiting for an answer are also notices (`Notices`). Reads the World;
## reading and answering go through session commands. Does nothing for a pack without
## letters (`LetterSystem.enabled`).

const PERCH_LAYER := 2
const PAPER_LAYER := 6
const PAPER_WIDTH := 500.0
const LIST_HEIGHT := 360.0
const FLY_SECONDS := 1.4
## How high the compound wall stands above its base line, in house pixels: the bird sits on top.
const WALL_TOP := 34.0
## Where on the screen (as a share of the house area) the bird likes to sit.
const PERCH_AIM := Vector2(0.7, 0.3)
const PERCH_MARGIN := 40.0
const PAPER := Color("#FBF1DA")
const PAPER_EDGE := Color("#D9BF8F")
const SNIPPET := 16

var main: Main
var session: GameSession
var bird: LetterBird
var box_button: Button

var _perch: CanvasLayer
var _paper_layer: CanvasLayer
var _root: Control
var _box: VBoxContainer
var _buttons: Dictionary = {}  # id -> Button
## "" (closed), "letter" or "box".
var _mode := ""
var _letter := -1
var _signature := ""
## Perch spots in map cells (x along the wall, y the wall line), worked out once.
var _spots: Array[Vector2] = []
var _spot := -1
## 0..1 through the landing; 1 when sitting.
var _fly := 1.0
var _from := Vector2.ZERO
var _unread := 0


func setup(m: Main) -> void:
	main = m
	session = m.session
	_perch = CanvasLayer.new()
	_perch.layer = PERCH_LAYER
	add_child(_perch)
	var top := Control.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.theme = ViewWidgets.hud_theme()
	_perch.add_child(top)
	bird = LetterBird.new()
	bird.visible = false
	bird.pressed.connect(open_newest)
	top.add_child(bird)
	# The letter box is one of the bar's main buttons (the bar sends its press to Main, which
	# opens the box); this view keeps its words and whether it shows.
	box_button = main.hud.button("letters")

	_paper_layer = CanvasLayer.new()
	_paper_layer.layer = PAPER_LAYER
	add_child(_paper_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = ViewWidgets.hud_theme()
	_root.visible = false
	_paper_layer.add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var sheet := PanelContainer.new()
	sheet.custom_minimum_size.x = PAPER_WIDTH
	sheet.add_theme_stylebox_override("panel", paper_style())
	center.add_child(sheet)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	sheet.add_child(_box)
	session.event.connect(_on_event)
	_find_spots()
	refresh()


## The paper of the letter and the box: cream, a wooden edge, a soft shadow.
static func paper_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.border_color = PAPER_EDGE
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(26)
	s.shadow_color = Color(0.29, 0.2, 0.14, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	return s


func _enabled() -> bool:
	var w := session.world
	return w != null and w.phase == "living" and LetterSystem.enabled(w.pack)


## "", "letter" or "box".
func opened() -> String:
	return _mode


func blocks_input() -> bool:
	return _mode != ""


## Opens the newest unread letter (the bird's tube); nothing when none waits.
func open_newest() -> void:
	if not _enabled() or main.overlays.current() != "":
		return
	var w := session.world
	for i in range(w.letters.size() - 1, -1, -1):
		if not bool(w.letters[i]["read"]):
			open_letter(int(w.letters[i]["id"]))
			return


## Opens one letter and marks it read.
func open_letter(id: int) -> void:
	if not _enabled() or LetterSystem.find(session.world, id).is_empty():
		return
	main.panels.close()
	_mode = "letter"
	_letter = id
	if not bool(LetterSystem.find(session.world, id)["read"]):
		session.command({"type": "read_letter", "letter": id})
	_signature = ""
	refresh()


func open_box() -> void:
	if not _enabled() or main.overlays.current() != "":
		return
	main.panels.close()
	_mode = "box"
	_letter = -1
	_signature = ""
	refresh()


func close() -> void:
	if _mode == "":
		return
	_mode = ""
	_letter = -1
	_signature = ""
	_rebuild()


## Test entry point and button handler: "btn.close", "btn.letters" (back to the box),
## "open.<id>" (a letter in the box), "choice.<i>" (answer the open letter).
func press(id: String) -> void:
	if not _buttons.has(id) or (_buttons[id] as Button).disabled:
		return
	if id == "btn.close":
		close()
	elif id == "btn.letters":
		open_box()
	elif id.begins_with("open."):
		open_letter(int(id.trim_prefix("open.")))
	elif id.begins_with("choice."):
		session.command({"type": "answer_letter", "letter": _letter, "choice": int(id.trim_prefix("choice."))})
		_signature = ""
		refresh()


func has_button(id: String) -> bool:
	return _buttons.has(id)


func is_disabled(id: String) -> bool:
	return not _buttons.has(id) or (_buttons[id] as Button).disabled


## All text on the paper, joined with newlines; for tests.
func text() -> String:
	var parts: Array[String] = []
	_collect(_box, parts)
	return "\n".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label or c is Button:
			out.append(c.text)
		_collect(c, out)


func _unhandled_key_input(event: InputEvent) -> void:
	if _mode != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _on_event(e: Dictionary) -> void:
	if str(e.get("type", "")) == "letter_arrived" and _enabled():
		_land()


## Starts the bird's landing (from off the top of the screen) unless it already sits there.
func _land() -> void:
	if bird.visible and _fly >= 1.0:
		bird.hop()
		return
	_spot = -1
	var at := _perch_point()
	_from = at + Vector2(-360.0, -320.0)
	_fly = 0.0


func refresh() -> void:
	var on := _enabled()
	box_button.visible = on
	if not on:
		bird.visible = false
		if _mode != "":
			close()
		return
	var w := session.world
	var n := LetterSystem.unread(w)
	if n > _unread and not bird.visible:
		_land()
	_unread = n
	box_button.text = session.strings.t("btn.letters") + ("（%d）" % n if n > 0 else "")
	bird.count = n
	bird.visible = n > 0 and main.overlays.current() == ""
	if _mode == "":
		return
	var sig := "%s|%d|%d|%d|%d" % [_mode, _letter, w.letters.size(), n, w.proposals.size()]
	if _mode == "letter":
		var l := LetterSystem.find(w, _letter)
		sig += "|%d|%s" % [int(l.get("answer", -2)), str(LetterSystem.is_open(w, l)) if not l.is_empty() else ""]
	if sig == _signature:
		return
	_signature = sig
	_rebuild()


## Moves the bird along its landing and keeps it on its spot as the house pans or zooms.
func tick(delta: float) -> void:
	if not bird.visible:
		return
	var at := _perch_point()
	var zoom := clampf(main.house.scale.x, 0.7, 1.3)
	bird.scale = Vector2.ONE * zoom
	if _fly < 1.0:
		_fly = minf(_fly + delta / FLY_SECONDS, 1.0)
		var k := 1.0 - pow(1.0 - _fly, 2.0)
		var arc := Vector2(0.0, -80.0 * sin(PI * _fly))
		bird.flying = _fly < 1.0
		bird.feet = _from.lerp(at, k) + arc
	else:
		bird.flying = false
		bird.feet = at
	bird.tick(delta)


## The screen point the bird stands on: a spot on the compound wall that is in view
## (kept while it stays in view), nearest the PERCH_AIM; clamped into view when none is.
func _perch_point() -> Vector2:
	var area := _area()
	var covered := main.hud.top_rects() if main.hud != null else ([] as Array[Rect2])
	if _spot >= 0 and _spot < _spots.size():
		var keep := _spot_screen(_spots[_spot])
		if area.has_point(keep) and _clear(keep, covered):
			return keep
	var aim := area.position + area.size * PERCH_AIM
	var best := -1
	var best_d := INF
	for i in _spots.size():
		var p := _spot_screen(_spots[i])
		if area.has_point(p) and _clear(p, covered) and p.distance_to(aim) < best_d:
			best = i
			best_d = p.distance_to(aim)
	_spot = best
	if best >= 0:
		return _spot_screen(_spots[best])
	return aim


## The screen rect the bird and its badge take when its feet are at `feet`.
func bird_rect(feet: Vector2) -> Rect2:
	var k := bird.scale.x if bird != null else 1.0
	return Rect2(feet - (LetterBird.FEET + Vector2(0, 4)) * k, Vector2(74, 66) * k)


## True when the bird standing at `feet` stays off every rect in `covered`.
func _clear(feet: Vector2, covered: Array[Rect2]) -> bool:
	var r := bird_rect(feet)
	for c in covered:
		if c.intersects(r):
			return false
	return true


## The part of the screen above the bottom bar, less a margin.
func _area() -> Rect2:
	var v := main.get_viewport().get_visible_rect().size if main.is_inside_tree() else HouseView.VIEW_SIZE
	return Rect2(Vector2.ONE * PERCH_MARGIN, Vector2(v.x, v.y - HouseView.BOTTOM_BAR) - Vector2.ONE * PERCH_MARGIN * 2.0)


## A point on the map (in cells) on the screen, raised to the top of the wall. Asks the
## house for `map_to_screen` when it has one (a projected view), else uses its plain
## `to_screen` on the cell grid.
func _spot_screen(map: Vector2) -> Vector2:
	var h := main.house
	var base: Vector2
	if h.has_method("map_to_screen"):
		base = h.call("map_to_screen", map)
	else:
		base = h.to_screen(map * HouseLayout.CELL)
	var top := WALL_TOP * h.scale.y
	if h.has_method("wall_top_at"):
		var t: float = h.call("wall_top_at", map)
		if t >= 0.0:
			top = t  # the 45° view's walls: 74 px at the back, 22 cut low
	return base + Vector2(0.0, -top)


## Perch spots every third cell along the compound wall, door openings left out; without a
## compound, along the top of the map.
func _find_spots() -> void:
	_spots.clear()
	var site := main.house.layout.site if main.house.layout != null else null
	if site != null and site.enabled and site.has_compound:
		var c: Rect2i = site.compound
		for x in range(c.position.x + 2, c.end.x - 1, 3):
			for y in [c.position.y, c.end.y]:
				if not site.is_open("x", y, x):
					_spots.append(Vector2(x + 0.5, y))
		for y in range(c.position.y + 2, c.end.y - 1, 3):
			for x in [c.position.x, c.end.x]:
				if not site.is_open("y", x, y):
					_spots.append(Vector2(x, y + 0.5))
		return
	if main.house.layout != null:
		var b := main.house.layout.bounds()
		var cells := b.size / HouseLayout.CELL
		for x in range(1, int(cells.x), 3):
			_spots.append(Vector2(x + 0.5, b.position.y / HouseLayout.CELL.y))


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_root.visible = _mode != ""
	if _mode == "letter":
		_fill_letter()
	elif _mode == "box":
		_fill_box()


func _fill_letter() -> void:
	var w := session.world
	var s := session.strings
	var l := LetterSystem.find(w, _letter)
	if l.is_empty():
		_mode = "box"
		_fill_box()
		return
	var head := HBoxContainer.new()
	_box.add_child(head)
	var from := _label(s.t("letter.from").replace("{writer}", str(l["writer"])), 15, ViewWidgets.WOOD)
	from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(from)
	head.add_child(_label(_when(int(l["t"])), 14, ViewWidgets.WOOD.lightened(0.2)))
	var rule := ColorRect.new()
	rule.color = PAPER_EDGE
	rule.custom_minimum_size = Vector2(0, 2)
	_box.add_child(rule)
	var look := _look(str(l["hand"]))
	var body := _label(str(l["text"]), int(look.get("size", 17)), _ink(look))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = PAPER_WIDTH - 52.0
	body.add_theme_constant_override("line_spacing", 8)
	_box.add_child(body)
	var tilt := float(look.get("tilt", 0.0))
	if tilt != 0.0:
		body.rotation_degrees = tilt
	var sign := _label(str(l["sign"]), int(look.get("size", 17)) - 1, _ink(look))
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_box.add_child(sign)
	var choices: Array = l["choices"]
	var answer := int(l["answer"])
	if answer >= 0 and answer < choices.size():
		_box.add_child(_label(s.t("letter.answered").replace("{choice}", str(choices[answer]["label"])), 15, ViewWidgets.ACCENT))
	elif not choices.is_empty() and not LetterSystem.is_open(w, l):
		_box.add_child(_label(s.t("letter.stale"), 15, ViewWidgets.WOOD))
	elif not choices.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		for i in choices.size():
			var b := _button("choice.%d" % i, str(choices[i]["label"]), row)
			b.disabled = not LetterSystem.choice_open(w, l, i)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	_box.add_child(foot)
	_button("btn.letters", s.t("btn.letters"), foot)
	_button("btn.close", s.t("btn.close"), foot)


func _fill_box() -> void:
	var w := session.world
	var s := session.strings
	_box.add_child(_label(s.t("title.letters"), 20, ViewWidgets.INK))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PAPER_WIDTH - 52.0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if w.letters.is_empty():
		list.add_child(_label(s.t("letters.none"), 16, ViewWidgets.WOOD))
	for i in range(w.letters.size() - 1, -1, -1):
		var l: Dictionary = w.letters[i]
		var line := "%s%s · %s · %s" % ["● " if not bool(l["read"]) else "", str(l["writer"]),
			_snippet(str(l["text"])), _when(int(l["t"]))]
		var b := _button("open.%d" % int(l["id"]), line, list)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(PAPER_WIDTH - 72.0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	_box.add_child(foot)
	_button("btn.close", s.t("btn.close"), foot)


func _snippet(t: String) -> String:
	return t if t.length() <= SNIPPET else t.substr(0, SNIPPET) + "…"


## "today" or "n days ago", by the household's local days.
func _when(t: int) -> String:
	var w := session.world
	var days := floori(float(w.now + w.utc_offset) / 86400.0) - floori(float(t + w.utc_offset) / 86400.0)
	if days <= 0:
		return session.strings.t("letter.today")
	return session.strings.t("letter.days").replace("{n}", str(days))


## The look of a hand from the pack's letter settings ({} for someone outside).
func _look(hand: String) -> Dictionary:
	for h in LetterSystem.cfg(session.world.pack).get("hands", []):
		if h is Dictionary and str(h.get("id", "")) == hand:
			var look = h.get("look", {})
			return look if look is Dictionary else {}
	return {}


func _ink(look: Dictionary) -> Color:
	var c := str(look.get("ink", ""))
	return Color.html(c) if Color.html_is_valid(c) else ViewWidgets.INK


func _label(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(id: String, label: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(press.bind(id))
	parent.add_child(b)
	_buttons[id] = b
	return b
