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
var house: HouseView
## Where the person is heading, after the house has spread out people sharing a cell.
var target := Vector2.ZERO
## Where they would head alone; the house adds the sideways offset on top.
var base_target := Vector2.ZERO
var held := false
## The corners still to walk through on the way to `target` (walls in between); empty when
## the way is straight. Worked out again whenever the target or the position changes
## from outside (a drop, a test).
var path := PackedVector2Array()
## The furniture they are heading to use ({}: none), so the house can find them another
## spot at it when theirs is taken.
var use_object: Dictionary = {}
## Whether they sit or lie on `use_object` (the pack's `poses.on`) rather than beside it.
var on_object := false
## The pose the current action asks for ("": none; see `_pick_pose`).
var action_pose := ""
var _path_goal := Vector2(INF, INF)
var _path_from := Vector2(INF, INF)
var selected := false:
	set(v):
		selected = v
		queue_redraw()

## The little 赏/罚 character that floats above the head for a second.
class FloatMark:
	extends Node2D
	const LIFETIME := 1.0
	var text := ""
	var age := 0.0
	## How tall the body under it is.
	var top := PersonView.BODY.y

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(-14, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 28, 22, Color(0.8, 0.15, 0.1))

	func tick(delta: float) -> bool:
		age += delta
		position.y = -top - 50.0 - age * 24.0
		return age < LIFETIME

var _mark: FloatMark

var _name := ""
var _doing := ""
## The label of the last thing they were busy with, and the World time they fell idle
## (-1: busy). Between two actions the kernel leaves a person idle for a step; the plate
## keeps the previous label through such a gap instead of flashing the idle text.
var _last_doing := ""
var _idle_from := -1
var _key := ""
var _rng := RandomNumberGenerator.new()
var _box := StyleBoxFlat.new()
var _body := Color.WHITE
## Height of the block relative to a grown-up's: babies and children are drawn smaller.
var size_factor := 1.0
## Time accumulated by tick(); drives the bob.
var _t := 0.0
## What the progress line follows: the action's identity, the kernel's last remaining_s, the
## time since that value last changed, and the furthest the line has reached.
var _pkey := ""
var _rem := -1.0
var _since := 0.0
var _maxp := 0.0
## The wish text shown in a thought bubble ("" for none).
var _wish := ""
## With the pack's art: {tex, height} of this person's picture ({}: drawn as a block), which
## way they face (1 right, -1 left; the pictures face right) and whether they look unwell.
var _look: Dictionary = {}
var _facing := 1.0
## The 45° view: which way the body is turned, for picking a rig: "side", "front" (towards
## the camera, walking down the screen) or "back" (away, walking up it).
var turned := "side"
## The 45° view: the way they would turn to, and for how long it has held (a turn waits
## TURN_HOLD, so a corner of the path does not flick the body round and back).
var _turn_want := "side"
var _turn_held := 0.0
const TURN_HOLD := 0.12
## The rig drawn now and the one fading out after a turn (0..1 through TURN_FADE).
var _rig_now: CutoutRig
var _rig_now_k := 1.0
var _rig_was: CutoutRig
var _rig_was_k := 1.0
var _fade := 1.0
const TURN_FADE := 0.16
## The walk cycle's clock: advances with the distance walked (screen pixels / STRIDE of a
## grown-up's cycle, shorter for smaller people), so feet do not slide.
var _stride_t := 0.0
const STRIDE := 100.0
## Old people walk this much slower.
const ELDER_PACE := 0.72
var _unwell := false
## Half a step of the walking bob, in seconds; how high the step lifts.
const STEP_PERIOD := 0.36
const STEP_LIFT := 2.5

## The thank-you wave: a quicker, higher hop and a waving arm.
const THANKS_HOP := 6.0
const THANKS_PERIOD := 0.45
const BOB_AMPLITUDE := 3.0
const BOB_PERIOD := 0.8
const ASLEEP_DARKEN := 0.3
const ARRIVED := 1.0
const BABY_SIZE := 0.5
## A flat picture sitting is drawn this much of its height.
const SIT_SQUASH := 0.8
const CHILD_SIZE := 0.75


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
	var h := _house()
	return h.layout if h != null else null


## The house this stands in (set by the house; else the parent, as in tests that build one).
func _house() -> HouseView:
	if house != null:
		return house
	return get_parent() as HouseView


