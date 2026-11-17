# 日历慢、动作快 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不开快进、盯着屏幕看一分钟，就能看到小人换两三件事；一个下午能见到《起家》35 条行为里的大多数。日历（饿、困、昼夜、年岁、工钱）仍按真实时间慢慢走，一代人约一周。

**Architecture:** 内核步长从写死的 60 秒改成主题包配置；行为的实际时长 = 表里的时长 ÷ 主题包的"动作加速"倍数（标了"慢"的行为除外）。一次行为给的好处按次算不变，消耗、工钱和营生进度按实际花的时间算。画面层给做事的人加原地动作和进度点。默认值保持旧行为（步长 60、加速 1），`_smoke` 主题包不改，用来证明旧行为没坏；`qijia` 用新值。

**Tech Stack:** Godot 4.7.2、GDScript、JSON；`./game/tests/run.sh [filter]`。

**Spec:** `docs/superpowers/specs/2026-11-17-lifesim-kernel-design.md` 第 13 节最后一条"日历慢、动作快"，以及 5.2、5.3。

## Global Constraints

- `game/kernel/sim/`：`RefCounted`、不读系统时钟、不含题材词和主题包 id、随机都走 `SimRng`、钱是整数且不为负
- `game/kernel/view/`：不含主题包 id 和题材词、不读 `.illness`、不写 `World` 字段
- 默认配置下（`step_seconds` 60、`action_speed` 1、没有行为标 `slow`）内核行为与改动前逐步一致：`_smoke` 主题包的既有测试除非直接断言了被改名的常量，否则一条都不许改期望值
- 离线补算与在线同一套规则；离线照看不周不致死
- 旧存档（缺新字段）要能读，缺的字段取默认值
- 测试输出无 ERROR / WARNING；两个主题包都要过
- 提交信息末尾加 `Co-Authored-By: <模型名> <noreply@anthropic.com>`；只在本地提交，不推送

## Review Focus

1. **换了步长以后，按"每步"而不是按"每秒"算的东西会变快 12 倍**（生病几率、脏乱和掉落物的出现、提亲计时、工钱整点、夸奖衰减）。逐个系统核对，凡是每步掷一次骰子的都要按 `dt` 折算。→ Task 1
2. **离开 48 小时回来**：补算要在几秒内跑完，结果与在线一致。→ Task 1
3. **行为变多以后按次计的副作用成倍出现**：零嘴类行为吃掉存粮、做饭类行为弄脏屋子、干活的工钱和进度。不能让一家人因此饿死或暴富。→ Task 2
4. **很短的行为（实际不足一步）**：至少占一步，好处照给，不会卡住或跳过结算。→ Task 2
5. **旧存档里正在进行的行为**（`remaining_s` 是按旧时长存的）：读出来能正常做完。→ Task 2

---

### Task 1: 步长由主题包定

**Files:**
- Modify: `game/kernel/sim/pack.gd`、`pack_validator.gd`、`world.gd`、`economy_system.gd`、`world_save.gd`，以及审出来按步计数的系统
- Modify: `game/packs/qijia/pack.json`
- Test: `game/tests/test_world_time.gd`、`test_pack.gd`、`test_packs_both.gd`、`test_offline.gd`，以及因 `World.STEP` 改名而需要改引用的测试

**Interfaces:**
- Produces: 配置项 `step_seconds: int`（默认 60；必须是 60 的约数：1、2、3、4、5、6、10、12、15、20、30、60）；`World.step_s: int`（构造时从主题包读；无效主题包为 60）。`World.STEP` 常量删掉，所有引用改用 `world.step_s`。`World.SYNC_OFFLINE_GAP` 不变（120 秒）
- qijia：`"step_seconds": 5`

- [ ] **Step 1: 写失败的测试**

```gdscript
# test_world_time.gd
func test_step_seconds_comes_from_the_pack():
	var w := TestKit.world()                       # _smoke，默认 60
	assert_eq(w.step_s, 60)
	var q := TestKit.world("qijia")
	assert_eq(q.step_s, 5)
	var t0 := q.now
	q.advance(12.0)
	assert_eq(q.now, t0 + 10)                      # 两步，余 2 秒留在累加器

func test_hourly_salary_is_paid_once_per_hour_at_small_steps():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	p.track = w.pack.livelihoods.keys()[0]
	w.drain_events()
	w.advance(3 * 3600.0)
	var pays := w.drain_events().filter(func(e): return e.type == "income" and e.get("source", "") == "salary")
	assert_eq(pays.size(), 3)
```

