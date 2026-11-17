class_name ViewStrings
extends RefCounted
## UI text table. Defaults are generic words; a pack may override any key with a flat
## `ui.json` ({"key": "text"}) in its directory. Never reveals illness names: view code
## must never read the illness field of a person.

const DEFAULTS := {
	"btn.praise": "赏", "btn.scold": "罚", "btn.family": "家人", "btn.shop": "商店", "btn.ledger": "目标",
	"btn.arrange": "摆设", "btn.adopt": "领养", "btn.reroll": "换一位", "btn.accept": "应下",
	"btn.decline": "回绝", "btn.close": "关闭", "btn.buy": "买", "btn.use_on": "给{name}用",
	"btn.sell": "卖掉", "btn.build": "加盖", "btn.new_game": "新开一局", "btn.settings": "设置",
	"idle": "闲着", "money": "{n} 文", "years": "{n} 岁", "stock": "存粮 {n}",
	"title.adopt": "领养一位", "title.proposal": "有人提亲", "title.over": "这一家到此为止",
	"title.away": "离开期间", "title.pack_error": "主题包有错", "title.load_error": "存档读不出来",
	"tab.items": "货品", "tab.inventory": "家里存的", "tab.goals": "目标", "tab.collection": "收藏",
	"tab.furniture": "家具",
	"set.flip": "昼夜颠倒", "set.speed": "调试快进",
	"error.busy": "那儿有人在用", "error.stage": "这个年纪做不了", "error.no_money": "钱不够",
	"error.wrong_track": "这不是他的营生", "error.no_stock": "家里没存货了", "error.no_target": "没有可收拾的",
	"error.requires": "他现在做不了这个", "error.dead": "人已经不在了", "error.no_object": "那儿没有东西",
	"error.no_action": "这东西他用不上", "error.annoyed": "夸得太勤，他烦了",
	"error.nothing_to_judge": "他这会儿没在做事", "error.not_praiseable": "这事没法赏罚",
	"error.wrong_medicine": "药不对症，白吃了", "error.no_item": "手头没有这样东西", "error.bad_qty": "数量不对",
	"error.out_of_bounds": "放不下，出界了", "error.overlap": "那儿已经有东西了",
	"error.wrong_area": "这东西得放在{where}", "error.room_not_built": "那间还没盖",
	"error.already_built": "已经盖过了", "error.no_room": "没有这间房", "error.no_object_type": "没有这种东西",
	"error.no_person": "没有这个人", "error.no_proposal": "这门亲事已经作罢", "error.not_adopting": "现在不是领养的时候",
	"error.not_running": "现在做不了", "error.unknown_command": "做不了", "error.unknown": "做不了",
	"gender.male": "男", "gender.female": "女", "label.likes": "喜欢", "label.dislikes": "厌恶",
	"label.savings": "带来 {n}", "load.backup": "旧存档会留一份备份，不会丢。",
	"load.corrupt": "存档坏了", "load.version": "存档是新版本存的，这个版本读不了",
	"load.pack_mismatch": "存档是另一个主题包的", "load.pack_changed": "主题包改过，旧存档对不上",
	"ev.fell_ill": "{name}看着不大对劲", "ev.cured": "{name}的病好了", "ev.level_up": "{name}成了{level}",
	"ev.married": "{name}进了门", "ev.died_old": "{name}寿终了", "ev.died_neglect": "{name}没能撑过去",
	"ev.proposal": "有人上门提亲", "ev.goal": "达成「{text}」，得 {n} 文",
	"ev.collected_first": "捡到{thing}，头一件，收起来了", "ev.collected_paid": "捡到{thing}，卖了 {n} 文",
	"away.time": "你离开了 {h} 小时", "away.capped": "（最多只补算 {h} 小时）", "away.years": "家里人长了 {y} 岁",
	"away.money": "钱 {n} 文", "away.died": "{name}寿终了", "away.ill": "{name}病过",
	"away.level": "{name}成了{level}", "away.goal": "达成「{text}」",
	"away.expired": "有 {n} 桩提亲过期作废了", "away.waiting": "有 {n} 桩提亲在等你回话",
	"away.messes": "屋里有 {n} 处要收拾", "away.over": "家里已经没有人了",
}

var pack: Pack
## Problems found while reading ui.json (bad JSON, not an object, non-string values).
var errors: Array[String] = []
var _over := {}


## `ui_path` overrides the default location res://packs/<pack.id>/ui.json (used by tests).
func _init(p: Pack, ui_path := "") -> void:
	pack = p
	var path := ui_path
	if path == "":
		if p == null or p.id == "":
			return
		path = "res://packs/%s/ui.json" % p.id
	if not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("ui.json: invalid JSON (line %d): %s" % [parser.get_error_line(), parser.get_error_message()])
		return
	if not parser.data is Dictionary:
		errors.append("ui.json: must be a JSON object")
		return
	for k in parser.data:
		if parser.data[k] is String:
			_over[str(k)] = parser.data[k]
		else:
			errors.append("ui.json: %s: value must be a string" % k)


