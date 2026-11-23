"""Cut the picked livestock cells out of the a_livestock_* green-screen sheets (keying from key_green_grid.key).

python3 assets/gen/key_livestock.py
Picks: (sheet, cols, rows, col, row) -> output path under assets/.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
from key_green_grid import key  # noqa: E402

PICKS = {
    "chars/a_pig": ("a_livestock_1", 3, 3, 0, 0),
    "chars/a_pig_front34/a_pig_front34": ("a_livestock_4", 3, 2, 0, 0),
    "chars/a_pig_back34/a_pig_back34": ("a_livestock_1", 3, 3, 2, 0),
    "chars/a_piglet": ("a_livestock_1", 3, 3, 0, 1),
    "chars/a_piglet_front34/a_piglet_front34": ("a_livestock_4", 3, 2, 1, 0),
    "chars/a_piglet_back34/a_piglet_back34": ("a_livestock_3", 3, 2, 0, 1),
    "chars/a_pig_sleep": ("a_livestock_1", 3, 3, 0, 2),
    "chars/a_chick_front34/a_chick_front34": ("a_livestock_1", 3, 3, 1, 2),
    "chars/a_hen_sit": ("a_livestock_1", 3, 3, 2, 2),
    "chars/a_hen": ("a_livestock_2", 3, 2, 0, 0),
    "chars/a_hen_front34/a_hen_front34": ("a_livestock_3", 3, 2, 1, 1),
    "chars/a_hen_back34/a_hen_back34": ("a_livestock_2", 3, 2, 2, 0),
}


def pick(im, cols, rows, c, r):
    """Cut by object, not by cell: snouts and ears cross the grid lines. Keep the biggest blob centred in the
    cell plus blobs overlapping its box (curly tails, eggs), paint every other blob green, crop with a margin."""
    a = np.array(im.convert("RGB")).astype(int)
    H, W = a.shape[:2]
    rr, g, b = a[..., 0], a[..., 1], a[..., 2]
    fg = ndimage.binary_opening(~((g > rr + 38) & (g > b + 38)), iterations=1)
    lab, n = ndimage.label(fg)
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(fg, lab, range(1, n + 1))
    x0, x1, y0, y1 = c * W / cols, (c + 1) * W / cols, r * H / rows, (r + 1) * H / rows
    cand = []
    for i, sl in enumerate(objs):
        cy, cx = (sl[0].start + sl[0].stop) / 2, (sl[1].start + sl[1].stop) / 2
        if x0 <= cx < x1 and y0 <= cy < y1:
            cand.append(i)
    main = max(cand, key=lambda i: sizes[i])
    ms = objs[main]
    keep = [main]
    for i in cand:
        sl = objs[i]
        if i != main and sizes[i] >= 25 and sl[0].start < ms[0].stop + 10 and sl[0].stop > ms[0].start - 10 \
                and sl[1].start < ms[1].stop + 10 and sl[1].stop > ms[1].start - 10:
            keep.append(i)
    ys = [objs[i][0] for i in keep]
    xs = [objs[i][1] for i in keep]
    m = 8
    box = (max(0, min(s.start for s in xs) - m), max(0, min(s.start for s in ys) - m),
           min(W, max(s.stop for s in xs) + m), min(H, max(s.stop for s in ys) + m))
    other = fg & ~np.isin(lab, [i + 1 for i in keep])
    a[other] = (0, 255, 0)
    return Image.fromarray(a.astype(np.uint8)).crop(box)


def main():
    for name, (sheet, cols, rows, c, r) in PICKS.items():
        im = Image.open(ROOT / f"assets/gen/inbox/{sheet}.png")
        out = ROOT / f"assets/{name}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        k = key(pick(im, cols, rows, c, r))
        k.save(out)
        print(out.relative_to(ROOT), k.size)


if __name__ == "__main__":
    main()
