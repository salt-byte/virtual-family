extends SceneTree
## godot --headless --path game -s res://tools/asks_cli.gd -- <pack_id> [seeds] [minutes]
## Prints one line of JSON: `AsksRun.run` for a fresh game and for a family of four, each
## left alone and with an attentive player, over `seeds` seeds (default 5) of `minutes` real
## minutes (default 60), plus the per-seed runs folded into means.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <pack_id> [seeds] [minutes]")
		quit(2)
		return
	var pack := Pack.load_dir("res://packs/" + args[0])
	if not pack.is_valid():
		for e in pack.errors:
			printerr(e)
		quit(1)
		return
	var seeds := int(args[1]) if args.size() > 1 else 5
	var minutes := int(args[2]) if args.size() > 2 else 60
	var out := {}
	for setup in ["fresh", "family"]:
		for helper in [false, true]:
			var runs: Array = []
			for s in seeds:
				var w: World = AsksRun.fresh(pack, s + 1) if setup == "fresh" else AsksRun.family(pack, s + 1)
				runs.append(AsksRun.run(w, minutes * 60, helper))
			out["%s_%s" % [setup, "helped" if helper else "alone"]] = _fold(runs, minutes)
	print(JSON.stringify(out))
	quit(0)


## Means over the runs of the headline numbers, the first run's need curve, and the kinds.
func _fold(runs: Array, minutes: int) -> Dictionary:
	var f := {"shown_pct": 0.0, "new_requests": 0.0, "still_open_at_end": 0.0}
	var hows := {"granted": [0.0, 0.0], "self": [0.0, 0.0], "expired": [0.0, 0.0]}
	var kinds := {}
	var ids := {}  # request key -> [ended, seconds up, by the player, by themselves, ran out], all runs
	for r in runs:
		for k in f:
			f[k] += float(r[k]) / runs.size()
		for h in hows:
			hows[h][0] += float(r[h]["n"]) / runs.size()
			hows[h][1] += float(r[h]["mean_s"]) * float(r[h]["n"])
		for k in r["by_kind"]:
			kinds[k] = int(kinds.get(k, 0)) + int(r["by_kind"][k])
		for k in r["by_id"]:
			var b: Array = ids.get(k, [0, 0, 0, 0, 0])
			for j in 5:
				b[j] += int(r["by_id"][k][j])
			ids[k] = b
	for k in f:
		f[k] = snappedf(f[k], 0.1)
	f["mean_gap_s"] = snappedf(60.0 * minutes / f["new_requests"], 1) if f["new_requests"] > 0 else -1
	for h in hows:
		var n := float(hows[h][0]) * runs.size()
		f[h] = {"n_per_run": snappedf(hows[h][0], 0.1), "mean_up_s": snappedf(hows[h][1] / n, 1) if n > 0 else 0}
	f["kinds_all_runs"] = kinds
	var by_id := {}
	for k in ids:
		var b: Array = ids[k]
		by_id[k] = {"ended": b[0], "mean_up_s": roundi(float(b[1]) / b[0]), "player": b[2], "self": b[3], "ran_out": b[4]}
	f["requests_all_runs"] = by_id
	f["people"] = runs[0]["people"]
	f["needs_every_5_min_seed1"] = runs[0]["needs_every_5_min"]
	f["per_seed_shown_pct"] = runs.map(func(r): return r["shown_pct"])
	return f
