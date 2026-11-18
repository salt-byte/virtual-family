"""Compose 起家 target images (style A: warm hand-drawn cartoon) at the real 1280x720 viewport.
Geometry follows game/kernel/view (CELL 48x36, WALL 30, BOTTOM_BAR 96, scale 1, rooms.json positions).
Reads pipeline outputs in assets/chars, assets/props, assets/tiles (not committed) and the fonts in .cache/
(ZCOOL KuaiLe, Noto Sans SC; both SIL OFL 1.1, not committed)."""
import json, math, random, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/scripts"))
import cutout_lib as cl  # noqa

W, H = 1280, 720
BAR = 96
CW, CH = 48, 36
WALL = 30
CAM = (40, 46)
LINE = (74, 52, 36)          # #4A3424 outline brown
WOOD = (138, 90, 54)         # #8A5A36 frame wood
CREAM = (255, 244, 223)      # #FFF4DF panels
TOMATO = (229, 83, 60)       # #E5533C selection / trouble
SKY = (79, 179, 232)         # #4FB3E8 pickups
BTN = (255, 227, 176)        # #FFE3B0 buttons
GRASS = (196, 214, 150)      # outside the compound
PLOT = (246, 236, 212)       # unbuilt plot
KUAILE = ROOT / ".cache/ZCOOLKuaiLe-Regular.ttf"
NOTO = ROOT / ".cache/NotoSansSC-Regular.otf"


def T(size):  # titles, names, buttons
    return ImageFont.truetype(str(KUAILE), size)


def B(size):  # body text
    return ImageFont.truetype(str(NOTO), size)


rooms = {r["id"]: r for r in json.load(open(ROOT / "game/packs/qijia/rooms.json"))}
objtypes = {o["id"]: o for o in json.load(open(ROOT / "game/packs/qijia/objects.json"))}
pack = json.load(open(ROOT / "game/packs/qijia/pack.json"))
objects = [dict(type=o["type"], room=o["room"], x=o["x"], y=o["y"]) for o in pack["start_objects"]]
for rid, r in rooms.items():
    for p in r.get("props", []):
        objects.append(dict(type=p["type"], room=rid, x=p["x"], y=p["y"]))

FLOOR = {"hall": "a_floor_hall", "bedroom": "a_floor_bed", "kitchen": "a_floor_earth", "woodshed": "a_floor_earth",
         "west_room": "a_floor_bed", "study": "a_floor_bed", "side": "a_floor_bed"}


def room_rect(rid):
    r = rooms[rid]
    x, y = CAM[0] + r["x"] * CW, CAM[1] + r["y"] * CH
    return (x, y, x + r["w"] * CW, y + r["h"] * CH)


def cell_center(rid, cx, cy):
    x0, y0, _, _ = room_rect(rid)
    return (x0 + cx * CW + CW / 2, y0 + cy * CH + CH / 2)


def load(p):
    return Image.open(p).convert("RGBA")


def trim(img):
    bb = img.getbbox()
    return img.crop(bb) if bb else img


def fit_h(img, h):
    img = trim(img)
    return img.resize((max(1, round(img.width * h / img.height)), h), Image.LANCZOS)


def tile_fill(size, tile, tw, th, soften=0.0):
    t = tile.resize((tw, th), Image.LANCZOS)
    out = Image.new("RGBA", size)
    for yy in range(0, size[1], th):
        for xx in range(0, size[0], tw):
            out.paste(t, (xx, yy))
    if soften:
        a = np.array(out).astype(float)
        a[..., :3] = a[..., :3] * (1 - soften) + np.array(CREAM) * soften
        out = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    return out


