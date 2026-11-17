# AI Life-Sim Studio（生活模拟游戏工坊）

给「家庭生活模拟」游戏用的 Claude Code 插件。小人住在一栋房子里，自己会饿、会病、会不高兴，也会干活、打扫、睡觉；
玩家把他们拖到东西上、夸、骂、买吃的买药买家具、扩建房子，一代一代传下去。

和姊妹插件 AI RPG Studio 的区别：游戏代码是固定的内核（本仓库 `game/` 下的 Godot 4.7.2 工程，
`game/kernel/sim` 是模拟，`game/kernel/view` 是视图层）。每个新游戏是一个**主题包**：
`game/packs/<id>/` 下一组 JSON 表（需求、行为、物件、房间、营生、物品、病、脏乱、收集品、目标、名字、pack.json，可选 ui.json）加美术。
第一个包是 `qijia`（《起家》，古代中国一户人家）。所以这个插件的技能负责填包、做美术，不给每个游戏生成玩法代码。

## 现状：骨架，还不是完整工作流

现在只有 12 个和题材无关的技能，从 AI RPG Studio 复制过来，换了措辞。
**不能当成完整的工作流安装使用**：技能里对制作人流程、设计页、项目立项文件的引用都还悬着，
所有这类地方留了 `TODO(lifesim)` 标记，`grep -rn "TODO(lifesim)" skills` 能找全。
每个技能改了什么、留了几个标记见 BORROWED.md，来源和许可见 CREDITS.md。

## 已有的 12 个技能

| 技能 | 一句话 |
|---|---|
| art-direction | 先定一页 ART_DIRECTION.md 和目标图，再找素材或生图 |
| style-consistency | 混用多套素材时，用整体色调、房间底色把画面统一成一个游戏 |
| asset-generation | 调用户的生图 API 出图，脚本抠背景、切分、做无缝贴图，Claude 验收 |
| asset-sourcing | 找开源美术素材，核对许可证，写署名 |
| asset-upload | 收用户自己的素材，核授权，盘点缺口 |
| asset-pipeline | 抠背景、切合集、放大、无缝贴图、图块选区，一套脚本 |
| cutout-animation | 小人拆成头、躯干、四肢，自动定关节，做走路等动画，生成 Godot 场景 |
| ui-layout | 界面设计方法，含本项目定下的生活模拟界面骨架 |
| web-release | 发布成网页版（GitHub Pages），附发布前清单 |
| writing-style | 全部文字的文风标准「肘击指令」（作者将生）和检查脚本 |
| localization-table | 文本表、多语言、截取中文字体 |
| devlog | 按统一格式把开发过程记进 DEVLOG.md |

## 还没有的

- 制作人流程（接需求、排步骤、停靠点、交接）
- 填主题包的技能：行为表编排、状态与词语阶梯、营生、病与症状、房间与家具、目标与掉落物、主题包校验
- 平衡、日记、截图这类工具技能

## 许可

待定，见 CREDITS.md。
