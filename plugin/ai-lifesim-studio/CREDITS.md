# CREDITS

## 本插件借自 AI RPG Studio 的部分

本插件的 12 个技能（art-direction、style-consistency、asset-generation、asset-sourcing、asset-upload、asset-pipeline、cutout-animation、ui-layout、web-release、writing-style、localization-table、devlog）来自同一作者（Yudie Deng）的 AI RPG Studio 插件，复制后只做了换题材的最小改动，见 BORROWED.md。下面是 AI RPG Studio 的 CREDITS.md 里和这 12 个技能及其脚本有关的条目，原样保留。

# 以下原样取自 AI RPG Studio 的 CREDITS.md

本插件的方法有一部分改造自开源的 skill 和工作流。每条写清：仓库、许可、借了什么、改了什么。
原则：MIT / Apache-2.0 的可以改写，保留本署名；没有许可文件的只借原则、用自己的话写，不复制原文。

## 文风标准

| 我们的 skill / 文件 | 来源 | 作者 | 用了什么 | 改了什么 |
|---|---|---|---|---|
| writing-style（全插件的文风标准）；dialogue-authoring/references/voice-prompt.md、story-review/references/criteria.md 的 F 层 | 「肘击指令」（用户提供的文风提示词） | **将生**（原文要求：二传必须标注将生） | 原文全文，一字不改收进 writing-style 第 4 节 | 加了适用范围（叙事 / 功能 / 文档）、和逻辑规则的关系、`check_style.py`、自检清单；原文示范语段只校语感，不进游戏文本 |

## 改造自开源 skill 的部分

| 我们的 skill / 文件 | 来源仓库 | 许可 | 借了什么 | 改了什么 |
|---|---|---|---|---|
| writing-style 第 7 节、check_style.py 的 A1–A8 | larashero3-dotcom/lieflat-less-ai-tone（随 writing-dna-skill 发布） | PolyForm Noncommercial 1.0.0 | 去 AI 味的规则方向、「不当成毛病的」清单、信息守恒原则、各项实测频率（AI 300 篇对人写的 329 篇） | 规则、正则和说明全部自己写，只引用实测数字并注明出处；没有复制原文 |
| writing-style 第 6 节、references/reference-novels.md、voice_stats.py | larashero3-dotcom/writing-dna-skill | PolyForm Noncommercial 1.0.0 | 先把范文拆成分层规则、写之前再回读几篇最接近的原文校语感 | 只留对白和旁白用得上的四层，改成游戏项目里的文风卡，统计脚本自己写；没有复制原文 |
| quest-design / game-concept / game-design / art-direction / playtest-automation / producer | novel-to-game | MIT | 七条硬否决（concept-method）、设计页输出合同、白盒先于美术、QA 六项证据与 NOT_RUN ≠ PASS、流程契约「上游文档是事实」、预算与范围复盘、intake 的「未确认假设」 | 全部按 RPG + Godot 的流程重写；没有复制任何合同原文 |
| producer / game-design / devlog / web-release / balancing / playtest-automation | claude-code-game-studios | MIT | 设计页八节、quick-design、测试证据表（留存截图）、「解析通过不等于跑过」、release-checklist、balance-check 三判据、session-state（压缩后先读状态文件）、propagate-design-change、scope-check、决策记录；/brainstorm 的提问方式（选项写成体验、回字母即可）|  合并为我们的 TASKS.md 当前状态段、变更影响清单、范围复盘；提问方式改写成 producer 的「定调题」题库；没有采用它的 49 个 agent 分工 |
| ui-layout | game-ui-design（jeremylongworth/AgentSkills） | MIT | 先列玩家要做的决定、控件全状态、对话框要求 | 按我们的屏重写 |
| ui-layout / art-direction | game-ui-design-workflow | MIT | 风格契约文件 | 并入 ART_DIRECTION 的界面风格契约表；**未用**其生图部分 |
| ui-layout | awesome-gamedev-agent-skills（game-ui-ux） | Apache-2.0 | 锚点布局、界面栈、事件驱动 HUD、键盘焦点 | 四条用自己的话写；其余（手机刘海、手柄）未用 |
| asset-generation | higgsfield-game-generation | 无许可文件 | 「风格线 → 资产清单 → 一张图派生一套动画」的流程思路 | 只借流程思路，不接它的服务；生图调用户自己的生图 API（`gen_image.py`） |
| asset-generation / asset-pipeline | 小红书笔记《如何0成本用AI制作整套2D游戏》 | 无（公开笔记） | 「AI 出图 → 抠背景 → 放大 → 透明 PNG → 切分合集 → 无缝贴图 → 绿幕角色做动画」的流程 | 只借流程；在 ChatGPT 网页里手动出图改成直接调 API，手工步骤（Photos、Photopea）改写成本插件的脚本，图生视频做动画的那一步没有采用，换成按画风选派生帧、帧表或骨骼拆件 |

## 游戏素材（graveholme）
见 graveholme 仓库的 CREDITS：LPC（Liberated Pixel Cup）角色与图块，CC-BY-SA 3.0 / GPL 3.0，作者名单随素材包。

## 本插件自己的许可
待用户决定（建议 MIT，和主要来源一致）。
