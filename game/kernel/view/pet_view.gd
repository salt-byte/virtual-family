class_name PetView
extends Node2D
## One animal of the household as a small coloured shape with a name plate (whitebox until
## the art pass). It goes to whatever it is doing: the object its action happens at, a cell
## of the room it names, after the person it follows, or beside whoever is looking after it.
## Reads the World, never writes it.

const SPEED := 120.0
## A grown-up's block is 28 x 44; an animal is a low wide shape scaled by its kind's `size`.
const BODY := Vector2(44, 30)
const ARRIVED := 1.0
const BOB_AMPLITUDE := 2.0
const BOB_PERIOD := 0.5
const THANKS_HOP := 6.0
const THANKS_PERIOD := 0.35
const FALLBACK := Color(0.7, 0.6, 0.45)

var pet: Pet
var session: GameSession
var target := Vector2.ZERO
var base_target := Vector2.ZERO
var path := PackedVector2Array()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _path_goal := Vector2(INF, INF)
var _path_from := Vector2(INF, INF)
var _rng := RandomNumberGenerator.new()
var _key := ""
var _name := ""
var _doing := ""
var _wish := ""
var _color := FALLBACK
var _size := 0.6
var _t := 0.0
var _float := ""
var _float_age := 0.0
## With the pack's art: {tex, height} of this kind's picture ({}: the whitebox shape), and
## which way it faces (the pictures face right).
var _look: Dictionary = {}
var _facing := 1.0


func setup(p: Pet, s: GameSession) -> void:
	pet = p
	session = s
	_rng.randomize()
	var l := layout()
	if l != null:
		position = _home_cell(session.world, l)
	refresh()


func layout() -> HouseLayout:
	return get_parent().layout if get_parent() != null and "layout" in get_parent() else null


## The drawn body size.
func body() -> Vector2:
	if not _look.is_empty():
		var tex: Texture2D = _look.tex
		var h: float = _look.height
		return Vector2(h * tex.get_width() / tex.get_height(), h)
	return BODY * _size


func refresh() -> void:
	var w := session.world
	if w == null or pet == null:
		return
	var k := PetSystem.kind_of(w.pack, pet)
	_color = HouseView.pack_color(k, FALLBACK)
	_size = float(k.get("size", 0.6))
	var house = get_parent()
	var skin: PackSkin = house.skin if house != null and "skin" in house else null
	_look = skin.pet_look(str(pet.kind)) if skin != null and skin.enabled else {}
	_name = session.strings.pet_name(pet, w)
	_doing = session.strings.pet_doing(pet, w)
	_wish = session.strings.pet_wish_text(pet, w)
	var l := layout()
	if l != null:
		base_target = _compute_target(w, l)
		target = base_target
	queue_redraw()


func thanking() -> bool:
	return pet != null and session.world != null and pet.thanks_until > session.world.now


func wish_bubble() -> String:
	return _wish


func doing_text() -> String:
	return _doing


## "thanks", "walking", "busy" or "idle", for drawing (the art pass maps these).
func pose() -> String:
	if thanking():
		return "thanks"
	if position.distance_to(target) > ARRIVED:
		return "walking"
	return "busy" if not pet.current.is_empty() else "idle"


func tick(delta: float) -> void:
	_t += delta
	if _float != "":
		_float_age += delta
		if _float_age > 1.2:
			_float = ""
	var was := position
	walk(SPEED * delta)
	if absf(position.x - was.x) > 0.01:
		_facing = signf(position.x - was.x)
	queue_redraw()


## Floats `text` above it for a moment (its joy at a wish come true).
func float_text_up(text: String) -> void:
	_float = text
	_float_age = 0.0


func float_text() -> String:
	return _float


func walk(step: float) -> void:
	if target != _path_goal or position != _path_from:
		_path_goal = target
		var l := layout()
		path = l.site.route(position, target) if l != null and l.site.enabled else PackedVector2Array()
	while step > 0.0:
		var next := path[0] if not path.is_empty() else target
		var d := position.distance_to(next)
		if d > step:
			position = position.move_toward(next, step)
			break
		position = next
		step -= d
		if path.is_empty():
			break
		path.remove_at(0)
	_path_from = position


