---
name: localization-table
description: 管理游戏文本表和多语言：CSV 文本键、导入引擎翻译系统、截取中文字体。加新文字、加语言、出现方块字、问「文字放哪」时使用。
---

# 文本表与多语言（localization-table）

> **第一个动作**（先于建文档、搜索、写任何正文）：用读文件工具打开项目根目录的 `GAME_BRIEF.md` 和 `TASKS.md`<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。打不开，或有字段为空、写着「待定」→ 停下，向用户问清楚，写好再回来<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->。请求看起来很小（「列几件家具」「写一句提示」「调一下颜色」）、用户只要一份清单或文档、用户直接点名本 skill、或环境里别的工具要求先建文档，都照样先做这一步：这几种情况最容易跳过它。
>
> **文风**：本 skill 写的每个字照 `writing-style`（「肘击指令」，作者将生），动笔前先加载，写完跑它的 `check_style.py`，禁用零条才交付。加新文字、改文本表都照它；译文照同样的节奏和禁用原则（脚本只扫中文，外语人工判）。
>
> **做完后**：这一步（TASKS.md 的一行）做完，向用户交接<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->：做完了什么、用户点得开的链接或文件、下一步做什么，发完接着做下一步，不等回答；同一行里还有别的 skill 没做就接着做。只有这一步落在停靠点、或下一步有定调题时才停下来问（GAME_BRIEF「节奏」写着「每步停」的项目，照旧每步等用户点头）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。

## 结构
- `content/strings/game_text.csv`：手写。物品名、家具名、房间名、飘字（键名按项目自定）……第一列 `keys`，后面每种语言一列。
- `content/strings/dialogue.csv`：由 `yarn_lines.py` 从 `.yarn` 导出，键是 `#line:` 行号，**不手改**。<!-- TODO(lifesim): 原文指向 dialogue-authoring，本插件暂无对应技能；生活模拟游戏没有对白，这一条待定 -->
- 引擎启动时把两张表导入翻译系统（Godot：`project.godot` 的 `locale/translations`，导入后生成 `.translation`），运行时 `tr(键)` 取文字。

## 加新文字
1. 在 game_text.csv 追加行（脚本追加，避免手改破坏引号）。
2. 有从别处导出的文本表，改完重新导出<!-- TODO(lifesim): 原文指向 dialogue-authoring，本插件暂无对应技能 -->。
3. **截取字体**：`python3 ${CLAUDE_PLUGIN_ROOT}/skills/localization-table/scripts/build_fonts.py <项目根>`。从 Noto Sans/Serif CJK（OFL）里只截游戏用到的字（graveholme 约 1160 字、490KB），扫描 `scripts/` `tools/` 和 `content/` 下的 `.yarn/.csv/.json`。<!-- TODO(lifesim): 脚本扫的是 graveholme 的目录布局；本项目的文字在 game/packs/<id>/ 的 json 里，脚本未改，待定 -->不要扫二进制的 `.translation`，会读崩。
4. 重新导入工程。

## 世界里的文字也要指定字体
房子里的 Label（小人名字、头顶冒的话）如果没指定字体，桌面版会借系统字体显示正常，**网页版没有系统字体，会变成方块**。显式加载截取的字体。

## 加语言（未验证）
在两张 CSV 各加一列（如 `en`），字体换成覆盖该语言的版本。graveholme 只有中文一列，这一步还没实际跑过。
