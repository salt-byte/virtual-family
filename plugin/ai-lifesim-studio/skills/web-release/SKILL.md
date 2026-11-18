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
include_filter="*.json"                   ← 必须：Godot 只打包它认识的资源，主题包的 json 不写这行会被漏掉
exclude_filter="tools/*"
variant/thread_support=false              ← GitHub Pages 不能设跨域隔离头，必须关线程
```
需要和编辑器同版本的导出模板（本项目是 4.7.2）。`game/tools/export_web.sh` 会先检查，缺了就说缺什么、怎么装，然后退出，不会自己下载。

## 步骤（本项目跑通的路线）
1. 内容改完：`python3 game/tools/build_font.py`，把主题包和界面用到的字截进 `game/assets/fonts/ui.otf`。它列出缺的字时必须一个都不缺，否则网页上是方块。
2. 导出：`./game/tools/export_web.sh`，产物在 `build/web/`（`build/` 不进 git）。约 38MB，大头是 `index.wasm`。
3. **先在本地测导出版**：`python3 -m http.server -d build/web 8060`，打开 http://localhost:8060，确认能进游戏、能看到小人在房子里动。直接双击 html 打不开，必须走 http 服务器。
4. **先看 GAME_BRIEF 的「版权与发布」**<!-- TODO(lifesim): 原文指向 producer 产出的 GAME_BRIEF.md，本插件暂无对应技能 -->。写着「只自己玩」或原作在版权期内的，不开 GitHub Pages（公开链接谁都能打开），只给本地链接或导出包。
5. 推源码：`git push origin main`。
6. 推网页版到 `gh-pages` 分支，**不放进 main**。不用切分支、不用另建目录，用一个临时索引把 `build/web` 直接做成一个提交：
   ```bash
   touch build/web/.nojekyll
   TREE=$(GIT_INDEX_FILE=$(mktemp -u) sh -c 'git --work-tree=build/web add -A . && git write-tree')
   C=$(git commit-tree "$TREE" -m "web build from main@$(git rev-parse --short HEAD)")
   git push -f origin "${C}:refs/heads/gh-pages"
   ```
   `gh-pages` 只放导出产物，每次整个替换，所以用 `-f`。推之前先问用户（推送就是公开），用户说过「做完直接推」的照办。
7. 第一次发布时，请用户在仓库 Settings → Pages 选 `gh-pages` 分支、根目录 `/`（API 可能被拦，需要用户手动点）。链接：`https://<用户>.github.io/<仓库>/`。部署要一两分钟，看到旧版就让用户按 Cmd+Shift+R 强制刷新。

## 推送踩过的坑
- 403：用户要先在 GitHub 给 Claude 的 GitHub App 授权这个仓库（settings/installations）。
- 推送偶尔返回 `remote rejected (failure)`，原样重试一次就好。
- 没有 rsync 时用 `tar cf - … | (cd 目标 && tar xf -)` 复制。
- **zsh 里变量后面紧跟冒号要加花括号**：`"$C:refs/heads/gh-pages"` 会被 zsh 当成 `$C` 加修饰符 `:r`，推送报 `src refspec … does not match any`。写成 `"${C}:refs/heads/gh-pages"`。
- 本机 `gh auth status` 显示钥匙串登录失败时，`git push` 走 git 自己的凭据，照样能推，不用先修 gh。
- 线上是不是旧版：`curl -sI https://<用户>.github.io/<仓库>/index.pck | grep -i last-modified`。

## 发布前清单（全过才到发布的停靠点）<!-- TODO(lifesim): 原文指向 producer 的「停靠点 D」，本插件暂无对应技能 -->
| 项 | 怎么查 |
|---|---|
| 验收过了 | `pack-verification` 四样都过，且是本次改动之后跑的 |
| 旧存档能读 | 测试里有旧存档用例（`run.sh save`）；改了房子再用上一版的 `save_<包名>.json` 实际开一次 |
| 没有方块字 | `build_font.py` 报零个缺字；本地导出版里翻一遍商店、家人面板、动作名 |
| 导出包含主题包 | `strings -n 6 build/web/index.pck \| grep -o "packs/[a-z_]*/[a-z_]*\.json" \| sort -u \| wc -l` 等于 `ls game/packs/*/*.json \| wc -l`（包里存的路径不带 `res://`） |
| CREDITS 齐 | 新用的素材、新借的 skill 都在 CREDITS.md 里 |
| 首页有操作说明 | README / 页面上有拖拽、夸、骂、拖动画面、滚轮缩放、点人跟随的说明 |
| 网页版冒烟 | 第 3 步的本地导出版能进游戏、能看到小人在动<!-- TODO(lifesim): 自动化的网页冒烟测试还没有 --> |
| DEVLOG 本节写了 | 含决策和证据路径 |
这张表来自 claude-code-game-studios 的 release-checklist，按我们的项目重写。

## 推送前：停下来确认
导出版测试通过后、推送之前，把本轮改动清单交给用户，问用户要不要发布<!-- TODO(lifesim): 原文指向 producer，本插件暂无对应技能 -->。


## 本模块需要确认的问题

先读已确认材料，仅就影响当前步骤的缺口提问，给出具体方案与取舍。

发布前核对目标平台、交付形式及发布目的地，已有决定直接沿用。给用户可检查的版本、验证结果与已知问题，在发布停靠点确认本次发布。
