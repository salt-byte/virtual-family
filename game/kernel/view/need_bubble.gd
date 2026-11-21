class_name NeedBubble
extends RefCounted
## The one thought bubble over a person's head: an ask (`AskSystem`) comes first, then a
## wish. An ask that waits for the player bobs gently so it catches the eye; once the person
## deals with it themselves it sits still and fades a little. A wish for a need is shown
## except while they are doing something that raises it; any other wish shows when it forms and then in short pulses (`wish_shown`), so the
## asks stand out and the house does not wear a bubble on every head all day. Each bubble is
## a small icon and a few words. The icon is the pack's picture of an object type or a pet
## kind when the name is one, else one of the shapes drawn here; nothing here knows the
## theme's words.

const INK := ViewWidgets.INK
const CREAM := Color("#FFF8EA")
const LINE := 1.6
const ICON := 20.0
const FONT_SIZE := 13
const PAD := 7.0
const HEIGHT := 28.0
## The gentle bob of a waiting ask: pixels up and down, and seconds per bob.
const BOB_PX := 2.5
const BOB_PERIOD := 1.4
## A wish other than a need's: shown this many seconds after it forms, then for `PULSE_ON`
## seconds out of every `PULSE_EVERY`.
const WISH_FIRST_S := 60
const PULSE_ON := 30
const PULSE_EVERY := 90
## Every shape it draws itself.
const SHAPES := ["bowl", "quilt", "washtub", "heart", "star", "ball", "candy", "paw", "bench", "sun", "wish"]


## The bubble over `p` now: {} for none, else {text, icon, kind: "ask" | "wish", waiting}.
## Nothing while they thank the player, are out, or are dead.
static func of(world: World, p: Person) -> Dictionary:
	if p == null or world == null or not p.alive or p.thanking(world.now) or OutingSystem.away(world, p):
		return {}
	var a := AskSystem.current(world, p)
	if not a.is_empty():
		return {"text": str(a.get("text", "")), "icon": str(a.get("icon", "")), "kind": "ask", "waiting": AskSystem.waiting(p)}
	var w := WishSystem.current(world, p)
	if not w.is_empty() and wish_shown(world, p, w):
		return {"text": str(w.get("text", "")), "icon": str(w.get("icon", "")), "kind": "wish", "waiting": false}
	return {}


## Whether `p`'s wish `w` shows over their head now (see the class notes).
static func wish_shown(world: World, p: Person, w: Dictionary) -> bool:
	if str(w.get("kind", "")) == "need":
		return not WishSystem.being_met(world, p)  # not from inside the bath they wished for
	var formed := int(p.wish.get("expires_at", 0)) - int(float(w.get("ttl_hours", 0.0)) * 3600.0)
	var age := world.now - formed
	if age < WISH_FIRST_S:
		return true
	# Each person pulses on their own beat.
	return posmod(age + p.uid * 37, PULSE_EVERY) < PULSE_ON


