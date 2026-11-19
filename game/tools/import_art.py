#!/usr/bin/env python3
"""Copy the style-A art (the `a_` files) from an assets folder into a pack's `art/` folder,
sized for the game: drawn at 2x, so a texture pixel is half a house pixel.

    python3 game/tools/import_art.py <assets dir> game/packs/qijia/art

- tiles/: square seamless textures -> 384x288 (one repeat covers 4x4 cells of 48x36 at 1x;
  ground is drawn straight down and squashed to 3/4). Wall faces stay square (256x256).
- props/: trimmed to their outline, the longer side at most 300 px.
- chars/: trimmed, 2x the height the game draws them at (adult 180); green-screen fringe
  left at the feet is cleared.
Needs Pillow.
"""
import sys
from pathlib import Path

from PIL import Image

PROPS_MAX = 300
CHAR_H = 200
WALLS = {"a_wall", "a_wall_compound"}


def trim(im):
    box = im.getchannel("A").getbbox()
    return im.crop(box) if box else im


def clear_green(im):
    px = im.load()
    w, h = im.size
    for y in range(int(h * 0.88), h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and g > r + 40 and g > b + 40:
                px[x, y] = (0, 0, 0, 0)
    return im


def fit(im, longest):
    k = min(1.0, longest / max(im.size))
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def main(src: Path, dst: Path) -> None:
    for sub in ("tiles", "props", "chars"):
        (dst / sub).mkdir(parents=True, exist_ok=True)
    for f in sorted((src / "tiles").glob("a_*.png")):
        im = Image.open(f).convert("RGBA")
        size = (256, 256) if f.stem in WALLS else (384, 288)
        im.resize(size, Image.LANCZOS).save(dst / "tiles" / f.name[2:], optimize=True)
    for f in sorted((src / "props").glob("a_*.png")):
        im = trim(Image.open(f).convert("RGBA"))
        fit(im, PROPS_MAX).save(dst / "props" / f.name[2:], optimize=True)
    for f in sorted((src / "chars").glob("a_*.png")):
        im = clear_green(trim(Image.open(f).convert("RGBA")))
        im = trim(im)
        k = CHAR_H / im.height
        im.resize((round(im.width * k), CHAR_H), Image.LANCZOS).save(dst / "chars" / f.name[2:], optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
