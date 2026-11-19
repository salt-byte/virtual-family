extends SceneTree
## godot --headless --path game -s res://tools/balance_cli.gd -- <pack_id> <families> <days> [first_seed]
## Prints one line of JSON summarising `BalanceRun.run` (seeds start at 1, or at first_seed).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args.size() > 4 or not args[1].is_valid_int() or not args[2].is_valid_int() \
			or (args.size() == 4 and not args[3].is_valid_int()):
		printerr("usage: -- <pack_id> <families> <days> [first_seed]")
		quit(2)
		return
	var pack := Pack.load_dir("res://packs/" + args[0])
	if not pack.is_valid():
		for e in pack.errors:
			printerr(e)
		quit(1)
		return
	print(JSON.stringify(BalanceRun.run(args[0], int(args[1]), int(args[2]), int(args[3]) if args.size() == 4 else 1)))
	quit(0)
