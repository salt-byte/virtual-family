#!/usr/bin/env python3
"""调用户的生图 API 出图（asset-generation 用）。只用 Python 标准库：云端和用户自己的电脑上都能直接跑，不用装包。

用法（在项目根目录跑，或用 --root 指过去）：
  python3 gen_image.py --check                   测连通和密钥，不花钱
  python3 gen_image.py --batch hero_ref --n 3    同一条提示词出 3 张候选：hero_ref_a.png、_b、_c
  python3 gen_image.py --batch env_01            出 prompts.json 里 sheet=env_01 的那张
  python3 gen_image.py --all                     出所有 inbox 里还没有的
  python3 gen_image.py --batch env_01 --force    重生（旧图挪进 inbox/_old/）
  python3 gen_image.py --all --dry-run           只打印要发的请求，不花钱
  python3 gen_image.py --export-md               导出 prompts.md（退回手动出图时给用户）

用到的文件（路径相对项目根）：
  assets/gen/gen_config.json  服务、型号、接口地址、单价、预算。提交进仓库，里面不放密钥
  .env                        GEN_API_KEY=...。不提交，.gitignore 里要有 .env；也可以直接设环境变量 GEN_API_KEY
  assets/gen/prompts.json     每张图一条：sheet、prompt、size、refs、background、grid
  assets/gen/inbox/           出的图，文件名 = sheet 名
  assets/gen/usage.csv        每次调用记一行：时间、sheet、服务、型号、张数、估算花费、结果

provider（gen_config.json 的 provider）：
  openai   OpenAI 图像接口，或任何 OpenAI 兼容的中转站（改 base_url）。有参考图时走 /images/edits
  ark      火山方舟 Seedream（即梦、豆包同款）
  gemini   Google Gemini 图像（Nano Banana），尺寸按比例给
  sdwebui  本机 Stable Diffusion WebUI / Forge（启动时加 --api），不要密钥、不支持参考图，只能在用户电脑上跑

退出码：0 成功；1 服务报错（报错原样打出）；2 网络被拦或连不上；3 密钥或型号不对；4 预算到了；5 配置或提示词有错。
"""
import argparse
import base64
import csv
import datetime as dt
import json
import mimetypes
import os
import shutil
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

DEFAULT_BASE = {
    "openai": "https://api.openai.com/v1",
    "ark": "https://ark.cn-beijing.volces.com/api/v3",
    "gemini": "https://generativelanguage.googleapis.com/v1beta",
    "sdwebui": "http://127.0.0.1:7860",
}
GEMINI_RATIOS = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]