`test_pack.gd`：`step_seconds` 为 0、7、61、5.5 时各报一条错（`pack.json`）；5 和 60 合法。

`test_packs_both.gd` 加一条"按秒折算"的总账测试，证明换步长不改变事情发生的快慢：同一个种子、同样的 qijia 内容，分别用 `step_seconds` 60 和 5 各跑 30 户 × 2 天（在测试里改 `pack.config["step_seconds"]` 后再建 `World`），比较两组的**平均**值——生病次数、脏乱出现次数、掉落物出现次数、提亲到达次数——每一项两组相差不超过 35%，且都大于 0。（这是防止"每步掷一次骰子"的东西变快 12 倍；容差宽是因为随机序列不同。）

`test_offline.gd`：qijia 补算 48 小时，墙上时间不超过 5 秒（用 `Time.get_ticks_msec()`，这是测试，不是内核），且 `test_offline_matches_online_when_no_floor_hit` 的 qijia 版本成立。

- [ ] **Step 2: 跑测试确认失败**
- [ ] **Step 3: 实现。** 先逐个读 `needs_system`、`illness_system`、`mess_system`、`collectible_system`、`family_system`、`goal_system`、`economy_system`、`autonomy_system` 的 `step`，把每一处"每步一次"的概率或计数列进报告，说明是否已按 `dt` 折算；没折算的改成按 `dt`（概率用 `1 - (1 - p_per_minute)^(dt/60)` 或等价的按时间计的写法，使 60 秒步长下的结果与改动前**逐位一致**——若做不到逐位一致，停下来报告，不要改 `_smoke` 的期望值）。存档里 `acc` 的合法范围随步长（0 ≤ acc < step_s）
- [ ] **Step 4: 跑全量测试；`cd game && godot --headless -s res://tools/balance_cli.gd -- qijia 20 3`，把 JSON 和用时贴进报告**（步长变小后这条会慢很多，属预期；超过 10 分钟就停下来报告）
- [ ] **Step 5: Commit** `feat(kernel): step length comes from the pack`

---

### Task 2: 行为走快钟

**Files:**
- Modify: `game/kernel/sim/pack.gd`、`pack_validator.gd`、`autonomy_system.gd`、`economy_system.gd`、`person.gd`、`world_save.gd`
- Modify: `game/packs/qijia/pack.json`、`actions.json`；`game/tools/diary_cli.gd`（若有按时长的假设）
- Test: `game/tests/test_autonomy.gd`、`test_economy.gd`、`test_pack.gd`、`test_save.gd`、`test_packs_both.gd`

**Interfaces:**
- Produces:
  - 配置项 `action_speed: float`（默认 1.0，≥ 1）
  - 行为字段 `slow: bool`（默认 false）
  - `AutonomySystem.duration_s(world: World, action: Dictionary) -> int`：`slow` 或加速为 1 时是 `duration_min × 60`；否则 `ceil(duration_min × 60 / action_speed)`，再向上取整到 `world.step_s` 的整数倍，最少一步
  - 行为开始时 `remaining_s = duration_s(...)`
  - **好处按次、消耗按时**：行为的 `needs` 里，正数总量不变（在实际时长里匀着给完）；负数乘以 `duration_s / (duration_min × 60)`（即按实际花的时间折算）
  - **工钱和进度按实际时间**：行为结束时传给 `EconomySystem.on_work_finished` 的分钟数是实际分钟（`duration_s / 60.0`，浮点）。零头不丢：`Person.work_carry: float`（默认 0，存档；旧存档缺它取 0）累积不足一文的工钱，`bonus = int(rate × minutes / 60 + work_carry)`，余数留回 `work_carry`
  - 默认配置下以上各项与改动前逐位一致
