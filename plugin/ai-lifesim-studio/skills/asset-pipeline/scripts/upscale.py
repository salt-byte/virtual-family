#!/usr/bin/env python3
"""放大素材（替代笔记里「传回 ChatGPT 说 Upscale」那一步，在本地做）。

用法：
  python3 upscale.py 输入.png 输出.png --scale 2 --mode pixel    # 像素风：整数倍最近邻，一个像素变成 2×2 的方块
  python3 upscale.py 输入.png 输出.png --scale 2 --mode smooth   # 卡通 / 手绘：Lanczos 放大后轻微锐化
  python3 upscale.py 输入.png 输出.png --fit 512                 # 长边放大或缩小到 512
  python3 upscale.py 输入目录 输出目录 --scale 2 --mode pixel

像素风只用整数倍，1.5 倍会让一部分像素变宽、一部分不变，格子就歪了。
smooth 模式只能把边缘弄干净，补不出原图没有的细节。要真的长出细节（毛发、纹理），用 AI 放大：
在生图工具里放大，或本地跑 Real-ESRGAN 这类模型，跑完再回到这里统一尺寸。
"""
import argparse
from pathlib import Path

from PIL import Image, ImageFilter

EXTS = {".png", ".jpg", ".jpeg", ".webp"}


def one(src, dst, a):
    img = Image.open(src).convert("RGBA")
    w, h = img.size
    if a.fit:
        k = a.fit / max(w, h)
    else:
        k = a.scale
    if a.mode == "pixel":
        if abs(k - round(k)) > 1e-6 or k < 1:
            raise SystemExit(f"{src.name}：像素风只能整数倍放大（现在是 {k:.2f} 倍）；先把原图修成整格大小")
        out = img.resize((w * int(round(k)), h * int(round(k))), Image.NEAREST)
    else:
        out = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
        if k > 1:
            out = out.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)
    print(f"{src.name} {w}×{h} → {dst} {out.size[0]}×{out.size[1]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--scale", type=float, default=2)
    ap.add_argument("--fit", type=int)
    ap.add_argument("--mode", choices=["pixel", "smooth"], required=True)
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
