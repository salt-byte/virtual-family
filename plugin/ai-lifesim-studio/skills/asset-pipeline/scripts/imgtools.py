#!/usr/bin/env python3
"""后期处理的公用函数：抠背景、找连通块、按阅读顺序排序。
remove_bg.py、split_objects.py 和 cutout-animation 的 split_parts.py 都从这里取。
只依赖 Pillow 和 numpy；装了 scipy 时连通块会快很多。
"""
import numpy as np
from PIL import Image


def load_rgba(path):
    return np.array(Image.open(path).convert("RGBA"))


def parse_color(s):
    s = s.strip().lstrip("#")
    if len(s) != 6:
        raise ValueError(f"颜色要写成 #RRGGBB：{s}")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def border_color(rgb):
    """四条边一圈像素的中位数：纯色底、绿幕都能这样取到背景色。"""
    h, w = rgb.shape[:2]
    k = max(2, min(h, w) // 100)
    ring = np.concatenate([rgb[:k].reshape(-1, 3), rgb[-k:].reshape(-1, 3),
                           rgb[:, :k].reshape(-1, 3), rgb[:, -k:].reshape(-1, 3)])
    return np.median(ring, axis=0).astype(np.float32)


def key_out(arr, color=None, tol=40.0, soft=20.0, despill=True):
    """把接近背景色的像素变透明。tol 以内全透明，tol 到 tol+soft 之间渐变，免得边缘一圈锯齿。
    原图已经有透明通道时，原来的透明保留。返回 (rgba, 背景色)。"""
    rgba = arr.astype(np.float32).copy()
    rgb = rgba[..., :3]
    bg = border_color(rgb) if color is None else color
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=-1))
    a = np.clip((dist - tol) / max(soft, 1e-6), 0.0, 1.0)
    rgba[..., 3] = np.minimum(rgba[..., 3], a * 255.0)
    if despill:
        # 物体边上几个像素会混进背景色（绿幕留下的绿边，深色描边混成暗绿）：
        # 在离透明区 despill_px 以内，把背景那个通道压到另外两个通道的上限
        ch = int(np.argmax(bg))
        if bg[ch] - np.delete(bg, ch).max() > 60:          # 背景是明显偏某一色的（绿幕、蓝幕）
            others = np.delete(rgb, ch, axis=-1).max(axis=-1)
            near_edge = dilate(a < 0.5, 3) & (a > 0)
            rgb[..., ch] = np.where(near_edge, np.minimum(rgb[..., ch], others), rgb[..., ch])
    return np.clip(rgba, 0, 255).astype(np.uint8), bg


def label(mask):
    """连通块编号（8 邻接）。返回 (labels, 块数)。"""
    try:
        from scipy import ndimage
        lab, n = ndimage.label(mask, structure=np.ones((3, 3), dtype=int))
        return lab, n
    except ImportError:
        pass
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    n = 0
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        n += 1
        stack = [(y0, x0)]
        lab[y0, x0] = n
        while stack:
            y, x = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
    return lab, n


def dilate(mask, r):
    """把蒙版向外扩 r 像素：同一个物体被背景缝隔开的碎块（树叶、头发丝）先连起来再分。"""
    if r <= 0:
        return mask
    try:
        from scipy import ndimage
        return ndimage.binary_dilation(mask, iterations=r)
    except ImportError:
        m = mask.copy()
        for _ in range(r):
            g = m.copy()
            g[1:] |= m[:-1]; g[:-1] |= m[1:]; g[:, 1:] |= m[:, :-1]; g[:, :-1] |= m[:, 1:]
            m = g
        return m


def components(alpha, min_area=64, merge_gap=4, thresh=16):
    """按透明通道找出一个个物体。返回 [{bbox:(x0,y0,x1,y1), area, mask}]，已按阅读顺序排好。"""
    solid = alpha > thresh
    lab, n = label(dilate(solid, merge_gap))
    out = []
    for i in range(1, n + 1):
        m = (lab == i) & solid
        area = int(m.sum())
        if area < min_area:
            continue
        ys, xs = np.nonzero(m)
        out.append({"bbox": (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1),
                    "area": area, "mask": m})
    return reading_order(out)


