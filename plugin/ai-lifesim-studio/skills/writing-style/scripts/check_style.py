#!/usr/bin/env python3
"""文风检查：按 writing-style（「肘击指令」，作者将生）的禁用语录扫文字。

用法：
    python3 check_style.py <项目根或文件> [更多路径]

给目录时扫里面的 .yarn .md .json .csv .txt .html（跳过 .git .godot addons node_modules site 等，
以及由 .md / outline.json 生成的页面：剧情谱、设计总览、项目主页）。
每处命中按语境分三种：
    旁白：.yarn 里没有说话人的文字行、.csv / .json 里的文字、.txt、.html 里去掉标签后的文字（原型、手写页面）
    对白：.yarn 的「名字: 台词」和「-> 选项」、任何文件里「」“”引号内的话
    文档：.md 里引号外的文字
同一条规则在不同语境里可能是「禁用」或「待判」：人物自己说「不是我，是他」是口语，旁白和文档里这么写就是八股。

输出：禁用 N 条 / 待判 M 条，每条带 文件:行号、规则、片段、语境。
退出码：有禁用 → 1；没有禁用 → 0；没找到可查的文字 → 2（未评估，不等于通过）。
行尾带 style-ok 的行跳过（用于引用禁用语的审查报告、文风讨论）。
A 类（去 AI 味补充）的思路和实测数据参考 lieflat-less-ai-tone（larashero3-dotcom），规则为本插件自写。
项目里有 content/style/voice.md 且写了「放行：A5 A8」这类行时，那几条 A 类禁用降为待判。
"""
import json
import os
import re
import sys

EXTS = {".yarn", ".md", ".json", ".csv", ".txt", ".html"}
SKIP_DIRS = {".git", ".godot", ".import", "addons", "node_modules", "build", "dist",
             "export", "__pycache__", ".venv", "venv", ".claude", ".github", "site"}
SKIP_FILES = {"package.json", "package-lock.json", "CREDITS.md", "LICENSE.md",
              "story.html", "story.fragment.html", "design_overview.html", "page.html"}   # 生成的页面：原文已在 .md / outline.json 里扫过
CJK = re.compile(r"[一-鿿]")

N = "旁白"
D = "对白"
M = "文档"
BAN = "禁用"
WARN = "待判"

