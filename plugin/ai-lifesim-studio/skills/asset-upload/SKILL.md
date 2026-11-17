---
name: asset-upload
description: 美术路线选了「自己上传」时用：收用户自己画的、买的或别处授权的素材，核对授权，盘点成清单，对照 ART_DIRECTION 的素材规格和「必需 vs 可降级」查缺什么、哪些不合规格，再交给 asset-pipeline 的脚本处理（抠背景、切分、放大、无缝贴图），角色动画按画风走派生帧、整张帧表或骨骼拆件（cutout-animation）。用户发来一批图、一个压缩包、说「我有自己的素材」时使用。美术路线是开源素材库用 asset-sourcing，AI 生图用 asset-generation。
---

# 自己上传的素材（asset-upload）

> **第一个动作**（先于建文档、搜索、写任何正文）：用读文件工具打开 `GAME_BRIEF.md`（美术路线应是「自己上传」；只是补一两张也可以留下）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->和 `design/ART_DIRECTION.md`（没有先回 `art-direction`；第 6 节「素材规格和角色动画」空着也先回去填）。
>
> **文风**：清单、给用户的缺口说明照 `writing-style` 的禁用语录写，结论放第一句。写完跑它的 `check_style.py`。
>
> **做完后**：这一步（TASKS.md 的一行）做完，向用户交接<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->：做完了什么、用户点得开的链接或文件、下一步做什么，发完接着做下一步，不等回答；同一行里还有别的 skill 没做就接着做。只有这一步落在停靠点、或下一步有定调题时才停下来问（GAME_BRIEF「节奏」写着「每步停」的项目，照旧每步等用户点头）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。

## 1. 收
- 用户把素材放进仓库的 `assets/upload/`（或在对话里附上、发压缩包，由你放进去）。原样保留一份，处理只在副本上做：处理结果放 `assets/chars/`、`assets/props/`、`assets/tiles/`。
- 压缩包解开到一个新的空目录里再看；`.psd`、`.kra`、`.aseprite` 这类分层文件，请用户导出成 PNG（一层一张，或者合成一张），插件不读分层文件。
- 用户的电脑连着时，用设备桥直接从他给的文件夹取。

## 2. 核授权（每一个来源问一次）
| 来源 | 要问清 | 写进 CREDITS.md |
|---|---|---|
| 用户自己画的 | 是不是全部自己画的；有没有描别人的图 | 「美术：<用户署名>」 |
| 买的素材包 | 店铺和素材包名、许可条款原文的链接；允不允许改、允不允许在网页游戏里用、允不允许把图放进公开仓库 | 素材包名、作者、条款链接 |
| 朋友或画师给的 | 对方同意的范围（这个游戏能用 / 能改 / 能公开） | 作者署名，对方要求的写法 |
| 网上找的、来源说不清的 | 不用。请用户换成上面三种之一，或转 `asset-sourcing` 找开源的 | — |

买的素材包大多不允许把原图放进公开仓库：照条款把这部分放进 `.gitignore`，README 写怎么取得，或者 GAME_BRIEF 的仓库改成私有。问清以前不提交。

## 3. 盘点成清单 `assets/upload/manifest.csv`
```
id,file,role,type,size,matches_spec,license,status,note
person_parts,upload/person_parts.png,小人,character-parts,1024x1024,是,自己画,待处理,
floor_tiles,upload/floor.png,地块,tileset,512x512,一格 48 像素，规格是 32,买的素材包 X,待处理,要缩放
```
每张图打开看一遍（看图，不只读文件名），填：它是什么、尺寸、合不合 ART_DIRECTION 第 6 节的规格（视角、画风精度、朝向、背景做法）。

## 4. 查缺口，告诉用户
对照 ART_DIRECTION 第 7 节「必需 vs 可降级」，给用户一张短表：
- **缺的必需素材**：每样写清要什么（「小人朝左的走路帧」「木地板地块，32 像素一格，能平铺」）。用户补，或者这几样改走 AI 生图（`asset-generation`），在清单 `source` 列写清。
- **不合规格的**：视角、像素密度、朝向对不上的，说清差在哪；能用脚本修的（尺寸、背景、平铺）标「脚本修」，修不了的（视角不同）请用户换。

缺口没定，不往下处理。

## 5. 处理：交给 asset-pipeline 的脚本
和 AI 生图共用一套（`asset-pipeline/scripts/`）：
| 素材 | 处理 |
|---|---|
| 一张图里多个物件 | `split_objects.py --key`；物件按格子排的加 `--grid 列x行` |
| 带纯色底的单张图 | `remove_bg.py` |
| 地块、墙面 | `make_seamless.py`（本来就能平铺的先跑 `--check`，倍数在 1.5 以下就不动） |
| 尺寸不对 | `upscale.py`：像素风整数倍，卡通 `--mode smooth --fit <长边>` |
| 图块表（tileset） | `grid_sheet.py` 画网格、看坐标，照 asset-pipeline「图块」一节选区 |

## 6. 角色动画：照 ART_DIRECTION 第 6 节
- 用户给的是一张张帧（走路 1、2、3……）：按帧布局排成帧表，逐帧查脚底高度是否一致。
- 用户给的是分好的部件：转 `cutout-animation`，`split_parts.py --from-dir`。
- 用户只有一张完整的角色图，又选了骨骼拆件：请用户在自己的软件里拆成部件（要求见 `cutout-animation/references/part-sheet-prompt.md`），或者拿这张图当参考图让 AI 生拆件图。
- 选了派生帧：照 `asset-generation` 第 5 步。

## 7. 验收
和 `asset-generation` 第 6 步一样：放进游戏截图，和目标图并排看；透明边、像素密度、和别的素材放在一起的色调（`style-consistency`）。清单里每张的 `status` 改成「已处理」或「请用户换」。
