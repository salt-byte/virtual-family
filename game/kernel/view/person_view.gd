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
## Lying on a bed (the house's `_spread`): the bed's uid, this sleeper's place on it (a slot,
## kept while they lie there), their rank among those lying on it and how many there are.
var bed_uid := -1
var bed_slot := -1
var bed_rank := 0
var bed_n := 1
## Lying down (0: up .. 1: lying): goes up over LIE_TIME once they reach the bed (sitting on
## its edge first, then lying back), down again as they get up (they wait for it).
var _lie := 0.0
## Where they lay (`lie_geo`), kept for getting up after the bed spot is gone.
var _lie_geo: Dictionary = {}
## The place across the bed (0..1 of its width) and the share of it, eased so a sleeper
## moves over instead of jumping when someone joins or leaves.
var _slot_f := -1.0
var _slot_n := 1.0
## Turning over in their sleep now and then: when the next turn comes, when the last one
## began, which way the head lies (1 / -1) and whether this turn has flipped it yet.
var _turn_next := -1.0
var _turn_from := -100.0
var _head_flip := 1.0
var _turn_flipped := true
var _dream := RandomNumberGenerator.new()
const LIE_TIME := 0.55
const SLEEP_BREATH := 3.8
const TURN_TIME := 1.2
const Z_PERIOD := 3.0
var _path_goal := Vector2(INF, INF)
## Giving way (`HouseView.give_way`): how long they have waited for someone in the way, and
## the cell of the one they last went round.
var waited := 0.0
var walked_round := Vector2i(-9999, -9999)
## The leg of the walk last checked for walls (`walk`).
var _leg_checked := Vector2(INF, INF)
var round_age := 99.0
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
## Tests set this (>= 0) to make every view's dice repeatable from the first frame: each view
## seeds from it and its person's uid. -1 (the game): fresh dice per view.
static var test_seed := -1
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
## The thought bubble over the head (`NeedBubble.of`: an ask, else a wish; {} for none) and
## its words ("" for none).
var _bubble: Dictionary = {}
var _wish := ""
## With the pack's art: {tex, height} of this person's picture ({}: drawn as a block), which
## way they face (1 right, -1 left; the pictures face right) and whether they look unwell.
var _look: Dictionary = {}
var _facing := 1.0
## The 45° view: which way the body is turned, for picking a rig (see `_turn`): "front34",
## "back34", or "back" / "side" for a look without the three-quarter rigs.
var turned := "front34"
## The 45° view: the way they would turn to, and for how long it has held (a turn waits
## TURN_HOLD, so a corner of the path does not flick the body round and back).
var _turn_want := "front34"
var _turn_held := 0.0
const TURN_HOLD := 0.12
## Carrying something to its place (`CarrySystem`), beat by beat: walk to where it lay
## (only when the screen is behind the sim: `_fetch`), stoop and pick it up (`_stoop_left`),
## walk with it held in both hands, stoop and put it in (`stow`, while the leg lasts, or
## `_stow_left` when the sim got there first). `_held` is its picture while in hand.
var _carry_key := ""
var _held: Texture2D
var _fetch := Vector2(INF, INF)
var _fetch_item := Vector2(INF, INF)
var _carry_dest := Vector2(INF, INF)
var _stoop_left := 0.0
var _stow_left := 0.0
## Walking eases in over WALK_EASE_IN seconds and slows over the last ARRIVE_EASE pixels.
var _walk_ramp := 0.0
const WALK_EASE_IN := 0.3
const ARRIVE_EASE := 30.0
const STOOP_TIME := 0.7
const STOW_TIME := 0.9
const HELD_SIZE := Vector2(30, 28)
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
	if test_seed >= 0:
		_rng.seed = hash([test_seed, p.uid])
	else:
		_rng.randomize()
	_dream.seed = hash(["dream", p.uid])
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
		if action_pose in ["sit", "doze"] and not on_object:
			# No seat under them: sitting on air reads as broken legs; they stand to do it.
			action_pose = "idle"
		# On a seat or a bed the spot is on the piece itself (see `on_spot`).
		base_target = want if on_object else l.stop_point(want)
		target = base_target
		_refresh_carry(w, l)
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
	_bubble = NeedBubble.of(w, person)
	_wish = str(_bubble.get("text", ""))
	var skin := _skin()
	_look = {}
	_unwell = false
	if skin != null and skin.enabled:
		_look = skin.person_look(person.stage(w.pack), person.gender, ViewLooks.of(person, w.pack))
		var u := skin.unwell()
		if not u.is_empty() and person.needs.has(u.need):
			_unwell = float(person.needs[u.need]) < float(u.below)
	queue_redraw()


