# 白盒画面（第 1 期的画面部分）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给已有的模拟内核接上一层色块画面，让雨蝶能在电脑上亲手玩完第 1 期那一圈：领养一个人 → 看他自己过日子 → 拖他去做事、赏罚 → 买米买药 → 收拾屋子 → 买家具摆放、加盖厢房 → 媒人上门成亲 → 离开再回来看"离开期间"小结。

**Architecture:** 画面层放在 `game/kernel/view/`，和内核一样不含题材词，界面文字的默认值是通用词，主题包可用 `ui.json` 覆盖。三块不依赖节点树的纯逻辑先做、先测：`ViewStrings`（文字表）、`HouseLayout`（格子与屏幕坐标换算、点选）、`GameSession`（持有 `World`，管时钟、存读档、设置，把事件转成信号）。节点一律用代码搭（不手写 `.tscn`，只有一个空壳 `main.tscn`），每个节点都有可被测试直接调用的 `refresh()` / `tick(delta)`，`_process` 只负责调它们。画面只通过 `World.sync / command / drain_events`、`SaveStore` 和只读字段与内核打交道。

**Tech Stack:** Godot 4.7.2、GDScript、JSON；沿用 `game/tests/` 的测试运行器，`./game/tests/run.sh [filter]`。

**Spec:** `docs/superpowers/specs/2026-11-17-lifesim-kernel-design.md`（5.1、5.3、5.5、第 9 节第 1 期、12b 第 1–7 和 14 条）。另读 `docs/superpowers/plans/2026-11-17-sim-layer-followups.md` 的"画面层必须知道的"。

**不在本计划内：** 美术和动画（第 5 期）、生育继承（第 2 期）、家业阶梯和其余营生（第 3 期）、换地面墙面、手机触摸适配、声音。

## Global Constraints

- Godot 4.7.2，GDScript。`game/kernel/sim/` 的约束不变（`RefCounted`、不读系统时钟、不含题材词）
- `game/kernel/view/` 下不得出现主题包 id 和题材专用词（"灶台""科举""侯府""集市""账房""家谱"等）；这些只能出现在 `game/packs/qijia/ui.json`
- 画面层**不改** `World` 的任何字段，只调 `sync`、`command`、`drain_events`、`SaveStore.save/load`，以及只读的静态查询（`HouseSystem.can_place`、`Person.status`、`Person.stage`、`Person.from_dict`）
- **先 `sync` 再发任何指令**；每帧 `sync` 一次，返回的小结 `simulated_seconds > 0` 就要展示
- 画面读活字段，不读 `to_dict()`；`world.candidate` 和提亲里的 `person` 是存档格式的字典，要显示先 `Person.from_dict(...)`
- **病名永不显示**：`game/kernel/view/` 里不得读取 `.illness`；玩家只能从小人头顶的行为文字（症状行为）认病
- 界面只占底部一条和左上角两个按钮，其余都是弹出面板，关掉就回到看房子；窗口 1280×720，横屏，鼠标操作。鼠标事件统一经 `InputEventMouseButton` / `InputEventMouseMotion` 处理，不写只能鼠标才走得通的逻辑（方便以后加触摸）
- 玩家看到的是词语阶梯（`Person.status`），不显示数值条
- 色块长相全部自己定：矩形加文字，不照搬参考游戏的界面长相、图标、配色
- 所有新代码过 `./game/tests/run.sh`，输出无 ERROR / WARNING；`_smoke` 和 `qijia` 两个包都要能进画面
- 提交信息末尾加 `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`（子 agent 写自己的模型名）；只在本地提交，不推送

## Review Focus

1. **存档读不出来**（损坏、版本不认识、主题包改过）：不崩、不静默覆盖；提示原因，玩家点"新开一局"后旧文件改名留底。→ Task 5、Task 9
2. **电脑合盖或切走标签页几小时后回来**：下一帧 `sync` 走离线补算，弹"离开期间"小结；期间排队的提亲还在。→ Task 5、Task 9
3. **拖着小人时他去世了，或拖着家具时用它的人换了事**：拖动安静地取消，不留悬空节点、不报错。→ Task 8、Task 11
4. **钱不够、位置不合适、东西被占着**：指令返回 `ok=false` 时给一句看得懂的话，状态不变；每个内核错误码都有对应文字。→ Task 3、Task 7
5. **调试快进之后重开游戏**：游戏钟比真实钟快，重开后不能卡住不走。时钟偏移存进设置文件。→ Task 5、Task 12

---

## 文件结构

```
game/
  project.godot                      # 改：窗口、主场景
  main.tscn                          # 空壳，根节点挂 kernel/view/main.gd
  kernel/sim/…                       # Task 1、2 小改
  kernel/view/
    view_strings.gd    ViewStrings   # 文字表：默认值 + 主题包 ui.json 覆盖
    house_layout.gd    HouseLayout   # 房间排布、格子↔屏幕、点选（纯逻辑）
    game_session.gd    GameSession   # World + 时钟 + 存读档 + 设置 + 信号（纯逻辑）
    main.gd            Main          # 根节点：建 session，装配下面各块
    house_view.gd      HouseView     # 画房间、家具、脏乱、掉落物；平移；昼夜
    person_view.gd     PersonView    # 一个小人：色块、名字、头顶一句话、走路
    drag_controller.gd DragController# 拖小人
    hud.gd             Hud           # 底部条、赏罚按钮、提示条
    overlays.gd        Overlays      # 领养、提亲、结束、包出错、读档出错、离开小结
    panels.gd          Panels        # 商店、目标与收藏、家人
    arrange_mode.gd    ArrangeMode   # 买、摆、挪、卖家具；加盖房间
    settings_panel.gd  SettingsPanel # 昼夜颠倒、调试快进
  packs/qijia/ui.json                # 《起家》的界面用词
  tests/test_view_*.gd
  export_presets.cfg                 # Task 12
README.md                            # Task 12：怎么跑
```

测试里拿场景树：`Engine.get_main_loop().root`。测试建的节点用完 `free()`。测试不等帧，直接调 `refresh()` / `tick()`。

---

### Task 1: 内核补漏——事件带种类、掉落物带房间

画面要知道"多了什么脏乱""捡到了什么""掉在哪个院子"。现在 `World.emit` 合并数据时事件名占了 `type` 键，这三类事件的种类被丢掉；掉落物没记房间。

**Files:**
- Modify: `game/kernel/sim/mess_system.gd`、`collectible_system.gd`、`world_save.gd`、`game/tools/diary_cli.gd`
- Test: `game/tests/test_events.gd`、`test_collect_goals.gd`、`test_save.gd`

**Interfaces:**
- Produces: 事件 `mess_spawned{uid, kind, room}`、`collectible_spawned{uid, kind, room}`、`collected{uid, kind, value, first, person}`；`world.collectibles` 每项多一个 `room: String`

- [ ] **Step 1: 写失败的测试**

