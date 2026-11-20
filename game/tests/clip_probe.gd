class_name ClipProbe
extends RefCounted
## Looks for 穿模 in a running house, in screen space after the 45° projection and the
## stage's sorting. `frame()` checks the cheap geometry every frame (feet in furniture,
## walking through walls); `check()` the drawing (sort order against the furniture pictures'
## opaque pixels, people over people, seats, the HUD bar) whenever it is called. Each hit is
## logged as {kind, t, who, at, pose, action, detail}; `counts` tallies them per kind.
##
## The rules, each a kind:
##   sort_order      a body overlaps a furniture picture's opaque pixels and is drawn on the
##                   wrong side of it (over a piece that stands in front, under one behind);
##   wall_sort       the same against a full-height back wall;
##   feet_in_furniture  feet inside a footprint (not the seat or bed they are using);
##   walk_wall       a step crosses a closed wall (not through a door gap);
##   stop_wall_line  standing still on a wall line, or where `can_stop` says no;
##   people_overlap  two people's bodies overlap more than OVERLAP (both still or both walking);
##   pet_overlap     a person and an animal likewise;
##   crowd           (not 穿模) two people standing a cell or more apart, one hiding most of
##                   the other on the screen;
##   seat_missing    sitting or lying with no seat or bed under them;
##   lie_wall        lying across a wall (the body's ends in another room or across a wall);
##   sit_height      sitting with the hips off the seat's surface by more than SIT_SLACK;
##   hud             a picture drawn over the bottom HUD bar from a layer above it.

const KINDS := ["sort_order", "wall_sort", "feet_in_furniture", "walk_wall", "stop_wall_line",
	"people_overlap", "pet_overlap", "crowd", "seat_missing", "lie_wall", "sit_height", "hud"]
## Two bodies closer than this (plan pixels, foot to foot) stand in each other's room; further
## apart and overlapping on the screen, one simply stands in front of the other ("crowd",
## counted but not 穿模) unless they overlap more than CROWD.
const NEAR := 34.0
const CROWD := 0.6
## Bodies overlapping more than this share of the smaller one count.
const OVERLAP := 0.3
## A body counts as over a picture when at least this many of its sample points hit the
## picture's opaque pixels.
const OPAQUE_MIN := 6
const SAMPLE := 3.0
## How far round a foot a person takes up (plan pixels), for the in-front-or-behind test.
const FOOT_R := 8.0
const SIT_SLACK := 6.0

var house: HouseView
var counts := {}
var events: Array = []
## Only the first `keep` hits of a kind are kept in `events` (counts go on).
var keep := 40
var t := 0.0
var _prev := {}       # node -> plan position at the last frame
var _masks := {}      # Texture2D -> Image
var _active := {}     # incident key -> true while it goes on
var _last_seat := {}  # walker -> uid of the seat it last sat on
var _seen := {}       # incident keys seen at this look
const FRAME_KINDS := ["feet_in_furniture", "walk_wall"]


func _init(h: HouseView) -> void:
	house = h
	for k in KINDS:
		counts[k] = 0


func _log(kind: String, who: Node2D, detail: String, extra := {}) -> void:
	# One incident per contact: the same kind, walker and other party seen at the last look
	# (frame or check) is the same incident going on.
	var other = extra.get("with", extra.get("key", ""))
	var key := "%s|%d|%s" % [kind, who.get_instance_id(), other.get_instance_id() if other is Object else str(other)]
	_seen[key] = true
	if _active.has(key):
		return
	counts[kind] = int(counts[kind]) + 1
	if int(counts[kind]) > keep:
		return
	var e := {"kind": kind, "t": t, "who": _name(who), "at": who.position, "pose": "", "action": "", "detail": detail, "node": who}
	if who is PersonView:
		var pv := who as PersonView
		e.pose = pv.body_pose()
		e.action = str(pv.person.current.get("action", ""))
	elif who is PetView:
		e.action = str((who as PetView).pet.current.get("action", ""))
	e.merge(extra)
	events.append(e)