## Keeps the carrying beats (see `_carry_key`) in step with the sim: a new carry leg (picked
## up out of sight of the screen: they first fetch it); the sim done before they got there
## (they still walk it over and put it in, then go on with whatever comes next).
func _refresh_carry(w: World, l: HouseLayout) -> void:
	var carry: Dictionary = person.current.get("carry", {})
	if not carry.is_empty():
		var key := "%d|%d" % [int(carry.get("uid", -1)), int(person.current.get("object_uid", -1))]
		var skin := _skin()
		_held = skin.carried_sprite(str(carry.kind), str(carry.type)) if skin != null else null
		_carry_dest = base_target
		if key != _carry_key:
			_carry_key = key
			var from := l.cell_center(str(carry.room), int(carry.x), int(carry.y))
			if position.distance_to(from) > HouseSite.CELL.x * 1.5:
				_fetch_item = from
				_fetch = l.stop_point(from)
	elif _carry_key != "":
		if _carry_dest.x != INF and (position.distance_to(_carry_dest) > ARRIVED or _fetch.x != INF) and _stow_left <= 0.0:
			# The sim has put it in already: the screen walks it over first.
			_carry_key = "done"
		elif _stow_left <= 0.0:
			_end_carry()
	if _carry_key == "":
		return
	if _carry_key == "done":
		target = _carry_dest
	if _fetch.x != INF:
		target = _fetch
	if _stoop_left > 0.0 or _stow_left > 0.0:
		target = position


func _end_carry() -> void:
	_carry_key = ""
	_held = null
	_fetch = Vector2(INF, INF)
	_fetch_item = Vector2(INF, INF)
	_carry_dest = Vector2(INF, INF)
	_stoop_left = 0.0
	_stow_left = 0.0


## True while they hold what they carry (not while still fetching it).
func holding() -> bool:
	return _held != null and _fetch.x == INF and _stoop_left <= 0.0


## Where the thing they are about to fetch still lies (plan point), INF when none.
func fetch_item() -> Vector2:
	return _fetch_item if _fetch.x != INF or _stoop_left > 0.0 else Vector2(INF, INF)


func held_picture() -> Texture2D:
	return _held


## Advances the carrying beats by `delta`: arriving to fetch, stooping, putting it in.
func _tick_carry(delta: float) -> void:
	if _carry_key == "":
		return
	if _fetch.x != INF and position.distance_to(_fetch) <= ARRIVED:
		_fetch = Vector2(INF, INF)
		_stoop_left = STOOP_TIME
	if _stoop_left > 0.0:
		_stoop_left -= delta
		if _stoop_left <= 0.0:
			_fetch_item = Vector2(INF, INF)
			target = _carry_dest if _carry_dest.x != INF else target
		return
	if _carry_key == "done":
		if _stow_left > 0.0:
			_stow_left -= delta
			if _stow_left <= 0.0:
				_end_carry()
				refresh()
		elif position.distance_to(_carry_dest) <= ARRIVED:
			_stow_left = STOW_TIME


## Draws what they carry between their two hands (the ends of the forearms).
func _draw_held(rig: CutoutRig, pose: Dictionary, xform: Transform2D) -> void:
	if _held == null:
		return
	var w := rig.world(pose)
	var sum := Vector2.ZERO
	var n := 0
	for id in ["arm_lower", "arm_back_lower"]:
		if not rig.has_part(id) or not w.has(id):
			continue
		var pt := rig.part(id)
		var size: Vector2 = pt.get("size", Vector2.ZERO)
		var pivot: Vector2 = pt.get("pivot", Vector2.ZERO)
		sum += xform * ((w[id] as Transform2D) * (Vector2(size.x * 0.5, size.y * 0.88) - pivot))
		n += 1
	if n == 0:
		return
	var at := sum / float(n)
	draw_texture_rect(_held, PackSkin.fit_rect(_held, at + Vector2(0, HELD_SIZE.y * 0.45), HELD_SIZE), false)


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
	return "busy" if not person.current.is_empty() or _carry_key != "" else "idle"


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
	elif bool(_bubble.get("waiting", false)):
		queue_redraw()  # the waiting ask's bubble bobs
	if _mark != null and not _mark.tick(delta):
		remove_child(_mark)
		_mark.queue_free()
		_mark = null
	_tick_lying(delta)
	_tick_carry(delta)
	if held:
		return
	var was := position
	var hv := _house()
	if _lie > 0.0 and not lying_down():
		pass  # getting up off the bed first
	elif hv == null or not hv.iso or not hv.give_way(self, delta):
		walk(SPEED * delta * pace() * _ease(delta))
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


## How fast they walk now, as a share of their pace: gathering speed over the first moments
## of a walk, slowing as they come up to where they are going (never quite stopping short).
func _ease(delta: float) -> float:
	var left := position.distance_to(target)
	if left <= ARRIVED:
		_walk_ramp = 0.0
		return 1.0
	_walk_ramp = minf(1.0, _walk_ramp + delta / WALK_EASE_IN)
	var start := 0.35 + 0.65 * smoothstep(0.0, 1.0, _walk_ramp)
	var stop := clampf(0.4 + 0.6 * left / ARRIVE_EASE, 0.4, 1.0)
	return start * stop


## The seat or bed they are on (its uid; -1 for none): while getting up, the bed they lay on.
func seat_uid() -> int:
	if on_object and not use_object.is_empty():
		return int(use_object.get("uid", -1))
	if _lie > 0.0 and not _lie_geo.is_empty():
		return int(_lie_geo.get("uid", -1))
	return -1


