#!/usr/bin/env python3
"""检查拆件角色：骨架接得上吗、关节点落在肉上吗、关节处有没有多画一截（转动时不露缝）。

用法：
  python3 check_rig.py assets/chars/hero/hero.rig.json [--anims references/anims.humanoid_side.json]

❌ 必须改：缺图、父部件不存在、关节点落在透明处、骨架绕成圈。
⚠ 要看一眼：关节处重叠太少（转起来会露缝）、动作转角很大、远侧部件画在了躯干前面。
有 ❌ 时退出码为 1。
"""
import argparse
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from cutout_lib import image_of, load_json, part_map  # noqa: E402


def opaque_at(alpha, pt, r=2):
    x, y = int(round(pt[0])), int(round(pt[1]))
    h, w = alpha.shape
    y0, y1, x0, x1 = max(0, y - r), min(h, y + r + 1), max(0, x - r), min(w, x + r + 1)
    return y1 > y0 and x1 > x0 and (alpha[y0:y1, x0:x1] > 16).any()


def row_width(alpha, y):
    y = int(np.clip(round(y), 0, alpha.shape[0] - 1))
    xs = np.nonzero(alpha[y] > 16)[0]
    return int(xs.max() - xs.min() + 1) if len(xs) else 0


def extent(alpha, pt, width, up):
    """从 pt 往上（或往下）还有多少像素是这个部件的：关节点外面多画的那一截。"""
    x = int(round(pt[0]))
    band = alpha[:, max(0, x - max(1, width // 4)): x + max(1, width // 4) + 1] > 16
    ys = np.nonzero(band.any(axis=1))[0]
    if not len(ys):
        return 0
    return float(pt[1] - ys.min()) if up else float(ys.max() - pt[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rig")
    ap.add_argument("--anims")
    a = ap.parse_args()
    rig_path = Path(a.rig)
    rig = load_json(rig_path)
    base = rig_path.parent
    pm = part_map(rig)
    errs, warns = [], []

    roots = [p["id"] for p in rig["parts"] if not p.get("parent")]
    if len(roots) != 1:
        errs.append(f"要有且只有一个根部件（parent 为空），现在是：{roots or '没有'}")
    for p in rig["parts"]:
        par = p.get("parent")
        if par and par not in pm:
            errs.append(f"{p['id']}：父部件 {par} 不存在")
        seen, cur = set(), p
        while cur.get("parent") and cur["parent"] in pm:
            if cur["id"] in seen:
                errs.append(f"{p['id']}：骨架绕成了圈")
                break
            seen.add(cur["id"])
            cur = pm[cur["parent"]]
    if errs:
        print("\n".join("❌ " + e for e in errs))
        sys.exit(1)

    alphas = {}
    for p in rig["parts"]:
        try:
            alphas[p["id"]] = np.array(image_of(rig, p, base))[..., 3]
        except (ValueError, FileNotFoundError) as e:
            errs.append(f"{p['id']}：{e}")
    for p in rig["parts"]:
        pid = p["id"]
        if pid not in alphas:
            continue
        if "pivot_px" not in p:
            errs.append(f"{pid}：没有 pivot_px，先跑 split_parts.py")
            continue
        al = alphas[pid]
        if not opaque_at(al, p["pivot_px"]):
            errs.append(f"{pid}：关节点 {p['pivot_px']} 落在透明处，部件会绕着空气转。改 pivot_px，或把这个部件重新生图")
        if p.get("parent"):
            par = pm[p["parent"]]
            pal = alphas.get(par["id"])
            if "attach_px" not in p:
                errs.append(f"{pid}：没有 attach_px")
                continue
            if pal is not None and not opaque_at(pal, p["attach_px"]):
                errs.append(f"{pid}：挂点 {p['attach_px']} 在 {par['id']} 图上的透明处，会和身体分开。改 attach_px")
            w = row_width(al, p["pivot_px"][1]) or 1
            up = extent(al, p["pivot_px"], w, up=True)
            if up < 0.4 * w:
                warns.append(f"{pid}：关节点往外只多出 {up:.0f} 像素（部件宽 {w}）。关节头要画圆、多画一截，"
                             f"否则一转就露缝。重新生图时提示里强调「关节处画成圆头，多画一截」，或把 pivot 往里挪")
            if pal is not None and par.get("parent") is not None:   # 根部件（躯干）挂点在中间，不查
                down = extent(pal, p["attach_px"], w, up=False)
                if down < 0.4 * w:
                    warns.append(f"{par['id']} → {pid}：挂点下面只剩 {down:.0f} 像素，{par['id']} 的末端要多画一截盖住关节")
    torso_z = pm[roots[0]].get("z", 0)
    for p in rig["parts"]:
        if "back" in p["id"] and p.get("z", 0) >= torso_z:
            warns.append(f"{p['id']}：远侧部件的 z（{p.get('z', 0)}）不低于躯干（{torso_z}），会画在身体前面")

    if a.anims:
        anims = load_json(a.anims)["animations"]
        for name, an in anims.items():
            for pid, tr in an.get("tracks", {}).items():
                if pid not in pm:
                    errs.append(f"动作 {name}：部件 {pid} 不在骨架里")
                    continue
                rots = [k[1] for k in tr.get("rot", [])]
                if rots and pm[pid].get("parent") and max(abs(r) for r in rots) > 100:
                    warns.append(f"动作 {name}：{pid} 转到 {max(rots, key=abs):.0f}°，关节处容易露缝，看一眼预览")
            for tr in an.get("tracks", {}).values():
                for key in ("rot", "pos"):
                    ks = tr.get(key, [])
                    if any(b[0] < a_[0] for a_, b in zip(ks, ks[1:])):
                        errs.append(f"动作 {name}：关键帧时间没按顺序排")
                    if ks and ks[-1][0] > an["length"] + 1e-6:
                        errs.append(f"动作 {name}：关键帧时间 {ks[-1][0]} 超过动作长度 {an['length']}")

    for e in errs:
        print("❌ " + e)
    for w in warns:
        print("⚠ " + w)
    if not errs and not warns:
        print("✓ 骨架、关节点、动作都没问题")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
