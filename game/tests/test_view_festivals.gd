extends TestCase
## Festivals and outings in the view: the festival board in the HUD, the toasts, the 出门
## list (button and drop on the gate), people out of sight while away, the market's
## festival goods and the away summary.

## 2026-01-01 08:00 UTC: the start of qijia's year (元宵 is minutes 6-18, 中秋 144-156).
var clk := {"unix": 1767254400.0, "offset": 0}
var n := 0


func _clock() -> Dictionary:
	return clk


func _main() -> Main:
	n += 1
	var d := "user://test_view_festivals_%d/" % n
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + f)
	var m := Main.create("qijia", d, _clock)
	Engine.get_main_loop().root.add_child(m)
	m.session.command({"type": "adopt"})
	m.tick(0.016)
	m.select(m.session.world.people[0].uid)
	m.tick(0.016)
	return m


func _done(m: Main) -> void:
	m.get_parent().remove_child(m)
	m.free()


## Runs the world to `minute` of the year (from 08:00) and lets the view catch up.
func _to_minute(m: Main, minute: float) -> void:
	var w := m.session.world
	w.advance(float(clk.unix) + minute * 60.0 - float(w.now))
	m.session._dispatch_events()
	m.tick(0.016)
	_clear_overlays(m)


## Reads away whatever card turned up meanwhile (a story fragment, a proposal), so the
## panels can open.
func _clear_overlays(m: Main) -> void:
	for i in 6:
		if m.overlays.current() == "":
			return
		var keys: Array = m.overlays._buttons.keys()
		m.overlays.press("btn.close" if keys.has("btn.close") else str(keys[0]))
		m.tick(0.016)


func test_the_festival_board_shows_the_festival_and_the_time_left():
	var m := _main()
	assert_eq(m.hud.festival_text(), "")
	_to_minute(m, 150)   # 中秋
	var t := m.hud.festival_text()
	assert_true(t.contains("八月十五 · 中秋"), t)
	assert_true(t.contains("还有 6 分钟"), t)
	_to_minute(m, 160)
	assert_eq(m.hud.festival_text(), "")
	_done(m)


func test_festivals_outings_and_remembering_are_toasts():
	var m := _main()
	_to_minute(m, 7)
	var start := str(m.session.pack.festivals["lantern"]["start_text"])
	assert_true(m.hud.toasts().has(start), str(m.hud.toasts()))
	assert_true(m.hud.notices().all(func(x): return str(x["text"]) != start), "a toast, not a notice")
	var s := m.session.strings
	var w := m.session.world
	var p: Person = w.people[0]
	var back := s.event({"type": "outing_back", "person": p.uid, "action": "go_to_market", "item": "",
		"text": "{name}回来就嚷嚷，集上的猪肉又涨了两文"}, w)
	assert_eq(back, s.person_name(p) + "回来就嚷嚷，集上的猪肉又涨了两文")
	var dead := TestKit.adult(w, 80.0)
	dead.given = "守拙"
	dead.family = "柳"
	w.kill_person(dead, "old_age")
	assert_true(s.event({"type": "mourned", "person": p.uid, "dead": dead.uid}, w).contains("柳守拙"))
	assert_eq(s.event({"type": "festival_ended", "festival": "lantern"}, w),
		str(w.pack.festivals["lantern"]["end_text"]))
	_done(m)


func test_the_go_out_button_lists_where_they_can_go_and_sends_them():
	var m := _main()
	_to_minute(m, 30)   # 08:30, the market is on
	var w := m.session.world
	var p: Person = w.people[0]
	var b := m.hud.button("go_out")
	assert_true(b != null and b.visible and not b.disabled)
	m.hud.press("go_out")
	assert_eq(m.panels.opened(), "go_out")
	var text := m.panels.text()
	assert_true(text.contains("挎着篮子出门赶集"), text)
	assert_true(text.find("挎着篮子出门赶集") < text.find("甩开竹竿蹲在河边钓鱼"), "outings first")
	assert_true(not text.contains("跟着人流去镇上看花灯"), "a festival's outing waits for it")
	m.panels.press("go:go_to_market")
	assert_eq(m.panels.opened(), "", "the list closes once they go")
	assert_true(OutingSystem.away(w, p))
	m.tick(0.016)
	assert_true(m.hud.button("go_out").disabled)
	assert_true(m.hud.bar_text().contains("出门去了"), m.hud.bar_text())
	# They walk to the gate, then the house no longer shows them.
	var pv: PersonView = m.house.people[p.uid]
	for i in 600:
		m.house.refresh()
		pv.tick(0.1)
		if not pv.visible:
			break
	assert_true(not pv.visible, "out of sight once at the gate")
	assert_true(not pv.hit(pv.position))
	# Back again: seen again.
	w.advance(AutonomySystem.duration_s(w, w.pack.actions["go_to_market"]))
	m.session._dispatch_events()
	m.tick(0.016)
	pv.tick(0.016)
	assert_true(pv.visible)
	_done(m)


func test_dropping_someone_on_the_gate_opens_the_list():
	var m := _main()
	var w := m.session.world
	var p: Person = w.people[0]
	var at := Vector2.INF
	var r: Dictionary = w.pack.rooms["gate"]
	for y in int(r["h"]):
		for x in int(r["w"]):
			var c := m.house.layout.cell_center("gate", x, y)
			var hit := m.house.pick(w, c)
			if at == Vector2.INF and str(hit.get("room", "")) == "gate" and not str(hit.get("kind", "")) in ["object", "mess", "collectible", "mark"]:
				at = c
	assert_true(at != Vector2.INF)
	m.drag.begin(p.uid)
	assert_eq(m.drag.drop(at), {})
	assert_eq(m.panels.opened(), "go_out")
	assert_eq(m.selected, p.uid)
	_done(m)


func test_festival_goods_are_greyed_out_of_season():
	var m := _main()
	var w := m.session.world
	w.money = 500
	m.panels.open("shop")
	m.panels.press("tab.items")   # 食物与药 holds the festival goods
	m.tick(0.016)
	assert_true(m.panels.has_button("buy:realgar_wine"))
	assert_true(m.panels.is_disabled("buy:realgar_wine"))
	assert_true(m.panels.text().contains(m.session.strings.t("shop.why.not_festival")), m.panels.text())
	assert_true(not m.panels.is_disabled("buy:rice"))
	m.panels.close()
	_to_minute(m, 84)   # 端午
	m.panels.open("shop")
	m.panels.press("tab.items")
	m.tick(0.016)
	assert_true(not m.panels.is_disabled("buy:realgar_wine"))
	_done(m)


func test_the_away_summary_names_festivals_and_who_came_back():
	var m := _main()
	var w := m.session.world
	var s := m.session.strings
	var lines := s.summary_lines({"festivals": ["mid_autumn", "new_year"],
		"outings": [{"person": w.people[0].uid, "action": "temple_fair", "item": "pinwheel",
			"text": "{name}举着纸风车跑进门，风车转得哗哗响"}]}, w)
	assert_true(lines.has(s.t("away.festival").replace("{name}", "中秋")), str(lines))
	assert_true(lines.has(s.person_name(w.people[0]) + "举着纸风车跑进门，风车转得哗哗响"), str(lines))
	for code in ["away", "closed", "not_festival"]:
		assert_true(ViewStrings.DEFAULTS.has("error." + code), code)
	_done(m)
