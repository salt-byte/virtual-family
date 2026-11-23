"""Hand-held props (assets/props/hand/<id>.png): small things a 3/4-front character holds in one fist.
Two 3x3 green-screen sheets for the short things, one 3x1 sheet for the long-handled tools.

python3 assets/gen/make_hand_prompts.py      # writes the jobs into prompts.json and rows into manifest.csv
After generating: python3 assets/gen/hand_props.py
"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "assets/gen"))
import make_looks_prompts as mlp  # noqa: E402

PROMPTS = ROOT / "assets/gen/prompts.json"
MANIFEST = ROOT / "assets/gen/manifest.csv"
INK = "纸上的字一律画成几行深褐色的毛笔笔画，像远看的一行行小字，不要画出能认的真字。"

# id -> (中文名, what to draw)
ITEMS = {
    "rice_bowl_full": ("一碗饭（带筷子）", "一碗饭：一只粗瓷饭碗，碗外是暖土黄色釉，碗口下一圈蓝色花边，盛得冒尖的米饭（米饭画成暖奶黄色，不用纯白），"
                       "饭上一小撮褐色咸菜，一双红褐色竹筷子并在一起斜搭在碗沿上，筷子头伸出碗外"),
    "bowl_empty": ("空碗", "空碗：和前一格同样的粗瓷饭碗，碗外暖土黄色釉、一圈蓝色花边，碗是空的，看得见碗里浅土黄色的釉底和两三粒饭"),
    "teacup": ("茶杯", "茶杯：一只小小的粗陶茶杯，没有把手，赭褐色釉，杯口一圈深一点的釉线，杯里是琥珀色的茶水"),
    "medicine_bowl": ("药碗", "药碗：一只深褐色粗陶小碗，比饭碗略小、略深，盛满黑褐色的汤药，药面上一点暖色的反光"),
    "medicine_bottle": ("药瓶", "药瓶：一只小小的葫芦形瓷药瓶，暖土黄色釉，瓶口塞着红布包的木塞，红布在瓶颈扎一道细绳，瓶身贴一小张红纸签"),
    "osmanthus_cake": ("桂花糕", "桂花糕：一块方方的小糕，浅金黄色、有一点半透明，糕面上撒一层橙黄色的小桂花，糕下垫一小片土黄色油纸"),
    "tofu_tray": ("豆腐盘", "豆腐盘：一只浅浅的方木托盘，橙棕色木框，盘里并排放着四块切好的方豆腐（豆腐画成暖奶黄色，不用纯白），"
                  "一角搭着一块土黄色的纱布；托盘平放，看得到盘里"),
    "ladle": ("勺（木汤勺）", "木汤勺：一把舀汤的大木勺，橙棕色老木，长柄竖直朝下，勺头在上方，勺口微微朝向我们，看得见勺里面"),
    "wok_spatula": ("锅铲", "锅铲：一把铁锅铲，深灰色的铁铲头在上方、微微弯，下面接一根竖直朝下的橙棕色木柄"),
    "book_open": ("翻开的线装书", "翻开的线装书：一本摊开的旧线装书，像捧在手里读那样两页摊开，纸页是旧黄色，每页竖着几行字；"
                  "两页之间书脊处微微凹下去，书页外侧露出一点蓝灰色布封面的边"),
    "book_closed": ("合上的书", "合上的线装书：一本合着的旧线装书，深蓝色布封面，左边一排褐色的订书线和四个针眼，封面左上贴一条竖长的旧黄纸签，签上几笔字"),
    "writing_brush": ("毛笔", "毛笔：一支毛笔竖着，黑色尖尖的笔毫朝下，笔杆是黄褐色的细竹管，笔杆顶端一个小小的红绳挂环"),
    "embroidery_hoop": ("绣绷（带针线）", "绣绷：一只圆形竹绣绷，稍微倾斜、看成一个扁一点的圆，绷着一块暗红色的绸布，上面绣了一半的一朵橙黄色的花（只绣花，没有叶子，花茎用褐色线），"
                        "一根银灰色的针带着一段红线插在布上，红线垂下来一小截"),
    "sugar_figure": ("糖人", "糖人：一根细细的竹签竖直朝下，签子顶上是一个琥珀金黄色、亮晶晶半透明的糖画小公鸡，糖丝勾出鸡冠、翅膀和翘尾巴"),
    "rattle_drum": ("拨浪鼓", "拨浪鼓：一只红漆木框的小圆鼓，鼓面是土黄色的皮，画着一朵红色小圆花，鼓两边各拴一根短线和一颗小木珠，"
                    "鼓下面一根橙棕色木柄竖直朝下"),
    "herb_bundle": ("一捆草药", "一捆草药：一小捆晒干的草药，中间用土黄色草绳扎紧，上半截是褐色、土红色、暗紫色的干枝叶和几朵干小花，"
                    "下半截是一把褐色的根茎；整捆竖着，扎绳的地方是手握的地方"),
    "carpenter_plane": ("刨子", "刨子：一把木工刨子，横放，长方形的橙棕色老木刨身，中间斜插一块深灰色铁刨刃，刃上露一截木楔；"
                        "刨身前后各横穿出一根短短的木把手；看得到刨身的顶面和正面"),
    "water_bucket": ("水桶", "水桶：一只木水桶，橙棕色木板拼成，箍着上下两道深褐色铁箍，桶口上一根弯弯的木提梁，桶里是蓝灰色的水"),
    "broom": ("竹扫帚", "竹扫帚：一根长长的黄褐色竹竿竖着，柄头朝上，竿下端扎着一大把散开的细竹枝（褐黄色），用草绳扎了两道，"
              "竹枝向下散成扇形，梢头有点乱"),
    "hoe": ("锄头", "锄头（中国农村挖地的板锄，不是斧头）：一根长长的橙棕色木柄竖着；柄的最上端套着一个深灰色的铁弯脖，向右伸出一小段后向下弯；弯脖下面连着一块又宽又薄的长方形深灰铁板（锄板），锄板竖直向下垂着、和木柄平行，挂在木柄上半截的右边，锄板的下边是平直的横刃口。整个铁件像一个“7”字挂在柄顶"),
    "axe": ("斧头", "劈柴的斧头：一根橙棕色木柄竖着（长度只有锄头柄的一半），上端装着一个深灰色的铁斧头，斧刃朝画面右边，刃口磨得发亮（浅灰色）"),
}
SHEETS = {
    "a_hand_1": (3, 3, ["rice_bowl_full", "bowl_empty", "teacup", "medicine_bowl", "medicine_bottle", "osmanthus_cake",
                        "tofu_tray", "ladle", "wok_spatula"]),
    "a_hand_2": (3, 3, ["book_open", "book_closed", "writing_brush", "embroidery_hoop", "sugar_figure", "rattle_drum",
                        "herb_bundle", "carpenter_plane", "water_bucket"]),
    "a_hand_3": (3, 1, ["broom", "hoe", "axe"]),
    "a_hand_4": (2, 1, ["hoe", "embroidery_hoop"]),   # redo: hoe came out as an axe, hoop had green leaves
}
HEAD = (mlp.STYLE.replace("不要任何文字和边框", "不要边框") +
        "视角和游戏里的人一样是“四分之三前”：镜头从斜前上方往下看约 30 度，看得到东西的顶面和正面。光从左上方来。"
        "\n附上的参考图只参考画风：描边粗细和颜色、上色方法、色调，照着它画；不要照抄参考图里的东西。")
TAIL = ("所有东西上都不用纯白和很浅的米白，也一点绿色都不用。东西都是拿在手里的小物件，单独画，不画手、不画人。"
        "背景是一整片纯绿色 #00FF00（绿幕），没有渐变、没有纹理；物件下面不画投影、不画地面。")


def sheet(name, cols, rows, ids):
    lines = []
    for r in range(rows):
        lines.append(f"第 {r + 1} 行从左到右：" + "；".join(ITEMS[i][1] for i in ids[r * cols:(r + 1) * cols]) + "。")
    if name == "a_hand_4":
        layout = ("画一张素材合集：严格排成 2 列 × 1 行，一共 2 格，每格是一个竖长条，左右两件东西互相不接触，格子之间不画分隔线。"
                  "左格的锄头竖直立着、居中，大约占格子高度的七成；右格的绣绷小小的，只占格子宽度的一半，放在格子正中。")
    elif rows == 1:
        layout = (f"画一张素材合集：严格排成 {cols} 列 × 1 行，一共 {cols} 格，每格是一个竖长条，一格放一件长柄农具，"
                  "竖直立着、居中，大约占格子高度的七成，上下左右都留空，互相不接触，格子之间不画分隔线。"
                  "三件工具按同一个比例画：扫帚和锄头一样长，斧头只有它们一半长。")
    else:
        layout = (f"画一张素材合集：严格排成 {cols} 列 × {rows} 行的格子，一共 {cols * rows} 格，一格放一样手里拿的小东西。"
                  "每个物件只占它那一格的一半左右大小，在格子里居中，物件之间留出大片空白，互相不接触，格子之间不画分隔线。"
                  "有柄的东西柄都竖直朝下。")
    return {"sheet": name, "size": "1536x1536", "background": "#00FF00", "grid": f"{cols}x{rows}",
            "refs": ["assets/gen/ref/a_furn_ref.png"],
            "prompt": HEAD + "\n" + layout + "\n" + "\n".join(lines) + "\n" + (INK if name == "a_hand_2" else "") + TAIL}


def main():
    jobs = [sheet(n, *v) for n, v in SHEETS.items()]
    data = json.loads(PROMPTS.read_text())
    names = {j["sheet"] for j in jobs}
    data = [d for d in data if d["sheet"] not in names] + jobs
    PROMPTS.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    rows = list(csv.reader(MANIFEST.open(encoding="utf-8")))
    have = {r[0] for r in rows[1:] if r}
    with MANIFEST.open("a", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        for n, (c, r, ids) in SHEETS.items():
            for k, i in enumerate(ids):
                if f"hand_{i}" not in have and n != "a_hand_4":
                    w.writerow([f"hand_{i}", "手持物", "prop", "", ITEMS[i][0], n, k, "待生成", "", ""])
    print(len(jobs), "prompts")


if __name__ == "__main__":
    main()
