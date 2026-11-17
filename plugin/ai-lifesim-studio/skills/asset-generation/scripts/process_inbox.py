#!/usr/bin/env python3
"""收图：把 assets/gen/inbox/ 里出好的图按清单自动处理成游戏素材，再拼一张验收图。
处理用 asset-pipeline 的脚本（remove_bg / split_objects / make_seamless），这里只按 manifest.csv 的 type 分流。

用法（在项目根目录跑，或用 --root）：
  python3 process_inbox.py                   处理清单里还没处理的（status 不是「已处理」「通过」的）
  python3 process_inbox.py --sheet env_01    只处理这几张（重生以后再跑）
  python3 process_inbox.py --all             全部重新处理

分流（manifest.csv 的 type 列）：
  一张图对应清单里好几行，或 prompts.json 给了 grid  → split_objects.py --grid 按格子切，名字照清单
  frames（整张帧表）                                  → 同上，切成一帧一张
  character / prop / ui（单张）                       → remove_bg.py 抠背景；服务直接出了透明底就不抠
  tile                                                → make_seamless.py 改成能无缝平铺
  parts（骨骼拆件图）                                 → 不处理，交给 cutout-animation 的 split_parts.py
处理中间产物（_contact.png、_preview.png、split.json）放 assets/gen/out/<sheet>/；
成品复制到 gen_config.json 的 out_dirs（默认 character→assets/chars，prop→assets/props，tile→assets/tiles，
ui→assets/ui，frames→assets/chars/<sheet>/）。
清单里处理过的行 status 改成「已处理」，source 写「服务 型号 日期」。
最后拼一张验收图 assets/gen/review/<时间>.png：每个成品放在棋盘格底上标上 id，地块平铺 2×2。先看这张，再看各自的 _contact.png。
像素风在 gen_config.json 写 "pixel_size": 32：抠图用硬边，地块缩到 32×32。
"""
import argparse
import csv
import datetime as dt
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PIPE = Path(__file__).resolve().parents[2] / "asset-pipeline" / "scripts"
OUT_DIRS = {"character": "assets/chars", "prop": "assets/props", "tile": "assets/tiles",
            "ui": "assets/ui", "frames": "assets/chars"}
DONE = {"已处理", "通过"}


