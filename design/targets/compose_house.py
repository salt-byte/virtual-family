"""03 连成一座房子: the qijia compound drawn as one house seen from above with the roof lifted off.
Rooms share walls, doorways connect them, a compound wall with a gate surrounds the courtyard, and five
places lie outside the wall. The grid here is a PROPOSAL for the game code (rooms.json keeps its own
positions for now). Style A pieces come from assets/ (not committed); UI helpers come from compose_targets."""
import importlib.util
import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import math
import random
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ct", HERE / "compose_targets.py")
ct = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ct)
ROOT = ct.ROOT
CW, CH = 48, 36
MAP_W, MAP_H = 56, 32           # cells
PAD = 2                          # extra cells of grass drawn around the map (wall tops rise above y=0)
OX, OY = 11, 6                   # compound origin in map cells
T, F = 12, 22                    # house wall: plan thickness, front-face height (px)
CT, CF = 16, 34                  # compound wall
DOOR = 1                         # door width in cells (the hall's main door is 2)

# room: (x, y, w, h) in compound cells, kind, built
ROOMS = {
    "woodshed": ((0, 0, 6, 6), "earth", True),
    "west_room": ((6, 0, 6, 6), "wood", False),
    "hall": ((12, 0, 10, 6), "brick", True),
    "bedroom": ((22, 0, 6, 6), "wood", True),
    "side": ((28, 0, 6, 6), "wood", False),
    "kitchen": ((0, 6, 6, 6), "earth", True),
    "study": ((0, 12, 6, 7), "wood", False),
    "coop_run": ((28, 6, 6, 7), "out", True),
    "pigsty": ((28, 13, 6, 6), "out", False),
    "yard": ((6, 6, 17, 7), "out", True),
    "well": ((23, 6, 5, 7), "paved", True),
    "threshing": ((6, 13, 7, 6), "out", False),
    "gate": ((13, 13, 8, 6), "out", True),
    "veg_plot": ((21, 13, 7, 6), "out", False),
}
COMPOUND = (0, 0, 34, 19)
# doors: (orientation, fixed line in compound cells, from, to) — gaps in a wall
DOORS = [("h", 6, 16, 18), ("h", 6, 24, 25), ("v", 22, 3, 4), ("h", 6, 2, 3), ("v", 6, 8, 9)]
GATE = (16, 18)                  # opening in the south compound wall (x cells)
FLOOR = {"brick": "a_floor_hall", "wood": "a_floor_bed", "earth": "a_floor_earth", "paved": "a_path", "out": "a_yard"}
OUTSIDE = {  # label, label cell (map coords)
    "bamboo": ("竹林", (2, 6)), "hill": ("后山小路", (17, 1)), "river": ("河边", (47, 9)),
    "field": ("田埂", (2, 23)), "tree": ("村口大树下", (33, 26)),
}


def px(cx, cy):
    return ((cx + PAD) * CW, (cy + PAD) * CH)


def croom(rid):
    (x, y, w, h), kind, built = ROOMS[rid]
    x0, y0 = px(OX + x, OY + y)
    return x0, y0, x0 + w * CW, y0 + h * CH


def tile(name, size, tw=192, th=144, soften=0.0):
    return ct.tile_fill(size, ct.load(ROOT / f"assets/tiles/{name}.png"), tw, th, soften)


def sprite(name, w=None, h=None):
    im = ct.trim(ct.load(ROOT / f"assets/props/{name}.png"))
    k = min((w or 1e9) / im.width, (h or 1e9) / im.height)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def put(img, im, x, y_bottom, shadow=True):
    if shadow:
        ct.shadow(img, x, y_bottom - 2, im.width * 0.75)
    img.alpha_composite(im, (round(x - im.width / 2), round(y_bottom - im.height)))


