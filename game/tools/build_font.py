"""只截取游戏用到的字，生成随游戏打包的小字体（网页版没有系统字体，不带字体中文会变成方块）。

用法：python3 game/tools/build_font.py [NotoSansSC-Regular.otf 的路径] [ZCOOLKuaiLe-Regular.ttf 的路径]
不给路径时用仓库根目录下 .cache/ 里的同名文件（不进 git）。
来源字体：
- 正文 Noto Sans SC（SIL Open Font License 1.1），https://github.com/notofonts/noto-cjk → assets/fonts/ui.otf
- 标题 站酷快乐体 ZCOOL KuaiLe（SIL Open Font License 1.1），https://github.com/googlefonts/zcool-kuaile
  → assets/fonts/title.ttf（标题、名字、按钮、钱数；没有的字由界面退回正文字体）
改了主题包或界面文字后重新运行。
"""
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # game/
CACHE = os.path.join(os.path.dirname(ROOT), ".cache")
FONTS = [
    ("NotoSansSC-Regular.otf", "ui.otf", "从 notofonts/noto-cjk 下载 Sans/SubsetOTF/SC/NotoSansSC-Regular.otf"),
    ("ZCOOLKuaiLe-Regular.ttf", "title.ttf", "从 googlefonts/zcool-kuaile 或 Google Fonts 下载 ZCOOLKuaiLe-Regular.ttf"),
]

chars = set(chr(c) for c in range(32, 127))
chars |= set("·—…「」《》“”‘’！？，。、：；（）【】〔〕●○◆◇▲▼×–％％✓？　")
files = glob.glob(os.path.join(ROOT, "packs", "**", "*.json"), recursive=True)
files += glob.glob(os.path.join(ROOT, "kernel", "view", "*.gd"))
for f in files:
    with open(f, encoding="utf-8") as fh:
        chars |= set(fh.read())
text = "".join(sorted(c for c in chars if c.isprintable()))

for i, (name, out_name, hint) in enumerate(FONTS):
    src = sys.argv[1 + i] if len(sys.argv) > 1 + i else os.path.join(CACHE, name)
    if not os.path.exists(src):
        sys.exit("找不到来源字体：" + src + "（" + hint + "）")
    out = os.path.join(ROOT, "assets", "fonts", out_name)
    font = TTFont(src)
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    cmap = font.getBestCmap()
    missing = [c for c in text if ord(c) not in cmap and not c.isspace()]
    font.save(out)
    print(out, os.path.getsize(out) // 1024, "KB,", len(text), "chars,", len(files), "files scanned")
    if missing:
        print("  字体里没有这些字（界面会退回正文字体）：", "".join(missing))
