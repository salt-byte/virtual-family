---
name: pack-verification
description: 改完主题包或内核之后、交给用户之前的验收：跑全部测试、跑平衡模拟看钱和吃饭和升级、抽一段日记看小人一天在干什么、量离线补算的耗时。每次改了 rooms / objects / actions / livelihoods / pack.json，或内核代码，交接前都用；用户问「数值会不会崩」「平衡吗」「这样改有没有问题」时也用。
---

# 主题包验收（pack-verification）

四样都过了才交给用户。哪样没过，要么改到过，要么停下来把最好的数字和原因告诉用户，不能悄悄放宽标准。

## 1. 测试

```
./game/tests/run.sh            # 全部，约 3 分钟
./game/tests/run.sh places     # 按文件名过滤，迭代时用
```

- 输出里出现 ERROR / WARNING 行、或某条测试一个断言都没做，都算失败。
- `_smoke` 是测试专用包：任何改动都不能改变它的行为，跑它的测试的预期一条都不能动。新字段的默认值必须等于改动前的行为。
- 要改已有测试的预期，逐条写下原因（通常是房子的几何变了、开局房间数变了）。
- 另外跑一下 `cd game && godot --headless --quit-after 5`，输出要干净。

## 2. 平衡

```
cd game && godot --headless -s res://tools/balance_cli.gd -- qijia 20 3
```

20 户人家、各过 3 天。《起家》的验收线：

| 项 | 线 |
|---|---|
| `alive_at_end` | 全部活着 |
| `deaths_neglect` | 0 |
| `median_money` | 上一轮中位数的 0.7–1.5 倍（上一轮是 1262） |
| `food_bought_per_day` / `max_food_bought_in_a_day` | ≤ 2 |
| `avg_level` | ≥ 0.6（大人在升级，说明正事没被消遣挤掉） |

只调包里的数据去达标，别为了过线改内核。

## 3. 日记抽查

```
cd game && godot --headless -s res://tools/diary_cli.gd -- qijia 1 7
```

挑一个人，看白天十分钟和傍晚十分钟。要看到：换着做不同的事、事和地方对得上（院子里看星星，不在卧房里）、夜里大多在睡觉。`test_qijia_lone_adult_daytime_hour_is_varied` 要求一个独居大人白天一小时里至少 15 种不同的事。

## 4. 性能

```
./game/tests/run.sh perf
```

离线 48 小时的补算，上限 10 秒。玩家关了游戏再打开，就要等这么久。动作越多越慢：《起家》从 96 条加到 144 条时一度量到 17 秒，后来把候选扫描改成先跑便宜的是非判断、边扫边留前几名，降到 9.9 秒。量的时候电脑忙不忙会影响结果，报数时要写上。

## 交给用户时说什么

- 全部测试的条数和结果，平衡那几项的数字，性能数字。
- 哪些只在测试里验证过、没在真窗口里看过（手感、画面、文字读起来对不对味），请用户亲眼看。
- 用户能直接点开的试玩方式：本地 `python3 -m http.server -d build/web 8060`，或发布后的网页链接（见 `web-release`）。
