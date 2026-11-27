#!/usr/bin/env python3
"""Cutout rigs from white-model part sheets (pilot: the father).

The sheet has four parts: head, torso, a whole arm, a whole leg. The arm and leg are painted
as one piece each and cut here at the elbow and knee (split), so the halves share one shading.

The image model paints over assets/gen/ref/white_p_<who>_<facing>_parts.png (six clay parts,
laid out by wm_person_sheet.py); this cuts assets/gen/inbox/p_<who>_<facing>_parts.png back
into the six parts by the same layout, stretches each onto its clay model's box and hangs them
by the 3D model's own joints (wm_<who>_<facing>.json); part ids, order and far-limb tints come
from the three-quarter template (assets/chars/rig.humanoid_34.json).

Writes assets/chars/a_<who>wm_<facing>/ (parts, rig, _rest.png) so the drawn rigs stay as
they are.

  python3 assets/gen/build_wm_rig.py father
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import build_34_rigs as b34  # noqa: E402
import build_looks as bl  # noqa: E402
import cutout_lib as cl  # noqa: E402
import fit_ruler  # noqa: E402
from wm_person_sheet import ROWS, ROW_H  # noqa: E402

CHARS = ROOT / "assets/chars"
INBOX = ROOT / "assets/gen/inbox"
# The image model paints the torso flatter than the camera sees the clay: the far shoulder and
# hip sit barely higher than the near ones. Keep this much of the 3D model's near-far drop.
DEPTH = 0.3
# From behind the hair hides the neck: the head sits this far (metres) lower on the collar.
HEAD_DROP = {"back34": 0.045}


def _run(count):
    """The heaviest unbroken run of rows (or columns) that have paint on them."""
    best, start = (0, 0, 0), None
    for i, v in enumerate(list(count > 3) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            best = max(best, (count[start:i].sum(), start, i))
            start = None
    return best[1], best[2]


def ink_box(alpha):
    """The painted thing's box: the main blob, not specks or a patch of uneven background."""
    a = np.array(alpha) > 40
    x0, x1 = _run(a.sum(0))
    y0, y1 = _run(a[:, x0:x1].sum(1))
    return x0, y0, x1, y1


def cut(sheet, book, out):
    """The four parts. The image model keeps each part in its cell but not its exact size or
    angle, so each painted part is stretched onto the box of its clay model: after that the
    joints are where the 3D model has them."""
    im = fit_ruler.key(Image.open(sheet))
    w, h = im.size
    y0 = 0
    for row, f in zip(ROWS, ROW_H):
        ch, cw = h * f, w / len(row)
        for c, n in enumerate(row):
            cell = im.crop((round(c * cw), round(y0), round((c + 1) * cw), round(y0 + ch)))
            cell = cell.crop(ink_box(cell.getchannel("A")))
            if n == "torso":   # painted with sleeves hanging at its sides: keep the jacket body
                cell.save(out / "torso.png")
                if b34.auto_sleeve_trim(out / "torso.png", hem=0.86):
                    print("  torso: sleeves cut off")
                    cell = Image.open(out / "torso.png")
            iw, ih = book["sheet"]["ink"][n][2:]
            print(f"  {n}: painted {cell.width}x{cell.height} -> clay {iw}x{ih}"
                  f" (stretch {cell.height / cell.width * iw / ih:.2f})")
            cell = cell.resize((iw, ih), Image.LANCZOS)
            # One more pixel off the edge: the pale background's fringe shows on dark cloth.
            cell.putalpha(cell.getchannel("A").filter(ImageFilter.MinFilter(3)))
            cell.save(out / f"{n}.png")
        y0 += ch


def joints(book):
    """Each part's joints on its cut picture, from the 3D model."""
    k, boxes, ink = book["sheet"]["scale"], book["sheet"]["boxes"], book["sheet"]["ink"]
    return {n: {j: [round(x * k + boxes[n][0] - ink[n][0], 1), round(y * k + boxes[n][1] - ink[n][1], 1)]
                for j, (x, y) in part["points"].items()} for n, part in book["parts"].items()}


