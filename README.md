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

底栏的「设置」里有两样东西：昼夜颠倒（把家里的钟点拨开 12 小时），和调试快进（×60、×600）。快进只为调试，正式版会去掉；开着的时候屏幕右上角会一直显示"×60"之类的标记。

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

存档和设置都在 Godot 的 `user://` 下：macOS 上是 `~/Library/Application Support/Godot/app_userdata/lifesim-kernel/`，文件是 `save_<包名>.json` 和 `settings.json`。网页版存在浏览器的站点存储里。想重来，删掉对应的 `save_<包名>.json` 即可（网页版清掉该站点的数据）；损坏的旧存档会自动留一份 `.bad` 备份。