def strip(img, name, box, soften=0.15, radius=10):
    x0, y0, x1, y1 = [int(v) for v in box]
    t = tile(name, (x1 - x0, y1 - y0), soften=soften)
    m = Image.new("L", t.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, t.width - 1, t.height - 1), radius, fill=255)
    t.putalpha(m.filter(ImageFilter.GaussianBlur(1.5)))
    img.alpha_composite(t, (x0, y0))


# ---------------------------------------------------------------- walls
def wall_segments(orient, line, a, b, gaps):
    """Split [a, b] (cells) by door gaps on this wall line."""
    cuts = sorted((g0, g1) for o, l, g0, g1 in gaps if o == orient and l == line and g0 < b and g1 > a)
    segs, cur = [], a
    for g0, g1 in cuts:
        if g0 > cur:
            segs.append((cur, g0))
        cur = max(cur, g1)
    if cur < b:
        segs.append((cur, b))
    return segs


def draw_hwall(img, d, x0, x1, Y, t, f, face, cap, outline=ct.LINE):
    """East-west wall whose plan line is Y (px): raised top face plus a south-facing front face."""
    top = (x0 - t / 2, Y - t / 2 - f, x1 + t / 2, Y + t / 2 - f)
    fw, fh = int(x1 - x0 + t), int(f)
    if fw > 0:
        img.alpha_composite(face.resize((fw, fh)) if face.size != (fw, fh) else face, (int(x0 - t / 2), int(Y + t / 2 - f)))
    d.rectangle((x0 - t / 2, Y + t / 2 - f, x1 + t / 2, Y + t / 2), outline=outline, width=2)
    d.rectangle(top, fill=cap, outline=outline, width=2)


def draw_vwall(img, d, X, y0, y1, t, f, face, cap, outline=ct.LINE):
    img.alpha_composite(face.resize((int(t), int(f))), (int(X - t / 2), int(y1 + t / 2 - f)))
    d.rectangle((X - t / 2, y1 + t / 2 - f, X + t / 2, y1 + t / 2), outline=outline, width=2)
    d.rectangle((X - t / 2, y0 - t / 2 - f, X + t / 2, y1 + t / 2 - f), fill=cap, outline=outline, width=2)


def face_strip(name, w, h, darken=1.0):
    src = ct.load(ROOT / f"assets/tiles/{name}.png")
    k = h / src.height
    t = src.resize((max(1, int(src.width * k)), h), Image.LANCZOS)
    out = Image.new("RGBA", (max(1, w), h))
    for x in range(0, w, t.width):
        out.paste(t, (x, 0))
    if darken != 1.0:
        a = np.array(out).astype(float)
        a[..., :3] *= darken
        out = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    return out