## Ends a look: what was not seen again is over.
func _turn_over(kinds: Array) -> void:
	for key in _active.keys():
		if str(key).get_slice("|", 0) in kinds and not _seen.has(key):
			_active.erase(key)
	for key in _seen:
		_active[key] = true
	_seen = {}


static func _name(n: Node2D) -> String:
	if n is PersonView:
		return "person %d" % (n as PersonView).person.uid
	if n is PetView:
		return "pet %d" % (n as PetView).pet.uid
	return str(n)


func _walkers() -> Array:
	var out: Array = []
	for uid in house.people:
		var pv: PersonView = house.people[uid]
		if pv.visible and not pv.held:
			out.append(pv)
	for uid in house.pets:
		out.append(house.pets[uid])
	return out


func _footprints() -> Array:
	var w := house.session.world
	var out: Array = []
	for o in w.objects:
		if str(o.room) in w.rooms_built:
			out.append([house.layout.object_rect(o, w.pack), int(o.uid), str(o.type)])
	return out


## Every frame: feet in furniture and steps through walls.
func frame(delta: float) -> void:
	t += delta
	var site := house.layout.site
	var feet := _footprints()
	for n in _walkers():
		var p: Vector2 = n.position
		var was: Vector2 = _prev.get(n, p)
		_prev[n] = p
		for f in feet:
			var r: Rect2 = f[0]
			if r.grow(-3.0).has_point(p) and not on_own_seat(n, int(f[1]), r) and not _stepped_over(str(f[2])):
				_log("feet_in_furniture", n, "in %s %s" % [f[2], r], {"key": f[1]})
				break
		if was.distance_to(p) > 0.01 and was.distance_to(p) < 60.0:
			var e := wall_crossed(site, was, p)
			if e != "":
				_log("walk_wall", n, "%s -> %s crosses %s" % [was, p, e], {"key": e})
	_turn_over(FRAME_KINDS)


## Whether walker `n` stands on the piece `uid` (footprint `r`) by right: the seat, bed or
## perch it is using, and only on its sitting strip (the front edge in to the seat's anchor),
## not anywhere across it.
func on_own_seat(n: Node2D, uid: int, r: Rect2) -> bool:
	var using := _using(n)
	var depth := 4.0
	if using >= 0:
		if n is PersonView and house.skin != null:
			depth = maxf(depth, float(house.skin.seat(str((n as PersonView).use_object.get("type", ""))).in) * HouseSite.CELL.y)
		_last_seat[n] = [using, depth]
	var last: Array = _last_seat.get(n, [-1, 4.0])
	if uid != using and uid != int(last[0]):
		return false  # (the seat just left counts too: getting up, off its front edge)
	depth = float(last[1]) if uid == int(last[0]) else depth
	return n.position.y >= r.end.y - depth - 6.0 and n.position.x > r.position.x and n.position.x < r.end.x


## Whether people walk over pieces of this type (a door sill): standing on it is no 穿模.
func _stepped_over(type: String) -> bool:
	return house.skin != null and house.skin.step_over(type)


## The object uid a walker stands on by right (a seat, a bed, an animal's perch), else -1.
func _using(n: Node2D) -> int:
	if n is PersonView:
		var pv := n as PersonView
		return int(pv.use_object.get("uid", -1)) if pv.on_object else -1
	if n is PetView:
		return int((n as PetView).pet.current.get("object_uid", -1))
	return -1