## Whether they lie (or are lying down) where they are now: lying in the 45° view, at their
## spot, not held. A swaddled baby's picture already lies, so it is not counted.
func lying_down() -> bool:
	return not held and _iso() and body_pose() == "sleep" and not bool(_look.get("lying", false)) \
		and pictured() and position.distance_to(target) <= ARRIVED


func _iso() -> bool:
	return _house() != null and _house().iso


## Lying down and getting up (`_lie`), easing the place across the bed, and turning over now
## and then in their sleep.
func _tick_lying(delta: float) -> void:
	if held:
		_lie = 0.0
		return
	var down := lying_down()
	if down or (_iso() and bool(_look.get("lying", false)) and body_pose() == "sleep"):
		var want := (float(bed_rank) + 0.5) / float(maxi(bed_n, 1))
		if _slot_f < 0.0 or (_lie <= 0.0 and down):
			_slot_f = want
			_slot_n = float(maxi(bed_n, 1))
		else:
			_slot_f = move_toward(_slot_f, want, delta * 0.8)
			_slot_n = move_toward(_slot_n, float(maxi(bed_n, 1)), delta * 2.0)
	if down:
		_lie = minf(1.0, _lie + delta / LIE_TIME)
		_lie_geo = lie_geo()
		queue_redraw()
		if _turn_next < 0.0:
			_turn_next = _t + _dream.randf_range(8.0, 20.0)
		elif _t >= _turn_next and _lie >= 1.0:
			_turn_from = _t
			_turn_flipped = false
			_turn_next = _t + _dream.randf_range(12.0, 26.0)
		if not _turn_flipped and _t - _turn_from >= TURN_TIME * 0.5:
			_head_flip = -_head_flip
			_turn_flipped = true
	elif _lie > 0.0:
		_lie = maxf(0.0, _lie - delta / LIE_TIME)
		queue_redraw()
		if _lie <= 0.0:
			_slot_f = -1.0
			_turn_next = -1.0


## How fast they walk, against a grown-up: old people slower.
func pace() -> float:
	if person == null or session == null or session.world == null:
		return 1.0
	var stages: Array = session.world.pack.cfg("stages")
	if stages.size() > 2 and person.stage(session.world.pack) == str(stages[-1]["id"]):
		return ELDER_PACE
	return 1.0


## Which way they face after moving by `d` (house coordinates): left or right on the screen
## (`_facing`: every rig faces right and is mirrored), and in the 45° view which rig the body
## is turned to: "back34" walking up the screen (turned away, three-quarters), "front34"
## otherwise: walking down or across it, and standing, working, sitting, eating (turned
## towards the camera, three-quarters, to the furniture they use). A look without the
## three-quarter rigs falls back to the back rig walking up the screen and the side rig
## otherwise. Nobody faces the camera head-on (the front rig is not used).
func _turn(d: Vector2, delta := 1.0) -> void:
	var iso := _house() != null and _house().iso
	var v := IsoMath.basis().basis_xform(d) if iso else d
	if absf(v.x) > 0.01:
		_facing = signf(v.x)
	if not iso:
		return
	var want := "front34"
	var len := v.length()
	if len > 0.01:
		if v.y <= -UP_SCREEN * len:
			want = "back34"
	else:
		# Standing at work: turned to what they work on (the piece, or the thing on the ground
		# they stoop for), their back to the camera when it is up the screen from them.
		var focus := _focus()
		if focus.x != INF:
			var dv := IsoMath.basis().basis_xform(focus - position)
			if absf(dv.x) > 1.0:
				_facing = signf(dv.x)
			if body_pose() in FACING_POSES and dv.y < -FACE_UP * dv.length():
				want = "back34"
	if not _look.has("rig_" + want):
		want = "back" if want == "back34" and _look.has("rig_back") else "side"
	if want != _turn_want:
		_turn_want = want
		_turn_held = 0.0
	_turn_held += delta
	if _turn_held >= TURN_HOLD:
		turned = want


## Poses in which they turn to what they work on (sitting, eating, sleeping and waving keep
## facing the camera), and how far up the screen it must be for them to turn their back.
const FACING_POSES := ["work", "stoop", "stow", "sweep", "stir", "scoop", "write", "read", "sew", "saw",
	"hoe", "push", "reach_up", "scatter", "bow"]
const FACE_UP := 0.3


## What they turn to while standing at work (plan point): the piece they use, else the thing
## they stoop for, else INF.
func _focus() -> Vector2:
	var l := layout()
	if l == null or session.world == null:
		return Vector2(INF, INF)
	if not use_object.is_empty():
		return l.object_rect(use_object, session.world.pack).get_center()
	if fetch_item().x != INF:
		return fetch_item()
	var tid := int(person.current.get("target_uid", -1)) if person != null else -1
	if tid >= 0:
		for list in [session.world.messes, session.world.collectibles]:
			for m in list:
				if int(m.uid) == tid:
					return l.cell_center(str(m.room), int(m.x), int(m.y))
	return Vector2(INF, INF)