def run(script, *args):
    r = subprocess.run([sys.executable, str(PIPE / script), *map(str, args)], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        raise RuntimeError(f"{script} 出错：{out}")
    return out


def find_src(inbox, sheet):
    for ext in (".png", ".webp", ".jpg", ".jpeg"):
        p = inbox / f"{sheet}{ext}"
        if p.exists():
            return p
    return None


def has_alpha(path):
    a = np.array(Image.open(path).convert("RGBA"))[..., 3]
    return (a < 250).mean() > 0.05


def load_json(p, default):
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else default


def font(size):
    for name in ("DejaVuSans-Bold.ttf", "Arial Bold.ttf", "Arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def review_sheet(items, out_path, cell=200):
    """items：[(id, png 路径, 是否地块)]。每格一个成品，棋盘格底，下面写 id。"""
    if not items:
        return None
    cols = min(5, len(items))
    rows = (len(items) + cols - 1) // cols
    W, H = cols * cell, rows * (cell + 24)
    sheet = Image.new("RGB", (W, H), (250, 250, 250))
    d = ImageDraw.Draw(sheet)
    f = font(14)
    for i, (aid, path, is_tile) in enumerate(items):
        x0, y0 = (i % cols) * cell, (i // cols) * (cell + 24)
        bg = Image.new("RGBA", (cell - 8, cell - 8), (236, 236, 236, 255))
        for yy in range(0, bg.size[1], 12):
            for xx in range(0, bg.size[0], 12):
                if (xx // 12 + yy // 12) % 2:
                    bg.paste((206, 206, 206, 255), (xx, yy, xx + 12, yy + 12))
        im = Image.open(path).convert("RGBA")
        if is_tile:  # 地块平铺 2×2，接缝一眼看得出
            t = Image.new("RGBA", (im.size[0] * 2, im.size[1] * 2))
            for dx in (0, 1):
                for dy in (0, 1):
                    t.paste(im, (dx * im.size[0], dy * im.size[1]))
            im = t
        k = min((cell - 16) / im.size[0], (cell - 16) / im.size[1])
        resample = Image.NEAREST if k >= 1 else Image.LANCZOS
        im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), resample)
        bg.alpha_composite(im, ((bg.size[0] - im.size[0]) // 2, (bg.size[1] - im.size[1]) // 2))
        sheet.paste(bg.convert("RGB"), (x0 + 4, y0 + 4))
        d.text((x0 + 6, y0 + cell), aid, fill=(30, 30, 30), font=f)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)
    return out_path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".")
    ap.add_argument("--sheet", nargs="+")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    gen = root / "assets/gen"
    inbox, work = gen / "inbox", gen / "out"
    mpath = gen / "manifest.csv"
    if not mpath.exists():
        sys.exit(f"没有 {mpath}：先按 asset-generation 第 2 步列清单")
    with open(mpath, encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        cols = list(reader.fieldnames or [])
        rows = list(reader)
    for c in ("status", "source", "note"):
        if c not in cols:
            cols.append(c)
    cfg = load_json(gen / "gen_config.json", {})
    jobs = {j["sheet"]: j for j in load_json(gen / "prompts.json", [])}
    out_dirs = {**OUT_DIRS, **cfg.get("out_dirs", {})}
    px = cfg.get("pixel_size")
    stamp = dt.date.today().isoformat()
    source = f"{cfg.get('provider', 'AI 生图')} {cfg.get('model', '')} {stamp}".replace("  ", " ")

    sheets = {}
    for r in rows:
        sheets.setdefault(r.get("sheet") or r["id"], []).append(r)
    if a.sheet:
        todo = [s for s in a.sheet if s in sheets]
        for s in set(a.sheet) - set(todo):
            print(f"✗ {s}：manifest.csv 里没有 sheet={s} 的行")
    else:
        todo = [s for s, rs in sheets.items() if a.all or any(r.get("status") not in DONE for r in rs)]

    review, warns, skipped = [], [], []
    for s in todo:
        rs = sorted(sheets[s], key=lambda r: int(r.get("sheet_pos") or 0))
        src = find_src(inbox, s)
        if not src:
            cands = sorted(inbox.glob(f"{s}_[a-d].*"))
            skipped.append(f"{s}：inbox 里没有 {s}.png" + (f"（有候选 {', '.join(p.name for p in cands)}：挑一张改名成 {s}.png）" if cands else ""))
            continue
        kind = rs[0].get("type", "prop")
        job = jobs.get(s, {})
        wd = work / s
        wd.mkdir(parents=True, exist_ok=True)
        transparent = has_alpha(src)
        try:
            if kind == "parts":
                skipped.append(f"{s}：骨骼拆件图，交给 cutout-animation 的 split_parts.py")
                continue
            grid = job.get("grid")
            if len(rs) > 1 or kind == "frames" or grid:
                if not grid:
                    raise RuntimeError("一张图对应好几行，但 prompts.json 里这张没写 grid（列x行）")
                args = [src, wd, "--grid", grid, "--manifest", mpath, "--batch", s]
                if not transparent:
                    args.append("--key")
                log = run("split_objects.py", *args)
                dest = root / out_dirs[kind] / (s if kind == "frames" else "")
                dest.mkdir(parents=True, exist_ok=True)
                for r in rs:
                    p = wd / f"{r['id']}.png"
                    if p.exists():
                        shutil.copy2(p, dest / p.name)
                        review.append((r["id"], dest / p.name, False))
                    else:
                        warns.append(f"{s}：没切出 {r['id']}，看 {(wd / '_contact.png').relative_to(root)}")
            else:
                r = rs[0]
                outp = wd / f"{r['id']}.png"
                if kind == "tile":
                    args = [src, outp] + (["--size", px] if px else [])
                    log = run("make_seamless.py", *args)
                elif transparent:
                    shutil.copy2(src, outp)
                    log = f"{src.name}：服务直接出了透明底，不抠"
                else:
                    args = [src, outp] + (["--soft", 0] if px else [])
                    if (job.get("background") or "").startswith("#"):
                        args += ["--color", job["background"]]
                    log = run("remove_bg.py", *args)
                dest = root / out_dirs[kind]
                dest.mkdir(parents=True, exist_ok=True)
                shutil.copy2(outp, dest / outp.name)
                review.append((r["id"], dest / outp.name, kind == "tile"))
        except RuntimeError as e:
            warns.append(f"{s}：{e}")
            continue
        print(log)
        warns += [f"{s}：{ln.strip()}" for ln in log.splitlines() if "提醒" in ln]
        for r in rs:
            r["status"] = "已处理"
            if not r.get("source") or r["source"].split(" ")[0] in ("openai", "ark", "gemini", "sdwebui", "AI"):
                r["source"] = source

    with open(mpath, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    sheet = review_sheet(review, gen / "review" / f"{dt.datetime.now():%Y%m%d-%H%M%S}.png")
    print()
    print(f"处理了 {len(review)} 个素材" + (f"；验收图 {sheet.relative_to(root)}（先看这张）" if sheet else ""))
    for x in skipped:
        print("跳过：" + x)
    for x in warns:
        print("⚠ " + x)
    return 1 if warns else 0


if __name__ == "__main__":
    sys.exit(main())