def noise_fill(size, color, seed, amp=5):
    rnd = np.random.default_rng(seed)
    base = np.ones((size[1], size[0], 3)) * np.array(color)
    n = rnd.normal(0, 1, (size[1] // 6 + 1, size[0] // 6 + 1))
    n = np.kron(n, np.ones((6, 6)))[: size[1], : size[0]]
    base += (n * amp)[..., None]
    return Image.fromarray(base.clip(0, 255).astype(np.uint8)).convert("RGBA")


def dashed(d, a, b, color, dash=10, gap=7, width=3):
    L = math.dist(a, b)
    ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    s = 0
    while s < L:
        e = min(L, s + dash)
        d.line([(a[0] + ux * s, a[1] + uy * s), (a[0] + ux * e, a[1] + uy * e)], fill=color, width=width)
        s += dash + gap


def clean_green(img):
    a = np.array(img).astype(np.int16)
    spill = (a[..., 1] - np.maximum(a[..., 0], a[..., 2])) > 40
    a[..., 3] = np.where(spill, 0, a[..., 3])
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def rig_figure(name, anim=None, t=0.0, height=90, flip=False):
    rp = ROOT / f"assets/chars/{name}/{name}.rig.json"
    rig = cl.load_json(rp)
    pose = {}
    if anim:
        anims = cl.load_json(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/references/anims.humanoid_side.json")["animations"]
        pose = cl.pose_at(rig, anims[anim], t)
    lo, hi = cl.bounds(rig, [pose])
    canvas = (int(hi[0] - lo[0]) + 8, int(hi[1] - lo[1]) + 8)
    img = fit_h(cl.render(rig, rp.parent, pose, canvas, (4 - lo[0], 4 - lo[1]), 1.0), height)
    return img.transpose(Image.FLIP_LEFT_RIGHT) if flip else img


def shadow(img, x, y, w=44):
    w = int(w)
    sh = Image.new("RGBA", (w + 20, 22))
    ImageDraw.Draw(sh).ellipse((10, 6, w + 10, 16), fill=LINE + (70,))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(2)), (round(x - (w + 20) / 2), round(y - 11)))


# ---------------------------------------------------------------- house layer
def house(night=False, people=(), messes=(), collectibles=()):
    img = noise_fill((W, H), GRASS, 5)
    d = ImageDraw.Draw(img)
    labels = []
    wall = load(ROOT / "assets/tiles/a_wall.png")
    for rid, r in rooms.items():
        x0, y0, x1, y1 = room_rect(rid)
        if x0 > W or y0 > H:
            continue
        if r.get("built"):
            if r.get("outdoor"):
                fl = tile_fill((x1 - x0, y1 - y0), load(ROOT / "assets/tiles/a_yard.png"), 192, 144, 0.25)
                m = Image.new("L", fl.size, 0)
                ImageDraw.Draw(m).rounded_rectangle((0, 0, fl.width - 1, fl.height - 1), 14, fill=255)
                fl.putalpha(m)
                img.alpha_composite(fl, (x0, y0))
                d.rounded_rectangle((x0, y0, x1, y1), 14, outline=(160, 120, 80), width=2)
                labels.append((x0 + 10, y0 + 6, r["name"], False))
            else:
                fl = tile_fill((x1 - x0, y1 - y0), load(ROOT / f"assets/tiles/{FLOOR[rid]}.png"), 192, 144, 0.2)
                img.alpha_composite(fl, (x0, y0))
                img.alpha_composite(tile_fill((x1 - x0, WALL), wall, 160, 160), (x0, y0 - WALL))
                d.rectangle((x0 - 4, y0 - WALL - 8, x1 + 4, y0 - WALL), fill=WOOD, outline=LINE, width=2)
                d.line([(x0, y0), (x1, y0)], fill=LINE + (255,), width=2)
                d.rectangle((x0 - 4, y0 - WALL - 8, x1 + 4, y1 + 3), outline=LINE, width=3)
                labels.append((x0 + 10, y0 - WALL + 5, r["name"], True))
        else:
            d.rounded_rectangle((x0, y0, x1, y1), 12, fill=PLOT)
            c = (150, 116, 84)
            dashed(d, (x0, y0), (x1, y0), c); dashed(d, (x1, y0), (x1, y1), c)
            dashed(d, (x1, y1), (x0, y1), c); dashed(d, (x0, y1), (x0, y0), c)
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            d.text((cx, cy - 12), r["name"], font=T(22), fill=(130, 100, 72), anchor="mm")
            tw = d.textlength(f"加盖 {r['build_cost']} 文", font=B(13)) + 22
            d.rounded_rectangle((cx - tw / 2, cy + 6, cx + tw / 2, cy + 30), 12, fill=BTN, outline=LINE, width=2)
            d.text((cx, cy + 18), f"加盖 {r['build_cost']} 文", font=B(13), fill=LINE, anchor="mm")
    draw = []
    for o in objects:
        t = objtypes[o["type"]]
        x0, y0, _, _ = room_rect(o["room"])
        rx, ry, rw, rh = x0 + o["x"] * CW, y0 + o["y"] * CH, t["w"] * CW, t["h"] * CH
        p = ROOT / f"assets/props/a_{o['type']}.png"
        if p.exists():
            draw.append((ry + rh, "obj", (rx, ry, rw, rh, p)))
    for m in messes:
        draw.append((cell_center(m[0], m[1], m[2])[1] - 30, "mess", m))
    for c in collectibles:
        draw.append((cell_center(c[0], c[1], c[2])[1] - 20, "col", c))
    for pe in people:
        draw.append((pe["at"][1], "person", pe))
    draw.sort(key=lambda e: e[0])
    tops = []
    for _, kind, data in draw:
        if kind == "obj":
            rx, ry, rw, rh, p = data
            im = trim(load(p))
            k = min(rw * 0.9 / im.width, (rh + 24) / im.height)
            im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            shadow(img, rx + rw / 2, ry + rh - 2, im.width * 0.8)
            img.alpha_composite(im, (round(rx + (rw - im.width) / 2), round(ry + rh - im.height + 2)))
        elif kind == "mess":
            rid, cx, cy, typ = data
            im = trim(load(ROOT / f"assets/props/a_{typ}.png"))
            im = im.resize((54, round(im.height * 54 / im.width)), Image.LANCZOS)
            x, y = cell_center(rid, cx, cy)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height / 2)))
        elif kind == "col":
            rid, cx, cy, typ = data
            x, y = cell_center(rid, cx, cy)
            d.ellipse((x - 20, y - 12, x + 20, y + 12), fill=(235, 247, 255), outline=SKY, width=3)
            im = trim(load(ROOT / f"assets/props/a_{typ}.png"))
            im = im.resize((28, round(im.height * 28 / im.width)), Image.LANCZOS)
            img.alpha_composite(im, (round(x - im.width / 2), round(y - im.height / 2 - 4)))
            for sx, sy, s in [(x + 18, y - 18, 5), (x - 20, y - 14, 3)]:
                d.polygon([(sx, sy - s), (sx + s * 0.35, sy), (sx, sy + s), (sx - s * 0.35, sy)], fill=SKY)
                d.polygon([(sx - s, sy), (sx, sy + s * 0.35), (sx + s, sy), (sx, sy - s * 0.35)], fill=SKY)
        else:
            pe = data
            x, y = pe["at"]
            fig = pe["img"]
            if pe.get("ill"):
                a = np.array(fig).astype(float)
                g = a[..., :3].mean(axis=-1, keepdims=True)
                a[..., :3] = a[..., :3] * 0.55 + g * 0.45
                a[..., :3] = a[..., :3] * 0.85 + np.array([150, 175, 150]) * 0.15
                fig = Image.fromarray(a.clip(0, 255).astype(np.uint8))
            shadow(img, x, y)
            if pe.get("selected"):
                d.ellipse((x - 27, y - 10, x + 27, y + 10), outline=TOMATO, width=4)
                d.polygon([(x - 7, y - fig.height - 14), (x + 7, y - fig.height - 14), (x, y - fig.height - 4)], fill=TOMATO)
            img.alpha_composite(fig, (round(x - fig.width / 2), round(y - fig.height + 2)))
            tops.append((x, y - fig.height, pe))
    for lx, ly, name, indoor in labels:
        d.text((lx, ly), name, font=T(17), fill=LINE if not indoor else (255, 248, 232),
               stroke_width=0 if not indoor else 2, stroke_fill=LINE)
    for x, top, pe in tops:
        if pe.get("selected"):
            w = 168
            px0, py0 = x - w / 2, top - 62
            d.rounded_rectangle((px0, py0, px0 + w, py0 + 42), 12, fill=CREAM, outline=LINE, width=2)
            d.text((x, py0 + 12), pe["name"], font=T(16), fill=LINE, anchor="mm")
            d.text((x, py0 + 29), pe["doing"], font=B(11), fill=LINE, anchor="mm")
            if pe.get("progress") is not None:
                d.rounded_rectangle((px0 + 10, py0 + 37, px0 + w - 10, py0 + 41), 2, fill=(230, 214, 186))
                d.rounded_rectangle((px0 + 10, py0 + 37, px0 + 10 + (w - 20) * pe["progress"], py0 + 41), 2, fill=TOMATO)
        else:
            d.text((x, top - 10), pe["name"], font=T(14), fill=LINE, anchor="mm", stroke_width=3, stroke_fill=CREAM)
        if pe.get("ill"):
            ic = fit_h(load(ROOT / "assets/props/a_icon_ill.png"), 22)
            ix = x - 84 - 36 if pe.get("selected") else x - 16
            iy = top - 56 if pe.get("selected") else top - 44
            d.ellipse((ix - 2, iy - 4, ix + 34, iy + 30), fill=CREAM, outline=TOMATO, width=3)
            img.alpha_composite(ic, (round(ix + 16 - ic.width / 2), round(iy + 2)))
        if pe.get("asleep"):
            for i, s in enumerate((12, 15, 18)):
                d.text((x + 16 + i * 9, top + 6 - i * 10), "z", font=T(s), fill=(90, 110, 170), anchor="mm",
                       stroke_width=2, stroke_fill=CREAM)
    if night:
        a = np.array(img).astype(float)
        a[..., :3] *= np.array([0.58, 0.62, 0.82])  # proposed softer NIGHT_COLOR for style A
        img = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    return img