## A walk counts as up the screen when it climbs this much of its length: a walk along
## either axis of the plan (27° on the screen) does; one across the screen does not.
const UP_SCREEN := 0.4


## The rig for the pose: the one the body is turned to (`turned`) when the look has it, the
## side rig otherwise and for lying down; a head-on back rig only walks. With its size factor
## (heads as big as the side rig's).
func _rig_for(bp: String) -> Array:
	var side: CutoutRig = _look.get("rig")
	if side == null or bp == "sleep" or turned == "side":
		return [side, 1.0]
	if turned == "back" and bp != "walk":
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
	# Every leg is checked once: one that would go through a closed wall (a way worked out
	# before the house changed, say) is worked out again; with no way at all they stand.
	var lay := layout()
	if lay != null and lay.site.enabled:
		var leg := path[0] if not path.is_empty() else target
		if leg != _leg_checked:
			_leg_checked = leg
			if lay.site.crosses_wall(position, leg):
				path = lay.site.route(position, target)
				leg = path[0] if not path.is_empty() else target
				_leg_checked = leg
				if lay.site.crosses_wall(position, leg):
					_leg_checked = Vector2(INF, INF)  # look again next frame
					_path_from = position
					return
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
	if _iso() and pictured() and (lying_down() or body_pose() == "sleep"):
		return lie_rect().grow(4.0).has_point(local)
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
				if action_pose in ["sit", "doze", "sleep"] and skin != null and skin.sat_on(str(o.type)):
					on_object = true
					return on_spot(l, o, w.pack, float(skin.seat(str(o.type)).in))
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
				# Beside them, a cell over (not in their body): the open cell east of where
				# they stand, else the nearest one.
				var them := (hv.people[tid] as PersonView).base_target
				if l.site.enabled:
					return l.stop_point(them + Vector2(HouseSite.CELL.x, 0), {l.site.cell_of(them): true})
				return them + Vector2(BODY.x, 0)
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
	if action_pose == "sleep" and room != "":
		# Asleep in a room with a bed (a baby in its swaddle): on the bed, beside whoever is.
		var bed := _bed_in(w, room)
		if not bed.is_empty():
			_key = ""
			use_object = bed
			on_object = true
			return on_spot(l, bed, w.pack, float(_skin().seat(str(bed.type)).in))
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


## A bed (`PackSkin.bed`) standing in `room`, in the 45° view; {} for none.
func _bed_in(w: World, room: String) -> Dictionary:
	var skin := _skin()
	if skin == null or not skin.iso():
		return {}
	for o in w.objects:
		if str(o.get("room", "")) == room and not skin.bed(str(o.type)).is_empty() and skin.sat_on(str(o.type)):
			return o
	return {}


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


## The thought bubble above the name plate (see `NeedBubble`).
func _draw_bubble() -> void:
	NeedBubble.draw(self, Vector2(0, -BODY.y - 44), _bubble, _t, _skin())


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
	var sit_up := seat_lift()
	var iso := _house() != null and _house().iso
	if thanking() and not held:
		lift = bob_offset()
	var line := Color("#4A3424")
	var lying := bp == "sleep" and not bool(_look.get("lying", false))
	# The 45° view: lying down, lying under the quilt, or getting up (see `_draw_bed`).
	var in_bed := iso and not bool(_look.get("lying", false)) and (lying_down() or _lie > 0.0)
	var swaddled := iso and bool(_look.get("lying", false)) and bp == "sleep" and position.distance_to(target) <= ARRIVED
	if iso and lying and not in_bed:
		# Held up off the bed: drawn standing.
		lying = false
		bp = "idle"
		picked = _rig_for(bp)
		rig = picked[0]
	if not lying and not in_bed and not swaddled:
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
	if in_bed:
		_draw_bed(tint)
	elif swaddled:
		_draw_swaddle(tint)
	elif lying:
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
			_rig_was.draw(self, _rig_pose(_rig_was, bp), Transform2D(0.0, Vector2(_facing * k0, k0), 0.0, Vector2(0, lift + 2.0 - sit_up)), tw)
		var k2 := h / rig.height * float(picked[1])
		var tn := Color(tint, tint.a * smoothstep(0.0, 1.0, _fade))
		var rx := Transform2D(0.0, Vector2(_facing * k2, k2), 0.0, Vector2(0, lift + 2.0 - sit_up))
		var rp := _rig_pose(rig, bp)
		var away := turned in ["back", "back34"]
		if holding() and away:
			_draw_held(rig, rp, rx)   # turned away: what they hold is in front of them, hidden
		rig.draw(self, rp, rx, tn)
		if holding() and not away:
			_draw_held(rig, rp, rx)
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
			"sit", "doze":
				sq = Vector2(1.04, SIT_SQUASH)
			"eat":
				sway = 0.05 * sin(TAU * _t / CutoutRig.EAT_PERIOD)
			"wave":
				sway = 0.06 * sin(TAU * _t / CutoutRig.WAVE_PERIOD)
			_:
				sq = Vector2(1.0, 1.0 + 0.012 * sin(TAU * _t / CutoutRig.BREATH_PERIOD))
		draw_set_transform(Vector2(0, lift + 2.0 - sit_up), sway, flip * sq)
		draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, tint)
		draw_set_transform(Vector2.ZERO)
	h = drawn_height()
	var top := -h + lift - sit_up
	if in_bed or swaddled:
		top = lie_rect().position.y + 6.0
	elif lying:
		top = lie_point().y - 14.0
	var font := ThemeDB.fallback_font
	if (in_bed and _lie >= 1.0) or swaddled:
		_draw_zs(1.0 if not swaddled else 0.7)
	elif bp == "doze" and iso:
		_draw_doze_z()
	elif lying and not in_bed:
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