func t(key: String) -> String:
	if _over.has(key):
		return _over[key]
	return DEFAULTS.get(key, key)


func _f(key: String, vars: Dictionary) -> String:
	return t(key).format(vars)


func error(code: String) -> String:
	var key := "error." + code
	if _over.has(key) or DEFAULTS.has(key):
		return t(key)
	return "%s（%s）" % [t("error.unknown"), code]


func person_name(p: Person) -> String:
	return p.family + p.given


func _level_name(track: String, level: int) -> String:
	var levels: Array = pack.livelihoods.get(track, {}).get("levels", [])
	if level >= 0 and level < levels.size():
		return str(levels[level]["name"])
	return ""


func person_line(p: Person, world: World) -> String:
	var out := "%d 岁" % int(p.age)
	var lv := _level_name(p.track, p.level) if p.track != "" else ""
	if lv != "":
		out += " · " + lv
	return out


func doing(p: Person, world: World) -> String:
	var aid := str(p.current.get("action", "")) if not p.current.is_empty() else ""
	if aid != "" and world.pack.actions.has(aid):
		return str(world.pack.actions[aid]["label"])
	return t("idle")


func status_line(p: Person, world: World) -> String:
	var words: Array[String] = []
	for word in p.status(world.pack).values():
		words.append(str(word))
	return "、".join(words)


func _name_of(uid: int, world: World) -> String:
	var p := world.person(uid)
	return person_name(p) if p != null else ""


## One sentence for events worth telling the player; "" for the rest.
func event(e: Dictionary, world: World) -> String:
	match str(e.get("type", "")):
		"fell_ill":
			return _f("ev.fell_ill", {"name": _name_of(int(e["person"]), world)})
		"cured":
			return _f("ev.cured", {"name": _name_of(int(e["person"]), world)})
		"level_up":
			return _f("ev.level_up", {"name": _name_of(int(e["person"]), world),
				"level": _level_name(str(e["track"]), int(e["level"]))})
		"married":
			return _f("ev.married", {"name": _name_of(int(e["person"]), world)})
		"person_died":
			var key := "ev.died_old" if str(e["cause"]) == "old_age" else "ev.died_neglect"
			return _f(key, {"name": _name_of(int(e["person"]), world)})
		"proposal_arrived":
			return t("ev.proposal")
		"goal_done":
			var g: Dictionary = world.pack.goals.get(str(e["goal"]), {})
			return _f("ev.goal", {"text": str(g.get("text", "")), "n": int(e["reward"])})
		"collected":
			var c: Dictionary = world.pack.collectibles.get(str(e["kind"]), {})
			var thing := str(c.get("name", ""))
			if e.get("first", false):
				return _f("ev.collected_first", {"thing": thing})
			return _f("ev.collected_paid", {"thing": thing, "n": int(e["value"])})
	return ""


func _hours(x: float) -> String:
	var r := snappedf(x, 0.1)
	return str(int(r)) if is_equal_approx(r, roundf(r)) else "%.1f" % r


func summary_lines(summary: Dictionary, world: World) -> Array[String]:
	var out: Array[String] = []
	var secs := float(summary.get("simulated_seconds", 0))
	if secs > 0.0:
		out.append(_f("away.time", {"h": _hours(secs / 3600.0)}))
	if summary.get("capped", false):
		out.append(_f("away.capped", {"h": str(world.pack.cfg("offline_cap_hours"))}))
	var years := float(summary.get("years_passed", 0.0))
	if years > 0.0:
		out.append(_f("away.years", {"y": _hours(years)}))
	var money := int(summary.get("money_delta", 0))
	if money != 0:
		out.append(_f("away.money", {"n": "%+d" % money}))
	for d in summary.get("deaths", []):
		out.append(_f("away.died", {"name": _name_of(int(d["person"]), world)}))
	for uid in summary.get("illnesses", []):
		out.append(_f("away.ill", {"name": _name_of(int(uid), world)}))
	for l in summary.get("level_ups", []):
		var p := world.person(int(l["person"]))
		var lv := _level_name(p.track, int(l["level"])) if p != null else ""
		out.append(_f("away.level", {"name": _name_of(int(l["person"]), world), "level": lv}))
	for gid in summary.get("goals_done", []):
		out.append(_f("away.goal", {"text": str(world.pack.goals.get(str(gid), {}).get("text", ""))}))
	var expired := int(summary.get("proposals_expired", 0))
	if expired > 0:
		out.append(_f("away.expired", {"n": expired}))
	var waiting := int(summary.get("proposals_waiting", 0))
	if waiting > 0:
		out.append(_f("away.waiting", {"n": waiting}))
	var messes := int(summary.get("messes_now", 0))
	if messes > 0:
		out.append(_f("away.messes", {"n": messes}))
	if summary.get("game_over", false):
		out.append(t("away.over"))
	return out
