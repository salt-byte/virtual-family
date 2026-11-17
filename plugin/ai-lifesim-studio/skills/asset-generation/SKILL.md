---
name: asset-generation
description: 美术路线选了「AI 生图」时用（另两条路线个别缺的素材要 AI 补时也用）：Claude 直接调用户的生图 API 出图并处理。第一次问用户用哪家服务、要 API 密钥和预算，测通；按 ART_DIRECTION 定风格线、列资产清单、写提示词，gen_image.py 出图，process_inbox.py 自动抠背景、切分、做无缝贴图，Claude 看图验收、不合格改提示词重生，整批再给用户看；角色动画按画风走派生帧、整张帧表或骨骼拆件（cutout-animation）。云端连不上生图服务时先请用户放行域名或在用户电脑上跑，都不行才退回用户自己出图。美术路线是开源素材库用 asset-sourcing，自己上传用 asset-upload。
---

# AI 生图素材（asset-generation）

> **第一个动作**（先于建文档、搜索、写任何正文）：用读文件工具打开 `GAME_BRIEF.md`（美术路线应是「AI 生图」；是开源素材库回 `asset-sourcing`，是自己上传回 `asset-upload`，只是补一两张缺的素材可以留下）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->和 `design/ART_DIRECTION.md`（没有先回 `art-direction`；第 6 节「素材规格和角色动画」空着也先回去填）。
>
> **文风**：提示词、清单里的描述照 `writing-style` 的禁用语录写，描述落到具体的形状、材质、颜色上。写完跑它的 `check_style.py`。
>
> **做完后**：这一步（TASKS.md 的一行）做完，向用户交接<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->：做完了什么、用户点得开的链接或文件、下一步做什么，发完接着做下一步，不等回答；同一行里还有别的 skill 没做就接着做。只有这一步落在停靠点、或下一步有定调题时才停下来问（GAME_BRIEF「节奏」写着「每步停」的项目，照旧每步等用户点头）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。

## 分工：出图和处理都在这边，用户给密钥、定预算、点头
Claude 用 `scripts/gen_image.py` 直接调用户的生图服务出图，出完跑 `scripts/process_inbox.py` 抠背景、切分、做无缝贴图，自己先看图挑毛病、改提示词重生，整批过了才拿给用户。用户要做的三件事：第一次给服务、密钥和预算；挑小人的长相、看「定风格」那三张；每批看一眼验收图。

两个脚本在 `${CLAUDE_PLUGIN_ROOT}/skills/asset-generation/scripts/`，在项目根目录跑（或加 `--root`），用法写在各自开头。`gen_image.py` 只用 Python 标准库，云端和用户的电脑上都能跑；`process_inbox.py` 调 `asset-pipeline` 的脚本，要 Pillow 和 numpy。

做法来自一篇小红书笔记《如何0成本用AI制作整套2D游戏》的流程（ChatGPT 出图、Photopea 手工抠图切片、腾讯 AI Studio 做行走动画）。出图改成直接调 API，手工那几步换成了脚本，动画换成按画风选做法（见 CREDITS.md）。

## 0. 第一次用：接上生图服务
一条消息问三件事，选项写取舍，回字母就行：

1. **用哪家服务**（`gen_config.json` 的 `provider`）：

| 选项 | provider | 好在哪 | 代价 |
|---|---|---|---|
| A. 火山方舟 Seedream（即梦、豆包同款） | `ark` | 国内付款方便，中文提示词听得懂，能带多张参考图 | 要在方舟控制台开通模型；尺寸有下限，报错就照报错调大 |
| B. OpenAI 图像接口（gpt-image 系列），或任何 OpenAI 兼容的中转站 | `openai` | 提示词照做得准；部分型号能直接出透明底 | 国外付款；中转站要填它给的接口地址 `base_url` |
| C. Google Gemini 图像（Nano Banana） | `gemini` | 带参考图时同一个角色最稳 | 国内网络连不上；尺寸只能按比例给 |
| D. 本机 Stable Diffusion WebUI / Forge | `sdwebui` | 不花钱 | 要用户电脑有显卡、WebUI 带 `--api` 开着；不支持参考图，同一个角色难保持一致；只能在用户电脑上跑（下面的 b） |

2. **API 密钥**。建议用户在服务后台给这个项目单独建一个密钥并设消费上限，做完删掉：密钥贴进对话会留在对话记录里。
3. **预算**：这个项目生图最多花多少钱，或最多出多少张。

