class_name VisitorView
extends PersonView
## Someone from outside the family who walks in for a while: the doctor of a doctor service
## (`ServiceSystem` "doctor"). Drawn like a person of the house with the look the service
## names, from a stand-in `Person` that is not in the world. The house moves it (`goal`), it
## says the diagnosis over its head (`say`), and it never takes a click.

## The uid of the stand-in (no person of the world has a negative uid).
const UID := -7
## Seconds the words stay over its head.
const SAY_SECONDS := 7.0

## Where it is heading (house coordinates).
var goal := Vector2.ZERO
## True once it is on its way out.
var leaving := false
## What it says ("" for nothing) and for how long more.
var say := ""
var _say_left := 0.0
## The words on its plate while it works ("" for none).
var busy_text := ""


## A stand-in for the visitor of doctor service `sid`: old, of the look's sex, called by the
## service's `visitor`.
static func stand_in(world: World, sid: String) -> Person:
	var sv: Dictionary = world.pack.services.get(sid, {})
	var p := Person.new()
	p.uid = UID
	p.given = str(sv.get("visitor", ""))
	p.look = str(sv.get("look", ""))
	p.gender = "male"
	for e in LookSystem.looks(world.pack):
		if str(e["id"]) == p.look:
			p.gender = str(e["sex"])
	var stages: Array = world.pack.cfg("stages")
	p.age = float(stages[-1].get("from", 60)) + 5.0 if not stages.is_empty() else 60.0
	p.lifespan = p.age + 100.0
	return p


func refresh() -> void:
	base_target = goal
	super.refresh()
	if busy_text != "":
		_doing = busy_text


func tick(delta: float) -> void:
	super.tick(delta)
	visible = true
	if _say_left > 0.0:
		_say_left -= delta
		if _say_left <= 0.0:
			say = ""


## Shows `text` over its head for SAY_SECONDS.
func speak(text: String) -> void:
	say = text
	_say_left = SAY_SECONDS


## Whether it has reached `goal`.
func arrived() -> bool:
	return position.distance_to(target) <= ARRIVED


func pose() -> String:
	if position.distance_to(target) > ARRIVED:
		return "walking"
	return "busy" if busy_text != "" else "idle"


func _say_size() -> Vector2:
	if say == "":
		return Vector2.ZERO
	var font := ThemeDB.fallback_font
	var w := minf(font.get_string_size(say, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20.0, 260.0)
	var lines := ceili((font.get_string_size(say, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20.0) / 260.0)
	return Vector2(w, 10.0 + 18.0 * lines + 8.0)


func label_size() -> Vector2:
	var base := super.label_size()
	var s := _say_size()
	return Vector2(maxf(base.x, s.x), base.y + s.y)


## The plate, and over it a speech bubble with what it says.
func draw_label(ci: CanvasItem, at: Vector2) -> void:
	super.draw_label(ci, at)
	if say == "":
		return
	var size := _say_size()
	var top := at.y - super.label_size().y - size.y
	var rect := Rect2(at.x - size.x * 0.5, top, size.x, size.y - 8.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#FFFDF6")
	box.border_color = Color("#4A3424")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	ci.draw_style_box(box, rect)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(at.x - 6, rect.end.y - 1), Vector2(at.x + 6, rect.end.y - 1),
		Vector2(at.x, rect.end.y + 7)]), Color("#4A3424"))
	var font := ThemeDB.fallback_font
	ci.draw_multiline_string(font, Vector2(rect.position.x + 10, rect.position.y + 19), say, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 20.0, 14, -1, Color("#4A3424"))
