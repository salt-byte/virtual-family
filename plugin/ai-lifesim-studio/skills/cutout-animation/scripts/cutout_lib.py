#!/usr/bin/env python3
"""拆件动画的公用部分：读骨架、算关节点、按姿势摆部件、插值动作。
split_parts / preview_rig / check_rig / build_godot_rig 都用这里的同一套算法，
所以预览 GIF 里看到的，就是 Godot 里播出来的。

坐标：y 向下；角度为正 = 屏幕上顺时针（和 Godot 的 rotation 一致）。
每个部件的原点在它自己的关节点（pivot）上；子部件挂在父部件图上的 attach 点。
"""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


# ---------- 读写 ----------
def load_json(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def save_json(p, data):
    Path(p).write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


def part_map(rig):
    return {p["id"]: p for p in rig["parts"]}


def image_of(rig, part, base):
    """部件用哪张图：自己的 image，或 same_as 指向的那个部件的图（后面的手脚复用前面的）。"""
    src = part
    seen = set()
    while "image" not in src and src.get("same_as"):
        if src["id"] in seen:
            raise ValueError(f"same_as 绕成了圈：{part['id']}")
        seen.add(src["id"])
        src = part_map(rig)[src["same_as"]]
    if "image" not in src:
        raise ValueError(f"部件 {part['id']} 没有图：先跑 split_parts.py")
    img = Image.open(Path(base) / src["image"]).convert("RGBA")
    tint = part.get("tint")
    if tint is not None and tint != 1:
        a = np.array(img).astype(np.float32)
        a[..., :3] *= float(tint)
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return img


# ---------- 关节点 ----------
def end_width(alpha, y0, y1, top):
    """靠近一端的那段（长度的 30%）有多宽：圆头关节的直径。"""
    h = y1 - y0
    rows = range(y0, y0 + max(1, int(h * 0.3))) if top else range(y1 - max(1, int(h * 0.3)), y1)
    ws = []
    for y in rows:
        xs = np.nonzero(alpha[y] > 16)[0]
        if len(xs):
            ws.append(xs.max() - xs.min() + 1)
    return float(np.median(ws)) if ws else 0.0


def resolve_point(alpha, spec):
    """spec 按不透明区域的外框算：
      {"y": 0–1}           从上往下按长度的比例
      {"top_w": k}         离上端 k 个「端头宽度」：圆头的胳膊腿写 0.5，关节点就在圆头的圆心上，转起来不露缝
      {"bottom_w": k}      离下端 k 个端头宽度
      "x": "center" | 0–1  center 取那一行附近不透明像素的平均位置：部件画得歪一点，关节点也落在肉上
      "dx" / "dy"          再按外框宽 / 高的比例挪一点"""
    ys, xs = np.nonzero(alpha > 16)
    if len(xs) == 0:
        raise ValueError("部件是空的（全透明）")
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    w, h = x1 - x0, y1 - y0
    if "top_w" in spec:
        y = y0 + float(spec["top_w"]) * end_width(alpha, y0, y1, True)
    elif "bottom_w" in spec:
        y = y1 - float(spec["bottom_w"]) * end_width(alpha, y0, y1, False)
    else:
        y = y0 + float(spec.get("y", 0.5)) * h
    xspec = spec.get("x", "center")
    if xspec == "center":
        band = (ys >= y - max(2, h * 0.04)) & (ys <= y + max(2, h * 0.04))
        x = float(xs[band].mean()) if band.any() else x0 + w / 2
    else:
        x = x0 + float(xspec) * w
    x += float(spec.get("dx", 0)) * w
    y += float(spec.get("dy", 0)) * h
    return [round(x, 1), round(y, 1)]


def fill_points(rig, base):
    """没写 pivot_px / attach_px 的部件，按骨架模板里的比例算出来。已经写了的（手调过的）不动。"""
    pm = part_map(rig)
    for p in rig["parts"]:
        img = image_of(rig, p, base)
        a = np.array(img)[..., 3]
        if "pivot_px" not in p:
            p["pivot_px"] = resolve_point(a, p.get("pivot", {"y": 0.5}))
        if p.get("parent") and "attach_px" not in p:
            par = pm[p["parent"]]
            pa = np.array(image_of(rig, par, base))[..., 3]
            p["attach_px"] = resolve_point(pa, p.get("attach", {"y": 0.5}))
        p["size"] = list(img.size)
    return rig


# ---------- 矩阵 ----------
def T(x, y):
    return np.array([[1, 0, x], [0, 1, y], [0, 0, 1]], dtype=np.float64)


def R(deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def order(rig):
    """父部件排在子部件前面。"""
    pm, out, seen = part_map(rig), [], set()

    def visit(pid):
        if pid in seen:
            return
        p = pm[pid]
        if p.get("parent"):
            visit(p["parent"])
        seen.add(pid)
        out.append(p)

    for p in rig["parts"]:
        visit(p["id"])
    return out


def local_offset(rig, p):
    """子部件的原点在父部件坐标里的位置 = 父图上的挂点 - 父图上的关节点。"""
    if not p.get("parent"):
        return rig.get("root_px", [0.0, 0.0])
    par = part_map(rig)[p["parent"]]
    return [p["attach_px"][0] - par["pivot_px"][0], p["attach_px"][1] - par["pivot_px"][1]]


def world(rig, pose):
    """pose = {部件: (角度, dx, dy)}。返回 {部件: 3×3 世界矩阵}。"""
    pm, W = part_map(rig), {}
    for p in order(rig):
        rot, dx, dy = pose.get(p["id"], (0.0, 0.0, 0.0))
        ox, oy = local_offset(rig, p)
        m = T(ox + dx, oy + dy) @ R(rot + p.get("rest_rot", 0.0))
        W[p["id"]] = (W[p["parent"]] @ m) if p.get("parent") else m
    return W


# ---------- 动作 ----------
def unit(rig):
    """动作表里的位移按「躯干高 100」写；换算成这张图的像素。"""
    root = next(p for p in rig["parts"] if not p.get("parent"))
    return root["size"][1] / 100.0 if "size" in root else 1.0


def sample(keys, t, length, loop, width):
    """keys = [[时间, 值...], ...]，线性插值；循环动作超出长度绕回开头。"""
    if not keys:
        return [0.0] * width
    if loop and length > 0:
        t = t % length
    if t <= keys[0][0]:
        return list(keys[0][1:1 + width])
    for a, b in zip(keys, keys[1:]):
        if a[0] <= t <= b[0]:
            k = (t - a[0]) / max(1e-9, b[0] - a[0])
            return [a[i] + (b[i] - a[i]) * k for i in range(1, 1 + width)]
    return list(keys[-1][1:1 + width])


def pose_at(rig, anim, t):
    u = unit(rig)
    pose = {}
    for pid, tr in anim.get("tracks", {}).items():
        rot = sample(tr.get("rot", []), t, anim["length"], anim.get("loop", False), 1)[0] if tr.get("rot") else 0.0
        dx, dy = sample(tr.get("pos", []), t, anim["length"], anim.get("loop", False), 2) if tr.get("pos") else (0.0, 0.0)
        pose[pid] = (rot, dx * u, dy * u)
    return pose


# ---------- 画 ----------
def corners(p):
    w, h = p["size"]
    px, py = p["pivot_px"]
    return np.array([[-px, -py, 1], [w - px, -py, 1], [w - px, h - py, 1], [-px, h - py, 1]]).T


def bounds(rig, poses):
    pts = []
    for pose in poses:
        W = world(rig, pose)
        for p in rig["parts"]:
            pts.append((W[p["id"]] @ corners(p))[:2].T)
    pts = np.concatenate(pts)
    return pts.min(axis=0), pts.max(axis=0)


def render(rig, base, pose, canvas, origin, scale=1.0, images=None, dots=False):
    """按 z 从小到大画；canvas = (宽, 高)，origin = 世界原点在画布上的位置。"""
    images = images or {p["id"]: image_of(rig, p, base) for p in rig["parts"]}
    W = world(rig, pose)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    view = T(origin[0], origin[1]) @ np.diag([scale, scale, 1.0])
    for p in sorted(rig["parts"], key=lambda p: p.get("z", 0)):
        px, py = p["pivot_px"]
        m = view @ W[p["id"]] @ T(-px, -py)           # 部件图上的像素 → 画布
        inv = np.linalg.inv(m)
        layer = images[p["id"]].transform(canvas, Image.AFFINE, tuple(inv[:2].flatten()),
                                          resample=Image.BICUBIC)
        out = Image.alpha_composite(out, layer)
    if dots:
        from PIL import ImageDraw
        d = ImageDraw.Draw(out)
        for p in rig["parts"]:
            x, y, _ = view @ W[p["id"]] @ np.array([0, 0, 1.0])
            d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(230, 30, 60, 255), outline=(255, 255, 255, 255))
    return out


def ground_root(rig, base):
    """把整个角色往上挪，让站立姿势下最低的不透明像素落在 y = 0：放进游戏时原点就在脚底。"""
    rig["root_px"] = [0.0, 0.0]
    W = world(rig, {})
    lowest = -1e9
    for p in rig["parts"]:
        a = np.array(image_of(rig, p, base))[..., 3]
        ys, xs = np.nonzero(a > 16)
        pts = np.stack([xs - p["pivot_px"][0], ys - p["pivot_px"][1], np.ones_like(xs)]).astype(np.float64)
        lowest = max(lowest, float((W[p["id"]] @ pts)[1].max()))
    rig["root_px"] = [0.0, round(-lowest, 1)]
    return rig
