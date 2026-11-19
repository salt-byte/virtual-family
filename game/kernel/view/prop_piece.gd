class_name PropPiece
extends Node2D
## One picture standing on the ground (a piece of furniture, a tree, a clump of bamboo),
## placed at its foot so the house's y-sort draws people in front of or behind it. Draws a
## soft shadow under it; a piece of furniture also carries the dishes served on it. Only
## used when the pack's skin has a picture for the thing.

var tex: Texture2D
## Where the picture goes, in house coordinates.
var rect := Rect2()
var shadow := true
## Opacity (a piece lifted in arrange mode is faded).
var alpha := 1.0
## The object this stands for (-1: scenery); its dishes are drawn on top.
var object_uid := -1
var house: HouseView
## Furniture people sit or lie on sorts this much above its foot, so whoever sits on it
## (feet just inside its front edge) is drawn over it.
var sort_lift := 0.0
const ON_LIFT := 10.0


func place(t: Texture2D, r: Rect2) -> void:
	tex = t
	rect = r
	position = Vector2(r.get_center().x, r.end.y - sort_lift)
	queue_redraw()


func _draw() -> void:
	if tex == null:
		return
	draw_set_transform(-position)
	if shadow:
		var foot := Vector2(rect.get_center().x, rect.end.y - 2.0)
		var w := rect.size.x * 0.95
		draw_colored_polygon(HouseGround._ellipse(Rect2(foot - Vector2(w * 0.5, 6), Vector2(w, 12))), Color(HouseGround.SHADOW, 0.25 * alpha))
	draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))
	if object_uid >= 0 and house != null:
		house.draw_dishes_on(self, object_uid)