func refresh() -> void:
	var w := session.world
	if w == null or person == null:
		return
	_name = session.strings.person_name(person)
	_doing = session.strings.doing(person, w)
	if not person.current.is_empty():
		_last_doing = _doing
		_idle_from = -1
	else:
		if _idle_from < 0:
			_idle_from = w.now
		if _last_doing != "" and float(w.now - _idle_from) <= idle_grace():
			_doing = _last_doing
	var l := layout()
	action_pose = _pick_pose(w)
	if l != null:
		use_object = {}
		on_object = false
		var want := _compute_target(w, l)
		if action_pose == "sit" and not on_object:
			# No seat under them: sitting on air reads as broken legs; they stand to do it.
			action_pose = "idle"
		# On a seat or a bed the spot is on the piece itself (see `on_spot`).
		base_target = want if on_object else l.stop_point(want)
		target = base_target
	var elder := false
	var stages: Array = w.pack.cfg("stages")
	if not stages.is_empty():
		elder = person.stage(w.pack) == str(stages[-1]["id"])
	var c := FEMALE if person.gender == "female" else (MALE if person.gender == "male" else OTHER)
	_body = c.lerp(ELDER_TINT, 0.7) if elder else c
	match person.stage(w.pack):
		"baby":
			size_factor = BABY_SIZE
		"child":
			size_factor = CHILD_SIZE
		_:
			size_factor = 1.0
	_track_progress(w)
	_wish = session.strings.wish_text(person, w)
	var skin := _skin()
	_look = {}
	_unwell = false
	if skin != null and skin.enabled:
		_look = skin.person_look(person.stage(w.pack), person.gender, person.look)
		var u := skin.unwell()
		if not u.is_empty() and person.needs.has(u.need):
			_unwell = float(person.needs[u.need]) < float(u.below)
	queue_redraw()


func _skin() -> PackSkin:
	var hv = _house()
	return hv.skin if hv != null and "skin" in hv else null


## The clickable body: the picture's size with the pack's art (narrowed to the figure),
## else the block.
func body_size() -> Vector2:
	if _look.is_empty():
		return BODY
	var tex: Texture2D = _look.tex
	var h: float = _look.height
	return Vector2(clampf(h * tex.get_width() / tex.get_height(), 30.0, 50.0), h)


## Whether the pack's art draws this person (else the whitebox block).
func pictured() -> bool:
	return not _look.is_empty()


## True while the person stops to thank the player (they turn to the screen and wave).
func thanking() -> bool:
	return person != null and session.world != null and person.thanking(session.world.now)


## What the body is doing, for drawing: "thanks" (facing the screen, waving), "asleep",
## "busy" (at work in place), "walking" or "idle". The art pass maps these to animations.
func pose() -> String:
	if person == null:
		return "idle"
	if thanking():
		return "thanks"
	if asleep():
		return "asleep"
	if position.distance_to(target) > ARRIVED and not held:
		return "walking"
	return "busy" if not person.current.is_empty() else "idle"


## The words over them while they face the screen: news of what they earned, else thanks.
func thanks_words() -> String:
	return session.strings.thanks_text(person, session.world)


