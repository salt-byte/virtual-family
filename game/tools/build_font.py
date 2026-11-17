"""只截取游戏用到的字，生成随游戏打包的小字体（网页版没有系统字体，不带字体中文会变成方块）。

用法：python3 game/tools/build_font.py [NotoSansSC-Regular.otf 的路径]
不给路径时用仓库根目录下 .cache/NotoSansSC-Regular.otf（不进 git）。
来源字体：Noto Sans SC（SIL Open Font License 1.1），https://github.com/notofonts/noto-cjk
改了主题包或界面文字后重新运行。
"""
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # game/
OUT = os.path.join(ROOT, "assets", "fonts", "ui.otf")

chars = set(chr(c) for c in range(32, 127))
chars |= set("·—…「」《》“”‘’！？，。、：；（）【】〔〕●○◆◇▲▼×–％％✓？　")
files = glob.glob(os.path.join(ROOT, "packs", "**", "*.json"), recursive=True)
files += glob.glob(os.path.join(ROOT, "kernel", "view", "*.gd"))
for f in files:
    with open(f, encoding="utf-8") as fh:
        chars |= set(fh.read())
text = "".join(sorted(c for c in chars if c.isprintable()))

src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(ROOT), ".cache", "NotoSansSC-Regular.otf")
if not os.path.exists(src):
    sys.exit("找不到来源字体：" + src + "（从 notofonts/noto-cjk 下载 Sans/SubsetOTF/SC/NotoSansSC-Regular.otf）")
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
font.save(OUT)
print(OUT, os.path.getsize(OUT) // 1024, "KB,", len(text), "chars,", len(files), "files scanned")
if missing:
    print("字体里没有这些字：", "".join(missing))