拿到以后：
- **型号和单价现查。** 上这家服务的文档页和价格页（WebSearch）查当前型号名和每张的价钱，挑一个推荐给用户，写进 `assets/gen/gen_config.json`（模板 `references/gen_config.example.json`）。型号名几个月一换，不从记忆里填。
- **密钥只放 `.env`。** 项目根目录写一行 `GEN_API_KEY=...`，先确认 `.gitignore` 里有 `.env`，再提交任何东西。密钥不写进 GAME_BRIEF、DEVLOG、CREDITS、提交信息、记忆，回复里也不复述。告诉用户：密钥只存在这次会话的工作区里，换一个会话要再给一次。
- **测通：`gen_image.py --check`。**
  - 「连得上」→ 往下走。
  - 「密钥不对」「型号名不对」→ 照提示问用户，或回文档页再查型号。
  - 「被网络拦了」→ 云端会话默认只放行少数域名。一条消息把两个办法给用户：
    - a. **放行这个域名**：claude.ai 网页版的设置 → Capabilities（功能），把脚本报出的域名加进允许列表。个人付费版自己加，Team / Enterprise 版找管理员，免费版加不了。加好回一句，再测；这个会话还不通，就新开一个会话接着做。
    - b. **在用户电脑上跑**：这个会话连着用户的电脑（Claude 桌面版，有在用户电脑上跑命令的工具）时，把 `gen_image.py`、`gen_config.json`、`prompts.json` 和参考图放进用户连上的项目文件夹，密钥写进那边的 `.env`，在用户电脑上出图（只要 python3，不用装包），再把 `inbox/` 里的图取回云端处理。国内连不上国外服务、选了本机 SD WebUI，也走这条。
  - 两个都走不通，才退回手动：`gen_image.py --export-md` 导出 `assets/gen/prompts.md`，用户在自己的工具里出图，存成清单里的文件名放进 `assets/gen/inbox/`，之后的处理照常。
- 选的服务、型号、预算，和这家服务的条款（许不许商用、要不要署名，去条款页查）写进 GAME_BRIEF「怎么做」块的「美术路线」一行（没有就加）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->和 CREDITS.md。

## 流程

### 1. 风格线（一段话，钉死）
从 ART_DIRECTION 的视觉原则、语法和第 6 节的素材规格写一段「风格线」：视角（俯视 / 斜 45° / 侧面）、画风精度（像素风一格多少像素 / 卡通 2D 的线条粗细）、调色板（6–8 个色值）、光从哪边来、禁止项（不要写实、不要文字、不要投影）。每条提示词都以它开头，整套素材才像一个游戏。

第一批只生「定风格」的三张：小人站立图、一种主要地块、一个常见物件。小人用 `--n 3` 出三张候选，Claude 先看、跑偏的重生，再请用户挑一张：挑中的改名成 `hero_ref.png`，复制一份到 `assets/gen/ref/`。用户点了头，风格线才算定；之后每条提示词带上 `assets/gen/ref/hero_ref.png` 当参考图（`prompts.json` 的 `refs`）。

### 2. 资产清单 `assets/gen/manifest.csv`
```
id,role,type,size,description,sheet,sheet_pos,status,source,note
hero_ref,小人,character,96x128,小人站立正面，粗布短衫，腰挂浅木碗,hero_ref,0,待生成,,
rock_moss,地图物件,prop,64x64,长青苔的灰石头,env_01,0,待生成,,
tree_ash,地图物件,prop,96x128,白蜡树，叶子稀,env_01,1,待生成,,
tile_snow,地块,tile,32x32,踩实的雪地，带车辙,tile_snow,0,待生成,,
```
- `type`：`character` / `prop` / `ui`（单张，抠背景）、`tile`（地块，做无缝）、`frames`（整张帧表，按格子切）、`parts`（骨骼拆件图，交给 `cutout-animation`）。收图脚本按它分流。
- **按合集出图。** 同一类物件 4–8 个放进一张合集（`sheet` 写合集名，`sheet_pos` 写它在格子里的编号），一次生成，风格自然一致，也省钱。地块和角色各自单独一张。
- 按 ART_DIRECTION 第 7 节「必需 vs 可降级」排优先级：主要小人、核心地块、底部条、商店面板先做。一批 10–20 张，不一口气几百张。

### 3. 写提示词 `assets/gen/prompts.json`
一张图一条（例子在 `references/prompts.example.json`）：
```json
{"sheet": "env_01", "prompt": "〈风格线〉\n画一张素材合集：4 列 × 2 行的格子……", "size": "1536x1024",
 "refs": ["assets/gen/ref/hero_ref.png"], "background": "#F0F0F0", "grid": "4x2"}
```
`prompt` 照 `references/prompt-rules.md` 写：风格线 + 内容 + 让脚本好处理的出图要求。最要紧的三条：
- **纯色背景，和物体反差大**：物件用浅灰或白底；角色用 #00FF00 绿幕，角色身上有绿色就改用品红 #FF00FF。`background` 写这个颜色，收图时按它抠。服务能直接出透明底（文档上写明了，`gen_config.json` 开了 `native_transparent`）时写 `"transparent"`，提示词里就不写绿幕。
- **合集按格子排**：「N 列 × M 行，一格一个，居中，互不接触，四周留空」，按 `sheet_pos` 列出每格放什么；`grid` 写同样的「列x行」。
- **不要投影、地面、文字、边框**：这些会和物体连在一起，切不开。