def glow(img, centers):
    a = np.array(img).astype(float)
    yy, xx = np.mgrid[0:H, 0:W]
    for cx, cy, r, k in centers:
        f = np.clip(1 - np.sqrt((xx - cx) ** 2 + ((yy - cy) * 1.25) ** 2) / r, 0, 1) ** 1.6 * k
        a[..., 0] = a[..., 0] * (1 + 1.1 * f) + 30 * f
        a[..., 1] = a[..., 1] * (1 + 0.85 * f) + 18 * f
        a[..., 2] = a[..., 2] * (1 + 0.3 * f)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


# ---------------------------------------------------------------- UI
def button(d, box, text, size=17, on=True, alert=False):
    x0, y0, x1, y1 = box
    d.rounded_rectangle((x0, y0 + 3, x1, y1 + 3), 12, fill=(196, 150, 104))
    d.rounded_rectangle(box, 12, fill=BTN if on else (232, 224, 210), outline=LINE if on else (170, 158, 140), width=2)
    d.text(((x0 + x1) / 2, (y0 + y1) / 2), text, font=T(size), fill=LINE if on else (150, 138, 120), anchor="mm")
    if alert:
        d.ellipse((x1 - 10, y0 - 6, x1 + 4, y0 + 8), fill=TOMATO, outline=CREAM, width=2)