- qijia：`"action_speed": 30`、`"hours_per_year": 4`；`sleep` 和 `nap` 标 `"slow": true`；按 Step 4 的结果调行为表

- [ ] **Step 1: 写失败的测试**

```gdscript
# test_autonomy.gd
func test_duration_is_scaled_rounded_up_to_steps_and_slow_is_exempt():
	var w := TestKit.world("qijia")                # step 5，加速 30
	var acts := w.pack.actions
	assert_eq(AutonomySystem.duration_s(w, acts["study"]), 120)       # 60 分钟 → 2 分钟
	assert_eq(AutonomySystem.duration_s(w, acts["wash_face"]), 20)    # 10 分钟 → 20 秒
	assert_eq(AutonomySystem.duration_s(w, acts["sleep"]), 420 * 60)  # 慢：不变
	var s := TestKit.world()                       # _smoke：默认
	assert_eq(AutonomySystem.duration_s(s, s.pack.actions["eat"]), int(s.pack.actions["eat"]["duration_min"]) * 60)

func test_gain_is_whole_but_cost_follows_real_time():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	p.track = "reading"
	var uid := w.add_object("desk", "hall", 6, 4)
	p.needs["energy"] = 80.0
	p.needs["fed"] = 40.0
	AutonomySystem.start(w, p, "study", uid)
	w.advance(120.0)
	# study 的 energy -6 是按 60 分钟定的；实际只用了 2 分钟 → 约 -0.2，再加这 2 分钟的自然消耗
	assert_true(p.needs["energy"] > 79.0, "energy " + str(p.needs["energy"]))
	assert_true(p.current.is_empty() or p.current["action"] != "study" or true)   # 见下
	# 吃一顿的好处不打折
	var q := TestKit.adult(w)
	q.needs["fed"] = 20.0
	w.stock["food"] = 3
	AutonomySystem.start(w, q, "eat_on_threshold", -1)
	w.advance(float(AutonomySystem.duration_s(w, w.pack.actions["eat_on_threshold"])))
	assert_true(q.needs["fed"] > 54.0, "fed " + str(q.needs["fed"]))
```

（上面那句 `or true` 的断言不要照抄：改成断言 `p.last_action == "study"`，即这件事在 120 秒内做完了。）

```gdscript
# test_economy.gd
func test_work_pay_follows_real_minutes_and_keeps_fractions():
	var w := TestKit.world("qijia")
	var p := TestKit.adult(w)
	p.track = "reading"                            # 蒙童：每小时 4 文
	var uid := w.add_object("desk", "hall", 6, 4)
	var money := w.money
	for i in 30:                                   # 30 次 × 2 分钟 = 1 小时实际干活
		AutonomySystem.start(w, p, "study", uid)
		w.advance(120.0)
		p.needs["fed"] = 80.0
	var earned := w.money - money - _salary_paid(w)   # 扣掉这段时间按时辰到账的工钱
	assert_eq(earned, 4)
	assert_near(p.progress, 60.0 * p.aptitude, 0.5)
```

（`_salary_paid` 用排空事件、数 `source == "salary"` 的办法实现。）

另加：`action_speed` 为 0.5 报错、1 和 30 合法；`slow` 非布尔报错；实际时长不足一步的行为占一步并正常结算（造一个 1 分钟的行为，在加速 30、步长 5 下 `duration_s == 5`，一步之后做完且好处到账）；`_smoke` 下 `test_action_applies_needs_proportionally_and_finishes`、`test_working_adds_bonus_and_progress`、`test_finished_work_action_pays_bonus` 原样通过；旧存档缺 `work_carry` 能读（取 0）；存档里行为的 `remaining_s` 大于新算出的时长时照常做完、不报错。

