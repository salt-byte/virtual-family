"""Writes assets/chars/looks.json: one entry per adoption look.

height: the height the game should draw this look at so its body (shoulder to heel) matches a_father at 90 px
(elders: a_grandma at 74). Hats and tall hair make the rest-pose bounding box taller,
so a plain 90 would shrink the body; this number compensates. Measured on the side rig from the neck down.
Women are matched to a_mother at 86; the two looks drawn tall get 4 % more.

python3 assets/gen/make_looks_json.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import build_facing_rigs  # noqa: E402,F401
import cutout_lib as cl  # noqa: E402

CHARS = ROOT / "assets/chars"

LOOKS = [
    ("a_adult_1", "male", "adult", "斗笠农夫", ["farming"],
     "斗笠压得低，赭黄短褂的袖子挽到小臂，腰里一根土红布带。裤腿卷到小腿肚，脚上一双草鞋，人晒得黝黑。"),
    ("a_adult_2", "male", "adult", "清瘦书生", ["reading"],
     "又高又瘦，头戴黑方巾，月白长衫垂到脚面，领口袖口滚一道深蓝边。嘴总抿着，难得一笑。"),
    ("a_adult_3", "male", "adult", "胖货郎", ["peddling"],
     "圆脸圆肚子，两撇小胡子，眼睛笑成两道缝。深棕毡帽，米白衬褂外头套一件酱红坎肩，盘扣绷得紧紧的。"),
    ("a_adult_4", "male", "adult", "木匠", ["carpentry"],
     "方下巴，一圈短胡茬，白布头巾在脑后打个结。深褐短褂外挂一条土黄帆布围裙，胸口一只小口袋，腿上打着绑腿。"),
    ("a_adult_5", "female", "adult", "绣娘", ["embroidery"],
     "瓜子脸，脑后一个圆髻，横插一根银簪，簪头一点红绒花。桃粉大襟袄滚月白边，脚上一双绣花鞋。"),
    ("a_adult_6", "female", "adult", "豆腐娘", ["tofu"],
     "圆脸红扑扑，一笑露出一排牙。白布头巾把头发全包住，靛蓝碎花袄外面套着白套袖，腰里系白围裙。"),
    ("a_adult_7", "female", "adult", "采药姑娘", ["medicine"],
     "齐眉刘海，两条麻花辫垂在肩后，辫梢扎红头绳。砖红短袄，腰上斜挎一只浅棕布药囊，腿上打浅灰绑腿。"),
    ("a_adult_8", "female", "adult", "瘦高农妇", ["farming", "embroidery"],
     "高个子，长脸，眉头总皱着。头顶盘大髻，插一根木簪，扎一条藏青白点头帕。藕荷色大襟袄，袖子挽到小臂。"),
    ("a_elder_1", "male", "elder", "老郎中", ["medicine", "reading"],
     "白胡子垂到胸口，黑瓜皮帽顶上一颗红绒结。灰蓝对襟长棉袄过了膝盖，背有点驼，笑眯眯的。"),
    ("a_elder_2", "female", "elder", "老婆婆", ["tofu", "embroidery"],
     "胖墩墩，满脸笑纹，银灰头发挽个小髻。额上勒一条黑抹额，正中缀一颗红珠，靛青大襟袄滚黑边。"),
]
BASE = {("adult", "male"): ("a_father", 90), ("adult", "female"): ("a_mother", 86),
        ("elder", "male"): ("a_grandma", 74), ("elder", "female"): ("a_grandma", 74)}
TALL = {"a_adult_2": 1.04, "a_adult_8": 1.04}   # the two drawn tall and thin


def body_share(name):
    """(torso + thigh + shin length) / rest height, on the side rig."""
    rig = cl.load_json(CHARS / name / f"{name}.rig.json")
    lo, hi = cl.bounds(rig, [{}])
    W = cl.world(rig, {})
    head = next(p for p in rig["parts"] if p["id"] == "head")
    neck_y = (W["head"] @ [0, 0, 1])[1]          # head pivot = neck root, in world coords
    return (hi[1] - neck_y) / (hi[1] - lo[1]), head


def main():
    out = []
    for lid, sex, stage, name, jobs, desc in LOOKS:
        ref, h = BASE[(stage, sex)]
        k_ref, _ = body_share(ref)
        k, _ = body_share(lid)
        out.append({
            "id": lid, "sex": sex, "stage": stage, "name": name, "description": desc, "livelihoods": jobs,
            "height": round(h * k_ref / k * TALL.get(lid, 1.0)),
            "rig": f"chars/{lid}/{lid}.rig.json",
            "rig_front": f"chars/{lid}_front/{lid}_front.rig.json",
            "rig_back": f"chars/{lid}_back/{lid}_back.rig.json",
            "portrait": f"chars/portraits/{lid}.png",
        })
    doc = {"note": "领养候选的长相。路径相对 assets/。height 是建议的游戏内身高（像素），让脖子以下的身子和父亲 / 母亲（老人和祖母）一样大，书生和瘦高农妇再高 4%；"
                   "戴斗笠、盘高髻的人头顶更高，所以数比 90 大。三套骨架部件 id 相同，正面、背面走路用 chars/anims.humanoid_front.json。",
           "looks": out}
    (CHARS / "looks.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1))
    for o in out:
        print(o["id"], o["height"])


if __name__ == "__main__":
    main()
