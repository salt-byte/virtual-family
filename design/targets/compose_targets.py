"""Compose 起家 target images at the real 1280x720 viewport from generated, pipeline-processed pieces.
Geometry follows game/kernel/view (CELL 48x36, WALL 30, BOTTOM_BAR 96, scale 1, rooms.json positions)."""
import json, math, random, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = Path("/Users/dengyudie/Downloads/virtual-family")
sys.path.insert(0, str(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/scripts"))
import cutout_lib as cl  # noqa

W, H = 1280, 720
BAR = 96
CW, CH = 48, 36
WALL = 30
CAM = (40, 46)  # house origin on screen
INK = (43, 38, 34)
ZHU = (181, 68, 58)
PAPER = (236, 229, 213)
SONG = "/System/Library/Fonts/Supplemental/Songti.ttc"


def F(size, bold=False):
    return ImageFont.truetype(SONG, size, index=1 if bold else 6)


rooms = {r["id"]: r for r in json.load(open(ROOT / "game/packs/qijia/rooms.json"))}
objtypes = {o["id"]: o for o in json.load(open(ROOT / "game/packs/qijia/objects.json"))}
pack = json.load(open(ROOT / "game/packs/qijia/pack.json"))
objects = [dict(type=o["type"], room=o["room"], x=o["x"], y=o["y"]) for o in pack["start_objects"]]
for rid, r in rooms.items():
    for p in r.get("props", []):
        objects.append(dict(type=p["type"], room=rid, x=p["x"], y=p["y"]))


def room_rect(rid):
    r = rooms[rid]
    x, y = CAM[0] + r["x"] * CW, CAM[1] + r["y"] * CH
    return (x, y, x + r["w"] * CW, y + r["h"] * CH)


def cell_center(rid, cx, cy):
    x0, y0, _, _ = room_rect(rid)
    return (x0 + cx * CW + CW / 2, y0 + cy * CH + CH / 2)


def load(p):
    return Image.open(p).convert("RGBA")


def tile_fill(size, tile, tw, th):
    t = tile.resize((tw, th), Image.LANCZOS)
    out = Image.new("RGBA", size)
    for yy in range(0, size[1], th):
        for xx in range(0, size[0], tw):
            out.paste(t, (xx, yy))
    return out


def jitter_line(d, a, b, width=2, color=INK + (220,), seed=0, step=10, amp=0.8):
    rnd = random.Random(seed)
    n = max(2, int(math.dist(a, b) / step))
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((a[0] + (b[0] - a[0]) * t + rnd.uniform(-amp, amp), a[1] + (b[1] - a[1]) * t + rnd.uniform(-amp, amp)))
    for i in range(n):
        w = max(1, round(width + rnd.uniform(-0.6, 0.8)))
        d.line([pts[i], pts[i + 1]], fill=color, width=w)


def dashed(d, a, b, color, dash=9, gap=7, width=2):
    L = math.dist(a, b)
    ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    s = 0
    while s < L:
        e = min(L, s + dash)
        d.line([(a[0] + ux * s, a[1] + uy * s), (a[0] + ux * e, a[1] + uy * e)], fill=color, width=width)
        s += dash + gap


def paper(size, seed=1):
    rnd = np.random.default_rng(seed)
    base = np.ones((size[1], size[0], 3)) * np.array(PAPER)
    noise = rnd.normal(0, 1, (size[1] // 4 + 1, size[0] // 4 + 1))
    noise = np.kron(noise, np.ones((4, 4)))[: size[1], : size[0]]
    fine = rnd.normal(0, 2.2, (size[1], size[0]))
    base += (noise * 3 + fine)[..., None]
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")


def feather(img, px=5):
    a = img.split()[3]
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rectangle((px, px, img.size[0] - px, img.size[1] - px), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(px))
    img.putalpha(ImageChops.multiply(a, m))
    return img


def clean_green(img):
    """Key out leftover green-screen smudges (saturated green) under the feet of the standing refs."""
    a = np.array(img).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    spill = (g - np.maximum(r, b)) > 40
    a[..., 3] = np.where(spill, 0, a[..., 3])
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def trim(img):
    bb = img.getbbox()
    return img.crop(bb) if bb else img


def fit_h(img, h):
    img = trim(img)
    return img.resize((max(1, round(img.width * h / img.height)), h), Image.LANCZOS)


def rig_figure(name, anim=None, t=0.0, height=60):
    rp = ROOT / f"assets/chars/{name}/{name}.rig.json"
    rig = cl.load_json(rp)
    base = rp.parent
    pose = {}
    if anim:
        anims = cl.load_json(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/references/anims.humanoid_side.json")["animations"]
        pose = cl.pose_at(rig, anims[anim], t)
    lo, hi = cl.bounds(rig, [pose])
    canvas = (int(hi[0] - lo[0]) + 8, int(hi[1] - lo[1]) + 8)
    img = cl.render(rig, base, pose, canvas, (4 - lo[0], 4 - lo[1]), 1.0)
    return fit_h(img, height)


# ---------------------------------------------------------------- house layer
def house(night=False, people=(), messes=(), collectibles=(), seed=3):
    img = paper((W, H), seed)
    d = ImageDraw.Draw(img, "RGBA")
    labels = []
    brick = load(ROOT / "assets/tiles/tile_brick.png")
    yard = load(ROOT / "assets/tiles/tile_yard.png")
    wall = load(ROOT / "assets/tiles/wall_lime.png")
    built = {rid for rid, r in rooms.items() if r.get("built")}
    for rid, r in rooms.items():
        x0, y0, x1, y1 = room_rect(rid)
        if x0 > W or y0 > H:
            continue
        if rid in built:
            if r.get("outdoor"):
                fl = feather(tile_fill((x1 - x0, y1 - y0), yard, 192, 144), 6)
                img.alpha_composite(fl, (x0, y0))
                d.text((x0 + 8, y0 + 5), r["name"], font=F(14), fill=INK + (190,))
            else:
                fl = tile_fill((x1 - x0, y1 - y0), brick, 192, 144)
                fa = np.array(fl).astype(float)
                fa[..., :3] = fa[..., :3] * 0.5 + np.array([226, 220, 206]) * 0.5
                fl = Image.fromarray(fa.clip(0, 255).astype(np.uint8))
                img.alpha_composite(fl, (x0, y0))
                wl = tile_fill((x1 - x0, WALL), wall, 160, 160)
                wl = Image.fromarray((np.array(wl).astype(float) * [0.93, 0.92, 0.9, 1]).astype(np.uint8))
                img.alpha_composite(wl, (x0, y0 - WALL))
                # beam on top of the wall, ink frame around the floor
                d.rectangle((x0 - 2, y0 - WALL - 4, x1 + 2, y0 - WALL), fill=(92, 74, 58, 255))
                jitter_line(d, (x0 - 2, y0 - WALL - 4), (x1 + 2, y0 - WALL - 4), 2, seed=hash(rid) % 99)
                jitter_line(d, (x0, y0), (x1, y0), 1, color=INK + (150,), seed=2)
                for a, b in [((x0, y0 - WALL), (x0, y1)), ((x1, y0 - WALL), (x1, y1))]:
                    jitter_line(d, a, b, 3, seed=hash(rid + "s") % 99)
                jitter_line(d, (x0, y1), (x1, y1), 2, color=INK + (170,), seed=5)
                labels.append((x0 + 8, y0 - WALL + 7, r["name"]))
        else:
            # unbuilt: blank paper, faint pencil hatch, dashed ink outline, name + cost
            hatch = Image.new("RGBA", (x1 - x0, y1 - y0))
            hd = ImageDraw.Draw(hatch)
            for k in range(-(y1 - y0), x1 - x0, 16):
                hd.line([(k, y1 - y0), (k + (y1 - y0), 0)], fill=INK + (18,), width=1)
            img.alpha_composite(hatch, (x0, y0))
            c = (120, 110, 98, 200)
            dashed(d, (x0, y0), (x1, y0), c); dashed(d, (x1, y0), (x1, y1), c)
            dashed(d, (x1, y1), (x0, y1), c); dashed(d, (x0, y1), (x0, y0), c)
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            d.text((cx, cy - 10), r["name"], font=F(18), fill=(110, 100, 88, 230), anchor="mm")
            d.text((cx, cy + 14), f"加盖 {r['build_cost']} 文", font=F(13), fill=(150, 108, 70, 230), anchor="mm")
    # draw order: everything that stands, sorted by its foot y
    drawables = []
    for o in objects:
        t = objtypes[o["type"]]
        x0, y0, _, _ = room_rect(o["room"])
        rx, ry = x0 + o["x"] * CW, y0 + o["y"] * CH
        rw, rh = t["w"] * CW, t["h"] * CH
        p = ROOT / f"assets/props/{o['type']}.png"
        if not p.exists():
            continue
        drawables.append((ry + rh, "obj", (o, rx, ry, rw, rh, p)))
    for m in messes:
        drawables.append((cell_center(m[0], m[1], m[2])[1] - 30, "mess", m))
    for c in collectibles:
        drawables.append((cell_center(c[0], c[1], c[2])[1] - 20, "col", c))
    for pe in people:
        drawables.append((pe["at"][1], "person", pe))
    drawables.sort(key=lambda e: e[0])
    plates = []
    for _, kind, data in drawables:
        if kind == "obj":
            o, rx, ry, rw, rh, p = data
            im = trim(load(p))
            k = min(rw * 0.9 / im.width, (rh + 20) / im.height)
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            img.alpha_composite(im, (round(rx + (rw - im.width) / 2), round(ry + rh - im.height + 4)))
        elif kind == "mess":
            rid, cx, cy, typ = data
            im = trim(load(ROOT / f"assets/props/{typ}.png"))
            im = im.resize((46, round(im.height * 46 / im.width)), Image.LANCZOS)
            x, y = cell_center(rid, cx, cy)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height / 2)))
        elif kind == "col":
            rid, cx, cy, typ = data
            x, y = cell_center(rid, cx, cy)
            d.ellipse((x - 18, y - 11, x + 18, y + 11), fill=(248, 243, 228, 255))
            # 藤黄 dotted ring = "something to pick up"
            for i in range(16):
                a0 = i * 22.5
                d.arc((x - 19, y - 12, x + 19, y + 12), a0, a0 + 11, fill=(200, 150, 40, 255), width=3)
            im = trim(load(ROOT / f"assets/props/{typ}.png"))
            im = im.resize((26, round(im.height * 26 / im.width)), Image.LANCZOS)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height / 2 - 2)))
            d.line([(x + 14, y - 16), (x + 14, y - 8)], fill=(255, 250, 230, 255), width=1)
            d.line([(x + 10, y - 12), (x + 18, y - 12)], fill=(255, 250, 230, 255), width=1)
        else:
            pe = data
            x, y = pe["at"]
            fig = pe["img"]
            if pe.get("ill"):
                arr = np.array(fig).astype(float)
                g = arr[..., :3].mean(axis=-1, keepdims=True)
                arr[..., :3] = arr[..., :3] * 0.45 + g * 0.55
                arr[..., :3] = arr[..., :3] * 0.85 + np.array([150, 160, 150]) * 0.15
                fig = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
            if pe.get("flip"):
                fig = fig.transpose(Image.FLIP_LEFT_RIGHT)
            # soft ink contact shadow
            sh = Image.new("RGBA", (60, 20))
            ImageDraw.Draw(sh).ellipse((10, 6, 50, 15), fill=INK + (60,))
            img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(2)), (round(x - 30), round(y - 11)))
            if pe.get("selected"):
                rnd = random.Random(7)
                for i in range(14):
                    a0 = i * 26 + rnd.uniform(-4, 4)
                    d.arc((x - 24, y - 9, x + 24, y + 9), a0, a0 + 21, fill=ZHU + (235,), width=3)
            img.alpha_composite(fig, (round(x - fig.width / 2), round(y - fig.height + 2)))
            plates.append((x, y - fig.height, pe))
    for lx, ly, name in labels:
        d.text((lx, ly), name, font=F(15, True), fill=INK + (235,), stroke_width=3, stroke_fill=(232, 226, 212, 230))
    # plates last, above everything in the house
    for x, top, pe in plates:
        if pe.get("selected"):
            w = 150
            px0, py0 = x - w / 2, top - 46
            d.rectangle((px0, py0, px0 + w, py0 + 38), fill=(246, 241, 230, 240), outline=INK + (200,), width=1)
            d.rectangle((px0, py0, px0 + 4, py0 + 38), fill=ZHU + (255,))
            d.text((x + 2, py0 + 11), pe["name"], font=F(13, True), fill=INK, anchor="mm")
            d.text((x + 2, py0 + 27), pe["doing"], font=F(11), fill=INK + (220,), anchor="mm")
            if pe.get("progress") is not None:
                d.rectangle((px0 + 6, py0 + 35, px0 + 6 + (w - 12) * pe["progress"], py0 + 37), fill=ZHU + (255,))
        else:
            d.text((x, top - 10), pe["name"], font=F(12, True), fill=INK + (210,), anchor="mm",
                   stroke_width=2, stroke_fill=(246, 241, 230, 200))
        if pe.get("ill"):
            ic = trim(load(ROOT / "assets/props/icon_ill.png"))
            ic = ic.resize((26, round(ic.height * 26 / ic.width)), Image.LANCZOS)
            ix = x - 75 - 22 if pe.get("selected") else x - 13
            yy = top - 42 if pe.get("selected") else top - 40
            d.ellipse((ix - 4, yy - 3, ix + 30, yy + ic.height + 3), fill=(246, 241, 230, 255), outline=ZHU + (220,), width=2)
            img.alpha_composite(ic, (round(ix), round(yy)))
        if pe.get("asleep"):
            d.text((x + 18, top + 8), "睡", font=F(13, True), fill=INK + (200,), anchor="mm")
    if night:
        arr = np.array(img).astype(float)
        arr[..., :3] *= np.array([0.45, 0.5, 0.7])
        img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    return img


