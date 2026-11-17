#!/usr/bin/env python3
"""把一张地面 / 墙面贴图改成能无缝平铺的（替代 Photopea 的「滤镜 > 其他 > 位移」再修接缝）。

用法：
  python3 make_seamless.py 草地.png 草地_tile.png              # 改成无缝，并出一张 3×3 平铺预览
  python3 make_seamless.py 草地.png --check                    # 只检查：四边接得上吗
  python3 make_seamless.py 草地.png 草地_tile.png --size 32    # 像素风：改完缩到 32×32 一格（最近邻）

做法：把图错开半张，接缝就挪到了正中间；再用一张中间实、四边虚的蒙版把原图和错开的图叠起来，
四边用的是错开图（天然能接上），中间用的是原图。--blend 控制过渡带占多宽（0.1–0.5）。
动手前先抹平大范围的明暗（AI 生的贴图常带一边亮一边暗的光照）：不抹，接缝没了，
平铺出来照样是一块亮一块暗的格子。--keep-light 关掉这一步（贴图本来就要有明暗，比如一面带光的墙）。

检查：左右两边、上下两边那一列像素的差，和图内部相邻两列的差比，给出倍数；1 左右接得上，超过 1.5 平铺能看见缝。
预览图（*_preview.png）一定要看：大块的显眼图案（一块石头、一朵花）平铺后会排成整齐的格子，
这种素材换成噪点均匀的纹理重新生图，或者把显眼的东西拆成单独的物件随机撒。
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def seam_error(arr):
    """接缝处的差 ÷ 图内部相邻两列（两行）的平均差。噪点多的纹理相邻像素本来就差得多，
    所以比的是倍数：1 左右就是接得上，超过 1.5 平铺时能看见缝。"""
    a = arr[..., :3].astype(np.float32)
    inner_x = float(np.abs(np.diff(a, axis=1)).mean()) or 1.0
    inner_y = float(np.abs(np.diff(a, axis=0)).mean()) or 1.0
    return float(np.abs(a[:, 0] - a[:, -1]).mean()) / inner_x, float(np.abs(a[0] - a[-1]).mean()) / inner_y


def flatten_light(arr):
    """拟合一个平滑的光照曲面（平面加二次项：一边亮一边暗、中间亮四角暗都管得到），减掉它再加回平均亮度。
    细节和颜色留着，只去掉大范围的明暗。"""
    h, w = arr.shape[:2]
    a = arr.astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    x, y = (xx / max(1, w - 1) - 0.5).ravel(), (yy / max(1, h - 1) - 0.5).ravel()
    A = np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], axis=1)
    out = a.copy()
    for c in range(3):
        v = a[..., c].ravel()
        coef, *_ = np.linalg.lstsq(A, v, rcond=None)
        surf = (A @ coef).reshape(h, w)
        out[..., c] = a[..., c] - surf + v.mean()
    return np.clip(out, 0, 255).astype(np.uint8)


def make_seamless(arr, blend=0.3):
    h, w = arr.shape[:2]
    a = arr.astype(np.float32)
    rolled = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)

    def ramp(n):
        # 0 在两端、1 在中间；中间一段全是 1，两端各 blend 的宽度渐变
        x = np.minimum(np.arange(n), np.arange(n)[::-1]) / max(1, n * blend)
        return np.clip(x, 0, 1)

    m = np.outer(ramp(h), ramp(w))[..., None]
    m = m * m * (3 - 2 * m)          # 平滑一点，过渡带看不出直线
    return np.clip(a * m + rolled * (1 - m), 0, 255).astype(np.uint8)


def preview(arr, path, n=3):
    img = Image.fromarray(arr)
    w, h = img.size
    sheet = Image.new(img.mode, (w * n, h * n))
    for i in range(n):
        for j in range(n):
            sheet.paste(img, (i * w, j * h))
    s = max(1, 600 // (w * n))
    if s > 1:
        sheet = sheet.resize((w * n * s, h * n * s), Image.NEAREST)
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--blend", type=float, default=0.3)
    ap.add_argument("--size", type=int, help="改完缩到 N×N（像素风一格的大小），最近邻")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--keep-light", action="store_true", help="不抹平大范围明暗")
    a = ap.parse_args()
    arr = np.array(Image.open(a.src).convert("RGBA"))
    lr, tb = seam_error(arr)
    print(f"原图：左右接缝 {lr:.2f} 倍，上下接缝 {tb:.2f} 倍（1 左右接得上，超过 1.5 能看见缝）")
    if a.check or not a.dst:
        preview(arr, Path(a.src).with_name(Path(a.src).stem + "_preview.png"))
        return
    out = make_seamless(arr if a.keep_light else flatten_light(arr), a.blend)
    img = Image.fromarray(out)
    if a.size:
        img = img.resize((a.size, a.size), Image.NEAREST)
        out = np.array(img)
    img.save(a.dst)
    lr, tb = seam_error(out)
    pv = Path(a.dst).with_name(Path(a.dst).stem + "_preview.png")
    preview(out, pv)
    print(f"写好 {a.dst}：左右接缝 {lr:.2f} 倍，上下接缝 {tb:.2f} 倍；平铺预览 {pv}")
    if a.size and max(lr, tb) > 1.5:
        print("  提醒：缩小以后边又对不上了：先缩到目标大小再跑一次本脚本（不加 --size）")


if __name__ == "__main__":
    sys.exit(main())