# (编号, 名称, 正则, {语境: 等级})；某语境不在字典里 = 该语境不查
_ALL_BAN = {N: BAN, D: BAN, M: BAN}
_SPOKEN_OK = {N: BAN, D: WARN, M: BAN}
RULES = [
    ("S1", "不是……而是……", r"(?<!是)不是[^。！？!?\n]{0,40}?而是", _ALL_BAN),
    ("S1", "并非……而是……", r"并非[^。！？!?\n]{0,40}?而是", _ALL_BAN),
    ("S1", "不在于……而在于……", r"不在于[^。！？!?\n]{0,40}?而在于", _ALL_BAN),
    ("S1", "不是……，是……", r"(?<!是)不是[^。！？!?\n，,；;]{1,25}[，,；;]\s*(?:就|才|只|正|都|也|倒)?是(?![否非不])", _SPOKEN_OK),
    ("S1", "不是……。是……（隔着句号）", r"(?<!是)不是[^。！？!?\n]{1,25}[。！？!?]\s*(?:而|就|才|只|正|都|也|倒)?是(?![否非不])", _SPOKEN_OK),
    ("S1", "不是……——是……（隔着破折号）", r"(?<!是)不是[^。！？!?\n]{1,25}——\s*(?:它|这|那|他|她|而)?(?:就|才|只|正)?是(?![否非不])", _SPOKEN_OK),
    ("S1", "与其说……不如说……", r"与其说[^。！？!?\n]{0,40}?不如说", _SPOKEN_OK),
    ("S2", "不仅……更……", r"不仅(?:仅)?[^。！？!?\n]{0,40}?更", _ALL_BAN),
    ("S2", "不只是 / 不单是 / 不止是……更……", r"不(?:只|单|止)(?:是)?[^。！？!?\n]{0,40}?更", _ALL_BAN),
    ("S2", "不仅（看是否在强行升华）", r"不仅(?:仅)?(?![^。！？!?\n]{0,40}?更)", {N: WARN, D: WARN, M: WARN}),
    ("S2", "从X到Y，从……/再到……", r"从[^，,。！？!?\n]{1,12}到[^，,。！？!?\n]{1,12}[，,、；;]\s*(?:从|再到)", _ALL_BAN),
    ("S2", "从X到Y收尾（看是否在强行升华）", r"从[^，,。！？!?\n]{1,8}到[^，,。！？!?\n]{1,8}[。！？!?]", {N: WARN, M: WARN}),
    ("S3", "一方面……另一方面……", r"一方面[^\n]{0,80}?另一方面", _ALL_BAN),
    ("S3", "另一方面（论文腔）", r"(?<!一方面)另一方面", {N: WARN, M: WARN}),
    ("S4", "说教引导", r"值得注意的是|值得一提的是|需要指出的是|毫无疑问|可想而知|不言而喻|显而易见|众所周知|不可否认", _SPOKEN_OK),
    ("M1", "泛滥比喻：锋利的刀", r"(?:像|如|似|仿佛|宛如|犹如)(?:同)?一把(?:锋利的|锐利的)?(?:刀|利刃|匕首|尖刀)", _ALL_BAN),
    ("M1", "泛滥比喻：石子投入湖面", r"(?:像|如|似|仿佛|宛如|犹如)(?:同)?一(?:颗|枚|块)石子|石子(?:投入|落入|掉进|丢进)(?:了)?(?:平静的)?(?:湖|水)", _ALL_BAN),
    ("M1", "泛滥比喻：重锤", r"(?:像|如|似|仿佛|宛如|犹如)(?:同)?一(?:记|柄|把)重锤", _ALL_BAN),
    ("M1", "泛滥比喻：潮水", r"(?:像|如|似|仿佛|宛如|犹如)(?:同)?潮水|潮水(?:般|一般|一样)(?:地)?(?:涌|袭|漫|席卷)", _ALL_BAN),
    ("M2", "AI 高频细节：第 X 颗纽扣 / 个街角 / 缕阳光 / 帧", r"第[一二三四五六七八九十百千两几\dXxＸ]+(?:颗(?:纽扣|扣子)|个街角|缕(?:阳光|光|月光|晨光)|帧(?:画面)?)", _ALL_BAN),
    ("M2", "AI 高频细节：第 X 只 / 根 / 道……（数到第几个，看是不是在凑细节）",
     r"第[一二三四五六七八九十百千两几\d]+(?:只|根|道|片|块|级|扇|盏|声|口|粒|棵|条|级台阶)", {N: WARN, D: WARN}),
    ("M3", "上帝视角：永远不会知道", r"永远(?:也)?不会知道", _SPOKEN_OK),
    ("M3", "上帝视角：X 不知道的是", r"不知道的是", _SPOKEN_OK),
    ("M3", "上帝视角：殊不知", r"殊不知", {N: WARN, M: WARN}),
    ("E1", "结尾总结", r"综上所述|总而言之|总的来说|总结来说|一言以蔽之", _SPOKEN_OK),
    ("E1", "「最后，」开头的总结", r"(?:^|(?<=[。！？!?\n]))\s*(?:最后|最终)[，,]", {N: WARN, M: WARN}),
    ("E1", "句首「总之，」总结", r"(?:^|(?<=[。！？!?\n\s]))总之(?=[，,])", {N: BAN, M: BAN}),
    ("E1", "总之", r"总之", {N: WARN, M: WARN}),
    # A 类：去 AI 味补充。思路和实测数据参考 lieflat-less-ai-tone（larashero3-dotcom），规则为本插件自写
    ("A1", "空转起手（说白了 / 说穿了 / 先说结论）", r"说白了|说穿了|先说结论", _SPOKEN_OK),
    ("A2", "冒号提示语（删掉提示语，直接写内容）",
     r"(?:一句话总结|一句话概括|核心是|关键在于|原因如下|本质上|换句话说|简单来说)[：:]", {N: BAN, M: BAN}),
    ("A3", "顿号连串三项以上（能概括就概括，不能就换掉其中一项的句法）", r"[^、，。！？!?\n；;：:]{1,12}(?:、[^、，。！？!?\n；;：:]{1,12}){2,}", {N: WARN}),
    ("A4", "拟人喻体（像一位导师 / 秘书 / 助手……写它实际做了什么）",
     r"(?:像|相当于|如同|好比|宛如)(?:是)?(?:一位|一个|一名)[^，,。！？!?\n]{0,8}(?:导师|秘书|助手|顾问|管家|审查员|实习生|向导|守护者|引路人)", {N: BAN, M: BAN, D: WARN}),
    ("A5", "翻译腔：当……时，（删掉当和时）", r"(?:^|(?<=[。！？!?\n，,]))\s*当[^。！？!?\n，,]{2,30}时[，,]", {N: WARN, M: WARN}),
    ("A5", "翻译腔：对于……来说 / 就……而言（对象直接放到句首）", r"(?:对于|对)[^。！？!?\n，,]{1,15}(?:来说|而言)|就[^。！？!?\n，,]{1,12}而言", {N: WARN, M: WARN}),
    ("A5", "翻译腔：句首连接词当路标（然而 / 此外 / 因此 / 与此同时 / 换言之）",
     r"(?:^|(?<=[。！？!?\n]))\s*(?:然而|此外|因此|与此同时|换言之|除此之外)[，,]", {N: WARN, M: WARN}),
    ("A5", "翻译腔：这意味着 / 这表明 / 这说明（并进前一句）", r"(?:^|(?<=[。！？!?\n]))\s*这(?:意味着|表明|说明)", {N: WARN, M: WARN}),
    ("A6", "名词化（进行了……的优化 / 实现了……的提升，恢复动词）",
     r"(?:进行|实现|完成)(?:了对?|对)[^。！？!?\n，,]{0,10}的(?:优化|提升|改进|调整|升级|改善|探索|分析|梳理)", {N: BAN, M: WARN}),
    ("F1", "直说情绪（换成动作、物、环境）",
     r"(?:感到|感觉到?|觉得|心里|内心|心中)(?:了)?(?:一阵|一丝|一股|一种|很|非常|十分|无比|格外|有些|有点|莫名的?|深深的?)?(?:的)?"
     r"(?:悲伤|孤独|愤怒|难过|伤心|痛苦|绝望|恐惧|害怕|开心|快乐|幸福|失落|寂寞|焦虑|紧张|愧疚|欣慰|无助|委屈|悲哀|悲凉|心酸)",
     {N: BAN, M: WARN}),
]
COMPILED = [(rid, name, re.compile(rx), lv) for rid, name, rx, lv in RULES]
BIBLE_JARGON = re.compile(r"中心张力|行为逻辑|命门|独立生活|弧线|钩子强度|推进包|\bfacts\b|停靠点 ?A0|〔第 ?\d+[–-]?\d* ?[回章]〕")