def glow(img, centers):
    """Warm lamp light added after the night tint (oil lamp, stove, altar candles)."""
    arr = np.array(img).astype(float)
    yy, xx = np.mgrid[0:H, 0:W]
    for (cx, cy, r, k) in centers:
        dist = np.sqrt((xx - cx) ** 2 + ((yy - cy) * 1.25) ** 2)
        f = np.clip(1 - dist / r, 0, 1) ** 1.6 * k
        arr[..., 0] = arr[..., 0] * (1 + 1.05 * f) + 26 * f
        arr[..., 1] = arr[..., 1] * (1 + 0.85 * f) + 16 * f
        arr[..., 2] = arr[..., 2] * (1 + 0.35 * f)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


# ---------------------------------------------------------------- UI
def bar(img, sel, money, stock, family_dot=False):
    d = ImageDraw.Draw(img, "RGBA")
    y0 = H - BAR
    strip = paper((W, BAR), 11)
    strip = Image.fromarray((np.array(strip).astype(float) * [1.03, 1.02, 1.0, 1]).clip(0, 255).astype(np.uint8))
    img.alpha_composite(strip, (0, y0))
    d.rectangle((0, y0, W, y0 + 5), fill=(94, 112, 120, 255))  # 花青绫边
    jitter_line(d, (0, y0 + 5), (W, y0 + 5), 2, seed=9, step=14)
    # avatar
    ax, ay = 22, y0 + 18
    av = sel["face"].copy()
    m = Image.new("L", av.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, av.width - 1, av.height - 1), fill=255)
    bgc = Image.new("RGBA", av.size, (246, 241, 230, 255))
    bgc.alpha_composite(av)
    bgc.putalpha(m)
    img.alpha_composite(bgc, (ax, ay))
    d.ellipse((ax - 2, ay - 2, ax + av.width + 1, ay + av.height + 1), outline=ZHU + (255,), width=2)
    x = ax + av.width + 14
    d.text((x, y0 + 22), sel["name"], font=F(20, True), fill=INK)
    d.text((x, y0 + 52), sel["line"], font=F(14), fill=INK + (200,))
    x += 150
    d.text((x, y0 + 22), "在做", font=F(12), fill=(130, 118, 104))
    d.text((x, y0 + 40), sel["doing_bar"], font=F(15), fill=INK)
    x += 270
    d.text((x, y0 + 22), "身上", font=F(12), fill=(130, 118, 104))
    sx = x
    for word, bad in sel["status"]:
        col = ZHU if bad else INK
        tw = d.textlength(word, font=F(15))
        if bad:
            d.rectangle((sx - 3, y0 + 39, sx + tw + 3, y0 + 61), outline=ZHU + (255,), width=1)
        d.text((sx, y0 + 40), word, font=F(15), fill=col)
        sx += tw + 14
    # money: coin + amount
    mx = 830
    coin = trim(load(ROOT / "assets/props/col_coins.png")).resize((30, 28), Image.LANCZOS)
    img.alpha_composite(coin, (mx, y0 + 22))
    d.text((mx + 36, y0 + 21), f"{money} 文", font=F(20, True), fill=INK)
    d.text((mx + 36, y0 + 52), f"存粮 {stock}", font=F(14), fill=INK + (200,))
    # bar buttons
    bx = 975
    for i, name in enumerate(["家谱", "集市", "账房", "摆设", "设置"]):
        x0 = bx + i * 59
        d.rectangle((x0, y0 + 26, x0 + 50, y0 + 70), fill=(244, 238, 226, 255), outline=INK + (210,), width=2)
        d.text((x0 + 25, y0 + 48), name, font=F(15, True), fill=INK, anchor="mm")
        if name == "家谱" and family_dot:
            d.ellipse((x0 + 42, y0 + 20, x0 + 54, y0 + 32), fill=ZHU + (255,))
    # praise / scold seals, top-left
    for i, (t, col) in enumerate([("罚", INK), ("赏", ZHU)]):
        cx, cy = 34 + i * 52, 34
        d.ellipse((cx - 20, cy - 20, cx + 20, cy + 20), fill=(246, 241, 230, 235), outline=col + (255,), width=3)
        d.text((cx, cy), t, font=F(20, True), fill=col, anchor="mm")


