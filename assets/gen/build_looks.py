"""Side / front / back cutout rigs for the adoption looks (a_adult_<n>, a_elder_<n>), plus portraits.

Side rig: split_parts.py with the plugin's rig.humanoid_side.json (same as a_father ...).
Front / back: same steps as build_facing_rigs.py (trousers cut to one thigh, a pair of shins cut to one, arms slimmed,
mirrored *_m.png for the far limbs), then the body is rescaled so head height / total height matches the side rig:
the sheets draw front views stockier, and person_view.gd only corrects that within 0.75-1.1.

python3 assets/gen/build_looks.py a_adult_1 a_adult_2 ...      # rigs for these looks (all facings)
python3 assets/gen/build_looks.py --portraits                    # portraits for every look in looks.json
"""
import copy
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import build_facing_rigs as bf  # noqa: E402
import cutout_lib as cl  # noqa: E402  (bf put the cutout scripts on sys.path)

SIDE_TPL = bf.CUT.parent / "references/rig.humanoid_side.json"
CHARS = ROOT / "assets/chars"
INBOX = ROOT / "assets/gen/inbox"
CREAM = (250, 243, 232, 255)

# per-look fixes found by eye: {(look, facing): {...}}
#   borrow: {part: (sheet, part, mirror?)}  take a part from another sheet of the same look
#   arm_slim: width factor for the arms (default 0.82 on front/back, 1.0 on side)
#   recolor: {part: [(y0, y1, (r, g, b)), ...]}  repaint the saturated pixels in a height band (fractions of the
#            part's height) with this colour, keeping their light/dark: joint knobs that came back skin-coloured
#   trim: {part: (x0, x1[, y1])}  keep only this column range (and rows above y1), fractions of the size: sleeves
#         drawn on a torso
#   map: split_parts.py --map for a sheet whose cells are off the grid
ROBE = (238, 232, 218)
DARK = (58, 56, 60)
GREYBLUE = (112, 126, 146)
FIX = {
    ("a_adult_1", "back"): {"borrow": {"leg_lower": ("a_adult_1_front_parts", "leg_lower", False)}},
    ("a_adult_2", "side"): {"recolor": {"arm_upper": [(0, 0.13, ROBE), (0.87, 1, ROBE)], "arm_lower": [(0, 0.13, ROBE)],
                                        "leg_upper": [(0, 0.13, ROBE), (0.87, 1, ROBE)], "leg_lower": [(0, 0.13, ROBE)]}},
    ("a_adult_2", "back"): {"arm_slim": 0.7, "borrow": {"arm_upper": ("a_adult_2_front_parts", "arm_upper", False),
                                       "arm_lower": ("a_adult_2_front_parts", "arm_lower", False),
                                       "leg_lower": ("a_adult_2_front_parts", "leg_lower", False)}},
    ("a_adult_3", "back"): {"trim": {"torso": (0.172, 0.842)},
                            "borrow": {"leg_lower": ("a_adult_3_front_parts", "leg_lower", False)}},
    ("a_adult_5", "back"): {"map": "0=head,1=torso,2=arm_upper,3=arm_lower,4=leg_upper,5=leg_lower",
                            "trim": {"torso": (0.2, 0.81)},
                            "borrow": {"arm_lower": ("a_adult_5_front_parts", "arm_lower", False),
                                       "leg_lower": ("a_adult_5_front_parts", "leg_lower", False)}},
    ("a_adult_2", "front"): {"arm_slim": 0.7},
    ("a_adult_6", "side"): {"arm_slim": 0.8},
    ("a_adult_6", "front"): {"arm_slim": 0.72, "borrow": {"leg_lower": ("a_adult_6_back_parts", "leg_lower", False)}},
    ("a_adult_6", "back"): {"arm_slim": 0.72},
    ("a_adult_8", "back"): {"arm_slim": 0.7, "trim": {"torso": (0.225, 0.79)}, "borrow": {"leg_lower": ("a_adult_8_front_parts", "leg_lower", False)}},
    ("a_adult_7", "back"): {"borrow": {"leg_lower": ("a_adult_7_front_parts", "leg_lower", False)}},
    # elders: front shins came back bare-legged (the trousers are black to the ankle): paint the skin black
    ("a_elder_1", "front"): {"recolor": {"leg_lower": [(0, 0.8, DARK)]}},
    ("a_elder_1", "back"): {"trim": {"torso": (0.19, 0.81)},
                            "borrow": {"leg_lower": ("a_elder_1_front_parts", "leg_lower", False)},
                            "recolor": {"leg_lower": [(0, 0.8, DARK)], "leg_upper": [(0.75, 1, DARK)],
                                        "arm_upper": [(0.8, 1, GREYBLUE)]}},
    ("a_elder_2", "front"): {"recolor": {"leg_lower": [(0, 0.8, DARK)]}},
    ("a_elder_2", "back"): {"trim": {"torso": (0.21, 0.78, 0.93)},
                            "borrow": {"arm_upper": ("a_elder_2_front_parts", "arm_upper", False),
                                       "arm_lower": ("a_elder_2_front_parts", "arm_lower", False),
                                       "leg_upper": ("a_elder_2_front_parts", "leg_upper", False),
                                       "leg_lower": ("a_elder_2_front_parts", "leg_lower", False)},
                            "recolor": {"leg_lower": [(0, 0.8, DARK)]}},
}


