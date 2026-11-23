"""Three-quarter (iso 45 deg) cutout rigs: assets/chars/a_<id>_front34/ and a_<id>_back34/.

Same 10 part ids as the side / front / back rigs. Template assets/chars/rig.humanoid_34.json: near limbs over the torso,
far limbs reuse the near images (same_as, tint 0.84) under it, hung a little higher and toward the far side.
front34 faces the viewer's lower right, back34 walks to the upper right; the game mirrors both for the left.

Fixes done here instead of paying for regenerations:
- trousers drawn as a pair in the thigh cell / two shins in the shin cell -> keep the viewer-left one (bf.half);
- sleeves drawn on the torso -> columns whose cloth stops short of the hem are cut (auto_sleeve_trim);
- body rescaled so head height / total height matches the side rig (within 1%).

python3 assets/gen/build_34_rigs.py father mother ...     # ids without the a_ prefix; no args = all 15
"""
import copy
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import build_facing_rigs as bf  # noqa: E402
import build_looks as bl  # noqa: E402
import cutout_lib as cl  # noqa: E402

CHARS = ROOT / "assets/chars"
INBOX = ROOT / "assets/gen/inbox"
TEMPLATE = CHARS / "rig.humanoid_34.json"
ALL = ["father", "mother", "child", "grandma", "grandpa"] + [f"adult_{i}" for i in range(1, 9)] + ["elder_1", "elder_2"]

# per-sheet fixes found by eye: {(id, facing): {...}} (same keys as build_looks.FIX, plus)
#   sleeve: False to skip the automatic sleeve trim; hem: row fraction a body column must reach (default 0.72)
#   arm_slim: width factor for the arms (default 0.9)
#   thigh_pair / shin_pair: True / False to force cutting a pair in half (default: decided by the shape)
GREY = (78, 80, 84)
SASH = (176, 74, 48)
FIX = {
    # yellow joint knobs on the trousers (the side sheet had the same defect): paint them trouser grey;
    # sleeve knobs on the torso reach the hem, so the automatic trim misses them
    ("child", "front34"): {"recolor": {"leg_upper": [(0.78, 1, GREY)], "leg_lower": [(0, 0.24, GREY)]},
                           "trim": {"torso": (0.17, 0.84)}},
    # scholar's robe: skin-coloured joint knobs at the robe's elbow / knee, sleeve stubs on the torso
    ("adult_2", "back34"): {"recolor": {"leg_upper": [(0.84, 1, bl.ROBE)], "arm_upper": [(0.84, 1, bl.ROBE)]},
                            "trim": {"torso": (0.24, 0.77)}},
    # tofu maker: bare shins (her trousers are black to the ankle), skin knobs on the sleeve / thigh tops
    ("adult_6", "back34"): {"recolor": {"leg_lower": [(0.0, 0.84, bl.DARK)], "leg_upper": [(0, 0.12, bl.DARK), (0.84, 1, bl.DARK)],
                                        "arm_upper": [(0, 0.14, bl.ROBE)]}},
    # straw-hat farmer: the sheets left out his earth-red sash; paint one across the waist (the side rig has it)
    ("adult_1", "front34"): {"recolor": {"torso": [(0.66, 0.77, SASH)]}},
    ("adult_1", "back34"): {"recolor": {"torso": [(0.70, 0.80, SASH)]}, "trim": {"torso": (0.08, 0.92)}},
    ("adult_6", "front34"): {"recolor": {"leg_lower": [(0.0, 0.84, bl.DARK)]}},
}


def auto_sleeve_trim(path, hem=0.72):
    """A torso cell that came back with sleeves: a sleeve's cloth ends at the cuff, well above the hem. Keep the
    columns whose lowest opaque pixel reaches `hem` of the height (the jacket body), plus a small rounded margin."""
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    al = a[..., 3] > 16
    h, w = al.shape
    low = np.array([np.nonzero(al[:, x])[0].max() if al[:, x].any() else -1 for x in range(w)])
    body = np.nonzero(low >= hem * h)[0]
    if len(body) == 0:
        return False
    x0, x1 = body.min(), body.max() + 1
    if (x1 - x0) > 0.86 * w:
        return False
    m = max(2, int(w * 0.015))
    x0, x1 = max(0, x0 - m), min(w, x1 + m)
    a[:, :x0, 3] = 0
    a[:, x1:, 3] = 0
    out = Image.fromarray(a)
    out.crop(bf.alpha_box(out)).save(path)
    return True


