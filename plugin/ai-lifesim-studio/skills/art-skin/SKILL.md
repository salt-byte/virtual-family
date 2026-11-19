---
name: art-skin
description: 把画好的图接进游戏：主题包的 art.json 写哪张贴图铺哪块地、哪张图是哪件家具哪种脏乱哪个人、骨骼拆件的小人做哪个动作摆哪个姿势；没图的地方照旧画白盒；import_art.py 把素材缩到游戏用的尺寸；人不穿模（use_spot、stop_point、按脚排前后、低墙按墙顶排、名字单独一层）。素材已经有了（asset-generation / asset-upload / cutout-animation 之后）、要放进游戏时使用；用户说「穿模」「人站在桌子里」「字叠在一起」「小人不动」「换一套美术」时也用。
---

# 美术皮（art-skin）

内核不认识任何一张图。主题包里一份 `art.json` 说清哪张图画什么，视图层的 `PackSkin` 照着画；写了的用图，没写的照旧画白盒（色块、圆、名字牌）。所以美术可以一件件往里接，接一半游戏也能玩；没有 `art.json` 的包（`_smoke`）画法和以前完全一样。

## 数据长什么样

`game/packs/<id>/art.json`，《起家》节选：

```json
{
  "dir": "art", "accent": "#E5533C", "pickup": "#4FB3E8",
  "tiles": {
    "grass": {"file": "tiles/grass.png", "size": [192, 144], "soften": 0.12},
    "plaster": {"file": "tiles/wall.png", "fit_height": true}},
  "sprites": {"kang": "props/kang.png", "mess_mud": "props/mess_mud.png", "dog": "chars/dog.png",
              "father": "chars/father.png", "sleeper": "chars/sleeper.png", "icon_ill": "props/icon_ill.png"},
  "ground": "grass", "compound_ground": "yard",
  "floors": {"hall": "floor_hall", "kitchen": "floor_earth"},
  "decor": {"#86C6DA": {"tile": "water"}, "#5F8F43": {"sprite": "big_tree"}, "#A8D8E6": {"hide": true}},
  "scenery": [{"sprite": "scarecrow", "x": 11.0, "y": 29.2, "w": 1.4}],
  "walls": {"house": "plaster", "compound": "rammed_earth", "gate": "gatehouse", "sill": "door_sill",
            "fence_ns": ["fence_ns", "fence_ns_b"]},
  "objects": {"kang": "kang", "threshold": "door_sill", "ayun_hoop": "embroidery_frame"},
  "messes": {"mud": "mess_mud", "leaves": "mess_droppings"},
  "pets": {"dog": {"sprite": "dog", "height": 46}},
  "people": [
    {"stage": "adult", "sex": "male", "sprite": "father", "height": 90,
     "rig": "rigs/father/father.rig.json", "asleep": "sleeper"},
    {"stage": "elder", "sprite": "grandpa", "height": 80, "rig": "rigs/grandpa/grandpa.rig.json", "lean": 11},
    {"stage": "baby", "sprite": "baby", "height": 26, "lying": true}],
  "unwell": {"sprite": "icon_ill", "need": "health", "below": 50},
  "poses": {"on": ["kang", "stool", "stone_bench", "threshold"],
            "objects": {"kang": "sit", "dining_table": "eat"},
            "actions": {"sleep": "sleep", "shell_beans": "sit", "eat_porridge": "eat", "saw_timber": "work"}}
}
```

| 键 | 管什么 |
|---|---|
| `tiles` | 无缝贴图。`size` 是一次重复盖多少房子像素；`soften` 往奶油色里调淡多少；墙面 `fit_height` 按墙高拉伸 |
| `ground` / `compound_ground` / `floors` | 院墙外、院墙内、各屋地面用哪块贴图 |
| `decor` | `pack.json` 的 `site.decor` 是按颜色画的色块，这里按颜色换成贴图、换成一张图，或者藏掉 |
| `scenery` | 地图上另摆的景（稻草人、芦苇、灌木），`y` 是脚的位置 |
| `walls` | 屋墙、院墙的墙面贴图，门楼、门槛的图，南北向篱笆一格一张轮着用 |
| `objects` / `messes` / `collectibles` | 物件类型、脏乱、可捡的东西各用哪张图 |
| `people` | 按年龄段和性别挑，从上往下第一条对上的；`height` 是画多高，`rig` 是骨骼拆件，`lean` 老人弯腰几度，`asleep` 睡着时换的那张，`lying` 图本来就是躺着的（襁褓） |
| `pets` | 每种动物的图和高度 |
| `unwell` | 某个需求低于多少时头顶挂的那个「不舒服」记号 |
| `poses` | 动作做什么姿势（见下） |

没写的那一项：物件画白盒方块，脏乱画一块奶油色底板加名字（积雪那种 `look: patch` 的不加底板），人画色块。