## Where someone sitting or lying on furniture `o` has their feet: the middle of its width,
## `inset` cells in from its front edge (the seat's anchor, `PackSkin.seat`: a stool's middle,
## the kang's edge), and at least a little inside it (the piece sorts ON_LIFT higher, and the
## house draws whoever sits on a piece over it).
static func on_spot(l: HouseLayout, o: Dictionary, pack: Pack, inset := 0.0) -> Vector2:
	var r := l.object_rect(o, pack)
	return Vector2(r.get_center().x, r.end.y - maxf(4.0, inset * HouseSite.CELL.y))


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
	if bool(a.get("picks", false)):
		return "stoop"
	if otype != "" or str(a.get("cleans", "")) != "":
		return "work"
	return "idle"


## The pose the body is drawn in: "wave" while thanking, "walk" on the way, else what the
## current action asks for (`action_pose`), "idle" with nothing to do.
func body_pose() -> String:
	if _stoop_left > 0.0:
		return "stoop"
	if _stow_left > 0.0:
		return "stow"
	match pose():
		"thanks":
			return "wave"
		"walking":
			return "carry" if holding() else "walk"
		"idle":
			return "stow" if holding() else "idle"
	if holding():
		return "stow"
	return action_pose if action_pose != "" else "idle"


## The rig's pose, bent forward by the look's `lean` (an old back): the torso tips forward,
## the legs tip back by as much so they still stand straight.
func _rig_pose(rig: CutoutRig, name: String) -> Dictionary:
	# Walking keeps step with the ground: the cycle follows the distance covered.
	var p := rig.pose(name, _stride_t if name == "walk" else _t)
	var lean: float = _look.get("lean", 0.0)
	if lean != 0.0 and name != "sleep" and rig.facing in ["side", "front34", "back34"]:
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
		"sit", "doze":
			var rig: CutoutRig = _rig_for("sit")[0]
			return h * (1.0 - rig.thigh * 0.97 / rig.height) if rig != null and rig.thigh > 0.0 else h * SIT_SQUASH
	return h


## How far the body is drawn above the feet: someone sitting on a seat higher than their
## shins sits on its surface, legs hanging (the seat's height, `PackSkin.seat`, less the hips'
## own height when sitting); 0 standing, or on a seat the pack gives no height.
func seat_lift() -> float:
	if not on_object or use_object.is_empty() or not body_pose() in ["sit", "doze"] or position.distance_to(target) > ARRIVED:
		return 0.0
	var skin := _skin()
	if skin == null or not (_house() != null and _house().iso):
		return 0.0
	return maxf(0.0, skin.seat_height(str(use_object.get("type", ""))) - _hips())


## How high the hips are above the feet when sitting (seat lift included), view pixels.
func hip_height() -> float:
	return _hips() + seat_lift()


## The hips' own height above the feet in the sitting pose.
func _hips() -> float:
	var h := body_size().y
	var picked := _rig_for("sit")
	var rig: CutoutRig = picked[0]
	if rig == null or not rig.has_part("leg_upper"):
		return h * (1.0 - SIT_SQUASH) + h * 0.2
	var hip: Transform2D = rig.world(rig.pose("sit", 0.0))["leg_upper"]
	return -hip.origin.y * h / rig.height * float(picked[1])


## Where the middle of a lying body goes, relative to the feet: on the furniture they lie on
## (its middle), else just above the ground. In the 45° view, the middle of their place on
## the bed (`lie_geo`).
func lie_point() -> Vector2:
	if _iso() and pictured():
		var g := _geo()
		return _lie_screen(g.head + g.axis * (g.length - g.head_len) * 0.5, g)
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
		extra = NeedBubble.HEIGHT + 12.0
		bw = NeedBubble.size_of(_bubble).x
	return Vector2(maxf(pw, bw), ph + extra)


## Where the label block's bottom middle sits by default, relative to the feet.
func label_anchor() -> Vector2:
	var top := -drawn_height() + step_lift() - seat_lift()
	if _iso() and pictured() and (lying_down() or _lie > 0.0 or body_pose() == "sleep"):
		top = lie_rect().position.y + 2.0
	elif body_pose() == "sleep":
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
	NeedBubble.draw(ci, at + Vector2(0, -6), _bubble, _t, _skin())


