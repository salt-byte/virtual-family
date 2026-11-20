class_name PetView
extends Node2D
## One animal of the household as a small coloured shape with a name plate (whitebox until
## the art pass). It goes to whatever it is doing: the object its action happens at, a cell
## of the room it names, after the person it follows, or beside whoever is looking after it.
## Reads the World, never writes it.
##
## It never stands like a cut-out. An action's `trot` sends it from spot to spot of its rooms
## for as long as the action lasts (with `pace` "slink" along the walls and into the
## corners); `pace` also sets the gait (trot: a bounce, slink: low and slow, dash: quick
## bounds) and, in place, "leap" (up onto the thing and down again), "hop" and "flap". While
## it stays put it breathes, does its kind's `idle` (wag: the tail end swings; flick: a flick
## and an ear twitch now and then; bob: the head bobs; peck: a quick dip to the ground now and
## then; root: the snout shoves at the ground) and shuffles a step now and then; `pace` "peck"
## and "root" do those dips over and over while it is at it (a hen pecking her way along, a
## pig rooting). Resting (`rest`) it lies flatter, breathes slow and turns over or stretches
## every so often; a kind with a lying picture (the skin's `rest`) shows that instead.
## All of it is a transform of its pictures (`pose_xform`): no frames needed.

const SPEED := 120.0
## The spot it took beside the piece of furniture `_beside_for` (uid; -1 none).
var _beside_for := -1
var _beside := Vector2.ZERO
## How far behind the person it follows an animal keeps (plan pixels).
const FOLLOW_GAP := 60.0
## A grown-up's block is 28 x 44; an animal is a low wide shape scaled by its kind's `size`.
const BODY := Vector2(44, 30)
const ARRIVED := 1.0
const BOB_AMPLITUDE := 2.5
const BOB_PERIOD := 0.4
const THANKS_HOP := 6.0
const THANKS_PERIOD := 0.35
const FALLBACK := Color(0.7, 0.6, 0.45)
## Walking speed by `pace`.
const PACE_SPEED := {"": 1.0, "trot": 1.35, "slink": 0.55, "dash": 1.9, "leap": 1.2, "hop": 0.6, "flap": 0.8,
	"peck": 0.6, "root": 0.5}
## Seconds a trot waits at each spot (from, to).
const DWELL := Vector2(0.6, 2.2)
## Seconds between small shuffles while it stays put (from, to), and how far (plan pixels).
const SHUFFLE_EVERY := Vector2(4.0, 9.0)
const SHUFFLE_REACH := 10.0
## Seconds between turning over or stretching while resting (from, to), and how long one takes.
const TURN_EVERY := Vector2(14.0, 26.0)
const TURN_TIME := 0.8
## How high a leap goes (screen pixels) and one round of it (seconds).
const LEAP_HIGH := 22.0
const LEAP_ROUND := 2.6

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
## The pet action under way ({} when none), its `remaining_s` last frame (a rise means it
## began again), and the kind's `idle`.
var _act: Dictionary = {}
var _last_rem := 0
var _idle := ""
## A trot's spots, the one it heads for, and how long it still waits there.
var _spots := PackedVector2Array()
var _spot := 0
var _dwell := 0.0
## A small step aside from where it is (shuffles), and when the next comes.
var _nudge := Vector2.ZERO
var _shuffle_in := 0.0
## Resting: when it next turns over or stretches, how far into it (-1: not now), how many.
var _turn_in := 0.0
var _turn_t := -1.0
var _turns := 0
## Its own phase, so two pets never move in step.
var _phase := 0.0
## The pose of this frame: offset (screen pixels), tilt (radians, before the facing flip) and
## scale (before the flip); see `pose_xform`.
var _off := Vector2.ZERO
var _rot := 0.0
var _scale := Vector2.ONE


func setup(p: Pet, s: GameSession) -> void:
	pet = p
	session = s
	_rng.randomize()
	_phase = _rng.randf() * 10.0
	_shuffle_in = _rng.randf_range(SHUFFLE_EVERY.x, SHUFFLE_EVERY.y)
	_turn_in = _rng.randf_range(TURN_EVERY.x, TURN_EVERY.y)
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