def recolor(path, bands):
    im = Image.open(path).convert("RGBA")
    a = np.array(im).astype(float)
    rgb = a[..., :3] / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    h = a.shape[0]
    for y0, y1, col in bands:
        band = np.zeros(a.shape[:2], bool)
        band[int(y0 * h):int(np.ceil(y1 * h))] = True
        m = band & (a[..., 3] > 0) & (sat > 0.22) & (mx > 0.38)
        lum = rgb.mean(-1)
        ref = np.median(lum[m]) if m.any() else 1
        shade = np.clip(lum / max(ref, 1e-3), 0.6, 1.15)
        for c in range(3):
            a[..., c] = np.where(m, np.clip(col[c] * shade, 0, 255), a[..., c])
    Image.fromarray(a.astype(np.uint8)).save(path)


def trim(path, x0, x1, y1=1.0):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    h, w = a.shape[:2]
    a[:, :int(x0 * w), 3] = 0
    a[:, int(x1 * w):, 3] = 0
    a[int(y1 * h):, :, 3] = 0
    out = Image.fromarray(a)
    out.crop(bf.alpha_box(out)).save(path)


def apply_fixes(look, facing, out):
    fix = FIX.get((look, facing), {})
    for part, bands in fix.get("recolor", {}).items():
        recolor(out / f"{part}.png", bands)
    for part, box in fix.get("trim", {}).items():
        trim(out / f"{part}.png", *box)
    if facing == "side" and "arm_slim" in fix:
        for p in ("arm_upper", "arm_lower"):
            im = Image.open(out / f"{p}.png")
            im.resize((max(1, round(im.width * fix["arm_slim"])), im.height), Image.LANCZOS).save(out / f"{p}.png")
    return bool(fix)


def head_ratio(rig):
    lo, hi = cl.bounds(rig, [{}])
    head = next(p for p in rig["parts"] if p["id"] == "head")
    return head["size"][1] / (hi[1] - lo[1])


def build_side(look):
    out = CHARS / look
    out.mkdir(parents=True, exist_ok=True)
    rj = out / f"{look}.rig.json"
    if rj.exists():
        rj.unlink()
    r = subprocess.run([sys.executable, str(bf.CUT / "split_parts.py"), str(INBOX / f"{look}_parts.png"), "--rig",
                        str(SIDE_TPL), "--name", look, "--out", str(out)], capture_output=True, text=True)
    print(r.stdout.strip()[-400:])
    if r.returncode:
        raise SystemExit(r.stderr)
    fix = FIX.get((look, "side"), {})
    for part, (sheet, src, mirror) in fix.get("borrow", {}).items():
        tmp = ROOT / f"assets/gen/out/{sheet}"
        bf.split_sheet(INBOX / f"{sheet}.png", tmp)
        im = Image.open(tmp / f"{src}.png")
        (ImageOps.mirror(im) if mirror else im).save(out / f"{part}.png")
    if apply_fixes(look, "side", out):
        rig = cl.load_json(rj)
        for p in rig["parts"]:
            p.pop("pivot_px", None), p.pop("attach_px", None)
        cl.fill_points(rig, out)
        cl.ground_root(rig, out)
        cl.save_json(rj, rig)
    return rj


def split_sheet(sheet, out, mapping=None):
    out.mkdir(parents=True, exist_ok=True)
    cmd = [sys.executable, str(bf.CUT / "split_parts.py"), str(sheet), "--rig", str(bf.TEMPLATE), "--name", "_split",
           "--out", str(out)]
    r = subprocess.run(cmd + (["--map", mapping] if mapping else []), capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)
    (out / "_split.rig.json").unlink()


def snap_attach(rig, out):
    """A front torso's shoulder corners and collar notch are transparent where the template puts the arm / head
    attach points; slide each such point toward the torso's middle (arms) or down (head) onto the cloth."""
    parts = {p["id"]: p for p in rig["parts"]}
    head = parts.get("head")
    if head:                                     # braids hanging below the neck push the neck pivot into the air
        a = np.array(Image.open(out / head["image"]).convert("RGBA"))[..., 3]
        x, y = head["pivot_px"]
        while y > a.shape[0] * 0.6 and a[int(round(y)), int(round(x))] <= 16:
            y -= 1
        head["pivot_px"] = [x, round(float(y), 1)]
    for p in rig["parts"]:
        par = parts.get(p.get("parent"))
        if not par or "attach_px" not in p:
            continue
        a = np.array(Image.open(out / par["image"]).convert("RGBA"))[..., 3]
        h, w = a.shape
        x, y = p["attach_px"]
        dx = 0 if p["id"] == "head" else (1 if x < w / 2 else -1)
        dy = 1 if p["id"] == "head" else 0
        for _ in range(int(max(w, h) * 0.2)):
            xi, yi = int(round(x)), int(round(y))
            if 0 <= xi < w and 0 <= yi < h and a[yi, xi] > 16:
                break
            x, y = x + dx, y + dy
        p["attach_px"] = [round(float(x), 1), round(float(y), 1)]