# --- lying down (the 45° view) ---------------------------------------------------------

## Where and how they lie (plan pixels): {head: the middle of the quilt's head edge; axis:
## plan direction from the head to the feet, along the bed (`PackSkin.bed`: its `along`);
## across: the direction to its near side; length, width: the quilt's; head_len: room for
## the head past the quilt's edge; lift: the surface's height (view pixels); bed: whether on
## a bed (else on the floor, on a mat, round where they stand)}. Sleepers sharing a bed lie
## side by side across it (`bed_rank` of `bed_n`), each in their share of its width.
func lie_geo() -> Dictionary:
	var tall: float = float(_look.get("height", 90.0)) if pictured() else 90.0
	var swaddled := bool(_look.get("lying", false))
	var b := IsoMath.basis()
	var skin := _skin()
	var bed := {}
	var r := Rect2()
	if on_object and not use_object.is_empty() and skin != null and layout() != null and session.world != null:
		bed = skin.bed(str(use_object.get("type", "")))
		r = layout().object_rect(use_object, session.world.pack)
	var axis := Vector2(1, 0)
	if not bed.is_empty():
		var along := str(bed.along)
		if along == "long":
			along = "y" if r.size.y > r.size.x else "x"
		axis = Vector2(0, 1) if along == "y" else Vector2(1, 0)
	var across := Vector2(axis.y, axis.x)
	var sp_a := b.basis_xform(axis).length()
	var sp_c := b.basis_xform(across).length()
	var head_len := 0.0 if swaddled else tall * 0.22 / sp_a
	var length := tall * (SWADDLE_LEN if swaddled else 0.74) / sp_a
	var width := tall * 0.46 / sp_c
	var head := Vector2.ZERO
	var lift := 2.0
	if not bed.is_empty():
		lift = float(bed.h)
		var lo := r.position.dot(across) + float(bed.margin)
		var hi := r.end.dot(across) - float(bed.margin)
		var n := maxf(_slot_n, 1.0)
		var f := _slot_f if _slot_f >= 0.0 else (float(bed_rank) + 0.5) / float(maxi(bed_n, 1))
		width = minf(width, (hi - lo) / n * 1.35)
		var a0 := r.position.dot(axis) + float(bed.head) * HouseSite.CELL.dot(axis)
		if swaddled:
			a0 = maxf(r.position.dot(axis) + 4.0, a0 - tall * 0.3 / sp_a)
		length = minf(length, r.end.dot(axis) - BED_END - a0)
		head = axis * a0 + across * lerpf(lo, hi, f)
	else:
		head = position - axis * (length - head_len) * 0.5
		# On the floor: the mat kept inside the room they lie in.
		var l := layout()
		var room := l.site.room_at(l.site.cell_of(position)) if l != null and l.site.enabled else ""
		var rr := l.room_rect(room) if room != "" else Rect2()
		if rr.has_area():
			var m := MAT_EDGE
			var lo_a := rr.position.dot(axis) + m + head_len * 1.2
			var hi_a := rr.end.dot(axis) - m - length - 4.0
			var a := head.dot(axis)
			a = clampf(a, lo_a, maxf(lo_a, hi_a))
			var c := clampf(head.dot(across), rr.position.dot(across) + m + width * 0.66, rr.end.dot(across) - m - width * 0.66)
			head = axis * a + across * c
	return {"uid": int(use_object.get("uid", -1)) if not bed.is_empty() else -1, "head": head, "axis": axis, "across": across, "length": length, "width": width,
		"head_len": head_len, "lift": lift, "bed": not bed.is_empty()}


## A mat on the floor keeps this far (plan pixels) inside the room's walls.
const MAT_EDGE := 8.0
## How far short of a bed's foot end the quilt stops (plan pixels: the bed's rim).
const BED_END := 12.0
## A swaddled baby's picture is this many times its height long, lying.
const SWADDLE_LEN := 1.45


## `lie_geo` while lying; while getting up, where they lay.
func _geo() -> Dictionary:
	if not lying_down() and _lie > 0.0 and not _lie_geo.is_empty():
		return _lie_geo
	return lie_geo()


## A plan point of `g` on the view, relative to the feet (raised to the surface).
func _lie_screen(p: Vector2, g: Dictionary) -> Vector2:
	return IsoMath.basis().basis_xform(p - position) + Vector2(0, -float(g.lift))


## The lying body on the view, relative to the feet: the quilt, the pillow and the head.
func lie_rect() -> Rect2:
	var g := _geo()
	var tall: float = float(_look.get("height", 90.0)) if pictured() else 90.0
	var hw: float = g.width * 0.5
	var pts: Array[Vector2] = []
	for p in [g.head + g.across * hw, g.head - g.across * hw, g.head + g.axis * g.length + g.across * hw,
			g.head + g.axis * g.length - g.across * hw, g.head - g.axis * g.head_len]:
		pts.append(_lie_screen(p, g))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow_individual(2.0, tall * 0.16, 2.0, 2.0)