### 4. 出图
- `gen_image.py --batch env_01 tile_snow` 出指定的几张，`--all` 出 inbox 里还没有的。先跑一次 `--dry-run` 看要发的请求。
- **预算由脚本管。** 每张记进 `assets/gen/usage.csv`；累计要超过 `gen_config.json` 的上限，脚本就停。停了就问用户加不加，不自己改上限。
- 服务拒绝（内容审核、尺寸不对、型号没开通）时，脚本原样打出服务的报错：照报错改提示词或 `size`，审核拦的换掉触发词（武器、血、裸露这一类写法），再出。

### 5. 收图：`process_inbox.py`
一条命令按清单的 `type` 分流，调 `asset-pipeline` 的脚本：

| type | 处理 | 中间产物（`assets/gen/out/<sheet>/`） |
|---|---|---|
| 合集、`frames` | `split_objects.py --grid`，名字照清单 | `_contact.png`：框和名字对上没有 |
| `character` / `prop` / `ui` 单张 | `remove_bg.py`，按 `background` 的颜色抠；服务出了透明底就不抠 | 抠完的图 |
| `tile` | `make_seamless.py`；像素风在 `gen_config.json` 写 `pixel_size`，缩到一格大小 | `_preview.png` 3×3 平铺 |
| `parts` | 不处理，转 `cutout-animation` | — |

成品复制进 `assets/chars`、`assets/props`、`assets/tiles`、`assets/ui`（`gen_config.json` 的 `out_dirs` 可改），清单的 `status` 改成「已处理」、`source` 填服务、型号和日期，最后拼一张验收图 `assets/gen/review/<时间>.png`。

**Claude 先自己验。** 用读文件工具看验收图，再看每张合集的 `_contact.png`、地块的 `_preview.png`，逐张对照：
- 和 `hero_ref.png`、ART_DIRECTION 的目标图比，风格线跑没跑偏（视角、线条、调色板、光的方向）；
- 合集数量对不对，有没有两个物件粘成一块、一个物件被切成两半；
- 透明边干不干净（绿边、白边），物体里有没有被抠出洞；
- 脚本打出来的 ⚠ 提醒。

不合格的：清单 `status` 改成「重做」，`note` 写原因；照 `prompt-rules.md` 最后那张表改提示词，`gen_image.py --batch <sheet> --force` 重生（旧图挪进 `inbox/_old/`），再 `process_inbox.py --sheet <sheet>`。同一张重生两次还不对，停下来带着图问用户。不手工修图。

### 6. 角色动画：照 ART_DIRECTION 第 6 节选的做法
- **一张图派生帧**（像素风小角色）：只生一张站立图，帧在这边做：腿两帧交替加身体上下 1 像素，干活帧（搬东西、打扫）把手臂区域旋转、位移 2–3 帧，转身、挨骂先用站立图闪白代替，列进可降级。排版按 `asset-pipeline` 的帧布局。
- **整张帧表**：提示词要「同一个角色，4 方向 × 3 帧，排成 4 行 3 列，绿幕」，带上 `hero_ref.png`，清单 `type` 写 `frames`、`prompts.json` 写 `"grid": "3x4"`；收图后逐帧和参考图比脸、衣服、比例，跑偏的帧整张重生，不将就。
- **骨骼拆件**（卡通、手绘 2D）：转 `cutout-animation`。拆件图照它的 `references/part-sheet-prompt.md` 写进 `prompts.json`（`type` 写 `parts`），同样用 `gen_image.py` 出。

### 7. 一批交给用户
自己验过的一批，交接时给：验收图（项目主页的美术页，和仓库里的图<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->）、这批出了几张、重生了几张、累计花了多少、还剩多少预算（读 `usage.csv`）。用户指出的问题按第 5 步改。

### 8. 放进游戏验收
- 放进游戏在真实视口截图（`playtest-automation` 的 `--autotest`）<!-- TODO(lifesim): 原文指向 playtest-automation，本插件暂无对应技能 -->，和 ART_DIRECTION 的目标图并排看：风格线有没有跑偏；
- 像素密度、和别的素材放在一起的色调（`style-consistency`）；
- 不通过的记回清单 `status=重做` 并写原因，回第 4 步。

### 9. 来源和版权
`manifest.csv` 的 `source` 列由收图脚本填（服务、型号、日期）；CREDITS.md 加一节「AI 生成素材」，写用的服务、型号和它的条款（有的服务不许商用或要求署名）。个别素材来自开源素材库的，照 `asset-sourcing` 的署名规则。

## 不做的事
- 不替用户注册账号、充值、开通模型：这些用户在服务的网页上自己做。
- 不超预算：到上限就停下来问，不自己改上限。
- 密钥不进仓库、不进任何文档和记忆，回复里不复述。
- 不用生图替代设计：ART_DIRECTION 没定的东西，不靠「多生几张挑」来定。
- 不手工逐张修图。脚本处理不了的，改提示词重新生。
