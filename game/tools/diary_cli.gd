extends SceneTree
## godot --headless --path game -s res://tools/diary_cli.gd -- <pack_id> <days> [seed]
## Prints one household's days as a readable diary: what each person chose to do on their
## own, and what happened to them. The household is looked after by `BalanceRun.caretake`
## (buys food, medicine and treats; accepts the first proposal). Nobody is ever dragged.

const SKIP := ["action_finished", "action_cancelled", "collectible_spawned", "collectible_expired", "proposal_expired"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not args[1].is_valid_int():
		printerr("usage: -- <pack_id> <days> [seed]")
		quit(2)
		return
	var w := BalanceRun.setup(args[0], int(args[2]) if args.size() > 2 else 1)
	if not w.pack.is_valid():
		for e in w.pack.errors:
			printerr(e)
		quit(1)
		return
	w.drain_events()
	var days := int(args[1])
	var salary := 0
	for h in days * 24:
		if h % 24 == 0:
			if h > 0:
				print("　　（这一天工钱进账 %d 文）" % salary)
			salary = 0
			print("\n━━ 第 %d 天 ━━ 家里有钱 %d 文" % [h / 24 + 1, w.money])
			for p in w.people:
				if p.alive:
					print("　　%s　%d 岁　%s" % [_name(w, p.uid), int(p.age), "、".join(p.status(w.pack).values())])
		BalanceRun.caretake(w)
		for m in 60:
			w.advance(60.0)
			for e in w.drain_events():
				if e.type == "income":
					salary += int(e.amount)
				elif not SKIP.has(e.type):
					print("%s　%s" % [_clock(w, int(e.t)), _line(w, e)])
	print("\n━━ 结束 ━━ 家里有钱 %d 文" % w.money)
	quit(0)


func _clock(w: World, t: int) -> String:
	var s := posmod(t + w.utc_offset, 86400)
	return "%02d:%02d" % [s / 3600, s % 3600 / 60]


func _name(w: World, uid: int) -> String:
	var p := w.person(uid)
	return p.family + p.given if p != null else "?"


func _line(w: World, e: Dictionary) -> String:
	var who := _name(w, int(e.get("person", 0)))
	match e.type:
		"action_started":
			return "%s %s" % [who, w.pack.actions[e.action]["label"]]
		"fell_ill":
			return "▲ %s 病了（玩家只看得到症状，要自己认是什么病）" % who
		"cured":
			return "● %s 的病治好了" % who
		"level_up":
			return "★ %s 成了%s" % [who, w.pack.livelihoods[e.track]["levels"][int(e.level)]["name"]]
		"married":
			return "★ 成亲了：%s 进了门" % who
		"proposal_arrived":
			return "✉ 媒人上门提亲"
		"person_died":
			return "✝ %s 去世（%s）" % [who, "寿终" if e.cause == "old_age" else "照看不周"]
		"mess_spawned":
			return "· %s多了一处脏乱" % w.pack.rooms[e.room].get("name", e.room)
		"mess_cleaned":
			return "· 一处脏乱收拾掉了"
		"collected":
			return "· 院里捡到东西（%s）" % ("头一件，收进藏品" if e.first else "卖了 %d 文" % int(e.value))
		"goal_done":
			return "✓ 达成「%s」，赏 %d 文" % [w.pack.goals[e.goal]["text"], int(e.reward)]
	return str(e)
