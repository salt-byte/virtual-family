"""05b 俯视 vs 斜 45°: current in-game screenshot beside the isometric target, same scale of panel."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compose_targets as ct  # noqa: E402

LEFT = Path.home() / "Downloads/qijia_house_shots/art_yard_people.png"
RIGHT = HERE / "05_斜45度.png"
PW, PH = 960, 540
GAP, HEAD, FOOT = 24, 92, 56

panels = [
    (LEFT, "现在（游戏截图）", "俯视：墙是一条窄带，地面像一张平面图，家具从斜上方看"),
    (RIGHT, "斜 45° 目标图", "菱形格子 64×32：后墙立起、前墙切低，家具和人从屋角看"),
]
sheet = Image.new("RGB", (PW * 2 + GAP * 3, PH + HEAD + FOOT), (250, 244, 232))
d = ImageDraw.Draw(sheet)
for k, (p, title, sub) in enumerate(panels):
    im = Image.open(p).convert("RGB").resize((PW, PH), Image.LANCZOS)
    x = GAP + k * (PW + GAP)
    d.text((x + PW / 2, 32), title, font=ct.T(32), fill=ct.LINE, anchor="mm")
    d.text((x + PW / 2, 70), sub, font=ct.B(18), fill=(120, 96, 72), anchor="mm")
    sheet.paste(im, (x, HEAD))
    d.rectangle((x - 2, HEAD - 2, x + PW + 1, HEAD + PH + 1), outline=ct.LINE, width=2)
d.text((GAP, HEAD + PH + 30), "左边是游戏现在的院子一带；右边同一座院子换成斜 45°：人用现有拆件，地面是现有贴图斜切成菱形，家具、门楼、窗是新生成的；底部条照 03 目标图。",
       font=ct.B(17), fill=(120, 96, 72), anchor="lm")
out = HERE / "05b_俯视vs斜45度.png"
sheet.save(out)
print(out, sheet.size)
