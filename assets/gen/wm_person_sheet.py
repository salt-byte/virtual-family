#!/usr/bin/env python3
"""Lay a person's four white-model parts (assets/blender/build_person.py) out on the sheet the
image model paints over: 1536 x 1536, #F0F0F0, two rows (head, torso / a whole arm, a whole leg), every part at the same scale, centred in its cell. Records each
part's box on the sheet in assets/gen/ref/wm_<who>_<facing>.json ("sheet").

  python3 assets/gen/wm_person_sheet.py <who> <facing> [facing ...]
"""
import json
import sys
from pathlib import Path

from PIL import Image

REF = Path(__file__).resolve().parent / "ref"
ROWS = [["head", "torso"], ["arm", "leg"]]
SIDE, PAD = 1536, 44
ROW_H = [0.46, 0.54]  # the arm and the leg are the tall ones


def sheet(who, facing):
    bp = REF / f"wm_{who}_{facing}.json"
    book = json.load(open(bp))
    ims = {n: Image.open(REF / f"_wm_{who}_{facing}_{n}.png").convert("RGBA") for r in ROWS for n in r}
    k = 9.0
    for row, f in zip(ROWS, ROW_H):
        k = min(k, (SIDE * f - 2 * PAD) / max(ims[n].height for n in row),
                (SIDE - PAD * (len(row) + 1)) / sum(ims[n].width for n in row))
    out = Image.new("RGB", (SIDE, SIDE), (240, 240, 240))
    book["sheet"] = {"scale": round(k, 4), "boxes": {}, "ink": {}}
    y0 = 0
    for row, f in zip(ROWS, ROW_H):
        ch, cw = SIDE * f, SIDE / len(row)
        for c, n in enumerate(row):
            im = ims[n].resize((round(ims[n].width * k), round(ims[n].height * k)), Image.LANCZOS)
            x, y = round(c * cw + (cw - im.width) / 2), round(y0 + (ch - im.height) / 2)
            out.paste(im, (x, y), im)
            book["sheet"]["boxes"][n] = [x, y, im.width, im.height]
            l, t, r, b = im.getchannel("A").point(lambda v: 255 * (v > 40)).getbbox()
            book["sheet"]["ink"][n] = [x + l, y + t, r - l, b - t]   # the clay itself, no margin
        y0 += ch
    out.save(REF / f"white_p_{who}_{facing}_parts.png")
    json.dump(book, open(bp, "w"), indent=1)
    print(facing, "scale", round(k, 3), "px/m on the sheet", round(k * book["px_per_m"]))


if __name__ == "__main__":
    for f in sys.argv[2:]:
        sheet(sys.argv[1], f)