## Whether a point in the house's coordinates lands on it.
func hit(world_pos: Vector2) -> bool:
	var b := body()
	return Rect2(position - Vector2(b.x * 0.5, b.y), b).grow(6.0).has_point(world_pos)


func rect() -> Rect2:
	var b := body()
	return Rect2(position - Vector2(b.x * 0.5, b.y), b)


func _compute_target(w: World, l: HouseLayout) -> Vector2:
	var house = get_parent()
	# Being looked after: it keeps still where it is.
	for q in w.people:
		if q.alive and not q.current.is_empty() and int(q.current.get("target_uid", -1)) == pet.uid:
			_key = ""
			return position
	var cur := pet.current
	if cur.has("follow") and house != null and "people" in house and house.people.has(int(cur["follow"])):
		_key = ""
		return (house.people[int(cur["follow"])] as PersonView).position + Vector2(-PersonView.BODY.x, 4)
	if cur.has("object_uid"):
		var o := w.object(int(cur["object_uid"]))
		if not o.is_empty():
			_key = ""
			var r := l.object_rect(o, w.pack)
			return Vector2(r.get_center().x, r.end.y - 4.0)
	if cur.has("mess"):
		var m := MessSystem.find(w, int(cur["mess"]))
		if not m.is_empty():
			_key = ""
			return l.cell_center(str(m.room), int(m.x), int(m.y)) + Vector2(14, 0)
	var room := str(cur.get("room", ""))
	var key := "%s|%s" % [cur.get("action", ""), room]
	if key == _key:
		return base_target
	_key = key
	if room != "" and w.pack.rooms.has(room) and l.room_rect(room).size != Vector2.ZERO:
		var r: Dictionary = w.pack.rooms[room]
		return l.cell_center(room, _rng.randi_range(0, int(r.w) - 1), _rng.randi_range(0, int(r.h) - 1))
	if cur.is_empty() and base_target != Vector2.ZERO:
		return base_target
	return _home_cell(w, l)


## A cell of one of its kind's `home` rooms that is built (the perch for a caged bird).
func _home_cell(w: World, l: HouseLayout) -> Vector2:
	var k := PetSystem.kind_of(w.pack, pet)
	var perch := str(k.get("perch", ""))
	if perch != "":
		for o in w.objects:
			if o.type == perch:
				var r := l.object_rect(o, w.pack)
				return Vector2(r.get_center().x, r.end.y - 4.0)
	var homes: Array = (k.get("home", []) as Array).filter(func(r): return w.rooms_built.has(r))
	if homes.is_empty():
		homes = w.rooms_built.filter(func(r): return not bool(w.pack.rooms[r].get("outside", false)))
	if homes.is_empty():
		return position
	var room := str(homes[_rng.randi_range(0, homes.size() - 1)])
	var rd: Dictionary = w.pack.rooms[room]
	return l.cell_center(room, _rng.randi_range(0, int(rd.w) - 1), _rng.randi_range(0, int(rd.h) - 1))


func bob_offset() -> float:
	if thanking():
		return -absf(THANKS_HOP * sin(TAU * _t / THANKS_PERIOD))
	if pose() == "walking":
		return -absf(BOB_AMPLITUDE * sin(TAU * _t / BOB_PERIOD))
	return 0.0


