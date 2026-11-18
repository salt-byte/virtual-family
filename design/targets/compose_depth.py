"""04 立体感对比: the same close-up (hall, bedroom, a piece of courtyard) in three treatments.
现在 = compose_house flat walls; A = depth_walls tall walls; B = a rough 2:1 isometric sketch."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compose_house as ch  # noqa: E402
ct = ch.ct
ROOT = ch.ROOT

CROP = (ch.OX + 11, ch.OY - 3.4, 18, 14.5)   # map cells: x, y, w, h


def people():
    father = ct.rig_figure("a_father", "walk", 0.15, 90)
    mother = ct.rig_figure("a_mother", None, 0, 86, flip=True)
    grandma = ct.fit_h(ct.clean_green(ct.load(ROOT / "assets/chars/a_grandma.png")), 74)
    child = ct.fit_h(ct.clean_green(ct.load(ROOT / "assets/chars/a_child.png")), 62)
    return [
        dict(name="程大柱", img=father, room="yard", cell=(8, 3), selected=True, doing="拿铁锹铲掉院里的鸡粪", progress=0.35),
        dict(name="柳晚晴", img=mother, room="hall", cell=(2, 4), doing="就着亮光缝补旧衣裳"),
        dict(name="苏素纨", img=grandma, room="bedroom", cell=(3, 4), doing="一边拍打被褥一边哼小调"),
        dict(name="程小满", img=child, room="yard", cell=(13, 3), doing="蹲在院里看蚂蚁搬家"),
    ]


def crop(big):
    x, y, w, h = CROP
    x0, y0 = ch.px(x, y)
    return big.crop((int(x0), int(y0), int(x0 + w * ch.CW), int(y0 + h * ch.CH)))


# ---------------------------------------------------------------- B: isometric sketch
TW, TH, WH = 64, 32, 70


def iso_sketch(size, ppl):
    W, H = size
    img = ct.tile_fill((W, H), ct.load(ROOT / "assets/tiles/a_grass.png"), 192, 144, 0.12)
    d = ImageDraw.Draw(img)
    ox, oy = W / 2 - 2 * TW, 110

    def P(i, j):
        return (ox + (i - j) * TW / 2, oy + (i + j) * TH / 2)

    def textured(tex_name, i0, j0, w, h, soften=0.2):
        tex = ch.tile(tex_name, (int(w * ch.CW), int(h * ch.CH)), soften=soften)
        # screen = M @ (u, v) + c, u in px along i, v in px along j
        M = np.array([[TW / 2 / ch.CW, -TW / 2 / ch.CH], [TH / 2 / ch.CW, TH / 2 / ch.CH]])
        c = np.array(P(i0, j0))
        inv = np.linalg.inv(M)
        off = -inv @ c
        data = (inv[0, 0], inv[0, 1], off[0], inv[1, 0], inv[1, 1], off[1])
        layer = tex.transform((W, H), Image.AFFINE, data, resample=Image.BILINEAR)
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).polygon([P(i0, j0), P(i0 + w, j0), P(i0 + w, j0 + h), P(i0, j0 + h)], fill=255)
        layer.putalpha(mask)
        img.alpha_composite(layer)

    def wall(a, b, height, shade=0.85):
        """Vertical wall between plan points a, b (cells), plaster face, dark cap."""
        pa, pb = P(*a), P(*b)
        poly = [pa, pb, (pb[0], pb[1] - height), (pa[0], pa[1] - height)]
        face = ch.tile("a_wall", (W, H), 160, 160)
        arr = np.array(face).astype(float); arr[..., :3] *= shade
        face = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        face.putalpha(m)
        img.alpha_composite(face)
        d.polygon(poly, outline=ct.LINE)
        d.line([pa, pb], fill=(138, 90, 54), width=5)
        d.line([(pa[0], pa[1] - height), (pb[0], pb[1] - height)], fill=(96, 74, 58), width=6)

    # region: compound x 12..28 -> i 0..16, y 0..11 -> j 0..11
    textured("a_yard", 0, 6, 16, 5, 0.22)
    textured("a_floor_hall", 0, 0, 10, 6)
    textured("a_floor_bed", 10, 0, 6, 6)
    textured("a_path", 11, 6, 5, 5)
    wall((0, 0), (16, 0), WH, 0.92)          # north (back) wall, lit
    wall((0, 0), (0, 6), WH, 0.75)           # west wall, shade
    wall((10, 0), (10, 2.6), WH, 0.75)       # hall | bedroom partition with a door gap
    wall((10, 3.6), (10, 6), WH, 0.75)
    things = []
    for typ, i, j, wcell in [("a_desk", 4, 1, 2), ("a_altar", 9, 1, 2), ("a_dining_table", 6.5, 4, 3),
                             ("a_kang", 11.5, 2, 3), ("a_well_head", 13, 9, 2), ("a_grape_trellis", 8, 10, 3.4)]:
        things.append((i + j, "obj", (typ, i, j, wcell)))
    spots = {"程大柱": (7, 8.5), "柳晚晴": (3, 5), "苏素纨": (13, 4.5), "程小满": (11, 9.5)}
    for pe in ppl:
        i, j = spots[pe["name"]]
        things.append((i + j, "person", (pe, i, j)))
    things.sort(key=lambda t: t[0])
    for _, kind, data in things:
        if kind == "obj":
            typ, i, j, wcell = data
            im = ch.sprite(typ, w=wcell * TW * 0.7)
            x, y = P(i, j)
            ct.shadow(img, x, y, im.width * 0.7)
            img.alpha_composite(im, (int(x - im.width / 2), int(y - im.height + 6)))
        else:
            pe, i, j = data
            x, y = P(i, j)
            ct.shadow(img, x, y)
            if pe.get("selected"):
                d.ellipse((x - 27, y - 10, x + 27, y + 10), outline=ct.TOMATO, width=4)
            fig = pe["img"]
            img.alpha_composite(fig, (int(x - fig.width / 2), int(y - fig.height + 2)))
            d.text((x, y - fig.height - 10), pe["name"], font=ct.T(14), fill=ct.LINE, anchor="mm", stroke_width=3, stroke_fill=ct.CREAM)
    # front walls cut low (south edge of the rooms, east edge)
    for a, b in [((0, 6), (4.5, 6)), ((5.5, 6), (12, 6)), ((13, 6), (16, 6))]:
        pa, pb = P(*a), P(*b)
        d.polygon([pa, pb, (pb[0], pb[1] - 14), (pa[0], pa[1] - 14)], fill=(220, 204, 176), outline=ct.LINE)
    for name, (i, j) in [("堂屋", (0.6, 0.8)), ("卧房", (10.6, 0.8)), ("院子", (0.6, 6.8)), ("井台", (11.6, 6.8))]:
        d.text(P(i, j), name, font=ct.T(15), fill=ct.LINE, stroke_width=3, stroke_fill=ct.CREAM)
    d.rounded_rectangle((16, H - 52, 300, H - 16), 12, fill=ct.CREAM, outline=ct.LINE, width=2)
    d.text((28, H - 34), "示意：只为看斜 45° 的感觉", font=ct.B(15), fill=ct.LINE, anchor="lm")
    return img


def main():
    ppl = people()
    messes = [("yard", 10, 1, "mess_droppings"), ("hall", 8, 4, "mess_dirt")]
    cols = [("yard", 14, 1, "col_coins")]
    flat = crop(ch.render(ppl, messes, cols, tall=False))
    tall = crop(ch.render(ppl, messes, cols, tall=True))
    iso = iso_sketch(flat.size, ppl)
    cw, chh = flat.size
    HEAD, GAP = 96, 16
    sheet = Image.new("RGB", (cw * 3 + GAP * 4, chh + HEAD + 60), (250, 244, 232))
    d = ImageDraw.Draw(sheet)
    heads = [("现在", "墙只抬起一窄条，地面像平面图"),
             ("A 墙立起来", "后墙一格多高、屋檐、西北来的光投影，前墙切低"),
             ("B 斜 45° 示意", "菱形格子 2:1，只拼了一个草样")]
    for k, (im, (h, sub)) in enumerate(zip([flat, tall, iso], heads)):
        x = GAP + k * (cw + GAP)
        d.text((x + cw / 2, 34), h, font=ct.T(34), fill=ct.LINE, anchor="mm")
        d.text((x + cw / 2, 74), sub, font=ct.B(16), fill=(120, 96, 72), anchor="mm")
        sheet.paste(im.convert("RGB"), (x, HEAD))
        d.rectangle((x - 1, HEAD - 1, x + cw, HEAD + chh), outline=ct.LINE, width=2)
    d.text((GAP, HEAD + chh + 30), "三列是同一块地方、同样的人和家具，1 倍缩放（大人 90 像素）；底部条省略。",
           font=ct.B(16), fill=(120, 96, 72), anchor="lm")
    sheet.save(ROOT / "design/targets/04_立体感对比.png")
    print(sheet.size)


if __name__ == "__main__":
    main()