```gdscript
# test_events.gd
func test_spawn_and_collect_events_name_the_kind():
	var w := TestKit.world()
	var p := TestKit.adult(w)
	var m := MessSystem.spawn(w, w.pack.mess_types.keys()[0])
	var c := CollectibleSystem.spawn(w, w.pack.collectibles.keys()[0])
	CollectibleSystem.collect(w, p, c)
	var by := {}
	for e in w.drain_events():
		by[e.type] = e
	assert_eq(by["mess_spawned"].kind, w.pack.mess_types.keys()[0])
	assert_eq(by["collectible_spawned"].kind, w.pack.collectibles.keys()[0])
	assert_eq(by["collected"].kind, w.pack.collectibles.keys()[0])
	assert_eq(by["collected"].person, p.uid)
	assert_true(m > 0)

# test_collect_goals.gd
func test_collectible_remembers_its_outdoor_room():
	var w := TestKit.world()
	var uid := CollectibleSystem.spawn(w)
	var c := CollectibleSystem.find(w, uid)
	assert_true(w.rooms_built.has(c["room"]))
	assert_true(bool(w.pack.rooms[c["room"]]["outdoor"]))
```

`test_save.gd` 加一条：存档里的掉落物缺 `room`、或 `room` 不是已知房间时，`from_dict` 返回 null（照 `test_missing_room_in_placed_entries_is_rejected` 的写法）。

- [ ] **Step 2: 跑 `./game/tests/run.sh test_events` 等，确认新测试失败**
- [ ] **Step 3: 实现。** 三处 `emit` 的 `"type"` 改成 `"kind"`，`collected` 加 `person`；掉落物记下抽到的房间 id；`world_save.gd` 的掉落物校验改成要求 `room`（把 `_valid_placed(d["collectibles"], false, …)` 的 false 改成要求房间）。`SAVE_VERSION` 不变（还没有流出去的存档）。`diary_cli.gd` 改成打印脏乱名和掉落物名
- [ ] **Step 4: 跑全量 `./game/tests/run.sh`，全过**
- [ ] **Step 5: Commit** `fix: spawn and collect events carry kind; collectibles remember their room`

---

### Task 2: 内核补漏——家具可多人同用、不连着做同一件事

日记里暴露的两个编排毛病：夫妻共用一张炕，一人睡着另一人整夜没处睡；同一件事连做三四遍。

**Files:**
- Modify: `game/kernel/sim/pack.gd`、`pack_validator.gd`、`autonomy_system.gd`、`game/packs/qijia/objects.json`、`game/packs/_smoke/objects.json`
- Test: `game/tests/test_autonomy.gd`、`test_pack.gd`、`test_packs_both.gd`

**Interfaces:**
- Produces: 物件类型字段 `capacity: int`（默认 1，整数，≥1）；配置项 `repeat_factor: float`（默认 0.3，范围 (0, 1]）。`AutonomySystem._occupied` 改为"其他使用者人数 ≥ capacity"

- [ ] **Step 1: 写失败的测试**

```gdscript
# test_autonomy.gd
func test_object_with_capacity_two_takes_two_people():
	var w := TestKit.world()
	var a := TestKit.adult(w)
	var b := TestKit.adult(w)
	var c := TestKit.adult(w)
	var type := str(w.pack.actions["sleep"]["object"])
	w.pack.object_types[type]["capacity"] = 2
	var uid := w.add_object(type, w.rooms_built[0], 0, 0)
	AutonomySystem.start(w, a, "sleep", uid)
	assert_eq(AutonomySystem.can_do(w, b, "sleep", uid), "")
	AutonomySystem.start(w, b, "sleep", uid)
	assert_eq(AutonomySystem.can_do(w, c, "sleep", uid), "busy")

func test_just_finished_action_scores_lower():
	var w := TestKit.world()
	var p := TestKit.adult(w)
	var a: Dictionary = w.pack.actions[w.pack.actions.keys()[0]]
	var fresh := AutonomySystem._score(w, p, a)
	p.last_action = str(a["id"])
	assert_near(AutonomySystem._score(w, p, a), fresh * 0.3)
```

`test_pack.gd`：`capacity` 为 0 或 1.5 时报错并指出 `objects.json` 和条目 id；`repeat_factor` 为 0 或 1.5 时报错。
`test_packs_both.gd`：qijia 里两个成年人、一张炕，从 21:00 推进 3 小时后两人都在做 `sleep`（先把两人 `energy` 设到 20）。

- [ ] **Step 2: 跑测试确认失败**
- [ ] **Step 3: 实现。** `ENTRY_DEFAULTS.object_types` 加 `capacity: 1`，进 `INT_FIELDS`；`DEFAULT_CONFIG` 加 `repeat_factor: 0.3`；校验两者；`_occupied` 数人头；`_score` 末尾在 `a["id"] == p.last_action` 时乘 `repeat_factor`。qijia 的 `kang` 设 `capacity: 2`
- [ ] **Step 4: 跑全量测试；再跑 `cd game && godot --headless -s res://tools/diary_cli.gd -- qijia 2 7`，确认夜里两人都上炕、不再连着三遍同一件事**。把这段日记的夜间部分贴进报告
- [ ] **Step 5: Commit** `feat: object capacity and anti-repeat scoring`

---

### Task 3: 界面文字表

**Files:**
- Create: `game/kernel/view/view_strings.gd`、`game/packs/qijia/ui.json`
- Test: `game/tests/test_view_strings.gd`；Modify: `game/tests/test_kernel_purity.gd`

**Interfaces:**
- Produces:
  - `ViewStrings.new(pack: Pack)`；读 `res://packs/<pack.id>/ui.json`（可没有；格式错了记进 `errors: Array[String]`，不崩，用默认值）
  - `t(key: String) -> String`：有覆盖用覆盖，否则默认值，都没有返回 key 本身
  - `error(code: String) -> String`：等于 `t("error." + code)`，没有则返回 `t("error.unknown")` 加括号里的 code
  - `event(e: Dictionary, world: World) -> String`：把一条事件写成一句提示，不需要提示的事件返回 `""`
  - `person_name(p: Person) -> String`（姓加名）、`person_line(p: Person, world: World) -> String`（"27 岁 · 蒙童"，无营生只写年岁）、`doing(p: Person, world: World) -> String`（当前行为的 `label`，没有则 `t("idle")`）、`status_line(p: Person, world: World) -> String`（`Person.status` 的词用顿号连起来）
  - `summary_lines(summary: Dictionary, world: World) -> Array[String]`：离开小结逐行

默认键和默认值（中文通用词）：