def reading_order(items):
    """先按行、再按列：中心的 y 相差不到这一行平均高度的一半，算同一行。"""
    if not items:
        return items
    items = sorted(items, key=lambda c: (c["bbox"][1] + c["bbox"][3]) / 2)
    rows, cur = [], [items[0]]
    for c in items[1:]:
        cy = (c["bbox"][1] + c["bbox"][3]) / 2
        ref_cy = np.mean([(r["bbox"][1] + r["bbox"][3]) / 2 for r in cur])
        ref_h = np.mean([r["bbox"][3] - r["bbox"][1] for r in cur])
        if abs(cy - ref_cy) <= ref_h / 2:
            cur.append(c)
        else:
            rows.append(cur)
            cur = [c]
    rows.append(cur)
    return [c for r in rows for c in sorted(r, key=lambda c: c["bbox"][0])]


def grid_order(items, size, cols, rows):
    """按格子对位：每个物体的中心落在哪一格，编号就是 行 × 列数 + 列。
    生图时要求「N 列 × M 行，一格一个」，比阅读顺序可靠（高矮不一的物件分不清算哪一行）。
    返回 (按格子编号排好的物体, 编号列表, 问题列表)；同一格落了两个物体、或有空格，写进问题列表。"""
    w, h = size
    slots, problems = {}, []
    for c in items:
        cx = (c["bbox"][0] + c["bbox"][2]) / 2
        cy = (c["bbox"][1] + c["bbox"][3]) / 2
        k = min(rows - 1, int(cy / (h / rows))) * cols + min(cols - 1, int(cx / (w / cols)))
        if k in slots:
            problems.append(f"第 {k} 格（第 {k // cols + 1} 行第 {k % cols + 1} 列）落了不止一个物体")
            if c["area"] <= slots[k]["area"]:
                continue
        slots[k] = c
    for k in range(cols * rows):
        if k not in slots:
            problems.append(f"第 {k} 格（第 {k // cols + 1} 行第 {k % cols + 1} 列）是空的")
    keys = sorted(slots)
    return [slots[k] for k in keys], keys, problems


def crop_component(rgba, comp, pad=2):
    """把一个物体单独切出来：别的物体的像素清成透明，四周留 pad 像素。"""
    x0, y0, x1, y1 = comp["bbox"]
    h, w = rgba.shape[:2]
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(w, x1 + pad), min(h, y1 + pad)
    piece = rgba[y0:y1, x0:x1].copy()
    keep = dilate(comp["mask"], 1)[y0:y1, x0:x1]
    piece[..., 3] = np.where(keep, piece[..., 3], 0)
    return Image.fromarray(piece), (x0, y0)


def contact_sheet(rgba, comps, labels, out_path, scale=None):
    """在原图上画出每个物体的框和编号，切完先看这张图对不对。"""
    from PIL import ImageDraw, ImageFont
    base = Image.fromarray(rgba)
    bg = Image.new("RGBA", base.size, (236, 236, 236, 255))
    for yy in range(0, base.size[1], 16):          # 棋盘格，透明的地方一眼看得出
        for xx in range(0, base.size[0], 16):
            if (xx // 16 + yy // 16) % 2:
                bg.paste((206, 206, 206, 255), (xx, yy, xx + 16, yy + 16))
    img = Image.alpha_composite(bg, base)
    if scale is None:
        scale = max(1, 900 // max(img.size))
    if scale > 1:
        img = img.resize((img.size[0] * scale, img.size[1] * scale), Image.NEAREST)
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", max(12, 14 * scale // 2))
    except OSError:
        font = ImageFont.load_default()
    for c, lb in zip(comps, labels):
        x0, y0, x1, y1 = [v * scale for v in c["bbox"]]
        d.rectangle((x0, y0, x1, y1), outline=(220, 30, 60, 255), width=2)
        d.rectangle((x0, y0, x0 + 8 + 8 * len(lb), y0 + 18), fill=(220, 30, 60, 255))
        d.text((x0 + 4, y0 + 2), lb, fill=(255, 255, 255, 255), font=font)
    img.convert("RGB").save(out_path)
