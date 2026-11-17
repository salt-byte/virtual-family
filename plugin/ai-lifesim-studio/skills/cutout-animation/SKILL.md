---
name: cutout-animation
description: 骨骼拆件动画（纸片拆件）：把卡通、手绘 2D 角色拆成头、躯干、胳膊、腿几块，自动定关节点，预览走路 / 待机 / 攻击 / 受击这几套默认动画（家务动作往动作表里加几行数），生成 Godot 4 场景（Node2D 关节 + Sprite2D + AnimationPlayer）。美术路线是 AI 生图或自己上传、ART_DIRECTION 第 6 节选了「骨骼拆件」时使用；用户说「角色动起来变形」「每帧长得不一样」「想加新动作又不想重新画」时也用。像素风小角色用 asset-generation 的派生帧，开源素材库用素材自带的帧。
---

# 骨骼拆件动画（cutout-animation）

> **第一个动作**（先于建文档、搜索、写任何正文）：用读文件工具打开项目根目录的 `GAME_BRIEF.md`、`TASKS.md`<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->和 `design/ART_DIRECTION.md`。打不开，或有字段为空、写着「待定」→ 停下，向用户问清楚，写好再回来<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->。ART_DIRECTION 第 6 节的「角色动画」不是「骨骼拆件」→ 回 `art-direction` 确认。
>
> **文风**：给用户的提示词、交接消息照 `writing-style` 的禁用语录写，写完跑它的 `check_style.py`。
>
> **做完后**：这一步（TASKS.md 的一行）做完，向用户交接<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->：做完了什么、用户点得开的链接或文件（预览 GIF 直接发）、下一步做什么，发完接着做下一步，不等回答；同一行里还有别的 skill 没做就接着做。只有这一步落在停靠点、或下一步有定调题时才停下来问（GAME_BRIEF「节奏」写着「每步停」的项目，照旧每步等用户点头）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。

## 为什么用拆件
逐帧生图做动画，每一帧都是重新画的：脸、衣服、比例每张都偏一点，连起来就闪。拆件的角色只有一套图，动画是让关节转起来，所以永远是同一个角色；加一个新动作只是在动作表里加几行数，不用再生图。代价是动作有「纸片感」，衣服头发不会自己飘；要飘的地方（披风、头发）单独拆成一块挂上去，给它一个小幅摆动。

插件里的引擎实现是 Godot 4；用 three.js 或自写 Canvas 时，`preview_rig.py` 的画法（`cutout_lib.py`）就是要移植的那套：每个部件一个原点在关节上的节点，子节点挂在父节点的挂点上，按 z 排先后画。

## 文件
| 文件 | 干什么 |
|---|---|
| `references/rig.humanoid_side.json` | 默认骨架：侧面朝右的人形，6 张图拼 10 个部件（远侧胳膊腿复用近侧的图，压暗） |
| `references/anims.humanoid_side.json` | 默认动作：idle、walk、attack、hurt。改手感就改这里的数 |
| `references/part-sheet-prompt.md` | 拆件图的提示词模板，和每条要求的理由 |
| `scripts/split_parts.py` | 拆件图（或分好的部件目录）→ 部件 PNG + `<名字>.rig.json`，关节点自动算好 |
| `scripts/preview_rig.py` | 站立图（关节标红点）+ 每个动作的 GIF 和帧表，不用开 Godot |
| `scripts/check_rig.py` | 查骨架、关节点、关节处有没有多画一截、动作表 |
| `scripts/build_godot_rig.py` | 写 Godot 场景 `.tscn` |

脚本路径前缀 `${CLAUDE_PLUGIN_ROOT}/skills/cutout-animation/`，下面省略。依赖 Pillow 和 numpy。

## 流程

### 1. 拿到部件
- **AI 生图**：用 `asset-generation` 的 `gen_image.py` 先生侧面站立参考图（`--n 3` 出候选），用户挑定长相；再照 `part-sheet-prompt.md` 写拆件图的提示词进 `prompts.json`（`refs` 带上参考图，清单 `type` 写 `parts`），同样用 `gen_image.py` 出，图落在 `assets/gen/inbox/<角色>_parts.png`。
- **自己上传**：用户给的已经分好的部件，按部件 id 命名放进一个目录（见 `part-sheet-prompt.md` 末尾）。用户只有一张完整的角色图：请用户在自己的软件里拆，或拿这张图当参考图让 AI 生拆件图。脚本不从一张完整的图里自动拆胳膊腿。

