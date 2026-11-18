"""Side-by-side style comparison for 起家: four styles x (person, well, dining table, yard tile, in-game mock at scale 1).
Reads the pipeline outputs in assets/chars, assets/props, assets/tiles (not committed)."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
HEI = "/System/Library/Fonts/STHeiti Medium.ttc"
def F(s): return ImageFont.truetype(HEI, s)

STYLES = [
    ("A", "暖色手绘卡通", "圆润、暖、饱和，主流经营游戏的感觉",
     "assets/chars/cmp_a_person.png", "assets/props/cmp_a_well.png", "assets/props/cmp_a_table.png", "assets/tiles/cmp_a_yard.png"),
    ("B", "干净扁平插画", "简单形状、平涂色块、细线",
     "assets/chars/cmp_b_person.png", "assets/props/cmp_b_well.png", "assets/props/cmp_b_table.png", "assets/tiles/cmp_b_yard.png"),
    ("C", "淡水彩无墨线", "现在这版去掉黑墨线，同色深线勾边",
     "assets/chars/cmp_c_person.png", "assets/props/cmp_c_well.png", "assets/props/cmp_c_table.png", "assets/tiles/cmp_c_yard.png"),
    ("D", "现在这版（水墨淡彩）", "参照：上一轮的目标图用的就是它",
     "assets/chars/fam_father.png", "assets/props/well_head.png", "assets/props/dining_table.png", "assets/tiles/tile_yard.png"),
]
ROWS = [("人物", 330), ("井", 230), ("饭桌", 230), ("院子地面", 230), ("游戏里\n（1 倍大小）", 230)]
COLW, LABW, HEADH = 400, 120, 120
W = LABW + COLW * 4
H = HEADH + sum(h for _, h in ROWS) + 40
BG = (244, 242, 238)


def load(p):
    return Image.open(ROOT / p).convert("RGBA")


def clean_green(img):
    a = np.array(img).astype(np.int16)
    spill = (a[..., 1] - np.maximum(a[..., 0], a[..., 2])) > 40
    a[..., 3] = np.where(spill, 0, a[..., 3])
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def fit(im, w, h):
    im = trim(im)
    k = min(w / im.width, h / im.height)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def tile_fill(size, tile, tw, th):
    t = tile.resize((tw, th), Image.LANCZOS)
    out = Image.new("RGBA", size)
    for y in range(0, size[1], th):
        for x in range(0, size[0], tw):
            out.paste(t, (x, y))
    return out


def mock(person, well, tile):
    """6x4 cells of yard at scale 1 (cell 48x36), the well on its 2x2 footprint, the person (76 px) beside it."""
    cw, ch = 48, 36
    w, h = 8 * cw, 5 * ch
    out = tile_fill((w, h), tile, 192, 144)
    d = ImageDraw.Draw(out, "RGBA")
    # well on footprint cells (1..2, 1..2)
    fx, fy, fw, fh = 1 * cw, 1 * ch, 2 * cw, 2 * ch
    wi = fit(well, fw * 0.9, fh + 20)
    out.alpha_composite(wi, (round(fx + (fw - wi.width) / 2), round(fy + fh - wi.height + 4)))
    # person standing at cell (4, 3)
    px, py = 4 * cw + cw / 2, 3 * ch + ch / 2 + 10
    sh = Image.new("RGBA", (60, 20))
    ImageDraw.Draw(sh).ellipse((10, 6, 50, 15), fill=(40, 34, 30, 60))
    out.alpha_composite(sh.filter(ImageFilter.GaussianBlur(2)), (round(px - 30), round(py - 11)))
    pi = fit(person, 60, 76)
    out.alpha_composite(pi, (round(px - pi.width / 2), round(py - pi.height + 2)))
    return out


def main():
    img = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(img)
    for i, (tag, name, sub, *_ ) in enumerate(STYLES):
        x0 = LABW + i * COLW
        d.text((x0 + COLW / 2, 42), f"{tag}  {name}", font=F(30), fill=(40, 36, 32), anchor="mm")
        d.text((x0 + COLW / 2, 84), sub, font=F(16), fill=(110, 104, 96), anchor="mm")
        if i:
            d.line([(x0, 16), (x0, H - 44)], fill=(210, 205, 196), width=2)
    y = HEADH
    for r, (label, rh) in enumerate(ROWS):
        d.line([(16, y), (W - 16, y)], fill=(210, 205, 196), width=1)
        for k, line in enumerate(label.split("\n")):
            d.text((LABW / 2, y + rh / 2 - 12 + k * 26 - (12 if "\n" in label else 0)), line, font=F(20 if k == 0 else 14),
                   fill=(70, 64, 58), anchor="mm")
        for i, (tag, name, sub, pp, wp, tp, yp) in enumerate(STYLES):
            x0 = LABW + i * COLW
            person = clean_green(load(pp))
            if r == 0:
                im = fit(person, COLW - 60, rh - 30)
            elif r == 1:
                im = fit(load(wp), COLW - 120, rh - 30)
            elif r == 2:
                im = fit(load(tp), COLW - 100, rh - 40)
            elif r == 3:
                im = tile_fill((COLW - 60, rh - 30), load(yp), 192, 144)
            else:
                im = mock(person, load(wp), load(yp))
            img.alpha_composite(im, (round(x0 + (COLW - im.width) / 2), round(y + (rh - im.height) / 2)))
        y += rh
    d.text((W - 20, H - 16), "人物、井、饭桌按 2 倍素材大小显示；最后一行是游戏里 1 倍大小：一格 48×36，人约 76 像素高",
           font=F(14), fill=(120, 114, 106), anchor="rb")
    out = ROOT / "design/style_compare/00_画风对比.png"
    img.convert("RGB").save(out)
    print(out, img.size)


if __name__ == "__main__":
    main()
