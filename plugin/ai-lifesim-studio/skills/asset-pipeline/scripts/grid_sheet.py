"""给图块表画网格和坐标，方便选区。选错格子（透明块、带草的变体）是最常见的地图问题。

用法：
  python3 grid_sheet.py <图块表.png> <输出.png>                 整张表，每 4 行标一次坐标
  python3 grid_sheet.py <图块表.png> <输出.png> x0 y0 x1 y1      放大 2 倍看一块区域，每格都标坐标
格子大小默认 32，可用环境变量 TILE 改。
"""
import os, sys
from PIL import Image, ImageDraw
T = int(os.environ.get('TILE', 32))
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
if len(sys.argv) >= 7:
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    c = im.crop((x0 * T, y0 * T, x1 * T, y1 * T))
    bg = Image.new('RGBA', c.size, (90, 110, 80, 255)); bg.alpha_composite(c)
    bg = bg.resize((c.size[0] * 2, c.size[1] * 2), Image.NEAREST)
    d = ImageDraw.Draw(bg)
    for x in range(x1 - x0):
        for y in range(y1 - y0):
            d.rectangle([x * 2 * T, y * 2 * T, (x + 1) * 2 * T - 1, (y + 1) * 2 * T - 1], outline=(255, 0, 0, 90))
            d.text((x * 2 * T + 2, y * 2 * T + 2), f'{x0 + x},{y0 + y}', fill=(255, 255, 0))
else:
    bg = Image.new('RGBA', im.size, (90, 110, 80, 255)); bg.alpha_composite(im)
    d = ImageDraw.Draw(bg)
    for i in range(0, im.size[0], T): d.line([(i, 0), (i, im.size[1])], fill=(255, 0, 0, 90))
    for j in range(0, im.size[1], T): d.line([(0, j), (im.size[0], j)], fill=(255, 0, 0, 90))
    for x in range(im.size[0] // T):
        for y in range(0, im.size[1] // T, 4): d.text((x * T + 1, y * T + 1), f'{x},{y}', fill=(255, 255, 0))
bg.save(out)
print('saved', out)
