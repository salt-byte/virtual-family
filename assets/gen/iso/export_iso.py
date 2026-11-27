"""Copy the cut-out iso pieces into assets/iso/ under the game's object ids, normalise orientation
(default = long side along i, i.e. screen down-right, standing against the north wall), and draw the contact sheet."""
import glob, shutil, sys
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "design/targets"))
import compose_targets as ct  # noqa: E402
SRC, DST = ROOT / "assets/gen/iso", ROOT / "assets/iso"
MAP = {'stove': 'i_stove', 'dining_table': 'i_table', 'kang_sleeper': 'i_kang_sleeper', 'vat': 'i_vat', 'stool': 'i_stool',
       'well_head': 'i_well', 'grape_trellis': 'i_trellis', 'millstone': 'i_millstone', 'woodpile': 'i_woodpile',
       'stone_bench': 'i_bench', 'altar': 'i_altar', 'clothesline': 'i_clothesline', 'desk': 'i_desk', 'coop': 'i_coop_hen',
       'washtub': 'i_washtub', 'cupboard': 'i_cupboard', 'gatehouse_green': 'i_gate', 'wall_window': 'f_window',
       'wall_door_curtain': 'f_door', 'wall_chili': 'f_chili', 'bookshelf': 'n_bookshelf', 'loom': 'n_loom',
       'embroidery_frame': 'n_embroidery_frame', 'carpenter_bench': 'n_carpenter_bench', 'tofu_box': 'n_tofu_box',
       'herb_grinder': 'n_herb_grinder', 'kang': 'n_kang', 'trough': 'n_trough', 'garden': 'n_garden', 'bridge': 'n_bridge',
       'peddler_pole': 'n_peddler_pole', 'fence': 'n_fence', 'gatehouse': 'n_gatehouse', 'sleeper': 'n_sleeper',
       'door_sill': 'n_door_sill', 'bird_cage': 'n_bird_cage'}
MIRROR = {'altar', 'desk', 'herb_grinder'}   # generated with the long side along j


def export():
    DST.mkdir(exist_ok=True)
    for gid, s in MAP.items():
        im = Image.open(SRC / f"{s}.png")
        (ImageOps.mirror(im) if gid in MIRROR else im).save(DST / f"{gid}.png")
    ImageOps.mirror(Image.open(DST / "fence.png")).save(DST / "fence_ns.png")


def sheet(paths, out, title, cols=9, cell=180):
    rows = (len(paths) + cols - 1) // cols
    sh = Image.new('RGBA', (cols * cell, rows * (cell + 24) + 50), (250, 244, 232, 255))
    d = ImageDraw.Draw(sh)
    d.text((12, 12), title, font=ct.B(20), fill=ct.LINE)
    for k, (label, f) in enumerate(paths):
        x, y = (k % cols) * cell, 50 + (k // cols) * (cell + 24)
        d.rectangle((x + 4, y + 4, x + cell - 4, y + cell - 4), fill=(140, 170, 120))
        im = Image.open(f).convert('RGBA')
        im.thumbnail((cell - 16, cell - 16))
        sh.alpha_composite(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2))
        d.text((x + cell // 2, y + cell + 8), label, font=ct.B(14), fill=ct.LINE, anchor='mm')
    sh.save(out)
    return sh


def char_renders():
    """Front / back rigs rendered standing (plus the side rig for comparison) and the pet sprites."""
    cl = ct.cl
    rd = ROOT / "assets/gen/review/facing"
    rd.mkdir(parents=True, exist_ok=True)
    out = []
    for c in ["father", "mother", "grandma", "grandpa", "child"]:
        for v in ["", "_front", "_back"]:
            rp = ROOT / f"assets/chars/a_{c}{v}/a_{c}{v}.rig.json"
            r = cl.load_json(rp)
            lo, hi = cl.bounds(r, [{}])
            im = cl.render(r, rp.parent, {}, (int(hi[0] - lo[0]) + 8, int(hi[1] - lo[1]) + 8), (4 - lo[0], 4 - lo[1]))
            f = rd / f"a_{c}{v or '_side'}.png"
            im.save(f)
            out.append((f"a_{c}{v or '_side'}", f))
    for n in ["a_dog_front", "a_dog_back", "a_cat_front", "a_cat_back"]:
        out.append((n, ROOT / f"assets/chars/{n}/{n}.png"))
    return out


if __name__ == "__main__":
    export()
    items = [(Path(f).stem, f) for f in sorted(glob.glob(str(DST / "*.png")))]
    items += char_renders()
    sheet(items, sys.argv[1] if len(sys.argv) > 1 else ROOT / "assets/gen/review/iso_sheet.png",
          "assets/iso 斜 45° 部件 + 人物正面 / 背面拆件（_side 是原来的侧面，对照用）+ 猫狗正背面（绿底只为看清抠图）")