# ---------------------------------------------------------------- map
def render(people=(), messes=(), collectibles=(), tall=False):
    W, H = (MAP_W + 2 * PAD) * CW, (MAP_H + 2 * PAD) * CH
    img = tile("a_grass", (W, H), soften=0.12)
    d = ImageDraw.Draw(img)
    rnd = random.Random(4)
    pills = []

    # outside places
    gx0, gy0 = px(0, 21)
    gx1, gy1 = px(21, MAP_H)
    strip(img, "a_field", (gx0, gy0, gx1, gy1), 0.05, 16)
    for yy in (25, 29):
        strip(img, "a_yard", (*px(0, yy), px(21, yy)[0], px(0, yy)[1] + CH * 0.6), 0.1, 6)
    for xx in (7, 14):
        strip(img, "a_yard", (*px(xx, 21), px(xx, 21)[0] + CW * 0.5, px(0, MAP_H)[1]), 0.1, 6)
    rx0, _ = px(51, 0)
    rx1, _ = px(54, 0)
    strip(img, "a_water", (rx0, 0, rx1, H), 0.0, 0)
    d.line([(rx0, 0), (rx0, H)], fill=(120, 150, 110), width=4)
    d.line([(rx1, 0), (rx1, H)], fill=(120, 150, 110), width=4)
    # paths: back-hill path, gate road, branches to the field and the tree, riverside path
    for box in [(px(10, 1), px(46, 3)), (px(27, 25), px(29, MAP_H + PAD)), (px(19, 28), px(29, 30)),
                (px(29, 29), px(40, 31)), (px(44, 1), px(46, 30)), (px(40, 29), px(46, 31))]:
        (a, b), (c, e) = box
        strip(img, "a_yard", (a, b, c, e), 0.1, 14)
    bx, by = px(51, 17)
    br = sprite("a_bridge", w=CW * 3.6, h=CH * 3.4)
    img.alpha_composite(br, (int(bx + (CW * 3 - br.width) / 2), int(by)))
    for cy in range(1, MAP_H, 3):
        if cy not in (16, 19):
            put(img, sprite("a_reeds", h=58), px(50, cy)[0] + rnd.randint(-10, 10), px(0, cy)[1] + 30, False)
    for (cx, cy) in [(1, 9), (3, 6), (5, 11), (7, 7), (2, 14), (8, 13), (4, 17), (9, 10), (6, 16), (1, 19)]:
        put(img, sprite("a_bamboo", h=150), px(cx, cy)[0], px(0, cy)[1] + 20)
    for (cx, cy, n) in [(12, 4, "a_rocks"), (20, 0, "a_bush"), (33, 4, "a_rocks"), (40, 0, "a_bush"), (47, 4, "a_bush"),
                        (25, 0, "a_rocks"), (44, 33, "a_bush"), (22, 33, "a_rocks")]:
        put(img, sprite(n, w=64), px(cx, cy)[0], px(0, cy)[1] + 28)
    put(img, sprite("a_scarecrow", h=96), px(10, 24)[0], px(0, 24)[1] + 30)
    tx, ty = px(37, 30)
    put(img, sprite("a_stone_bench", w=96), tx - 70, ty + 40)
    put(img, sprite("a_big_tree", h=260), tx, ty + 30)
    for key, (label, (lx, ly)) in OUTSIDE.items():
        pills.append((*px(lx, ly), label, None))

    # compound ground: courtyard, then rooms
    cx0, cy0 = px(OX, OY)
    cx1, cy1 = px(OX + COMPOUND[2], OY + COMPOUND[3])
    img.alpha_composite(tile("a_yard", (cx1 - cx0, cy1 - cy0), soften=0.22), (cx0, cy0))
    pa, pb = px(OX + 16, OY + 6), px(OX + 18, OY + 19)
    strip(img, "a_path", (pa[0], pa[1], pb[0], pb[1]), 0.15, 8)
    for rid, ((x, y, w, h), kind, built) in ROOMS.items():
        x0, y0, x1, y1 = croom(rid)
        name = ct.rooms[rid]["name"]
        cost = ct.rooms[rid].get("build_cost", 0)
        if kind == "out":
            if not built:
                c = (150, 116, 84)
                for a, b in [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))]:
                    ct.dashed(d, a, b, c)
                pills.append(((x0 + x1) / 2, (y0 + y1) / 2, name, cost))
            else:
                pills.append((x0 + 12, y1 - 22, name, None))
            continue
        if kind == "paved":
            img.alpha_composite(tile("a_path", (x1 - x0, y1 - y0), soften=0.2), (x0, y0))
            pills.append((x0 + 12, y1 - 22, name, None))
            continue
        if built:
            img.alpha_composite(tile(FLOOR[kind], (x1 - x0, y1 - y0), soften=0.2), (x0, y0))
            pills.append((x0 + 14, y0 + T / 2 + 6, name, None))
        else:
            d.rectangle((x0, y0, x1, y1), fill=ct.PLOT)
            d.rectangle((x0 + 4, y0 + 4, x1 - 4, y1 - 4), outline=(176, 168, 156), width=6)
            c = (150, 116, 84)
            for a, b in [((x0 + 4, y0 + 4), (x1 - 4, y0 + 4)), ((x1 - 4, y0 + 4), (x1 - 4, y1 - 4)),
                         ((x1 - 4, y1 - 4), (x0 + 4, y1 - 4)), ((x0 + 4, y1 - 4), (x0 + 4, y0 + 4))]:
                ct.dashed(d, a, b, c, width=2)
            pills.append(((x0 + x1) / 2, (y0 + y1) / 2, name, cost))
    # coop fence on the coop run's west edge, gap of one cell to the well
    fx, _ = px(OX + 28, 0)
    for cyy in range(OY + 6, OY + 13):
        if cyy in (OY + 9,):
            continue
        f = sprite("a_fence", w=CH * 1.15).rotate(90, expand=True)
        f = f.resize((14, CH + 4))
        img.alpha_composite(f, (int(fx - 7), int(px(0, cyy)[1] - 2)))

    if tall:
        import depth_walls
        depth_walls.draw(img, d, sys.modules[__name__])
    else:
        # walls: built indoor rooms draw their edges; the compound wall replaces outer edges
        house_face = face_strip("a_wall", 400, F, 0.96)
        cap = (246, 232, 204)
        built_in = {rid for rid, (_, k, b) in ROOMS.items() if b and k not in ("out", "paved")}
        hw, vw = {}, {}
        for rid in built_in:
            (x, y, w, h), _, _ = ROOMS[rid]
            for Y in (y, y + h):
                if Y in (COMPOUND[1], COMPOUND[3]):
                    continue
                hw.setdefault(Y, []).append((x, x + w))
            for X in (x, x + w):
                if X in (COMPOUND[0], COMPOUND[2]):
                    continue
                vw.setdefault(X, []).append((y, y + h))
        for X, spans in vw.items():
            for a, b in spans:
                for s0, s1 in wall_segments("v", X, a, b, DOORS):
                    Xp = px(OX + X, 0)[0]
                    draw_vwall(img, d, Xp, px(0, OY + s0)[1], px(0, OY + s1)[1], T, F, house_face, cap)
        for Y, spans in sorted(hw.items()):
            for a, b in spans:
                for s0, s1 in wall_segments("h", Y, a, b, DOORS):
                    Yp = px(0, OY + Y)[1]
                    x0p, x1p = px(OX + s0, 0)[0], px(OX + s1, 0)[0]
                    draw_hwall(img, d, x0p, x1p, Yp, T, F, face_strip("a_wall", int(x1p - x0p + T), F, 0.96), cap)
        for o, line, g0, g1 in DOORS:  # thresholds in the gaps
            if o == "h":
                Yp = px(0, OY + line)[1]
                sill = sprite("a_door_sill", w=(g1 - g0) * CW - 6)
                img.alpha_composite(sill, (int(px(OX + g0, 0)[0] + 3), int(Yp - sill.height / 2)))
            else:
                Xp = px(OX + line, 0)[0]
                ya, yb = px(0, OY + g0)[1], px(0, OY + g1)[1]
                d.rounded_rectangle((Xp - 7, ya + 2, Xp + 7, yb - 2), 4, fill=(150, 150, 150), outline=ct.LINE, width=2)
        # compound wall
        cface = face_strip("a_wall_compound", 400, CF)
        ccap = (128, 132, 142)
        ax0, ay0 = px(OX, OY)
        ax1, ay1 = px(OX + COMPOUND[2], OY + COMPOUND[3])
        draw_vwall(img, d, ax0, ay0, ay1, CT, CF, cface, ccap)
        draw_vwall(img, d, ax1, ay0, ay1, CT, CF, cface, ccap)
        draw_hwall(img, d, ax0, ax1, ay0, CT, CF, face_strip("a_wall_compound", ax1 - ax0 + CT, CF), ccap)
        gl, gr = px(OX + GATE[0], 0)[0], px(OX + GATE[1], 0)[0]
        draw_hwall(img, d, ax0, gl, ay1, CT, CF, face_strip("a_wall_compound", int(gl - ax0 + CT), CF), ccap)
        draw_hwall(img, d, gr, ax1, ay1, CT, CF, face_strip("a_wall_compound", int(ax1 - gr + CT), CF), ccap)
        for xx in range(int(ax0), int(ax1), 24):  # tile cap ridges
            d.line([(xx, ay0 - CT / 2 - CF), (xx, ay0 + CT / 2 - CF)], fill=(98, 102, 112), width=1)
        gh = sprite("a_gatehouse", w=(GATE[1] - GATE[0] + 1.6) * CW)
        put(img, gh, (gl + gr) / 2, ay1 + CT / 2 + 4, shadow=False)

    # standing things, sorted by foot y
    draw = []
    for o in ct.objects:
        if o["room"] not in ROOMS or not ROOMS[o["room"]][2]:
            continue
        t = ct.objtypes[o["type"]]
        x0, y0, _, _ = croom(o["room"])
        rx, ry, rw, rh = x0 + o["x"] * CW, y0 + o["y"] * CH, t["w"] * CW, t["h"] * CH
        p = ROOT / f"assets/props/a_{o['type']}.png"
        if p.exists():
            draw.append((ry + rh, "obj", (rx, ry, rw, rh, p)))
    for rid, cxx, cyy, typ in messes:
        x0, y0, _, _ = croom(rid)
        draw.append((y0 + cyy * CH, "mess", (x0 + cxx * CW + CW / 2, y0 + cyy * CH + CH / 2, typ)))
    for rid, cxx, cyy, typ in collectibles:
        x0, y0, _, _ = croom(rid)
        draw.append((y0 + cyy * CH, "col", (x0 + cxx * CW + CW / 2, y0 + cyy * CH + CH / 2, typ)))
    for pe in people:
        x0, y0, _, _ = croom(pe["room"])
        pe = dict(pe, at=(x0 + pe["cell"][0] * CW + CW / 2, y0 + pe["cell"][1] * CH + CH / 2 + 10))
        draw.append((pe["at"][1], "person", pe))
    draw.sort(key=lambda e: e[0])
    tops = []
    for _, kind, data in draw:
        if kind == "obj":
            rx, ry, rw, rh, p = data
            im = ct.trim(ct.load(p))
            k = min(rw * 0.9 / im.width, (rh + 24) / im.height)
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            ct.shadow(img, rx + rw / 2, ry + rh - 2, im.width * (0.95 if tall else 0.8))
            img.alpha_composite(im, (round(rx + (rw - im.width) / 2), round(ry + rh - im.height + 2)))
        elif kind == "mess":
            x, y, typ = data
            im = sprite(f"a_{typ}", w=54)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height / 2)))
        elif kind == "col":
            x, y, typ = data
            d.ellipse((x - 20, y - 12, x + 20, y + 12), fill=(235, 247, 255), outline=ct.SKY, width=3)
            im = sprite(f"a_{typ}", w=28)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height / 2 - 4)))
        else:
            x, y = data["at"]
            fig = data["img"]
            ct.shadow(img, x, y)
            if data.get("selected"):
                d.ellipse((x - 27, y - 10, x + 27, y + 10), outline=ct.TOMATO, width=4)
                d.polygon([(x - 7, y - fig.height - 14), (x + 7, y - fig.height - 14), (x, y - fig.height - 4)], fill=ct.TOMATO)
            img.alpha_composite(fig, (round(x - fig.width / 2), round(y - fig.height + 2)))
            tops.append((x, y - fig.height, data))
    # labels: small text on the floor near the wall; unbuilt places get a cost pill
    for x, y, name, cost in pills:
        if cost is None:
            d.text((x, y), name, font=ct.T(16), fill=ct.LINE, stroke_width=3, stroke_fill=ct.CREAM)
        else:
            d.text((x, y - 12), name, font=ct.T(22), fill=(130, 100, 72), anchor="mm", stroke_width=3, stroke_fill=ct.CREAM)
            tw = d.textlength(f"加盖 {cost} 文", font=ct.B(13)) + 22
            d.rounded_rectangle((x - tw / 2, y + 6, x + tw / 2, y + 30), 12, fill=ct.BTN, outline=ct.LINE, width=2)
            d.text((x, y + 18), f"加盖 {cost} 文", font=ct.B(13), fill=ct.LINE, anchor="mm")
    for x, top, pe in tops:
        if pe.get("selected"):
            w = 168
            px0, py0 = x - w / 2, top - 62
            d.rounded_rectangle((px0, py0, px0 + w, py0 + 42), 12, fill=ct.CREAM, outline=ct.LINE, width=2)
            d.text((x, py0 + 12), pe["name"], font=ct.T(16), fill=ct.LINE, anchor="mm")
            d.text((x, py0 + 29), pe["doing"], font=ct.B(11), fill=ct.LINE, anchor="mm")
            d.rounded_rectangle((px0 + 10, py0 + 37, px0 + w - 10, py0 + 41), 2, fill=(230, 214, 186))
            d.rounded_rectangle((px0 + 10, py0 + 37, px0 + 10 + (w - 20) * pe.get("progress", 0), py0 + 41), 2, fill=ct.TOMATO)
        else:
            d.text((x, top - 10), pe["name"], font=ct.T(14), fill=ct.LINE, anchor="mm", stroke_width=3, stroke_fill=ct.CREAM)
    return img


