extends SceneTree
## godot --headless --path game -s res://tools/balance_cli.gd -- <pack_id> <families> <days>
## Prints one line of JSON summarising `BalanceRun.run` (seeds start at 1).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[1].is_valid_int() or not args[2].is_valid_int():
		printerr("usage: -- <pack_id> <families> <days>")
		quit(2)
		return
	var pack := Pack.load_dir("res://packs/" + args[0])
	if not pack.is_valid():
		for e in pack.errors:
			printerr(e)
		quit(1)
		return
	print(JSON.stringify(BalanceRun.run(args[0], int(args[1]), int(args[2]), 1)))
	quit(0)
