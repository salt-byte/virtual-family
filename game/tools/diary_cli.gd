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


## HH:MM:SS: on the fast action clock a person starts several things within one minute.
func _clock(w: World, t: int) -> String:
	var s := posmod(t + w.utc_offset, 86400)
	return "%02d:%02d:%02d" % [s / 3600, s % 3600 / 60, s % 60]


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
			return "· %s多了一处脏乱（%s）" % [w.pack.rooms[e.room].get("name", e.room), w.pack.mess_types[e.kind].get("name", e.kind)]
		"dish_served":
			var o := w.object(int(e.object))
			return "· %s上摆出了%s" % [w.pack.object_types.get(str(o.get("type", "")), {}).get("name", "?"), w.pack.dishes[e.kind]["name"]]
		"dish_finished":
			return "· %s%s" % [w.pack.dishes[e.kind]["name"], "吃光了" if e.how == "eaten" else "放凉了没人吃"]
		"mess_cleaned":
			return "· 一处脏乱收拾掉了"
		"collected":
			return "· %s 捡到%s（%s）" % [who, w.pack.collectibles[e.kind].get("name", e.kind), "头一件，收进藏品" if e.first else "卖了 %d 文" % int(e.value)]
		"goal_done":
			return "✓ 达成「%s」，赏 %d 文" % [w.pack.goals[e.goal]["text"], int(e.reward)]
		"wish_formed":
			return "♡ %s 心里想着：%s" % [who, w.pack.wishes[e.wish]["text"]]
		"wish_granted":
			return "♡ %s 如愿了（%s），朝屏幕招手道谢" % [who, w.pack.wishes[e.wish]["text"]]
		"wish_expired":
			return "♡ %s 没等到：%s" % [who, w.pack.wishes[e.wish]["text"]]
		"mood_changed":
			return "☁ %s %s" % [who, {"sad": "难过起来", "depressed": "这几天闷闷不乐（抑郁）", "": "心绪好了"}.get(e.mood, e.mood) if not (e.was == "depressed") else "缓过来了"]
		"fragment_found":
			return "◆ %s 捡到了%s" % [who, StorySystem.fragment(w.pack, e.story, e.fragment)["name"]]
		"conceived":
			return "✿ %s 怀上了" % who
		"born":
			var c := w.person(int(e.person))
			return "✿ 添丁：%s（%s，第 %d 代）" % [who, "男" if c.gender == "male" else "女", c.generation + 1]
		"births_blocked":
			return "✿ 炕睡不下了，添不了丁"
		"relative_arrived":
			return "✿ 只剩下孩子，远房亲戚 %s 进了门" % who
		"took_up":
			return "★ %s 长大成人，做了%s" % [who, w.pack.livelihoods[e.track]["name"]]
		"story_unlocked", "story_finale", "story_done":
			return "◆ 旧事「%s」：%s" % [w.pack.stories[e.story]["title"], {"story_unlocked": "露了头", "story_finale": "凑齐了", "story_done": "了结"}[e.type]]
	return str(e)
