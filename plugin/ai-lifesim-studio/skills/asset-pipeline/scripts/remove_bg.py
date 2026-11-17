#!/usr/bin/env python3
"""纯色底或绿幕抠成透明 PNG（替代 Photopea 的「选择 > 色彩范围」再删除）。

用法：
  python3 remove_bg.py 输入.png 输出.png                 # 背景色从四条边自动取
  python3 remove_bg.py 输入.png 输出.png --color #00FF00 # 指定背景色
  python3 remove_bg.py 输入目录 输出目录                  # 整个目录的 png / jpg / webp

参数：
  --tol 40     和背景色的距离在这以内全透明。背景有噪点（生图常见）就调大，抠掉了物体本身就调小
  --soft 20    tol 到 tol+soft 之间半透明，边缘不起锯齿；像素风设 0（硬边）
  --no-despill 不压边缘的背景色。默认会把绿幕、蓝幕留下的一圈色边压掉

抠完一定打开看：物体里和背景同色的地方（绿衣服配绿幕）会被一起抠掉，这时换背景色重新生图。
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from imgtools import key_out, load_rgba, parse_color  # noqa: E402

EXTS = {".png", ".jpg", ".jpeg", ".webp"}


def one(src, dst, a):
    arr = load_rgba(src)
    out, bg = key_out(arr, parse_color(a.color) if a.color else None, a.tol, a.soft, not a.no_despill)
    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out).save(dst)
    clear = (out[..., 3] == 0).mean() * 100
    print(f"{src.name} → {dst}：背景色 #{''.join(f'{int(v):02X}' for v in bg)}，透明 {clear:.0f}%")
    if clear < 5:
        print("  提醒：几乎没抠掉东西。背景色取错了，或者背景不是纯色：用 --color 指定，或重新生图要求纯色底")
    if clear > 97:
        print("  提醒：几乎全抠空了。物体和背景太接近：调小 --tol，或换一个和物体反差大的背景色重新生图")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--color")
    ap.add_argument("--tol", type=float, default=40)
    ap.add_argument("--soft", type=float, default=20)
    ap.add_argument("--no-despill", action="store_true")
    a = ap.parse_args()
    src, dst = Path(a.src), Path(a.dst)
    if src.is_dir():
        for f in sorted(src.iterdir()):
            if f.suffix.lower() in EXTS:
                one(f, dst / (f.stem + ".png"), a)
    else:
        one(src, dst, a)


if __name__ == "__main__":
    main()