class GenError(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


# ---------- 配置 ----------

def load_env(root):
    """读项目根的 .env（KEY=VALUE 一行一个）。环境变量里已有的不覆盖。"""
    p = root / ".env"
    if not p.exists():
        return
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def load_config(root):
    p = root / "assets/gen/gen_config.json"
    if not p.exists():
        raise GenError(f"没有 {p}：照 asset-generation/references/gen_config.example.json 写一份", 5)
    cfg = json.loads(p.read_text(encoding="utf-8"))
    prov = cfg.get("provider")
    if prov not in DEFAULT_BASE:
        raise GenError(f"gen_config.json 的 provider 只能是 {', '.join(DEFAULT_BASE)}，现在是 {prov!r}", 5)
    if prov != "sdwebui" and not cfg.get("model"):
        raise GenError("gen_config.json 没写 model：去这家服务的文档页查当前的型号名，写进去", 5)
    cfg["base_url"] = (cfg.get("base_url") or DEFAULT_BASE[prov]).rstrip("/")
    return cfg


def api_key(cfg):
    if cfg["provider"] == "sdwebui":
        return ""
    k = os.environ.get(cfg.get("key_env", "GEN_API_KEY"), "")
    if not k:
        raise GenError("没有密钥：在项目根的 .env 写一行 GEN_API_KEY=...（.env 不提交），或设环境变量 GEN_API_KEY", 3)
    return k


def load_jobs(root):
    p = root / "assets/gen/prompts.json"
    if not p.exists():
        raise GenError(f"没有 {p}", 5)
    jobs = json.loads(p.read_text(encoding="utf-8"))
    seen = set()
    for j in jobs:
        if not j.get("sheet") or not j.get("prompt"):
            raise GenError(f"prompts.json 里有一条缺 sheet 或 prompt：{j}", 5)
        if j["sheet"] in seen:
            raise GenError(f"prompts.json 里 sheet 重名：{j['sheet']}", 5)
        seen.add(j["sheet"])
    return jobs


# ---------- HTTP ----------

def _ctx():
    ctx = ssl.create_default_context()
    for var in ("SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE"):
        f = os.environ.get(var)
        if f and Path(f).exists():
            ctx.load_verify_locations(f)
            break
    return ctx


def classify_net_error(e, url):
    host = urllib.parse.urlparse(url).hostname
    s = str(getattr(e, "reason", e))
    if "Tunnel connection failed" in s or "403" in s and "Forbidden" in s:
        return GenError(f"被网络拦了：这个环境不放行 {host}（云端会话默认只放行少数域名）。"
                        f"办法见 asset-generation 第 0 步：放行这个域名，或在用户电脑上跑", 2)
    if isinstance(getattr(e, "reason", None), ConnectionRefusedError) or "refused" in s.lower():
        return GenError(f"连不上 {host}：服务没开（本机 WebUI 要开着并带 --api 启动），或地址写错了", 2)
    if isinstance(getattr(e, "reason", None), socket.gaierror) or "Name or service not known" in s or "nodename" in s:
        return GenError(f"找不到 {host}：域名写错了，或这台机器的网络解析不了它", 2)
    if isinstance(getattr(e, "reason", None), (socket.timeout, TimeoutError)) or "timed out" in s:
        return GenError(f"连 {host} 超时：网络不通（国内连不上部分国外服务），或服务太慢", 2)
    return GenError(f"连 {host} 失败：{s}", 2)


def http(method, url, headers=None, body=None, timeout=300):
    """返回 (状态码, 响应字节)。HTTP 错误也返回，不抛；网络层的错误转成 GenError。"""
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_ctx() if url.startswith("https") else None) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as e:
        raise classify_net_error(e, url)


def post_json(url, headers, payload, retries=3):
    data = json.dumps(payload).encode("utf-8")
    h = {"Content-Type": "application/json", **headers}
    return _with_retry(lambda: http("POST", url, h, data), retries)


def post_multipart(url, headers, fields, files, retries=3):
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    for k, path in files:
        mime = mimetypes.guess_type(str(path))[0] or "image/png"
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{Path(path).name}"\r\n'
                     f'Content-Type: {mime}\r\n\r\n'.encode() + Path(path).read_bytes() + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    h = {"Content-Type": f"multipart/form-data; boundary={boundary}", **headers}
    return _with_retry(lambda: http("POST", url, h, b"".join(parts)), retries)


def _with_retry(fn, retries):
    for i in range(retries + 1):
        status, raw = fn()
        if status in (429, 500, 502, 503, 504) and i < retries:
            wait = 5 * (2 ** i)
            print(f"  服务返回 {status}，{wait} 秒后重试（第 {i + 1} 次）")
            time.sleep(wait)
            continue
        return status, raw


def raise_for(status, raw, what):
    if 200 <= status < 300:
        return
    text = raw.decode("utf-8", "replace")
    try:  # 服务的报错多半是 JSON，转义的中文还原成字
        text = json.dumps(json.loads(text), ensure_ascii=False)
    except ValueError:
        pass
    text = text[:800]
    if status in (401, 403):
        raise GenError(f"{what}：密钥不对或没开通（HTTP {status}）。服务原话：{text}", 3)
    if status == 404:
        raise GenError(f"{what}：接口地址或型号名不对（HTTP 404）。服务原话：{text}", 3)
    raise GenError(f"{what}：服务报错 HTTP {status}。服务原话：{text}", 1)


def fetch_url(url):
    status, raw = http("GET", url, timeout=120)
    raise_for(status, raw, "下载生成的图")
    return raw


def data_url(path):
    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(Path(path).read_bytes()).decode()


def parse_size(s):
    try:
        w, h = s.lower().split("x")
        return int(w), int(h)
    except Exception:
        return None


# ---------- 各家服务 ----------