## The closed wall a straight step from `a` to `b` goes through ("" for none). A step
## through a cell corner may go either way round.
static func wall_crossed(site: HouseSite, a: Vector2, b: Vector2) -> String:
	var ca := site.cell_of(a)
	var cb := site.cell_of(b)
	if ca == cb:
		return ""
	var n := int(ceil(a.distance_to(b) / 4.0)) + 1
	var c := ca
	for i in range(1, n + 1):
		var q := site.cell_of(a.lerp(b, float(i) / float(n)))
		if q == c:
			continue
		var d := q - c
		if absi(d.x) + absi(d.y) == 1:
			if not site.edge_free(c, q):
				return "edge %s|%s" % [c, q]
		elif absi(d.x) == 1 and absi(d.y) == 1:
			var v1 := Vector2i(q.x, c.y)
			var v2 := Vector2i(c.x, q.y)
			if not ((site.edge_free(c, v1) and site.edge_free(v1, q)) or (site.edge_free(c, v2) and site.edge_free(v2, q))):
				return "corner %s|%s" % [c, q]
		c = q
	return ""


## The drawing checks; call after the house's tick (so the stage is sorted).
func check() -> void:
	var proj := house.proj
	var kids := house.stage.get_children()
	var index := {}
	for i in kids.size():
		index[kids[i]] = i
	var w := house.session.world
	var walkers := _walkers()
	var rects := {}
	for n in walkers:
		rects[n] = body_rect(n)
	# Bodies against furniture pictures and tall walls.
	for n in walkers:
		var body: Rect2 = rects[n]
		if body.size == Vector2.ZERO:
			continue
		for uid in house.props:
			var piece: PropPiece = house.props[uid]
			var o := w.object(uid)
			if o.is_empty() or not str(o.room) in w.rooms_built:
				continue
			var pic := Rect2(proj * piece.position + piece.rect.position, piece.rect.size)
			var x := pic.intersection(body)
			if not x.has_area() or opaque_hits(piece, pic, x) < OPAQUE_MIN:
				continue
			var fr := house.layout.object_rect(o, w.pack)
			var side := 1 if on_own_seat(n, int(uid), fr) or (_stepped_over(str(o.type)) and fr.grow(2.0).has_point(n.position)) else side_of(n.position, fr)
			var drawn_after: bool = index[n] > index[piece]
			if side == 1 and not drawn_after:
				_log("sort_order", n, "under %s, which stands behind" % o.type, {"with": piece})
			elif side == -1 and drawn_after:
				_log("sort_order", n, "over %s, which stands in front" % o.type, {"with": piece})
		for wp in house.walls:
			if not (wp is IsoWall) or wp.role != "wall" or not wp.tall or wp.open or wp.view_box.size == Vector2.ZERO:
				continue
			if not wp.view_box.intersects(body):
				continue
			var x2: Rect2 = wp.view_box.intersection(body)
			if x2.get_area() < 40.0:
				continue
			var side2 := wall_side(n.position, wp)
			var after: bool = index[n] > index[wp]
			if side2 == 1 and not after:
				_log("wall_sort", n, "under the wall %s %d %d" % [wp.along, wp.line, wp.at], {"with": wp})
			elif side2 == -1 and after:
				_log("wall_sort", n, "over the wall %s %d %d" % [wp.along, wp.line, wp.at], {"with": wp})
	# Bodies against bodies.
	for i in walkers.size():
		for j in range(i + 1, walkers.size()):
			var a: Node2D = walkers[i]
			var b: Node2D = walkers[j]
			if a is PetView and b is PetView:
				continue
			var ma := _moving(a)
			if ma != _moving(b):
				continue
			var ra: Rect2 = rects[a]
			var rb: Rect2 = rects[b]
			var xr := ra.intersection(rb)
			if not xr.has_area():
				continue
			var frac := xr.get_area() / minf(ra.get_area(), rb.get_area())
			var apart := a.position.distance_to(b.position)
			if frac > OVERLAP and apart < NEAR:
				var kind := "people_overlap" if a is PersonView and b is PersonView else "pet_overlap"
				_log(kind, a, "%s %.0f%% %s %.0f px apart" % [_name(b), frac * 100.0, "walking" if ma else "still", apart], {"with": b})
			elif frac > CROWD and not ma and a is PersonView and b is PersonView:
				_log("crowd", a, "%s %.0f%% hidden behind, %.0f px apart" % [_name(b), frac * 100.0, apart], {"with": b})
	# Standing still: on a wall line, a seat under the sitter, lying within the room.
	var site := house.layout.site
	for uid in house.people:
		var pv: PersonView = house.people[uid]
		if not pv.visible or pv.held or _moving(pv):
			continue
		var bp := pv.body_pose()
		var bad := ""
		var detail := ""
		if not pv.on_object and (not site.can_stop(pv.position) or on_wall_line(site, pv.position)):
			bad = "stop_wall_line"
		if bp in ["sit", "sleep"] and not bool(pv._look.get("lying", false)):
			if not pv.on_object or pv.use_object.is_empty():
				bad = "seat_missing"
			else:
				var r := house.layout.object_rect(pv.use_object, w.pack)
				if not r.grow(1.0).has_point(pv.position):
					bad = "seat_missing"
				elif bp == "sleep" and lies_across_wall(pv, r):
					bad = "lie_wall"
				elif bp == "sit":
					var off := sit_offset(pv)
					if absf(off) > SIT_SLACK:
						bad = "sit_height"
						detail = "hips %.0f px off the seat" % off
		if bad != "":
			_log(bad, pv, "%s %s" % [pv.use_object.get("type", ""), detail], {"key": "%s|%s" % [pv.use_object.get("uid", -1), pv.person.current.get("action", "")]})
	_turn_over(KINDS.filter(func(k): return not k in FRAME_KINDS))
	_check_hud()


