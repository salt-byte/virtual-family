"""Keepsake pictures for three more stories (bell / paper_kite / ferry_tags in game/packs/qijia/stories.json):
a_story_3 (3x3) + a_story_4 (2x2; old_kite twice so the better one can be kept). Same look as make_story_prompts.

python3 assets/gen/make_story2_prompts.py     # writes the jobs into prompts.json
python3 assets/gen/make_story2_prompts.py --key   # after generating: key the sheets into assets/props/
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import make_story_prompts as msp  # noqa: E402

PROMPTS = ROOT / "assets/gen/prompts.json"
ITEMS = {
    "bell_clapper": "一只旧铜铃舌（没有铃，只有铃舌）：一根短短的黄铜棒，一头是磨扁了的圆疙瘩，铜色发暗、磨亮的地方泛金；另一头的小环上拴着一截褪成粉红的红绳，绳子松松地弯着",
    "sugar_wrapper": "一块包糖的油纸：一张土黄色的方油纸叠了四折、半摊开，折缝里粘着一粒琥珀色透亮的麦芽糖；纸角用黑炭条画了七道短竖杠，其中六道被一道斜线划掉",
    "tally_stick": "刻着口子的竹签：一根扁扁的旧竹签斜放着，竹皮是黄褐色，一侧边上刻着一排整齐的三角小口子（七道），签尾竖着一行很小的墨字笔画",
    "kite_ribs": "扎成十字的竹篾：四根细长的黄褐色竹篾两两交叉扎成十字，交叉的地方用土黄色麻线缠了一圈又一圈，缠成一个粗粗的疙瘩",
    "almanac_page": "糊过风筝的黄历：一页撕下来的旧黄历纸，暗黄色，边是撕开的毛边，纸面干裂起皮、边上掉了几小块渣；上面印着几格竖排的小字和一道红色的格线，其中一格旁边有一个弯弯的指甲掐痕",
    "swallow_tail": "两条纸燕尾：两条红纸剪的细长尾巴，剪口歪歪扭扭，一长一短交叉着放，每条尾巴尖上点着一个黑色的墨圆点",
    "tangled_line": "一团乱麻线：一团土黄色的麻线乱糟糟缠在一起，一个线头拉出来，拴着一枚铜钱（圆形方孔，暗黄铜色），铜钱的方孔里塞着一张卷成细条的小黄纸条",
    "ferry_tag": "一块木牌：巴掌大的长方形深褐色旧木牌，上头钻了一个小孔，边角磨圆、被手摸得发黑发亮；正面烙着一个焦黑的大字「渡」",
    "pipe_bowl": "一只旧烟袋：一根竹烟杆，一头是黄铜烟锅，竹杆上有一道裂纹，用细细的灰铁丝箍了三道；烟杆上挂着一只小小的褪色深蓝布烟荷包，荷包口露出一点褐色烟丝",
    "pole_tip": "一截竹篙头：一截粗竹竿斜放着，黄褐色的旧竹，下端包着一圈暗铁皮、铁头磨秃了；竹身上横刻着几道深浅不一的水痕刻线，最高那道旁边两个很小的墨字笔画",
    "tag_bundle": "一串木牌：一根土黄色麻绳穿着十几块小小的长方形褐色木牌，木牌颜色深浅不一，挤挤挨挨串成一串，绳子两头打了结垂下来",
    "old_kite": "一只燕子风筝：红纸和黄纸糊的燕子形状风筝，展开的翅膀是红色，肚子是黄色，两条细长的红色剪刀尾巴，竹篾骨架在纸下隐约看得见，翅膀上用黑墨画了几道羽毛线，眼睛一个墨点；纸有点旧，一处小补丁",
}
SHEETS = {
    "a_story_3": (3, ["bell_clapper", "sugar_wrapper", "tally_stick", "kite_ribs", "almanac_page", "swallow_tail",
                      "tangled_line", "ferry_tag", "pipe_bowl"]),
    "a_story_4": (2, ["pole_tip", "tag_bundle", "old_kite", "old_kite"]),
}
# redo of three cells that missed details (clapper end, the 7 strokes, pole notches); keyed over the a_story_3/4 cuts
REDO = {
    "bell_clapper": "一只旧铜铃舌（铃铛里面那根会晃的小铜锤，没有铃）：一根短粗的黄铜棒，下端是一个实心的铜疙瘩，疙瘩的一面被磕得扁平发亮；上端一个小铜环，环上拴着一截褪成粉红的红绳，绳子松松地弯着",
    "sugar_wrapper": "一块包糖的油纸：一张土黄色的方油纸叠成四折的小方块，一角掀开，折缝里粘着一粒琥珀色透亮的麦芽糖；纸面一角用黑炭条画了七道分开的短竖杠，排成一排，左边六道每道上各打了一个小叉，最右边那一道没打叉",
    "pole_tip": "一截竹篙头：一截粗竹竿斜放着，黄褐色的旧竹，有竹节；下端套着一个实心的锥形铁头，铁头尖被磨得又秃又圆；竹身上横刻着五六道细细的刻痕，一道比一道高，像量水的记号，最高那道旁边两个很小的墨字笔画",
}
SHEETS["a_story_5"] = (2, ["bell_clapper", "sugar_wrapper", "pole_tip", "pole_tip"])
ITEMS_REDO = REDO
KEEP = {0, 3}   # a_story_5 cells that replaced the first cut: bell_clapper, pole_tip (sugar_wrapper redo was worse)
OUT_REDONE = SHEETS["a_story_5"][1]
OUT = {i: f"props/story/{i}" for i in ITEMS}
OUT["old_kite"] = "props/a_col_old_kite"


def sheet(name, n, ids):
    items = {**ITEMS, **REDO} if name == "a_story_5" else ITEMS
    rows = [f"第 {r + 1} 行从左到右：" + "；".join(items[i] for i in ids[r * n:(r + 1) * n]) + "。" for r in range(n)]
    total = n * n
    return {"sheet": name, "size": "1536x1536", "background": "#00FF00", "grid": f"{n}x{n}",
            "refs": ["assets/gen/ref/a_furn_ref.png"],
            "prompt": msp.HEAD + f"\n画一张素材合集：严格排成 {n} 列 × {n} 行的格子，一共 {total} 格，一格放一样旧东西（老宅里翻出来的旧物件，"
            "有年头、有故事，颜色比新东西旧一点、暗一点，但还是清楚的深棕描边、温暖的颜色）。每个物件只占它那一格的一半左右大小，在格子里居中，"
            "长条的东西斜着放，物件之间留出大片空白，互相不接触，格子之间不画分隔线。\n" + "\n".join(rows) +
            "\n纸上和竹木上的小字一律画成几道深褐色的笔画，不要画出能认的真字（木牌上的「渡」字除外）。"
            "所有东西上都不用纯白和很浅的米白（纸是旧黄色），也不用绿色（竹子画成旧的黄褐色）。背景是一整片纯绿色 #00FF00（绿幕），没有渐变、没有纹理；"
            "物件下面不画投影、不画地面。"}


def key_all(only=None):
    import key_green_grid as kg
    from PIL import Image
    for name, (n, ids) in SHEETS.items():
        if only and name not in only:
            continue
        src = ROOT / f"assets/gen/inbox/{name}.png"
        if not src.exists():
            continue
        im = Image.open(src)
        W, H = im.size
        for k, i in enumerate(ids):
            c, r = k % n, k // n
            cell = im.crop((c * W // n, r * H // n, (c + 1) * W // n, (r + 1) * H // n))
            if name == "a_story_5":   # candidates; the picked ones (KEEP) also go to assets/props/story/
                out = ROOT / f"assets/gen/out/a_story_5/{i}_{k}.png"
                if k in KEEP:
                    kg.key(cell).save(ROOT / f"assets/{OUT[i]}.png")
            elif i in {OUT_REDONE[k2] for k2 in KEEP}:
                out = ROOT / f"assets/gen/out/{name}/{i}_first.png"
            elif k == 3 and name == "a_story_4":
                out = ROOT / "assets/gen/out/a_story_4/old_kite_alt.png"
            else:
                out = ROOT / f"assets/{OUT[i]}.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            kim = kg.key(cell)
            kim.save(out)
            print(out.relative_to(ROOT), kim.size)


def main():
    if "--key" in sys.argv:
        return key_all([a for a in sys.argv[1:] if not a.startswith("--")] or None)
    jobs = [sheet(s, n, ids) for s, (n, ids) in SHEETS.items()]  # noqa
    data = json.loads(PROMPTS.read_text())
    names = {j["sheet"] for j in jobs}
    data = [d for d in data if d["sheet"] not in names] + jobs
    PROMPTS.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    print(len(jobs), "prompts")


if __name__ == "__main__":
    main()
