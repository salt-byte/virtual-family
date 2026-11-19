class_name IsoMath
extends RefCounted
## The 45° view (2:1 diamonds): how a point of the site plan (house coordinates, a cell
## 48 x 36) lands on the view (unscaled screen pixels, a cell a 64 x 32 diamond). Plan x
## (east) runs down-right on the screen, plan y (south) down-left; the camera stands in the
## south-east, so whatever has the larger x + y stands in front. Pure maths, no drawing.

## The screen size of one cell's diamond.
const TILE := Vector2(64, 32)
## The screen length of one cell's edge (either axis).
const EDGE := 35.77708764
## Screen pixels per plan pixel of a north-south walk (EDGE / 36): walkers cover this many
## screen pixels per plan pixel of their speed, whichever way they go.
const ISO_PACE := 0.99380799


## Plan pixels -> view pixels (a linear map: the plan origin stays at the view origin).
static func basis() -> Transform2D:
	var c := HouseSite.CELL
	return Transform2D(Vector2(TILE.x * 0.5 / c.x, TILE.y * 0.5 / c.x), Vector2(-TILE.x * 0.5 / c.y, TILE.y * 0.5 / c.y), Vector2.ZERO)


## View pixels -> plan pixels.
static func inverse() -> Transform2D:
	return basis().affine_inverse()


static func to_view(p: Vector2) -> Vector2:
	return basis() * p


static func to_plan(v: Vector2) -> Vector2:
	return inverse() * v


## A point given in cells (fractions allowed) -> view pixels.
static func cell_view(i: float, j: float) -> Vector2:
	return Vector2((i - j) * TILE.x * 0.5, (i + j) * TILE.y * 0.5)


## The diamond a plan rect covers, in view pixels: top, right, bottom, left corner.
static func diamond(r: Rect2) -> PackedVector2Array:
	var b := basis()
	return PackedVector2Array([b * r.position, b * Vector2(r.end.x, r.position.y), b * r.end, b * Vector2(r.position.x, r.end.y)])


## The view rect around a plan rect's diamond.
static func view_rect(r: Rect2) -> Rect2:
	var d := diamond(r)
	return Rect2(Vector2(d[3].x, d[0].y), Vector2(d[1].x - d[3].x, d[2].y - d[0].y))


## How far in front a plan point stands (view y): larger is nearer the camera.
static func depth(p: Vector2) -> float:
	return (basis() * p).y


## A transform for drawing upright (unslanted) at plan point `at` on a canvas item that
## draws in plan coordinates under `basis()`: local x right, y down, in view pixels.
static func upright(at: Vector2) -> Transform2D:
	var inv := inverse()
	return Transform2D(inv.x, inv.y, at)