def gen_openai(cfg, key, job, refs):
    base, model = cfg["base_url"], cfg["model"]
    hdr = {"Authorization": f"Bearer {key}"}
    fields = {"model": model, "prompt": job["prompt"], "n": 1}
    if job.get("size") or cfg.get("size"):
        fields["size"] = job.get("size") or cfg.get("size")
    if cfg.get("quality"):
        fields["quality"] = cfg["quality"]
    if job.get("background") == "transparent" and cfg.get("native_transparent"):
        fields["background"] = "transparent"
        fields["output_format"] = "png"
    fields.update(cfg.get("extra", {}))
    if refs:
        status, raw = post_multipart(f"{base}/images/edits", hdr, {k: str(v) for k, v in fields.items()},
                                     [("image[]", r) for r in refs])
    else:
        status, raw = post_json(f"{base}/images/generations", hdr, fields)
    raise_for(status, raw, "OpenAI 出图")
    d = json.loads(raw)["data"][0]
    return base64.b64decode(d["b64_json"]) if d.get("b64_json") else fetch_url(d["url"])


def gen_ark(cfg, key, job, refs):
    payload = {"model": cfg["model"], "prompt": job["prompt"], "response_format": "b64_json", "watermark": False}
    if job.get("size") or cfg.get("size"):
        payload["size"] = job.get("size") or cfg.get("size")
    if refs:
        payload["image"] = [data_url(r) for r in refs]
    payload.update(cfg.get("extra", {}))
    status, raw = post_json(f"{cfg['base_url']}/images/generations", {"Authorization": f"Bearer {key}"}, payload)
    raise_for(status, raw, "Seedream 出图")
    d = json.loads(raw)["data"][0]
    return base64.b64decode(d["b64_json"]) if d.get("b64_json") else fetch_url(d["url"])


def nearest_ratio(size):
    wh = parse_size(size or "")
    if not wh:
        return None
    r = wh[0] / wh[1]
    return min(GEMINI_RATIOS, key=lambda s: abs(int(s.split(":")[0]) / int(s.split(":")[1]) - r))


def gen_gemini(cfg, key, job, refs):
    parts = [{"inlineData": {"mimeType": mimetypes.guess_type(str(r))[0] or "image/png",
                             "data": base64.b64encode(Path(r).read_bytes()).decode()}} for r in refs]
    parts.append({"text": job["prompt"]})
    img_cfg = {}
    ratio = nearest_ratio(job.get("size") or cfg.get("size"))
    if ratio:
        img_cfg["aspectRatio"] = ratio
    if cfg.get("image_size"):
        img_cfg["imageSize"] = cfg["image_size"]
    gc = {"responseModalities": ["IMAGE"]}
    if img_cfg:
        gc["imageConfig"] = img_cfg
    payload = {"contents": [{"role": "user", "parts": parts}], "generationConfig": gc}
    payload.update(cfg.get("extra", {}))
    url = f"{cfg['base_url']}/models/{cfg['model']}:generateContent"
    status, raw = post_json(url, {"x-goog-api-key": key}, payload)
    raise_for(status, raw, "Gemini 出图")
    resp = json.loads(raw)
    imgs = []
    for c in resp.get("candidates", []):
        for p in (c.get("content") or {}).get("parts", []):
            d = p.get("inlineData") or p.get("inline_data")
            if d and d.get("data"):
                imgs.append(d["data"])
    if not imgs:
        why = [c.get("finishReason") for c in resp.get("candidates", [])] or resp.get("promptFeedback")
        raise GenError(f"Gemini 没返回图（{why}）：多半是内容审核拦了，或提示词没要求画图。服务原话：{json.dumps(resp, ensure_ascii=False)[:500]}", 1)
    return base64.b64decode(imgs[-1])


def gen_sdwebui(cfg, key, job, refs):
    if refs:
        print("  注意：sdwebui 不支持参考图，这张没带参考图出")
    w, h = parse_size(job.get("size") or cfg.get("size") or "1024x1024")
    payload = {"prompt": job["prompt"], "negative_prompt": cfg.get("negative_prompt", ""),
               "width": w, "height": h, "steps": cfg.get("steps", 28), "batch_size": 1}
    payload.update(cfg.get("extra", {}))
    status, raw = post_json(f"{cfg['base_url']}/sdapi/v1/txt2img", {}, payload)
    raise_for(status, raw, "SD WebUI 出图")
    return base64.b64decode(json.loads(raw)["images"][0].split(",", 1)[-1])


GEN = {"openai": gen_openai, "ark": gen_ark, "gemini": gen_gemini, "sdwebui": gen_sdwebui}


# ---------- 连通检查 ----------