def bar(img, sel, money, stock):
    d = ImageDraw.Draw(img)
    y0 = H - BAR
    d.rounded_rectangle((-20, y0 - 6, W + 20, H + 20), 18, fill=WOOD)
    d.rounded_rectangle((-20, y0, W + 20, H + 20), 16, fill=CREAM)
    av = sel["face"]
    ax, ay = 20, y0 + 16
    m = Image.new("L", av.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, av.width - 1, av.height - 1), fill=255)
    bg = Image.new("RGBA", av.size, (255, 230, 190, 255))
    bg.alpha_composite(av)
    bg.putalpha(m)
    img.alpha_composite(bg, (ax, ay))
    d.ellipse((ax - 3, ay - 3, ax + av.width + 2, ay + av.height + 2), outline=TOMATO, width=3)
    x = ax + av.width + 16
    d.text((x, y0 + 16), sel["name"], font=T(24), fill=LINE)
    d.text((x, y0 + 52), sel["line"], font=B(14), fill=LINE)
    x += 150
    d.text((x, y0 + 18), "在做", font=B(12), fill=(150, 120, 90))
    d.text((x, y0 + 40), sel["doing_bar"], font=B(15), fill=LINE)
    x += 270
    d.text((x, y0 + 18), "身上", font=B(12), fill=(150, 120, 90))
    sx = x
    for word, bad in sel["status"]:
        tw = d.textlength(word, font=B(14)) + 16
        d.rounded_rectangle((sx, y0 + 40, sx + tw, y0 + 64), 12, fill=(255, 222, 214) if bad else (240, 230, 208),
                            outline=TOMATO if bad else None, width=2)
        d.text((sx + tw / 2, y0 + 52), word, font=B(14), fill=(190, 60, 40) if bad else LINE, anchor="mm")
        sx += tw + 6
    mx = 846
    coin = trim(load(ROOT / "assets/props/a_col_coins.png")).resize((32, 30), Image.LANCZOS)
    img.alpha_composite(coin, (mx, y0 + 18))
    d.text((mx + 38, y0 + 16), f"{money} 文", font=T(24), fill=LINE)
    d.text((mx + 38, y0 + 52), f"存粮 {stock}", font=B(14), fill=LINE)
    bx = 978
    for i, name in enumerate(["家谱", "集市", "账房", "摆设", "设置"]):
        button(d, (bx + i * 59, y0 + 22, bx + i * 59 + 52, y0 + 66), name, 17)
    for i, (t, col) in enumerate([("罚", WOOD), ("赏", TOMATO)]):
        cx, cy = 34 + i * 54, 34
        d.ellipse((cx - 22, cy - 19, cx + 22, cy + 25), fill=(196, 150, 104))
        d.ellipse((cx - 22, cy - 22, cx + 22, cy + 22), fill=BTN, outline=col, width=3)
        d.text((cx, cy), t, font=T(22), fill=col, anchor="mm")


