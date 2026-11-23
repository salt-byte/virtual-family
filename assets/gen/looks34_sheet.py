"""Contact sheet for the 3/4 rigs: ~/Downloads/qijia_house_shots/looks34_sheet.png

Per look: side rest | front34 rest | back34 rest | 6-frame walk (front34) | 6-frame walk_up (back34),
then a row of action poses on father, and an iso scene (floor tiles + furniture + people) to judge the angle.

python3 assets/gen/looks34_sheet.py [--poses ids...]       # --poses writes a pose strip per id to the scratch dir
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import build_34_rigs as b34  # noqa: E402
import cutout_lib as cl  # noqa: E402

CHARS = ROOT / "assets/chars"
ANIMS = json.loads((CHARS / "anims.humanoid_34.json").read_text())["animations"]
OUT = Path.home() / "Downloads/qijia_house_shots/looks34_sheet.png"
BG = (250, 243, 232)
INK = (74, 52, 36)
FONT = "/System/Library/Fonts/STHeiti Medium.ttc"
NAMES = {"father": "父亲", "mother": "母亲", "child": "孩子", "grandma": "祖母", "grandpa": "爷爷"}


def font(n):
    try:
        return ImageFont.truetype(FONT, n)
    except OSError:
        return ImageFont.load_default()


def rig_path(pid, facing):
    suf = "" if facing == "side" else "_" + facing
    return CHARS / f"a_{pid}{suf}/a_{pid}{suf}.rig.json"


def render(rp, pose=None, h=None, scale=None, z=None):
    """Render with feet at the bottom centre of a fixed box. scale: pixels per rig pixel."""
    rig = cl.load_json(rp)
    if z:
        for p in rig["parts"]:
            if p["id"] in z:
                p["z"] = z[p["id"]]
    pose = pose or {}
    lo, hi = cl.bounds(rig, [{}])
    if scale is None:
        scale = h / (hi[1] - lo[1])
    lo2, hi2 = cl.bounds(rig, [pose])
    lo = (min(lo[0], lo2[0]), min(lo[1], lo2[1]))
    hi = (max(hi[0], hi2[0]), max(hi[1], hi2[1]))
    pad = 6
    W = int((hi[0] - lo[0]) * scale) + 2 * pad
    H = int((hi[1] - lo[1]) * scale) + 2 * pad
    im = cl.render(rig, rp.parent, pose, (W, H), (pad - lo[0] * scale, pad - lo[1] * scale), scale=scale)
    return im, (pad - lo[0] * scale, pad - lo[1] * scale)   # image, where the feet origin landed


def anim_frames(rp, name, n, scale):
    rig = cl.load_json(rp)
    a = ANIMS[name]
    return [render(rp, cl.pose_at(rig, a, a["length"] * i / n), scale=scale, z=a.get("z")) for i in range(n)]


def scale_for(rp, h):
    lo, hi = cl.bounds(cl.load_json(rp), [{}])
    return h / (hi[1] - lo[1])


def look_height(pid):
    """Game height in px (looks.json / family) so people stand at their relative sizes."""
    if pid in NAMES:
        return {"father": 90, "mother": 86, "child": 62, "grandma": 74, "grandpa": 80}[pid]
    for lk in json.loads((CHARS / "looks.json").read_text())["looks"]:
        if lk["id"] == f"a_{pid}":
            return lk["height"]
    return 90


def strip(items, gap=10, base=None):
    """items: [(image, origin)] -> paste with feet on one baseline."""
    top = max(o[1] for _, o in items)
    bottom = max(im.height - o[1] for im, o in items)
    W = sum(im.width for im, _ in items) + gap * (len(items) - 1)
    out = Image.new("RGBA", (W, int(top + bottom)), (0, 0, 0, 0))
    x = 0
    for im, o in items:
        out.alpha_composite(im, (x, int(top - o[1])))
        x += im.width + gap
    return out, top


def person_row(pid, k=2.0):
    H = look_height(pid) * k
    s_side = scale_for(rig_path(pid, "side"), H)
    blocks = [("side", [render(rig_path(pid, "side"), scale=s_side)])]
    for f in ("front34", "back34"):
        if rig_path(pid, f).exists():
            blocks.append((f, [render(rig_path(pid, f), scale=scale_for(rig_path(pid, f), H))]))
    for f, an in (("front34", "walk"), ("back34", "walk_up")):
        if rig_path(pid, f).exists():
            blocks.append((f"{an}", anim_frames(rig_path(pid, f), an, 6, scale_for(rig_path(pid, f), H))))
    return blocks


def iso_scene(people, k=2.0):
    """A few iso floor tiles with furniture and people standing on them (game scale x k)."""
    W, H = 1400, 760
    im = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(im)
    tw, th = 64 * k, 32 * k
    ox, oy = W / 2, 200
    NI, NJ = 9, 7
    # the hall floor texture laid on the 2:1 diamond grid (as the game shears its square tiles)
    tex = Image.open(ROOT / "assets/tiles/a_floor_hall.png").convert("RGBA")
    S = 128
    R = 3                                   # one texture repeat spans 3 x 3 tiles, so the bricks keep their size
    tex = tex.resize((S * R, S * R), Image.LANCZOS)
    sq = Image.new("RGBA", (NI * S, NJ * S))
    for i in range(0, NI, R):
        for j in range(0, NJ, R):
            sq.paste(tex, (i * S, j * S))
    # output (X, Y) -> square (u, v): u - v = 2 (X - ox) / tw * S, u + v = 2 (Y - oy) / th * S
    a1, b1 = S / tw, S / th
    inv = (a1, b1, -a1 * ox - b1 * oy, -a1, b1, a1 * ox - b1 * oy)
    floor = sq.transform((W, H), Image.AFFINE, inv, resample=Image.BICUBIC)
    im.alpha_composite(floor)
    for i in range(NI + 1):
        d.line([(ox + (i - 0) * tw / 2, oy + i * th / 2), (ox + (i - NJ) * tw / 2, oy + (i + NJ) * th / 2)], fill=(150, 140, 126))
    for j in range(NJ + 1):
        d.line([(ox - j * tw / 2, oy + j * th / 2), (ox + (NI - j) * tw / 2, oy + (NI + j) * th / 2)], fill=(150, 140, 126))

    def foot(i, j):
        return ox + (i - j) * tw / 2, oy + (i + j) * th / 2 + th / 2

    items = []   # (sort key, image, x, y) with x, y the feet / base centre
    furn = {"dining_table": (3.5, 2.5, 150), "cupboard": (1.0, 0.6, 130), "stool": (6.0, 1.5, 60), "altar": (6.5, 0.4, 150),
            "vat": (0.8, 4.8, 70)}
    for name, (i, j, w) in furn.items():
        f = Image.open(ROOT / f"assets/iso/{name}.png").convert("RGBA")
        f = f.resize((int(w * k), int(f.height * w * k / f.width)), Image.LANCZOS)
        x, y = foot(i, j)
        items.append((i + j, f, x - f.width / 2, y - f.height + th * 0.35))
    spots = [(2.2, 4.3, "front34", False), (5.2, 3.9, "back34", False), (7.0, 5.2, "front34", True),
             (4.2, 5.6, "back34", True), (1.6, 2.6, "front34", False)]
    for (i, j, f, flip), pid in zip(spots, people):
        rp = rig_path(pid, f)
        if not rp.exists():
            continue
        p, o = render(rp, scale=scale_for(rp, look_height(pid) * k))
        if flip:
            p = p.transpose(Image.FLIP_LEFT_RIGHT)
            o = (p.width - o[0], o[1])
        x, y = foot(i, j)
        sh = Image.new("RGBA", p.size, (0, 0, 0, 0))
        items.append((i + j, p, x - o[0], y - o[1]))
        d.ellipse((x - 16 * k, y - 5 * k, x + 16 * k, y + 5 * k), fill=(110, 104, 96))
    extras = [("props/a_mess_wrapper", 3.2, 6.2, 34, 0.0), ("props/a_mess_fruit_core", 8.0, 3.2, 28, 0.0),
              ("props/a_mess_cloth_scraps", 1.3, 6.4, 34, 0.0), ("props/a_mess_feathers", 6.3, 6.3, 32, 0.0),
              ("chars/a_dog_front34/a_dog_front34", 8.0, 6.0, 44, 1.0), ("chars/a_cat_back34/a_cat_back34", 8.2, 3.4, 34, 1.0)]
    for name, i, j, w, stand in extras:
        f = Image.open(ROOT / f"assets/{name}.png").convert("RGBA")
        f = f.resize((int(w * k), int(f.height * w * k / f.width)), Image.LANCZOS)
        x, y = foot(i, j)
        # litter lies flat (centred on the tile), pets stand on it (feet at the tile centre)
        items.append((i + j - (0.5 if not stand else 0), f, x - f.width / 2, y - (f.height if stand else f.height / 2)))
    for _, f, x, y in sorted(items, key=lambda t: t[0]):
        im.alpha_composite(f, (int(x), int(y)))
    return im


def sheet(ids):
    rows = []
    for pid in ids:
        if not rig_path(pid, "front34").exists() and not rig_path(pid, "back34").exists():
            continue
        rows.append((pid, person_row(pid)))
    lab_w = 150
    rendered = []
    for pid, blocks in rows:
        items = []
        for label, frames in blocks:
            s, top = strip(frames, gap=4)
            items.append((label, s, top))
        rendered.append((pid, items))
    W = lab_w + max(sum(s.width + 34 for _, s, _ in items) for _, items in rendered)
    row_h = [max(s.height for _, s, _ in items) + 40 for _, items in rendered]
    head = 60
    scene = iso_scene(["father", "mother", "child", "grandpa", "adult_1"])
    W = max(W, scene.width + 40, 20 + 9 * 172 + 360)
    H = head + sum(row_h) + scene.height + 70 + 300 + 460
    out = Image.new("RGB", (int(W), int(H)), BG)
    d = ImageDraw.Draw(out)
    d.text((14, 14), "四分之三视角骨架（游戏身高 ×2）：侧面 | 3/4 前（朝右下）| 3/4 后（朝右上）| 3/4 前走路 6 帧 | 3/4 后走路 6 帧；"
           "往左走整体水平翻转", fill=INK, font=font(24))
    y = head
    for (pid, items), rh in zip(rendered, row_h):
        nm = NAMES.get(pid) or next((lk["name"] for lk in json.loads((CHARS / "looks.json").read_text())["looks"]
                                     if lk["id"] == f"a_{pid}"), pid)
        d.text((14, y + 10), f"a_{pid}", fill=INK, font=font(20))
        d.text((14, y + 36), nm, fill=INK, font=font(22))
        x = lab_w
        base = y + rh - 34
        for label, s, top in items:
            out.paste(s, (int(x), int(base - top)), s)
            d.text((x, base + 6), label, fill=(120, 100, 80), font=font(16))
            x += s.width + 34
        d.line((lab_w, base + 30, W - 20, base + 30), fill=(225, 214, 196))
        y += rh
    d.text((14, y + 14), "斜 45° 等距地面（64×32 菱形格 ×2）上的家具和人：3/4 前 / 后，左边两个是翻转后的朝左下 / 左上",
           fill=INK, font=font(22))
    out.paste(scene, (20, y + 50))
    y += 50 + scene.height
    d.text((14, y + 4), "新加：四样地上的垃圾（a_mess_wrapper / fruit_core / cloth_scraps / feathers）和猫狗 3/4 前 / 后单张图",
           fill=INK, font=font(22))
    x = 20
    for name in ["props/a_mess_wrapper", "props/a_mess_fruit_core", "props/a_mess_cloth_scraps", "props/a_mess_feathers",
                 "chars/a_dog_front34/a_dog_front34", "chars/a_dog_back34/a_dog_back34",
                 "chars/a_cat_front34/a_cat_front34", "chars/a_cat_back34/a_cat_back34"]:
        f = Image.open(ROOT / f"assets/{name}.png").convert("RGBA")
        f.thumbnail((200, 190))
        tile = Image.new("RGB", (210, 200), (205, 194, 171))
        tile.paste(f, ((210 - f.width) // 2, 195 - f.height), f)
        out.paste(tile, (x, y + 40))
        d.text((x, y + 244), name.split("/")[-1], fill=(120, 100, 80), font=font(15))
        x += 222
    # keepsakes for the 旧物匣 (one per story fragment + the finale hoop), the cabinet and the label tag
    y += 280
    d.text((14, y), "旧物匣：每个旧故事碎片一张（assets/props/story/<碎片 id>.png）、博古架 ui_cabinet.png、纸签 ui_tag.png",
           fill=INK, font=font(22))
    sys.path.insert(0, str(ROOT / "assets/gen"))
    import make_story_prompts as msp
    ids = [i for v in msp.SHEETS.values() for i in v]
    for n, sid in enumerate(ids):
        f = Image.open(ROOT / f"assets/props/story/{sid}.png").convert("RGBA")
        f.thumbnail((150, 140))
        tile = Image.new("RGB", (160, 150), (236, 226, 204))
        tile.paste(f, ((160 - f.width) // 2, (150 - f.height) // 2), f)
        cx, cy = 20 + (n % 9) * 172, y + 40 + (n // 9) * 186
        out.paste(tile, (cx, cy))
        d.text((cx, cy + 152), sid, fill=(120, 100, 80), font=font(14))
    cab = Image.open(ROOT / "assets/props/ui_cabinet.png").convert("RGBA")
    cab.thumbnail((330, 360))
    out.paste(cab, (20 + 9 * 172 + 10, y + 40), cab)
    tag = Image.open(ROOT / "assets/props/ui_tag.png").convert("RGBA")
    out.paste(tag, (20 + 9 * 172 + 40, y + 40 + cab.height + 6), tag)
    OUT.parent.mkdir(exist_ok=True)
    out.save(OUT)
    print(OUT, out.size)


def poses(pid, path):
    items = []
    for f in ("front34", "back34"):
        rp = rig_path(pid, f)
        sc = scale_for(rp, 300)
        for an in ("idle", "work", "sit", "eat", "wave" if f == "front34" else "wave_up"):
            a = ANIMS[an]
            rig = cl.load_json(rp)
            items.append(render(rp, cl.pose_at(rig, a, a["length"] * 0.5), scale=sc, z=a.get("z")))
    s, _ = strip(items, gap=20)
    bg = Image.new("RGB", s.size, BG)
    bg.paste(s, (0, 0), s)
    bg.save(path)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--poses"]:
        for pid in sys.argv[2:]:
            poses(pid, f"/private/tmp/claude-501/-Users-dengyudie/8a72c248-f9dd-41b0-926a-c97139095275/scratchpad/poses_{pid}.png")
    else:
        sheet(sys.argv[1:] or b34.ALL)
