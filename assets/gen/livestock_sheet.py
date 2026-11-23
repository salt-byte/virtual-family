"""Contact strip for the pigsty / coop animals: every sprite on a cream tile, then the animals at game scale next
to the dog. Writes ~/Downloads/qijia_house_shots/livestock_sheet.png.

python3 assets/gen/livestock_sheet.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
C = ROOT / "assets/chars"
OUT = Path.home() / "Downloads/qijia_house_shots/livestock_sheet.png"
FONT = "/System/Library/Fonts/STHeiti Medium.ttc"
BG, TILE, INK = (246, 238, 222), (234, 222, 198), (74, 52, 36)

SPRITES = [
    ("a_pig", "猪 侧面"), ("a_pig_front34/a_pig_front34", "猪 3/4 前"), ("a_pig_back34/a_pig_back34", "猪 3/4 后"),
    ("a_pig_sleep", "猪 趴睡"),
    ("a_piglet", "小猪 侧面"), ("a_piglet_front34/a_piglet_front34", "小猪 3/4 前"),
    ("a_piglet_back34/a_piglet_back34", "小猪 3/4 后"),
    ("a_hen", "母鸡 侧面"), ("a_hen_front34/a_hen_front34", "母鸡 3/4 前"), ("a_hen_back34/a_hen_back34", "母鸡 3/4 后"),
    ("a_hen_sit", "母鸡 孵蛋"), ("a_chick_front34/a_chick_front34", "小鸡 3/4 前"),
]
# display height relative to the dog's front34 height (dog = 1.0)
SCALE = [("a_dog_front34/a_dog_front34", 1.0, "狗 1.0"), ("a_pig_front34/a_pig_front34", 0.95, "猪 0.95"),
         ("a_pig_sleep", 0.62, "趴睡 0.62"), ("a_piglet_front34/a_piglet_front34", 0.5, "小猪 0.5"),
         ("a_hen_front34/a_hen_front34", 0.6, "母鸡 0.6"), ("a_hen_sit", 0.5, "孵蛋 0.5"),
         ("a_chick_front34/a_chick_front34", 0.3, "小鸡 0.3"), ("a_dog", 0.8, "狗 侧面"), ("a_pig", 0.8, "猪 侧面")]


def font(n):
    return ImageFont.truetype(FONT, n)


def main():
    T, PAD, LBL = 200, 14, 26
    cols = 6
    rows = (len(SPRITES) + cols - 1) // cols
    dogH = 200
    scale_w = 0
    scaled = []
    for name, k, lab in SCALE:
        im = Image.open(C / f"{name}.png").convert("RGBA")
        if name in ("a_dog", "a_pig"):          # side views: same px per unit as each other
            ref = Image.open(C / "a_dog.png")
            f = dogH * 0.8 / ref.height if name == "a_dog" else dogH * 0.8 / ref.height * 1.25
            im = im.resize((int(im.width * f), int(im.height * f)))
        else:
            h = int(dogH * k)
            im = im.resize((int(im.width * h / im.height), h))
        scaled.append((im, lab))
        scale_w += max(im.width, 80) + 24
    W = max(PAD + cols * (T + PAD), scale_w + 2 * PAD)
    top = 50
    gridH = rows * (T + LBL + PAD)
    H = top + gridH + 50 + dogH + 60
    sheet = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 12), "猪圈 / 鸡笼的牲口（style A，绿幕抠图）：侧面朝右｜3/4 前（朝右下）｜3/4 后（朝右上）；往左走水平翻转",
           fill=INK, font=font(20))
    for i, (name, lab) in enumerate(SPRITES):
        x, y = PAD + (i % cols) * (T + PAD), top + (i // cols) * (T + LBL + PAD)
        d.rounded_rectangle((x, y, x + T, y + T), 10, fill=TILE)
        im = Image.open(C / f"{name}.png").convert("RGBA")
        im.thumbnail((T - 20, T - 20))
        sheet.alpha_composite(im, (x + (T - im.width) // 2, y + (T - im.height) // 2))
        d.text((x + 4, y + T + 2), f"{lab}  {Path(name).name}", fill=INK, font=font(14))
    y0 = top + gridH + 8
    d.text((PAD, y0), "和大黄狗比个头（显示高度 ÷ 狗 3/4 前的高度；末两张是侧面，猪画成狗的 1.25 倍）", fill=INK, font=font(18))
    base = y0 + 36 + dogH
    x = PAD
    for im, lab in scaled:
        sheet.alpha_composite(im, (x, base - im.height))
        d.text((x, base + 6), lab, fill=INK, font=font(14))
        x += max(im.width, 80) + 24
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(OUT)
    print(OUT, sheet.size)


if __name__ == "__main__":
    main()
