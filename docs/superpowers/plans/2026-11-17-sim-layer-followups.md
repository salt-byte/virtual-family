# 模拟层：留给后续计划的事项

模拟层计划（2026-11-17-sim-layer.md）已全部完成并通过总审阅。以下是执行台账里留下的、下一份计划（白盒画面）及之后要用到的内容。

## 画面层必须知道的

- 画面只通过 `World.sync(unix, utc_offset)`、`World.command`、`World.drain_events`、存读档和只读状态与内核打交道；**先 sync 再发任何指令**（否则领养时的计时器会按 0 时刻起算）
- 事件里小人一律用 `person`；`uid` 只指杂务或掉落物
- 指令返回 `ok=false` 时仍可能有 `action_started`（病人被拖动后会露出症状）
- 主题包无效时内核不报错只置 `phase=invalid`，画面要有一处把 `pack.errors` 显示出来
- `to_dict()` 里的浮点数为存档做了编码，画面读状态要读活的字段，不要读 `to_dict()`
- 内核没有走路时间，行为是瞬间开始的；走过去的动画由画面自己做
- 离开超过上限回来后，之前设的计时（提亲期限、掉落物过期）会在第一步一起到期

## 已知边界（留给第 2、3 期）

- 没有生育和继承：一局只有一代人，约四到六天寿终后结束；孩童专属行为暂时看不到
- 配偶去世后 `married` 仍为真，不会再有人提亲
- 每次提亲只有一位候选人（设计文档写的是几位）
- 《起家》只有读书一条营生；织机不挣钱，只让人心情好；夫妻共用一张土炕
- 行为没有防重复的冷却，同一件事可能连着做（试玩时留意）

## 审阅中记下、暂未处理的小问题

- 任务 1：chance(1.0) can theoretically return false (randf inclusive)
- 任务 1：SimRng.set_state raises on missing keys (will be fed from saves)
- 任务 1：rng state roundtrip only tested on same instance; weighted_pick distribution/empty case untested
- 任务 1：run.sh discards --import errors
- 任务 1：run.sh treats any WARNING line as fatal (deliberate strictness)
- 任务 2：praise_decay_per_hour int/float inconsistency; config values not range-checked (hours_per_year 0); fixtures are full copies of _smoke
- 任务 3：duplicated clamp expr in needs_system; Person.stage assumes sorted stages; negative advance() seconds stalls _acc (Task 13 must guard); remaining_s int-coerced; test gaps (add_person uid, event t, single game_over)
- 任务 4：person's own object counts as busy for themselves (Task 5 told to exclude own uid); start() with uid -1 and no free object not guarded; kill_person emits no action_cancelled; no anti-repeat cooldown; "baby" stage id hard-coded in autonomy (packs must name the youngest stage "baby"); test gaps (likes/dislikes scoring, requires positive paths, two idle people sharing an object)
- 任务 5：explicit drag action not bound to the dragged object's type is accepted; "invalid" phase command rejection untested; praise/scold on dead person untested; praise window boundary inclusive and unpinned
- 任务 6：earn() income event lacks uid; work bonus truncates (59 min at 1/h pays 0); test gaps (level change mid-cycle, use_item on dead person, buy stock item qty > 1)
- 任务 7：wrong-illness medicine test mislabelled (never tests sick-with-different-illness); no cures+needs test; determinism test passes with both ""; no negative show_symptom tests; cure does not cancel an illness-gated action in progress
- 任务 8：explicit built room used for mess even if indoor/outdoor mismatched
- 任务 9：place/move with missing x/y default to 0 silently; place runs can_place twice; test gaps (two simultaneous users, outdoor object indoors, cross-room move, sell test hard-codes 0.5)
- 任务 8：claimed_by_other indexes pack.actions[...] directly (errors on unknown id)
- 任务 10：test_never_exceeds_max can pass vacuously; goal conditions cured/married/objects_owned/room_built/level_reached/collected untested; no autonomous pick-up test; MessSystem<->AutonomySystem mutual dependency; RED produced after implementation
- 任务 11：make_person wastes rng draws for proposals; answer_proposal when lone adult gone / second adult present keeps random family; family-name test could pass by chance; no test that expiry schedules interval_hours; reroll clears income_carry without comment; proposals.erase by value
- 任务 13：Offline writes world._events directly (add World.requeue_events); summary mappings illnesses/level_ups/goals_done/proposals_expired have no content assertions
- 任务 12：version/pack_id check duplicated in SaveStore.load and from_dict; world.gd +290 lines of save code (candidate for world_save.gd)
- 任务 14：BalanceRun reloads the pack per family; upper-median integer division; 4 child-only actions unreachable until births; loom earns nothing (single track); a few labels 11 chars long for the bottom bar
- 任务 12：uid-counter check ignores candidate uid and the person inside each proposal
- 总审阅后：存档里 acc 未做 0–60 范围检查；run.sh 的 find|xargs 遇到带空格的路径会出错

（其中事件键名、kill_person 不发取消事件、拖动显式行为不校验、治愈不结束病榻行为、阶段名硬编码、Offline 直接写 _events、world.gd 过长 这几条已在总审阅后的修补中解决。）
