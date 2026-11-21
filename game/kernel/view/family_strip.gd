class_name FamilyStrip
extends PanelContainer
## The family switcher: a row of small round faces just above the bottom bar's left end, one
## for every living person of the house, in the world's order. Each face is their look's
## painted portrait cropped round (the view's stand-in look for an old save's "",
## `ViewLooks`), else a round of their colour with the first character of their name. The
## one shown in the bar is ringed tomato; a small dot sits on a face while that person has
## something waiting (tomato: ill or a need gone bad; wood: an ask or a wish); someone away
## on an outing is dimmed and captioned "出门了". A click picks that person (`picked`); the
## bar decides what that does. Animals are not here (they are picked in the house).
## At narrow widths the faces shrink (the captions go first), and past that the row scrolls.

signal picked(uid: int)

## The face's diameter at full size and at its smallest, and the room for one face.
const FACE := 38.0
const FACE_MIN := 24.0
const GAP := 4.0
const CAPTION := 11
## Below this face size the captions are left off.
const CAPTION_FROM := 32.0
## Where the portrait's face sits in the square painting (the middle of the crop, its radius),
## as a share of the picture's side.
const CROP_CENTRE := Vector2(0.5, 0.42)
const CROP_RADIUS := 0.36
## Words the pack's ui.json may replace.
const WORDS := {"bar.away": "出门了", "bar.switch_tip": "看看{name}在做什么"}

var _scroll: ScrollContainer
var _row: HBoxContainer
var _faces: Array[Face] = []
var _sig := ""
var _face_size := FACE


## One person's face in the strip.
class Face:
	extends Control
	var uid := -1
	var tex: Texture2D
	var color := Color.GRAY
	var initial := ""
	var caption := ""
	var side := FamilyStrip.FACE
	var selected := false
	var away := false
	## The waiting dot's colour; transparent for none.
	var dot := Color(0, 0, 0, 0)
	var strip: FamilyStrip

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE

	func set_state(sel: bool, is_away: bool, d: Color) -> void:
		if sel == selected and is_away == away and d == dot:
			return
		selected = sel
		away = is_away
		dot = d
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			accept_event()
			if strip != null:
				strip.picked.emit(uid)

	func _draw() -> void:
		var r := side * 0.5
		var c := Vector2(size.x * 0.5, r + 2.0)
		var dim := Color(1, 1, 1, 0.42) if away else Color.WHITE
		draw_circle(c, r, (ViewWidgets.ACCENT if selected else ViewWidgets.WOOD) * dim)
		draw_circle(c, r - (3.0 if selected else 1.5), ViewWidgets.CREAM * dim)
		var inner := r - (4.5 if selected else 3.0)
		if tex != null:
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 32:
				var a := TAU * float(i) / 32.0
				var u := Vector2(cos(a), sin(a))
				pts.append(c + u * inner)
				uvs.append(FamilyStrip.CROP_CENTRE + u * FamilyStrip.CROP_RADIUS)
			var tint := Color(0.85, 0.82, 0.78, 0.5) if away else Color.WHITE
			draw_colored_polygon(pts, tint, uvs, tex)
		else:
			draw_circle(c, inner, color * dim)
			var font := get_theme_default_font()
			var fs := int(inner * 1.05)
			var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ViewWidgets.CREAM * dim)
		if dot.a > 0.0:
			var at := c + Vector2(r * 0.72, -r * 0.72)
			draw_circle(at, 5.5, ViewWidgets.CREAM)
			draw_circle(at, 4.0, dot)
		if caption != "" and side >= FamilyStrip.CAPTION_FROM:
			var font2 := get_theme_default_font()
			var w2 := minf(font2.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, FamilyStrip.CAPTION).x, size.x)
			var ink := ViewWidgets.MUTED if away else (ViewWidgets.ACCENT if selected else ViewWidgets.INK)
			draw_string(font2, Vector2((size.x - w2) * 0.5, side + 2.0 + FamilyStrip.CAPTION + 1.0), caption,
				HORIZONTAL_ALIGNMENT_LEFT, size.x, FamilyStrip.CAPTION, ink)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := ViewWidgets.chip_style(Color(ViewWidgets.CREAM, 0.92), ViewWidgets.WOOD)
	st.set_corner_radius_all(14)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 3
	add_theme_stylebox_override("panel", st)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(GAP))
	_scroll.add_child(_row)


static func word(strings: ViewStrings, key: String) -> String:
	return strings.t(key) if strings != null and strings.has(key) else str(WORDS[key])


## Fills the strip for `people` (living, in order). `info(uid)` gives {away, dot}; `selected`
## is the uid shown in the bar (-1: none ringed); `max_width` the room it may take.
func show_people(people: Array, selected: int, info: Callable, skin: PackSkin, pack: Pack,
		strings: ViewStrings, max_width: float) -> void:
	var n := people.size()
	var room := maxf(max_width - 16.0, FACE_MIN)
	var want := FACE + 12.0
	var fit := (room - GAP * maxf(n - 1, 0)) / maxf(n, 1)
	var side := clampf(fit - 12.0 if fit < want else FACE, FACE_MIN, FACE)
	var sig := "%d|%.0f" % [n, side]
	for p in people:
		var away: bool = info.call(p.uid).get("away", false)
		sig += "|%d:%s:%s:%s" % [p.uid, ViewLooks.of(p, pack), p.given, away]
	if sig != _sig:
		_sig = sig
		_face_size = side
		for f in _faces:
			_row.remove_child(f)
			f.queue_free()
		_faces.clear()
		for p in people:
			var f := Face.new()
			f.strip = self
			f.uid = p.uid
			f.side = side
			var look := ViewLooks.of(p, pack)
			f.tex = skin.portrait(look) if skin != null and skin.enabled and look != "" else null
			f.color = PersonView.FEMALE if p.gender == "female" else (PersonView.MALE if p.gender == "male" else PersonView.OTHER)
			f.initial = p.given.left(1)
			var away: bool = info.call(p.uid).get("away", false)
			f.caption = word(strings, "bar.away") if away else p.given
			f.tooltip_text = word(strings, "bar.switch_tip").replace("{name}", strings.person_name(p) if strings != null else p.given)
			var cap := side >= CAPTION_FROM
			f.custom_minimum_size = Vector2(maxf(side + 12.0, 44.0) if cap else side + 4.0, side + 4.0 + (CAPTION + 3.0 if cap else 0.0))
			_row.add_child(f)
			_faces.append(f)
	for f in _faces:
		var i: Dictionary = info.call(f.uid)
		f.set_state(f.uid == selected, bool(i.get("away", false)), i.get("dot", Color(0, 0, 0, 0)))
	var content := _row.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(minf(content.x, room), content.y)


## The uids on show, in order; for tests.
func uids() -> Array[int]:
	var out: Array[int] = []
	for f in _faces:
		out.append(f.uid)
	return out


## The face for `uid`, or null; for tests.
func face(uid: int) -> Face:
	for f in _faces:
		if f.uid == uid:
			return f
	return null


## The size the faces are drawn at now; for tests.
func face_size() -> float:
	return _face_size


## Clicks the face of `uid` (also the test entry point); false when it is not on show.
func click(uid: int) -> bool:
	if face(uid) == null:
		return false
	picked.emit(uid)
	return true