def toast(img, text):
    d = ImageDraw.Draw(img, "RGBA")
    tw = d.textlength(text, font=F(15))
    x0, y0 = W / 2 - tw / 2 - 16, 14
    d.rectangle((x0, y0, x0 + tw + 32, y0 + 32), fill=(246, 241, 230, 245), outline=INK + (200,), width=1)
    d.rectangle((x0, y0, x0 + 4, y0 + 32), fill=ZHU + (255,))
    d.text((W / 2 + 2, y0 + 16), text, font=F(15), fill=INK, anchor="mm")


def shop_panel(img, money):
    shade = Image.new("RGBA", (W, H - BAR), (20, 22, 30, 110))
    img.alpha_composite(shade, (0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    pw, ph = 560, 440
    x0, y0 = (W - pw) // 2, (H - BAR - ph) // 2 + 4
    card = paper((pw, ph), 21)
    img.alpha_composite(card, (x0, y0))
    d.rectangle((x0, y0, x0 + pw, y0 + ph), outline=(94, 112, 120, 255), width=6)  # 绫边
    d.rectangle((x0 + 8, y0 + 8, x0 + pw - 8, y0 + ph - 8), outline=INK + (200,), width=1)
    d.text((x0 + 28, y0 + 22), "集市", font=F(24, True), fill=INK)
    d.text((x0 + pw - 28, y0 + 34), f"手头 {money} 文", font=F(15), fill=INK + (210,), anchor="rm")
    # tabs
    tx = x0 + 28
    for i, t in enumerate(["货品", "家里存的"]):
        w = d.textlength(t, font=F(15)) + 20
        if i == 0:
            d.rectangle((tx, y0 + 64, tx + w, y0 + 90), fill=(244, 238, 226, 255), outline=INK + (220,), width=2)
        d.text((tx + w / 2, y0 + 77), t, font=F(15, i == 0), fill=INK if i == 0 else (120, 110, 98), anchor="mm")
        tx += w + 10
    jitter_line(d, (x0 + 24, y0 + 96), (x0 + pw - 24, y0 + 96), 1, color=INK + (120,), seed=4)
    rows = [("粮食", None), ("一袋米面", 24), ("药铺", None), ("老姜红枣丸", 30), ("青黛药膏", 36),
            ("零嘴", None), ("糖人", 12), ("桂花糕", 18)]
    y = y0 + 108
    for name, price in rows:
        if price is None:
            d.text((x0 + 30, y), name, font=F(13), fill=(150, 108, 70))
            y += 24
            continue
        hi = name == "老姜红枣丸"
        if hi:
            d.rectangle((x0 + 22, y - 6, x0 + pw - 22, y + 30), fill=(238, 214, 200, 255), outline=ZHU + (200,))
        d.text((x0 + 44, y), name, font=F(17, hi), fill=INK)
        if hi:
            d.text((x0 + 44 + d.textlength(name, font=F(17, True)) + 10, y + 3), "治伤风", font=F(13), fill=ZHU)
        d.text((x0 + 360, y), f"{price} 文", font=F(16), fill=INK)
        ok = money >= price
        bx = x0 + pw - 110
        d.rectangle((bx, y - 3, bx + 80, y + 25), fill=(244, 238, 226, 255) if ok else (226, 221, 211, 255),
                    outline=(INK + (220,)) if ok else (160, 152, 140, 255), width=2 if ok else 1)
        d.text((bx + 40, y + 11), "买" if ok else "钱不够", font=F(14, ok), fill=INK if ok else (140, 130, 118), anchor="mm")
        y += 38
    # close
    d.rectangle((x0 + pw - 98, y0 + ph - 50, x0 + pw - 28, y0 + ph - 20), fill=(244, 238, 226, 255), outline=INK + (220,), width=2)
    d.text((x0 + pw - 63, y0 + ph - 35), "关闭", font=F(15, True), fill=INK, anchor="mm")
    d.text((x0 + 30, y0 + ph - 35), "Esc 也能关", font=F(12), fill=(140, 130, 118), anchor="lm")


def face_of(fig, size=56):
    h = fig.height
    head = fig.crop((0, 0, fig.width, int(h * 0.3)))
    head = trim(head)
    s = max(head.width, head.height)
    sq = Image.new("RGBA", (s, s))
    sq.alpha_composite(head, ((s - head.width) // 2, (s - head.height) // 2 + s // 10))
    return sq.resize((size, size), Image.LANCZOS)


def main():
    out = ROOT / "design/targets"
    out.mkdir(parents=True, exist_ok=True)
    father = rig_figure("father", "walk", 0.15, 78)
    father_hi = rig_figure("father", None, 0, 300)
    mother = rig_figure("mother", None, 0, 74)
    mother_hi = rig_figure("mother", None, 0, 300)
    child = fit_h(clean_green(load(ROOT / "assets/chars/fam_child.png")), 54)
    grandma = fit_h(clean_green(load(ROOT / "assets/chars/fam_grandma.png")), 66)

    # ---------- 01 daytime: hall + yard, the selected father is about to clear a mess
    hx, hy = cell_center("yard", 9, 3)
    people = [
        dict(name="程大柱", img=father, at=(hx - 30, hy + 14), selected=True,
             doing="拿铁锹铲掉院里的鸡粪", progress=0.35),
        dict(name="柳晚晴", img=mother, at=cell_center("hall", 2, 3), doing="就着亮光缝补旧衣裳"),
        dict(name="程小满", img=child, at=cell_center("yard", 14, 6), flip=False, doing="蹲在院里看蚂蚁搬家"),
        dict(name="苏素纨", img=grandma, at=cell_center("hall", 0, 5)[0:1] + (cell_center("hall", 0, 5)[1] + 8,), doing="坐在矮凳上剥豆子"),
    ]
    messes = [("yard", 9, 3, "mess_droppings"), ("hall", 7, 4, "mess_dirt"), ("yard", 3, 5, "mess_dirt")]
    cols = [("yard", 15, 1, "col_coins")]
    img = house(False, people, messes, cols)
    sel = dict(name="程大柱", line="34 岁 · 佃户", face=face_of(father_hi),
               doing_bar="拿铁锹铲掉院里的鸡粪 · 35%", status=[("半饱", False), ("抖擞", False), ("舒心", False), ("康健", False)])
    bar(img, sel, 200, 6)
    toast(img, "捡到鸡窝外的鸡蛋，卖了 6 文")
    img.convert("RGB").save(out / "01_晌午院子.png")

    # ---------- 02 night: mother has a chill in the bedroom; 集市 open, the medicine costs more than the family has
    people = [
        dict(name="柳晚晴", img=mother, at=cell_center("bedroom", 1, 3), selected=True, ill=True,
             doing="捂着嘴咳得直不起腰", progress=None),
        dict(name="程大柱", img=father_hi.resize((father.width, father.height)) if False else rig_figure("father", None, 0, 78),
             at=cell_center("hall", 6, 1), flip=True, doing="拨亮油灯的灯芯"),
        dict(name="程小满", img=child, at=cell_center("bedroom", 4, 2), asleep=True, doing="睡下"),
    ]
    img = house(True, people, [("hall", 7, 4, "mess_dirt")], [], seed=3)
    ax0, ay0, _, _ = room_rect("hall")
    img = glow(img, [(ax0 + 9 * CW, ay0 - 6, 150, 0.9), (ax0 + 6 * CW + 24, ay0 + 40, 120, 0.7),
                     (room_rect("bedroom")[0] + 70, room_rect("bedroom")[1] + 90, 150, 0.75)])
    selm = dict(name="柳晚晴", line="31 岁 · 绣娘", face=face_of(mother_hi),
                doing_bar="捂着嘴咳得直不起腰", status=[("半饱", False), ("发蔫", False), ("有点闷", False), ("伤风", True), ("虚弱", True)])
    bar(img, selm, 26, 0)
    shop_panel(img, 26)
    img.convert("RGB").save(out / "02_夜里伤风.png")

    # ---------- the same night without the panel, for the readability check
    img2 = house(True, people, [("hall", 7, 4, "mess_dirt")], [], seed=3)
    img2 = glow(img2, [(ax0 + 9 * CW, ay0 - 6, 150, 0.9), (ax0 + 6 * CW + 24, ay0 + 40, 120, 0.7),
                       (room_rect("bedroom")[0] + 70, room_rect("bedroom")[1] + 90, 150, 0.75)])
    bar(img2, selm, 26, 0)
    img2.convert("RGB").save(out / "02b_夜里伤风_无面板.png")
    print("ok")


if __name__ == "__main__":
    main()