```
btn.praise 赏   btn.scold 罚   btn.family 家人   btn.shop 商店   btn.ledger 目标   btn.arrange 摆设
btn.adopt 领养   btn.reroll 换一位   btn.accept 应下   btn.decline 回绝   btn.close 关闭
btn.buy 买   btn.use_on 给{name}用   btn.sell 卖掉   btn.build 加盖   btn.new_game 新开一局   btn.settings 设置
idle 闲着   money {n} 文   years {n} 岁   stock 存粮 {n}
title.adopt 领养一位   title.proposal 有人提亲   title.over 这一家到此为止   title.away 离开期间
title.pack_error 主题包有错   title.load_error 存档读不出来
tab.items 货品   tab.inventory 家里存的   tab.goals 目标   tab.collection 收藏   tab.furniture 家具
set.flip 昼夜颠倒   set.speed 调试快进
error.busy 那儿有人在用   error.stage 这个年纪做不了   error.no_money 钱不够   error.wrong_track 这不是他的营生
error.no_stock 家里没存货了   error.no_target 没有可收拾的   error.requires 他现在做不了这个   error.dead 人已经不在了
error.no_object 那儿没有东西   error.no_action 这东西他用不上   error.annoyed 夸得太勤，他烦了   error.nothing_to_judge 他这会儿没在做事
error.not_praiseable 这事没法赏罚   error.wrong_medicine 药不对症，白吃了   error.no_item 手头没有这样东西   error.bad_qty 数量不对
error.out_of_bounds 放不下，出界了   error.overlap 那儿已经有东西了   error.wrong_area 这东西得放在{where}   error.room_not_built 那间还没盖
error.already_built 已经盖过了   error.no_room 没有这间房   error.no_object_type 没有这种东西   error.no_person 没有这个人
error.no_proposal 这门亲事已经作罢   error.not_adopting 现在不是领养的时候   error.not_running 现在做不了   error.unknown_command 做不了   error.unknown 做不了
load.corrupt 存档坏了   load.version 存档是新版本存的，这个版本读不了   load.pack_mismatch 存档是另一个主题包的   load.pack_changed 主题包改过，旧存档对不上
ev.fell_ill {name}看着不大对劲   ev.cured {name}的病好了   ev.level_up {name}成了{level}   ev.married {name}进了门
ev.died_old {name}寿终了   ev.died_neglect {name}没能撑过去   ev.proposal 有人上门提亲   ev.goal 达成「{text}」，得 {n} 文
ev.collected_first 捡到{thing}，头一件，收起来了   ev.collected_paid 捡到{thing}，卖了 {n} 文
away.time 你离开了 {h} 小时   away.capped （最多只补算 {h} 小时）   away.years 家里人长了 {y} 岁   away.money 钱 {n} 文
away.died {name}寿终了   away.ill {name}病过   away.level {name}成了{level}   away.goal 达成「{text}」
away.expired 有 {n} 桩提亲过期作废了   away.waiting 有 {n} 桩提亲在等你回话   away.messes 屋里有 {n} 处要收拾   away.over 家里已经没有人了
```

`ui.json` 是一层扁平的 `{"键": "文字"}`。qijia 的：`btn.family 家谱`、`btn.shop 集市`、`btn.ledger 账房`、`btn.adopt 收留`、`title.adopt 收留一位落脚的人`、`title.proposal 媒人上门`。

- [ ] **Step 1: 写失败的测试**

```gdscript
func test_default_and_override():
	var s := ViewStrings.new(Pack.load_dir("res://packs/_smoke"))
	assert_eq(s.t("btn.shop"), "商店")
	var q := ViewStrings.new(Pack.load_dir("res://packs/qijia"))
	assert_eq(q.t("btn.shop"), "集市")
	assert_eq(q.t("no.such.key"), "no.such.key")

func test_every_kernel_error_code_has_text():
	var re := RegEx.create_from_string('(?:fail\\(|return )"([a-z_]+)"')
	var s := ViewStrings.new(Pack.load_dir("res://packs/_smoke"))
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
	var w := BalanceRun.setup("qijia", 1)
	var p := w.people[0]
	IllnessSystem.infect(w, p, "chill")
	var s := ViewStrings.new(w.pack)
	var line := ""
	for e in w.drain_events():
		if e.type == "fell_ill":
			line = s.event(e, w)
	assert_true(line.contains(p.given))
	for id in w.pack.illnesses:
		assert_true(not line.contains(str(w.pack.illnesses[id]["name"])))
```

另加：`event` 对 `action_started`、`income`、`mess_spawned` 返回 `""`；`goal_done` 的句子含目标的 `text` 和奖励数；`collected` 首件和重复件两种句子；`summary_lines` 对零小结返回空数组，对一份填满的小结逐项有行、`capped` 时带上限那行；坏的 `ui.json`（在 `tests/fixtures/` 下加一个只为此用的包）记错不崩。

`test_kernel_purity.gd` 加一条：`res://kernel/view/*.gd` 里不含 `["qijia", "_smoke", "灶台", "科举", "侯府", "集市", "账房", "家谱", "媒人", ".illness"]`。

- [ ] **Step 2: 跑 `./game/tests/run.sh test_view_strings`，确认失败**
- [ ] **Step 3: 实现 `ViewStrings`**（`DEFAULTS` 是一个 const 字典；`{name}` 这类占位用 `String.format`）
- [ ] **Step 4: 跑全量测试**
- [ ] **Step 5: Commit** `feat(view): string table with pack overrides`

---

### Task 4: 房屋排布与坐标换算

**Files:**
- Create: `game/kernel/view/house_layout.gd`
- Test: `game/tests/test_view_layout.gd`

**Interfaces:**
- Consumes: `world.pack.rooms`（`w`、`h`、`outdoor`）、`world.rooms_built`、`world.objects`、`world.messes`、`world.collectibles`
- Produces（`class_name HouseLayout extends RefCounted`）：
  - 常量 `CELL := Vector2(48, 36)`（格子比宽矮，表示斜俯视）、`GAP := 48.0`、`WALL := 30.0`（室内房间上沿的墙高）
  - `HouseLayout.new(pack: Pack)`：**所有**房间（含未盖的）按主题包顺序从左到右排，底边对齐，间隔 `GAP`；原点在第一间房的左上角
  - `room_rect(room: String) -> Rect2`、`bounds() -> Rect2`（含墙）
  - `cell_to_pos(room, x, y) -> Vector2`（格子左上角）、`cell_center(room, x, y) -> Vector2`
  - `pos_to_cell(pos: Vector2) -> Dictionary`：`{room, x, y}`，不在任何房间里时 `{}`
  - `object_rect(o: Dictionary, pack: Pack) -> Rect2`
  - `stand_pos(o: Dictionary, pack: Pack) -> Vector2`：用这件家具时人站的位置——家具下沿正中往下半格，若出了房间则取家具中心
  - `pick(world: World, pos: Vector2) -> Dictionary`：`{kind: "object"|"mess"|"collectible"|"room"|"", uid, room}`；优先级 掉落物 > 脏乱 > 家具 > 房间；只在已盖的房间里点得中家具和杂物，未盖的房间只返回 `room`

- [ ] **Step 1: 写失败的测试**（用 qijia：堂屋 8×6、厢房 5×4、院子 9×6）

