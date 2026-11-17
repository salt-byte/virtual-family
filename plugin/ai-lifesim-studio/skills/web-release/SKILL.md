---
name: web-release
description: 把生活模拟游戏发布成网页版（GitHub Pages），让人点开链接就能玩；同时推送源码和开发记录。导出设置是 Godot 的（跑通的路线）；three.js 和自写 Canvas 本身就是网页，跳过导出，发布步骤和发布前清单照用。用户问「必须下载才能玩吗」「放到 GitHub 上」「发布」时使用。
---

# 网页发布（web-release）

> **第一个动作**（先于建文档、搜索、写任何正文）：用读文件工具打开项目根目录的 `GAME_BRIEF.md` 和 `TASKS.md`<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。打不开，或有字段为空、写着「待定」→ 停下，向用户问清楚，写好再回来<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->。请求看起来很小（「列几件家具」「写一句提示」「调一下颜色」）、用户只要一份清单或文档、用户直接点名本 skill、或环境里别的工具要求先建文档，都照样先做这一步：这几种情况最容易跳过它。
>
> **做完后**：这一步（TASKS.md 的一行）做完，向用户交接<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->：做完了什么、用户点得开的链接或文件、下一步做什么，发完接着做下一步，不等回答；同一行里还有别的 skill 没做就接着做。只有这一步落在停靠点、或下一步有定调题时才停下来问（GAME_BRIEF「节奏」写着「每步停」的项目，照旧每步等用户点头）<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。

> **引擎不是 Godot 时**：下面「导出设置」只对 Godot 成立。three.js 和自写 Canvas 本身就是静态网页：没有导出这一步，把入口 HTML、脚本和 `content/`、素材一起推到 GitHub Pages 即可；后面的发布步骤、发布前清单、无头浏览器复测（`playtest-automation` 的网页版测试<!-- TODO(lifesim): 原文指向 playtest-automation，本插件暂无对应技能 -->）照用。要注意的坑换成：`content/` 里的 json / yarn 用 `fetch` 读，本地直接双击打开 HTML 会被浏览器拦，测试和发布都要走 http 服务器；路径大小写在 GitHub Pages 上是敏感的。

## 导出设置（export_presets.cfg，验证过）
```
platform="Web"
export_filter="all_resources"
include_filter="*.yarn, *.json, *.csv"    ← 必须：Godot 只打包它认识的资源，自定义格式会被漏掉 <!-- TODO(lifesim): 原文是 graveholme 的 yarn 对白文件；本项目的主题包是 game/packs/<id>/ 下的 json，过滤规则要按需核对 -->
exclude_filter="tools/*"
variant/thread_support=false              ← GitHub Pages 不能设跨域隔离头，必须关线程
```
需要对应版本的导出模板（版本要求另查）<!-- TODO(lifesim): 原文指向 godot-project-structure，本插件暂无对应技能 -->。

## 步骤
1. 内容改完：跑 `build_fonts.py`，以及项目里的内容检查脚本<!-- TODO(lifesim): 原文指向 dialogue-authoring / game-data-schema 的 yarn_lines.py、check_content.py，本插件暂无对应技能 -->。
2. 重新导入：`godot --headless --path . --import`。
3. 导出：`godot --headless --path . --export-release "Web" docs/index.html`。产物约 42MB（`index.wasm` 35MB、`index.pck` 7MB）。`docs/` 里放一个空的 `.gdignore`，免得 Godot 把导出的文件当资源导入。
4. **测导出版**（`playtest-automation` 第 3 层<!-- TODO(lifesim): 原文指向 playtest-automation，本插件暂无对应技能 -->），确认能进游戏、能看到小人在房子里动。
5. 仓库结构：已建好的仓库的根目录就是项目源码<!-- TODO(lifesim): 原文指向 producer 流程里的步骤号，本插件暂无对应技能 -->（`.godot/` 和生成的 `.translation` 由 `.gitignore` 挡掉）；网页版放 `docs/`，加一个 `.nojekyll`。README、DEVLOG、素材署名本来就在根目录。不另建发布仓库（`producer/references/github-sync.md`<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->）。
6. 提交并推送。提交信息写清本轮改了什么。
7. **先看 GAME_BRIEF 的「版权与发布」**，并在「怎么做」块补「交付形式」一行<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md / TASKS.md，本插件暂无对应技能 -->。 写着「只自己玩」或原作在版权期内的，不开 GitHub Pages（公开链接谁都能打开），只给用户本人能打开的试玩方式：claude.ai 的私有页面，或导出包发给用户本人。用户这时改口要公开，先提醒版权风险，确认后改 GAME_BRIEF 再发。
8. 第一次发布时请用户在仓库 Settings → Pages 选 main 分支、`/docs` 目录（这一步 API 可能被代理拦住，需要用户手动点）。链接：`https://<用户>.github.io/<仓库>/`。

## 推送踩过的坑
- 403：用户要先在 GitHub 给 Claude 的 GitHub App 授权这个仓库（settings/installations）。
- 推送偶尔返回 `remote rejected (failure)`，原样重试一次就好。
- 没有 rsync 时用 `tar cf - … | (cd 目标 && tar xf -)` 复制。

## 发布前清单（全过才到发布的停靠点）<!-- TODO(lifesim): 原文指向 producer 的「停靠点 D」，本插件暂无对应技能 -->
| 项 | 怎么查 |
|---|---|
| `qa/verification.json` 六项 PASS，run_id 是本次改动之后的<!-- TODO(lifesim): 原文指向 playtest-automation，本插件暂无对应技能 --> | 看文件；旧的 run 不算 |
| 旧存档能读 | 用上一版的 `save.json` 起游戏，`--playtest` 或手动进到地图 |
| 没有方块字 | `--autotest` 截图里每屏看一眼；新加的字要在 `build_fonts.py` 的字表里 |
| 导出包含内容文件 | `grep -a -o "res://content/dialogue/[A-Za-z]*\.yarn" index.pck \| sort -u` 数量 = 源文件数；json / csv 同理<!-- TODO(lifesim): 原文是 graveholme 的对白文件路径，本项目改查 packs 下的 json，待定 --> |
| CREDITS 齐 | 新用的素材、新借的 skill 都在 CREDITS.md 里 |
| 首页有操作说明 | README / 页面上有拖拽、夸、骂、快捷键的说明 |
| 网页版冒烟 | `web_smoke.js` 能进游戏、能看到小人在动<!-- TODO(lifesim): 原文指向 playtest-automation，本插件暂无对应技能 --> |
| DEVLOG 本节写了 | 含决策和证据路径 |
这张表来自 claude-code-game-studios 的 release-checklist，按我们的项目重写。

## 推送前：停下来确认
导出版测试通过后、推送之前，把本轮改动清单交给用户，问用户要不要发布<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->。


## 本模块需要确认的问题

先读已确认材料，仅就影响当前步骤的缺口提问，给出具体方案与取舍。

发布前核对目标平台、交付形式及发布目的地，已有决定直接沿用。给用户可检查的版本、验证结果与已知问题，在发布停靠点确认本次发布。
