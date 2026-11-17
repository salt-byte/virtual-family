# 《起家》（暂用名）· 家庭生活模拟内核

这是一个家庭生活模拟游戏：领养一位家人，看他们在屋里过日子，你用赏罚、买东西、摆家具来照应。游戏内核（`game/kernel`）不带任何主题，人物、物件、文字都来自主题包（`game/packs/<id>`），第一个主题包是《起家》（`game/packs/qijia`）。用 Godot 4.7.2 做的。

## 怎么玩

```
godot --path game
```

默认主题包由项目设置 `lifesim/default_pack` 决定（现在是 `qijia`）。换一个包：

```
godot --path game -- --pack=_smoke
```

游戏里有两个钟。日历走慢钟：饿、困、昼夜、工钱、年岁都按真实时间，一代人大约一周，关掉游戏期间照样过（最多补算 48 小时）。手上的事走快钟：《起家》里念一次书约 2 分钟，扫地约 30 秒，所以不开快进也看得到小人不停地换事情；夜里睡觉例外，按真实时间睡。两个数都在主题包的 `pack.json` 里（`step_seconds`、`action_speed`），行为表里标了 `slow` 的走慢钟。

底栏的「设置」里有两样东西：昼夜颠倒（把家里的钟点拨开 12 小时），和调试快进（×60、×600）。快进只为调试，正式版会去掉；开着的时候屏幕右上角会一直显示"×60"之类的标记。每次启动都回到 ×1，已经快进过的时间按主题包分开记在 `settings.json` 里。

## 跑测试

```
./game/tests/run.sh            # 全部
./game/tests/run.sh view_      # 按文件名过滤
```

出现 ERROR/WARNING 行，或者某条测试一个断言都没做，都算失败。

## 导出网页版

```
./game/tools/export_web.sh
python3 -m http.server -d build/web 8060
```

然后打开 http://localhost:8060。脚本不会自己下载东西：没装 4.7.2 的导出模板就会告诉你缺什么、怎么装，然后退出。导出的文件放在 `build/`，不进 git。

## 存档在哪

存档和设置都在 Godot 的 `user://` 下：macOS 上是 `~/Library/Application Support/Godot/app_userdata/lifesim-kernel/`，文件是 `save_<包名>.json` 和 `settings.json`。网页版存在浏览器的站点存储里。想重来，删掉对应的 `save_<包名>.json` 即可（网页版清掉该站点的数据）；损坏的旧存档会自动留一份备份（`.bad`，已有就用 `.bad2`、`.bad3`……，旧备份不会被删）。

## 字体

网页版没有系统字体，所以游戏自带一个小字体 `game/assets/fonts/ui.otf`：从 Noto Sans SC（SIL Open Font License 1.1，协议全文在同目录的 `OFL.txt`）里只截取了主题包和界面用到的字。改了主题包或界面文字后要重新生成，否则新字在网页版里是方块：

```
python3 game/tools/build_font.py <NotoSansSC-Regular.otf 的路径>
```

来源字体从 https://github.com/notofonts/noto-cjk 下载（`Sans/SubsetOTF/SC/NotoSansSC-Regular.otf`）。