```gdscript
func test_rooms_sit_left_to_right_bottom_aligned():
	var l := HouseLayout.new(Pack.load_dir("res://packs/qijia"))
	assert_eq(l.room_rect("hall"), Rect2(0, 0, 384, 216))
	assert_eq(l.room_rect("side"), Rect2(432, 72, 240, 144))
	assert_eq(l.room_rect("yard").position.x, 720.0)

func test_cell_roundtrip_and_outside():
	var l := HouseLayout.new(Pack.load_dir("res://packs/qijia"))
	assert_eq(l.pos_to_cell(l.cell_center("yard", 8, 5)), {"room": "yard", "x": 8, "y": 5})
	assert_eq(l.pos_to_cell(Vector2(400, 10)), {})

func test_pick_priority_and_unbuilt_room():
	var w := BalanceRun.setup("qijia", 1)
	var l := HouseLayout.new(w.pack)
	var o: Dictionary = w.objects[0]
	var at := l.object_rect(o, w.pack).get_center()
	assert_eq(l.pick(w, at).kind, "object")
	w.messes.append({"uid": 9001, "type": "dirt", "room": o.room, "x": o.x, "y": o.y})
	assert_eq(l.pick(w, l.cell_center(o.room, o.x, o.y)).uid, 9001)
	assert_eq(l.pick(w, l.room_rect("side").get_center()), {"kind": "room", "uid": -1, "room": "side"})
	assert_eq(l.pick(w, Vector2(-500, -500)).kind, "")
```

另加：`stand_pos` 在家具贴房间下沿时落回家具中心；`bounds()` 包住所有房间和墙。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: Commit** `feat(view): house layout and hit testing`

---

### Task 5: GameSession——时钟、存读档、设置

**Files:**
- Create: `game/kernel/view/game_session.gd`
- Test: `game/tests/test_view_session.gd`

**Interfaces:**
- Produces（`class_name GameSession extends RefCounted`）：
  - 信号 `event(e: Dictionary)`、`command_failed(code: String)`、`away(summary: Dictionary)`、`changed()`（任何一步之后发一次，面板据此刷新）
  - 字段 `world: World`、`pack: Pack`、`strings: ViewStrings`、`load_error := ""`、`settings := {"flip_day_night": false, "clock_skew": 0, "speed": 1}`
  - `GameSession.new(pack_id: String, dir := "user://", real_clock := Callable())`：`real_clock` 返回 `{unix: float, offset: int}`，空则用系统钟（`Time.get_unix_time_from_system()`、`Time.get_time_zone_from_system().bias * 60`）。读 `dir + "settings.json"`（没有或坏了用默认值）
  - `start() -> void`：主题包无效 → `world` 是 invalid 的世界，不读档；否则 `SaveStore.load(pack, save_path())`：`missing` → 新世界（种子取当前 unix）；成功 → 用读到的世界；其他错误 → `load_error` 记错误码，`world = null`，**不动存档文件**
  - `new_game() -> void`：存档文件存在则改名为 `save_path() + ".bad"`（已有同名先删），再建新世界，清 `load_error`
  - `save_path() -> String`：`dir + "save_<pack.id>.json"`
  - `now_unix() -> int`：真实 unix + `settings.clock_skew`；`utc_offset() -> int`：真实偏移，`flip_day_night` 时加 43200
  - `tick(delta: float) -> void`：`world` 为空或 invalid 时什么也不做。`speed > 1` 时把 `(speed - 1) * delta` 累进 `clock_skew`（内部用浮点累加，存整数）。调 `world.sync(now_unix(), utc_offset())`；小结 `simulated_seconds > 0` 时发 `away`；把 `drain_events()` 逐条发 `event`；发 `changed`。每累计 30 秒真实时间 `save()` 一次
  - `command(cmd: Dictionary) -> Dictionary`：先 `sync` 再 `world.command`，失败发 `command_failed(error)`，之后照 `tick` 的方式派发事件并发 `changed`；返回结果
  - `save() -> bool`（世界处于 living / adopting / over 时写；同时写设置）、`set_setting(key, value) -> void`（立即写设置文件）
- Consumes: `World.sync`、`SaveStore.save/load`、`ViewStrings`

- [ ] **Step 1: 写失败的测试。** 每个测试用 `user://test_session_<名字>/` 目录，开头清空。假钟：`var clk := {"unix": 1767254400.0, "offset": 0}`，`func(): return clk`。

```gdscript
func test_new_game_then_adopt_then_time_passes():
	var s := _session()          # qijia + 假钟 + 干净目录
	s.start()
	assert_eq(s.world.phase, "adopting")
	assert_true(s.command({"type": "adopt"}).ok)
	clk.unix += 90.0
	s.tick(0.016)
	assert_eq(s.world.now, 1767254400 + 60)   # 60 秒一步，余 30 秒留在累加器

func test_save_and_resume_shows_away_summary():
	var s := _session(); s.start(); s.command({"type": "adopt"}); s.tick(0.016)
	assert_true(s.save())
	clk.unix += 3 * 3600.0
	var got := []
	var s2 := _session(false)    # 同一目录，不清空
	s2.away.connect(func(sum): got.append(sum))
	s2.start(); s2.tick(0.016)
	assert_eq(got.size(), 1)
	assert_eq(got[0].simulated_seconds, 3 * 3600)

func test_corrupt_save_is_reported_and_kept_until_new_game():
	_write(dir + "save_qijia.json", "{not json")
	var s := _session(false); s.start()
	assert_eq(s.load_error, "corrupt")
	assert_true(s.world == null)
	s.tick(0.016)                                  # 不崩
	assert_eq(FileAccess.get_file_as_string(dir + "save_qijia.json"), "{not json")
	s.new_game()
	assert_eq(s.world.phase, "adopting")
	assert_eq(FileAccess.get_file_as_string(dir + "save_qijia.json.bad"), "{not json")

func test_debug_speed_survives_restart():
	var s := _session(); s.start(); s.command({"type": "adopt"})
	s.set_setting("speed", 600)
	for i in 100:
		s.tick(0.1)                                # 10 秒真实时间 ≈ 100 分钟游戏时间
	var ahead := s.world.now
	assert_true(ahead > 1767254400 + 5000)
	s.save()
	var s2 := _session(false); s2.start()
	clk.unix += 120.0
	s2.tick(0.016)
	assert_true(s2.world.now > ahead)              # 没有卡住

func test_flip_day_night_shifts_local_hour_by_12():
	var s := _session(); s.start(); s.command({"type": "adopt"}); s.tick(0.016)
	var h := s.world.local_hour()
	s.set_setting("flip_day_night", true); s.tick(0.016)
	assert_near(fposmod(s.world.local_hour() - h, 24.0), 12.0, 0.1)
```

另加：失败指令发 `command_failed`（没钱时 `buy`）；事件经 `event` 信号发出且只发一次；无效主题包（`pack_id` 指向不存在的目录）`start()` 后 `world.phase == "invalid"`、`tick` 和 `save` 都不崩不写文件；坏的 `settings.json` 回到默认值。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: Commit** `feat(view): game session with clock, save and settings`

---

### Task 6: 主场景、房屋和小人

**Files:**
- Create: `game/main.tscn`、`game/kernel/view/main.gd`、`house_view.gd`、`person_view.gd`
- Modify: `game/project.godot`
- Test: `game/tests/test_view_scene.gd`

