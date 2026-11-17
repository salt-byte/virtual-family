#!/usr/bin/env python3
"""一张图里的多个素材，自动切成一个个 PNG（替代 Photopea 的「分割切片」）。

用法：
  python3 split_objects.py 合集.png 输出目录 --grid 4x2 --names rock,tree,fence,well,cart,barrel,crate,sign
  python3 split_objects.py 合集.png 输出目录 --grid 4x2 --key           # 还没抠背景：先抠再切
  python3 split_objects.py 合集.png 输出目录 --grid 4x2 --manifest assets/gen/manifest.csv --batch env_01

--grid 列x行：生图时要求「N 列 × M 行，一格一个物体」，这里按每个物体的中心落在哪一格编号
（第 1 行从左到右是 0、1、2……，接着第 2 行）。物件高矮不一时只有这样对得准。
不给 --grid 就按阅读顺序（从上到下一行行，每行从左到右），只适合一样高的物件排成一排。
名字按编号对上：
  --names        直接给名字，用逗号隔开
  --manifest     从 asset-generation 的 manifest.csv 里取 sheet 列等于 --batch 的那些行的 id，按 sheet_pos 排
  都不给          命名成 <合集名>_00、_01……

参数：
  --min-area 64    比这小的碎块当噪点丢掉
  --merge-gap 4    相隔不到这么多像素的碎块算同一个物体（一棵树的几簇叶子）；物体挨得太近被并成一个，就调小
  --pad 2          每块四周留几个像素的透明边

输出：每个物体一个 PNG、split.json（每块在原图里的位置和大小）、_contact.png（原图上画好框和编号）。
先看 _contact.png：数量对不对、有没有两个物体被并成一个、有没有一个物体被切成两半。
"""
import argparse
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from imgtools import components, contact_sheet, crop_component, grid_order, key_out, load_rgba  # noqa: E402


def names_from_manifest(path, batch):
    rows = [r for r in csv.DictReader(open(path, encoding="utf-8")) if r.get("sheet") == batch]
    rows.sort(key=lambda r: int(r.get("sheet_pos") or 0))
    return [r["id"] for r in rows]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("outdir")
    ap.add_argument("--grid", help="列x行，例 4x2")
    ap.add_argument("--names")
    ap.add_argument("--manifest")
    ap.add_argument("--batch")
    ap.add_argument("--key", action="store_true", help="先按边缘颜色抠背景")
    ap.add_argument("--tol", type=float, default=40)
    ap.add_argument("--min-area", type=int, default=64)
    ap.add_argument("--merge-gap", type=int, default=4)
    ap.add_argument("--pad", type=int, default=2)
    a = ap.parse_args()

    src, out = Path(a.src), Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    arr = load_rgba(src)
    if a.key:
        arr, _ = key_out(arr, None, a.tol)
    elif (arr[..., 3] == 255).all():
        sys.exit("这张图没有透明背景：先跑 remove_bg.py，或者加 --key")

    comps = components(arr[..., 3], a.min_area, a.merge_gap)
    slots = list(range(len(comps)))                 # 每个物体的编号；按格子对位时是格子号，空格的名字跳过
    expect = None
    if a.grid:
        cols, rows = (int(v) for v in a.grid.lower().split("x"))
        expect = cols * rows
        comps, slots, problems = grid_order(comps, (arr.shape[1], arr.shape[0]), cols, rows)
        for pr in problems:
            print("提醒：" + pr + "。看 _contact.png；格子没对齐就重新生图，要求严格按格子排、每格居中")
    names = None
    if a.names:
        names = [n.strip() for n in a.names.split(",") if n.strip()]
    elif a.manifest:
        if not a.batch:
            sys.exit("用 --manifest 时要给 --batch（manifest 里 sheet 列的值）")
        names = names_from_manifest(a.manifest, a.batch)
    if names is not None and len(names) != (expect or len(comps)):
        print(f"提醒：找到 {len(comps)} 个物体，名字有 {len(names)} 个。先看 _contact.png："
              f"物体被并成一块就调小 --merge-gap，被切碎就调大；生图时物体之间要留空")
    labels = []
    info = []
    for i, c in enumerate(comps):
        k = slots[i]
        name = names[k] if names and k < len(names) else f"{src.stem}_{k:02d}"
        img, (x, y) = crop_component(arr, c, a.pad)
        img.save(out / f"{name}.png")
        labels.append(f"{k} {name}")
        info.append({"name": name, "x": x, "y": y, "w": img.size[0], "h": img.size[1], "area": c["area"]})
    (out / "split.json").write_text(json.dumps({"source": str(src), "objects": info}, ensure_ascii=False, indent=1),
                                    encoding="utf-8")
    contact_sheet(arr, comps, labels, out / "_contact.png")
    print(f"切出 {len(comps)} 个物体 → {out}；先看 {out / '_contact.png'}")


if __name__ == "__main__":
    main()
