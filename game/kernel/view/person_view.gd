class_name PersonView
extends Node2D
## One person as a coloured block that walks to whatever they are doing. Reads the World,
## never writes it.

const SPEED := 140.0
const BODY := Vector2(28, 44)
const MALE := Color(0.35, 0.55, 0.85)
const FEMALE := Color(0.88, 0.5, 0.62)
const OTHER := Color(0.6, 0.6, 0.6)
const ELDER_TINT := Color(0.62, 0.62, 0.62)

var person: Person
var session: GameSession
## Where the person is heading, after the house has spread out people sharing a cell.
var target := Vector2.ZERO
## Where they would head alone; the house adds the sideways offset on top.
var base_target := Vector2.ZERO
var held := false

var _name := ""
var _doing := ""
var _key := ""
var _rng := RandomNumberGenerator.new()
var _box := StyleBoxFlat.new()


func setup(p: Person, s: GameSession) -> void:
	person = p
	session = s
	_rng.randomize()
	_box.set_corner_radius_all(8)
	var l := layout()
	if l != null and session.world != null and session.world.phase != "invalid":
		position = _entrance(session.world, l)
	refresh()


func layout() -> HouseLayout:
	return get_parent().layout if get_parent() != null and "layout" in get_parent() else null


func refresh() -> void:
	var w := session.world
	if w == null or person == null:
		return
	_name = session.strings.person_name(person)
	_doing = session.strings.doing(person, w)
	var l := layout()
	if l != null:
		base_target = _compute_target(w, l)
		target = base_target
	var elder := false
	var stages: Array = w.pack.cfg("stages")
	if not stages.is_empty():
		elder = person.stage(w.pack) == str(stages[-1]["id"])
	var c := FEMALE if person.gender == "female" else (MALE if person.gender == "male" else OTHER)
	_box.bg_color = c.lerp(ELDER_TINT, 0.7) if elder else c
	queue_redraw()


func tick(delta: float) -> void:
	if held:
		return
	position = position.move_toward(target, SPEED * delta)


func _compute_target(w: World, l: HouseLayout) -> Vector2:
	var cur := person.current
	if not cur.is_empty():
		var oid := int(cur.get("object_uid", -1))
		if oid >= 0:
			var o := w.object(oid)
			if not o.is_empty():
				_key = ""
				return l.stand_pos(o, w.pack)
		var tid := int(cur.get("target_uid", -1))
		if tid >= 0:
			for list in [w.messes, w.collectibles]:
				for m in list:
					if int(m.uid) == tid:
						_key = ""
						return l.cell_center(str(m.room), int(m.x), int(m.y))
	if cur.is_empty():
		_key = ""
		return base_target if base_target != Vector2.ZERO else position
	var room := l.nearest_room(position, w.rooms_built)
	if room == "":
		return _entrance(w, l)
	var key := str(cur.get("action", ""))
	if key != _key:
		_key = key
		var r: Dictionary = w.pack.rooms[room]
		var cell := Vector2i(_rng.randi_range(0, int(r.w) - 1), _rng.randi_range(0, int(r.h) - 1))
		return l.cell_center(room, cell.x, cell.y)
	return base_target


func _entrance(w: World, l: HouseLayout) -> Vector2:
	for id in w.pack.rooms:
		if id in w.rooms_built and not bool(w.pack.rooms[id].get("outdoor", false)):
			return l.room_rect(id).get_center()
	return Vector2.ZERO


func _draw() -> void:
	if person == null:
		return
	draw_style_box(_box, Rect2(Vector2(-BODY.x * 0.5, -BODY.y), BODY))
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(1, 1, 1, 0.88)
	plate.set_corner_radius_all(5)
	draw_style_box(plate, Rect2(Vector2(-70, -BODY.y - 36), Vector2(140, 34)))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-70, -BODY.y - 21), _name, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color.BLACK)
	draw_string(font, Vector2(-70, -BODY.y - 6), _doing, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(0.1, 0.1, 0.1))
