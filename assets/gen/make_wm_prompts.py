#!/usr/bin/env python3
"""Prompts for the white-model people (the family other than the father, whose four entries
were tuned by hand and are the pattern for these). Per person four sheets in prompts.json:
p_<who>_front34, p_<who>_front34_parts, p_<who>_back34, p_<who>_back34_parts.

  python3 assets/gen/make_wm_prompts.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROMPTS = ROOT / "assets/gen/prompts.json"

STYLE = ("3D 卡通渲染风格的游戏角色素材，像家庭模拟经营游戏里等距视角的小人，和同一个游戏里的家具是一套：圆润厚实、比例略夸张的玩具感造型，"
         "头大身子短，手脚圆滚滚；柔和的全局光照和环境光遮蔽，有柔和的明暗过渡、缝隙和凹处略暗、顶面略亮，有淡淡的高光；材质简化：粗布衣服看得出布纹和几道衣褶，"
         "洗得发旧、略微褪色，皮肤是光滑的暖肤色；颜色偏旧、饱和度中等偏低。光从左上方来，左前面亮、右前面略暗。不描边，不是手绘平涂，不是写实照片，不要像素风，不要水墨。")
FACE = "脸是简单可爱的卡通脸：两只黑亮的圆眼睛、淡淡的腮红、一个小鼻子、微微笑着的嘴，眉毛细细的、颜色淡、平平的，神情温和{face}。"
BG = "背景是一整片均匀的浅灰白色 #F0F0F0，没有渐变；不画地面、不画投影、不画文字、不画边框、不画分隔线、不画闪光和小星星。"
CLAY = ("严格照图1（一张白色粘土模型）的形状、比例、视角和摆放来画：只给它上颜色、材质和一点小细节，不改轮廓、不改视角、不旋转、不增减部件，"
        "在画面里的位置和大小也和图1 一样。")
BROWS = "眉毛是两道很细很短的弧线，颜色淡，离眼睛远一些，眉尾往下弯，眉头不皱，是一张和气带笑的脸"

# who: what, look (the whole person), face (added to the face), hair_front / hair_back (the head part),
# jacket (its colour and cloth), front / back (the torso part), sleeve, cuff, trousers, ankle, shoe
PEOPLE = {
    "mother": dict(
        what="母亲：三十岁上下的女人",
        look="黑发光滑地往后梳，在脑后挽一个圆髻；橙棕色立领大襟袄，袖口翻出一道米白色的边；腰上系一条深蓝色短围裙，盖住肚子到胯；深灰蓝色的布裤，黑布鞋",
        face="，没有胡子，脸圆润柔和",
        hair_front="黑发光滑地往后梳，额前没有刘海，脑后露出一点圆髻",
        hair_back="黑发光滑地往后梳，脑后一个圆圆的发髻，髻上横插一根木簪",
        jacket="橙棕色立领大襟袄",
        front="上半截是橙棕色袄子，一道斜襟从领口斜到腋下；腰上一条深蓝色的围裙带子，带子下面是一片深蓝色短围裙，盖到下摆",
        back="后背一整片橙棕色布，腰上横着一条深蓝色的围裙带子，在后腰打一个小结；没有围裙布",
        sleeve="橙棕色", cuff="米白色", trousers="深灰蓝色", ankle="裤脚收口，露出一点白袜", shoe="黑布鞋"),
    "grandpa": dict(
        what="爷爷：七十岁上下的老汉",
        look="花白的短发，下巴上一撮花白的山羊胡，眼角和额头有几道皱纹；深棕色立领对襟旧棉袄，厚墩墩的，胸前一排盘扣，袖口翻出一道灰褐色的边；黑布裤，黑布鞋；不拿拐杖",
        face="；两道花白的眉毛，眼角有笑纹，是个和气的老人",
        hair_front="花白的短发，下巴上一撮花白的山羊胡，额头两三道浅浅的皱纹",
        hair_back="花白的短发，后脑勺圆圆的，没有头巾、没有帽子",
        jacket="深棕色立领对襟旧棉袄",
        front="深棕色棉袄的前面和一侧，厚墩墩的，胸前一排盘扣",
        back="后背一整片深棕色棉布，厚墩墩的，没有盘扣",
        sleeve="深棕色", cuff="灰褐色", trousers="黑色", ankle="裤脚收口", shoe="黑布鞋"),
    "grandma": dict(
        what="祖母：六十多岁的老太太",
        look="白发往后梳，在脑后挽一个小圆髻，眼角和额头有几道皱纹；豆沙紫褐色立领大襟夹袄，厚墩墩的，袖口翻出一道浅灰色的边；深灰色布裤，黑布鞋",
        face="，没有胡子；眼角有笑纹，是个慈祥的老太太",
        hair_front="白发往后梳，额前没有刘海，脑后露出一点小圆髻，额头两三道浅浅的皱纹",
        hair_back="白发往后梳，脑后一个小圆髻，髻上横插一根银簪",
        jacket="豆沙紫褐色立领大襟夹袄",
        front="豆沙紫褐色夹袄的前面和一侧，厚墩墩的，一道斜襟从领口斜到腋下，襟上两三粒盘扣",
        back="后背一整片豆沙紫褐色布，厚墩墩的，没有盘扣",
        sleeve="豆沙紫褐色", cuff="浅灰色", trousers="深灰色", ankle="裤脚收口", shoe="黑布鞋"),
    "child": dict(
        what="孩子：七八岁的小孩，三头身，头大，圆脸，胳膊腿短而圆",
        look="黑发，头顶左右各扎一个圆圆的小抓髻，系着红头绳，额前一排短短的刘海；明黄色立领小褂，袖口翻出一道米白色的边；深灰色布裤，黑布鞋",
        face="，没有胡子；脸蛋圆鼓鼓的，是个高兴的小孩",
        hair_front="黑发，头顶左右各一个圆圆的小抓髻，系着红头绳，额前一排短短的刘海",
        hair_back="黑发，头顶左右各一个圆圆的小抓髻，系着红头绳，后脑勺圆圆的",
        jacket="明黄色立领小褂",
        front="明黄色小褂的前面和一侧，一道斜襟从领口斜到腋下，襟上两粒盘扣",
        back="后背一整片明黄色布，没有盘扣",
        sleeve="明黄色", cuff="米白色", trousers="深灰色", ankle="裤脚收口", shoe="黑布鞋"),
}


def who_line(p):
    return "这个人是%s；%s。" % (p["what"], p["look"]) + FACE.format(face=p["face"])


def whole(who, p, facing):
    if facing == "front34":
        body = ("画这个人站着的样子，从斜上方往下看：身体转了 45 度，脸、胸口、脚尖都朝向画面的右下方，两条胳膊自然垂在身体两边。" + CLAY + BG
                + "\n图2 是同一个游戏里已经画好的一家人里的父亲：光照、明暗、材质的质感、做旧的程度、脸的画法和 3D 渲染风格都照图2，"
                  "这个人要像和图2 同一批做出来的 3D 玩具小人，没有任何描边线；但不画图2 里的那个人，发型、衣服、身材都按上面写的画，只画这一个人。")
        refs = ["assets/gen/ref/white_p_%s_front34.png" % who, "assets/gen/inbox/p_father_front34.png"]
    else:
        body = ("画这个人站着的背影，从斜上方往下看：背对着我们、朝画面的右上方站着，看到的是后脑勺、后背和脚后跟，看不到脸（最多露出一点右边的脸颊和耳朵），"
                "两条胳膊自然垂在身体两边。后脑勺：%s。衣服的后背：%s。" % (p["hair_back"], p["back"]) + CLAY + BG
                + "\n图2 是同一个人正面的样子：发型、衣服的颜色和材质、光照、3D 渲染风格都照图2，没有任何描边线；但这张画的是这个人的背面。")
        refs = ["assets/gen/ref/white_p_%s_back34.png" % who, "assets/gen/inbox/p_%s_front34.png" % who]
    return {"sheet": "p_%s_%s" % (who, facing), "size": "1536x1536", "background": "#F0F0F0", "refs": refs,
            "prompt": STYLE + "\n" + who_line(p) + "\n" + body}


def parts(who, p, facing):
    front = facing == "front34"
    view = "所有零件都是从斜上方看、朝向画面右下方的样子。" if front else "所有零件都是从斜上方看、背对着我们朝画面右上方的样子，看到的是背面。"
    if front:
        head = "头：看得到脸：两只又大又黑亮的圆眼睛、腮红、小鼻子、微笑的嘴；%s%s；%s。" % (BROWS, p["face"].split("；")[0], p["hair_front"])
        torso = "躯干：%s。" % p["front"]
    else:
        head = "头：看到的是后脑勺：%s，看不到脸，最多露出一只耳朵。" % p["hair_back"]
        torso = "躯干：%s，上面是立领的后面。" % p["back"]
    body = (
        "图2 是这个人已经画好的样子。把这个人拆成 4 个零件，像可以拆开的玩具小人的零件，照图1 的摆法画在一张图上。图1 是这 4 个零件的白色粘土模型："
        "上面一排是头（一个圆球，不带脖子）和躯干（立领里插着一小截脖子）；下面一排左边是一整条笔直下垂的胳膊，右边是一整条笔直站着的腿。"
        "严格照图1 的形状、大小、位置和视角来画：4 个零件各在图1 里原来的位置，一个不多一个不少，互相不接触，只给每个零件上颜色、材质和小细节，"
        "不改轮廓、不旋转、不把零件拼起来、不画完整的人。" + view + head + "头是一个圆球，下巴下面什么都没有，不画脖子。" + torso
        + "立领中间立着一小截肤色的脖子，脖子顶上是平的。躯干是一个上窄下宽的布桶，像一件没有袖子的坎肩：两边没有袖子、没有胳膊、没有球形的肩头，"
          "肩膀只是圆角的%s布料；下面没有腿。" % p["sleeve"]
        + "胳膊：从肩头到手是完整的一条，笔直下垂；整条是一只%s袖子，布料从上到下连续，中间没有接缝、没有关节、没有分段，肩头是鼓起的圆头；"
          "袖口一圈%s的翻边，下面一只肤色的手。" % (p["sleeve"], p["cuff"])
        + "腿：只画一条腿（单独一条，像一根柱子），不是一条裤子、不是两条腿并排、没有裤腰；从胯到脚是完整的一条，笔直；整条是%s裤腿，布料连续，"
          "中间没有接缝、没有分段，顶端是鼓起的圆头、实心的；%s，脚上一只%s。" % (p["trousers"], p["ankle"], p["shoe"])
        + "每个零件的颜色、材质、光照都和图2 里这个人身上对应的部位一模一样，没有任何描边线。" + BG)
    return {"sheet": "p_%s_%s_parts" % (who, facing), "size": "1536x1536", "background": "#F0F0F0",
            "refs": ["assets/gen/ref/white_p_%s_%s_parts.png" % (who, facing), "assets/gen/inbox/p_%s_%s.png" % (who, facing)],
            "prompt": STYLE + "\n" + who_line(p) + "\n" + body}


if __name__ == "__main__":
    book = json.loads(PROMPTS.read_text())
    new = [f(who, p, facing) for who, p in PEOPLE.items() for facing in ("front34", "back34") for f in (whole, parts)]
    names = {e["sheet"] for e in new}
    book = [e for e in book if e["sheet"] not in names] + new
    PROMPTS.write_text(json.dumps(book, ensure_ascii=False, indent=1))
    print("wrote", len(new), "prompts")