**Interfaces:**
- `project.godot`：`run/main_scene="res://main.tscn"`，窗口 1280×720，`stretch/mode="canvas_items"`、`aspect="keep"`
- `Main extends Node`：`static func create(pack_id: String, dir := "user://", real_clock := Callable()) -> Main`（不入树也能建好全部子节点）；字段 `session: GameSession`、`house: HouseView`；`tick(delta)` 调 `session.tick` 再调各子块的 `refresh()`；`_process` 调 `tick`；`_notification` 在 `NOTIFICATION_WM_CLOSE_REQUEST` 和 `NOTIFICATION_APPLICATION_FOCUS_OUT` 时 `session.save()`。主题包 id 取命令行参数 `--pack=<id>`（`OS.get_cmdline_user_args()`），没有则 `"qijia"`
- `HouseView extends Node2D`：`setup(session: GameSession)`；字段 `layout: HouseLayout`、`people: Dictionary`（uid → `PersonView`）；`refresh()` 让小人节点和 `world.people` 里活着的人一一对应（多的删、少的建），并 `queue_redraw()`；`tick(delta)` 推小人走路；`world_pos(screen: Vector2) -> Vector2`、`pan(by: Vector2)`（平移量夹在 `layout.bounds()` 不出屏的范围内）；按住空白处拖动平移。`_draw` 画：已盖房间（室内浅色地加上沿一条墙，室外另一种浅色）、未盖房间（虚线框，中间写房名和造价）、家具（色块加名字，颜色按 `category` 的哈希取，同类同色）、脏乱（小褐块）、掉落物（小黄块）。开局把 `layout.bounds()` 居中在底部条以上的区域。夜色：`CanvasModulate` 子节点，`night_amount(local_hour: float) -> float` 在 6–18 点为 0、20–4 点为 1、之间线性过渡，颜色从白插到 `Color(0.45, 0.5, 0.7)`
- `PersonView extends Node2D`：`setup(person: Person, session: GameSession)`；`refresh()` 更新头顶文字（名字一行，`strings.doing` 一行）和目标位置；`tick(delta)` 以每秒 140 像素走向目标；字段 `target: Vector2`、`held := false`（被拖着时不走）。目标位置规则：当前行为有 `object_uid` ≥ 0 → `layout.stand_pos`；有 `target_uid` → 该脏乱或掉落物所在格子中心；都没有 → 该行为开始时在**当前所在房间**里随机挑一格（用画面自己的 `RandomNumberGenerator`，行为不变就不换）；人还不在任何房间（刚进门）→ 第一间已盖的室内房间中心。色块：28×44 的圆角矩形，男女各一种颜色，老人（`stage` 为最后一个阶段）发灰
- 两人落在同一格时，后来的那个横向错开 20 像素

- [ ] **Step 1: 写失败的测试**

```gdscript
func _main(pack := "qijia") -> Main:
	var m := Main.create(pack, _clean_dir(), func(): return clk)
	Engine.get_main_loop().root.add_child(m)
	return m

func test_both_packs_boot_and_adopt():
	for pack in ["qijia", "_smoke"]:
		var m := _main(pack)
		m.tick(0.016)
		assert_eq(m.house.people.size(), 0)
		m.session.command({"type": "adopt"})
		m.tick(0.016)
		assert_eq(m.house.people.size(), 1)
		m.free()

func test_person_walks_to_the_object_they_use():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	var o: Dictionary = w.objects[0] if not w.objects.is_empty() else {}
	# 新开的一局没有家具：先免费放一件能用的
	var uid := w.add_object("stool", "hall", 3, 3)
	assert_true(m.session.command({"type": "drag", "person": p.uid, "object": uid}).ok)
	var pv: PersonView = m.house.people[p.uid]
	m.tick(0.016)
	assert_eq(pv.target, m.house.layout.stand_pos(w.object(uid), w.pack))
	for i in 200:
		pv.tick(0.05)
	assert_true(pv.position.distance_to(pv.target) < 1.0)
	m.free()

func test_dead_person_node_is_removed():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var p := m.session.world.people[0]
	m.session.world.kill_person(p, "old_age")     # 测试里直接动内核，模拟寿终
	m.tick(0.016)
	assert_eq(m.house.people.size(), 0)
	m.free()

func test_night_amount():
	assert_eq(HouseView.night_amount(12.0), 0.0)
	assert_eq(HouseView.night_amount(23.0), 1.0)
	assert_near(HouseView.night_amount(19.0), 0.5)
```

另加：`pan` 夹住不出界；无效主题包时 `Main.create` 不崩、`tick` 不崩。

注意：**新开的一局房子是空的**（`BalanceRun.setup` 那种"每样一件"只是测试用）。领养之后玩家手里有起始的钱，但买不起全套家具。这一点在 Task 11 处理（开局送基本家具），本任务不管。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: 人工看一眼。** `cd game && godot --path . -- --pack=qijia`，窗口里能看到三块房间（厢房是虚线框）。截一张图存到报告里说明看到了什么；看不到窗口的环境写明"未目视"
- [ ] **Step 6: Commit** `feat(view): main scene, house and people`

---

### Task 7: 底部条、选中、赏罚、提示条

**Files:**
- Create: `game/kernel/view/hud.gd`；Modify: `main.gd`、`house_view.gd`
- Test: `game/tests/test_view_hud.gd`

**Interfaces:**
- `Main.selected: int`（选中小人的 uid，-1 为无）；`Main.select(uid: int)`。点小人选中（`PersonView` 画一圈描边）；选中的人不在了自动改选第一个活着的人，没人则 -1；领养、成亲后若当前无选中，选中新来的人
- `Hud extends CanvasLayer`：`setup(main: Main)`、`refresh()`。组成：
  - 底部条（高 96）：左起色块头像、`strings.person_name`、`strings.person_line`；中间"正在做什么"一句（`strings.doing`）；右侧状态一句（`strings.status_line`）和钱（`t("money")`）、存粮（`t("stock")`，取 `world.stock` 各项之和）；按钮 `btn.family`、`btn.shop`、`btn.ledger`、`btn.arrange`、`btn.settings`（按下发信号 `open(what: String)`，值为 `family|shop|ledger|arrange|settings`，面板在后面的任务接）
  - 左上角 `btn.scold`、`btn.praise` 两个按钮：对选中的人发 `{"type": "scold"|"praise", "person": uid}`；无选中时禁用
  - 提示条：`toast(text: String)`，屏幕上方居中，一条显示 3 秒，最多叠 4 条，新的在下；`toasts() -> Array[String]`（当前显示中的，测试用）
  - 接 `session.command_failed` → `toast(strings.error(code))`；接 `session.event` → `strings.event(e, world)` 非空就 `toast`
  - 赏罚成功时在小人头顶冒一个字（赏/罚），1 秒后消失
- 世界不在 living 时底部条只留钱和设置按钮，赏罚禁用

- [ ] **Step 1: 写失败的测试**

