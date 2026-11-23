"""Cut the hand-held props out of the a_hand_* green-screen sheets, scale them to the people rigs and write
assets/props/hand/<id>.png + index.json (id -> 中文名, grip point, orientation).

python3 assets/gen/hand_props.py
Scale: a front34 person rig is ~1404 px tall at rig resolution and ~180 px in game art (90 px on screen, drawn at 2x),
so a fist is ~14 px wide. Each prop's longer side is set in px at that 2x scale (LONG below).
Hi-res cut-outs stay in assets/gen/out/a_hand/ for re-scaling later.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
from key_green_grid import key  # noqa: E402
from key_livestock import pick  # noqa: E402
from make_hand_prompts import ITEMS  # noqa: E402

OUT = ROOT / "assets/props/hand"
HIRES = ROOT / "assets/gen/out/a_hand"
FIGURE_PX = 180
# id -> (sheet, cols, rows, col, row, longer side px @2x, grip (fx, fy) of the trimmed sprite, orientation)
UP = "upright: 按图里的样子正着拿，底在下"
HD = "handle_down: 柄竖直朝下、头朝上；拿着走时可整体转 ±20°"
PICKS = {
    "rice_bowl_full": ("a_hand_1", 3, 3, 0, 0, 30, (0.45, 0.93), UP + "；手托碗底"),
    "bowl_empty": ("a_hand_1", 3, 3, 1, 0, 26, (0.5, 0.93), UP + "；手托碗底"),
    "teacup": ("a_hand_1", 3, 3, 2, 0, 14, (0.5, 0.6), UP + "；手捏杯身"),
    "medicine_bowl": ("a_hand_1", 3, 3, 0, 1, 24, (0.5, 0.93), UP + "；手托碗底"),
    "medicine_bottle": ("a_hand_1", 3, 3, 1, 1, 16, (0.5, 0.65), UP + "；手握瓶肚"),
    "osmanthus_cake": ("a_hand_1", 3, 3, 2, 1, 18, (0.5, 0.75), UP + "；指尖捏着油纸"),
    "tofu_tray": ("a_hand_1", 3, 3, 0, 2, 46, (0.5, 0.92), UP + "；双手端托盘下沿（单手时握点在下沿中间）"),
    "ladle": ("a_hand_1", 3, 3, 1, 2, 44, (0.5, 0.82), HD + "；舀汤时转 180° 勺头朝下"),
    "wok_spatula": ("a_hand_1", 3, 3, 2, 2, 42, (0.5, 0.84), HD + "；炒菜时向前倾 30–60°"),
    "book_open": ("a_hand_2", 3, 3, 0, 0, 38, (0.5, 0.9), UP + "；双手捧下沿（单手时握点在书脊下端）"),
    "book_closed": ("a_hand_2", 3, 3, 1, 0, 26, (0.2, 0.75), UP + "；手握书脊（左侧订线）"),
    "writing_brush": ("a_hand_2", 3, 3, 2, 0, 30, (0.5, 0.45), "tip_down: 笔尖朝下、竖直，写字时笔尖向下点；握笔杆中段"),
    "embroidery_hoop": ("a_hand_4", 2, 1, 1, 0, 30, (0.06, 0.62), UP + "；手握绣绷左下竹圈"),
    "sugar_figure": ("a_hand_2", 3, 3, 1, 1, 44, (0.5, 0.92), HD + "；握竹签下端"),
    "rattle_drum": ("a_hand_2", 3, 3, 2, 1, 38, (0.5, 0.88), HD + "；握木柄，摇时左右转 ±30°"),
    "herb_bundle": ("a_hand_2", 3, 3, 0, 2, 34, (0.5, 0.72), "bundle_up: 花叶朝上、根朝下；握扎绳处"),
    "carpenter_plane": ("a_hand_2", 3, 3, 1, 2, 38, (0.72, 0.62), "horizontal: 横放，刨木时贴着木板前后推；握刨刃后方的刨身"),
    "water_bucket": ("a_hand_2", 3, 3, 2, 2, 42, (0.5, 0.03), "hanging: 手提提梁顶，桶垂在手下"),
    "broom": ("a_hand_3", 3, 1, 0, 0, 112, (0.5, 0.42), "head_down: 扫帚头朝下、柄朝上；扫地时下端向一侧倾 20–30°，另一只手可握 (0.5, 0.05)"),
    "hoe": ("a_hand_4", 2, 1, 0, 0, 136, (0.14, 0.72), HD + "；锄板朝右；扛在肩上时转约 -60°，锄地时举过头再落下"),
    "axe": ("a_hand_3", 3, 1, 2, 0, 66, (0.3, 0.88), HD + "；刃朝右；劈柴时举过头向下劈"),
}
# a_hand_4 is the redo sheet: hoe came out as an axe on a_hand_3, the hoop had green leaves on a_hand_2


def snap(im, x, y):
    """Move the grip onto the nearest opaque pixel (thin sticks drawn a little slanted)."""
    a = np.array(im)[..., 3]
    if a[y, x] >= 128:
        return x, y
    ys, xs = np.nonzero(a >= 128)
    k = int(np.argmin((xs - x) ** 2 + (ys - y) ** 2))
    return int(xs[k]), int(ys[k])


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    HIRES.mkdir(parents=True, exist_ok=True)
    sheets = {}
    index = {"_about": {"figure_px": FIGURE_PX, "scale_note": "像素按人物 2x 美术尺寸（人约 180 px 高、拳头约 14 px 宽）；"
                        "grip 是成品图里手握处的像素坐标（左上为原点），grip_frac 是相对宽高的比例",
                        "view": "四分之三前，光从左上"}}
    for pid, (sheet, cols, rows, c, r, long_px, (fx, fy), orient) in PICKS.items():
        if sheet not in sheets:
            src = ROOT / f"assets/gen/inbox/{sheet}.png"
            if not src.exists():
                print("missing", sheet)
                continue
            sheets[sheet] = Image.open(src)
        hi = key(pick(sheets[sheet], cols, rows, c, r))
        hi.save(HIRES / f"{pid}.png")
        s = long_px / max(hi.size)
        sm = hi.resize((max(1, round(hi.width * s)), max(1, round(hi.height * s))), Image.LANCZOS)
        sm.save(OUT / f"{pid}.png", optimize=True)
        gx, gy = snap(sm, round(fx * (sm.width - 1)), round(fy * (sm.height - 1)))
        index[pid] = {"name": ITEMS[pid][0], "file": f"{pid}.png", "size": list(sm.size), "grip": [gx, gy],
                      "grip_frac": [fx, fy], "orientation": orient}
        print(pid, hi.size, "->", sm.size, "grip", (gx, gy))
    (OUT / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
