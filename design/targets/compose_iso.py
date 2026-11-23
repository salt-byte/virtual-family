"""05 斜 45°: the qijia compound as a 2:1 isometric (diamond grid) dollhouse, 1280x720 with the game's bottom bar.
Plan axes: i = east (screen down-right), j = south (screen down-left). The camera sits south-east, so the
north (j=0) and west (i=0) outer walls are the back walls and stand full height; every wall that faces the
camera is cut low. Iso props come from assets/gen/iso/ (generated 2026-11-19); people, tiles, small props
are the existing style-A assets. UI helpers come from compose_targets."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compose_targets as ct  # noqa: E402

cl = ct.cl
ROOT = ct.ROOT
ISO = ROOT / "assets/gen/iso"
W, H = 1280, 720
TW, TH = 64, 32                 # diamond tile
WH, LH = 112, 16                # back wall height, cut-down wall height
CWH, CLH = 74, 22               # compound wall: back height, cut-down height
OX, OY = 600, 104               # screen position of plan point (0, 0) at ground level
CI, CJ = 20, 16                 # compound size in tiles
S = 48                          # texture px per tile before the iso transform
EDGE = (TW / 2) ** 2 + (TH / 2) ** 2
EDGE = EDGE ** 0.5              # screen length of one tile edge (35.8 px)
CAP = (96, 74, 58)


def P(i, j, z=0.0):
    return (OX + (i - j) * TW / 2, OY + (i + j) * TH / 2 - z)


def load(p):
    return ct.trim(ct.load(p))


def sized(im, w=None, h=None):
    k = min((w or 1e9) / im.width, (h or 1e9) / im.height)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def floor(img, tex, i0, j0, w, h, period=192, soften=0.0, dark=1.0):
    t = ct.tile_fill((int(w * S), int(h * S)), ct.load(ROOT / f"assets/tiles/{tex}.png"), period, period, soften)
    if dark != 1.0:
        t = ImageEnhance.Brightness(t).enhance(dark)
    M = np.array([[TW / 2 / S, -TW / 2 / S], [TH / 2 / S, TH / 2 / S]])
    inv = np.linalg.inv(M)
    off = -inv @ np.array(P(i0, j0))
    layer = t.transform((W, H), Image.AFFINE, (inv[0, 0], inv[0, 1], off[0], inv[1, 0], inv[1, 1], off[1]),
                        resample=Image.BICUBIC)
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon([P(i0, j0), P(i0 + w, j0), P(i0 + w, j0 + h), P(i0, j0 + h)], fill=255)
    layer.putalpha(m)
    img.alpha_composite(layer)


def shear_onto(img, flat, start, along_i, shade=1.0):
    """Paste a flat elevation (x along the wall, y down) onto a vertical wall plane whose bottom-left is `start`
    (screen). along_i: the wall runs down-right (north wall); else down-left (west wall)."""
    if shade != 1.0:
        a = np.array(flat).astype(float)
        a[..., :3] *= shade
        flat = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    sx = (TW / 2) / EDGE * (1 if along_i else -1)
    sy = (TH / 2) / EDGE
    x0, y0 = start[0], start[1] - flat.height
    # screen X = x0 + sx*x ; Y = y0 + y + sy*x  -> inverse
    data = (1 / sx, 0, -x0 / sx, -sy / sx, 1, -y0 + sy * x0 / sx)
    layer = flat.transform((W, H), Image.AFFINE, data, resample=Image.BICUBIC)
    img.alpha_composite(layer)


def wall_flat(length_tiles, height, windows=(), hang=(), kind="house"):
    """Elevation of a back wall: beam, plaster, posts, wainscot; decals at tile offsets."""
    L = int(round(length_tiles * EDGE))
    if kind == "house":
        tex = ct.tile_fill((L, height), ct.load(ROOT / "assets/tiles/a_wall.png"), 150, 150, 0.1)
    else:
        tex = ct.tile_fill((L, height), ct.load(ROOT / "assets/tiles/a_wall_compound.png"), 130, 130, 0.0)
    flat = tex.copy()
    d = ImageDraw.Draw(flat)
    if kind == "house":
        d.rectangle((0, 0, L, 9), fill=(110, 76, 50))
        d.line((0, 9, L, 9), fill=ct.LINE, width=2)
        d.rectangle((0, height - 20, L, height), fill=(150, 100, 62))
        d.line((0, height - 20, L, height - 20), fill=ct.LINE, width=2)
        for k in np.arange(0, length_tiles + 0.01, 3):
            x = int(k * EDGE)
            d.rectangle((x - 4, 0, x + 4, height), fill=(122, 82, 52), outline=ct.LINE, width=1)
        for off, name, w in windows:
            dec = sized(load(ISO / f"{name}.png"), w=w)
            flat.alpha_composite(dec, (int(off * EDGE - dec.width / 2), int(height * 0.24)))
        for off, name, w, y in hang:
            dec = sized(load(ISO / f"{name}.png"), w=w)
            flat.alpha_composite(dec, (int(off * EDGE - dec.width / 2), int(y)))
    else:
        d.rectangle((0, height - 16, L, height), fill=(150, 150, 140))
        for x in range(0, L, 22):
            d.line((x, height - 16, x, height), fill=(110, 110, 100), width=1)
        d.line((0, height - 16, L, height - 16), fill=ct.LINE, width=2)
    d.rectangle((0, 0, L - 1, height - 1), outline=ct.LINE, width=2)
    return flat


def cap(d, a, b, z, thick, color, outline=True):
    """Top of a wall from plan a to b at height z, thickness `thick` tiles centred on the line."""
    (i0, j0), (i1, j1) = a, b
    if j0 == j1:
        pts = [P(i0, j0 - thick / 2, z), P(i1, j1 - thick / 2, z), P(i1, j1 + thick / 2, z), P(i0, j0 + thick / 2, z)]
    else:
        pts = [P(i0 - thick / 2, j0, z), P(i1 - thick / 2, j1, z), P(i1 + thick / 2, j1, z), P(i0 + thick / 2, j0, z)]
    d.polygon(pts, fill=color, outline=ct.LINE if outline else None)
    return pts


def low_wall(img, a, b, kind="house"):
    """A cut-down wall segment: visible front face + cream (house) or tiled (compound) top."""
    d = ImageDraw.Draw(img)
    h, th = (LH, 0.2) if kind == "house" else (CLH, 0.28)
    (i0, j0), (i1, j1) = a, b
    if j0 == j1:   # runs along i, face toward +j
        f = [P(i0, j0 + th / 2), P(i1, j1 + th / 2), P(i1, j1 + th / 2, h), P(i0, j0 + th / 2, h)]
        face_col = (226, 210, 182) if kind == "house" else (200, 150, 96)
    else:          # runs along j, face toward +i
        f = [P(i0 + th / 2, j0), P(i1 + th / 2, j1), P(i1 + th / 2, j1, h), P(i0 + th / 2, j0, h)]
        face_col = (198, 182, 156) if kind == "house" else (176, 128, 80)
    d.polygon(f, fill=face_col, outline=ct.LINE)
    # end face so the cut reads as a solid wall
    if j0 == j1:
        e = [P(i1, j1 - th / 2), P(i1, j1 + th / 2), P(i1, j1 + th / 2, h), P(i1, j1 - th / 2, h)]
    else:
        e = [P(i1 - th / 2, j1), P(i1 + th / 2, j1), P(i1 + th / 2, j1, h), P(i1 - th / 2, j1, h)]
    d.polygon(e, fill=tuple(int(c * 0.85) for c in face_col), outline=ct.LINE)
    top = (246, 232, 204) if kind == "house" else (120, 132, 150)
    cap(d, a, b, h, th, top)


def ground_shadow(img, cx, cy, w, alpha=80):
    w = int(w)
    hgt = max(8, w // 2)
    sh = Image.new("RGBA", (w + 24, hgt + 24))
    ImageDraw.Draw(sh).ellipse((12, 12, w + 12, hgt + 12), fill=ct.LINE + (alpha,))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)), (round(cx - (w + 24) / 2), round(cy - (hgt + 24) / 2)))


def wall_ao(img):
    """Soft shade on the floor along the two back walls (sun in the north-west, walls block it)."""
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    for k in range(10):
        t = 0.9 * (1 - k / 10)
        a = int(16 + k * 7)
        d.polygon([P(0, 0), P(CI, 0), P(CI, t), P(0, t)], fill=a)
        d.polygon([P(0, 0), P(0, 8), P(t, 8), P(t, 0)], fill=a)
    m = m.filter(ImageFilter.GaussianBlur(5))
    sh = Image.new("RGBA", (W, H), ct.LINE + (0,))
    sh.putalpha(m.point(lambda v: int(v * 0.85)))
    img.alpha_composite(sh)


def regreen_roof(im):
    """The generated gatehouse came with green glazed tiles; the game's roofs are grey-blue."""
    a = np.array(im).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g > r + 18) & (g > b + 4)
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    for k, c in enumerate((0.86, 0.95, 1.12)):
        a[..., k] = np.where(green, lum * c, a[..., k])
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def rig(name, h, pose=None, anim=None, t=0.0, flip=False):
    rp = ROOT / f"assets/chars/{name}/{name}.rig.json"
    r = cl.load_json(rp)
    p = dict(pose or {})
    if anim:
        anims = cl.load_json(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/references/anims.humanoid_side.json")["animations"]
        p.update(cl.pose_at(r, anims[anim], t))
    lo, hi = cl.bounds(r, [p])
    canvas = (int(hi[0] - lo[0]) + 8, int(hi[1] - lo[1]) + 8)
    im = ct.fit_h(cl.render(r, rp.parent, p, canvas, (4 - lo[0], 4 - lo[1]), 1.0), h)
    return im.transpose(Image.FLIP_LEFT_RIGHT) if flip else im


SIT = {"leg_upper": (-88, 0, 0), "leg_lower": (88, 0, 0), "leg_back_upper": (-80, 0, 0), "leg_back_lower": (84, 0, 0),
       "arm_upper": (-35, 0, 0), "arm_lower": (-45, 0, 0), "arm_back_upper": (-30, 0, 0), "arm_back_lower": (-40, 0, 0)}
STIR = {"arm_upper": (-55, 0, 0), "arm_lower": (-50, 0, 0), "arm_back_upper": (-40, 0, 0), "arm_back_lower": (-60, 0, 0),
        "torso": (5, 0, 0)}


def render():
    img = Image.new("RGBA", (W, H), (150, 190, 110, 255))
    d = ImageDraw.Draw(img)

    # ---- ground
    floor(img, "a_grass", -16, -14, 52, 46, period=220, soften=0.1)
    floor(img, "a_yard", 8.6, 16, 2.8, 14, period=192, soften=0.15)          # dirt road out of the gate
    floor(img, "a_yard", 0, 0, CI, CJ, period=192, soften=0.18)
    floor(img, "a_floor_earth", 0, 0, 5, 8, period=192)
    floor(img, "a_floor_hall", 5, 0, 8, 6, period=150)
    floor(img, "a_floor_bed", 13, 0, 7, 6, period=192)
    floor(img, "a_path", 9, 6, 2, 10, period=150, soften=0.1)
    floor(img, "a_path", 15, 8, 4, 4, period=150, soften=0.1)
    for (i0, j0, w, h) in [(9, 6, 2, 10), (15, 8, 4, 4)]:
        d.polygon([P(i0, j0), P(i0 + w, j0), P(i0 + w, j0 + h), P(i0, j0 + h)], outline=(120, 110, 100))

    # ---- things standing outside, behind the back walls (peek over them)
    things = []   # (depth, kind, payload)
    bamboo = sized(load(ROOT / "assets/props/a_bamboo.png"), h=230)
    tree = sized(load(ROOT / "assets/props/a_big_tree.png"), h=250)
    for (i, j, im) in [(-2.2, 11.5, bamboo), (-1.6, 14.6, sized(bamboo, h=190))]:
        x, y = P(i, j)
        img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height)))
    bush = sized(load(ROOT / "assets/props/a_bush.png"), w=90)
    rocks = sized(load(ROOT / "assets/props/a_rocks.png"), w=80)
    for (i, j) in [(3, -1.6), (16, -1.4)]:
        x, y = P(i, j)
        img.alpha_composite(bush, (round(x - bush.width / 2), round(y - bush.height + 40)))

    # ---- back walls (full height): north j=0 over i 0..20, west i=0 over j 0..8, compound west j 8..16
    wall_ao(img)
    north = wall_flat(CI, WH, windows=[(3.0, "f_window", 46), (8.0, "f_window", 60), (11.0, "f_window", 60),
                                       (17.5, "f_window", 60)], hang=[(1.4, "f_chili", 40, 20)])
    shear_onto(img, north, P(0, 0), along_i=True, shade=1.0)
    west = wall_flat(8, WH, windows=[(5.6, "f_window", 46)], hang=[(2.2, "f_chili", 34, 26)])
    shear_onto(img, west, P(0, 0), along_i=False, shade=0.80)
    cw = wall_flat(8, CWH, kind="compound")
    shear_onto(img, cw, P(0, 8), along_i=False, shade=0.84)
    d = ImageDraw.Draw(img)
    # wall tops: dark beam cap with a grey tile eave on the outside
    cap(d, (0, 0), (CI, 0), WH, 0.22, CAP)
    cap(d, (0, 0), (0, 8), WH, 0.22, CAP)
    eave_n = [P(-0.1, -0.11, WH), P(CI + 0.1, -0.11, WH), P(CI + 0.1, -0.75, WH - 10), P(-0.1, -0.75, WH - 10)]
    eave_w = [P(-0.11, -0.1, WH), P(-0.11, 8, WH), P(-0.75, 8, WH - 10), P(-0.75, -0.1, WH - 10)]
    for poly in (eave_w, eave_n):
        d.polygon(poly, fill=(112, 124, 142), outline=ct.LINE)
    for k in np.arange(0.4, CI, 0.55):
        d.line([P(k, -0.15, WH), P(k, -0.72, WH - 10)], fill=(84, 94, 110), width=2)
    for k in np.arange(0.4, 8, 0.55):
        d.line([P(-0.15, k, WH), P(-0.72, k, WH - 10)], fill=(84, 94, 110), width=2)
    cap(d, (0, 8), (0, 16), CWH, 0.3, (120, 132, 150))
    for k in np.arange(8.3, 16, 0.5):
        d.line([P(-0.15, k, CWH), P(0.15, k, CWH)], fill=(84, 94, 110), width=2)
    # end of the house's west wall where the lower compound wall continues
    d.polygon([P(-0.11, 8, 0), P(0.11, 8, 0), P(0.11, 8, WH), P(-0.11, 8, WH)], fill=(170, 150, 120), outline=ct.LINE)

    # ---- low walls, split into unit pieces so they depth-sort with people and props
    def segs(a, b, gaps=(), kind="house"):
        (i0, j0), (i1, j1) = a, b
        n = int(round(max(abs(i1 - i0), abs(j1 - j0))))
        pieces = []
        for k in range(n):
            if j0 == j1:
                s, e = (i0 + k, j0), (i0 + k + 1, j0)
                pos = i0 + k + 0.5
            else:
                s, e = (i0, j0 + k), (i0, j0 + k + 1)
                pos = j0 + k + 0.5
            if any(g0 <= pos <= g1 for g0, g1 in gaps):
                continue
            depth = (s[0] + e[0]) / 2 + (s[1] + e[1]) / 2 + 0.05
            pieces.append((depth, "wall", (s, e, kind)))
        return pieces

    things += segs((0, 8), (5, 8))
    things += segs((5, 0), (5, 8), gaps=[(2, 3), (6, 7)])
    things += segs((5, 6), (13, 6), gaps=[(9, 11)])
    things += segs((13, 0), (13, 6), gaps=[(2, 3)])
    things += segs((13, 6), (20, 6), gaps=[(15, 16)])
    things += segs((20, 0), (20, 6))
    things += segs((20, 6), (20, 16), kind="compound")
    things += segs((0, 16), (20, 16), gaps=[(8, 12)], kind="compound")
    # stone thresholds in the doorways of cut walls
    for (a, b) in [((9, 6), (11, 6)), ((15, 6), (16, 6)), ((5, 6), (5, 7)), ((5, 2), (5, 3)), ((13, 2), (13, 3))]:
        cap(d, a, b, 3, 0.3, (168, 170, 166))

    # ---- props: (name, plan i, plan j, width px, flip)
    props = [
        ("i_stove", 1.6, 2.4, 128, False), ("i_vat", 3.9, 5.0, 62, False), ("i_cupboard", 3.7, 1.1, 78, False),
        ("i_altar", 9.3, 1.0, 140, True), ("i_table", 9.2, 3.6, 150, False), ("i_stool", 6.6, 4.6, 44, False),
        ("i_kang_sleeper", 17.6, 2.0, 184, False), ("i_desk", 14.0, 4.6, 92, False),
        ("i_trellis", 6.9, 11.0, 150, False), ("i_well", 17.0, 10.0, 104, False), ("i_bench", 7.6, 7.4, 92, False),
        ("i_clothesline", 16.4, 14.2, 124, False), ("i_woodpile", 1.6, 9.6, 84, False),
        ("i_coop_hen", 18.8, 7.6, 96, False), ("i_washtub", 13.9, 7.7, 64, False), ("i_millstone", 3.4, 13.2, 82, False),
    ]
    for name, i, j, w, flip in props:
        im = sized(load(ISO / f"{name}.png"), w=w)
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        things.append((i + j, "prop", (im, i, j)))
    gate = sized(regreen_roof(load(ISO / "i_gate.png")), w=210)
    things.append((10 + 16 + 0.3, "prop", (gate, 10.15, 16.25)))
    # small style-A props that are flat or round enough to read from any side
    for nm, i, j, w in [("a_mess_droppings", 12.8, 9.6, 44)]:
        things.append((i + j - 0.5, "flat", (sized(load(ROOT / f"assets/props/{nm}.png"), w=w), i, j)))
    tree_i, tree_j = 1.2, 21.0
    things.append((tree_i + tree_j, "prop", (tree, tree_i, tree_j)))
    things.append((22.2 + 8.6, "prop", (sized(bush, w=110), 22.2, 8.6)))

    # ---- people
    father = rig("a_father", 86, anim="walk", t=0.15)
    mother = rig("a_mother", 82, pose=STIR)
    grandpa = rig("a_grandpa", 70, pose=SIT)
    child = ct.fit_h(ct.clean_green(ct.load(ROOT / "assets/chars/a_child.png")), 58)
    people = [
        dict(name="程大柱", img=father, at=(11.9, 10.0), selected=True, doing="拿铁锹铲掉院里的鸡粪", progress=0.35),
        dict(name="柳晚晴", img=mother, at=(1.0, 4.0), doing="烧火做晌午饭"),
        dict(name="程老栓", img=grandpa, at=(8.73, 4.52), doing="坐在桌边歇脚"),
        dict(name="程小满", img=child, at=(16.0, 11.5), doing="趴在井沿看水"),
        dict(name="苏素纨", img=None, at=(17.4, 2.1), asleep=True),
    ]
    for pe in people:
        if pe["img"] is not None:
            i, j = pe["at"]
            things.append((i + j + 0.02, "person", pe))

    # coin pickup near the trellis
    coin = sized(load(ROOT / "assets/props/a_col_coins.png"), w=30)

    things.sort(key=lambda t: t[0])
    tops = []
    for depth, kind, data in things:
        if kind == "wall":
            s, e, k = data
            low_wall(img, s, e, k)
        elif kind in ("prop", "flat"):
            im, i, j = data
            x, y = P(i, j)
            if kind == "prop":
                ground_shadow(img, x, y - 4, im.width * 0.8, 70)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height + (8 if kind == "prop" else im.height / 2))))
        else:
            pe = data
            i, j = pe["at"]
            x, y = P(i, j)
            fig = pe["img"]
            y -= pe.get("lift", 0)
            dd = ImageDraw.Draw(img)
            if not pe.get("lift"):
                ground_shadow(img, x, y, 40, 90)
            if pe.get("selected"):
                dd.ellipse((x - 30, y - 13, x + 30, y + 13), outline=ct.TOMATO, width=4)
            img.alpha_composite(fig, (round(x - fig.width / 2), round(y - fig.height + 3)))
            tops.append((x, y - fig.height, pe))
    d = ImageDraw.Draw(img)
    cx, cy = P(12.4, 13.0)
    d.ellipse((cx - 22, cy - 11, cx + 22, cy + 11), fill=(196, 230, 248), outline=ct.SKY, width=3)
    img.alpha_composite(coin, (round(cx - coin.width / 2), round(cy - coin.height + 4)))

    # ---- room names on the floor, by the back wall
    for name, (i, j) in [("灶间", (0.4, 6.1)), ("堂屋", (5.5, 4.9)), ("卧房", (13.5, 4.9)), ("院子", (12.0, 14.6)), ("井台", (18.6, 11.4))]:
        x, y = P(i, j)
        d.text((x, y), name, font=ct.T(17), fill=(255, 248, 232), stroke_width=3, stroke_fill=ct.LINE, anchor="lm")

    # ---- name tags (selected person gets the plate)
    for x, top, pe in tops:
        if pe.get("selected"):
            w = 168
            px0, py0 = x - w / 2, top - 62
            d.polygon([(x - 7, top - 16), (x + 7, top - 16), (x, top - 6)], fill=ct.TOMATO)
            d.rounded_rectangle((px0, py0, px0 + w, py0 + 42), 12, fill=ct.CREAM, outline=ct.LINE, width=2)
            d.text((x, py0 + 12), pe["name"], font=ct.T(16), fill=ct.LINE, anchor="mm")
            d.text((x, py0 + 29), pe["doing"], font=ct.B(11), fill=ct.LINE, anchor="mm")
            d.rounded_rectangle((px0 + 10, py0 + 37, px0 + w - 10, py0 + 41), 2, fill=(230, 214, 186))
            d.rounded_rectangle((px0 + 10, py0 + 37, px0 + 10 + (w - 20) * pe["progress"], py0 + 41), 2, fill=ct.TOMATO)
        else:
            d.text((x, top - 10), pe["name"], font=ct.T(14), fill=ct.LINE, anchor="mm", stroke_width=3, stroke_fill=ct.CREAM)
    # sleeper on the kang: name + z's
    x, y = P(17.4, 2.1)
    d.text((x + 8, y - 150), "苏素纨", font=ct.T(14), fill=ct.LINE, anchor="mm", stroke_width=3, stroke_fill=ct.CREAM)
    for k, s in enumerate((12, 15, 18)):
        d.text((x + 66 + k * 10, y - 100 - k * 11), "z", font=ct.T(s), fill=(90, 110, 170), anchor="mm",
               stroke_width=2, stroke_fill=ct.CREAM)
    return img, father


def main(out=HERE / "05_斜45度.png", ui=True):
    img, father = render()
    if ui:
        ct.toast(img, "捡到鸡窝外的鸡蛋，卖了 6 文")
        sel = dict(name="程大柱", line="34 岁 · 佃户", doing_bar="拿铁锹铲掉院里的鸡粪 · 35%",
                   status=[("半饱", False), ("抖擞", False), ("舒心", False), ("康健", False)], face=ct.face_of(father))
        ct.bar(img, sel, 200, 6)
    img.convert("RGB").save(out)
    print(out, img.size)
    return img


if __name__ == "__main__":
    main()
