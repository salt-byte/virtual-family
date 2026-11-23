"""Front / back cutout rigs for the iso view (assets/chars/<id>_front, <id>_back).

Same 10 part ids as the side rigs (head, torso, arm_upper, arm_lower, leg_upper, leg_lower, arm_back_*, leg_back_*), so
the game can swap rigs by facing and keep its animation-track names. Differences from the side rig:
- the "back" limbs are the other side of the body: their own mirrored image (<part>_m.png), no tint, attached at the
  mirrored shoulder / hip;
- the part sheet shows trousers (both thighs) in the leg_upper cell; this script cuts them down the middle;
- a lower-leg cell that came back as a pair is cut in half the same way.
Use with assets/chars/anims.humanoid_front.json (front and back share it).

python3 assets/gen/build_facing_rigs.py            # all five people, both facings
"""
import copy
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
CUT = ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/scripts"
sys.path.insert(0, str(CUT))
import cutout_lib as cl  # noqa: E402

TEMPLATE = ROOT / "assets/chars/rig.humanoid_front.json"
PEOPLE = ["father", "mother", "grandma", "grandpa", "child"]
# a sheet whose cells came back wrong can borrow parts from another sheet: {(person, facing): {part: (sheet, part)}}
BORROW = {("child", "back"): {"arm_upper": ("a_child_front_parts", "arm_upper"),
                              "leg_lower": ("a_child_front_parts", "leg_lower")}}


def alpha_box(im):
    a = np.array(im)[..., 3]
    ys, xs = np.nonzero(a > 16)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def half(im):
    """Keep the viewer-left half of a symmetric pair (trousers, two shins)."""
    x0, y0, x1, y1 = alpha_box(im)
    mid = (x0 + x1) // 2
    a = np.array(im)
    # cut in the gap between the legs if there is one near the middle, else at the middle
    cols = (a[y0:y1, :, 3] > 16).sum(0)
    lo, hi = int(x0 + (x1 - x0) * 0.38), int(x0 + (x1 - x0) * 0.62)
    gap = lo + int(np.argmin(cols[lo:hi]))
    cut = gap if cols[gap] < (y1 - y0) * 0.6 else mid
    out = im.crop((x0, y0, cut, y1))
    return out.crop(alpha_box(out))


def split_sheet(sheet, out):
    out.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([sys.executable, str(CUT / "split_parts.py"), str(sheet), "--rig", str(TEMPLATE),
                        "--name", "_split", "--out", str(out)], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)
    (out / "_split.rig.json").unlink()


def build(person, facing):
    name = f"a_{person}_{facing}"
    out = ROOT / f"assets/chars/{name}"
    split_sheet(ROOT / f"assets/gen/inbox/{name}_parts.png", out)
    for part, (sheet, src) in BORROW.get((person, facing), {}).items():
        tmp = ROOT / f"assets/gen/out/{sheet}"
        split_sheet(ROOT / f"assets/gen/inbox/{sheet}.png", tmp)
        Image.open(tmp / f"{src}.png").save(out / f"{part}.png")
    # trousers -> one thigh; a pair of shins -> one shin
    thigh = half(Image.open(out / "leg_upper.png").convert("RGBA"))
    thigh.save(out / "leg_upper.png")
    shin = Image.open(out / "leg_lower.png").convert("RGBA")
    if shin.width > shin.height * 0.75:
        shin = half(shin)
    shin.save(out / "leg_lower.png")
    # the sheets draw sleeves wider than the side rigs do; slim the arms so the front silhouette matches
    for p in ("arm_upper", "arm_lower"):
        im = Image.open(out / f"{p}.png")
        im.resize((max(1, round(im.width * 0.82)), im.height), Image.LANCZOS).save(out / f"{p}.png")
    for p in ("arm_upper", "arm_lower", "leg_upper", "leg_lower"):
        ImageOps.mirror(Image.open(out / f"{p}.png")).save(out / f"{p}_m.png")
    rig = copy.deepcopy(cl.load_json(TEMPLATE))
    rig.pop("note", None)
    rig["name"] = name
    rig["facing"] = facing
    for p in rig["parts"]:
        p.pop("same_as", None)
        p["image"] = p.pop("image_file")
    cl.fill_points(rig, out)
    cl.ground_root(rig, out)
    cl.save_json(out / f"{name}.rig.json", rig)
    return out / f"{name}.rig.json"


if __name__ == "__main__":
    who = sys.argv[1:] or PEOPLE
    for person in who:
        for facing in ("front", "back"):
            print(build(person, facing))
