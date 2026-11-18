# BORROWED

12 个技能从 AI RPG Studio（同一作者）复制，先逐字节复制整个目录，再只改措辞。脚本和 JSON 全部没改。
TODO 数 = 该技能目录下 `TODO(lifesim)` 的个数（共 91）。

通用改动（每个带「第一个动作」「做完后」两段的技能都有）：
- 「回 producer 向用户提问」改成「向用户问清楚」，「按 producer 第 6 节交接」改成「向用户交接」，各带 TODO。
- GAME_BRIEF.md / TASKS.md 保留文件名，带 TODO（它们由 producer 产出，本插件没有）。
- 小请求举例「写个故事大纲」等换成「列几件家具」等。
- 保留「停靠点」的意思，去掉 A/B/D 字母和步骤号，带 TODO。

| 技能 | 复制的文件 | 改了什么 | TODO | 没把握的 |
|---|---|---|---|---|
| art-direction | SKILL.md；references/ART_DIRECTION.template.md | description 换成生活模拟的触发语，去掉 game-concept 和「停靠点 B」；玩家/威胁/奖励/地标换成小人/家具/脏乱/掉落物/地标；颜色编码例子换成生病/脏乱；HUD 例子换成选中者状态和钱；必需资产例子换成底部条、商店面板；视觉原则例句换成老宅；模板的上游行、敌人行、停靠点标题同步改 | 13 | graveholme 的反面案例（尸骸之野像公园）原样留着；「CONCEPT」「设计页」「定调题」都悬空 |
| style-consistency | SKILL.md | description 换成房间/状态色调；区域→房间；神龛篝火→灶火灯烛；战斗背景→弹出面板背景；两处通用头 | 4 | 吸血鬼紫红色调、尸骸之野、色值保留并标明是 graveholme（RPG）的例子；「弹出面板背景按房间取色」是我换的等价说法，可能偏离原意 |
| asset-generation | SKILL.md；references/{prompt-rules.md,gen_config.example.json,prompts.example.json}；scripts/{gen_image.py,process_inbox.py}（可执行位保留） | 主角→小人；学徒→小人；必需清单换成小人/底部条/商店面板；攻击帧→干活帧，受击→挨骂；两处 GAME_BRIEF 写入点、项目主页、playtest-automation 加 TODO | 6 | prompts.example.json 里还有「画学徒」，按「脚本和数据不动」没改；第 8 步依赖 playtest-automation 的 --autotest，悬空 |
| asset-sourcing | SKILL.md | description 和第 1 步清单换成小人/家具/脏乱；设计页、玩法参考处加 TODO | 6 | 候选表是 graveholme 的结果（含「野猪人」「RPG 包」），原文已声明，没动 |
| asset-upload | SKILL.md | 清单示例（hero/forest）换成 person/floor；缺口示例换成小人/木地板 | 3 | 无 |
| asset-pipeline | SKILL.md；scripts/{make_seamless,build_assets.example,remove_bg,upscale,split_objects,grid_sheet,imgtools}.py | description 里的地图→房子/房间；prop.gd 与 tools/snap_world.gd 两处是 graveholme 做法，加 TODO | 6 | LPC 纸娃娃、3×6 拼边块、吸血鬼/游魂变体整节保留（原文已声明是 LPC / graveholme 专用）；build_assets.example.py 里仍有「吸血鬼」注释，没改 |
| cutout-animation | SKILL.md；references/{rig.humanoid_side.json,anims.humanoid_side.json,part-sheet-prompt.md}；scripts/{split_parts,build_godot_rig,cutout_lib,check_rig,preview_rig}.py | description 说明默认动作表是 idle/walk/attack/hurt、家务动作自己加；换装备→换衣服，拿武器→拿扫帚；攻击设计页引用改成家务动作；拆件提示词里「长兵器」→「长工具」 | 6 | 默认动作表仍是 attack/hurt，没加家务动作（那是新能力） |
| ui-layout | SKILL.md；references/ui-ux.md | description、决定举例、控件状态举例、对话框要求→弹出面板要求、观察清单、色板项都换成生活模拟；**新增**「生活模拟的界面骨架」一段（标了 NEW(lifesim)，5 行）；ui-ux.md 的界面清单行、HUD 行换词 | 14 | 「已有的、验证过的界面元素」（敌人红三角、NPC 气泡、对话框）和 ui-ux.md 的「剧情选择界面」「品类要点」整段是 RPG 内容，原样留着并标 TODO；ui-ux.md 第 3 行的《小说改编 RPG 设计师》是出处，没动 |
| web-release | SKILL.md | 之后按本项目跑通的路线重写了导出设置、步骤、发布前清单（gh-pages 分支、临时索引提交、zsh 冒号坑），TODO 从 17 个降到 9 个。原先：description 加「生活模拟游戏」；yarn、check_content、playtest、停靠点 D、verification.json 等处加 TODO；「能触发对话」→「能看到小人在动」；操作说明项换成拖拽、夸、骂 | 9 | 导出的 include_filter 里的 *.yarn 和 grep yarn 的检查项是 graveholme 的，主题包是 json，只加了 TODO |
| writing-style | SKILL.md；references/reference-novels.md；scripts/{check_style.py（可执行位保留）,voice_stats.py} | 只改 description、第 1 节三行例子表；其余只在指向缺失技能处追加 TODO，原文一字没动；出处、第 4 节原文、将生署名没改 | 12 | 整个技能偏叙事（对白、人物卡、story-bible、Yarn），生活模拟游戏用得上的主要是禁用语录和第 7 节；reference-novels.md 里的「亚瑟王项目」例子没动 |
| localization-table | SKILL.md；scripts/build_fonts.py | description 去掉「对白表导出」；键名例子、世界里的 Label 例子换成家里的；对白表、字体脚本扫描路径加 TODO | 7 | build_fonts.py 扫的是 scripts/ tools/ content/，本项目文字在 game/packs/<id>/，脚本没改，需要决定 |
| devlog | SKILL.md | description 加「生活模拟游戏」；数字例子、表格例子换成家具/房间；verify、playtest、变更影响清单、「制作人」处加 TODO | 5 | 踩坑例子（.yarn、verify.py）是 graveholme 的，原样留着 |

## 没有改的
- 所有 `.py`、`.json` 脚本和数据文件逐字节相同（`diff -rq` 只报上面列的 .md 文件）。
- 各文件里的 graveholme 经验和数字，只在原文没写明是例子的地方才加标注。
