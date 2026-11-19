extends SceneTree
## godot --headless --path game -s res://tools/pets_cli.gd -- <households> <days>
## Two long runs of a family of four with a dog and a cat (qijia):
## - "neglected": nobody looks after the animals (the pack's care actions are taken out and
##   the caretaker leaves them alone; it still looks after the people);
## - "cared": the usual hourly caretaker, and the family looks after them by itself.
## Prints, per household, what became of each animal (ran away / came back / died, and when).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var homes := int(args[0]) if args.size() > 0 else 5
	var days := int(args[1]) if args.size() > 1 else 5
	for mode in ["neglected", "cared"]:
		var tally := {}
		for i in homes:
			var pack := Pack.load_dir("res://packs/qijia")
			if mode == "neglected":
				for id in pack.actions.keys():
					if not (pack.actions[id]["pet"] as Dictionary).is_empty():
						pack.actions.erase(id)
				pack.config["pets"]["stray_chance_per_hour"] = 0.0
			BalanceRun.look_after_pets = mode == "cared"
			var w := BalanceRun.setup_pack(pack, 100 + i)
			var spouse := FamilySystem.make_person(w, w.pack.cfg("adopt_age"))
			w.add_person(spouse)
			w.married = true
			for k in 2:
				w.add_person(FamilySystem.make_person(w, [6, 12]))
			w.stock["food"] = 20
			if mode == "cared":
				w.pack.config["pets"]["stray_chance_per_hour"] = 0.0
			var dog := PetSystem.add(w, "dog", "bought")
			var cat := PetSystem.add(w, "cat", "bought")
			var log: Array[String] = []
			var t0 := w.now
			for h in days * 24:
				BalanceRun.caretake(w)
				w.advance(3600.0)
				for e in w.drain_events():
					if str(e.type) in ["pet_ran_away", "pet_came_back", "pet_died", "pet_fell_ill", "pet_cured"]:
						var p := PetSystem.find(w, int(e.pet))
						var what: String = str(e.type).trim_prefix("pet_") + (":" + str(e.cause) if e.has("cause") else "")
						log.append("%s#%d %s h%d" % [p.given, p.uid, what, (int(e.t) - t0) / 3600])
						tally[what] = int(tally.get(what, 0)) + 1
			print("%s #%d (dog %s#%d lives %.1f y, cat %s#%d %.1f y; pets age %s y per %s h): %s" % [mode, i, dog.given, dog.uid,
				dog.lifespan, cat.given, cat.uid, cat.lifespan, str(w.pack.cfg("pets").get("age_rate", 1.0)),
				str(w.pack.cfg("hours_per_year")), ", ".join(log)])
		print("%s total: %s" % [mode, tally])
	quit()
