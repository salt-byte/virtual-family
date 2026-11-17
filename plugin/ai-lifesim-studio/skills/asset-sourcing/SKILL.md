---
name: asset-sourcing
description: 找开源游戏美术素材并核对许可证（CC0、CC-BY、CC-BY-SA、GPL），只下需要的文件，写署名。需要小人、图块、家具、图标、字体素材，或问「能用什么开源美术」时使用。找、核许可、署名的做法通用；文中的候选表和 LPC 是 graveholme（黑暗奇幻、2D 俯视像素）的结果，本项目按自己的画风重新搜。
---

# 找素材（asset-sourcing）

> **第一个动作**（先于建文档、搜索、写任何正文）：用读文件工具打开项目根目录的 `GAME_BRIEF.md` 和 `TASKS.md`<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。打不开，或有字段为空、写着「待定」→ 停下，向用户问清楚，写好再回来<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->。请求看起来很小（「列几件家具」「写一句提示」「调一下颜色」）、用户只要一份清单或文档、用户直接点名本 skill、或环境里别的工具要求先建文档，都照样先做这一步：这几种情况最容易跳过它。
>
> **做完后**：这一步（TASKS.md 的一行）做完，向用户交接<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->：做完了什么、用户点得开的链接或文件、下一步做什么，发完接着做下一步，不等回答；同一行里还有别的 skill 没做就接着做。只有这一步落在停靠点、或下一步有定调题时才停下来问（GAME_BRIEF「节奏」写着「每步停」的项目，照旧每步等用户点头）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。

> **候选表是 graveholme 的**：下面第 2 步的表是 graveholme（黑暗奇幻、2D 俯视像素、64px 角色）搜出来的结论，不是本项目的推荐清单。本项目按 ART_DIRECTION 的画风和视角重新搜、重新填表；LPC 只适合 2D 俯视像素，画风不对就不用它。找素材的步骤、许可证判断、只下需要的文件、署名格式通用。

## 先确认能访问哪里
云端环境通常只能访问 GitHub 和 npm（graveholme 里 itch.io、OpenGameArt、kenney.nl 都打不开）。在 GitHub 找；GitHub 上没有的，请用户下载后发过来。

## 步骤
1. **按需求列清单**（从 ART_DIRECTION 的必需清单和各设计页「需要的素材」一节来<!-- TODO(lifesim): 原文指向 game-design，本插件暂无对应技能 -->）：小人（需要换装吗？）、地面和墙、家具和物件、脏乱和掉落物、界面、字体。和 ART_DIRECTION 的画风对齐（有玩法参考时也对照它<!-- TODO(lifesim): 原文指向 game-design / mechanics-library 的玩法参考，本插件暂无对应技能 -->）（2D 俯视像素 / 3D 低模）。
2. **在 GitHub 搜候选，填对比表**（graveholme 的实际结果）：

   | 素材 | 结论 |
   |---|---|
   | iwenzhou/kenney（CC0） | 只有旧版 RPG 包，卡通风，不适合黑暗奇幻 |
   | pixel-boy/NinjaAdventure | 仓库只有 Demo 用到的一小部分，没有许可证文件 → 不用 |
   | DrJamgo/love2d-lpc-tiles | ✅ 地形、树、墓碑、帐篷、城墙、刑架、船、农作物 |
   | LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator | ✅ 分图层角色（身体/头/头发/衣服/盔甲/披风），有吸血鬼头、骷髅、野猪人头 |
   | LPC 狼 | 没找到 → 野兽敌人改成野猪人，相关支线跟着改名 |

   **没有许可证文件的仓库一律不用。**
3. **同一套体系优先**：graveholme 角色和地形都用 LPC，画风天然一致（见 `style-consistency`）。
4. **只拉需要的文件**：大仓库（LPC 生成器 8 万多个文件）用
   `git clone --filter=blob:none --sparse <url>` + `git sparse-checkout set <目录…>`，graveholme 最后只取了 83 张图、不到 1MB。
5. **核对许可并署名**：LPC 是 CC-BY-SA 3.0 / GPL 3.0（部分 OGA-BY 3.0），可以改、可以商用，但**必须署名**，衍生美术用同样协议。把仓库自带的 credits 文件复制到 `assets/credits/`，README 里写来源链接。
6. 字体：Noto Sans/Serif CJK（OFL）。像素风中文可找开源像素字体（例如 Fusion Pixel、Ark Pixel，未在 graveholme 里验证）。

## 3D 路线（配 three.js，未验证）
glTF 模型；常见 CC0 来源 Kenney、Quaternius 多在它们自己的网站上，需要用户下载后提供。