func _moving(n: Node2D) -> bool:
	return n.position.distance_to(n.target) > 1.0


## The figure on the view (the house's unscaled view pixels): a person's body less the
## picture's transparent sides; an animal's picture.
func body_rect(n: Node2D) -> Rect2:
	var foot := house.proj * n.position
	if n is PersonView:
		var pv := n as PersonView
		if pv.body_pose() == "sleep":
			var c := foot + pv.lie_point()
			var len := pv.body_size().y
			return Rect2(c - Vector2(len * 0.45, 12), Vector2(len * 0.9, 24))
		var bw := pv.body_size().x * 0.6
		var h := pv.drawn_height()
		return Rect2(foot + Vector2(-bw * 0.5, -h - pv.seat_lift()), Vector2(bw, h))
	if n is PetView:
		var b := (n as PetView).body()
		return Rect2(foot + Vector2(-b.x * 0.4, -b.y), Vector2(b.x * 0.8, b.y))
	return Rect2()


## How many sample points of view rect `x` fall on the opaque pixels of the piece's picture.
func opaque_hits(piece: PropPiece, pic: Rect2, x: Rect2) -> int:
	var img: Image = _masks.get(piece.tex)
	if img == null:
		img = piece.tex.get_image()
		if img.is_compressed():
			img.decompress()
		_masks[piece.tex] = img
	var sx := float(img.get_width()) / pic.size.x
	var sy := float(img.get_height()) / pic.size.y
	var hits := 0
	var y := x.position.y + SAMPLE * 0.5
	while y < x.end.y:
		var xx := x.position.x + SAMPLE * 0.5
		while xx < x.end.x:
			var u := (xx - pic.position.x) * sx
			if piece.flip:
				u = img.get_width() - 1 - u
			var v := (y - pic.position.y) * sy
			var px := clampi(int(u), 0, img.get_width() - 1)
			var py := clampi(int(v), 0, img.get_height() - 1)
			if img.get_pixel(px, py).a > 0.5:
				hits += 1
			xx += SAMPLE
		y += SAMPLE
	return hits


## Whether someone standing at plan point `p` is in front of footprint `r` (1), behind it
## (-1) or neither surely (0: overlapping, or in front on one axis and behind on the other).
static func side_of(p: Vector2, r: Rect2) -> int:
	var front := p.x - FOOT_R >= r.end.x or p.y - FOOT_R >= r.end.y
	var behind := p.x + FOOT_R <= r.position.x or p.y + FOOT_R <= r.position.y
	if front and not behind:
		return 1
	if behind and not front:
		return -1
	return 0


