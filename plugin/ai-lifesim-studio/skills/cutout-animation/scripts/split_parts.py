#!/usr/bin/env python3
"""拆件图 → 一张张部件 PNG + 这个角色的骨架文件（<名字>.rig.json），关节点按骨架模板自动算好。

用法：
  # AI 生图的拆件图（绿幕或纯色底，部件之间留空）
  python3 split_parts.py 拆件图.png --rig references/rig.humanoid_side.json --name hero --out assets/chars/hero
  # 用户自己上传的、已经分好的部件：目录里按部件 id 命名（head.png、torso.png……）
  python3 split_parts.py --from-dir 部件目录 --rig ... --name hero --out assets/chars/hero
  # 自动对应错了：看 _contact.png 上的编号，手动指定
  python3 split_parts.py 拆件图.png --rig ... --name hero --out ... --map 0=torso,1=head

自动对应：骨架模板的 sheet_rows 写了拆件图上每一格放哪个部件（行 × 列），按每块的中心落在哪一格认部件。
模板没写 sheet_rows，或加了 --reading-order，就把有自己图的部件（没写 same_as 的）按阅读顺序对上。
对不上（有空格、一格两块、块数不对）时照样把每块存成 piece_NN.png，提醒你用 --map 指定。

输出到 --out：
  <部件>.png         切好的部件
  <名字>.rig.json    骨架 + 每个部件的图、pivot_px（自己的关节点）、attach_px（挂在父部件图上的哪一点）、root_px（让脚踩在 y=0）
  _contact.png       拆件图上画好框、编号和对上的部件名，先看这张
已有的 <名字>.rig.json 里手调过的 pivot_px / attach_px 会保留；要重算就删掉那两项再跑。
"""
import argparse
import copy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / "asset-pipeline" / "scripts"))
from cutout_lib import fill_points, ground_root, load_json, save_json  # noqa: E402
from imgtools import components, contact_sheet, crop_component, grid_order, key_out, load_rgba  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet", nargs="?")
    ap.add_argument("--from-dir")
    ap.add_argument("--rig", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--map", help="编号=部件，逗号隔开，例 0=torso,1=head")
    ap.add_argument("--reading-order", action="store_true", help="不按 sheet_rows 的格子，按阅读顺序对")
    ap.add_argument("--tol", type=float, default=40)
    ap.add_argument("--merge-gap", type=int, default=3)
    ap.add_argument("--min-area", type=int, default=80)
    ap.add_argument("--pad", type=int, default=3)
    a = ap.parse_args()

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    rig = copy.deepcopy(load_json(a.rig))
    rig.pop("note", None)
    rig["name"] = a.name
    need = [p["id"] for p in rig["parts"] if not p.get("same_as")]
    prev_path = out / f"{a.name}.rig.json"
    prev = {p["id"]: p for p in load_json(prev_path)["parts"]} if prev_path.exists() else {}

    if a.from_dir:
        src = Path(a.from_dir)
        missing = [pid for pid in need if not (src / f"{pid}.png").exists()]
        if missing:
            sys.exit(f"{src} 里缺这些部件：{', '.join(m + '.png' for m in missing)}")
        for pid in need:
            arr = load_rgba(src / f"{pid}.png")
            if (arr[..., 3] == 255).all():
                arr, _ = key_out(arr, None, a.tol)
            comps = components(arr[..., 3], a.min_area, 6)
            if not comps:
                sys.exit(f"{pid}.png 是空的")
            # 一个文件里只该有一个部件：取最大的一块
            big = max(comps, key=lambda c: c["area"])
            img, _ = crop_component(arr, big, a.pad)
            img.save(out / f"{pid}.png")
        mapping = {pid: pid for pid in need}
    else:
        if not a.sheet:
            sys.exit("给一张拆件图，或用 --from-dir")
        arr = load_rgba(a.sheet)
        if (arr[..., 3] == 255).all():
            arr, bg = key_out(arr, None, a.tol)
            print(f"抠掉背景色 #{''.join(f'{int(v):02X}' for v in bg)}")
        comps = components(arr[..., 3], a.min_area, a.merge_gap)
        grid = rig.get("sheet_rows")
        problems = []
        if grid and not a.reading_order and not a.map:
            cols, rows = max(len(r) for r in grid), len(grid)
            comps, slots, problems = grid_order(comps, (arr.shape[1], arr.shape[0]), cols, rows)
            cell = {r * cols + c: pid for r, row in enumerate(grid) for c, pid in enumerate(row)}
            idx = {cell[k]: i for i, k in enumerate(slots) if k in cell}
            for k in slots:
                if k not in cell:
                    problems.append(f"第 {k} 格不该有部件")
            problems = [p_ for p_ in problems if not any(p_.startswith(f"第 {k} 格") and "是空的" in p_
                                                       for k in range(cols * rows) if k not in cell)]
            problems = [p_ + (f"，这一格应该是 {cell[int(p_.split()[1])]}" if "是空的" in p_ and int(p_.split()[1]) in cell else "")
                        for p_ in problems]
            if problems or set(idx) != set(need):
                for p_ in problems:
                    print("提醒：" + p_)
                idx = None
        elif a.map:
            idx = {}
            for kv in a.map.split(","):
                k, v = kv.split("=")
                idx[v.strip()] = int(k)
        elif len(comps) == len(need):
            idx = {pid: i for i, pid in enumerate(need)}
        else:
            idx = None
        labels = []
        for i, c in enumerate(comps):
            who = next((pid for pid, j in (idx or {}).items() if j == i), None)
            labels.append(f"{i} {who}" if who else str(i))
        contact_sheet(arr, comps, labels, out / "_contact.png")
        if idx is None:
            for i, c in enumerate(comps):
                crop_component(arr, c, a.pad)[0].save(out / f"piece_{i:02d}.png")
            sys.exit(f"找到 {len(comps)} 块，要的部件是 {len(need)} 个（{', '.join(need)}）。"
                     f"看 {out / '_contact.png'}：多了就是有部件被切碎了（调大 --merge-gap）或有杂点（调大 --min-area），"
                     f"少了就是部件粘在一起（调小 --merge-gap，或重新生图让部件离远一点）；"
                     f"也可以用 --map 0=head,1=torso… 直接指定")
        for pid in need:
            if pid not in idx or idx[pid] >= len(comps):
                sys.exit(f"--map 里没有 {pid}，或编号超出了 0–{len(comps) - 1}")
            img, _ = crop_component(arr, comps[idx[pid]], a.pad)
            img.save(out / f"{pid}.png")
        mapping = {pid: pid for pid in need}

    for p in rig["parts"]:
        if p["id"] in mapping:
            p["image"] = f"{mapping[p['id']]}.png"
        old = prev.get(p["id"], {})
        for k in ("pivot_px", "attach_px", "rest_rot"):
            if k in old:
                p[k] = old[k]
    fill_points(rig, out)
    ground_root(rig, out)
    save_json(prev_path, rig)
    print(f"写好 {len(need)} 张部件图和 {prev_path}")
    print(f"下一步：python3 {HERE / 'preview_rig.py'} {prev_path} --anims <动作表> --out <预览目录>，看站立图上的红点是不是落在关节上")


if __name__ == "__main__":
    main()
