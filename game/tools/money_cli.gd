extends SceneTree
## godot --headless --path game -s res://tools/money_cli.gd -- <pack_id> <families> <days>
## Where a household's money comes from, day by day: income by source, what was spent, and
## the money at each day's end (BalanceRun's caretaker plays the household).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fams := int(args[1])
	var days := int(args[2])
	var by_day := []
	for d in days:
		by_day.append({"src": {}, "earned": 0, "spent": 0, "end": 0, "workers": 0})
	for i in fams:
		var w := BalanceRun.setup(args[0], 1 + i)
		for h in days * 24:
			var d: Dictionary = by_day[h / 24]
			var before := w.money
			BalanceRun.caretake(w)
			var got := 0
			for k in 12:
				w.advance(300.0)
			for e in w.drain_events():
				if e.type == "income":
					got += int(e.amount)
					d.src[e.source] = int(d.src.get(e.source, 0)) + int(e.amount)
			d.earned += got
			d.spent += maxi(before + got - w.money, 0)
			if h % 24 == 23:
				d.end += w.money
				for p in w.people:
					if p.alive and p.track != "" and p.stage(w.pack) in ["adult", "elder"]:
						d.workers += 1
	for d in days:
		var x: Dictionary = by_day[d]
		var src := {}
		for s in x.src:
			src[s] = x.src[s] / fams
		print("day %d  earned %d  spent %d  end %d  workers %.1f  %s" % [d + 1, x.earned / fams, x.spent / fams, x.end / fams, float(x.workers) / fams, JSON.stringify(src)])
	quit(0)
