extends TestCase

func _living() -> World:
	return BalanceRun.setup("qijia", 1)

func _events_of(w: World, type: String) -> Array:
	return w.drain_events().filter(func(e): return e.type == type)

func test_default_and_override():
	var s := ViewStrings.new(Pack.load_dir("res://packs/_smoke"))
	assert_eq(s.t("btn.shop"), "商店")
	var q := ViewStrings.new(Pack.load_dir("res://packs/qijia"))
	assert_eq(q.t("btn.shop"), "集市")
	assert_eq(q.t("btn.close"), "关闭")
	assert_eq(q.t("no.such.key"), "no.such.key")
	assert_eq(q.errors, [] as Array[String])

func test_missing_pack_does_not_crash():
	var s := ViewStrings.new(Pack.load_dir("res://packs/no_such_pack"))
	assert_eq(s.t("btn.shop"), "商店")

func test_error_codes():
	var s := ViewStrings.new(Pack.load_dir("res://packs/_smoke"))
	assert_eq(s.error("busy"), "那儿有人在用")
	assert_eq(s.error("zzz"), "做不了（zzz）")

func test_every_kernel_error_code_has_text():
	var re := RegEx.create_from_string('(?:fail\\(|return )"([a-z_]+)"')
	var n := 0
	for f in DirAccess.get_files_at("res://kernel/sim"):
		if not f.ends_with(".gd"):
			continue
		for m in re.search_all(FileAccess.get_file_as_string("res://kernel/sim/" + f)):
			var code := m.get_string(1)
			if code in ["mess", "collectible"]:  # target_kind 的返回值，不是错误码
				continue
			n += 1
			assert_true(ViewStrings.DEFAULTS.has("error." + code), "no text for " + code)
	assert_true(n > 20)

func test_fell_ill_text_never_names_the_illness():
	var w := _living()
	var p: Person = w.people[0]
	IllnessSystem.infect(w, p, "chill")
	var s := ViewStrings.new(w.pack)
	var line := ""
	for e in w.drain_events():
		if e.type == "fell_ill":
			line = s.event(e, w)
	assert_true(line.contains(p.given))
	for id in w.pack.illnesses:
		assert_true(not line.contains(str(w.pack.illnesses[id]["name"])))

func test_silent_events():
	var w := _living()
	var s := ViewStrings.new(w.pack)
	var p: Person = w.people[0]
	for e in [{"type": "action_started", "person": p.uid, "action": "x", "object": 0, "target": 0},
			{"type": "income", "amount": 5, "source": "work"},
			{"type": "mess_spawned", "uid": 1, "kind": "k", "room": "r"},
			{"type": "action_finished", "person": p.uid, "action": "x"},
			{"type": "proposal_expired", "id": 1}]:
		assert_eq(s.event(e, w), "")

func test_sentences_for_events():
	var w := _living()
	var s := ViewStrings.new(w.pack)
	var p: Person = w.people[0]
	var lv: String = w.pack.livelihoods[p.track]["levels"][0]["name"] if p.track != "" else ""
	if p.track != "":
		var line := s.event({"type": "level_up", "person": p.uid, "track": p.track, "level": 0}, w)
		assert_true(line.contains(p.given) and line.contains(lv))
	assert_true(s.event({"type": "married", "person": p.uid}, w).contains(p.given))
	assert_true(s.event({"type": "cured", "person": p.uid}, w).contains(p.given))
	assert_eq(s.event({"type": "proposal_arrived", "id": 1}, w), "有人上门提亲")
	assert_true(s.event({"type": "person_died", "person": p.uid, "cause": "old_age"}, w).contains("寿终"))
	assert_true(s.event({"type": "person_died", "person": p.uid, "cause": "neglect"}, w).contains("没能撑过去"))
	var gid: String = w.pack.goals.keys()[0]
	var g := s.event({"type": "goal_done", "goal": gid, "reward": 123}, w)
	assert_true(g.contains(str(w.pack.goals[gid]["text"])) and g.contains("123"))
	var cid: String = w.pack.collectibles.keys()[0]
	var cname: String = w.pack.collectibles[cid]["name"]
	var first := s.event({"type": "collected", "uid": 1, "kind": cid, "value": 4, "first": true, "person": p.uid}, w)
	var again := s.event({"type": "collected", "uid": 1, "kind": cid, "value": 4, "first": false, "person": p.uid}, w)
	assert_true(first.contains(cname) and first.contains("头一件"))
	assert_true(again.contains(cname) and again.contains("4") and not again.contains("头一件"))