## 骨骼拆件和姿势

小人有 `rig` 的用 `CutoutRig` 动起来，七个姿势：`idle`（呼吸）、`walk`、`work`（两手在身前忙）、`sit`、`eat`（手往嘴边送）、`sleep`（躺平）、`wave`（招手道谢）。拆件和定关节见 `cutout-animation`。

一个动作摆什么姿势，按这个顺序找：`poses.actions` 里有这个动作 id 就用它；没有，看动作用的物件在不在 `poses.objects` 里；都没有，`slow` 的动作躺下睡，用着家具、在打扫、在捡东西的做 `work`，其余 `idle`。路上一律 `walk`，道谢时 `wave`。`poses.on` 里的物件是「坐上去、躺上去」的，人画在它上面；不在里面的，人站在旁边。

没有 rig 的平面图也有姿势：坐下压扁一点、往下沉，睡觉换 `asleep` 那张或者整张放倒。《起家》给 90 个动作配了姿势，剩下的走默认。

## import_art.py

```
python3 game/tools/import_art.py <素材目录> game/packs/<id>/art
python3 game/tools/import_art.py --rigs-only <素材目录> game/packs/<id>/art
```

素材按两倍画，一个贴图像素是半个房子像素：

- `tiles/`：方的无缝贴图缩到 384×288，一次重复盖 4×4 格（格子 48×36）；地面直着画下去、压成四分之三高。墙面保持 256×256。
- `props/`：裁到轮廓，长边最多 300。
- `chars/`：裁好，按游戏里画的高度放两倍（大人 180），脚底残留的绿幕边清掉。
- `chars/a_<名字>/` 里有 `.rig.json` 的拆件：部件图和 rig 里每个像素值都减半，存成 `rigs/<名字>/<名字>.rig.json`。

只认 `a_` 开头的文件（画风 A）。换一套画风就换前缀，旧的留着。

## 不穿模

用户第一眼就会看到穿模：人站在饭桌里、躺进墙里、名字叠成一团。《起家》一次修掉的规矩（提交 81f575b，测试在 `test_view_clipping.gd`）：

- **人不停在家具上，也不停在墙线上**。家具占的格子从行走图里挖掉，路绕着走。去用一件家具时，站的地方由 `use_spot` 给：先找它前面一排，再找两边，最后找后面，必须是空格、和家具之间没有墙。随便走到某处时由 `stop_point` 给：那一点能停就停，不能停就挪到同一边墙内最近的空格中间。
- **人多了各占一格**。两个人去同一个地方，挪到相邻的两格，不再是错开 20 像素叠着。新来的人、挤着的人都取同一屋最近的空格。
- **站着的东西按脚排前后**（y-sort）。人、家具、景、宠物都按脚的位置排，脚靠下的画在前面。
- **矮的前墙按墙顶排**，站在屋子最前排的人画在门槛上面；高墙按墙脚排。门楼底下或后面有人时，门楼变淡。
- **坐处和床排得稍高**一点，坐在凳上、躺在炕上的人画在它上面。
- **图不贴侧墙**。家具的图比格子宽时往屋里收，不伸进墙里。
- **名字单独一层**，盖在所有图上面，互相推开不重叠。只有选中的那个人显示他在做什么，其余只写名字。两盘饭菜搁一张桌时只画圆点不写字。

## 设计的教训

1. **先白盒后美术，一样样换**。有图就用，没图白盒，每接一批图都能马上进游戏看。
2. **图的大小按游戏里的尺寸定**，导入时一次缩好。大人 90 像素高，狗比人宽（这条写进了测试）。
3. **点击框跟着图走**，图换大了框也大；悬停高亮和摆家具的虚影放在图上面一层，不被图挡住。
4. **穿模当成规则写进测试**，别靠一张张截图去找。每条规矩一个测试：用的地方在家具旁边且没隔墙、所有停点都是空格且不在墙线上、路绕开家具、名字不重叠。
5. **改了几何，测试预期要跟着改并写原因**：两人同处从差 20 像素变成两格、矮前墙不再变淡（它后面不会再站人）、凳子是坐上去的、图离墙挪了一格减墙缝、狗的图比人宽、《起家》每样物件都有图。

## 验收

- `./game/tests/run.sh view_skin`、`view_clipping`、`view_site` 全过，输出没有贴图导入失败（`.import` 里 `valid=false` 会让 `run.sh` 判失败）。
- 截图看一遍白天、夜里、下雨、下雪，每个年龄段的人站、走、坐、吃、睡各一张。截图的做法见 `pack-verification` 第 5 节：只在最后统一截一次，窗口放到屏幕外。
- 改了 `art.json` 的包和没有 `art.json` 的 `_smoke` 都要跑，确认后者画法一点没变。