## The drawn body size (lying down while it rests, with a lying picture).
func body() -> Vector2:
	if not _look.is_empty():
		var tex: Texture2D = _look.tex
		var h: float = _look.height
		if lying():
			tex = _look.rest
			h = _look.rest_height
		return Vector2(h * tex.get_width() / tex.get_height(), h)
	return BODY * _size


## True while it rests and its kind has a lying (or sitting) picture to show for it.
func lying() -> bool:
	return _look.has("rest") and resting() and pet != null and position.distance_to(target) <= ARRIVED


func refresh() -> void:
	var w := session.world
	if w == null or pet == null:
		return
	var k := PetSystem.kind_of(w.pack, pet)
	_color = HouseView.pack_color(k, FALLBACK)
	_size = float(k.get("size", 0.6))
	_idle = str(k.get("idle", ""))
	var hv = _house()
	var skin: PackSkin = hv.skin if hv != null and "skin" in hv else null
	_look = skin.pet_look(str(pet.kind)) if skin != null and skin.enabled else {}
	_name = session.strings.pet_name(pet, w)
	_doing = session.strings.pet_doing(pet, w)
	_wish = session.strings.pet_wish_text(pet, w)
	_act = PetSystem.action(w.pack, str(pet.current.get("action", ""))) if not pet.current.is_empty() else {}
	var rem := int(pet.current.get("remaining_s", 0))
	if rem > _last_rem:
		_key = ""  # the same action begun again: new spots
	_last_rem = rem
	var l := layout()
	if l != null:
		var before := base_target
		base_target = _compute_target(w, l)
		if base_target.distance_to(before) > SHUFFLE_REACH * 3.0:
			_nudge = Vector2.ZERO  # somewhere new: the old step aside means nothing there
		target = base_target + _nudge
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


## The action's `pace` ("" for none); a follower trots.
func pace_of() -> String:
	var p := str(_act.get("pace", ""))
	if p == "" and pet != null and pet.current.has("follow"):
		return "trot"
	return p


## True while its action is a rest (`rest`): lying down, turning over now and then.
func resting() -> bool:
	return bool(_act.get("rest", false))


## The spots of the trot under way (empty when it is not trotting).
func spots() -> PackedVector2Array:
	return _spots


func tick(delta: float) -> void:
	_t += delta
	if _float != "":
		_float_age += delta
		if _float_age > 1.2:
			_float = ""
	_step_spots(delta)
	_step_shuffle(delta)
	var was := position
	var hv := _house()
	if hv == null or not hv.iso or not hv.give_way(self, delta):
		walk(SPEED * float(PACE_SPEED.get(pace_of(), 1.0)) * delta)
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
	_step_rest(delta)
	_pose_now()
	queue_redraw()


## A trot goes on to its next spot once it has waited at this one; spots used up before the
## action is, it picks a fresh one in the same rooms.
func _step_spots(delta: float) -> void:
	if _spots.is_empty() or position.distance_to(target) > ARRIVED:
		return
	_dwell -= delta
	if _dwell > 0.0:
		return
	_spot += 1
	if _spot >= _spots.size():
		var l := layout()
		var more := _spot_cells(session.world, l, 1, pace_of() == "slink") if l != null else PackedVector2Array()
		if more.is_empty():
			_spot = _spots.size() - 1
			return
		_spots.append(more[0])
	_dwell = _rng.randf_range(DWELL.x, DWELL.y)
	base_target = _spots[_spot]
	_nudge = Vector2.ZERO
	target = base_target


## Now and then, while it stays put (not resting, not trotting, not following), it takes a
## small step aside or just turns round.
func _step_shuffle(delta: float) -> void:
	if pet == null or not _spots.is_empty() or resting() or pet.current.is_empty() or pet.current.has("follow") \
			or thanking() or position.distance_to(target) > ARRIVED:
		return
	_shuffle_in -= delta
	if _shuffle_in > 0.0:
		return
	_shuffle_in = _rng.randf_range(SHUFFLE_EVERY.x, SHUFFLE_EVERY.y)
	if _rng.randf() < 0.35:
		_facing = -_facing
		return
	var reach := SHUFFLE_REACH * (0.5 if pace_of() in ["hop", "flap", "leap"] else 1.0)
	_nudge = Vector2(_rng.randf_range(-reach, reach), _rng.randf_range(-reach * 0.6, reach * 0.6))
	target = base_target + _nudge