def toast(img, text):
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=B(15))
    x0, y0 = W / 2 - tw / 2 - 22, 12
    d.rounded_rectangle((x0, y0 + 3, x0 + tw + 44, y0 + 39), 18, fill=(196, 150, 104))
    d.rounded_rectangle((x0, y0, x0 + tw + 44, y0 + 36), 18, fill=CREAM, outline=LINE, width=2)
    d.ellipse((x0 + 10, y0 + 12, x0 + 22, y0 + 24), fill=SKY)
    d.text((W / 2 + 6, y0 + 18), text, font=B(15), fill=LINE, anchor="mm")


def shop_panel(img, money):
    img.alpha_composite(Image.new("RGBA", (W, H - BAR), (40, 30, 30, 110)), (0, 0))
    d = ImageDraw.Draw(img)
    pw, ph = 560, 446
    x0, y0 = (W - pw) // 2, (H - BAR - ph) // 2 + 2
    d.rounded_rectangle((x0, y0 + 6, x0 + pw, y0 + ph + 6), 22, fill=(120, 80, 50))
    d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), 22, fill=WOOD)
    d.rounded_rectangle((x0 + 8, y0 + 8, x0 + pw - 8, y0 + ph - 8), 16, fill=CREAM)
    d.text((x0 + 30, y0 + 22), "集市", font=T(30), fill=LINE)
    d.text((x0 + pw - 30, y0 + 38), f"手头 {money} 文", font=B(15), fill=LINE, anchor="rm")
    tx = x0 + 30
    for i, t in enumerate(["货品", "家里存的"]):
        w = d.textlength(t, font=T(17)) + 28
        d.rounded_rectangle((tx, y0 + 66, tx + w, y0 + 96), 14, fill=BTN if i == 0 else (240, 230, 208),
                            outline=LINE if i == 0 else None, width=2)
        d.text((tx + w / 2, y0 + 81), t, font=T(17), fill=LINE if i == 0 else (150, 130, 105), anchor="mm")
        tx += w + 10
    rows = [("粮食", None), ("一袋米面", 24), ("药铺", None), ("老姜红枣丸", 30), ("青黛药膏", 36),
            ("零嘴", None), ("糖人", 12), ("桂花糕", 18)]
    y = y0 + 112
    for name, price in rows:
        if price is None:
            d.text((x0 + 32, y), name, font=B(13), fill=(170, 120, 70))
            y += 24
            continue
        hi = name == "老姜红枣丸"
        if hi:
            d.rounded_rectangle((x0 + 22, y - 6, x0 + pw - 22, y + 30), 12, fill=(255, 226, 214), outline=TOMATO, width=2)
        d.text((x0 + 44, y), name, font=B(17), fill=LINE)
        if hi:
            d.text((x0 + 44 + d.textlength(name, font=B(17)) + 10, y + 3), "治伤风", font=B(13), fill=(190, 60, 40))
        d.text((x0 + 350, y), f"{price} 文", font=B(16), fill=LINE)
        ok = money >= price
        button(d, (x0 + pw - 120, y - 4, x0 + pw - 36, y + 24), "买" if ok else "钱不够", 15, ok)
        y += 38
    button(d, (x0 + pw - 110, y0 + ph - 56, x0 + pw - 30, y0 + ph - 22), "关闭", 17)
    d.text((x0 + 32, y0 + ph - 39), "Esc 也能关", font=B(12), fill=(160, 135, 110), anchor="lm")