HEAD_NUM = re.compile(r"^#{1,6}\s*(?:\*\*)?(?:第?[一二三四五六七八九十]+[、．.]|第[一二三四五六七八九十]+[，,、\s])")
LIST_INTRO = re.compile(r"几种|几个|几点|几条|几项|几类|以下|如下|包括|这些|通常有|主要有")
LIST_ITEM = re.compile(r"^(?:[-*+]\s|\d+[.)、]\s?|\|)")
DASH_LIMIT = 2.0   # 每千字破折号上限：人写的约 0.8，Claude 约 4（lieflat-less-ai-tone 实测）

QUOTE_PAIRS = [("「", "」"), ("“", "”"), ("『", "』")]


def quoted_spans(text):
    """返回 text 里引号内的区间（不含引号本身）。"""
    spans = []
    for o, c in QUOTE_PAIRS:
        start = None
        for i, ch in enumerate(text):
            if ch == o and start is None:
                start = i + 1
            elif ch == c and start is not None:
                spans.append((start, i))
                start = None
    return spans


def in_spans(pos, spans):
    return any(a <= pos < b for a, b in spans)


YARN_SKIP = re.compile(r"^\s*(?:title:|tags:|position:|color:|group:|---|===|//|<<)")
YARN_SPEAKER = re.compile(r"^\s*([^\s:：<>#\-][^:：<>#]{0,19})[:：]\s*(.*)$")
YARN_OPTION = re.compile(r"^\s*->\s*(.*)$")
YARN_INLINE = re.compile(r"<<[^>]*>>|#[^\s#]+|\{[^}]*\}")