## Resting, it turns over (a squash and a flip) or stretches out every so often.
func _step_rest(delta: float) -> void:
	if _turn_t >= 0.0:
		var was := _turn_t
		_turn_t += delta
		if _turns % 2 == 1 and was < TURN_TIME * 0.5 and _turn_t >= TURN_TIME * 0.5:
			_facing = -_facing
		if _turn_t >= TURN_TIME:
			_turn_t = -1.0
		return
	if not resting() or position.distance_to(target) > ARRIVED:
		return
	_turn_in -= delta
	if _turn_in <= 0.0:
		_turn_in = _rng.randf_range(TURN_EVERY.x, TURN_EVERY.y)
		_turn_t = 0.0
		_turns += 1


## How many times it has turned over or stretched while resting.
func turns() -> int:
	return _turns


## Works out this frame's pose (see `_off`, `_rot`, `_scale`).
func _pose_now() -> void:
	var t := _t + _phase
	_off = Vector2.ZERO
	_rot = 0.0
	_scale = Vector2.ONE
	if pet == null:
		return
	var g := pose()
	if g == "thanks":
		_off.y = -absf(THANKS_HOP * sin(TAU * t / THANKS_PERIOD))
		return
	var pace := pace_of()
	if g == "walking":
		var period: float = {"trot": 0.32, "slink": 0.7, "dash": 0.24, "peck": 0.2, "root": 0.42}.get(pace, BOB_PERIOD)
		var high: float = {"trot": 4.0, "slink": 0.8, "dash": 5.0, "peck": 1.5, "root": 1.6}.get(pace, BOB_AMPLITUDE)
		var s := absf(sin(TAU * t / period))
		_off.y = -high * s
		# Squashed as it lands, stretched at the top; rocking with the step.
		_scale = Vector2(1.0 + 0.05 * (1.0 - s), 0.94 + 0.09 * s)
		if pace == "slink":
			_scale *= Vector2(1.06, 0.88)  # low to the ground
		else:
			_rot = 0.05 * sin(TAU * t / period)
		return
	if lying():
		# Its lying picture: a slow deep breath, a shift now and then.
		_scale = Vector2(1.0, 1.0 + 0.03 * sin(TAU * t / 3.2))
		if _turn_t >= 0.0:
			var k := sin(PI * _turn_t / TURN_TIME)
			_scale *= Vector2(1.0 + 0.06 * k, 1.0 - 0.05 * k)
		return
	if resting():
		# Lying flatter, a slow deep breath; turning over or stretching now and then.
		_scale = Vector2(1.06, 0.9 + 0.035 * sin(TAU * t / 3.2))
		if _turn_t >= 0.0:
			var k := sin(PI * _turn_t / TURN_TIME)
			if _turns % 2 == 1:
				_scale.y *= 1.0 - 0.3 * k
				_off.y = -3.0 * k
			else:
				_scale *= Vector2(1.0 + 0.18 * k, 1.0 - 0.08 * k)
				_rot = -0.06 * k
		return
	# Awake in one place: breathing, and what its kind does with its body.
	_scale.y = 1.0 + 0.025 * sin(TAU * t / 1.8)
	match pace:
		"leap":
			# Up onto the thing, a moment there, down again.
			var c := fmod(t, LEAP_ROUND)
			if c < 0.45:
				_off.y = -LEAP_HIGH * sin(0.5 * PI * c / 0.45)
			elif c < 1.6:
				_off.y = -LEAP_HIGH
			elif c < 2.0:
				_off.y = -LEAP_HIGH * cos(0.5 * PI * (c - 1.6) / 0.4)
			if c < 0.1 or (c > 2.0 and c < 2.12):
				_scale = Vector2(1.08, 0.86)  # a crouch before the spring, a give on landing
		"hop":
			var c := fmod(t, 0.9)
			if c < 0.35:
				_off.y = -6.0 * sin(PI * c / 0.35)
			elif c > 0.82:
				_scale = Vector2(1.06, 0.9)
		"flap":
			_off.y = -3.0 - 2.0 * absf(sin(TAU * t / 0.5))
			_scale.x = 1.0 + 0.09 * sin(TAU * t / 0.1)
			_rot = 0.05 * sin(TAU * t / 0.23)
		"peck":
			_peck(t, 0.55, 1.0)
		"root":
			_root(t, 1.0)
	match _idle:
		"wag":
			# The tail end swings in bursts: a quick sway about the feet.
			var burst := clampf(sin(TAU * t / 3.0) * 2.0 + 0.6, 0.0, 1.0)
			_rot += 0.04 * burst * sin(TAU * t / 0.26)
			_scale.x *= 1.0 + 0.012 * burst * sin(TAU * t / 0.13)
		"flick":
			var c := fmod(t, 4.3)
			if c < 0.25:
				_rot += 0.07 * sin(PI * c / 0.25)  # the tail flicks
			if fmod(t + 1.7, 5.9) < 0.12:
				_scale.y *= 0.96  # an ear twitches
		"bob":
			var c := fmod(t, 0.8)
			if c < 0.18:
				_off.y -= 2.0 * sin(PI * c / 0.18)
				_rot += 0.08 * sin(PI * c / 0.18)
		"peck":
			if pace != "peck":
				_peck(t, 3.1, 0.7)  # a dip at the ground now and then
		"root":
			if pace != "root":
				_root(fmod(t, 5.3) if fmod(t, 5.3) < 1.6 else 0.0, 0.6)