```gdscript
func test_bar_shows_selected_person_in_words_not_numbers():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var p := m.session.world.people[0]
	assert_eq(m.selected, p.uid)
	var text := m.hud.bar_text()                 # 底部条所有可见文字拼起来，测试用
	assert_true(text.contains(p.given))
	for word in p.status(m.session.pack).values():
		assert_true(text.contains(word))
	assert_true(not text.contains(str(int(p.needs["fed"]))))   # 不出现状态数值

func test_praise_with_nothing_to_judge_toasts_reason():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	AutonomySystem.cancel(m.session.world, m.session.world.people[0])
	m.session.world.people[0].last_action = ""
	m.hud.press("praise")                        # 测试入口：等同于点按钮
	assert_eq(m.hud.toasts(), [m.session.strings.error("nothing_to_judge")])

func test_selection_moves_on_when_person_dies():
	# 两个人，选中第一个，第一个去世 → 选中第二个
```

另加：`goal_done` 事件出一条含奖励数的提示；第 5 条提示进来时最早的一条被挤掉。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: Commit** `feat(view): bottom bar, selection, praise and scold, toasts`

---

### Task 8: 拖动小人

**Files:**
- Create: `game/kernel/view/drag_controller.gd`；Modify: `main.gd`、`house_view.gd`、`person_view.gd`
- Test: `game/tests/test_view_drag.gd`

**Interfaces:**
- `DragController extends Node`：`setup(main: Main)`；`begin(uid: int)`、`move(world_pos: Vector2)`、`drop(world_pos: Vector2) -> Dictionary`（返回指令结果，没发指令返回 `{}`）、`cancel()`；`dragging: int`（-1 为没在拖）。`HouseView` 的鼠标事件调这四个函数：在小人身上按下并移动超过 6 像素才算拖（否则是点选）；松开即 `drop`
- 拖着时：`PersonView.held = true`，跟着光标；光标下的家具/脏乱/掉落物描边高亮
- `drop` 规则：`layout.pick` 得到
  - `object` → `{"type": "drag", "person", "object": uid}`
  - `mess` → `{"type": "drag", "person", "mess": uid}`
  - `collectible` → `{"type": "drag", "person", "collectible": uid}`
  - 其他（空地、未盖的房间、屋外）→ `{"type": "drag", "person", "object": -1}`（内核回 `no_object`，但会让病人露出症状）；这种情况**不**弹"那儿没有东西"的提示。落在已盖房间里就把人留在那儿，落在别处就回到拖起前的位置
- 指令成功：小人留在松手处，再自己走到站位。指令失败（忙、年纪不合适等）：提示条给原因（经 `command_failed`），小人留在松手处
- 每次 `refresh` 检查：正在拖的人不在活人里了 → `cancel()`

- [ ] **Step 1: 写失败的测试**

```gdscript
func test_drop_on_object_starts_its_action():
	var m := _main_with_adult_and("stool", "hall", 3, 3)      # 领养 + 免费放一件
	var p := m.session.world.people[0]
	var uid: int = m.session.world.objects[0].uid
	m.drag.begin(p.uid)
	var r := m.drag.drop(m.house.layout.object_rect(m.session.world.object(uid), m.session.pack).get_center())
	assert_true(r.ok)
	assert_eq(int(p.current["object_uid"]), uid)
	assert_eq(m.drag.dragging, -1)

func test_drop_on_empty_floor_is_quiet_and_keeps_position():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	var at := m.house.layout.cell_center("hall", 6, 4)
	m.drag.begin(p.uid); m.drag.drop(at)
	assert_eq(m.hud.toasts(), [])
	assert_eq(m.house.people[p.uid].position, at)

func test_drop_on_busy_object_toasts_busy():
	# 两个成年人、一件 capacity 1 的家具，第一个在用，拖第二个上去 → 提示 error.busy，第二个人的 current 不变

func test_drag_is_cancelled_when_person_dies_mid_drag():
	var m := _main_with_adult_and("stool", "hall", 3, 3)
	var p := m.session.world.people[0]
	m.drag.begin(p.uid)
	m.session.world.kill_person(p, "old_age"); m.tick(0.016)
	assert_eq(m.drag.dragging, -1)
	assert_eq(m.drag.drop(Vector2.ZERO), {})
```

另加：拖到脏乱上开始收拾（`current.target_uid` 是那处脏乱）；拖到掉落物上开始捡；拖一个病人到空地后，事件里出现该病的症状行为的 `action_started`（`ok=false` 也有）。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: Commit** `feat(view): drag people onto things`

---

### Task 9: 整屏弹层——领养、提亲、结束、出错、离开小结

**Files:**
- Create: `game/kernel/view/overlays.gd`；Modify: `main.gd`
- Test: `game/tests/test_view_overlays.gd`

**Interfaces:**
- `Overlays extends CanvasLayer`：`setup(main: Main)`、`refresh()`、`current() -> String`（`""|"pack_error"|"load_error"|"adopt"|"over"|"away"|"proposal"`，测试用）、`text() -> String`（当前弹层的全部文字）、`press(button_key: String)`（测试入口）
- 显示优先级从高到低，每次 `refresh` 重新判定：
  1. `pack_error`：`world.phase == "invalid"`。逐行列出 `pack.errors`（可滚动），没有按钮
  2. `load_error`：`session.load_error != ""`。显示 `t("load." + code)` 和 `btn.new_game`（→ `session.new_game()`）；说明旧存档会留底
  3. `adopt`：`phase == "adopting"`。候选人卡片（`Person.from_dict(world.candidate)`）：姓名、性别、年岁、营生名（`pack.livelihoods[track].name` 加 0 级的名字）、喜好和厌恶的标签；按钮 `btn.adopt`、`btn.reroll`
  4. `over`：`phase == "over"`。一句 `title.over`，按钮 `btn.new_game`（→ `{"type": "reroll"}`，回到领养）
  5. `away`：有未读的离开小结（接 `session.away`，存一份；关闭后清掉）。`strings.summary_lines` 逐行，按钮 `btn.close`
  6. `proposal`：`world.proposals` 非空且玩家点开了。不自动弹：来了提亲时提示条提示一次，`btn.family` 按钮上出一个圆点；点 `btn.family`（Task 10 的家人面板）或点提示旁的入口打开。卡片：对方姓名、性别、年岁、营生、喜恶、带来的钱（`pr["savings"]`）；按钮 `btn.accept`、`btn.decline`（→ `answer_proposal`）；`btn.close` 先不回话
- 有弹层时，房屋的点选和拖动不响应（弹层用一块全屏半透明底挡住）

- [ ] **Step 1: 写失败的测试**

