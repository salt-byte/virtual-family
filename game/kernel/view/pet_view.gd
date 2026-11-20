class_name PetView
extends Node2D
## One animal of the household as a small coloured shape with a name plate (whitebox until
## the art pass). It goes to whatever it is doing: the object its action happens at, a cell
## of the room it names, after the person it follows, or beside whoever is looking after it.
## Reads the World, never writes it.

const SPEED := 120.0
## The spot it took beside the piece of furniture `_spot_for` (uid; -1 none).
var _spot_for := -1
var _spot := Vector2.ZERO
## How far behind the person it follows an animal keeps (plan pixels).
const FOLLOW_GAP := 52.0
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
var house: HouseView
var target := Vector2.ZERO
var base_target := Vector2.ZERO
var path := PackedVector2Array()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _path_goal := Vector2(INF, INF)
## Giving way (`HouseView.give_way`): how long they have waited for someone in the way, and
## the cell of the one they last went round.
var waited := 0.0
var walked_round := Vector2i(-9999, -9999)
var round_age := 99.0
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
## The 45° view: "side", "front" or "back", for the kind's front and back pictures.
var turned := "side"


func setup(p: Pet, s: GameSession) -> void:
	pet = p
	session = s
	_rng.randomize()
	var l := layout()
	if l != null:
		position = _home_cell(session.world, l)
	refresh()


func layout() -> HouseLayout:
	var h := _house()
	return h.layout if h != null else null


## The house this stands in (set by the house; else the parent, as in tests that build one).
func _house() -> HouseView:
	if house != null:
		return house
	return get_parent() as HouseView


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
	var hv = _house()
	var skin: PackSkin = hv.skin if hv != null and "skin" in hv else null
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
	var hv := _house()
	if hv == null or not hv.iso or not hv.give_way(self, delta):
		walk(SPEED * delta)
	var iso := _house() != null and _house().iso
	var v := IsoMath.basis().basis_xform(position - was) if iso else position - was
	if absf(v.x) > 0.01:
		_facing = signf(v.x)
	if iso:
		# As people: three-quarters to the camera, or away walking up the screen; head-on
		# and side pictures only for a kind without the three-quarter ones.
		var up := v.length() > 0.01 and v.y <= -PersonView.UP_SCREEN * v.length()
		if _look.has("front34"):
			turned = "back34" if up and _look.has("back34") else "front34"
		elif v.length() > 0.01:
			turned = "side" if absf(v.y) < 0.2 * v.length() else ("front" if v.y > 0.0 else "back")
		else:
			turned = "side"
	queue_redraw()


## Floats `text` above it for a moment (its joy at a wish come true).
func float_text_up(text: String) -> void:
	_float = text
	_float_age = 0.0


func float_text() -> String:
	return _float


func walk(step: float) -> void:
	if target != _path_goal or position != _path_from:
		if target != _path_goal:
			walked_round = Vector2i(-9999, -9999)
		_path_goal = target
		var l := layout()
		path = l.site.route(position, target) if l != null and l.site.enabled else PackedVector2Array()
	# In the 45° view the step is measured on the screen (so walking east is as quick to the
	# eye as walking south): ISO_PACE turns plan pixels of a north-south walk into screen ones.
	var iso := _house() != null and _house().iso
	if iso:
		step *= IsoMath.ISO_PACE
	while step > 0.0:
		var next := path[0] if not path.is_empty() else target
		var d := position.distance_to(next)
		if iso and d > 0.0:
			d = IsoMath.basis().basis_xform(next - position).length()
		if d > step:
			position = position.lerp(next, step / d)
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
	if _house() != null and _house().iso:
		var local := IsoMath.basis().basis_xform(world_pos - position)
		return Rect2(-Vector2(b.x * 0.5, b.y), b).grow(6.0).has_point(local)
	return Rect2(position - Vector2(b.x * 0.5, b.y), b).grow(6.0).has_point(world_pos)


func rect() -> Rect2:
	var b := body()
	return Rect2(position - Vector2(b.x * 0.5, b.y), b)