def check(cfg):
    prov, base = cfg["provider"], cfg["base_url"]
    host = urllib.parse.urlparse(base).hostname
    try:
        key = api_key(cfg)
    except GenError as e:
        print(e)
        return e.code
    if prov == "openai":
        url, hdr = f"{base}/models", {"Authorization": f"Bearer {key}"}
    elif prov == "ark":
        url, hdr = f"{base}/models", {"Authorization": f"Bearer {key}"}
    elif prov == "gemini":
        url, hdr = f"{base}/models/{cfg['model']}", {"x-goog-api-key": key}
    else:
        url, hdr = f"{base}/sdapi/v1/sd-models", {}
    try:
        status, raw = http("GET", url, hdr, timeout=20)
    except GenError as e:
        print(e)
        return e.code
    text = raw.decode("utf-8", "replace")[:300]
    if status in (401, 403):
        print(f"连得上 {host}，但密钥不对或没开通（HTTP {status}）：{text}")
        return 3
    if prov == "gemini" and status == 404:
        print(f"连得上 {host}，但没有叫 {cfg['model']} 的型号：去 Gemini 文档页查当前型号名")
        return 3
    if 200 <= status < 300:
        print(f"连得上 {host}，WebUI 开着" if prov == "sdwebui" else f"连得上 {host}，密钥有效（{prov} · {cfg['model']}）")
        return 0
    # 有的服务没有「列型号」接口（返回 404 / 405）：能拿到 HTTP 回应就说明网络是通的，密钥等第一次出图才知道
    print(f"连得上 {host}（HTTP {status}）；这家服务没有免费的验密钥接口，第一次出图时才知道密钥对不对")
    return 0


# ---------- 预算和用量 ----------

USAGE_COLS = ["time", "sheet", "provider", "model", "images", "est_cost", "result"]


def usage_rows(root):
    p = root / "assets/gen/usage.csv"
    if not p.exists():
        return []
    return list(csv.DictReader(open(p, encoding="utf-8")))


def log_usage(root, row):
    p = root / "assets/gen/usage.csv"
    new = not p.exists()
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "a", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=USAGE_COLS)
        if new:
            w.writeheader()
        w.writerow(row)


def spent(root):
    rows = [r for r in usage_rows(root) if r.get("result") == "ok"]
    return sum(int(r["images"] or 0) for r in rows), sum(float(r["est_cost"] or 0) for r in rows)


def budget_ok(root, cfg, n):
    imgs, cost = spent(root)
    price = float(cfg.get("price_per_image") or 0)
    cur = cfg.get("currency", "")
    if cfg.get("budget") is not None and price and cost + n * price > float(cfg["budget"]) + 1e-9:
        raise GenError(f"预算到了：已花约 {cost:.2f}{cur}（{imgs} 张），再出 {n} 张要 {n * price:.2f}{cur}，"
                       f"上限 {cfg['budget']}{cur}。停下来问用户要不要加预算，不要自己改上限", 4)
    if cfg.get("max_images") is not None and imgs + n > int(cfg["max_images"]):
        raise GenError(f"张数到了：已出 {imgs} 张，上限 {cfg['max_images']} 张。停下来问用户要不要加", 4)


# ---------- 存图 ----------

def sniff_ext(b):
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if b[:3] == b"\xff\xd8\xff":
        return ".jpg"
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return ".webp"
    return ".png"


def save_image(inbox, name, data):
    ext = sniff_ext(data)
    try:  # 装了 Pillow 就统一存成 PNG；没装（在用户电脑上跑）就按原格式存，收图脚本都认
        from PIL import Image
        import io
        im = Image.open(io.BytesIO(data))
        dst = inbox / f"{name}.png"
        im.save(dst)
        return dst
    except Exception:
        dst = inbox / f"{name}{ext}"
        dst.write_bytes(data)
        return dst


def existing(inbox, name):
    return [p for p in inbox.glob(f"{name}.*") if p.is_file()]


def archive(inbox, name):
    old = inbox / "_old"
    for p in existing(inbox, name):
        old.mkdir(exist_ok=True)
        stamp = dt.datetime.now().strftime("%m%d-%H%M%S")
        shutil.move(str(p), str(old / f"{p.stem}_{stamp}{p.suffix}"))


# ---------- 主流程 ----------