## A peck every `every` seconds: the body tips forward fast, a tap, and back (`k` how deep).
func _peck(t: float, every: float, k: float) -> void:
	var c := fmod(t, every)
	if c < 0.22:
		var d := sin(PI * c / 0.22)
		_rot += 0.32 * k * d
		_off.y += 1.5 * k * d
		_scale.y *= 1.0 - 0.05 * k * d


## Rooting: the snout shoves forward and up in a slow rhythm, the body leaning into it.
func _root(t: float, k: float) -> void:
	var s := sin(TAU * t / 1.6)
	_rot += k * (0.09 + 0.07 * s)
	_scale.x *= 1.0 + 0.03 * k * maxf(s, 0.0)
	_off.y += k * 1.2 * maxf(-s, 0.0)


## This frame's pose as a transform about its feet, facing included (what `_draw` uses).
func pose_xform() -> Transform2D:
	return Transform2D(_rot * _facing, Vector2(_facing * _scale.x, _scale.y), 0.0, _off)


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
			_spots = PackedVector2Array()
			return position
	var cur := pet.current
	if cur.has("follow") and hv != null and "people" in hv and hv.people.has(int(cur["follow"])):
		_key = ""
		_spots = PackedVector2Array()
		# A step behind them (to the west), not at their heels.
		var lead := (hv.people[int(cur["follow"])] as PersonView).position
		return lead + Vector2(-FOLLOW_GAP, 4) if not l.site.enabled else l.stop_point(lead + Vector2(-FOLLOW_GAP, 4), {l.site.cell_of(lead): true})
	if cur.has("object_uid"):
		var o := w.object(int(cur["object_uid"]))
		if not o.is_empty():
			_key = ""
			_spots = PackedVector2Array()
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
			if _beside_for == int(o.uid) and not taken.has(l.site.cell_of(_beside)):
				return _beside
			_beside_for = int(o.uid)
			_beside = l.stand_pos(o, w.pack, taken)
			return _beside
	if cur.has("mess"):
		var m := MessSystem.find(w, int(cur["mess"]))
		if not m.is_empty():
			_key = ""
			_spots = PackedVector2Array()
			return l.cell_center(str(m.room), int(m.x), int(m.y)) + Vector2(14, 0)
	var room := str(cur.get("room", ""))
	var key := "%s|%s" % [cur.get("action", ""), room]
	if key == _key:
		return base_target
	_key = key
	_spots = PackedVector2Array()
	var n := int(_act.get("trot", 0))
	if n > 0 and room != "":
		_spots = _spot_cells(w, l, n, pace_of() == "slink", room)
		if not _spots.is_empty():
			_spot = 0
			_dwell = _rng.randf_range(DWELL.x, DWELL.y)
			_nudge = Vector2.ZERO
			return _spots[0]
	if room != "" and w.pack.rooms.has(room) and l.room_rect(room).size != Vector2.ZERO:
		var r: Dictionary = w.pack.rooms[room]
		return _free_spot(l, l.cell_center(room, _rng.randi_range(0, int(r.w) - 1), _rng.randi_range(0, int(r.h) - 1)))
	if cur.is_empty() and base_target != Vector2.ZERO:
		return base_target
	return _home_cell(w, l)


