"""从 Noto Sans/Serif CJK（OFL 协议）里只截取游戏用到的字，生成小字体文件。脚本里加了新文字后重新运行。"""
import sys, glob, os
from fontTools.ttLib import TTCollection
from fontTools import subset
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 传项目根目录
chars = set(chr(c) for c in range(32, 127)) | set('·—…「」《》“”‘’！？，。、：；（）【】〔〕◆◇▲▼▾○◐●⚠×–％%0123456789')
for f in glob.glob(os.path.join(ROOT, 'scripts/**/*.gd'), recursive=True) + glob.glob(os.path.join(ROOT, 'tools/*.gd')) + [f for f in glob.glob(os.path.join(ROOT, 'content/**/*'), recursive=True) if f.endswith(('.yarn', '.csv', '.json'))]:
    chars |= set(open(f, encoding='utf-8').read())
text = ''.join(sorted(c for c in chars if c.isprintable()))
def make(ttc, face_hint, out):
    col = TTCollection(ttc)
    font = next(f for f in col.fonts if face_hint in f['name'].getDebugName(1))
    opts = subset.Options(); opts.layout_features = ['*']; opts.name_IDs = ['*']
    s = subset.Subsetter(opts); s.populate(text=text); s.subset(font)
    font.save(out); print(out, os.path.getsize(out) // 1024, 'KB', len(text), 'chars')
make('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', 'Noto Sans CJK SC', os.path.join(ROOT, 'assets/fonts/ui.otf'))
make('/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc', 'Noto Serif CJK SC', os.path.join(ROOT, 'assets/fonts/title.otf'))
