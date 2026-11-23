extends SceneTree
## godot --headless --path game -s res://tools/year_cli.gd -- <pack_id> [years] [seed]
## One household through whole years of festivals: the calendar, then for each festival
## that comes round, who did what for it, which wishes came and went, who went out and what
## they brought back. Outings outside the festivals are listed too. The household is
## `BalanceRun.family_of_four` plus the grandfather's grave (a grandparent who died before
## the game began, so that the day for the dead has someone to remember), looked after by
## `BalanceRun.caretake` every hour and `BalanceRun.festival_round` every five minutes.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <pack_id> [years] [seed]")
		quit(2)
		return
	var years := float(args[1]) if args.size() > 1 else 1.0
	var w := BalanceRun.family_of_four(args[0], int(args[2]) if args.size() > 2 else 1)
	if not w.pack.is_valid():
		for e in w.pack.errors:
			printerr(e)
		quit(1)
		return
	var grandpa := FamilySystem.make_person(w, [70, 70])
	grandpa.gender = "male"
	grandpa.family = w.people[0].family
	w.add_person(grandpa)
	grandpa.alive = false
	w.people[0].father = grandpa.uid
	w.drain_events()
	var year_s := float(w.pack.cfg("hours_per_year")) * 3600.0
	print("━━ 节令（一年 %.1f 个现实小时）━━" % (year_s / 3600.0))
	for c in FestivalSystem.calendar(w.pack):
		var f: Dictionary = w.pack.festivals[c.id]
		print("　%s　%s　第 %d–%d 分钟（%d 分钟）" % [f["name"], f["banner"], int(c.start_s) / 60, int(c.end_s) / 60, (int(c.end_s) - int(c.start_s)) / 60])
	for c in FestivalSystem.dates_between(w.pack, w.now, w.now + 366 * 86400, w.utc_offset):
		var f: Dictionary = w.pack.festivals[c.id]
		print("　%s　%s　%s 起，%d 天（按现实日历，不在模拟的这几年里）" % [f["name"], f["banner"],
			Time.get_date_string_from_unix_time(int(c.start_unix) + w.utc_offset), (int(c.end_unix) - int(c.start_unix)) / 86400])
	var on := ""
	var did := {}  # person uid -> [labels] during the festival on
	var notes: Array[String] = []
	var minutes := int(years * year_s / 60.0)
	for m in minutes:
		if m % 60 == 0:
			BalanceRun.caretake(w)
		w.advance(60.0)
		if w.festival != "" and m % 5 == 4:
			BalanceRun.festival_round(w)
		for e in w.drain_events():
			match e.type:
				"festival_started":
					on = e.festival
					did = {}
					notes = []
					var f: Dictionary = w.pack.festivals[on]
					print("\n%s ❀ %s（%s）%s" % [_clock(w, int(e.t)), f["name"], WeatherSystem.season_at(w.pack, int(e.t)).get("name", ""), f["start_text"]])
				"festival_ended":
					for uid in did:
						print("　　%s：%s" % [_name(w, uid), "；".join(did[uid])])
					for n in notes:
						print("　　" + n)
					print("%s ❀ %s过完了：%s" % [_clock(w, int(e.t)), w.pack.festivals[e.festival]["name"], w.pack.festivals[e.festival]["end_text"]])
					on = ""
				"action_started":
					var a: Dictionary = w.pack.actions[e.action]
					if on != "" and not (a["festivals"] as Array).is_empty():
						if not did.has(int(e.person)):
							did[int(e.person)] = []
						did[int(e.person)].append(a["label"])
					elif OutingSystem.is_outing(a):
						_note(on, notes, w, e, "%s 出了门：%s" % [_name(w, int(e.person)), a["label"]])
				"outing_back":
					var got := "（带回%s）" % w.pack.items[e.item]["name"] if str(e.item) != "" else ""
					_note(on, notes, w, e, "⌂ " + str(e.text).replace("{name}", _name(w, int(e.person))) + got)
				"wish_formed", "wish_granted", "wish_expired":
					var wish: Dictionary = w.pack.wishes[e.wish]
					if str(wish["festival"]) != "" or str(wish["kind"]) == "do":
						var verb: String = {"wish_formed": "心里想着", "wish_granted": "如愿了", "wish_expired": "没等到"}[e.type]
						_note(on, notes, w, e, "♡ %s %s：%s" % [_name(w, int(e.person)), verb, wish["text"]])
				"mourned":
					_note(on, notes, w, e, "✝ %s 念叨了好一阵 %s" % [_name(w, int(e.person)), _name(w, int(e.dead))])
	print("\n━━ 结束 ━━ 家里有钱 %d 文" % w.money)
	quit(0)


## During a festival a line waits for its summary; otherwise it is printed at once.
func _note(on: String, notes: Array[String], w: World, e: Dictionary, line: String) -> void:
	if on != "":
		notes.append(line)
	else:
		print("%s %s" % [_clock(w, int(e.t)), line])


func _clock(w: World, t: int) -> String:
	var s := posmod(t + w.utc_offset, 86400)
	return "%02d:%02d" % [s / 3600, s % 3600 / 60]


func _name(w: World, uid: int) -> String:
	var p := w.person(uid)
	return p.family + p.given if p != null else "?"