## Lying down or getting up: sitting on the bed's edge (on the floor: standing), then lying
## back under the quilt; the two cross over in the second part of LIE_TIME.
func _draw_bed(tint: Color) -> void:
	var g := _geo()
	var f := smoothstep(0.35, 1.0, _lie)
	if f < 1.0:
		_draw_on_edge(g, 1.0 - f, tint)
	if f > 0.0:
		_draw_under_quilt(g, f, tint)


## Sitting on the bed's edge where they got onto it (standing, on the floor), faded to `a`.
func _draw_on_edge(g: Dictionary, a: float, tint: Color) -> void:
	var bp := "sit" if bool(g.bed) else "idle"
	var picked := _rig_for(bp)
	var rig: CutoutRig = picked[0]
	var h: float = _look.height
	var col := Color(tint, tint.a * a)
	if rig == null:
		var tex: Texture2D = _look.tex
		var w := h * tex.get_width() / tex.get_height()
		draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, col)
		return
	var k := h / rig.height * float(picked[1])
	var up := maxf(0.0, float(g.lift) - _hips()) if bool(g.bed) else 0.0
	rig.draw(self, _rig_pose(rig, bp), Transform2D(0.0, Vector2(_facing * k, k), 0.0, Vector2(0, 2.0 - up)), col)


## Under the quilt: a mat on the floor (no bed), the pillow, their own head on it, and the
## quilt over the rest, rising as they breathe and heaving when they turn over.
func _draw_under_quilt(g: Dictionary, a: float, tint: Color) -> void:
	var skin := _skin()
	var q := skin.quilt() if skin != null else {}
	var breath := 0.5 + 0.5 * sin(TAU * _t / SLEEP_BREATH)
	var u := (_t - _turn_from) / TURN_TIME
	var roll := sin(PI * u) if u >= 0.0 and u <= 1.0 else 0.0
	var col := Color(tint, tint.a * a)
	var head: Vector2 = g.head
	var axis: Vector2 = g.axis
	var across: Vector2 = g.across
	var w: float = g.width
	if q.is_empty():
		# No quilt in the skin: the whole sleeping picture, along the bed.
		if _look.has("asleep"):
			var pic: Texture2D = _look.asleep
			var at := lie_point()
			var len := float(_look.height) * 1.15
			draw_texture_rect(pic, PackSkin.fit_rect(pic, at + Vector2(0, len * 0.3), Vector2(len, len)), false, col)
		return
	var line := Color(q.line, a)
	if not bool(g.bed):
		var m0: Vector2 = head - axis * (g.head_len * 1.2)
		var m1: Vector2 = head + axis * (g.length + 4.0)
		var mw := w * 0.66
		_quad(g, [m0 - across * mw, m1 - across * mw, m1 + across * mw, m0 + across * mw], Color(q.mat, a), line)
	var p0: Vector2 = head - axis * (g.head_len * 0.95)
	var p1: Vector2 = head + axis * (g.head_len * 0.2)
	var pw := w * 0.42
	var pillow := [p0 - across * pw, p1 - across * pw, p1 + across * pw, p0 + across * pw]
	_quad(g, pillow, Color((q.pillow as Color).darkened(0.28), a), Color(0, 0, 0, 0), Vector2(0, 3))
	_quad(g, pillow, Color(q.pillow, a), line)
	_draw_sleeping_head(g, col, breath, roll)
	_draw_quilt(g, q, col, breath, roll)


## A four-cornered patch of plan points on the view, filled and outlined.
func _quad(g: Dictionary, corners: Array, fill: Color, line: Color, shift := Vector2.ZERO) -> void:
	var pts := PackedVector2Array()
	for c in corners:
		pts.append(_lie_screen(c, g) + shift)
	draw_colored_polygon(pts, fill)
	if line.a > 0.0:
		pts.append(pts[0])
		draw_polyline(pts, line, 1.5)


## The rig whose head they sleep with: their own look's, turned away (else its side one);
## null without one.
func sleeping_head_rig() -> CutoutRig:
	var r: CutoutRig = _look.get("rig_back34", _look.get("rig"))
	return r if r != null and r.has_part("head") else null


## A sleeping head is drawn this much bigger than a standing one (it lies nearer the eye).
const HEAD_K := 1.12


