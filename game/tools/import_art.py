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

    python3 game/tools/import_art.py --iso-only <assets dir> <pack art dir>

copies only what the 45° view adds: iso/<id>.png -> iso/<id>.png (trimmed, the longer side at
most ISO_MAX), the facing rigs chars/a_<name>_front|_back/ -> rigs/<name>_front|_back/, and
the animals' single facing pictures chars/a_<kind>_front|_back/<file>.png -> chars/<kind>_front|_back.png.
    python3 game/tools/import_art.py --looks-only <assets dir> <pack art dir>

copies only the looks (chars/looks.json): their rigs, all three facings, as
rigs/<id>[_front|_back]/ (the id without its a_ prefix), and their portraits
chars/portraits/a_<id>.png -> portraits/<id>.png (trimmed, the longer side at most 256).

    python3 game/tools/import_art.py --34-only <assets dir> <pack art dir>

copies only the three-quarter (45°) views: the rigs chars/a_<name>_front34|_back34/ ->
rigs/<name>_front34|_back34/, the animals' single pictures chars/a_<kind>_front34|_back34/
<file>.png -> chars/<kind>_front34|_back34.png, and their animations
chars/anims.humanoid_34.json -> rigs/anims.humanoid_34.json.
Needs Pillow.
"""
import shutil
import json
import sys
from pathlib import Path

from PIL import Image

PROPS_MAX = 300
ISO_MAX = 400
ISO_SKIP = {"gatehouse_green", "kang_sleeper"}  # made for the target picture only
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


FACINGS = ("_front", "_back")
FACINGS_34 = ("_front34", "_back34")


def _bare(name: str) -> str:
    for f in FACINGS_34 + FACINGS:
        name = name.removesuffix(f)
    return name


def import_rigs(src: Path, dst: Path, facing_only=False, only=None, facings=FACINGS) -> None:
    for d in sorted((src / "chars").glob("a_*")):
        rigs = list(d.glob("*.rig.json")) if d.is_dir() else []
        if not rigs:
            continue
        if facing_only and not d.name.endswith(facings):
            continue
        if only is not None and _bare(d.name) not in only:
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


def import_iso(src: Path, dst: Path) -> None:
    (dst / "iso").mkdir(parents=True, exist_ok=True)
    for f in sorted((src / "iso").glob("*.png")):
        if f.stem in ISO_SKIP:
            continue
        im = trim(Image.open(f).convert("RGBA"))
        fit(im, ISO_MAX).save(dst / "iso" / f.name, optimize=True)
    import_rigs(src, dst, facing_only=True)
    (dst / "chars").mkdir(parents=True, exist_ok=True)
    for d in sorted((src / "chars").glob("a_*_front")) + sorted((src / "chars").glob("a_*_back")):
        if not d.is_dir() or list(d.glob("*.rig.json")):
            continue
        pics = [p for p in d.glob("*.png") if not p.name.startswith("_")]
        if pics:
            im = trim(Image.open(pics[0]).convert("RGBA"))
            k = CHAR_H / 2 / im.height
            im.resize((round(im.width * k), round(CHAR_H / 2)), Image.LANCZOS).save(dst / "chars" / f"{d.name[2:]}.png", optimize=True)


def single_pictures(src: Path, dst: Path, facings) -> None:
    """The animals' one-picture facings: chars/a_<kind><facing>/<file>.png -> chars/<kind><facing>.png."""
    (dst / "chars").mkdir(parents=True, exist_ok=True)
    for f in facings:
        for d in sorted((src / "chars").glob(f"a_*{f}")):
            if not d.is_dir() or list(d.glob("*.rig.json")):
                continue
            pics = [p for p in d.glob("*.png") if not p.name.startswith("_")]
            if pics:
                im = trim(Image.open(pics[0]).convert("RGBA"))
                k = CHAR_H / 2 / im.height
                im.resize((round(im.width * k), round(CHAR_H / 2)), Image.LANCZOS).save(dst / "chars" / f"{d.name[2:]}.png", optimize=True)


def import_34(src: Path, dst: Path) -> None:
    import_rigs(src, dst, facing_only=True, facings=FACINGS_34)
    single_pictures(src, dst, FACINGS_34)
    anims = src / "chars" / "anims.humanoid_34.json"
    if anims.exists():
        (dst / "rigs").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(anims, dst / "rigs" / "anims.humanoid_34.json")


PORTRAIT_MAX = 256


def import_looks(src: Path, dst: Path) -> None:
    looks = json.loads((src / "chars" / "looks.json").read_text())["looks"]
    ids = {l["id"] for l in looks}
    import_rigs(src, dst, only=ids)
    (dst / "portraits").mkdir(parents=True, exist_ok=True)
    for l in looks:
        f = src / l["portrait"]
        if f.exists():
            im = trim(Image.open(f).convert("RGBA"))
            fit(im, PORTRAIT_MAX).save(dst / "portraits" / f"{l['id'][2:]}.png", optimize=True)


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
    iso = "--iso-only" in args
    looks = "--looks-only" in args
    only34 = "--34-only" in args
    args = [a for a in args if a not in ("--rigs-only", "--iso-only", "--looks-only", "--34-only")]
    if len(args) != 2:
        sys.exit(__doc__)
    (import_34 if only34 else import_looks if looks else import_iso if iso else import_rigs if only else main)(Path(args[0]), Path(args[1]))