def split(out, limb, J):
    """Cut a whole painted limb at its bend into <limb>_upper.png and <limb>_lower.png. Both
    halves keep a disc round the joint, so standing they lie back together as the one picture
    (no seam, one continuous shading) and bent the disc is the round of the elbow or knee.
    Returns each half's pivot, the joint on the upper half, and the sizes."""
    a = np.array(Image.open(out / f"{limb}.png").convert("RGBA"))
    h, w = a.shape[:2]
    jy = J["bend"][1]
    on = np.nonzero(a[int(round(jy)), :, 3] > 40)[0]
    cx, r = (on.min() + on.max()) / 2, (on.max() - on.min()) / 2 + 1
    yy, xx = np.mgrid[:h, :w]
    disc = (xx - cx) ** 2 + (yy - jy) ** 2 <= r * r
    res = {}
    for half, keep in (("upper", (yy < jy) | disc), ("lower", (yy >= jy) | disc)):
        b = a.copy()
        b[~keep, 3] = 0
        im = Image.fromarray(b)
        x0, y0, x1, y1 = im.getchannel("A").point(lambda v: 255 * (v > 16)).getbbox()
        im.crop((x0, y0, x1, y1)).save(out / f"{limb}_{half}.png")
        res[half] = {"off": (x0, y0), "size": [x1 - x0, y1 - y0]}
    (out / f"{limb}.png").unlink()
    up, lo = res["upper"], res["lower"]
    up["pivot"] = [round(J["pivot"][0] - up["off"][0], 1), round(J["pivot"][1] - up["off"][1], 1)]
    up["child"] = [round(cx - up["off"][0], 1), round(jy - up["off"][1], 1)]
    lo["pivot"] = [round(cx - lo["off"][0], 1), round(jy - lo["off"][1], 1)]
    return {f"{limb}_upper": up, f"{limb}_lower": lo}


def assemble(name, facing, out, book):
    tpl = cl.load_json(b34.TEMPLATE)
    J = joints(book)
    t = J["torso"]
    for a in ("shoulder", "hip"):
        mid = (t[f"{a}_l"][1] + t[f"{a}_r"][1]) / 2
        for side in "lr":
            t[f"{a}_{side}"][1] = round(mid + (t[f"{a}_{side}"][1] - mid) * DEPTH, 1)
    P = {n: {"pivot": J[n]["pivot"], "size": book["sheet"]["ink"][n][2:]} for n in ("head", "torso")}
    P.update(split(out, "arm", J["arm"]))
    P.update(split(out, "leg", J["leg"]))
    # The near side is the one lower on the picture.
    near, far = ("l", "r") if t["shoulder_l"][1] > t["shoulder_r"][1] else ("r", "l")
    neck = [t["neck"][0], round(t["neck"][1] + HEAD_DROP.get(facing, 0) * book["px_per_m"] * book["sheet"]["scale"], 1)]
    hang = {"head": neck, "arm_upper": t[f"shoulder_{near}"], "arm_back_upper": t[f"shoulder_{far}"],
            "leg_upper": t[f"hip_{near}"], "leg_back_upper": t[f"hip_{far}"],
            "arm_lower": P["arm_upper"]["child"], "arm_back_lower": P["arm_upper"]["child"],
            "leg_lower": P["leg_upper"]["child"], "leg_back_lower": P["leg_upper"]["child"]}
    rig = {"name": name, "facing": facing, "sheet_rows": ROWS, "parts": []}
    for q in tpl["parts"] if facing == "front34" else tpl["parts_back34"]:
        p = {k: q[k] for k in ("id", "parent", "z", "same_as", "tint") if k in q}
        src = q.get("same_as", q["id"])
        if "same_as" not in q:
            p["image"] = f"{src}.png"
        p["pivot_px"] = P[src]["pivot"]
        if p["id"] in hang:
            p["attach_px"] = hang[p["id"]]
        p["size"] = P[src]["size"]
        if p["id"] == "head":
            p["z"] = 4   # a ball that sits on the collar, in front of the torso, behind the near arm
        rig["parts"].append(p)
    cl.ground_root(rig, out)
    return rig


def build(who, facing):
    name = f"a_{who}wm_{facing}"
    out = CHARS / name
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.png"):
        f.unlink()
    book = json.load(open(ROOT / f"assets/gen/ref/wm_{who}_{facing}.json"))
    print(name)
    cut(INBOX / f"p_{who}_{facing}_parts.png", book, out)
    rig = assemble(name, facing, out, book)
    cl.save_json(out / f"{name}.rig.json", rig)
    bl.render_rest(out / f"{name}.rig.json").save(out / "_rest.png")
    print(f"  head ratio {bl.head_ratio(rig):.3f}")


if __name__ == "__main__":
    for who in sys.argv[1:] or ["father"]:
        for facing in ("front34", "back34"):
            if (INBOX / f"p_{who}_{facing}_parts.png").exists():
                build(who, facing)