```gdscript
func test_boot_shows_adopt_then_reroll_changes_candidate_then_adopt_closes():
	var m := _main(); m.tick(0.016)
	assert_eq(m.overlays.current(), "adopt")
	var before := m.overlays.text()
	m.overlays.press("btn.reroll"); m.tick(0.016)
	assert_true(m.overlays.text() != before)
	m.overlays.press("btn.adopt"); m.tick(0.016)
	assert_eq(m.overlays.current(), "")
	assert_eq(m.session.world.people.size(), 1)

func test_candidate_age_is_readable_not_encoded():
	var m := _main(); m.tick(0.016)
	assert_true(not m.overlays.text().contains("$f"))
	var age := int(Person.from_dict(m.session.world.candidate).age)
	assert_true(m.overlays.text().contains(str(age)))

func test_broken_pack_lists_errors():
	var m := _main("no_such_pack"); m.tick(0.016)
	assert_eq(m.overlays.current(), "pack_error")
	assert_true(m.overlays.text().contains(m.session.pack.errors[0]))

func test_corrupt_save_offers_new_game():
	# 目录里先放坏存档 → current() == "load_error"；press("btn.new_game") → "adopt"

func test_returning_after_hours_shows_summary_once():
	# 领养、存档、假钟 +5 小时、新建 Main → "away"，文字含 away.time 的那句；press("btn.close") → ""；再 tick 不再出现

func test_proposal_accept_brings_spouse():
	var m := _main(); m.overlays.press("btn.adopt"); m.tick(0.016)
	clk.unix += 16 * 60.0; m.tick(0.016)           # 第一桩提亲在入住 15 分钟后
	assert_eq(m.session.world.proposals.size(), 1)
	assert_eq(m.overlays.current(), "")             # 不自动弹
	m.overlays.open_proposal(); m.tick(0.016)
	assert_eq(m.overlays.current(), "proposal")
	m.overlays.press("btn.accept"); m.tick(0.016)
	assert_eq(m.session.world.people.size(), 2)
	assert_eq(m.overlays.current(), "")
```

（16 分钟的跳变大于 120 秒，会走离线补算并弹 `away`。这条测试里改成每次 +60 秒、循环 16 次 `tick`，避免小结弹层挡住。）

另加：提亲过期（`proposals` 变空）时已打开的提亲卡自动关闭；`over` 弹层点新开一局后回到 `adopt`，钱保留。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: Commit** `feat(view): adoption, proposal, game over, error and away overlays`

---

### Task 10: 面板——商店、目标与收藏、家人

**Files:**
- Create: `game/kernel/view/panels.gd`；Modify: `main.gd`、`hud.gd`
- Test: `game/tests/test_view_panels.gd`

**Interfaces:**
- `Panels extends CanvasLayer`：`setup(main: Main)`、`open(what: String)`（`shop|ledger|family`）、`close()`、`opened() -> String`、`refresh()`、`text() -> String`、`press(id: String)`（测试入口，id 见下）。面板居中、宽 560、带 `btn.close`，同时只开一个；按 Esc 关闭。接 `Hud.open` 信号
- **商店**两页：
  - `tab.items`：`pack.items` 按 `category` 分组，每行 名称、价钱、`btn.buy`（id `buy:<item>` → `{"type": "buy", "item": id}`）；钱不够的行按钮置灰
  - `tab.inventory`：`world.inventory` 里数量 > 0 的物品，每行 名称、数量、`btn.use_on`（填选中的人名；id `use:<item>` → `{"type": "use_item", "item", "person": main.selected}`）；无选中时置灰。上方一行 `t("stock")`
  - 物品行**不写**它治什么病，只写名称；药名本身是玩家认药的线索
- **目标与收藏**两页：
  - `tab.goals`：`pack.goals` 逐条 `text` 和奖励；在 `world.goals_done` 里的打勾并排到后面
  - `tab.collection`：`pack.collectibles` 逐种，`world.collection` 里有的显示名称，没有的显示"？"
- **家人**：活着的人逐行（姓名、`person_line`、`status_line`，点一行 → `main.select` 并关闭面板）；`world.proposals` 非空时顶部一行提亲入口（id `proposal` → `overlays.open_proposal()` 并关闭面板）

- [ ] **Step 1: 写失败的测试**

```gdscript
func test_buy_food_raises_stock_and_spends_money():
	var m := _living()                               # 已领养
	var w := m.session.world
	var money := w.money
	m.panels.open("shop"); m.panels.press("buy:rice")
	assert_eq(w.money, money - 24)
	assert_eq(int(w.stock["food"]), 8)

func test_medicine_goes_to_inventory_and_is_used_on_selected_person():
	var m := _living(); var w := m.session.world; var p := w.people[0]
	IllnessSystem.infect(w, p, "chill")
	m.panels.open("shop"); m.panels.press("buy:ginger_pill")
	assert_true(not m.panels.text().contains("伤风"))          # 不泄露病名
	m.panels.press("tab.inventory"); m.panels.press("use:ginger_pill")
	assert_eq(w.stats["cured"], 1)

func test_wrong_medicine_toasts_and_is_spent():
	# 得了 chill，买 indigo_salve 来用 → 提示 error.wrong_medicine，库存归零，病还在（用 p.illness 在测试里断言可以，view 代码里不可以）

func test_unaffordable_item_button_is_disabled():
	# 把钱花到 10 文以下 → m.panels.is_disabled("buy:rice")

func test_goals_and_collection_reflect_world():
	# goals_done 加一条 → 文字里该条带勾；collection 为空时收藏页全是"？"

func test_family_row_selects_person():
```

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: Commit** `feat(view): shop, goals and family panels`

---

### Task 11: 摆设——买、摆、挪、卖家具，加盖房间，开局家当

**Files:**
- Create: `game/kernel/view/arrange_mode.gd`；Modify: `main.gd`、`house_view.gd`、`panels.gd`、`game/kernel/sim/pack.gd`、`pack_validator.gd`、`family_system.gd`、`game/packs/qijia/pack.json`、`game/packs/_smoke/pack.json`
- Test: `game/tests/test_view_arrange.gd`、`test_family.gd`、`test_pack.gd`

**Interfaces:**
- **开局家当（内核）**：配置项 `start_objects: Array`，每项 `{"type", "room", "x", "y"}`，默认 `[]`。第一次领养（`adopted_once` 由假变真那一刻）把它们免费放进去（走 `world.add_object`）。校验：类型和房间存在、房间 `built`、`HouseSystem.can_place` 的规则逐件成立（出界、重叠、室内外不符都报错，指出 `pack.json` 和第几件）。qijia：堂屋放 灶台、土炕、书案、水缸、矮凳，院子放 鸡笼（具体格子由实现者排，互不重叠，留出走动的空）；织机和菜畦留给玩家买。`_smoke` 放两件
- `ArrangeMode extends Node`：`setup(main: Main)`、`active: bool`、`enter()`、`exit()`；进入后屏幕上方一条横幅说明当前在摆设，右侧一列家具目录（`pack.object_types` 按 `category` 分组：名称、价钱；买不起的置灰）和 `btn.close`。进入时拖小人不响应
  - `pick_type(type: String)`：手上拿一件新家具（半透明影子跟着光标，按格子吸附）
  - `pick_object(uid: int)`：拿起一件已有的家具（原地留淡影）
  - `hover(world_pos: Vector2)`：更新影子位置；`can_drop() -> bool`（`HouseSystem.can_place(world, type, room, x, y, 拿起的 uid 或 -1) == ""`；新买的还要钱够）。影子可放为绿、不可放为红
  - `drop(world_pos: Vector2) -> Dictionary`：新家具 → `{"type": "place", "object_type", "room", "x", "y"}`；已有的 → `{"type": "move", "object", "room", "x", "y"}`。成功后手上清空；失败保持拿着，提示原因（`wrong_area` 的 `{where}` 填室内或室外的通用词）
  - `sell_held() -> Dictionary`：拿着已有家具时，目录下方出现 `btn.sell` 和回收价（`price × sell_back_ratio` 取整）→ `{"type": "sell_object", "object"}`
  - `cancel_held()`：右键或 Esc 放回原处
  - `build(room: String) -> Dictionary`：摆设模式里点未盖的房间 → 弹确认（房名、造价）→ `{"type": "build_room", "room"}`