### 2. 切件
```
python3 scripts/split_parts.py assets/gen/inbox/hero_parts.png --rig references/rig.humanoid_side.json \
    --name hero --out assets/chars/hero
python3 scripts/split_parts.py --from-dir <部件目录> --rig references/rig.humanoid_side.json --name hero --out assets/chars/hero
```
先看 `_contact.png`：每块的框和名字对不对。对不上时脚本会说哪一格空了、哪一格多了；按提示调参数、`--map` 手动指定，或重新生图。

### 3. 看站立图，修关节点
```
python3 scripts/preview_rig.py assets/chars/hero/hero.rig.json --anims references/anims.humanoid_side.json --out qa/rig_preview/hero
python3 scripts/check_rig.py assets/chars/hero/hero.rig.json --anims references/anims.humanoid_side.json
```
`rest.png` 上的红点要落在脖子根、肩、肘、胯、膝上。偏了就改 `hero.rig.json` 里那个部件的 `pivot_px`（自己绕哪一点转）或 `attach_px`（挂在父部件图上哪一点），单位是像素，在部件图上量。重跑 `split_parts.py` 时手改过的值会保留。

`check_rig.py` 的 ❌ 全部改掉才往下走；⚠ 逐条看预览确认。最常见的 ⚠ 是「关节点往外只多出几像素」：部件末端是平切口，一转就露缝，重新生图时强调「两头画成圆头」。

### 4. 看动作
逐个打开 `<动作>.gif`，再看 `<动作>_sheet.png` 逐帧查：
- 关节处有没有缝、有没有部件转到不该在的前后（远侧胳膊跑到身体前面 → 改 `z`）；
- 脚底有没有在地面上滑（走路时身体上下动的幅度和腿的摆角配不上 → 改动作表）；
- 动作的力度对不对得上设计页（家务动作的前摇和收招时间照对应的设计页写<!-- TODO(lifesim): 原文指向 game-design，本插件暂无对应技能 -->）。

动作表的格式：每个部件一条，`rot` 是 `[时间, 角度]`（正 = 顺时针：腿往后摆、膝盖往后弯、躯干前倾），`pos` 是 `[时间, dx, dy]`（按躯干高 100 写）。预览和 Godot 读同一份，预览对了 Godot 就对。

### 5. 进 Godot
```
python3 scripts/build_godot_rig.py assets/chars/hero/hero.rig.json --anims references/anims.humanoid_side.json \
    --res res://assets/chars/hero --out assets/chars/hero/hero.tscn
```
场景原点在脚底；朝左走把根节点 `scale.x` 设成 -1。播放：`$AnimationPlayer.play("walk")`。换衣服 = 换某个部件 Sprite2D 的 `texture`；拿扫帚 = 在前臂节点下面加一个 Sprite2D。

验收：`godot --headless --import` 不报错；用 `--headless -s` 跑一段脚本加载场景、播每个动作、打印几个时间点的关节角度，和 `cutout_lib.pose_at` 算出来的一致（插件测过：攻击动作 0、0.1、0.18、0.2、0.24、0.3 秒六个点逐个相等）。再放进游戏截图看一次（`playtest-automation`<!-- TODO(lifesim): 原文指向 playtest-automation，本插件暂无对应技能 -->）。

### 6. 记录
- `assets/gen/manifest.csv` 里拆件图一行，`status` 写「已拆件」；部件 PNG、`.rig.json`、`.tscn` 一起提交。
- 动作表改过的数，DEVLOG 记一句为什么改（「走路脚底打滑：身体起伏从 4 改成 2.5」）。

## 踩过的坑
- **整数插值**：Godot 的值轨道按第一个关键帧的类型插值，第一个值写成 `0` 会被当成整数，转角只剩 0、-57.3°、-114.6° 这几档。`build_godot_rig.py` 一律写成 `0.0`；手改 `.tscn` 时也要带小数点。
- **脖子画在衣领外面**：头的 z 要比躯干低，脖子才藏得进去。默认骨架里头是 2、躯干是 3。
- **绿边**：深色描边和绿幕混出一圈暗绿，`remove_bg` 在离透明区 3 像素以内把绿压掉；还看得见就重新生图，背景换品红。
- **关节点按比例算会偏**：圆头关节的圆心离末端半个宽度，按长度的 10% 算会落在圆头外面。默认骨架用 `top_w: 0.5`（离上端半个端头宽度）。