func thanks_width() -> float:
	return maxf(80.0, ThemeDB.fallback_font.get_string_size(thanks_words(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8.0)


## The text of the thought bubble ("" when there is no wish).
func wish_bubble() -> String:
	return _wish


func tick(delta: float) -> void:
	_t += delta
	_since += delta
	if not person.current.is_empty() or thanking():
		_maxp = maxf(_maxp, _estimate())
		queue_redraw()
	if _mark != null and not _mark.tick(delta):
		remove_child(_mark)
		_mark.queue_free()
		_mark = null
	if held:
		return
	var was := position
	walk(SPEED * delta * pace())
	visible = not out_of_sight()
	var moved := position - was
	if _house() != null and _house().iso:
		moved = IsoMath.basis().basis_xform(moved) / IsoMath.ISO_PACE
	var tall := (_look.height as float) if not _look.is_empty() else 90.0
	_stride_t += moved.length() / (STRIDE * clampf(tall / 90.0, 0.6, 1.1) * (0.85 if pace() < 1.0 else 1.0)) * CutoutRig.WALK_PERIOD
	_fade = minf(1.0, _fade + delta / TURN_FADE)
	_turn(position - was, delta)
	if pictured() and position != was or _fade < 1.0:
		queue_redraw()


## How fast they walk, against a grown-up: old people slower.
func pace() -> float:
	if person == null or session == null or session.world == null:
		return 1.0
	var stages: Array = session.world.pack.cfg("stages")
	if stages.size() > 2 and person.stage(session.world.pack) == str(stages[-1]["id"]):
		return ELDER_PACE
	return 1.0


## Which way they face after moving by `d` (house coordinates): left or right on the screen,
## and in the 45° view towards the camera, away or sideways; standing at furniture they
## turn sideways to it; standing about they face the camera.
func _turn(d: Vector2, delta := 1.0) -> void:
	var iso := _house() != null and _house().iso
	var v := IsoMath.basis().basis_xform(d) if iso else d
	if absf(v.x) > 0.01:
		_facing = signf(v.x)
	if not iso:
		return
	var want := turned
	if v.length() > 0.01:
		want = "side" if absf(v.y) < 0.2 * v.length() else ("front" if v.y > 0.0 else "back")
	elif not use_object.is_empty() and layout() != null and session.world != null:
		var mid := layout().object_rect(use_object, session.world.pack).get_center()
		var dv := IsoMath.basis().basis_xform(mid - position)
		if absf(dv.x) > 1.0:
			_facing = signf(dv.x)
		want = "side"
	elif person != null and person.current.is_empty():
		want = "front"
	if want != _turn_want:
		_turn_want = want
		_turn_held = 0.0
	_turn_held += delta
	if _turn_held >= TURN_HOLD:
		turned = want


## The rig for the pose: a front or back rig while walking or standing about, when the
## pack has one; else the side rig. With its size factor (heads as big as the side rig's).
func _rig_for(bp: String) -> Array:
	var side: CutoutRig = _look.get("rig")
	if side == null or not bp in ["walk", "idle"] or turned == "side":
		return [side, 1.0]
	var r: CutoutRig = _look.get("rig_" + turned)
	if r == null:
		return [side, 1.0]
	var k := 1.0
	if r.head_height > 0.0 and side.head_height > 0.0:
		k = clampf((side.head_height / side.height) / (r.head_height / r.height), 0.75, 1.1)
	return [r, k]


## Moves up to `step` pixels along the way to `target`, round walls through their doors.
func walk(step: float) -> void:
	if target != _path_goal or position != _path_from:
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


## The "what they are doing" text on the plate (the previous action's through a short
## idle gap).
func doing_text() -> String:
	return _doing


## The longest idle gap, in World seconds, that still shows the previous action: one
## kernel step plus a second.
func idle_grace() -> float:
	return float(session.world.step_s) + 1.0 if session.world != null else 0.0


## How far through the current action, 0..1; -1 when idle. Between the kernel's steps the
## value is extrapolated from tick time (at most one step), and never moves backwards.
func progress() -> float:
	if person == null or person.current.is_empty() or session.world == null:
		return -1.0
	return clampf(maxf(_estimate(), _maxp), 0.0, 1.0)


func _duration() -> float:
	var w := session.world
	var aid := str(person.current.get("action", ""))
	if not w.pack.actions.has(aid):
		return 0.0
	return float(AutonomySystem.duration_s(w, w.pack.actions[aid]))


func _estimate() -> float:
	var d := _duration()
	if d <= 0.0:
		return 0.0
	var rem := float(person.current.get("remaining_s", d))
	var v := 1.0 - rem / d
	if is_equal_approx(rem, _rem):
		v += minf(_since, float(session.world.step_s)) / d
	return clampf(v, 0.0, 1.0)


func _track_progress(w: World) -> void:
	var cur := person.current
	if cur.is_empty():
		_pkey = ""
		_rem = -1.0
		_since = 0.0
		_maxp = 0.0
		return
	var key := "%s|%s|%s" % [cur.get("action", ""), cur.get("object_uid", -1), cur.get("target_uid", -1)]
	var rem := float(cur.get("remaining_s", 0))
	if key != _pkey or rem > _rem:
		_pkey = key
		_maxp = 0.0
		_rem = rem
		_since = 0.0
	elif rem != _rem:
		_rem = rem
		_since = 0.0
	_maxp = maxf(_maxp, _estimate())


## Whether the current action is a slow one (sleeping).
func slow() -> bool:
	if person == null or person.current.is_empty() or session.world == null:
		return false
	var aid := str(person.current.get("action", ""))
	var acts: Dictionary = session.world.pack.actions
	return acts.has(aid) and bool(acts[aid].get("slow", false))


## True while doing something slow (sleeping) and in place.
func asleep() -> bool:
	return slow() and position.distance_to(target) <= ARRIVED


## The vertical wobble of the block while busy in place: zero when idle, walking, held or asleep.
func bob_offset() -> float:
	if thanking() and not held:
		return -absf(THANKS_HOP * sin(TAU * _t / THANKS_PERIOD))
	if person == null or held or person.current.is_empty() or asleep():
		return 0.0
	if position.distance_to(target) > ARRIVED:
		return 0.0
	return BOB_AMPLITUDE * sin(TAU * _t / BOB_PERIOD)


## True once someone out on an outing has reached where they leave from (the gate): the
## house does not show them until they are back.
func out_of_sight() -> bool:
	return person != null and session != null and session.world != null and not held \
		and OutingSystem.away(session.world, person) and position.distance_to(target) <= ARRIVED


## Whether a point in the house's coordinates lands on this person's body or name plate.
func hit(world_pos: Vector2) -> bool:
	if not visible:
		return false
	var local := world_pos - position
	if _house() != null and _house().iso:
		local = IsoMath.basis().basis_xform(local)
	var body := body_size()
	return Rect2(Vector2(-body.x * 0.5, -body.y), body).grow(4.0).has_point(local)


## Floats `text` above the head for a second, replacing any one already showing.
func float_text_up(text: String) -> void:
	if _mark == null:
		_mark = FloatMark.new()
		add_child(_mark)
	_mark.text = text
	_mark.age = 0.0
	_mark.top = body_size().y
	_mark.position = Vector2(0, -_mark.top - 50.0)
	_mark.queue_redraw()


func float_text() -> String:
	return _mark.text if _mark != null else ""


func _compute_target(w: World, l: HouseLayout) -> Vector2:
	var cur := person.current
	if not cur.is_empty():
		var oid := int(cur.get("object_uid", -1))
		if oid >= 0:
			var o := w.object(oid)
			if not o.is_empty():
				_key = ""
				use_object = o
				var skin := _skin()
				if action_pose in ["sit", "sleep"] and skin != null and skin.sat_on(str(o.type)):
					on_object = true
					return on_spot(l, o, w.pack)
				return l.stand_pos(o, w.pack)
		var tid := int(cur.get("target_uid", -1))
		if tid >= 0:
			for list in [w.messes, w.collectibles]:
				for m in list:
					if int(m.uid) == tid:
						_key = ""
						return l.cell_center(str(m.room), int(m.x), int(m.y))
			# Caring for a baby or a pet: over to where it is, just beside it.
			var hv = _house()
			if hv != null and "pets" in hv and hv.pets.has(tid):
				_key = ""
				var pet := hv.pets[tid] as PetView
				if pictured():
					# Clear of the animal's own name plate, so the two plates do not overlap.
					return pet.position + Vector2(body_size().x * 0.5 + pet.body().x * 0.5 + 34.0, 0)
				return pet.position + Vector2(BODY.x, 0)
			if hv != null and "people" in hv and hv.people.has(tid) and hv.people[tid] != self:
				_key = ""
				return (hv.people[tid] as PersonView).base_target + Vector2(BODY.x, 0)
	if cur.is_empty():
		_key = ""
		return base_target if base_target != Vector2.ZERO else position
	# An action that finishes a story at its mark (digging): straight to the mark.
	var sid := str(w.pack.actions.get(str(cur.get("action", "")), {}).get("completes_story", ""))
	if sid != "":
		for m in StorySystem.marks(w):
			if m.story == sid and m.get("dig", false):
				_key = ""
				return l.cell_center(str(m.room), int(m.x), int(m.y))
	# An action that names where it happens: a random cell of that room.
	var room := str(cur.get("room", ""))
	if room == "" or not w.pack.rooms.has(room) or l.room_rect(room).size == Vector2.ZERO:
		# Somewhere at home: the places outside the house are only for what is done there.
		var home := w.rooms_built.filter(func(r): return not bool(w.pack.rooms[r].get("outside", false)))
		room = l.nearest_room(position, home if not home.is_empty() else w.rooms_built)
	if room == "":
		return _entrance(w, l)
	var key := "%s|%s" % [cur.get("action", ""), cur.get("room", "")]
	if key != _key:
		_key = key
		var r: Dictionary = w.pack.rooms[room]
		var cell := Vector2i(_rng.randi_range(0, int(r.w) - 1), _rng.randi_range(0, int(r.h) - 1))
		# A few tries for a cell nobody's furniture stands on.
		for i in 8:
			if not l.site.enabled or l.site.walkable(l.site.cell_of(l.cell_center(room, cell.x, cell.y))):
				break
			cell = Vector2i(_rng.randi_range(0, int(r.w) - 1), _rng.randi_range(0, int(r.h) - 1))
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
	if pictured():
		_draw_pictured()
		return
	var bob := bob_offset()
	_box.bg_color = _body.darkened(ASLEEP_DARKEN) if asleep() else _body
	var body := BODY * Vector2(maxf(size_factor, 0.7), size_factor)
	draw_style_box(_box, Rect2(Vector2(-body.x * 0.5, -body.y + bob), body))
	if selected:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = Color(0.95, 0.75, 0.1)
		ring.set_border_width_all(3)
		ring.set_corner_radius_all(10)
		draw_style_box(ring, Rect2(Vector2(-BODY.x * 0.5, -BODY.y + bob), BODY).grow(4.0))
	if thanking():
		# Facing the screen: two eyes, a raised arm waving, and a small thank-you above.
		var top := Vector2(0, -BODY.y + bob)
		draw_circle(top + Vector2(-6, 10), 2.5, Color(0.1, 0.1, 0.1))
		draw_circle(top + Vector2(6, 10), 2.5, Color(0.1, 0.1, 0.1))
		var sway := 0.5 * sin(TAU * _t / THANKS_PERIOD)
		var shoulder := top + Vector2(BODY.x * 0.5, 14)
		draw_line(shoulder, shoulder + Vector2(10, -16).rotated(sway), _body.darkened(0.25), 5.0)
		var tw := thanks_width()
		draw_string(ThemeDB.fallback_font, Vector2(-tw * 0.5, -BODY.y - 44), thanks_words(),
			HORIZONTAL_ALIGNMENT_CENTER, tw, 14, Color(0.75, 0.2, 0.1))
	elif _wish != "":
		_draw_bubble()
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(1, 1, 1, 0.88)
	plate.set_corner_radius_all(5)
	draw_style_box(plate, Rect2(Vector2(-70, -BODY.y - 36), Vector2(140, 34)))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-70, -BODY.y - 21), _name, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color.BLACK)
	draw_string(font, Vector2(-70, -BODY.y - 6), _doing, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(0.1, 0.1, 0.1))
	var prog := progress()
	if prog >= 0.0:
		draw_rect(Rect2(Vector2(-70, -BODY.y - 4), Vector2(140.0 * prog, 2)), Color(0.2, 0.6, 0.3))


