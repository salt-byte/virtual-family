"""Keepsake pictures for the 旧物匣: every old-story fragment (game/packs/qijia/stories.json) plus the finale object
ayun_hoop, two 3x3 green-screen sheets; and the curio cabinet for the panel background.

python3 assets/gen/make_story_prompts.py          # writes the jobs into prompts.json
After generating: python3 assets/gen/key_green_grid.py (STORY / CABINET jobs there).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import make_looks_prompts as mlp  # noqa: E402

PROMPTS = ROOT / "assets/gen/prompts.json"
INK = "纸上的字一律画成几行深褐色的毛笔笔画，像远看的一行行小字，不要画出能认的真字。"
# fragment id -> what to draw (from its text in stories.json)
ITEMS = {
    "half_sampler": "半幅绣样：一块发黄的旧绸子，方方的一小块，边上起了毛；上面绣了半枝粉红色的并蒂莲，一朵绣好了，另一朵只有墨线描的轮廓没绣；一根锈成褐色的绣花针还别在布上",
    "yun_hairpin": "刻着芸字的银簪：一根旧银簪斜放着，簪头是一朵小小的梅花，磨得发亮，银灰色带一点暗；簪身上刻着一个很小的字形笔画（只是几道刻痕）",
    "red_shoe": "井边的一只绣鞋：一只旧的女式绣花鞋，红缎面已经褪成暗土红色，鞋面绣着一朵小花，鞋帮沾着一块干泥",
    "pressed_flower": "纸里夹着的干花：一张折成方胜形状的旧黄纸，打开了一半，里头夹着一朵压扁的干野菊，花瓣是褪色的暗黄色，叶子干成了褐色；纸角写着一小行字",
    "letter_first_half": "半封信：一张旧信纸的上半截，下边是撕开的毛边，纸是旧黄色，竖着写了几行字，有一块墨叫水洇开成一团晕",
    "letter_second_half": "另外半封信：一只打开的小圆胭脂盒，盒是暗红漆面、里面空了，盒里卷着半张旧黄信纸，信纸上边是撕开的毛边，竖着写了几行字",
    "cloth_tiger": "布老虎：一只旧的红黄两色布老虎玩具，趴着，额头上画着王字的花纹，一只耳朵被嚼烂了、缺了一块，肚子瘪了一半；旁边一小撮深红褐色的干枣核",
    "rattle_drum": "拨浪鼓：一只旧拨浪鼓，红漆木框的小圆鼓，鼓面的皮裂了一道口，一根木柄，两边各拴一根线和一颗小木弹丸",
    "half_sugar_monkey": "油纸包着的半个糖人：一张摊开的土黄色油纸，上面粘着半个琥珀色透亮的糖人，看得出是一只小猴子的上半身，糖化了又干，边缘粘在纸上",
    "tiger_shoe": "一只小虎头鞋：一只很小的婴儿虎头鞋，鞋头是橙黄色的老虎脸，黑色的眉毛和胡须，两只小圆耳朵，鞋底纳得密密的白麻线（画成浅土黄色），鞋尖磨薄了一块",
    "birthday_slip": "歪歪扭扭的红纸条：一张小小的长条红纸，褪成暗红，上面是歪歪扭扭的黑字笔画，有两个画了圈的地方，纸边卷起",
    "poem_ten_years": "写着十年的诗笺：一张竖长的旧诗笺，淡黄色带一点暗纹，竖写两行工整的字，旁边一小行朱红色的批注",
    "poem_millstone": "卷在竹筒里的诗笺：一截短短的青黄色旧竹筒横放着，筒口露出卷着的一卷旧黄纸，纸卷抽出来一半",
    "poem_nine_steps": "沾着泥的诗笺：一张旧黄诗笺，下半截糊着一大块褐色干泥，上半截能看到一行字",
    "poem_ledger": "夹在旧账里的诗笺：一本翻开的线装旧账本，蓝布封面，纸页发黄，里面夹着一张露出半截的诗笺，最后一行字写得特别重、特别黑",
    "poem_burnt": "烧掉一角的诗笺：一张旧黄诗笺，右下角烧焦了，焦边是黑褐色卷起来的弧，写着两行字",
    "poem_last": "最后一张诗笺：一张很旧的黄纸诗笺，边角软软卷起，字的墨色很淡、快要看不见，末尾一个小小的落款",
    "ayun_hoop": "阿芸的旧绣绷：一只圆形的旧竹绣绷，竹圈磨得发亮，绷着一块暗红色的旧绸，上面绣了一半的一朵花，一根针别在布上，旁边垂一截红线",
}
SHEETS = {
    "a_story_1": ["half_sampler", "yun_hairpin", "red_shoe", "pressed_flower", "letter_first_half", "letter_second_half",
                  "cloth_tiger", "rattle_drum", "half_sugar_monkey"],
    "a_story_2": ["tiger_shoe", "birthday_slip", "poem_ten_years", "poem_millstone", "poem_nine_steps", "poem_ledger",
                  "poem_burnt", "poem_last", "ayun_hoop"],
}
HEAD = (mlp.STYLE.replace("不要任何文字和边框", "不要边框") + "视角是从斜上方往下看约 45 度，看得到物体的顶面和正面。光从左上方来。"
        "\n附上的参考图只参考画风：描边粗细和颜色、上色方法、色调，照着它画；不要照抄参考图里的东西。")


def story_sheet(name, ids):
    rows = []
    for r in range(3):
        rows.append(f"第 {r + 1} 行从左到右：" + "；".join(f"{ITEMS[i]}" for i in ids[r * 3:(r + 1) * 3]) + "。")
    return {"sheet": name, "size": "1536x1536", "background": "#00FF00", "grid": "3x3",
            "refs": ["assets/gen/ref/a_furn_ref.png"],
            "prompt": HEAD + "\n画一张素材合集：严格排成 3 列 × 3 行的格子，一共 9 格，一格放一样旧东西（老宅里翻出来的旧物件，"
            "有年头、有故事，颜色比新东西旧一点、暗一点，但还是清楚的深棕描边、温暖的颜色）。每个物件只占它那一格的一半左右大小，在格子里居中，"
            "物件之间留出大片空白，互相不接触，格子之间不画分隔线。\n" + "\n".join(rows) +
            "\n" + INK + "所有东西上都不用纯白和很浅的米白（纸是旧黄色），也不用绿色。背景是一整片纯绿色 #00FF00（绿幕），没有渐变、没有纹理；"
            "物件下面不画投影、不画地面。"}


def cabinet():
    return {"sheet": "a_ui_cabinet", "size": "1536x1536", "background": "#00FF00", "grid": "1x1",
            "refs": ["assets/gen/ref/a_furn_ref.png"],
            "prompt": HEAD.replace("视角是从斜上方往下看约 45 度，看得到物体的顶面和正面。", "视角是正前方平视。") +
            "\n画一个旧木头博古架（放古玩的多宝格柜子），正面平视、左右对称，整个占画面的八成。暖棕色的老榆木，木纹淡淡的，边角磨圆，"
            "柜顶一道微微翘起的檐，底下四只矮脚。里面用木板隔成 4 行 × 4 列一样大的方格子，每格都是空的，格子里面是颜色深一点的木头背板，"
            "格子的四边有一圈细细的木框线。格子里什么都不放。柜子不用绿色。背景是一整片纯绿色 #00FF00（绿幕），没有渐变；柜子下面不画投影、不画地面。"}


def main():
    jobs = [story_sheet(n, ids) for n, ids in SHEETS.items()] + [cabinet()]
    data = json.loads(PROMPTS.read_text())
    names = {j["sheet"] for j in jobs}
    data = [d for d in data if d["sheet"] not in names] + jobs
    PROMPTS.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    print(len(jobs), "prompts")


if __name__ == "__main__":
    main()
