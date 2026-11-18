class_name WeatherView
extends Node2D
## Falling rain or snow over the whole window, and a light tint, as the pack's current
## weather entry describes it (`view`: kind "rain" | "snow", `amount` 0..1, `color`, `tint`).
## Theme-neutral: it knows nothing but those fields. Drawn in screen space just above the
## house; reads the World, never writes it.

## Particles at amount 1.0 on a 1280x720 window (scaled with the window area).
const MAX_DROPS := 260
const RAIN_SPEED := Vector2(-120.0, 900.0)
const SNOW_SPEED := Vector2(0.0, 70.0)
const RAIN_LENGTH := 22.0

var session: GameSession
## {pos: Vector2, speed: float, phase: float} per particle.
var _drops: Array = []
var _kind := ""
var _amount := 0.0
var _color := Color.WHITE
var _tint := Color(0, 0, 0, 0)
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func setup(s: GameSession) -> void:
	session = s
	_rng.seed = 7  # looks only; never touches the sim's random numbers
	z_index = 50
	refresh()


func _size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else HouseView.VIEW_SIZE


## The view settings of the world's weather now ({} for none).
func current() -> Dictionary:
	var w := session.world if session != null else null
	if w == null or w.phase == "invalid":
		return {}
	var v = WeatherSystem.weather_entry(w.pack, w.weather).get("view", {})
	return v if v is Dictionary else {}


func kind() -> String:
	return _kind


func drop_count() -> int:
	return _drops.size()


func refresh() -> void:
	var v := current()
	_kind = str(v.get("kind", ""))
	_amount = clampf(float(v.get("amount", 0.0)), 0.0, 1.0)
	_color = HouseView.pack_color(v, Color.WHITE)
	var t = v.get("tint")
	_tint = Color.html(t) if t is String and Color.html_is_valid(t) else Color(0, 0, 0, 0)
	var size := _size()
	var want := 0 if _kind == "" else int(MAX_DROPS * _amount * (size.x * size.y) / (1280.0 * 720.0))
	while _drops.size() > want:
		_drops.pop_back()
	while _drops.size() < want:
		_drops.append({"pos": Vector2(_rng.randf() * size.x, _rng.randf() * size.y),
			"speed": _rng.randf_range(0.7, 1.3), "phase": _rng.randf() * TAU})
	queue_redraw()


func tick(delta: float) -> void:
	_time += delta
	if _drops.is_empty():
		return
	var size := _size()
	for d in _drops:
		var p: Vector2 = d.pos
		if _kind == "snow":
			p += (SNOW_SPEED * float(d.speed) + Vector2(sin(_time * 1.3 + float(d.phase)) * 25.0, 0.0)) * delta
		else:
			p += RAIN_SPEED * float(d.speed) * delta
		if p.y > size.y + RAIN_LENGTH:
			p = Vector2(_rng.randf() * (size.x + 200.0), -RAIN_LENGTH)
		if p.x < -40.0:
			p.x += size.x + 80.0
		elif p.x > size.x + 40.0:
			p.x -= size.x + 80.0
		d.pos = p
	queue_redraw()


func _draw() -> void:
	if _tint.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, _size()), _tint)
	if _kind == "rain":
		var dir := RAIN_SPEED.normalized() * RAIN_LENGTH
		var c := Color(_color, 0.55)
		for d in _drops:
			draw_line(d.pos, d.pos + dir * float(d.speed), c, 1.4)
	elif _kind == "snow":
		var c2 := Color(_color, 0.9)
		for d in _drops:
			draw_circle(d.pos, 1.6 + float(d.speed) * 1.4, c2)