def yarn_segments(line):
    """把一行 Yarn 切成 (文字, 语境)。返回 [] 表示这一行不查。"""
    if YARN_SKIP.match(line):
        return []
    m = YARN_OPTION.match(line)
    if m:
        return [(YARN_INLINE.sub("", m.group(1)), D)]
    m = YARN_SPEAKER.match(line)
    if m and CJK.search(m.group(2) or ""):
        return [(YARN_INLINE.sub("", m.group(2)), D)]
    text = YARN_INLINE.sub("", line)
    return [(text, N)] if CJK.search(text) else []


JSON_STR = re.compile(r'"((?:[^"\\]|\\.)*)"')


def json_segments(line):
    out = []
    for m in JSON_STR.finditer(line):
        s = m.group(1)
        if CJK.search(s):
            out.append((s, N))
    return out


def scan_text(text, base_ctx, hits, path, lineno, prose=True):
    spans = quoted_spans(text)
    seen = set()
    banned = {}
    for rid, name, rx, levels in COMPILED:
        for m in rx.finditer(text):
            ctx = base_ctx
            if ctx != D and in_spans(m.start(), spans):
                ctx = D
            level = levels.get(ctx)
            if rid == "A3" and not prose:   # 顿号罗列只查成段的文字（.yarn .txt），数据和提示词里的清单不管
                continue
            if not level:
                continue
            key = (m.start(), rid)
            if key in seen:
                continue
            seen.add(key)
            if level == WARN and any(a <= m.start() < b for a, b in banned.get(rid, [])):
                continue  # 同一处已按同类规则判了禁用，不再重复列待判
            if level == BAN:
                banned.setdefault(rid, []).append((m.start(), m.end()))
            a = max(0, m.start() - 12)
            b = min(len(text), m.end() + 12)
            snippet = ("…" if a > 0 else "") + text[a:b].strip() + ("…" if b < len(text) else "")
            hits.append({"level": level, "path": path, "line": lineno, "rule": f"{rid} {name}",
                         "ctx": ctx, "snippet": snippet})


def scan_file(path, rel, hits):
    ext = os.path.splitext(path)[1].lower()
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (UnicodeDecodeError, OSError):
        return False
    if not any(CJK.search(l) for l in lines):
        return False
    in_fence = False
    in_style = None
    num_heads = []
    dash_count = [0]
    cjk_count = [0]
    is_bible = os.path.basename(path) == "bible.md"
    in_sources = False
    for i, line in enumerate(lines, 1):
        if "style-ok" in line:
            continue
        if is_bible:   # 故事圣经给人读：正文不许用插件术语、不许夹出处标签（「来源」一节除外）
            if line.startswith("## "):
                in_sources = line.strip() in ("## 来源", "## 附：资料")
            if not in_sources and not line.lstrip().startswith("```"):
                for m in BIBLE_JARGON.finditer(line):
                    hits.append({"level": BAN, "path": rel, "line": i, "rule": "B1 圣经正文用了插件术语 / 出处标签（换成平常话，出处挪到「来源」）",
                                 "ctx": M, "snippet": line.strip()[:60]})
        if ext == ".md":
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            segs = [(line, M)]
        elif ext == ".yarn":
            segs = yarn_segments(line)
        elif ext == ".json":
            segs = json_segments(line)
        elif ext == ".html":
            low = line.lower()
            if "<style" in low or "<!--" in low:
                in_style = "-->" if "<!--" in low and "-->" not in low[low.find("<!--"):] else ("</style>" if "<style" in low else None)
                if in_style is None:
                    line = re.sub(r"<!--.*?-->", " ", line)
            if in_style:
                if in_style in low:
                    in_style = None
                continue
            text = re.sub(r"\s//\s.*$", " ", line)          # 代码注释不算给玩家看的字
            text = re.sub(r"<[^>]*>", " ", text)
            segs = [(text, N)] if CJK.search(text) else []
        else:  # .csv .txt
            segs = [(line, N)]
        if ext == ".md":
            hm = HEAD_NUM.match(line)
            if hm:
                num_heads.append(i)
            elif line.startswith("#"):
                if len(num_heads) < 3:
                    num_heads.clear()
            st = line.strip()
            nxt = lines[i].lstrip() if i < len(lines) else ""
            if st.endswith(("：", ":")) and not st.startswith(("#", "-", "*", "|", ">")) and LIST_ITEM.match(nxt) and not LIST_ITEM.match(st) and len(CJK.findall(st)) <= 25 and LIST_INTRO.search(st):
                hits.append({"level": WARN, "path": rel, "line": i, "rule": "A2 空转句引出列表（这句写成有内容的判断，或删掉让列表直接接上文）",
                             "ctx": M, "snippet": st[:40]})
        for text, ctx in segs:
            if ctx != D:
                dash_count[0] += text.count("——")
                cjk_count[0] += len(CJK.findall(text))
            if CJK.search(text):
                scan_text(text, ctx, hits, rel, i, prose=ext in (".yarn", ".txt"))
                if ext in (".yarn", ".csv", ".html") and "「" in text:   # 给玩家看的字：简体中文用“”
                    k = text.index("「")
                    hits.append({"level": WARN, "path": rel, "line": i, "rule": "Q1 引号用了「」：给玩家看的字用“”，台词写成「名字: 台词」放进对话框",
                                 "ctx": ctx, "snippet": text[max(0, k - 12):k + 16].strip()})
    if len(num_heads) >= 3:
        hits.append({"level": BAN, "path": rel, "line": num_heads[0], "rule": "A7 小标题用「一、二、三」通篇编号（删掉编号，留小标题文字）",
                     "ctx": M, "snippet": lines[num_heads[0] - 1].strip()[:40]})
    if cjk_count[0] >= 1000 and dash_count[0] >= 5 and dash_count[0] * 1000 / cjk_count[0] > DASH_LIMIT:
        hits.append({"level": WARN, "path": rel, "line": 1,
                     "rule": f"A8 破折号太密（每千字 {dash_count[0] * 1000 / cjk_count[0]:.1f} 处，人写的约 0.8；改成逗号、句号或完整句子，对白不算）",
                     "ctx": M, "snippet": f"全文 {dash_count[0]} 处"})
    return True


