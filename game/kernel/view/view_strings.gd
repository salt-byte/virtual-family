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
	"idle": "闲着", "money": "钱 {n}", "years": "{n} 岁", "stock": "存货 {n}",
	"title.adopt": "领养一位", "title.proposal": "有人提亲", "title.over": "这一家到此为止",
	"title.away": "离开期间", "over.reason": "家里的人都已经过世了。",
	"over.carry": "房子和钱都还在，留给下一位来的人。", "title.pack_error": "主题包有错", "title.load_error": "存档读不出来",
	"tab.items": "货品", "tab.inventory": "家里存的", "tab.goals": "目标", "tab.collection": "收藏",
	"tab.furniture": "家具", "where.indoor": "屋里", "where.outdoor": "院里",
	"btn.confirm": "确定", "btn.cancel": "取消",
	"arrange.banner": "摆设中：点家具拿起，再点一下放下；点目录里的东西买下，点灰色的房间加盖；按住拖动能挪房子看别处；右键或 Esc 放回原处",
	"arrange.refund": "卖掉能回 {n}", "arrange.build": "加盖「{room}」，造价 {cost}，定了吗？",
	"set.flip": "昼夜颠倒", "set.speed": "调试快进",
	"set.clock": "家里现在是 {t}", "set.debug_note": "快进只为调试，正式版会去掉。",
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
	"error.no_place": "那地方还没有", "error.fixed": "这个挪不动",
	"error.no_track": "没有这一行", "error.weather": "这会儿的天气做不了这个",
	"sky": "{season} · {weather}", "error.same_track": "已经在做这一行了",
	"family.child": "还小", "family.job": "{job} · {level}", "btn.change_track": "改行",
	"title.change_track": "给{name}改行", "change.note": "改行要从头学起，眼下这一行的本事不留。",
	"change.option": "{job} · 从{level}做起 · 每日 {money}",
	"ev.took_up": "{name}长大成人，做起了{job}", "ev.changed_track": "{name}改行做{job}，从{level}学起",
	"ev.married_job": "{name}进了门，{job} · {level}",
	"gender.male": "男", "gender.female": "女", "label.likes": "喜欢", "label.dislikes": "厌恶",
	"label.savings": "带来 {n}", "load.backup": "旧存档会留一份备份，不会丢。",
	"load.corrupt": "存档坏了", "load.version": "存档是新版本存的，这个版本读不了",
	"load.pack_mismatch": "存档是另一个主题包的", "load.pack_changed": "主题包改过，旧存档对不上",
	"ev.fell_ill": "{name}看着不大对劲", "ev.cured": "{name}的病好了", "ev.level_up": "{name}成了{level}",
	"ev.married": "{name}进了门", "ev.died_old": "{name}寿终了", "ev.died_neglect": "{name}没能撑过去",
	"ev.proposal": "有人上门提亲", "ev.proposal_expired": "一桩提亲过期作罢了",
	"ev.goal": "达成「{text}」，得 {n}",
	"ev.collected_first": "捡到{thing}，头一件，收起来了", "ev.collected_paid": "捡到{thing}，卖了 {n}",
	"away.time": "你离开了 {h} 小时", "away.minutes": "你离开了 {m} 分钟", "away.capped": "（最多只补算 {h} 小时）", "away.years": "家里人长了 {y} 岁",
	"away.money": "钱 {n}", "away.died": "{name}寿终了", "away.ill": "{name}病过",
	"away.level": "{name}成了{level}", "away.goal": "达成「{text}」",
	"away.expired": "有 {n} 桩提亲过期作废了", "away.waiting": "有 {n} 桩提亲在等你回话",
	"away.messes": "屋里有 {n} 处要收拾", "away.over": "家里已经没有人了",
	"hint.drag": "把人拖到东西上，他就去用它；不拖的时候，他自己过日子",
	"error.keepsake": "这是旧物，不卖", "error.no_visitor": "门口已经没有人了",
	"mood.sad": "难过", "mood.depressed": "抑郁",
	"ev.mood_depressed": "{name}这几天闷闷不乐", "ev.mood_recovered": "{name}缓过来了",
	"ev.wish_formed": "{name}心里想着：{text}", "ev.wish_granted": "{name}如愿了：{text}",
	"ev.wish_expired": "{name}没等到：{text}",
	"wish.line": "心愿：{text}", "shop.wanted": "{name}想要", "thanks": "谢谢",
	"btn.stories": "旧事", "stories.locked": "……", "stories.none": "还没有翻出什么旧事。",
	"ev.fragment": "捡到了{name}", "ev.story_done": "「{title}」有了着落",
	"btn.receive": "收下", "visitor.money": "留下 {money}",
	"away.fragment": "捡到了{name}", "away.story_done": "「{title}」有了着落",
	"status.pregnant": "有了身孕", "months": "{n} 个月",
	"family.generation": "第{n}代", "numerals": "一,二,三,四,五,六,七,八,九,十",
	"family.spouse": "配偶 {name}", "family.parents": "父 {father} · 母 {mother}",
	"family.dead": "已故 · 享年 {n} 岁", "hint.no_bed": "床不够睡了，再添张床才好再要孩子",
	"ev.conceived": "{name}有了身孕", "ev.born.male": "添了个男孩，取名{name}",
	"ev.born.female": "添了个女孩，取名{name}", "ev.relative": "家里没了大人，{name}来照看孩子们",
	"title.born": "家里添了人", "born.parents": "{father}和{mother}的孩子", "title.relative": "来了一位亲戚",
	"away.born": "{name}出生了", "away.relative": "{name}来家里照看孩子", "proposal.for": "说给{name}",
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