func test_person_helpers():
	var w := _living()
	var s := ViewStrings.new(w.pack)
	var p: Person = w.people[0]
	assert_eq(s.person_name(p), p.family + p.given)
	p.age = 27.4
	p.track = ""
	assert_eq(s.person_line(p, w), "27 岁")
	p.track = w.pack.livelihoods.keys()[0]
	p.level = 0
	assert_eq(s.person_line(p, w), "27 岁 · " + str(w.pack.livelihoods[p.track]["levels"][0]["name"]))
	p.current = {}
	assert_eq(s.doing(p, w), "闲着")
	var aid: String = w.pack.actions.keys()[0]
	p.current = {"action": aid}
	assert_eq(s.doing(p, w), str(w.pack.actions[aid]["label"]))
	var st := p.status(w.pack)
	assert_eq(s.status_line(p, w), "、".join(st.values()))

func test_summary_lines():
	var w := _living()
	var s := ViewStrings.new(w.pack)
	var p: Person = w.people[0]
	var zero := {"simulated_seconds": 0, "capped": false, "years_passed": 0.0, "money_delta": 0, "deaths": [],
		"illnesses": [], "level_ups": [], "proposals_expired": 0, "proposals_waiting": 0, "goals_done": [],
		"messes_now": 0, "game_over": false}
	assert_eq(s.summary_lines(zero, w), [] as Array[String])
	var full := zero.duplicate(true)
	full.simulated_seconds = 3600 * 5
	full.capped = true
	full.years_passed = 2.6
	full.money_delta = 120
	full.deaths = [{"person": p.uid, "cause": "old_age"}]
	full.illnesses = [p.uid]
	full.level_ups = [{"person": p.uid, "level": 0}]
	full.proposals_expired = 2
	full.proposals_waiting = 1
	full.goals_done = [w.pack.goals.keys()[0]]
	full.messes_now = 3
	full.game_over = true
	var lines := s.summary_lines(full, w)
	var text := "\n".join(lines)
	assert_true(text.contains("5") and text.contains("48"))
	assert_true(text.contains("+120"))
	assert_true(text.contains("3 处要收拾") and text.contains("2 桩提亲过期") and text.contains("1 桩提亲在等"))
	assert_true(text.contains("没有人了"))
	assert_true(text.contains(p.given))
	assert_eq(lines.size(), 12)
	var neg := zero.duplicate()
	neg.money_delta = -30
	assert_true("\n".join(s.summary_lines(neg, w)).contains("-30"))

func test_broken_ui_json_records_error_and_uses_defaults():
	var s := ViewStrings.new(Pack.load_dir("res://tests/fixtures/bad_ui_pack"), "res://tests/fixtures/bad_ui_pack/ui.json")
	assert_true(s.errors.size() == 1, str(s.errors))
	assert_eq(s.t("btn.shop"), "商店")

func test_error_fills_placeholders():
	var s := ViewStrings.new(Pack.load_dir("res://packs/_smoke"))
	assert_eq(s.error("wrong_area", {"where": s.t("where.outdoor")}), "这东西得放在院里")
	assert_eq(s.error("busy", {"where": "x"}), "那儿有人在用")
	assert_eq(s.t("where.indoor"), "屋里")
