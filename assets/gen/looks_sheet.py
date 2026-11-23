"""Contact sheet for the adoption looks: portrait, side / front / back rest pose, and a walk strip per facing.
Every rig is drawn at the height the game uses (adult 90 px, elder 74) x SCALE, with a_father as the yardstick.

python3 assets/gen/looks_sheet.py                       # all looks in assets/chars/looks.json -> ~/Downloads/qijia_house_shots/looks_sheet.png
python3 assets/gen/looks_sheet.py a_adult_1 --out x.png # just these (ids need not be in looks.json yet)
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import build_facing_rigs  # noqa: E402,F401  (puts cutout_lib on sys.path)
import cutout_lib as cl  # noqa: E402

CHARS = ROOT / "assets/chars"
ANIM_SIDE = cl.load_json(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/references/anims.humanoid_side.json")["animations"]
ANIM_FRONT = cl.load_json(CHARS / "anims.humanoid_front.json")["animations"]
SCALE = 2
HEIGHT = {"adult": 90, "elder": 74}
BG = (250, 243, 232)
INK = (74, 52, 36)
FONT = None
for f in ("/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/STHeiti Medium.ttc", "/Library/Fonts/Arial Unicode.ttf"):
    if Path(f).exists():
        FONT = f
        break


def font(sz):
    return ImageFont.truetype(FONT, sz) if FONT else ImageFont.load_default()


def rig_path(name):
    return CHARS / name / f"{name}.rig.json"


def draw(name, h_px, pose=None, ref_h=None):
    """Render at the game's size: the rest-pose height maps to h_px (the head-ratio fix applies to front/back)."""
    rp = rig_path(name)
    rig = cl.load_json(rp)
    lo, hi = cl.bounds(rig, [{}])
    rest_h = hi[1] - lo[1]
    k = h_px * SCALE / (ref_h or rest_h)
    lo2, hi2 = cl.bounds(rig, [pose or {}])
    canvas = (int((hi2[0] - lo2[0]) * k) + 8, int((hi2[1] - lo2[1]) * k) + 8)
    im = cl.render(rig, rp.parent, pose or {}, canvas, (4 - lo2[0] * k, 4 - lo2[1] * k), k)
    return im, (4 - lo2[1] * k)          # image, y of the ground line (root at y=0)


def facing_height(look, facing, h):
    """Mirror person_view.gd: a front/back rig is scaled by (side head/height)/(this head/height), clamped 0.75..1.1."""
    if facing == "side":
        return h
    def ratio(n):
        r = cl.load_json(rig_path(n))
        lo, hi = cl.bounds(r, [{}])
        return next(p for p in r["parts"] if p["id"] == "head")["size"][1] / (hi[1] - lo[1])
    k = max(0.75, min(1.1, ratio(look) / ratio(f"{look}_{facing}")))
    return h * k


def strip(look, facing, h, frames=6):
    name = look if facing == "side" else f"{look}_{facing}"
    rig = cl.load_json(rig_path(name))
    anim = (ANIM_SIDE if facing == "side" else ANIM_FRONT)["walk"]
    hh = facing_height(look, facing, h)
    lo, hi = cl.bounds(rig, [{}])
    out = []
    for i in range(frames):
        pose = cl.pose_at(rig, anim, anim["length"] * i / frames)
        out.append(draw(name, hh, pose, ref_h=hi[1] - lo[1]))
    return out


def sheet(looks, out):
    rows = []
    for lk in looks:
        h = lk.get("height") or HEIGHT.get(lk["stage"], 90)
        cells = []
        por = CHARS / f"portraits/{lk['id']}.png"
        cells.append(("portrait", [(Image.open(por).convert("RGBA").resize((128, 128)), None)] if por.exists() else []))
        for f in ("side", "front", "back"):
            name = lk["id"] if f == "side" else f"{lk['id']}_{f}"
            cells.append((f, [draw(name, facing_height(lk["id"], f, h))]))
        for f in ("side", "front", "back"):
            cells.append((f"walk {f}", strip(lk["id"], f, h)))
        rows.append((lk, cells))
    ref = [("父亲 side", draw("a_father", 90)), ("父亲 front", draw("a_father_front", facing_height("a_father", "front", 90)))]
    row_h = 90 * SCALE + 60
    widths = []
    for lk, cells in rows:
        w = 260
        for _, ims in cells:
            w += sum(im.width for im, _ in ims) + 6 * len(ims) + 24
        widths.append(w)
    W = max(widths + [800])
    H = 50 + row_h * (len(rows) + 1)
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((14, 12), "领养候选：每人一张头像，侧面 / 正面 / 背面站立，三个朝向的走路（按游戏里的身高，×2；第一行是父亲作比例尺）", fill=INK, font=font(20))
    y = 50
    base = y + 90 * SCALE + 8
    x = 260
    d.text((14, y + 20), "比例尺 a_father", fill=INK, font=font(18))
    for lab, (im, gy) in ref:
        img.paste(im, (x, int(base - gy)), im)
        d.text((x, base + 10), lab, fill=INK, font=font(13))
        x += im.width + 30
    d.line((240, base, W - 10, base), fill=(220, 205, 185), width=1)
    for lk, cells in rows:
        y += row_h
        base = y + 90 * SCALE + 8
        d.line((240, base, W - 10, base), fill=(220, 205, 185), width=1)
        d.text((14, y + 14), lk["id"], fill=INK, font=font(18))
        d.text((14, y + 40), f"{lk.get('name', '')}", fill=INK, font=font(20))
        d.text((14, y + 70), f"{lk['sex']} · {lk['stage']}", fill=INK, font=font(14))
        x = 260
        for lab, ims in cells:
            x0 = x
            for im, gy in ims:
                top = base - 128 if gy is None else int(base - gy)
                img.paste(im, (x, top), im)
                x += im.width + 6
            d.text((x0, base + 10), lab, fill=INK, font=font(13))
            x += 24
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(out, img.size)


if __name__ == "__main__":
    args = sys.argv[1:]
    out = Path.home() / "Downloads/qijia_house_shots/looks_sheet.png"
    if "--out" in args:
        i = args.index("--out")
        out = Path(args[i + 1])
        args = args[:i] + args[i + 2:]
    if args:
        looks = [{"id": a, "sex": "?", "stage": "elder" if "elder" in a else "adult", "name": ""} for a in args]
    else:
        looks = json.loads((CHARS / "looks.json").read_text())["looks"]
    sheet(looks, out)
