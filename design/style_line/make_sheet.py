"""Style-line review sheet for style A: every processed piece on a neutral background, tiles 2x2, rigs at rest and walking."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[2]
F = lambda s: ImageFont.truetype(str(ROOT / ".cache/NotoSansSC-Regular.otf"), s)
NAMES = [("a_father", "父亲"), ("a_mother", "母亲"), ("a_grandma", "祖母"), ("a_child", "孩子"),
         ("a_well_head", "井"), ("a_millstone", "石磨"), ("a_grape_trellis", "葡萄架"), ("a_clothesline", "晾衣绳"),
         ("a_altar", "供桌"), ("a_dining_table", "饭桌"), ("a_stone_bench", "石凳"), ("a_woodpile", "柴垛"),
         ("a_kang", "土炕"), ("a_stove", "灶台"), ("a_vat", "水缸"), ("a_desk", "书案"), ("a_stool", "矮凳"),
         ("a_loom", "织机"), ("a_coop", "鸡笼"), ("a_garden", "菜畦"), ("a_mess_dirt", "满地碎屑（脏乱）"),
         ("a_mess_droppings", "鸡粪落叶（脏乱）"), ("a_col_egg", "鸡蛋（掉落）"), ("a_col_coins", "铜钱（掉落）"),
         ("a_col_hairpin", "银簪（掉落）"), ("a_icon_ill", "药碗（病）")]
TILES = [("a_yard", "院子泥土地"), ("a_floor_hall", "堂屋方砖"), ("a_floor_bed", "卧房木地板"),
         ("a_floor_earth", "灶间 / 柴房夯土"), ("a_wall", "屋里石灰墙")]
C, COLS = 200, 6


def find(n):
    for d in ("assets/chars", "assets/props", "assets/tiles"):
        p = ROOT / d / f"{n}.png"
        if p.exists():
            return Image.open(p).convert("RGBA")
    raise SystemExit(f"missing {n}")


def cell(im):
    bb = im.getbbox(); im = im.crop(bb) if bb else im
    k = min((C - 24) / im.width, (C - 24) / im.height)
    return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)


items = [(cell(find(n)), t) for n, t in NAMES]
for n, t in TILES:
    im = find(n).resize((96, 96), Image.LANCZOS)
    t2 = Image.new("RGBA", (192, 192))
    for x in (0, 96):
        for y in (0, 96):
            t2.paste(im, (x, y))
    items.append((cell(t2), t + "（2×2 平铺）"))
rows = (len(items) + COLS - 1) // COLS
rig = Image.open(sys.argv[1]).convert("RGBA") if len(sys.argv) > 1 else None
W = COLS * C
H = 70 + rows * (C + 28) + (rig.height * W // rig.width + 40 if rig else 0)
out = Image.new("RGB", (W, H), (250, 246, 238))
d = ImageDraw.Draw(out)
d.text((20, 18), "起家 · 画风 A 暖色手绘卡通 · 风格线", font=F(28), fill=(74, 52, 36))
for i, (im, t) in enumerate(items):
    x, y = (i % COLS) * C, 70 + (i // COLS) * (C + 28)
    d.rounded_rectangle((x + 6, y + 6, x + C - 6, y + C - 6), 14, fill=(240, 232, 216))
    out.paste(im, (x + (C - im.width) // 2, y + (C - im.height) // 2), im)
    d.text((x + C / 2, y + C + 8), t, font=F(15), fill=(74, 52, 36), anchor="mm")
if rig:
    y = 70 + rows * (C + 28) + 10
    d.text((20, y), "拆件小人：父亲、母亲站立（红点是关节）和父亲走路帧", font=F(18), fill=(74, 52, 36))
    r = rig.resize((W, rig.height * W // rig.width), Image.LANCZOS)
    out.paste(r, (0, y + 30), r)
out.save(ROOT / "design/style_line/00_风格线验收图.png")
print(out.size)