- [ ] **Step 2: 跑测试确认失败**
- [ ] **Step 3: 实现内核部分，全量测试通过**
- [ ] **Step 4: 调《起家》的行为表，直到下面几条同时成立。** 用 `cd game && godot --headless -s res://tools/balance_cli.gd -- qijia 20 3` 和 `godot --headless -s res://tools/diary_cli.gd -- qijia 1 7`（日记现在很长，看前 200 行和夜里一段）。可以动的只有 `game/packs/qijia/*.json`（行为的 `base`、`duration_min`、`needs`、`hours`、`consumes`、`mess` 几率），不许为了凑数改内核：
  - 20 户 3 天：都活着，没有照看不周致死；期末存款中位数在改动前（约 1350 文）的 0.6–1.6 倍之间
  - 一户一天里出现的不同行为不少于 20 种
  - 白天任取连续 10 分钟，同一个人换事情不少于 4 次（在 `test_packs_both.gd` 里写成测试：10:00 起 10 分钟，数 `action_started`）
  - 夜里（22:00–05:00）两个成年人大部分时间在睡：这 7 小时里每人的 `action_started` 不超过 6 次（也写成测试）
  - 存粮不被零嘴吃空：照看者一天买米不超过 2 袋（在 `BalanceRun` 的小结里加一项 `food_bought_per_day` 并断言）
  - 会消耗存粮的行为只在有需要时才做（它们的 `base` 为 0 或靠需要打分），把你做的每一处改动和理由列进报告
- [ ] **Step 5: `test_packs_both.gd` 里按天数写死的期望（比如两天内的行为种类数）跟着新节奏更新，报告里逐条说明**
- [ ] **Step 6: Commit** `feat(kernel): actions run on a fast clock; qijia retuned`

---

### Task 3: 做事的人看得出在忙

**Files:**
- Modify: `game/kernel/view/person_view.gd`、`hud.gd`、`view_strings.gd`（如需）
- Test: `game/tests/test_view_scene.gd`、`test_view_hud.gd`

**Interfaces:**
- `PersonView.progress() -> float`：没在做事为 -1；否则 `1 - remaining_s / AutonomySystem.duration_s(world, action)`，夹在 0–1（只读内核）
- 做事且已走到位时，色块原地上下轻晃（振幅 3 像素、周期 0.8 秒，用 `tick(delta)` 累计的时间驱动，`bob_offset() -> float` 可测）；走路中和被拖着时不晃；闲着不晃
- 头顶文字牌下沿画一条细进度线（宽度 = 牌宽 × `progress()`），闲着不画
- 底部条"正在做什么"那句后面带进度：一条同样的细线或"·"加百分比都可以，取其一并保持不出现状态数值
- 标了 `slow` 的行为（睡觉）不晃，改成色块变暗 30%，表示睡着

- [ ] **Step 1: 写失败的测试**

```gdscript
# test_view_scene.gd
func test_progress_and_bob_follow_the_action():
	var m := _main(); m.session.command({"type": "adopt"}); m.tick(0.016)
	var w := m.session.world
	var p := w.people[0]
	var pv: PersonView = m.house.people[p.uid]
	AutonomySystem.cancel(w, p); m.tick(0.016)
	assert_eq(pv.progress(), -1.0)
	assert_eq(pv.bob_offset(), 0.0)
	var desk: int = w.objects.filter(func(o): return o.type == "desk")[0].uid
	m.session.command({"type": "drag", "person": p.uid, "object": desk}); m.tick(0.016)
	assert_near(pv.progress(), 0.0, 0.05)
	for i in 200:                                   # 走到位
		pv.tick(0.05)
	pv.tick(0.2)
	assert_true(absf(pv.bob_offset()) > 0.0 and absf(pv.bob_offset()) <= 3.0)
	clk.unix += 60.0; m.tick(0.016)                 # 念书 2 分钟，过了一半
	assert_near(pv.progress(), 0.5, 0.1)
```

另加：被拖着（`held`）时 `bob_offset()` 为 0；睡觉（`slow`）时 `bob_offset()` 为 0 且 `asleep()` 为真；底部条文字里出现进度而不出现任何状态数值。

- [ ] **Step 2–4: 确认失败 → 实现 → 全量测试 + `cd game && godot --headless --quit-after 5`**
- [ ] **Step 5: Commit** `feat(view): people visibly busy: bob, progress line, asleep`

---

## 做完之后

1. 全量测试；`balance_cli qijia 20 3`；`diary_cli` 看白天十分钟和夜里
2. 截图核对：白天做事的人有进度线，夜里睡着的人变暗
3. 更新 README 里"调试快进"一段（×1 下已经看得到动静）和两份遗留事项