def face_of(fig, size=58):
    head = trim(fig.crop((0, 0, fig.width, int(fig.height * 0.3))))
    s = max(head.width, head.height)
    sq = Image.new("RGBA", (s, s))
    sq.alpha_composite(head, ((s - head.width) // 2, (s - head.height) // 2 + s // 12))
    return sq.resize((size, size), Image.LANCZOS)


def main():
    out = ROOT / "design/targets"
    out.mkdir(parents=True, exist_ok=True)
    father_walk = rig_figure("a_father", "walk", 0.15, 90)
    father = rig_figure("a_father", None, 0, 90, flip=True)
    mother = rig_figure("a_mother", None, 0, 86)
    grandma = fit_h(clean_green(load(ROOT / "assets/chars/a_grandma.png")), 74)
    child = fit_h(clean_green(load(ROOT / "assets/chars/a_child.png")), 62)
    face_f = face_of(rig_figure("a_father", None, 0, 400))
    face_m = face_of(rig_figure("a_mother", None, 0, 400))

    hx, hy = cell_center("yard", 9, 3)
    people = [
        dict(name="程大柱", img=father_walk, at=(hx - 30, hy + 16), selected=True, doing="拿铁锹铲掉院里的鸡粪", progress=0.35),
        dict(name="柳晚晴", img=mother, at=cell_center("hall", 2, 3), doing="就着亮光缝补旧衣裳"),
        dict(name="程小满", img=child, at=cell_center("yard", 14, 6), doing="蹲在院里看蚂蚁搬家"),
        dict(name="苏素纨", img=grandma, at=(cell_center("hall", 1, 5)[0], cell_center("hall", 1, 5)[1] + 8), doing="坐在矮凳上剥豆子"),
    ]
    img = house(False, people, [("yard", 9, 3, "mess_droppings"), ("hall", 7, 4, "mess_dirt"), ("yard", 3, 5, "mess_dirt")],
                [("yard", 15, 1, "col_coins")])
    bar(img, dict(name="程大柱", line="34 岁 · 佃户", face=face_f, doing_bar="拿铁锹铲掉院里的鸡粪 · 35%",
                  status=[("半饱", False), ("抖擞", False), ("舒心", False), ("康健", False)]), 200, 6)
    toast(img, "捡到鸡窝外的鸡蛋，卖了 6 文")
    img.convert("RGB").save(out / "01_晌午院子.png")

    people = [
        dict(name="柳晚晴", img=mother, at=cell_center("bedroom", 2, 4), selected=True, ill=True, doing="捂着嘴咳得直不起腰"),
        dict(name="程大柱", img=father, at=cell_center("hall", 2, 3), doing="拨亮油灯的灯芯"),
        dict(name="程小满", img=child, at=cell_center("bedroom", 4, 2), asleep=True, doing="睡下"),
    ]
    hx0, hy0, _, _ = room_rect("hall")
    bx0, by0, _, _ = room_rect("bedroom")
    lamps = [(hx0 + 9 * CW, hy0 - 6, 150, 0.9), (hx0 + 2 * CW + 40, hy0 + 70, 120, 0.7), (bx0 + 70, by0 + 90, 150, 0.75)]
    sel = dict(name="柳晚晴", line="31 岁 · 绣娘", face=face_m, doing_bar="捂着嘴咳得直不起腰",
               status=[("半饱", False), ("发蔫", False), ("有点闷", False), ("伤风", True), ("虚弱", True)])
    for fname, panel in [("02_夜里伤风.png", True), ("02b_夜里伤风_无面板.png", False)]:
        img = glow(house(True, people, [("hall", 7, 4, "mess_dirt")], []), lamps)
        bar(img, sel, 26, 0)
        if panel:
            shop_panel(img, 26)
        img.convert("RGB").save(out / fname)
    print("ok")


if __name__ == "__main__":
    main()