func _compute_target(w: World, l: HouseLayout) -> Vector2:
	var hv = _house()
	# Being looked after: it keeps still where it is.
	for q in w.people:
		if q.alive and not q.current.is_empty() and int(q.current.get("target_uid", -1)) == pet.uid:
			_key = ""
			return position
	var cur := pet.current
	if cur.has("follow") and hv != null and "people" in hv and hv.people.has(int(cur["follow"])):
		_key = ""
		# A step behind them (to the west), not at their heels.
		var lead := (hv.people[int(cur["follow"])] as PersonView).position
		return lead + Vector2(-FOLLOW_GAP, 4) if not l.site.enabled else l.stop_point(lead + Vector2(-FOLLOW_GAP, 4), {l.site.cell_of(lead): true})
	if cur.has("object_uid"):
		var o := w.object(int(cur["object_uid"]))
		if not o.is_empty():
			_key = ""
			var r := l.object_rect(o, w.pack)
			var skin: PackSkin = hv.skin if hv != null and "skin" in hv else null
			var k := PetSystem.kind_of(w.pack, pet)
			# On what it lies on (the threshold, the kang) or perches in; beside anything else.
			if str(k.get("perch", "")) == str(o.type) or not l.site.enabled:
				return Vector2(r.get_center().x, r.end.y - 4.0)
			if skin != null and skin.sat_on(str(o.type)):
				return _on_piece(o, r)
			# Its spot stays put while nobody comes to stand on it.
			var taken := _people_cells(l)
			if _spot_for == int(o.uid) and not taken.has(l.site.cell_of(_spot)):
				return _spot
			_spot_for = int(o.uid)
			_spot = l.stand_pos(o, w.pack, taken)
			return _spot
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
		return _free_spot(l, l.cell_center(room, _rng.randi_range(0, int(r.w) - 1), _rng.randi_range(0, int(r.h) - 1)))
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
	return _free_spot(l, l.cell_center(room, _rng.randi_range(0, int(rd.w) - 1), _rng.randi_range(0, int(rd.h) - 1)))


## Where it lies on a piece people also sit or lie on (the kang, the threshold): along its
## front edge, as far as it can be from the people on it or heading there.
func _on_piece(o: Dictionary, r: Rect2) -> Vector2:
	var y := r.end.y - 4.0
	var best := Vector2(r.get_center().x, y)
	var hv := _house()
	if hv == null:
		return best
	var best_d := -INF
	var n := maxi(1, int(r.size.x / 24.0))
	for i in n + 1:
		var p := Vector2(lerpf(r.position.x + 12.0, r.end.x - 12.0, float(i) / float(n)), y)
		var d := INF
		for uid in hv.people:
			var pv: PersonView = hv.people[uid]
			if int(pv.use_object.get("uid", -2)) == int(o.uid) or r.grow(HouseSite.CELL.y).has_point(pv.target):
				d = minf(d, absf(pv.target.x - p.x))
		# The furthest from everyone; the middle when nobody is on it.
		var score := minf(d, 1000.0) - 0.01 * absf(p.x - r.get_center().x)
		if score > best_d:
			best_d = score
			best = p
	return best


## A spot to stand about at near `p`: off furniture and wall lines, and a cell away from
## where anyone stands or is heading (an animal keeps a little distance).
func _free_spot(l: HouseLayout, p: Vector2) -> Vector2:
	return l.stop_point(p, _people_cells(l))


## The cells people are heading to, with the cells their feet reach into (Vector2i -> true).
func _people_cells(l: HouseLayout) -> Dictionary:
	var out := {}
	var hv := _house()
	if hv == null or not l.site.enabled:
		return out
	for uid in hv.people:
		var pv: PersonView = hv.people[uid]
		for at in [pv.target]:
			for dx in [-HouseSite.FEET - 10.0, 0.0, HouseSite.FEET + 10.0]:
				out[l.site.cell_of(at + Vector2(dx, 0))] = true
	return out


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
	var pic: Texture2D = _look.get(turned, _look.tex) if turned != "side" else _look.tex
	var pb := b
	if pic != _look.tex:
		pb = Vector2(b.y * pic.get_width() / pic.get_height(), b.y)
	draw_texture_rect(pic, Rect2(-pb.x * 0.5, -pb.y, pb.x, pb.y), false, tint)
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