## Their own head (the look's rig: turned away, else the side one) on the pillow, its top
## towards the head end, the face turned up the screen; turning over turns it the other way.
func _draw_sleeping_head(g: Dictionary, col: Color, breath: float, roll: float) -> void:
	var r: CutoutRig = sleeping_head_rig()
	if r == null:
		return
	var side: CutoutRig = _look.get("rig")
	var h: float = _look.height
	var part := r.part("head")
	var size: Vector2 = part.size
	var want := h * 0.25 * HEAD_K
	if side != null and side.head_height > 0.0:
		want = side.head_height / side.height * h * HEAD_K
	var k := want / maxf(1.0, size.y)
	var up := -IsoMath.basis().basis_xform(g.axis).normalized()
	var th := atan2(up.x, -up.y)
	var mx := -1.0 if sin(th) > 0.0 else 1.0
	mx *= _head_flip
	var neck := _lie_screen(g.head - g.axis * (float(g.head_len) * 0.06), g) + Vector2(0, -2.0 - 1.2 * breath - 2.0 * roll)
	draw_set_transform_matrix(Transform2D(th, Vector2(mx * k, k), 0.0, neck) * Transform2D(0.0, -(part.pivot as Vector2)))
	draw_texture(part.tex, Vector2.ZERO, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The quilt: the skin's picture cut to its outline (`PackSkin.quilt`), its three corners laid
## on this sleeper's place (so it lies along the bed, as wide as their share), breathing.
func _draw_quilt(g: Dictionary, q: Dictionary, col: Color, breath: float, roll: float) -> void:
	var tex: Texture2D = q.tex
	var c: Array = q.corners
	var q0: Vector2 = g.head + g.across * (float(g.width) * 0.5)
	var q1: Vector2 = g.head - g.across * (float(g.width) * 0.5)
	var q2: Vector2 = q0 + g.axis * float(g.length)
	var pic := Transform2D(c[1] - c[0], c[2] - c[0], Vector2.ZERO)
	var lin := Transform2D(q1 - q0, q2 - q0, Vector2.ZERO) * pic.affine_inverse()
	var to_plan := Transform2D(lin.x, lin.y, q0 - lin.basis_xform(c[0]))
	var b := IsoMath.basis()
	var to_view := Transform2D(b.x, b.y, -b.basis_xform(position) + Vector2(0, -float(g.lift)))
	# Breathing: the quilt rises a little from its lower edge; turning over, it heaves.
	var hgt := float(tex.get_height())
	var lump := Transform2D(0.0, Vector2(1.0, 1.0 + 0.035 * breath + 0.07 * roll), 0.0, Vector2(roll * 8.0, hgt)) * Transform2D(0.0, Vector2(0, -hgt))
	draw_set_transform_matrix(to_view * to_plan * lump)
	var cut: PackedVector2Array = q.cut
	var uvs := PackedVector2Array()
	var ts := Vector2(tex.get_size())
	for p in cut:
		uvs.append(p / ts)
	draw_polygon(cut, PackedColorArray([col]), uvs, tex)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A swaddled baby asleep: its own lying picture along the bed (or a mat on the floor),
## breathing.
func _draw_swaddle(tint: Color) -> void:
	var g := lie_geo()
	var skin := _skin()
	var q := skin.quilt() if skin != null else {}
	var tex: Texture2D = _look.tex
	var h: float = _look.height
	if not bool(g.bed) and not q.is_empty():
		var m0: Vector2 = g.head - g.axis * 4.0
		var m1: Vector2 = g.head + g.axis * (float(g.length) + 4.0)
		var mw: float = h * 0.5
		_quad(g, [m0 - g.across * mw, m1 - g.across * mw, m1 + g.across * mw, m0 + g.across * mw], q.mat, q.mat_line)
	var len := h * SWADDLE_LEN
	var size := Vector2(len, len * tex.get_height() / tex.get_width())
	var d := IsoMath.basis().basis_xform(g.axis).normalized()
	var start := _lie_screen(g.head, g)
	var mid := start + d * len * 0.5 + Vector2(0, -size.y * 0.3)
	var sx := 1.0
	if d.x < 0.0:
		d = -d
		sx = -1.0
	var breath := 0.5 + 0.5 * sin(TAU * _t / SLEEP_BREATH)
	draw_set_transform(mid, atan2(d.y, d.x), Vector2(sx, 1.0 + 0.03 * breath))
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false, tint)
	draw_set_transform(Vector2.ZERO)


## Soft z's drifting up from the head and fading, one after another.
func _draw_zs(k := 1.0) -> void:
	var g := _geo()
	var font := ThemeDB.fallback_font
	var line := Color("#4A3424")
	var tall: float = float(_look.get("height", 90.0))
	var at := _lie_screen(g.head - g.axis * float(g.head_len) * 0.5, g) + Vector2(4, -tall * 0.14)
	for i in 3:
		var ph := fmod(_t / Z_PERIOD + float(i) / 3.0, 1.0)
		var a := sin(PI * ph) * 0.85
		var size := int(round((8.0 + 6.0 * ph) * k))
		var p := at + Vector2(3.0 + 10.0 * ph + 2.0 * sin(TAU * ph), -24.0 * ph) * k
		draw_string_outline(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(1, 1, 1, a * 0.7))
		draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(line, a))


## Dozing: one small z as the head sinks.
func _draw_doze_z() -> void:
	var u := fmod(_t, CutoutRig.DOZE_PERIOD) / CutoutRig.DOZE_PERIOD
	if u > 0.82:
		return
	var a := sin(PI * u / 0.82) * 0.8
	var h := drawn_height() + seat_lift()
	var p := Vector2(_facing * 14.0 + 6.0 * u, -h + 14.0 - 16.0 * u)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(1, 1, 1, a * 0.7))
	draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Color("#4A3424"), a))