## A thought bubble with the wish above the name plate.
func _draw_bubble() -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(_wish, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	var rect := Rect2(Vector2(-w * 0.5, -BODY.y - 66), Vector2(w, 22))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.95)
	box.border_color = Color(0.55, 0.5, 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	draw_style_box(box, rect)
	draw_circle(Vector2(-6, -BODY.y - 40), 3.0, Color(1, 1, 1, 0.95))
	draw_circle(Vector2(-10, -BODY.y - 36), 2.0, Color(1, 1, 1, 0.95))
	draw_string(font, rect.position + Vector2(0, 16), _wish, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.2, 0.15, 0.1))


## The ring under the feet shows only while the player presses on or carries this person.
const RING_FILL := Color(1, 1, 1, 0.22)
const RING_LINE := Color(1, 1, 1, 0.7)
func ring_shown() -> bool:
	if held:
		return true
	var h := _house()
	return h != null and person != null and h.pressing_uid() == person.uid


## The walking step: a small hop on every step while walking, 0 otherwise.
func step_lift() -> float:
	if pose() != "walking":
		return 0.0
	return -absf(sin(PI * _t / STEP_PERIOD)) * STEP_LIFT


## The person drawn from the pack's art: a soft shadow, the picture (mirrored when walking
## left, a hop per step, darker asleep), the selection ring and pointer in the skin's accent
## colour, the unwell mark, and a cream name plate.
func _draw_pictured() -> void:
	var skin := _skin()
	var accent := skin.accent if skin != null else Color("#E5533C")
	var tex: Texture2D = _look.tex
	var body := body_size()
	var h: float = _look.height
	var w := h * tex.get_width() / tex.get_height()
	var bp := body_pose()
	var picked := _rig_for(bp)
	var rig: CutoutRig = picked[0]
	var lift := step_lift() if rig == null else 0.0
	var iso := _house() != null and _house().iso
	if thanking() and not held:
		lift = bob_offset()
	var line := Color("#4A3424")
	var lying := bp == "sleep" and not bool(_look.get("lying", false))
	if not lying:
		draw_colored_polygon(HouseGround._ellipse(Rect2(Vector2(-w * 0.45, -5), Vector2(w * 0.9, 10))), Color(HouseGround.SHADOW, 0.25))
	if ring_shown():
		# Only while the player has them in hand: a soft white ellipse on the floor.
		var ring := HouseGround._ellipse(Rect2(Vector2(-30, -15), Vector2(60, 30)) if iso else Rect2(Vector2(-27, -10), Vector2(54, 20)), 32)
		draw_colored_polygon(ring, RING_FILL)
		ring.append(ring[0])
		draw_polyline(ring, RING_LINE, 2.5)
	var tint := Color.WHITE
	if _unwell:
		tint = tint.lerp(Color(0.72, 0.8, 0.7), 0.45)
	var flip := Vector2(_facing, 1.0)
	if lying:
		# On the back, along the ground (or on what they lie on), head to one side.
		var at := lie_point()
		draw_colored_polygon(HouseGround._ellipse(Rect2(at + Vector2(-h * 0.5, 2), Vector2(h, 14))), Color(HouseGround.SHADOW, 0.2))
		if _look.has("asleep") and bool(_look.get("asleep_iso", false)) and iso:
			# A 45° picture of someone under a quilt, along the piece they lie on.
			var pic2: Texture2D = _look.asleep
			var pw := 110.0
			var along_y := false
			if on_object and not use_object.is_empty() and layout() != null and session.world != null:
				var orr := layout().object_rect(use_object, session.world.pack)
				pw = IsoMath.view_rect(orr).size.x * 0.72
				along_y = orr.size.y / HouseSite.CELL.y > orr.size.x / HouseSite.CELL.x
			var ps := Vector2(pic2.get_size()) * (pw / pic2.get_width())
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1 if along_y else 1, 1))
			draw_texture_rect(pic2, Rect2(Vector2(at.x * (-1 if along_y else 1), at.y) - ps * 0.5, ps), false, tint)
			draw_set_transform(Vector2.ZERO)
		elif _look.has("asleep"):
			var pic: Texture2D = _look.asleep
			var len := h * 1.15
			draw_set_transform(Vector2.ZERO, 0.0, flip)
			draw_texture_rect(pic, PackSkin.fit_rect(pic, Vector2(at.x * _facing, at.y + len * 0.12), Vector2(len, len)), false, tint)
			draw_set_transform(Vector2.ZERO)
		elif rig != null:
			var k := h / rig.height
			var x := Transform2D(-PI * 0.5, at) * Transform2D(0.0, Vector2(_facing * k, k), 0.0, Vector2.ZERO) * Transform2D(0.0, Vector2(0, rig.height * 0.5))
			rig.draw(self, _rig_pose(rig, "sleep"), x, tint)
		else:
			draw_set_transform(at, -PI * 0.5, flip)
			draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5, w, h), false, tint)
			draw_set_transform(Vector2.ZERO)
	elif rig != null:
		if rig != _rig_now:
			# A turn: the old view fades out under the new one over TURN_FADE seconds.
			_rig_was = _rig_now
			_rig_was_k = _rig_now_k
			_rig_now = rig
			_rig_now_k = float(picked[1])
			_fade = 0.0 if _rig_was != null else 1.0
		if _fade < 1.0 and _rig_was != null:
			var k0 := h / _rig_was.height * _rig_was_k
			var tw := Color(tint, tint.a * (1.0 - _fade))
			_rig_was.draw(self, _rig_pose(_rig_was, bp), Transform2D(0.0, Vector2(_facing * k0, k0), 0.0, Vector2(0, lift + 2.0)), tw)
		var k2 := h / rig.height * float(picked[1])
		var tn := Color(tint, tint.a * smoothstep(0.0, 1.0, _fade))
		rig.draw(self, _rig_pose(rig, bp), Transform2D(0.0, Vector2(_facing * k2, k2), 0.0, Vector2(0, lift + 2.0)), tn)
	else:
		# One flat picture: walking hops and sways; working squashes in time; sitting is
		# drawn shorter; eating nods.
		var sway := 0.0
		var sq := Vector2.ONE
		match bp:
			"walk":
				sway = 0.04 * sin(TAU * _t / (STEP_PERIOD * 2.0))
			"work":
				var q := 0.5 + 0.5 * sin(TAU * _t / CutoutRig.WORK_PERIOD)
				sq = Vector2(1.0 + 0.03 * q, 1.0 - 0.06 * q)
			"sit":
				sq = Vector2(1.04, SIT_SQUASH)
			"eat":
				sway = 0.05 * sin(TAU * _t / CutoutRig.EAT_PERIOD)
			"wave":
				sway = 0.06 * sin(TAU * _t / CutoutRig.WAVE_PERIOD)
			_:
				sq = Vector2(1.0, 1.0 + 0.012 * sin(TAU * _t / CutoutRig.BREATH_PERIOD))
		draw_set_transform(Vector2(0, lift + 2.0), sway, flip * sq)
		draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, tint)
		draw_set_transform(Vector2.ZERO)
	h = drawn_height()
	var top := -h + lift
	if lying:
		top = lie_point().y - 14.0
	var font := ThemeDB.fallback_font
	if lying:
		for i in 3:
			draw_string_outline(font, Vector2(10 + i * 7, top + 4 - i * 9), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11 + i * 3, 3, Color.WHITE)
			draw_string(font, Vector2(10 + i * 7, top + 4 - i * 9), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11 + i * 3, line)
	if _unwell and skin != null:
		var u := skin.unwell()
		if not u.is_empty():
			var at := Vector2(body.x * 0.5 + 12, top + 6)
			draw_circle(at, 14, Color.WHITE)
			draw_arc(at, 14, 0, TAU, 24, accent, 2.5)
			draw_texture_rect(u.tex, PackSkin.fit_rect(u.tex, at + Vector2(0, 11), Vector2(22, 22)), false)
	if selected:
		draw_colored_polygon(PackedVector2Array([Vector2(-7, top - 12), Vector2(7, top - 12), Vector2(0, top - 3)]), accent)