## The text for a failure code; `vars` fills the {placeholders} some sentences have.
func error(code: String, vars := {}) -> String:
	var key := "error." + code
	if _over.has(key) or DEFAULTS.has(key):
		return t(key).format(vars)
	return "%s（%s）" % [t("error.unknown"), code]


func person_name(p: Person) -> String:
	return p.family + p.given


func _level_name(track: String, level: int) -> String:
	var levels: Array = pack.livelihoods.get(track, {}).get("levels", [])
	if level >= 0 and level < levels.size():
		return str(levels[level]["name"])
	return ""


## "{job} · {level}" for a person's livelihood; "" without one.
func job_line(p: Person) -> String:
	var job: Dictionary = pack.livelihoods.get(p.track, {})
	if job.is_empty():
		return ""
	return _f("family.job", {"job": str(job.get("name", "")), "level": _level_name(p.track, p.level)})


func _job_name(track: String) -> String:
	return str(pack.livelihoods.get(track, {}).get("name", ""))


func person_line(p: Person, world: World) -> String:
	var out := _f("months", {"n": int(p.age * 12.0)}) if p.age < 1.0 else _f("years", {"n": int(p.age)})
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
	if p.pregnant():
		words.append(t("status.pregnant"))
	if p.mood != "":
		words.append(t("mood." + p.mood))
	for word in p.status(world.pack).values():
		words.append(str(word))
	return "、".join(words)


func _name_of(uid: int, world: World) -> String:
	var p := world.person(uid)
	return person_name(p) if p != null else ""


## The season and weather now ("{season} · {weather}"; just the season before the first
## weather roll); "" for a pack without seasons.
func sky_line(world: World) -> String:
	if world == null or not WeatherSystem.enabled(world.pack):
		return ""
	var season := str(WeatherSystem.season_at(world.pack, world.now).get("name", ""))
	var wx := str(WeatherSystem.weather_entry(world.pack, world.weather).get("name", ""))
	if wx == "":
		return season
	return _f("sky", {"season": season, "weather": wx})


## The text of the wish `p` holds now; "" for none.
func wish_text(p: Person, world: World) -> String:
	return str(WishSystem.current(world, p).get("text", ""))


func _wish_line(key: String, e: Dictionary, world: World) -> String:
	var w: Dictionary = world.pack.wishes.get(str(e.get("wish", "")), {})
	return _f(key, {"name": _name_of(int(e["person"]), world), "text": str(w.get("text", ""))})


## The name of a thing lying about: a collectible, or a story fragment.
func thing_name(c: Dictionary, world: World) -> String:
	if c.has("story"):
		return str(StorySystem.fragment(world.pack, str(c["story"]), str(c["type"])).get("name", ""))
	return str(world.pack.collectibles.get(str(c.get("type", "")), {}).get("name", ""))


func story_title(sid: String, world: World) -> String:
	return str(world.pack.stories.get(sid, {}).get("title", ""))


## "第一代" for generation 0: the label of a generation (`family.generation` with the
## pack's `numerals` for the first ten, digits after that).
func generation_label(gen: int) -> String:
	var nums := t("numerals").split(",")
	var n := nums[gen] if gen >= 0 and gen < nums.size() else str(gen + 1)
	return _f("family.generation", {"n": n})