def main():
    father = ct.rig_figure("a_father", "walk", 0.15, 90)
    mother = ct.rig_figure("a_mother", None, 0, 86, flip=True)
    grandma = ct.fit_h(ct.clean_green(ct.load(ROOT / "assets/chars/a_grandma.png")), 74)
    child = ct.fit_h(ct.clean_green(ct.load(ROOT / "assets/chars/a_child.png")), 62)
    people = [
        dict(name="程大柱", img=father, room="yard", cell=(9, 3), selected=True, doing="拿铁锹铲掉院里的鸡粪", progress=0.35),
        dict(name="柳晚晴", img=mother, room="hall", cell=(2, 3), doing="就着亮光缝补旧衣裳"),
        dict(name="苏素纨", img=grandma, room="kitchen", cell=(4, 3), doing="蹲在灶前烧火熬粥"),
        dict(name="程小满", img=child, room="well", cell=(2, 5), doing="对着水缸照影子"),
    ]
    big = render(people, [("yard", 10, 3, "mess_droppings"), ("hall", 8, 4, "mess_dirt"), ("yard", 3, 5, "mess_dirt")],
                 [("yard", 14, 1, "col_coins")])
    out = ROOT / "design/targets"
    # 03: game viewport at scale 1, camera on the hall and courtyard
    vx, vy = px(OX + 1.2, OY - 2.2)
    view = big.crop((int(vx), int(vy), int(vx) + ct.W, int(vy) + ct.H)).copy()
    ct.bar(view, dict(name="程大柱", line="34 岁 · 佃户", face=ct.face_of(ct.rig_figure("a_father", None, 0, 400)),
                      doing_bar="拿铁锹铲掉院里的鸡粪 · 35%",
                      status=[("半饱", False), ("抖擞", False), ("舒心", False), ("康健", False)]), 200, 6)
    ct.toast(view, "捡到鸡窝外的鸡蛋，卖了 6 文")
    view.convert("RGB").save(out / "03_连成一座房子.png")
    # 03b: whole map at fit scale, no UI
    k = min(ct.W / big.width, ct.H / big.height)
    small = big.resize((round(big.width * k), round(big.height * k)), Image.LANCZOS)
    canvas = ct.tile_fill((ct.W, ct.H), ct.load(ROOT / "assets/tiles/a_grass.png"), round(192 * k), round(144 * k), 0.12)
    canvas.alpha_composite(small, ((ct.W - small.width) // 2, (ct.H - small.height) // 2))
    canvas.convert("RGB").save(out / "03b_全图.png")
    print("scale for 03b:", round(k, 3), "map px:", big.size)


if __name__ == "__main__":
    main()