## Where someone sitting or lying on furniture `o` has their feet: the middle of its front
## edge, a little inside it (the piece sorts ON_LIFT higher, so they are drawn over it).
static func on_spot(l: HouseLayout, o: Dictionary, pack: Pack) -> Vector2:
	var r := l.object_rect(o, pack)
	return Vector2(r.get_center().x, r.end.y - 4.0)


## The pose an action is done in: the pack's art says (`PackSkin.pose_for`); else asleep for
## a slow action, working for one at furniture or one that cleans or picks something up,
## standing idle otherwise.
func _pick_pose(w: World) -> String:
	var cur := person.current
	if cur.is_empty():
		return ""
	var aid := str(cur.get("action", ""))
	var o := w.object(int(cur.get("object_uid", -1))) if int(cur.get("object_uid", -1)) >= 0 else {}
	var otype := str(o.get("type", ""))
	var skin := _skin()
	var named := skin.pose_for(aid, otype) if skin != null else ""
	if named in CutoutRig.POSES:
		return named
	var a: Dictionary = w.pack.actions.get(aid, {})
	if bool(a.get("slow", false)):
		return "sleep"
	if otype != "" or str(a.get("cleans", "")) != "" or bool(a.get("picks", false)):
		return "work"
	return "idle"


## The pose the body is drawn in: "wave" while thanking, "walk" on the way, else what the
## current action asks for (`action_pose`), "idle" with nothing to do.
func body_pose() -> String:
	match pose():
		"thanks":
			return "wave"
		"walking":
			return "walk"
		"idle":
			return "idle"
	return action_pose if action_pose != "" else "idle"