## The generation a person is shown under: a spouse who married in stands with their partner.
func shown_generation(p: Person, world: World) -> int:
	var g := p.generation
	var other := world.person(p.spouse) if p.spouse > 0 else null
	if other != null:
		g = maxi(g, other.generation)
	return g


## The sentence for a birth: the child's sex and name.
func born_line(child: Person) -> String:
	var key := "ev.born." + child.gender
	if not (_over.has(key) or DEFAULTS.has(key)):
		key = "ev.born.male"
	return _f(key, {"name": person_name(child)})


## One sentence for events worth telling the player; "" for the rest.
func event(e: Dictionary, world: World) -> String:
	match str(e.get("type", "")):
		"conceived":
			return _f("ev.conceived", {"name": _name_of(int(e["person"]), world)})
		"born":
			var child := world.person(int(e["person"]))
			return born_line(child) if child != null else ""
		"relative_arrived":
			return _f("ev.relative", {"name": _name_of(int(e["person"]), world)})
		"births_blocked":
			return t("hint.no_bed")
		"wish_formed":
			return _wish_line("ev.wish_formed", e, world)
		"wish_granted":
			return _wish_line("ev.wish_granted", e, world)
		"wish_expired":
			return _wish_line("ev.wish_expired", e, world)
		"mood_changed":
			if str(e["mood"]) == "depressed":
				return _f("ev.mood_depressed", {"name": _name_of(int(e["person"]), world)})
			if str(e["was"]) == "depressed":
				return _f("ev.mood_recovered", {"name": _name_of(int(e["person"]), world)})
			return ""
		"fragment_found":
			var f := StorySystem.fragment(world.pack, str(e["story"]), str(e["fragment"]))
			return _f("ev.fragment", {"name": str(f.get("name", ""))})
		"story_finale":
			return str(world.pack.stories.get(str(e["story"]), {}).get("finale", {}).get("hint", ""))
		"story_done":
			var done := str(world.pack.stories.get(str(e["story"]), {}).get("finale", {}).get("done_text", ""))
			return done if done != "" else _f("ev.story_done", {"title": story_title(str(e["story"]), world)})
		"fell_ill":
			return _f("ev.fell_ill", {"name": _name_of(int(e["person"]), world)})
		"cured":
			return _f("ev.cured", {"name": _name_of(int(e["person"]), world)})
		"level_up":
			return _f("ev.level_up", {"name": _name_of(int(e["person"]), world),
				"level": _level_name(str(e["track"]), int(e["level"]))})
		"married":
			var who := world.person(int(e["person"]))
			if who != null and job_line(who) != "":
				return _f("ev.married_job", {"name": person_name(who), "job": _job_name(who.track),
					"level": _level_name(who.track, who.level)})
			return _f("ev.married", {"name": _name_of(int(e["person"]), world)})
		"took_up":
			return _f("ev.took_up", {"name": _name_of(int(e["person"]), world), "job": _job_name(str(e["track"]))})
		"changed_track":
			return _f("ev.changed_track", {"name": _name_of(int(e["person"]), world),
				"job": _job_name(str(e["track"])), "level": _level_name(str(e["track"]), 0)})
		"person_died":
			var key := "ev.died_old" if str(e["cause"]) == "old_age" else "ev.died_neglect"
			return _f(key, {"name": _name_of(int(e["person"]), world)})
		"proposal_arrived":
			return t("ev.proposal")
		"proposal_expired":
			return t("ev.proposal_expired")
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
	if secs >= 3600.0:
		out.append(_f("away.time", {"h": _hours(secs / 3600.0)}))
	elif roundi(secs / 60.0) > 0:
		out.append(_f("away.minutes", {"m": roundi(secs / 60.0)}))
	if summary.get("capped", false):
		out.append(_f("away.capped", {"h": str(world.pack.cfg("offline_cap_hours"))}))
	var years := float(summary.get("years_passed", 0.0))
	if _hours(years) != "0":
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
	for f in summary.get("fragments", []):
		var frag := StorySystem.fragment(world.pack, str(f["story"]), str(f["fragment"]))
		out.append(_f("away.fragment", {"name": str(frag.get("name", ""))}))
	for sid in summary.get("stories_done", []):
		out.append(_f("away.story_done", {"title": story_title(str(sid), world)}))
	for uid in summary.get("births", []):
		out.append(_f("away.born", {"name": _name_of(int(uid), world)}))
	for uid in summary.get("relatives", []):
		out.append(_f("away.relative", {"name": _name_of(int(uid), world)}))
	if summary.get("game_over", false):
		out.append(t("away.over"))
	return out
