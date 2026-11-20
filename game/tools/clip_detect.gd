extends SceneTree
## Runs the real 起家 house for a while at normal speed and counts 穿模 (`ClipProbe`).
## Headless for the counts:
##   godot --headless --path game -s res://tools/clip_detect.gd -- <scenario> <minutes> <out dir>
## Off-screen (never on the user's screen) to also save a cropped picture of the first few of
## each kind as <out dir>/clip_<kind>_<n>.png:
##   godot --path game --position 20000,20000 --resolution 1280x720 -s res://tools/clip_detect.gd -- <scenario> <minutes> <out dir> shots
## <scenario>: "full" (every room built, a family of seven, a dog, a cat and a bird) or
## "start" (the default start). Uses its own user:// folder, never the real save.

const DT := 1.0 / 30.0
const CHECK_EVERY := 3
const SHOTS_PER_KIND := 3

var clk := {"unix": 1767254400.0 + 7.0 * 3600.0, "offset": 0}
var m: Main
var probe: ClipProbe
var out := ""
var shots := false
var _shot_n := {}
var _mark: Node2D
var _mark_rects: Array = []


func _clock() -> Dictionary:
	return clk


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := str(args[0]) if args.size() > 0 else "full"
	var minutes := float(args[1]) if args.size() > 1 else 60.0
	out = str(args[2]) if args.size() > 2 else "user://clip_out"
	shots = args.size() > 3 and str(args[3]) == "shots"
	DirAccess.make_dir_recursive_absolute(out)
	m = start(self, scenario, clk, _clock)
	m.set_process(false)
	probe = ClipProbe.new(m.house)
	if shots:
		var layer := CanvasLayer.new()
		layer.layer = 50
		_mark = Node2D.new()
		_mark.draw.connect(func():
			for r in _mark_rects:
				_mark.draw_rect(r, Color(1, 0, 0), false, 2.0))
		layer.add_child(_mark)
		root.add_child(layer)
	var frames := int(minutes * 60.0 / DT)
	var t0 := Time.get_ticks_msec()
	for f in frames:
		clk.unix += DT
		m.tick(DT)
		probe.frame(DT)
		if f % CHECK_EVERY == 0:
			var before := probe.events.size()
			probe.check()
			if shots:
				for i in range(before, probe.events.size()):
					await _shoot(probe.events[i])
		if f % 9000 == 0:
			print("  %.0f min  %s  (%d ms)" % [f * DT / 60.0, probe.summary(), Time.get_ticks_msec() - t0])
	print("RESULT %s %.0f min: %s" % [scenario, minutes, probe.summary()])
	var lines: Array = []
	for e in probe.events:
		lines.append("%7.1fs %-18s %-10s at %s pose=%s action=%s %s" % [e.t, e.kind, e.who, e.at, e.pose, e.action, e.detail])
	var f2 := FileAccess.open(out.path_join("clip_log_%s.txt" % scenario), FileAccess.WRITE)
	f2.store_string(probe.summary() + "\n" + "\n".join(lines) + "\n")
	f2.close()
	for l in lines.slice(0, 80):
		print(l)
	quit()


## A fresh 起家 house in its own user:// folder. "full": every room built, a family of
## seven and three animals; "start": as a new game starts.
static func start(tree: SceneTree, scenario: String, clk: Dictionary, clock: Callable) -> Main:
	var d := "user://clip_detect_%s/" % scenario
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	seed(11)
	var main := Main.create("qijia", d, clock)
	tree.root.add_child(main)
	main.session.command({"type": "adopt"})
	var w := main.session.world
	if scenario == "full":
		w.money = 100000
		for id in w.pack.rooms:
			if not id in w.rooms_built:
				main.session.command({"type": "build_room", "room": id})
		var spouse := FamilySystem.make_person(w, w.pack.cfg("adopt_age"))
		spouse.gender = "female" if w.people[0].gender == "male" else "male"
		w.add_person(spouse)
		w.married = true
		w.add_person(FamilySystem.make_person(w, [62, 66]))
		w.add_person(FamilySystem.make_person(w, [64, 68]))
		for i in 2:
			w.add_person(FamilySystem.make_person(w, [6, 12]))
		w.add_person(FamilySystem.make_person(w, [18, 22]))
		for k in ["dog", "cat", "bird"]:
			if w.pack.pets.has(k):
				PetSystem.add(w, k, "bought")
		w.stock["food"] = 40
		for e in [["stool", "yard", 8, 1], ["stool", "hall", 1, 4], ["millstone", "yard", 2, 1],
				["clothesline", "yard", 5, 5], ["loom", "bedroom", 3, 3]]:
			if HouseSystem.can_place(w, e[0], e[1], e[2], e[3]) == "":
				w.add_object(e[0], e[1], e[2], e[3])
	main.tick(DT)
	return main


func _shoot(e: Dictionary) -> void:
	var k: String = e.kind
	var n := int(_shot_n.get(k, 0))
	if n >= SHOTS_PER_KIND:
		return
	_shot_n[k] = n + 1
	var house := m.house
	house.unfollow()
	house.zoom_to(1.6)
	house.pan(Vector2(640, 330) - house.to_screen(e.at))
	var c := house.to_screen(e.at)
	_mark_rects = []
	if k != "hud":
		for who in [e.get("node"), e.get("with")]:
			if who is PersonView or who is PetView:
				var r: Rect2 = probe.body_rect(who)
				_mark_rects.append(Rect2(house.position + r.position * house.scale, r.size * house.scale))
	_mark.queue_redraw()
	house.queue_redraw()
	if house.ground != null:
		house.ground.queue_redraw()
	for i in 3:
		await process_frame
	var img := root.get_texture().get_image()
	var crop := Rect2i(int(c.x) - 200, int(c.y) - 230, 400, 300).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if k == "hud":
		crop = Rect2i(0, img.get_height() - 160, img.get_width(), 160)
	var part := img.get_region(crop)
	part.save_png(out.path_join("clip_%s_%d.png" % [k, n + 1]))
	print("  shot clip_%s_%d.png  %s %s %s" % [k, n + 1, e.who, e.action, e.detail])
