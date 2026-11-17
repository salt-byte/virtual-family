#!/usr/bin/env python3
"""数文风：给参考小说的样本和我们的成稿各数一遍，对照着看差在哪。

用法：
    python3 voice_stats.py <文件或目录> [更多路径]        # 每个文件一行，最后一行合计
    python3 voice_stats.py --total <文件或目录> ...       # 只出合计

扫 .md .txt .yarn。数的是：
    字数        汉字数
    句长        平均每句多少汉字（按。！？…和换行断句）
    短句        ≤15 字的句子占比
    长句        ≥50 字的句子占比
    句号/逗号    句号类（。！？）和逗号的比；肘击指令要句号比逗号多
    破折号      每千字几处（人写的约 0.8，Claude 约 4）
    冒号        每千字几处
    对白        引号（“”「」）里的字占全部汉字的比例；.yarn 的「名字: 台词」也算对白
    段长        平均每段多少汉字
"""
import os
import re
import sys

EXTS = {".md", ".txt", ".yarn"}
CJK = re.compile(r"[一-鿿]")
SENT_END = re.compile(r"[。！？!?…]+|\n")
QUOTED = re.compile(r"“[^”]*”|「[^」]*」")
YARN_LINE = re.compile(r"^\s*[^\s:：<>#\-][^:：<>#]{0,19}[:：]\s*(.*)$")


def stats(text, yarn=False):
    lines = text.splitlines()
    if yarn:
        lines = [l for l in lines if not re.match(r"^\s*(?:title:|tags:|position:|---|===|//|<<)", l)]
    body = "\n".join(l for l in lines if not l.lstrip().startswith(("#", "|", "```")))
    cjk = len(CJK.findall(body))
    if cjk == 0:
        return None
    sents = [s for s in SENT_END.split(body) if CJK.search(s)]
    lens = [len(CJK.findall(s)) for s in sents]
    paras = [p for p in (body.splitlines() if yarn else re.split(r"\n\s*\n", body)) if CJK.search(p)]   # .yarn 一行一段
    quoted = sum(len(CJK.findall(m)) for m in QUOTED.findall(body))
    if yarn:
        for l in lines:
            m = YARN_LINE.match(l)
            if m and not QUOTED.search(l):
                quoted += len(CJK.findall(m.group(1)))
    ends = len(re.findall(r"[。！？!?]", body))
    commas = body.count("，") + body.count(",")
    return {
        "字数": cjk,
        "句长": sum(lens) / len(lens) if lens else 0,
        "短句%": 100 * sum(1 for n in lens if n <= 15) / len(lens) if lens else 0,
        "长句%": 100 * sum(1 for n in lens if n >= 50) / len(lens) if lens else 0,
        "句号/逗号": ends / commas if commas else float(ends),
        "破折号/千字": body.count("——") * 1000 / cjk,
        "冒号/千字": (body.count("：") + body.count(":")) * 1000 / cjk,
        "对白%": 100 * min(quoted, cjk) / cjk,
        "段长": cjk / len(paras) if paras else cjk,
        "_text": body,
    }


def collect(paths):
    out = []
    for p in paths:
        if os.path.isfile(p):
            out.append(p)
            continue
        for root, dirs, names in os.walk(p):
            # 跳过 . 和 _ 开头的目录：refs/_source 放整本书、refs/_old 放换下来的旧样本，都不算样本
            dirs[:] = sorted(d for d in dirs if not d.startswith((".", "_")))
            out += [os.path.join(root, n) for n in sorted(names) if os.path.splitext(n)[1].lower() in EXTS]
    return out


COLS = ["字数", "句长", "短句%", "长句%", "句号/逗号", "破折号/千字", "冒号/千字", "对白%", "段长"]


def row(name, s):
    cells = [f"{s[c]:.0f}" if c == "字数" else f"{s[c]:.1f}" for c in COLS]
    return f"| {name} | " + " | ".join(cells) + " |"


def main(argv):
    only_total = "--total" in argv
    paths = [a for a in argv[1:] if a != "--total"]
    if not paths:
        print(__doc__)
        return 2
    results = []
    yarn_text, plain_text = [], []
    for f in collect(paths):
        try:
            text = open(f, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        is_yarn = f.endswith(".yarn")
        s = stats(text, yarn=is_yarn)
        if s:
            results.append((os.path.basename(f), s))
            (yarn_text if is_yarn else plain_text).append(text)
    if not results:
        print("没找到含中文的 .md / .txt / .yarn。")
        return 2
    print("| 文件 | " + " | ".join(COLS) + " |")
    print("|---|" + "---|" * len(COLS))
    if not only_total:
        for name, s in results:
            print(row(name, s))
    parts = []
    if plain_text:
        parts.append(stats("\n\n".join(plain_text)))
    if yarn_text:
        parts.append(stats("\n\n".join(yarn_text), yarn=True))
    if len(parts) == 1:
        print(row("**合计**", parts[0]))
    else:
        total = sum(p["字数"] for p in parts)
        merged = {c: sum(p[c] * p["字数"] for p in parts) / total for c in COLS}
        merged["字数"] = total
        print(row("**合计**", merged))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