## The same against one cell's length of wall.
static func wall_side(p: Vector2, wp: IsoWall) -> int:
	var c := HouseSite.CELL
	var r: Rect2
	if wp.along == "x":
		r = Rect2(Vector2(wp.at * c.x, wp.line * c.y), Vector2(c.x, 0))
	else:
		r = Rect2(Vector2(wp.line * c.x, wp.at * c.y), Vector2(0, c.y))
	var front := p.x - 2.0 >= r.end.x or p.y - 2.0 >= r.end.y
	var behind := p.x + 2.0 <= r.position.x or p.y + 2.0 <= r.position.y
	if front and not behind:
		return 1
	if behind and not front:
		return -1
	return 0


static func on_wall_line(site: HouseSite, p: Vector2) -> bool:
	var c := site.cell_of(p)
	var lo := Vector2(c) * HouseSite.CELL
	var hi := lo + HouseSite.CELL
	return (p.x - lo.x < 8.0 and site.v_walls.has(Vector2i(c.x, c.y))) \
		or (hi.x - p.x < 8.0 and site.v_walls.has(Vector2i(c.x + 1, c.y))) \
		or (p.y - lo.y < 8.0 and site.h_walls.has(Vector2i(c.x, c.y))) \
		or (hi.y - p.y < 8.0 and site.h_walls.has(Vector2i(c.x, c.y + 1)))


## Whether the body of someone lying on the bed with footprint `r` reaches past a wall: its
## two ends (across the screen) land in another room or behind a wall from its middle.
func lies_across_wall(pv: PersonView, r: Rect2) -> bool:
	var site := house.layout.site
	var mid := house.proj * pv.position + pv.lie_point()
	var half := pv.body_size().y * 0.5
	for dx in [-half, half]:
		var end := house.proj.affine_inverse() * (mid + Vector2(dx, 0))
		# The end of the body, dropped onto the bed's top, back to the floor under it.
		var floor_end := end + (house.proj.affine_inverse().basis_xform(Vector2(0, 38)))
		var ce := site.cell_of(floor_end)
		if site.room_at(ce) != site.room_at(site.cell_of(r.get_center())):
			return true
		if not r.grow(HouseSite.CELL.x * 0.5).has_point(floor_end):
			return true
	return false


## How far (view pixels) a sitter's hips are above (+) or below (-) the seat's surface: the
## surface height comes from the pack (`seats` in art.json poses); a seat without one counts
## the stool's.
func sit_offset(pv: PersonView) -> float:
	var skin := house.skin
	var seat_h := skin.seat_height(str(pv.use_object.get("type", "")))
	return pv.hip_height() - seat_h


## Pictures on layers over the HUD (the letter bird's perch) inside the bottom bar.
func _check_hud() -> void:
	var main := house.get_parent()
	if main == null:
		return
	var vp := house.get_viewport_rect().size if house.is_inside_tree() else HouseView.VIEW_SIZE
	var bar := Rect2(0, vp.y - HouseView.BOTTOM_BAR, vp.x, HouseView.BOTTOM_BAR)
	for layer in main.find_children("*", "CanvasLayer", true, false):
		var cl := layer as CanvasLayer
		if cl.layer <= 1 or not cl.visible:
			continue
		for c in cl.find_children("*", "LetterBird", true, false):
			var bird := c as Control
			if bird.is_visible_in_tree() and bird.get_global_rect().intersects(bar):
				counts["hud"] = int(counts["hud"]) + 1
				if int(counts["hud"]) <= keep:
					events.append({"kind": "hud", "t": t, "who": "letter bird", "at": bird.global_position, "pose": "", "action": "", "detail": str(bird.get_global_rect())})


func summary() -> String:
	var parts: Array = []
	for k in KINDS:
		parts.append("%s=%d" % [k, int(counts[k])])
	return " ".join(parts)
