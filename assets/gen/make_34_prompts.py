"""Three-quarter (iso 45 deg) views of every look: reference boards, lineups, part sheets.

Steps (all paths under assets/gen):
  python3 assets/gen/make_34_prompts.py refs       # ref/a34_board_<g>.png: each person side / front / back + iso furniture
  python3 assets/gen/make_34_prompts.py prompts    # lineups a34_lineup_<g> and part sheets a_<id>_front34_parts / _back34_parts
  python3 assets/gen/make_34_prompts.py crops      # after the lineups: ref/a_<id>_front34_ref.png / _back34_ref.png

front34 = body turned 45 deg, facing the viewer's lower right; back34 = turned away, walking to the upper right.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GEN = ROOT / "assets/gen"
CHARS = ROOT / "assets/chars"
PROMPTS = GEN / "prompts.json"
sys.path.insert(0, str(GEN))
import make_looks_prompts as mlp  # noqa: E402

STYLE = mlp.STYLE
GROUPS = {
    "fam": ["father", "mother", "grandma", "grandpa", "child"],
    "a": ["adult_1", "adult_2", "adult_3", "adult_4", "adult_5"],
    "b": ["adult_6", "adult_7", "adult_8", "elder_1", "elder_2"],
}
FAMILY = {
    "father": ("父亲", "三十多岁的男人，瘦高，头身比 1:5；头上裹一条灰蓝布巾，在脑后打结；青蓝色立领对襟短褂，一排盘扣，袖口翻出一道浅灰边；"
               "暖灰色布裤，小腿打浅灰绑腿，黑布鞋"),
    "mother": ("母亲", "三十岁上下的女人，头身比 1:5；黑发在脑后挽一个圆髻；橙棕色大襟袄；腰前系一条深蓝色短围裙，下摆只到胯部；深色裤子，黑布鞋"),
    "grandma": ("祖母", "六十多岁的老太太，头身比 1:4.5，背明显驼着向前弓，脖子往前探；白发在脑后挽一个髻，满脸皱纹；豆沙紫褐色夹袄；"
                "深灰裤子，黑布鞋"),
    "grandpa": ("爷爷", "七十岁上下的老汉，头身比 1:4.5，背驼着向前弓；花白短发、花白山羊胡，满脸皱纹；深棕色对襟旧棉袄；黑布裤，黑布鞋；不拿拐杖"),
    "child": ("孩子", "七八岁的孩子，头身比 1:3，头大，圆脸，胳膊腿短而圆；头顶扎两个小抓髻；明黄色小褂；深灰裤子，黑布鞋"),
}


def who(pid):
    if pid in FAMILY:
        return FAMILY[pid]
    return mlp.LOOKS["a_" + pid]


def render_rig(rp, pad=8):
    sys.path.insert(0, str(ROOT / "plugin/ai-lifesim-studio/skills/cutout-animation/scripts"))
    import cutout_lib as cl
    rig = cl.load_json(rp)
    lo, hi = cl.bounds(rig, [{}])
    canvas = (int(hi[0] - lo[0]) + 2 * pad, int(hi[1] - lo[1]) + 2 * pad)
    return cl.render(rig, rp.parent, {}, canvas, (pad - lo[0], pad - lo[1]))


def fit(im, h):
    im = im.crop(im.getbbox())
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)


def refs():
    """One board per group: per person side, front and back rest poses on green; a strip of iso furniture under."""
    furn = ["dining_table", "stool", "cupboard", "altar"]
    for g, ids in GROUPS.items():
        W, H = 2400, 1320
        board = Image.new("RGB", (W, H), (0, 255, 0))
        cw = W // len(ids)
        for k, pid in enumerate(ids):
            ims = []
            for suf in ("", "_front", "_back"):
                rp = CHARS / f"a_{pid}{suf}/a_{pid}{suf}.rig.json"
                ims.append(fit(render_rig(rp), 520 if pid != "child" else 380))
            tot = sum(i.width for i in ims) + 2 * 16
            if tot > cw - 20:
                f = (cw - 20) / tot
                ims = [i.resize((max(1, round(i.width * f)), max(1, round(i.height * f))), Image.LANCZOS) for i in ims]
            x = k * cw + 10
            gap = 16
            for im in ims:
                board.paste(im, (x, 700 - im.height), im)
                x += im.width + max(4, gap)
        x = 60
        for f in furn:
            im = fit(Image.open(ROOT / f"assets/iso/{f}.png").convert("RGBA"), 330)
            # furniture on a cream ground so it reads as "the scene's camera", not as a person
            card = Image.new("RGB", (im.width + 40, 370), (240, 232, 214))
            card.paste(im, (20, 20), im)
            board.paste(card, (x, 900))
            x += card.width + 60
        out = GEN / f"ref/a34_board_{g}.png"
        board.save(out)
        print(out)


ANGLE = ("镜头的角度和参考图下面那几件家具一样：游戏是 2:1 的斜 45 度等距视角，镜头在人物的斜前上方、往下看约 30 度，看得到一点帽顶 / 头顶和肩膀上面，"
         "脚底的鞋看得到一点鞋面。")
FRONT34 = ("四分之三侧前方：人的身体整体转了 45 度，脸、胸口、脚尖都朝向画面的右下方。看得到脸的大半个正面和两只眼睛（靠右那只眼睛窄一点、靠近脸的边），"
           "鼻子朝右下；身体的正面和一侧都看得见；两只脚并排站，靠左的那只脚比靠右那只低一点（在画面上沿一条从左下到右上的斜线），两只鞋尖都朝右下。"
           "靠左的那只胳膊整条看得见、垂在身体左边；靠右的那只胳膊有一半被身体挡住，只从身体右边露出一条。")
BACK34 = ("四分之三侧后方：人背对着我们，身体整体转了 45 度，朝画面的右上方走去。看得到后脑勺、后背的大半和身体的一侧；脸几乎看不见，"
          "只在右边露出一点脸颊和耳朵的轮廓，看不到眼睛；两只脚并排站，靠右的那只脚比靠左那只低一点（沿一条从右下到左上的斜线），"
          "看得到鞋跟，鞋尖朝右上。靠右的那只胳膊整条看得见；靠左的那只胳膊有一半被身体挡住。")


def lineup(g, facing):
    """One row of five, one facing per image (a 2-row sheet drew the back row as front views again)."""
    ids = GROUPS[g]
    names = "、".join(f"第 {k + 1} 个是{who(p)[0]}（{who(p)[1]}）" for k, p in enumerate(ids))
    refs = [f"assets/gen/ref/a34_board_{g}.png"]
    if facing == "front34":
        view = "五个人都是" + FRONT34
        ref_txt = "参考图上面一排是五个人，每人三张：侧面、正面、背面。下面一排家具只用来说明游戏的镜头角度，不要画家具。"
    else:
        refs.append(f"assets/gen/ref/a34_front_{g}.png")
        view = ("五个人全都背对着我们，一张脸都不画，一只眼睛都看不到：" + BACK34 +
                "就像参考图里每个人的背面那张，只是整个人往右转了 45 度，后背斜对着我们、朝右上方的远处看去。")
        ref_txt = ("第一张参考图上面一排是五个人，每人三张：侧面、正面、背面；下面一排家具只用来说明游戏的镜头角度，不要画家具。"
                   "第二张参考图是同样五个人的四分之三侧前方，这次要画的是他们转过身去的样子。")
    return {
        "sheet": f"a34_lineup_{g}_{'front' if facing == 'front34' else 'back'}", "size": "2560x1536",
        "background": "#00FF00", "grid": "5x1", "refs": refs,
        "prompt": STYLE + "\n" + ref_txt +
        "\n画同样这五个人，从左到右排成一排，5 列 × 1 行，一格一个人，全身，两手自然垂在身体两侧，站直。" + names + "。"
        "\n" + view + "\n" + ANGLE +
        "\n每个人的发型、头饰、衣服款式和颜色、身材比例（头身比、胖瘦、驼背）和参考图里同一个人完全一样，同样粗细的深棕描边、同样的上色。"
        "头不要画得比参考图大。五个人脚底在同一高度，互相不接触，格子之间不画分隔线。背景是一整片纯绿色 #00FF00（绿幕），"
        "没有渐变；人物脚下不画影子、不画地面，鞋底下面直接就是绿色。人物身上一点绿色都不用。",
    }


JOINTS = mlp.JOINTS
NO_GREEN = mlp.NO_GREEN


def parts(pid, facing):
    w, look = who(pid)
    view = FRONT34 if facing == "front34" else BACK34
    if facing == "front34":
        head = "头连脖子，四分之三侧前方：脸朝右下，两只眼睛都看得见，靠右那只窄一点"
        shoe = "鞋子是四分之三侧前方看到的样子：鞋尖朝右下，看得到鞋面和一侧，不是正侧面的鞋，也不是正对着我们的鞋"
        torso = "上身的四分之三侧前方：胸口朝右下，看得到衣服的前襟和一侧，盘扣、襟边、围裙这些前面的细节在偏右的位置"
        arm = "从斜前方看"
    else:
        head = "头连脖子，四分之三侧后方：看到后脑勺的头发和头饰，右边露出一点脸颊和耳朵的轮廓，看不到眼睛"
        shoe = "鞋子是四分之三侧后方看到的样子：看得到鞋跟和一侧，鞋尖朝右上，不是正侧面的鞋"
        torso = "上身的四分之三侧后方：后背朝着我们、偏向右上，看得到衣服的后背和一侧，没有前襟的扣子"
        arm = "从斜后方看"
    body = ("把参考图里的这个人拆成 6 个部件，像做皮影的零件一样，画在一张图上，排成 3 行 2 列的格子，每格一个部件，居中，部件之间留出大片空白，"
            "互相不接触，格子之间不画分隔线。参考图第一张是这个人" + ("四分之三侧前方" if facing == "front34" else "四分之三侧后方") +
            "的样子，第二张是他的侧面；所有部件都照第一张的角度画：" + view + "脸、发型、头饰、衣服、颜色、描边粗细、上色方法和参考图一模一样，"
            "身材和参考图一样，不要画得更矮更胖。"
            f"第 1 行：左格是{head}（帽子、头巾、发髻、辫子都画在头上；脖子往下多画一截，不带衣领和肩膀）；右格是躯干：{torso}，"
            "只有从肩膀到胯部这一段，两个肩头画成圆润完整的布料（衣服把肩头整个包住，肩头没有洞），躯干上完全没有胳膊、没有手、没有袖子，"
            "肩膀两边不伸出任何袖管，胯部以下什么都没有。"
            f"第 2 行：左格是一条上臂（只有一条，{arm}，整段是袖子，从肩到肘），竖直朝下；右格是一条前臂连手（只有一条，袖子下半截加一只手），竖直朝下。"
            "第 3 行：左格是一条大腿（只有一条腿，不是一双，从胯到膝，裤腿），竖直朝下；右格是一条小腿连脚（只有一条腿、一只鞋，不是一双），"
            f"小腿竖直朝下，裤腿一直包到脚踝，{shoe}。大腿和小腿一样粗，接在一起时外轮廓是一条顺的直线。")
    extra = ""
    if pid == "adult_2":
        extra = ("长衫的拆法：躯干那块是长衫的上半截（到胯部）；长衫下摆分给两条腿：大腿那块是月白色长衫布包住的一段，小腿那块上半截还是月白色长衫布、"
                 "下面露出一点深色裤脚和黑布鞋。")
    if pid in ("adult_4", "adult_6"):
        extra = ("围裙的拆法：躯干那块带着围裙的上半截；围裙下半截分给大腿那块，大腿上盖着围裙布。" if facing == "front34"
                 else "从后面看围裙只露出腰后系的带子和结，画在躯干那块上。")
    if pid == "adult_3":
        extra = "坎肩没有袖子：躯干那块是米白衬褂外套着酱红坎肩，肩头是坎肩包住的圆肩；米白衬褂的袖子整段画在上臂和前臂上。"
    if pid == "adult_7":
        extra = ("麻花辫画在头那块上，从后脑垂下来，只画到肩膀下面一点，不要长过躯干。" if facing == "back34"
                 else "麻花辫在背后，从这个角度只在脖子后面露出一点，画在头那块上。药囊画在躯干那块的胯边。")
    if pid == "elder_1":
        extra = "长棉袄的拆法：躯干那块到胯部；棉袄下摆分给大腿那块，大腿上盖着灰蓝色棉袄布。白胡子画在头那块上。"
    if pid == "mother" and facing == "front34":
        extra = "深蓝短围裙画在躯干那块的下半截，只到胯部。"
    if pid in ("grandma", "grandpa", "elder_1", "elder_2"):
        extra += "老人的躯干微微前弓。"
    if pid == "child":
        extra += "孩子头身比 1:3，胳膊腿短而圆。小褂的袖子整段画在上臂那块上，躯干上一点袖子都不画。"
    return {"sheet": f"a_{pid}_{facing}_parts", "size": "1536x1536", "background": "#00FF00", "grid": "2x3",
            "refs": [f"assets/gen/ref/a_{pid}_{facing}_ref.png", f"assets/gen/ref/a_{pid}_ref.png"],
            "prompt": STYLE + "\n" + f"参考图是{w}：{look}。\n" + body + extra + mlp.SLIM + JOINTS +
            "再说一遍：第 3 行两格各只有一条腿、一只鞋，不要画成一条裤子或一双鞋；躯干两边没有袖子。" + NO_GREEN}


def prompts():
    jobs = [lineup(g, f) for g in GROUPS for f in ("front34", "back34")]
    for g, ids in GROUPS.items():
        for pid in ids:
            for f in ("front34", "back34"):
                jobs.append(parts(pid, f))
    data = json.loads(PROMPTS.read_text())
    names = {j["sheet"] for j in jobs}
    data = [d for d in data if d["sheet"] not in names] + jobs
    PROMPTS.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    print(len(jobs), "prompts")


def crops():
    """Cut each person out of its lineup cell (green key) -> ref/a_<id>_<facing>_ref.png; also a34_front_<g>.png
    (the front row, as the identity reference for the back lineup)."""
    for g, ids in GROUPS.items():
        for facing in ("front34", "back34"):
            src = GEN / f"inbox/a34_lineup_{g}_{'front' if facing == 'front34' else 'back'}.png"
            rows, row = 1, 0
            if not src.exists():
                src = GEN / f"inbox/a34_lineup_{g}.png"     # first try: 2 rows, only the front row came out right
                rows, row = 2, 0
                if facing != "front34" or not src.exists():
                    continue
            im = Image.open(src).convert("RGB")
            a = np.array(im).astype(int)
            W, H = im.size
            y0r, y1r = row * H // rows, (row + 1) * H // rows
            if facing == "front34":
                im.crop((0, y0r, W, y1r)).save(GEN / f"ref/a34_front_{g}.png")
            # people: the five biggest non-green blobs in the row (with small bits glued on by closing), left to right
            from scipy import ndimage
            c = a[y0r:y1r]
            fg = ~((c[..., 1] > 110) & (c[..., 1] > c[..., 0] + 40) & (c[..., 1] > c[..., 2] + 40))
            lab, n = ndimage.label(ndimage.binary_closing(fg, iterations=6))
            sizes = ndimage.sum(fg, lab, range(1, n + 1))
            big = sorted(np.argsort(sizes)[-5:] + 1, key=lambda i: np.nonzero((lab == i).any(0))[0][0])
            for k, pid in enumerate(ids):
                sl = ndimage.find_objects((lab == big[k]).astype(int))[0]
                m = lab == big[k]
                rgba = np.dstack([c[..., :3], np.where(m, 255, 0)]).astype(np.uint8)
                person = Image.fromarray(rgba).crop((sl[1].start, sl[0].start, sl[1].stop, sl[0].stop))
                cell = Image.new("RGB", (person.width + 24, person.height + 24), (0, 255, 0))
                cell.paste(person, (12, 12), person)
                cell.save(GEN / f"ref/a_{pid}_{facing}_ref.png")
                print(pid, facing, cell.size)


if __name__ == "__main__":
    {"refs": refs, "prompts": prompts, "crops": crops}[sys.argv[1]]()