## The rig's pose, bent forward by the look's `lean` (an old back): the torso tips forward,
## the legs tip back by as much so they still stand straight.
func _rig_pose(rig: CutoutRig, name: String) -> Dictionary:
	# Walking keeps step with the ground: the cycle follows the distance covered.
	var p := rig.pose(name, _stride_t if name == "walk" else _t)
	var lean: float = _look.get("lean", 0.0)
	if lean != 0.0 and name != "sleep" and rig.facing == "side":
		p["torso"] = p.get("torso", Vector3.ZERO) + Vector3(lean, 0, 0)
		p["head"] = p.get("head", Vector3.ZERO) - Vector3(lean * 0.6, 0, 0)
		for leg in ["leg_upper", "leg_back_upper"]:
			p[leg] = p.get(leg, Vector3.ZERO) - Vector3(lean, 0, 0)
	return p


## How tall the figure stands as drawn now (lower sitting, flat lying).
func drawn_height() -> float:
	var h := body_size().y
	match body_pose():
		"sleep":
			return h if bool(_look.get("lying", false)) else 26.0
		"sit":
			var rig: CutoutRig = _look.get("rig")
			return h * (1.0 - rig.thigh * 0.97 / rig.height) if rig != null and rig.thigh > 0.0 else h * SIT_SQUASH
	return h