def run_job(root, cfg, key, job, n, force, dry):
    inbox = root / "assets/gen/inbox"
    inbox.mkdir(parents=True, exist_ok=True)
    names = [job["sheet"]] if n == 1 else [f"{job['sheet']}_{chr(97 + i)}" for i in range(n)]
    if not force and all(existing(inbox, nm) for nm in names):
        print(f"{job['sheet']}：inbox 里已经有了，跳过（要重生加 --force）")
        return 0
    refs = [root / r for r in job.get("refs", [])]
    missing = [str(r) for r in refs if not r.exists()]
    if missing:
        raise GenError(f"{job['sheet']}：参考图不存在：{', '.join(missing)}", 5)
    if dry:
        print(f"[dry-run] {cfg['provider']} · {cfg.get('model', '')} · {job['sheet']} × {n} · "
              f"size={job.get('size') or cfg.get('size')} · 参考图 {len(refs)} 张 · background={job.get('background')}")
        print("  " + job["prompt"][:200].replace("\n", " ") + ("…" if len(job["prompt"]) > 200 else ""))
        return 0
    budget_ok(root, cfg, n)
    price = float(cfg.get("price_per_image") or 0)
    made = 0
    for nm in names:
        if existing(inbox, nm) and not force:
            continue
        t0 = time.time()
        try:
            data = GEN[cfg["provider"]](cfg, key, job, refs)
        except GenError as e:
            log_usage(root, {"time": dt.datetime.now().isoformat(timespec="seconds"), "sheet": nm,
                             "provider": cfg["provider"], "model": cfg.get("model", ""), "images": 0,
                             "est_cost": 0, "result": f"error {e.code}"})
            raise
        archive(inbox, nm)  # 新图到手才把旧图挪进 _old/：重生失败时旧图还在
        dst = save_image(inbox, nm, data)
        made += 1
        log_usage(root, {"time": dt.datetime.now().isoformat(timespec="seconds"), "sheet": nm,
                         "provider": cfg["provider"], "model": cfg.get("model", ""), "images": 1,
                         "est_cost": f"{price:.4f}", "result": "ok"})
        print(f"{nm} → {dst.relative_to(root)}（{time.time() - t0:.0f} 秒）")
    return made


def export_md(root, jobs):
    out = root / "assets/gen/prompts.md"
    lines = ["# 生图提示词", "",
             "每条在你的生图工具里出一张，存成标题里的文件名，放进 `assets/gen/inbox/`。带参考图的，把列出的参考图一起传上去。", ""]
    for j in jobs:
        lines += [f"## {j['sheet']}.png", ""]
        meta = [f"尺寸 {j['size']}" if j.get("size") else "", f"参考图：{', '.join(j['refs'])}" if j.get("refs") else ""]
        if any(meta):
            lines += ["　".join(m for m in meta if m), ""]
        lines += ["```", j["prompt"], "```", ""]
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"写好 {out.relative_to(root)}，{len(jobs)} 条")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="项目根目录")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--batch", nargs="+", metavar="SHEET")
    g.add_argument("--all", action="store_true")
    g.add_argument("--export-md", action="store_true")
    ap.add_argument("--n", type=int, default=1, help="同一条提示词出几张候选（最多 4）")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    load_env(root)
    try:
        if a.export_md:
            export_md(root, load_jobs(root))
            return 0
        cfg = load_config(root)
        if a.check:
            return check(cfg)
        jobs = load_jobs(root)
        if a.batch:
            by = {j["sheet"]: j for j in jobs}
            bad = [s for s in a.batch if s not in by]
            if bad:
                raise GenError(f"prompts.json 里没有：{', '.join(bad)}", 5)
            todo = [by[s] for s in a.batch]
        else:
            todo = jobs
        n = max(1, min(4, a.n))
        key = "" if a.dry_run else api_key(cfg)
        total = sum(run_job(root, cfg, key, j, n, a.force, a.dry_run) for j in todo)
        if not a.dry_run:
            imgs, cost = spent(root)
            cur = cfg.get("currency", "")
            tail = f"，预算上限 {cfg['budget']}{cur}" if cfg.get("budget") is not None else ""
            print(f"这次出了 {total} 张。项目累计 {imgs} 张，约 {cost:.2f}{cur}{tail}")
        return 0
    except GenError as e:
        print(f"✗ {e}")
        return e.code


if __name__ == "__main__":
    sys.exit(main())
