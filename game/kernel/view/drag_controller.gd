class_name DragController
extends Node
## Picking a person up and dropping them on furniture, a mess, something lying about, a
## baby (to care for it) or an animal of the house (to feed, pet, wash or dose it).
## The drop becomes one `drag` command; the result decides nothing here except where the
## person is left standing. Reads the World, writes only through the session.

const KINDS := {"object": "object", "mess": "mess", "collectible": "collectible"}

## Uid of the person being dragged; -1 for nobody.
var dragging := -1

var main: Main
var _origin := Vector2.ZERO


func setup(m: Main) -> void:
	main = m


func begin(uid: int) -> void:
	if dragging >= 0:
		cancel()
	var pv := _view(uid)
	if pv == null:
		return
	dragging = uid
	_origin = pv.position
	pv.held = true
	pv.z_index = 10
	_hover(main.house.layout.pick(main.session.world, pv.position))


func move(world_pos: Vector2) -> void:
	var pv := _view(dragging)
	if pv == null:
		return
	pv.position = world_pos
	var baby := _baby_at(world_pos, dragging)
	var pet := main.house.pet_at(world_pos) if baby < 0 else -1
	if baby >= 0:
		_hover({"kind": "person", "uid": baby})
	elif pet >= 0:
		_hover({"kind": "pet", "uid": pet})
	else:
		_hover(main.house.layout.pick(main.session.world, world_pos))


## Lets go of the person at `world_pos` and returns the command's result; `{}` when nothing
## was being dragged or no command was sent.
func drop(world_pos: Vector2) -> Dictionary:
	if dragging < 0:
		return {}
	var uid := dragging
	var pv := _view(uid)
	var hit := main.house.layout.pick(main.session.world, world_pos)
	dragging = -1
	_hover({})
	if pv == null:
		return {}
	pv.held = false
	pv.z_index = 0
	var baby := _baby_at(world_pos, uid)
	if baby >= 0:
		_leave_at(pv, world_pos)
		return main.session.command({"type": "drag", "person": uid, "tend": baby})
	var pet := main.house.pet_at(world_pos)
	if pet >= 0:
		_leave_at(pv, world_pos)
		return main.session.command({"type": "drag", "person": uid, "pet": pet})
	var cmd := {"type": "drag", "person": uid}
	var quiet := not KINDS.has(str(hit.kind)) and str(hit.kind) != "mark"
	if quiet:
		cmd["object"] = -1
	elif str(hit.kind) == "mark":
		cmd["story"] = str(hit.story)
	else:
		cmd[KINDS[str(hit.kind)]] = int(hit.uid)
	var built: bool = str(hit.room) != "" and str(hit.room) in main.session.world.rooms_built
	if built:
		_leave_at(pv, world_pos)
	else:
		_leave_at(pv, _origin)
	if quiet:
		main.hud.mute("no_object")
	var r := main.session.command(cmd)
	if quiet:
		main.hud.unmute()
	return r


func cancel() -> void:
	if dragging < 0:
		return
	var pv := _view(dragging)
	dragging = -1
	_hover({})
	if pv != null:
		pv.held = false
		pv.z_index = 0
		_leave_at(pv, _origin)


## Called after every house refresh: a person who is no longer alive cannot be dragged.
func refresh() -> void:
	if dragging >= 0 and _view(dragging) == null:
		cancel()


func _leave_at(pv: PersonView, pos: Vector2) -> void:
	pv.position = pos
	pv.base_target = pos
	pv.target = pos


## The uid of a living baby under `world_pos` other than `held_uid` (the one being dragged), or -1.
func _baby_at(world_pos: Vector2, held_uid: int) -> int:
	var w := main.session.world
	for uid in main.house.people:
		if uid == held_uid:
			continue
		var p := w.person(uid)
		if p != null and p.alive and p.stage(w.pack) == "baby" and (main.house.people[uid] as PersonView).hit(world_pos):
			return uid
	return -1


func _view(uid: int) -> PersonView:
	if main == null or uid < 0 or not main.house.people.has(uid):
		return null
	return main.house.people[uid]


func _hover(h: Dictionary) -> void:
	main.house.set_hover(h)