func _draw() -> void:
	if pet == null:
		return
	var b := body()
	var bob := bob_offset()
	var r := Rect2(Vector2(-b.x * 0.5, -b.y + bob), b)
	draw_colored_polygon(HouseGround._ellipse(Rect2(Vector2(-b.x * 0.5, -5), Vector2(b.x, 8))), Color(HouseGround.SHADOW, 0.3))
	if not _look.is_empty():
		_draw_pictured(b, bob)
		return
	var box := StyleBoxFlat.new()
	box.bg_color = _color.darkened(0.25) if pet.sick else _color
	box.set_corner_radius_all(int(minf(b.x, b.y) * 0.45))
	draw_style_box(box, r)
	# A head at the front, so the shape reads as an animal and not a crate.
	draw_circle(Vector2(b.x * 0.42, -b.y * 0.85 + bob), b.y * 0.36, box.bg_color.darkened(0.1))
	draw_circle(Vector2(b.x * 0.5, -b.y * 0.9 + bob), 1.8, Color(0.08, 0.08, 0.08))
	if selected:
		draw_rect(r.grow(4.0), Color(0.95, 0.75, 0.1), false, 2.5)
	var font := ThemeDB.fallback_font
	var top := -b.y - 6.0
	if _float != "":
		draw_string(font, Vector2(-40, top - 40 - _float_age * 20.0), _float, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(0.8, 0.25, 0.15))
	elif _wish != "":
		var ww := font.get_string_size(_wish, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
		var bubble := StyleBoxFlat.new()
		bubble.bg_color = Color(1, 1, 1, 0.95)
		bubble.border_color = Color(0.55, 0.5, 0.45)
		bubble.set_border_width_all(1)
		bubble.set_corner_radius_all(9)
		draw_style_box(bubble, Rect2(Vector2(-ww * 0.5, top - 46), Vector2(ww, 19)))
		draw_string(font, Vector2(-ww * 0.5, top - 32), _wish, HORIZONTAL_ALIGNMENT_CENTER, ww, 11, Color(0.2, 0.15, 0.1))
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(1, 1, 1, 0.8)
	plate.set_corner_radius_all(4)
	draw_style_box(plate, Rect2(Vector2(-55, top - 24), Vector2(110, 24)))
	draw_string(font, Vector2(-55, top - 13), _name, HORIZONTAL_ALIGNMENT_CENTER, 110, 11, Color.BLACK)
	draw_string(font, Vector2(-55, top - 2), _doing, HORIZONTAL_ALIGNMENT_CENTER, 110, 9, Color(0.15, 0.15, 0.15))


## The pack's picture: mirrored when heading left, a hop while walking, a slow breath
## otherwise; a small cream plate with its name (and what it does when selected).
func _draw_pictured(b: Vector2, bob: float) -> void:
	var breath := 1.0 + 0.015 * sin(TAU * _t / 2.2)
	var tint := Color(0.85, 0.85, 0.8) if pet.sick else Color.WHITE
	draw_set_transform(Vector2(0, bob + 2.0), 0.0, Vector2(_facing, breath))
	draw_texture_rect(_look.tex, Rect2(-b.x * 0.5, -b.y, b.x, b.y), false, tint)
	draw_set_transform(Vector2.ZERO)
	var line := Color("#4A3424")
	var font := ThemeDB.fallback_font
	var top := -b.y + bob - 4.0
	if selected:
		draw_colored_polygon(PackedVector2Array([Vector2(-6, top - 10), Vector2(6, top - 10), Vector2(0, top - 2)]), Color("#E5533C"))
		top -= 10.0
	if _float != "":
		draw_string(font, Vector2(-40, top - 40 - _float_age * 20.0), _float, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(0.8, 0.25, 0.15))
	elif _wish != "":
		var ww := font.get_string_size(_wish, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
		var bubble := StyleBoxFlat.new()
		bubble.bg_color = Color(1, 1, 1, 0.95)
		bubble.border_color = Color(0.55, 0.5, 0.45)
		bubble.set_border_width_all(1)
		bubble.set_corner_radius_all(9)
		draw_style_box(bubble, Rect2(Vector2(-ww * 0.5, top - 46), Vector2(ww, 19)))
		draw_string(font, Vector2(-ww * 0.5, top - 32), _wish, HORIZONTAL_ALIGNMENT_CENTER, ww, 11, Color(0.2, 0.15, 0.1))
	var text := _name if not selected else "%s · %s" % [_name, _doing]
	var pw := clampf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0, 30.0, 180.0)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("#FFF4DF", 0.92)
	plate.border_color = Color("#E5533C") if selected else Color(line, 0.5)
	plate.set_border_width_all(2 if selected else 1)
	plate.set_corner_radius_all(6)
	draw_style_box(plate, Rect2(Vector2(-pw * 0.5, top - 16), Vector2(pw, 16)))
	draw_string(font, Vector2(-pw * 0.5, top - 4), text, HORIZONTAL_ALIGNMENT_CENTER, pw, 11, line)