## `n` spots for a trot: cells of the action's built rooms, the first in `first` when given
## and most of the rest there too; with `edges`, on the walls and in the corners only.
func _spot_cells(w: World, l: HouseLayout, n: int, edges: bool, first := "") -> PackedVector2Array:
	var out := PackedVector2Array()
	var rooms: Array = (_act.get("rooms", []) as Array).filter(func(r): return w.rooms_built.has(r) \
			and l.room_rect(str(r)).size != Vector2.ZERO)
	if rooms.is_empty():
		return out
	if first == "" or not rooms.has(first):
		first = str(rooms[_rng.randi_range(0, rooms.size() - 1)]) if _spots.is_empty() else ""
	for i in n:
		var room := first
		if room == "" or (i > 0 and _rng.randf() < 0.4):
			room = str(rooms[_rng.randi_range(0, rooms.size() - 1)])
		var rd: Dictionary = w.pack.rooms[room]
		var cw := int(rd.w)
		var ch := int(rd.h)
		var x := _rng.randi_range(0, cw - 1)
		var y := _rng.randi_range(0, ch - 1)
		if edges:
			if _rng.randf() < 0.5:
				x = 0 if _rng.randf() < 0.5 else cw - 1
			else:
				y = 0 if _rng.randf() < 0.5 else ch - 1
		# Off furniture and wall lines, and off where people stand.
		out.append(_free_spot(l, l.cell_center(room, x, y)))
	return out


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


## How far it is lifted this frame (a hop, a leap, a bounce); 0 standing still.
func bob_offset() -> float:
	return _off.y


func _draw() -> void:
	if pet == null:
		return
	var b := body()
	var bob := bob_offset()
	var r := Rect2(Vector2(-b.x * 0.5, -b.y + bob), b)
	# The shadow stays on the ground and shrinks while it is up in the air.
	var lift := clampf(-bob / (LEAP_HIGH + 2.0), 0.0, 0.6)
	var sw := b.x * _scale.x * (1.0 - lift)
	draw_colored_polygon(HouseGround._ellipse(Rect2(Vector2(-sw * 0.5, -5), Vector2(sw, 8))), Color(HouseGround.SHADOW, 0.3 * (1.0 - lift)))
	if not _look.is_empty():
		_draw_pictured(b, bob)
		return
	var box := StyleBoxFlat.new()
	box.bg_color = _color.darkened(0.25) if pet.sick else _color
	box.set_corner_radius_all(int(minf(b.x, b.y) * 0.45))
	draw_set_transform_matrix(pose_xform())
	draw_style_box(box, Rect2(Vector2(-b.x * 0.5, -b.y), b))
	# A head at the front, so the shape reads as an animal and not a crate.
	draw_circle(Vector2(b.x * 0.42, -b.y * 0.85), b.y * 0.36, box.bg_color.darkened(0.1))
	draw_circle(Vector2(b.x * 0.5, -b.y * 0.9), 1.8, Color(0.08, 0.08, 0.08))
	draw_set_transform(Vector2.ZERO)
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


## The pack's picture in this frame's pose (`pose_xform`: mirrored when heading left, the
## gait, the breath and the idle moves); a small cream plate with its name (and what it does
## when selected).
func _draw_pictured(b: Vector2, bob: float) -> void:
	var tint := Color(0.85, 0.85, 0.8) if pet.sick else Color.WHITE
	var xf := pose_xform()
	xf.origin += Vector2(0, 2.0)
	draw_set_transform_matrix(xf)
	var pic: Texture2D = _look.get(turned, _look.tex) if turned != "side" else _look.tex
	if lying():
		pic = _look.rest  # body() is already its size
	var pb := b
	if pic != _look.tex and not lying():
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