- 每次 `refresh`：手上那件已有家具不在 `world.objects` 里了 → 清空手上

- [ ] **Step 1: 写失败的测试**

```gdscript
# test_family.gd
func test_first_adoption_furnishes_the_house_once():
	var w := World.new(Pack.load_dir("res://packs/qijia"), 1)
	w.sync(1767254400, 0)
	w.command({"type": "adopt"})
	var n := w.objects.size()
	assert_true(n >= 5)
	assert_eq(w.money, 200)                       # 家当不花钱
	# 走到 over 再 reroll + adopt：家具数不变
	w.kill_person(w.people[0], "old_age")
	w.command({"type": "reroll"}); w.command({"type": "adopt"})
	assert_eq(w.objects.size(), n)

# test_view_arrange.gd
func test_place_new_furniture_charges_and_shows_up():
	var m := _living(); var w := m.session.world
	w.money = 1000
	var n := w.objects.size()
	m.arrange.enter(); m.arrange.pick_type("stool")
	var at := _free_cell_center(m, "hall")
	m.arrange.hover(at)
	assert_true(m.arrange.can_drop())
	assert_true(m.arrange.drop(at).ok)
	assert_eq(w.objects.size(), n + 1)
	assert_eq(w.money, 910)

func test_overlap_is_red_and_drop_keeps_holding():
	# hover 到已有家具的格子 → can_drop() 为假；drop 返回 ok=false、error "overlap"、手上还拿着、钱没动

func test_indoor_thing_cannot_go_in_the_yard():
	# 把 stool hover 到院子 → can_drop() 为假（wrong_area）

func test_move_object_cancels_its_user():
	# 人在用矮凳，摆设模式里把矮凳挪到别处 → 那人的 current 为空，家具 uid 不变、坐标变了

func test_sell_refunds_half():
func test_build_room_then_place_inside():
	# 钱设到 3000，build("side") → rooms_built 含 side，钱少 2400；随后能在 side 里放下一件家具

func test_cannot_afford_new_furniture():
	# 钱 50，pick_type("kang") → can_drop() 为假；drop → error no_money
```

`test_pack.gd`：`start_objects` 里类型不存在、房间未盖、两件重叠，各报一条错。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**（`BalanceRun.setup` 现在领养后会多出开局家当，再"每样放一件"时已有的类型跳过；`test_packs_both.gd` 相应的断言跟着调）
- [ ] **Step 5: 跑一遍平衡，确认没被开局家当带偏：** `cd game && godot --headless -s res://tools/balance_cli.gd -- qijia 50 3`，50 户都活着、没有照看不周致死。把这行 JSON 贴进报告
- [ ] **Step 6: Commit** `feat: starting furniture; arrange mode to buy, place, move, sell and build`

---

### Task 12: 设置、网页导出、怎么跑

**Files:**
- Create: `game/kernel/view/settings_panel.gd`、`game/export_presets.cfg`、`README.md`、`game/tools/export_web.sh`
- Modify: `main.gd`、`.gitignore`
- Test: `game/tests/test_view_settings.gd`

**Interfaces:**
- `SettingsPanel`（接 `Hud.open("settings")`，可并进 `Panels` 的结构）：
  - `set.flip` 开关 → `session.set_setting("flip_day_night", bool)`
  - `set.speed`：三个单选 ×1、×60、×600 → `session.set_setting("speed", n)`。旁边一行小字说明这是调试用、正式版会去掉。速度 > 1 时屏幕右上角一直显示"×60"之类的标记
  - 显示当前游戏里的钟点（`world.local_hour()` 化成 时:分）
- `export_presets.cfg`：一个 Web 预设，名 `Web`，导出到 `../build/web/index.html`；**导出过滤里包含 `*.json`**（主题包是纯 JSON，不加就不会被打进包）。`build/` 进 `.gitignore`
- `export_web.sh`：检查导出模板是否装了（`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`），没装就打印要装什么、怎么装然后以非零码退出，**不自己下载**；装了就 `godot --headless --path game --export-release Web`
- `README.md`（中文，半页以内）：这是什么；本机怎么玩（`godot --path game`）；怎么换主题包（`-- --pack=_smoke`）；怎么跑测试；怎么导出网页版和本地预览（`python3 -m http.server -d build/web`）；存档在哪、怎么删档重来；调试快进是什么

- [ ] **Step 1: 写失败的测试**

```gdscript
func test_speed_marker_and_setting_persist():
	var m := _living()
	m.settings.press("speed:60"); m.tick(0.016)
	assert_eq(m.session.settings.speed, 60)
	assert_true(m.hud.bar_text().contains("×60") or m.settings.marker_text() == "×60")
	var m2 := _main_same_dir()
	assert_eq(m2.session.settings.speed, 60)

func test_flip_toggle_changes_night_tint():
	# 假钟设在当地正午 → night_amount 为 0；打开昼夜颠倒并 tick → night_amount 为 1
```

另加：`Pack.load_dir` 用的是 `FileAccess`/`DirAccess` 读 `res://`——写一条测试断言 `export_presets.cfg` 的 `include_filter` 含 `*.json`。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试**
- [ ] **Step 5: 试导出。** 跑 `game/tools/export_web.sh`。模板没装：把脚本打印的提示原样写进报告，状态记 DONE_WITH_CONCERNS（网页版未验证），不要自己去下载模板。模板装了：导出后起本地服务，用浏览器打开，确认能进领养界面、领养后小人出现、刷新页面后存档还在；把看到的写进报告
- [ ] **Step 6: Commit** `feat(view): settings, debug speed, web export preset and README`

---

## 做完之后（不是任务，是交付时要做的）

1. 全量测试；`balance_cli` 50 户 3 天；`diary_cli` 看一遍夜里
2. 自己用 `godot --path game` 把这一圈从头到尾玩一遍，调试快进开到 ×60：领养 → 拖去念书 → 赏 → 买米 → 等脏乱出现并收拾 → 买一件家具摆上 → 等提亲并应下 → 关掉重开看小结。逐项记下通不通
3. 把怎么启动、玩的时候留意什么，写给雨蝶。**这是第 1 期的停靠点：她亲手玩，判断这一圈好不好玩**