def split_sheet(sheet, out, mapping=None):
    """split_parts.py exits non-zero on a warning (e.g. two shins in one cell) even when all 6 parts came out."""
    import subprocess
    out.mkdir(parents=True, exist_ok=True)
    cmd = [sys.executable, str(bf.CUT / "split_parts.py"), str(sheet), "--rig", str(bf.TEMPLATE), "--name", "_split",
           "--out", str(out)] + (["--map", mapping] if mapping else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    need = ["head", "torso", "arm_upper", "arm_lower", "leg_upper", "leg_lower"]
    if not all((out / f"{n}.png").exists() for n in need) and not mapping:
        # 6 pieces found but one cell held two (a pair of shins): take the pieces in reading order
        r = subprocess.run(cmd + ["--map", ",".join(f"{i}={n}" for i, n in enumerate(need))], capture_output=True, text=True)
    if not all((out / f"{n}.png").exists() for n in need):
        raise SystemExit(r.stdout + r.stderr)
    for f in out.glob("piece_*.png"):
        f.unlink()
    if r.returncode:
        print("  split warning:", r.stdout.strip().splitlines()[-2][:120] if r.stdout.strip() else r.stderr[-200:])
    (out / "_split.rig.json").unlink(missing_ok=True)


def half_side(im, side):
    """bf.half keeps the viewer-left leg. With toes pointing right the right shoe is usually drawn over the left
    one's toe, so the left half loses its toe at the cut: keep the right leg instead (side="right")."""
    if side == "left":
        return bf.half(im)
    from PIL import ImageOps
    return ImageOps.mirror(bf.half(ImageOps.mirror(im)))


def _assemble(name, facing, out):
    tpl = cl.load_json(TEMPLATE)
    rig = {"name": name, "facing": facing, "sheet_rows": tpl["sheet_rows"],
           "parts": copy.deepcopy(tpl["parts"] if facing == "front34" else tpl["parts_back34"])}
    for p in rig["parts"]:
        p.pop("what", None)
        if "image_file" in p:
            p["image"] = p.pop("image_file")
    cl.fill_points(rig, out)
    # snap_attach reads p["image"]; give the far limbs theirs for the call only
    for p in rig["parts"]:
        if "same_as" in p:
            p["image"] = next(q for q in rig["parts"] if q["id"] == p["same_as"])["image"]
    bl.snap_attach(rig, out)
    for p in rig["parts"]:
        if "same_as" in p:
            p.pop("image")
    cl.ground_root(rig, out)
    return rig


def build(pid, facing):
    look = f"a_{pid}"
    name = f"{look}_{facing}"
    out = CHARS / name
    fix = FIX.get((pid, facing), {})
    for f in out.glob("*.png"):
        f.unlink()
    split_sheet(INBOX / f"{name}_parts.png", out, fix.get("map"))
    for part, (sheet, src, mirror) in fix.get("borrow", {}).items():
        tmp = ROOT / f"assets/gen/out/{sheet}"
        bf.split_sheet(INBOX / f"{sheet}.png", tmp)
        im = Image.open(tmp / f"{src}.png").convert("RGBA")
        from PIL import ImageOps
        (ImageOps.mirror(im) if mirror else im).save(out / f"{part}.png")
    for part, bands in fix.get("recolor", {}).items():
        bl.recolor(out / f"{part}.png", bands)
    for part, box in fix.get("trim", {}).items():
        bl.trim(out / f"{part}.png", *box)
    notes = []
    if fix.get("sleeve", True) and "torso" not in fix.get("trim", {}):
        if auto_sleeve_trim(out / "torso.png", fix.get("hem", 0.72)):
            notes.append("sleeves cut off torso")
    thigh = Image.open(out / "leg_upper.png").convert("RGBA")
    if fix.get("thigh_pair", thigh.width > thigh.height * 0.62):
        thigh = bf.half(thigh)
        notes.append("thigh pair halved")
    thigh.save(out / "leg_upper.png")
    shin = Image.open(out / "leg_lower.png").convert("RGBA")
    if fix.get("shin_pair", shin.width > shin.height * 0.8):
        side = fix.get("shin_side", "right" if facing == "front34" else "left")
        shin = half_side(shin, side)
        notes.append(f"shin pair halved ({side})")
    shin.save(out / "leg_lower.png")
    k = fix.get("arm_slim", 0.9)
    for p in ("arm_upper", "arm_lower"):
        im = Image.open(out / f"{p}.png")
        im.resize((max(1, round(im.width * k)), im.height), Image.LANCZOS).save(out / f"{p}.png")
    side_ratio = bl.head_ratio(cl.load_json(CHARS / f"{look}/{look}.rig.json"))
    rig = _assemble(name, facing, out)
    for _ in range(4):
        f = bl.head_ratio(rig) / side_ratio
        if abs(f - 1) < 0.005:
            break
        for p in ("torso", "arm_upper", "arm_lower", "leg_upper", "leg_lower"):
            im = Image.open(out / f"{p}.png")
            im.resize((max(1, round(im.width * f)), max(1, round(im.height * f))), Image.LANCZOS).save(out / f"{p}.png")
        rig = _assemble(name, facing, out)
    cl.save_json(out / f"{name}.rig.json", rig)
    print(f"{name}: head ratio {bl.head_ratio(rig):.3f} (side {side_ratio:.3f}) {'; '.join(notes)}")
    return out / f"{name}.rig.json"


if __name__ == "__main__":
    for pid in sys.argv[1:] or ALL:
        for facing in ("front34", "back34"):
            if (INBOX / f"a_{pid}_{facing}_parts.png").exists():
                build(pid, facing)