## The bubble's size for `b` (without the tail and the bob).
static func size_of(b: Dictionary) -> Vector2:
	if b.is_empty():
		return Vector2.ZERO
	var tw := ThemeDB.fallback_font.get_string_size(str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var iw := ICON + 4.0 if str(b.get("icon", "")) != "" else 0.0
	return Vector2(tw + iw + PAD * 2.0, HEIGHT)


## How far a waiting ask is lifted now (0 for anything else), `t` in seconds.
static func bob(b: Dictionary, t: float) -> float:
	return -BOB_PX * (0.5 + 0.5 * sin(TAU * t / BOB_PERIOD)) if bool(b.get("waiting", false)) else 0.0


## Draws bubble `b` on `ci` with its bottom middle (above the tail) at `at`; `t` drives the
## bob, `skin` (may be null) gives the pack's pictures.
static func draw(ci: CanvasItem, at: Vector2, b: Dictionary, t: float, skin: PackSkin) -> void:
	if b.is_empty():
		return
	var sz := size_of(b)
	var lift := bob(b, t)
	var fade := 0.8 if str(b["kind"]) == "ask" and not bool(b["waiting"]) else 1.0
	var rect := Rect2(Vector2(at.x - sz.x * 0.5, at.y - sz.y + lift), sz)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(CREAM, 0.97 * fade)
	box.border_color = Color(INK, 0.7 * fade)
	box.set_border_width_all(2 if bool(b["waiting"]) else 1)
	box.set_corner_radius_all(12)
	ci.draw_style_box(box, rect)
	# The thought tail: two small rounds below the left of the middle.
	ci.draw_circle(Vector2(at.x - 5.0, at.y + 4.0 + lift * 0.5), 3.2, Color(CREAM, fade))
	ci.draw_arc(Vector2(at.x - 5.0, at.y + 4.0 + lift * 0.5), 3.2, 0.0, TAU, 12, Color(INK, 0.6 * fade), 1.0, true)
	ci.draw_circle(Vector2(at.x - 9.0, at.y + 9.0), 1.8, Color(CREAM, fade))
	ci.draw_arc(Vector2(at.x - 9.0, at.y + 9.0), 1.8, 0.0, TAU, 10, Color(INK, 0.6 * fade), 1.0, true)
	var x := rect.position.x + PAD
	var icon := str(b.get("icon", ""))
	if icon != "":
		draw_icon(ci, Rect2(Vector2(x, rect.position.y + (sz.y - ICON) * 0.5), Vector2(ICON, ICON)), icon, skin, fade)
		x += ICON + 4.0
	var font := ThemeDB.fallback_font
	ci.draw_string(font, Vector2(x, rect.position.y + sz.y * 0.5 + FONT_SIZE * 0.36), str(b["text"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(INK, fade))


## Draws icon `name` into `r`: the pack's picture of that object type or pet kind when it
## has one, else a drawn shape (`SHAPES`), else the plain thought sign.
static func draw_icon(ci: CanvasItem, r: Rect2, name: String, skin: PackSkin, fade := 1.0) -> void:
	if skin != null and skin.enabled and not SHAPES.has(name):
		var tex := skin.object_sprite(name)
		if tex == null:
			var look := skin.pet_look(name)
			tex = look.get("tex") if look.get("tex") is Texture2D else null
		if tex != null:
			ci.draw_texture_rect(tex, PackSkin.fit_rect(tex, Vector2(r.get_center().x, r.end.y), r.size), false, Color(1, 1, 1, fade))
			return
	var s := r.size.x / 24.0
	ci.draw_set_transform(r.position, 0.0, Vector2(s, s))
	_shape_icon(ci, name if SHAPES.has(name) else "wish", fade)
	ci.draw_set_transform(Vector2.ZERO)


## One drawn icon on a 24 x 24 grid: flat warm fills inside the dark brown outline, the same
## hand as the bar's icons (`HudIcon`).
static func _shape_icon(ci: CanvasItem, name: String, fade: float) -> void:
	var ink := Color(INK, fade)
	match name:
		"bowl":
			_poly(ci, _half_disc(Vector2(12, 12), 7.0), Color("#FFFBF0", fade), ink)
			_poly(ci, [Vector2(2.5, 12), Vector2(21.5, 12), Vector2(17.5, 20), Vector2(6.5, 20)], Color("#C8573E", fade), ink)
			ci.draw_line(Vector2(9, 4.5), Vector2(10, 1.5), Color(ink, 0.6), 1.4)
			ci.draw_line(Vector2(14, 4.5), Vector2(15, 1.5), Color(ink, 0.6), 1.4)
		"quilt":
			_poly(ci, [Vector2(2, 9), Vector2(22, 9), Vector2(22, 20), Vector2(2, 20)], Color("#6F9BC9", fade), ink)
			_poly(ci, [Vector2(2, 9), Vector2(9, 9), Vector2(9, 14), Vector2(2, 14)], Color("#FFF4DF", fade), ink)
			ci.draw_line(Vector2(12, 12), Vector2(20, 12), Color(ink, 0.5), 1.2)
			ci.draw_string(ThemeDB.fallback_font, Vector2(15, 7), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ink)
			ci.draw_string(ThemeDB.fallback_font, Vector2(19, 4), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, ink)
		"washtub":
			_poly(ci, [Vector2(2, 10), Vector2(22, 10), Vector2(19, 20), Vector2(5, 20)], Color("#B5763E", fade), ink)
			_poly(ci, [Vector2(3.5, 10), Vector2(20.5, 10), Vector2(19.5, 12.5), Vector2(4.5, 12.5)], Color("#8FD0E8", fade), ink)
			for c in [Vector2(8, 6), Vector2(13, 4), Vector2(17, 6.5)]:
				ci.draw_circle(c, 1.8, Color("#FFFFFF", fade))
				ci.draw_arc(c, 1.8, 0.0, TAU, 10, Color(ink, 0.6), 1.0, true)
		"heart":
			var red := Color("#E5533C", fade)
			_poly(ci, [Vector2(3.2, 10.5), Vector2(12, 21), Vector2(20.8, 10.5), Vector2(12, 8)], red, red)
			ci.draw_circle(Vector2(7.5, 8.5), 4.6, red)
			ci.draw_circle(Vector2(16.5, 8.5), 4.6, red)
			ci.draw_arc(Vector2(7.5, 8.5), 4.6, PI * 0.8, PI * 2.0, 12, ink, LINE, true)
			ci.draw_arc(Vector2(16.5, 8.5), 4.6, PI, PI * 2.2, 12, ink, LINE, true)
			ci.draw_line(Vector2(3.2, 10.5), Vector2(12, 21), ink, LINE, true)
			ci.draw_line(Vector2(20.8, 10.5), Vector2(12, 21), ink, LINE, true)
		"star":
			var pts: Array = []
			for k in 10:
				var ang := -PI * 0.5 + PI * float(k) / 5.0
				pts.append(Vector2(12, 12.5) + Vector2(cos(ang), sin(ang)) * (9.5 if k % 2 == 0 else 4.2))
			_poly(ci, pts, Color("#E8B64A", fade), ink)
		"ball":
			ci.draw_circle(Vector2(12, 12), 8.5, Color("#E5533C", fade))
			ci.draw_arc(Vector2(12, 12), 8.5, -0.6, 0.6, 8, Color("#FFF4DF", fade), 3.0)
			ci.draw_arc(Vector2(12, 12), 8.5, PI - 0.6, PI + 0.6, 8, Color("#FFF4DF", fade), 3.0)
			ci.draw_line(Vector2(12, 3.5), Vector2(12, 20.5), Color("#FFF4DF", fade), 2.0)
			ci.draw_arc(Vector2(12, 12), 8.5, 0.0, TAU, 24, ink, LINE, true)
		"candy":
			ci.draw_line(Vector2(12, 12), Vector2(12, 23), Color("#B5763E", fade), 2.0)
			ci.draw_circle(Vector2(12, 8.5), 6.5, Color("#E8B64A", fade))
			ci.draw_arc(Vector2(12, 8.5), 3.5, 0.0, PI * 1.6, 10, Color("#C8573E", fade), 1.6)
			ci.draw_arc(Vector2(12, 8.5), 6.5, 0.0, TAU, 20, ink, LINE, true)
		"paw":
			var brown := Color("#B5763E", fade)
			for c in [Vector2(6, 9), Vector2(10, 5), Vector2(14, 5), Vector2(18, 9)]:
				ci.draw_circle(c, 2.6, brown)
				ci.draw_arc(c, 2.6, 0.0, TAU, 12, ink, 1.2, true)
			ci.draw_circle(Vector2(12, 15.5), 5.2, brown)
			ci.draw_arc(Vector2(12, 15.5), 5.2, 0.0, TAU, 16, ink, LINE, true)
		"bench":
			_poly(ci, [Vector2(2, 10), Vector2(22, 10), Vector2(22, 14), Vector2(2, 14)], Color("#B5AFA3", fade), ink)
			_poly(ci, [Vector2(4, 14), Vector2(7, 14), Vector2(7, 21), Vector2(4, 21)], Color("#A9A49A", fade), ink)
			_poly(ci, [Vector2(17, 14), Vector2(20, 14), Vector2(20, 21), Vector2(17, 21)], Color("#A9A49A", fade), ink)
		"sun":
			var gold := Color("#E8B64A", fade)
			for k in 8:
				var ang := TAU * float(k) / 8.0
				ci.draw_line(Vector2(12, 12) + Vector2(cos(ang), sin(ang)) * 7.5, Vector2(12, 12) + Vector2(cos(ang), sin(ang)) * 10.5, gold, 2.0)
			ci.draw_circle(Vector2(12, 12), 5.5, gold)
			ci.draw_arc(Vector2(12, 12), 5.5, 0.0, TAU, 16, ink, LINE, true)
		_:
			for c in [[Vector2(9, 11), 5.0], [Vector2(15, 10), 6.0], [Vector2(6, 20), 1.8]]:
				ci.draw_circle(c[0], c[1], Color("#FFF4DF", fade))
				ci.draw_arc(c[0], c[1], 0.0, TAU, 16, ink, LINE, true)


static func _poly(ci: CanvasItem, pts: Array, fill: Color, edge: Color) -> void:
	var p := PackedVector2Array(pts)
	ci.draw_colored_polygon(p, fill)
	p.append(pts[0])
	ci.draw_polyline(p, edge, LINE, true)


static func _half_disc(c: Vector2, r: float) -> Array:
	var p: Array = []
	for k in 13:
		var a := PI + PI * float(k) / 12.0
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p