## Where the middle of a lying body goes, relative to the feet: on the furniture they lie on
## (its middle), else just above the ground.
func lie_point() -> Vector2:
	if on_object and not use_object.is_empty() and layout() != null and session.world != null:
		var r := layout().object_rect(use_object, session.world.pack)
		var d := Vector2(0, r.get_center().y - 4.0 - position.y)
		if _house() != null and _house().iso:
			# On top of the piece: its middle, raised to its top.
			return IsoMath.basis().basis_xform(r.get_center() - position) + Vector2(0, -38)
		return d
	return Vector2(0, -12)


## The size of the label block over the head (pictured people; the house draws it on a layer
## above everything): the name plate, plus the thought bubble or thank-you over it. A person
## not selected shows only their name on a small plate; the selected one also shows what
## they are doing and how far along.
func label_size() -> Vector2:
	var font := ThemeDB.fallback_font
	var pw := 0.0
	var ph := 0.0
	if selected:
		pw = maxf(font.get_string_size(_doing, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 18.0
		pw = clampf(pw, 60.0, 170.0)
		ph = 32.0
	else:
		pw = clampf(font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0, 36.0, 120.0)
		ph = 18.0
	var extra := 0.0
	var bw := 0.0
	if thanking():
		extra = 20.0
		bw = thanks_width()
	elif _wish != "":
		extra = 30.0
		bw = font.get_string_size(_wish, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	return Vector2(maxf(pw, bw), ph + extra)


## Where the label block's bottom middle sits by default, relative to the feet.
func label_anchor() -> Vector2:
	var top := -drawn_height() + step_lift()
	if body_pose() == "sleep":
		top += lie_point().y + 6.0
	return Vector2(0, top - (14.0 if selected else 3.0))


## Draws the label block on `ci` with its bottom middle at `at` (the canvas's coordinates).
func draw_label(ci: CanvasItem, at: Vector2) -> void:
	var skin := _skin()
	var accent := skin.accent if skin != null else Color("#E5533C")
	var line := Color("#4A3424")
	var font := ThemeDB.fallback_font
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("#FFF4DF", 0.94)
	plate.border_color = accent if selected else Color(line, 0.55)
	plate.set_border_width_all(2 if selected else 1)
	plate.set_corner_radius_all(9 if selected else 7)
	var rect: Rect2
	if selected:
		var pw := clampf(maxf(font.get_string_size(_doing, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 18.0, 60.0, 170.0)
		rect = Rect2(at + Vector2(-pw * 0.5, -32), Vector2(pw, 32))
		ci.draw_style_box(plate, rect)
		ci.draw_string(font, Vector2(rect.position.x, at.y - 18), _name, HORIZONTAL_ALIGNMENT_CENTER, pw, 13, line)
		ci.draw_string(font, Vector2(rect.position.x + 4, at.y - 5), _doing, HORIZONTAL_ALIGNMENT_CENTER, pw - 8, 11, line.lightened(0.15))
		var prog := progress()
		if prog >= 0.0:
			ci.draw_rect(Rect2(rect.position.x + 6, at.y - 3, (pw - 12) * prog, 3), accent)
	else:
		var nw := clampf(font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0, 36.0, 120.0)
		rect = Rect2(at + Vector2(-nw * 0.5, -18), Vector2(nw, 18))
		ci.draw_style_box(plate, rect)
		ci.draw_string(font, Vector2(rect.position.x, at.y - 5), _name, HORIZONTAL_ALIGNMENT_CENTER, nw, 12, line)
	var y := rect.position.y
	if thanking():
		var tw := thanks_width()
		ci.draw_string_outline(font, Vector2(at.x - tw * 0.5, y - 4), thanks_words(), HORIZONTAL_ALIGNMENT_CENTER, tw, 14, 3, Color.WHITE)
		ci.draw_string(font, Vector2(at.x - tw * 0.5, y - 4), thanks_words(), HORIZONTAL_ALIGNMENT_CENTER, tw, 14, accent)
	elif _wish != "":
		_draw_bubble_at(ci, Vector2(at.x, y - 6))


func _draw_bubble_at(ci: CanvasItem, at: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(_wish, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	var rect := Rect2(Vector2(at.x - w * 0.5, at.y - 22), Vector2(w, 22))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.95)
	box.border_color = Color(0.55, 0.5, 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	ci.draw_style_box(box, rect)
	ci.draw_circle(at + Vector2(-6, 4), 3.0, Color(1, 1, 1, 0.95))
	ci.draw_string(font, rect.position + Vector2(0, 16), _wish, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.2, 0.15, 0.1))