def collect(paths):
    files = []
    for p in paths:
        p = os.path.abspath(p)
        if os.path.isfile(p):
            files.append((p, os.path.basename(p)))
            continue
        for root, dirs, names in os.walk(p):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
            for n in sorted(names):
                if os.path.splitext(n)[1].lower() in EXTS and n not in SKIP_FILES:
                    full = os.path.join(root, n)
                    files.append((full, os.path.relpath(full, p)))
    return files


ALLOW_LINE = re.compile(r"^\s*[-*]?\s*放行[：:]\s*(.+)$")


def find_allow(paths):
    """往上找项目里的 content/style/voice.md，读它的「放行：A5 A8」行：参考小说本来就这么写的规则降成待判。
    S / M / E / F 类（肘击指令的禁用语录）不能放行。"""
    allow = set()
    for p in paths:
        d = os.path.abspath(p if os.path.isdir(p) else os.path.dirname(p))
        while True:
            v = os.path.join(d, "content", "style", "voice.md")
            if os.path.isfile(v):
                with open(v, encoding="utf-8") as f:
                    for line in f:
                        m = ALLOW_LINE.match(line)
                        if m:
                            allow |= {r for r in re.findall(r"\bA\d\b", m.group(1))}
                break
            if os.path.dirname(d) == d:
                break
            d = os.path.dirname(d)
    return allow


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 2
    hits = []
    scanned = 0
    for full, rel in collect(argv[1:]):
        if scan_file(full, rel, hits):
            scanned += 1
    allow = find_allow(argv[1:])
    for h in hits:
        if h["level"] == BAN and h["rule"].split()[0] in allow:
            h["level"] = WARN
            h["rule"] += "（voice.md 放行，看是否贴合参考小说）"
    print("文风检查（writing-style ·「肘击指令」，作者将生）")
    if scanned == 0:
        print("未评估：没找到含中文的 .yarn / .md / .json / .csv / .txt / .html。这不等于通过。")
        return 2
    bans = [h for h in hits if h["level"] == BAN]
    warns = [h for h in hits if h["level"] == WARN]
    print(f"禁用 {len(bans)} 条 · 待判 {len(warns)} 条 · 扫了 {scanned} 个文件")
    for title, group in (("禁用（改掉才交付）", bans), ("待判（逐条看：人物口语可留，旁白和文档里改掉）", warns)):
        if not group:
            continue
        print(f"\n{title}")
        for h in group:
            print(f"  {h['path']}:{h['line']}  [{h['rule']}]  {h['snippet']}  （{h['ctx']}）")
    return 1 if bans else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
