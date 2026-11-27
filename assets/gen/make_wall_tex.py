#!/usr/bin/env python3
"""The qijia walls' and floors' textures from the four AI textures in assets/gen/out/tex
(plaster.png and earth.png made seamless; the two brick ones cropped to whole bricks):

  tiles/wall.png       a house's back wall face, bottom to top: grey-brick wainscot (WAINSCOT
                       of the height), a dark course, yellowed whitewash with soot up top.
                       Drawn with fit_height, so the texture's height is the face's height.
  tiles/wall_low.png   a cut wall's face: three courses of the same brick.
  tiles/floor_earth.png  rammed earth (top-down)
  tiles/floor_brick.png  grey floor bricks (top-down, 4 x 4 bricks: two bricks a cell)

  python3 assets/gen/make_wall_tex.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "gen" / "out" / "tex"
OUT = ROOT / "game" / "packs" / "qijia" / "art" / "tiles"

H = 224            # the back wall face at 2x (BACK 112 view px)
WAINSCOT = 0.40
COURSE = 12.8      # one brick course at 2x on the back wall
BRICK_SRC_COURSE = 1225 / 12.0


def grey(img, keep=0.45, warm=(1.03, 1.0, 0.95)):
    """Pull the AI bricks' blue toward a warm grey."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    lum = (a * [0.3, 0.59, 0.11]).sum(axis=-1, keepdims=True)
    a = a * keep + lum * (1 - keep)
    a = a * np.array(warm, dtype=np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def tile_x(img, w):
    out = Image.new("RGB", (w, img.height))
    x = 0
    while x < w:
        out.paste(img, (x, 0))
        x += img.width
    return out


def main():
    bricks = grey(Image.open(SRC / "tex_brick_wall_period.png"))
    k = COURSE / BRICK_SRC_COURSE
    bw = round(bricks.width * k)                     # one brick period wide
    W = bw * 4
    wh = round(H * WAINSCOT)
    b = bricks.resize((bw, round(bricks.height * k)), Image.LANCZOS)
    b = tile_x(b, W)
    wains = b.crop((0, b.height - wh, W, b.height))  # bottom courses

    pl = Image.open(SRC / "plaster.png").convert("RGB")
    ps = W
    pl = pl.resize((ps, ps), Image.LANCZOS)
    pl = tile_x(pl, W)
    up = pl.crop((0, 0, W, H - wh))
    a = np.asarray(up, dtype=np.float32)
    # Yellowed lime, a little darker overall, and soot from the eaves down.
    a = a * np.array([0.97, 0.93, 0.84], dtype=np.float32)
    y = np.linspace(0.0, 1.0, a.shape[0], dtype=np.float32)[:, None, None]
    soot = 1.0 - 0.34 * np.clip(1.0 - y / 0.45, 0, 1) ** 1.6
    a = a * soot
    up = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

    wall = Image.new("RGB", (W, H))
    wall.paste(up, (0, 0))
    wall.paste(wains, (0, H - wh))
    # A darker course on top of the wainscot and the plaster's shadow on it.
    d = np.asarray(wall, dtype=np.float32)
    top = H - wh
    d[top:top + 5] *= 0.62
    d[top - 3:top] *= np.array([0.8, 0.85, 0.9])[:, None, None]
    Image.fromarray(np.clip(d, 0, 255).astype(np.uint8)).save(OUT / "wall.png")

    # The low walls: three courses, the brick period at the same width.
    low_h = round(3 * BRICK_SRC_COURSE)
    low = bricks.crop((0, bricks.height - low_h, bricks.width, bricks.height))
    low = low.resize((bw * 2, round(low_h * bw * 2 / bricks.width)), Image.LANCZOS)
    low = tile_x(low, W)
    low.save(OUT / "wall_low.png")

    earth = Image.open(SRC / "earth.png").convert("RGB")
    a = np.asarray(earth, dtype=np.float32) * np.array([1.04, 0.98, 0.88], dtype=np.float32)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).resize((384, 288), Image.LANCZOS).save(OUT / "floor_earth.png")

    fb = grey(Image.open(SRC / "tex_floor_brick_period.png"), keep=0.55)
    fb.resize((384, 288), Image.LANCZOS).save(OUT / "floor_brick.png")
    print("wall", (W, H), "low", low.size)


if __name__ == "__main__":
    main()
