class_name PropPiece
extends Node2D
## One picture standing on the ground (a piece of furniture, a tree, a clump of bamboo),
## placed at its foot so the house's y-sort draws people in front of or behind it. Draws a
## soft shadow under it; a piece of furniture also carries the dishes served on it. Only
## used when the pack's skin has a picture for the thing.

var tex: Texture2D
## Where the picture goes: in house coordinates (`place`), or round this node, upright, in
## view pixels (`place_at`, the 45° view).
var rect := Rect2()
var shadow := true
## The 45° view: the shadow's outline round this node (the footprint), view pixels.
var shade := PackedVector2Array()
## Opacity (a piece lifted in arrange mode is faded).
var alpha := 1.0
## The object this stands for (-1: scenery); its dishes are drawn on top.
var object_uid := -1
var house: HouseView
## Furniture people sit or lie on sorts this much above its foot, so whoever sits on it
## (feet just inside its front edge) is drawn over it.
var sort_lift := 0.0
const ON_LIFT := 10.0
## The 45° view: drawn mirrored; how much further back it sorts (view pixels).
var flip := false
var sort_bias := 0.0
var _local := false


func place(t: Texture2D, r: Rect2) -> void:
	tex = t
	rect = r
	_local = false
	position = Vector2(r.get_center().x, r.end.y - sort_lift)
	queue_redraw()


## Stands the picture at plan point `at`; `r` is upright round it, in view pixels.
func place_at(t: Texture2D, r: Rect2, at: Vector2) -> void:
	tex = t
	rect = r
	_local = true
	position = at
	queue_redraw()


func _draw() -> void:
	if tex == null:
		return
	if not _local:
		draw_set_transform(-position)
	if shadow and _local and shade.size() >= 3:
		draw_colored_polygon(shade, Color(HouseGround.SHADOW, 0.14 * alpha))
	elif shadow:
		var foot := Vector2(rect.get_center().x, rect.end.y - 2.0)
		var w := rect.size.x * 0.95
		var h := 12.0
		var a := 0.25
		if _local:
			# The 45° view: under the middle of the footprint (this node's origin), not under
			# the picture's lowest point (an open piece's front leg).
			foot = Vector2(rect.get_center().x, 0.0)
			w = rect.size.x * 0.7
			h = w * 0.45
			a = 0.16
		draw_colored_polygon(HouseGround._ellipse(Rect2(foot - Vector2(w * 0.5, h * 0.5), Vector2(w, h))), Color(HouseGround.SHADOW, a * alpha))
	if flip:
		var mid := rect.get_center().x
		draw_set_transform(Vector2(2.0 * mid, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))
	if object_uid >= 0 and house != null:
		house.draw_dishes_on(self, object_uid)
