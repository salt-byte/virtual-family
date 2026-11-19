class_name PersonPortrait
extends Control
## A person drawn into a card (the adoption picker, the proposal card): their own picture
## from the pack skin, facing the player, on a round cream ground; without a picture, a
## round of their colour with the first character of their name.
## In order: the painted portrait of the person's own look (`portrait`, the adapter for the
## looks being wired on main), else their rig standing and breathing (`look_for`), else a
## round of their colour with the first character of their name.

var person: Person
var skin: PackSkin
var pack: Pack
## The id of the person's look (a face and outfit of their own), "" for none.
var look := ""
var _t := 0.0
var _portrait: Texture2D


## `look_id` names the person's look when the caller knows it (a candidate's dict); else it
## is read from the person once Person carries one.
static func make(p: Person, sk: PackSkin, pk: Pack, side := Vector2(150, 160), look_id := "") -> PersonPortrait:
	var pp := PersonPortrait.new()
	pp.person = p
	pp.skin = sk
	pp.pack = pk
	pp.look = look_id
	if pp.look == "" and p != null and p.get("look") is String:
		pp.look = str(p.get("look"))
	pp._portrait = pp.portrait()
	pp.custom_minimum_size = side
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return pp


## ADAPTER (looks on main): the painted portrait of the person's look, or null. Asks the
## skin first (`look_portrait(id)`, the API being added on main); until then looks for
## `chars/portraits/<id>.png` in the pack's art folder.
func portrait() -> Texture2D:
	if look == "" or skin == null or not skin.enabled:
		return null
	if skin.has_method("portrait"):
		var t = skin.call("portrait", look)
		return t if t is Texture2D else null
	if skin.has_method("look_portrait"):
		var t2 = skin.call("look_portrait", look)
		return t2 if t2 is Texture2D else null
	var file := "chars/portraits/%s.png" % look
	if not ResourceLoader.exists(str(skin.get("_base")) + "/" + file):
		return null
	return skin.texture(file)


## The skin's look for this person: {rig_front, rig, tex, height} or {}.
func look_for() -> Dictionary:
	if skin == null or not skin.enabled or person == null or pack == null:
		return {}
	return skin.person_look(person.stage(pack), person.gender, str(person.get("look") if person.get("look") != null else ""))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r := minf(size.x, size.y) * 0.5 - 2.0
	if person != null and _portrait != null:
		# The painted portrait in a wooden frame, as large as the card allows.
		var k := minf((size.x - 8.0) / _portrait.get_width(), (size.y - 8.0) / _portrait.get_height())
		var sz := Vector2(_portrait.get_width(), _portrait.get_height()) * k
		var at := Rect2(c - sz * 0.5, sz)
		draw_rect(at.grow(3.0), ViewWidgets.PALE)
		draw_texture_rect(_portrait, at, false)
		draw_rect(at.grow(3.0), ViewWidgets.WOOD, false, 3.0)
		return
	draw_circle(c, r, ViewWidgets.PALE)
	draw_arc(c, r, 0.0, TAU, 48, ViewWidgets.WOOD, 3.0, true)
	if person == null:
		return
	var look_d := look_for()
	var rig: CutoutRig = look_d.get("rig_front", look_d.get("rig"))
	var feet := Vector2(c.x, c.y + r * 0.86)
	var tall := r * 1.62 * (1.0 if person.stage(pack) in ["adult", "elder"] else 0.78)
	if rig != null:
		var k := tall / rig.height
		var x := Transform2D(0.0, Vector2(k, k), 0.0, feet)
		rig.draw(self, rig.pose("idle", _t), x)
		return
	var tex: Texture2D = look_d.get("tex")
	if tex != null:
		var k2 := tall / float(tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * k2
		draw_texture_rect(tex, Rect2(feet - Vector2(sz.x * 0.5, sz.y), sz), false)
		return
	var col := PersonView.FEMALE if person.gender == "female" else (PersonView.MALE if person.gender == "male" else PersonView.OTHER)
	draw_circle(c, r * 0.62, col)
	var font := get_theme_default_font()
	var fs := int(r * 0.7)
	var ch := person.given.left(1)
	var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ViewWidgets.CREAM)
