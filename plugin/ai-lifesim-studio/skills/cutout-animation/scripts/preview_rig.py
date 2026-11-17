#!/usr/bin/env python3
"""不开 Godot，先看拆件角色动起来什么样：站立图（关节点标红点）+ 每个动作一张 GIF + 一张帧表。

用法：
  python3 preview_rig.py assets/chars/hero/hero.rig.json --anims references/anims.humanoid_side.json --out qa/rig_preview/hero
  python3 preview_rig.py ... --only walk,attack --fps 12 --scale 2

输出：
  rest.png         站立姿势，红点是每个部件的关节点：红点要落在肩、肘、胯、膝、脖子上
  <动作>.gif       循环播放的动作
  <动作>_sheet.png 一个动作的全部帧排成一行，逐帧看接缝
画法和 build_godot_rig.py 生成的场景是同一套（cutout_lib.py），这里对了，Godot 里也对。
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from cutout_lib import bounds, image_of, load_json, pose_at, render  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rig")
    ap.add_argument("--anims", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only")
    ap.add_argument("--fps", type=int, default=12)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--bg", default="#E8E4DA", help="预览底色；GIF 不支持半透明，用一个接近游戏地面的颜色")
    a = ap.parse_args()

    rig_path = Path(a.rig)
    rig = load_json(rig_path)
    base = rig_path.parent
    anims = load_json(a.anims)["animations"]
    if a.only:
        anims = {k: v for k, v in anims.items() if k in a.only.split(",")}
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    images = {p["id"]: image_of(rig, p, base) for p in rig["parts"]}

    # 所有动作的所有帧一起算外框，画布大小一致，GIF 不会跳
    frames_of = {}
    poses = [{}]
    for name, an in anims.items():
        n = max(2, round(an["length"] * a.fps))
        ts = [an["length"] * i / (n if an.get("loop") else n - 1) for i in range(n)]
        frames_of[name] = [pose_at(rig, an, t) for t in ts]
        poses += frames_of[name]
    lo, hi = bounds(rig, poses)
    pad = 12
    s = a.scale
    canvas = (int((hi[0] - lo[0]) * s) + pad * 2, int((hi[1] - lo[1]) * s) + pad * 2)
    origin = (pad - lo[0] * s, pad - lo[1] * s)
    bg = Image.new("RGBA", canvas, a.bg)

    rest = render(rig, base, {}, canvas, origin, s, images, dots=True)
    Image.alpha_composite(bg, rest).convert("RGB").save(out / "rest.png")
    print(f"站立图：{out / 'rest.png'}")
    for name, poses in frames_of.items():
        fr = [Image.alpha_composite(bg, render(rig, base, p, canvas, origin, s, images)).convert("RGB")
              for p in poses]
        fr[0].save(out / f"{name}.gif", save_all=True, append_images=fr[1:],
                   duration=int(1000 / a.fps), loop=0, disposal=2)
        sheet = Image.new("RGB", (canvas[0] * len(fr), canvas[1]), a.bg)
        for i, f in enumerate(fr):
            sheet.paste(f, (i * canvas[0], 0))
        sheet.save(out / f"{name}_sheet.png")
        print(f"{name}：{len(fr)} 帧 → {out / (name + '.gif')}")


if __name__ == "__main__":
    main()
