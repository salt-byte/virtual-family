#!/usr/bin/env python3
"""Fit a painted piece back onto the ruler: key out the flat background (only what joins the
picture's edges, so pale parts inside survive), take the painted thing's box and scale and
move it onto the box of the white model's ruler render (assets/gen/ref/ruler_<name>.png),
so its size and footing are the model's whatever the image model drifted. Writes the game's
picture and prints the art.json "ruler" entry (px_per_m, anchor on the written picture).

  python3 assets/gen/fit_ruler.py <name> <painted.png> <out.png>

GAP_TOL=14 (environment) keys enclosed background a little further from #F0F0F0 when the
image model drifted its grey inside a frame (the loom); the default is 7. NOCLIP=1 keeps the
painted thing whole instead of cutting it to the white model's outline, for a piece whose
painted parts sit a little off the model's (the loom's cloth).
"""
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REF = Path(__file__).resolve().parent / "ref"
TOL = 18


def key(img):
    """RGBA with the edge-joined background clear."""
    rgb = img.convert("RGB")
    w, h = rgb.size
    mark = (255, 0, 255)
    work = rgb.copy()
    seeds = [(x, 0) for x in range(0, w, 16)] + [(x, h - 1) for x in range(0, w, 16)] + \
            [(0, y) for y in range(0, h, 16)] + [(w - 1, y) for y in range(0, h, 16)]
    for s in seeds:
        if work.getpixel(s) != mark:
            ImageDraw.floodfill(work, s, mark, thresh=TOL)
    a = np.array(work)
    bg = (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)
    # Background showing through a closed gap (between a stool's legs): near-exact #F0F0F0.
    o = np.array(rgb).astype(int)
    gap = int(os.environ.get("GAP_TOL", "7"))
    bg |= (np.abs(o - 240).max(axis=-1) <= gap) & ((o.max(axis=-1) - o.min(axis=-1)) <= 6)
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def main(name, painted, out):
    book = json.load(open(REF / "ruler.json"))[name]
    white = Image.open(REF / ("ruler_%s.png" % name)).convert("RGBA")
    wb = white.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    thing = key(Image.open(painted))
    # Its box without a pale grey patch of floor painted under it (bright, almost no colour).
    t = np.array(thing).astype(int)
    pale = (t[..., :3].min(axis=-1) > 195) & (t[..., :3].max(axis=-1) - t[..., :3].min(axis=-1) < 14)
    solid = (t[..., 3] > 40) & ~pale
    tb = Image.fromarray((solid * 255).astype(np.uint8)).getbbox()
    thing = thing.crop(tb).resize((wb[2] - wb[0], wb[3] - wb[1]), Image.LANCZOS)
    canvas = Image.new("RGBA", white.size, (0, 0, 0, 0))
    canvas.alpha_composite(thing, (wb[0], wb[1]))
    # Nothing outside the white model's outline (a pale patch of floor the image model
    # painted under it), give or take a few pixels of drift.
    keep = white.getchannel("A").point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.5))
    a = np.array(canvas.getchannel("A"))
    if os.environ.get("NOCLIP") != "1":
        a = np.minimum(a, np.array(keep))
    c = np.array(canvas).astype(int)
    pale = (c[..., :3].min(axis=-1) > 185) & (c[..., :3].max(axis=-1) - c[..., :3].min(axis=-1) < 18)
    a[pale & (np.array(white.getchannel("A")) < 128)] = 0
    canvas.putalpha(Image.fromarray(a.astype(np.uint8)))
    canvas.save(out)
    entry = {"px_per_m": book["px_per_m"], "anchor": book["anchor"]}
    print(json.dumps({name: entry}))


if __name__ == "__main__":
    main(*sys.argv[1:4])