def _assemble(name, facing, out):
    for p in ("arm_upper", "arm_lower", "leg_upper", "leg_lower"):
        ImageOps.mirror(Image.open(out / f"{p}.png")).save(out / f"{p}_m.png")
    rig = copy.deepcopy(cl.load_json(bf.TEMPLATE))
    rig.pop("note", None)
    rig["name"] = name
    rig["facing"] = facing
    for p in rig["parts"]:
        p.pop("same_as", None)
        p["image"] = p.pop("image_file")
    cl.fill_points(rig, out)
    snap_attach(rig, out)
    cl.ground_root(rig, out)
    return rig


def build_facing(look, facing, side_ratio):
    name = f"{look}_{facing}"
    out = CHARS / name
    fix = FIX.get((look, facing), {})
    split_sheet(INBOX / f"{name}_parts.png", out, fix.get("map"))
    for part, (sheet, src, mirror) in fix.get("borrow", {}).items():
        tmp = ROOT / f"assets/gen/out/{sheet}"
        bf.split_sheet(INBOX / f"{sheet}.png", tmp)
        im = Image.open(tmp / f"{src}.png").convert("RGBA")
        if part == "leg_upper" and im.width > im.height * 0.7:
            im = bf.half(im)
        (ImageOps.mirror(im) if mirror else im).save(out / f"{part}.png")
    apply_fixes(look, facing, out)
    thigh = Image.open(out / "leg_upper.png").convert("RGBA")
    if "leg_upper" not in fix.get("borrow", {}) or thigh.width > thigh.height * 0.7:
        thigh = bf.half(thigh)
    thigh.save(out / "leg_upper.png")
    shin = Image.open(out / "leg_lower.png").convert("RGBA")
    if shin.width > shin.height * 0.75:
        shin = bf.half(shin)
    shin.save(out / "leg_lower.png")
    k = fix.get("arm_slim", 0.82)
    for p in ("arm_upper", "arm_lower"):
        im = Image.open(out / f"{p}.png")
        im.resize((max(1, round(im.width * k)), im.height), Image.LANCZOS).save(out / f"{p}.png")
    # body scale so the head takes the same share of the height as on the side rig
    rig = _assemble(name, facing, out)
    for _ in range(3):
        f = head_ratio(rig) / side_ratio
        if abs(f - 1) < 0.01:
            break
        for p in ("torso", "arm_upper", "arm_lower", "leg_upper", "leg_lower"):
            im = Image.open(out / f"{p}.png")
            im.resize((max(1, round(im.width * f)), max(1, round(im.height * f))), Image.LANCZOS).save(out / f"{p}.png")
        rig = _assemble(name, facing, out)
    rig = _assemble(name, facing, out)
    cl.save_json(out / f"{name}.rig.json", rig)
    print(f"{name}: head ratio {head_ratio(rig):.3f} (side {side_ratio:.3f})")
    return out / f"{name}.rig.json"


def render_rest(rig_path, pose=None, pad=6):
    rig = cl.load_json(rig_path)
    lo, hi = cl.bounds(rig, [pose or {}])
    canvas = (int(hi[0] - lo[0]) + 2 * pad, int(hi[1] - lo[1]) + 2 * pad)
    return cl.render(rig, rig_path.parent, pose or {}, canvas, (pad - lo[0], pad - lo[1]))


def portrait(look, size=256):
    rp = CHARS / f"{look}_front/{look}_front.rig.json"
    im = render_rest(rp)
    rig = cl.load_json(rp)
    head_h = next(p for p in rig["parts"] if p["id"] == "head")["size"][1]
    a = np.array(im)[..., 3]
    ys, xs = np.nonzero(a > 16)
    top = ys.min()
    cut_h = int(head_h * 1.55)                      # head plus shoulders
    crop = im.crop((0, top, im.width, min(im.height, top + cut_h)))
    xs2 = np.nonzero(np.array(crop)[..., 3].max(0) > 16)[0]
    crop = crop.crop((xs2.min(), 0, xs2.max() + 1, crop.height))
    k = (size * 0.86) / max(crop.width, crop.height)
    crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.LANCZOS)
    bg = Image.new("RGBA", (size, size), CREAM)
    bg.alpha_composite(crop, ((size - crop.width) // 2, size - crop.height))
    (CHARS / "portraits").mkdir(exist_ok=True)
    bg.convert("RGB").save(CHARS / f"portraits/{look}.png")


def build(look):
    sp = build_side(look)
    side_ratio = head_ratio(cl.load_json(sp))
    print(f"{look}: side head ratio {side_ratio:.3f}")
    for facing in ("front", "back"):
        build_facing(look, facing, side_ratio)
    portrait(look)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--portraits"]:
        import json
        for lk in json.loads((CHARS / "looks.json").read_text())["looks"]:
            portrait(lk["id"])
    else:
        for lk in args:
            build(lk)
