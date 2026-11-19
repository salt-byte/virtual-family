#!/usr/bin/env python3
"""Copy the style-A art (the `a_` files) from an assets folder into a pack's `art/` folder,
sized for the game: drawn at 2x, so a texture pixel is half a house pixel.

    python3 game/tools/import_art.py <assets dir> game/packs/qijia/art

- tiles/: square seamless textures -> 384x288 (one repeat covers 4x4 cells of 48x36 at 1x;
  ground is drawn straight down and squashed to 3/4). Wall faces stay square (256x256).
- props/: trimmed to their outline, the longer side at most 300 px.
- chars/: trimmed, 2x the height the game draws them at (adult 180); green-screen fringe
  left at the feet is cleared.
- chars/a_<name>/ with a `<anything>.rig.json` (a cutout rig: parts + joints) -> rigs/<name>/:
  the part pictures and every pixel value in the rig halved (RIG_SCALE), the rig saved as
  rigs/<name>/<name>.rig.json.

    python3 game/tools/import_art.py --rigs-only <assets dir> <pack art dir>

copies only the rigs (leaves the other pictures as they are).
Needs Pillow.
"""
import json
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


RIG_SCALE = 0.5
RIG_KEYS = ("pivot_px", "attach_px", "root_px", "size")


def import_rigs(src: Path, dst: Path) -> None:
    for d in sorted((src / "chars").glob("a_*")):
        rigs = list(d.glob("*.rig.json")) if d.is_dir() else []
        if not rigs:
            continue
        name = d.name[2:]
        out = dst / "rigs" / name
        out.mkdir(parents=True, exist_ok=True)
        rig = json.loads(rigs[0].read_text())
        rig["name"] = name
        for part in rig.get("parts", []):
            for k in RIG_KEYS:
                if k in part:
                    part[k] = [round(v * RIG_SCALE, 2) for v in part[k]]
            img = part.get("image")
            if img and (d / img).exists():
                im = Image.open(d / img).convert("RGBA")
                im.resize((max(1, round(im.width * RIG_SCALE)), max(1, round(im.height * RIG_SCALE))), Image.LANCZOS).save(out / img, optimize=True)
        if "root_px" in rig:
            rig["root_px"] = [round(v * RIG_SCALE, 2) for v in rig["root_px"]]
        (out / f"{name}.rig.json").write_text(json.dumps(rig, ensure_ascii=False, indent=1))


def main(src: Path, dst: Path) -> None:
    import_rigs(src, dst)
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
    args = sys.argv[1:]
    only = "--rigs-only" in args
    args = [a for a in args if a != "--rigs-only"]
    if len(args) != 2:
        sys.exit(__doc__)
    (import_rigs if only else main)(Path(args[0]), Path(args[1]))
