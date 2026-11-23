"""Cut a green-screen grid sheet into keyed PNGs (one per cell, every piece in the cell kept: scattered pits and
crumbs belong to the same item). Green = clearly greener than red and blue, which also takes the darker green
"shadow" the model paints under feet; edge pixels are de-spilled (green clamped to max(red, blue)).

python3 assets/gen/key_green_grid.py           # 3/4 pets, litter, keepsakes (props/story/), cabinet
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
JOBS = {
    "a_mess_litter": (2, 2, ["props/a_mess_wrapper", "props/a_mess_fruit_core", "props/a_mess_cloth_scraps",
                             "props/a_mess_feathers"]),
    "a_pets34": (2, 2, ["chars/a_dog_front34/a_dog_front34", "chars/a_dog_back34/a_dog_back34",
                        "chars/a_cat_front34/a_cat_front34", "chars/a_cat_back34/a_cat_back34"]),
}
sys_path = ROOT / "assets/gen"
import sys  # noqa: E402
sys.path.insert(0, str(sys_path))
import make_story_prompts as msp  # noqa: E402
for _sheet, _ids in msp.SHEETS.items():
    JOBS[_sheet] = (3, 3, [f"props/story/{i}" for i in _ids])
JOBS["a_ui_cabinet"] = (1, 1, ["props/ui_cabinet"])


def key(cell):
    a = np.array(cell.convert("RGB")).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g > r + 38) & (g > b + 38)
    fg = ~green
    fg = ndimage.binary_opening(fg, iterations=1)
    lab, n = ndimage.label(fg)
    if n:
        sizes = ndimage.sum(fg, lab, range(1, n + 1))
        keep = np.isin(lab, np.nonzero(sizes >= 25)[0] + 1)      # drop single specks of noise
    else:
        keep = fg
    alpha = np.where(keep, 255, 0).astype(np.uint8)
    edge = keep & ~ndimage.binary_erosion(keep, iterations=5)
    out = a.copy()
    gmax = np.maximum(r, b)
    out[..., 1] = np.where(edge & (g > gmax), gmax, g)
    alpha = ndimage.gaussian_filter(alpha.astype(float), 0.6).clip(0, 255).astype(np.uint8) * keep
    im = Image.fromarray(np.dstack([out.astype(np.uint8), alpha]))
    return im.crop(im.getbbox())


def main():
    for sheet, (cols, rows, names) in JOBS.items():
        src = ROOT / f"assets/gen/inbox/{sheet}.png"
        if not src.exists():
            continue
        im = Image.open(src)
        W, H = im.size
        for k, name in enumerate(names):
            c, r = k % cols, k // cols
            cell = im.crop((c * W // cols, r * H // rows, (c + 1) * W // cols, (r + 1) * H // rows))
            out = ROOT / f"assets/{name}.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            k_im = key(cell)
            k_im.save(out)
            print(out.relative_to(ROOT), k_im.size)


if __name__ == "__main__":
    main()
