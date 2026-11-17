#!/usr/bin/env python3
"""拆件角色 → Godot 4 场景（.tscn）：每个部件一个 Node2D 关节 + 一个 Sprite2D，动作进 AnimationPlayer。

用法：
  python3 build_godot_rig.py assets/chars/hero/hero.rig.json --anims references/anims.humanoid_side.json \
      --res res://assets/chars/hero --out assets/chars/hero/hero.tscn

  --res   部件 PNG 在 Godot 工程里的路径（res://…）。PNG 要先放进工程的这个目录
  --out   写到哪里；一般和部件图放一起

场景结构：
  <名字> (Node2D)                 原点在脚底（split_parts 算的 root_px）
    torso (Node2D)                 每个部件一个关节节点，位置 = 挂点，转它就是转这个关节
      sprite (Sprite2D)            部件图，offset 让关节点落在节点原点
      head (Node2D) / sprite ...
    AnimationPlayer                动作表里的每个动作 + RESET（站立姿势）
z_index 写在 Sprite2D 上（相对模式），关节节点是 0，放进游戏里还能跟着整个角色排前后。
朝左走：把根节点的 scale.x 设成 -1，不用另做一套。
"""
import argparse
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from cutout_lib import load_json, local_offset, order, part_map, unit  # noqa: E402


def f(x):
    """浮点数一律带小数点：值轨道的第一个值写成 0，Godot 会把整条轨道当整数插值，
    转角就只剩 0、-57.3°、-114.6° 这几档（-1、-2 弧度）。"""
    s = f"{x:.6f}".rstrip("0")
    if s.endswith("."):
        s += "0"
    return "0.0" if s in ("-0.0", "") else s


def vec(x, y):
    return f"Vector2({f(x)}, {f(y)})"


def node_path(rig, pid):
    pm, parts = part_map(rig), []
    cur = pm[pid]
    while cur:
        parts.append(cur["id"])
        cur = pm.get(cur.get("parent")) if cur.get("parent") else None
    return "/".join(reversed(parts))


def texture_of(rig, p):
    pm = part_map(rig)
    while "image" not in p:
        p = pm[p["same_as"]]
    return p["image"]


def track(i, path, times, values, loop):
    return "\n".join([
        f'tracks/{i}/type = "value"',
        f"tracks/{i}/imported = false",
        f"tracks/{i}/enabled = true",
        f'tracks/{i}/path = NodePath("{path}")',
        f"tracks/{i}/interp = 1",
        f"tracks/{i}/loop_wrap = {'true' if loop else 'false'}",
        f"tracks/{i}/keys = {{",
        f'"times": PackedFloat32Array({", ".join(f(t) for t in times)}),',
        f'"transitions": PackedFloat32Array({", ".join("1" for _ in times)}),',
        '"update": 0,',
        f'"values": [{", ".join(values)}]',
        "}",
    ])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rig")
    ap.add_argument("--anims", required=True)
    ap.add_argument("--res", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rig = load_json(a.rig)
    anims = load_json(a.anims)["animations"]
    pm = part_map(rig)
    u = unit(rig)
    res = a.res.rstrip("/")
    rest_pos = {p["id"]: local_offset(rig, p) for p in rig["parts"]}
    rest_rot = {p["id"]: math.radians(p.get("rest_rot", 0.0)) for p in rig["parts"]}

    tex = sorted({texture_of(rig, p) for p in rig["parts"]})
    tex_id = {t: f"{i + 1}_{Path(t).stem}" for i, t in enumerate(tex)}
    ext = [f'[ext_resource type="Texture2D" path="{res}/{t}" id="{tex_id[t]}"]' for t in tex]

    used = {}          # (部件, 属性) → True：RESET 要覆盖到每条被动作改过的属性
    subs = []
    for name, an in anims.items():
        loop = bool(an.get("loop"))
        lines = [f'[sub_resource type="Animation" id="Animation_{name}"]', f'resource_name = "{name}"',
                 f"length = {f(an['length'])}"]
        if loop:
            lines.append("loop_mode = 1")
        i = 0
        for pid, tr in an.get("tracks", {}).items():
            if pid not in pm:
                sys.exit(f"动作 {name}：部件 {pid} 不在骨架里")
            path = node_path(rig, pid)
            if tr.get("rot"):
                lines.append(track(i, f"{path}:rotation", [k[0] for k in tr["rot"]],
                                   [f(rest_rot[pid] + math.radians(k[1])) for k in tr["rot"]], loop))
                used[(pid, "rotation")] = True
                i += 1
            if tr.get("pos"):
                ox, oy = rest_pos[pid]
                lines.append(track(i, f"{path}:position", [k[0] for k in tr["pos"]],
                                   [vec(ox + k[1] * u, oy + k[2] * u) for k in tr["pos"]], loop))
                used[(pid, "position")] = True
                i += 1
        subs.append((name, "\n".join(lines)))

    reset = ['[sub_resource type="Animation" id="Animation_RESET"]', 'resource_name = "RESET"', "length = 0.001"]
    for i, (pid, prop) in enumerate(sorted(used)):
        v = f(rest_rot[pid]) if prop == "rotation" else vec(*rest_pos[pid])
        reset.append(track(i, f"{node_path(rig, pid)}:{prop}", [0], [v], False))
    subs.insert(0, ("RESET", "\n".join(reset)))

    lib = ['[sub_resource type="AnimationLibrary" id="AnimationLibrary_main"]', "_data = {"]
    lib += [f'&"{n}": SubResource("Animation_{n}"),' for n, _ in subs]
    lib.append("}")

    root_name = rig.get("name", "Character")
    nodes = [f'[node name="{root_name}" type="Node2D"]']
    for p in order(rig):
        pid = p["id"]
        parent = "." if not p.get("parent") else node_path(rig, p["parent"])
        px, py = p["pivot_px"]
        nodes.append(f'\n[node name="{pid}" type="Node2D" parent="{parent}"]\nposition = {vec(*rest_pos[pid])}'
                     + (f"\nrotation = {f(rest_rot[pid])}" if rest_rot[pid] else ""))
        spr = [f'\n[node name="sprite" type="Sprite2D" parent="{node_path(rig, pid)}"]',
               f"z_index = {int(p.get('z', 0))}",
               f'texture = ExtResource("{tex_id[texture_of(rig, p)]}")',
               "centered = false",
               f"offset = {vec(-px, -py)}"]
        if p.get("tint") not in (None, 1):
            t = float(p["tint"])
            spr.append(f"self_modulate = Color({f(t)}, {f(t)}, {f(t)}, 1)")
        nodes.append("\n".join(spr))
    nodes.append('\n[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\n'
                 'libraries = {\n&"": SubResource("AnimationLibrary_main")\n}')
    first = next((n for n, _ in subs if n == "idle"), None)
    if first:
        nodes[-1] += '\nautoplay = &"idle"'

    load_steps = len(ext) + len(subs) + 2
    text = (f"[gd_scene load_steps={load_steps} format=3]\n\n" + "\n".join(ext) + "\n\n"
            + "\n\n".join(s for _, s in subs) + "\n\n" + "\n".join(lib) + "\n\n" + "\n".join(nodes) + "\n")
    Path(a.out).write_text(text, encoding="utf-8")
    print(f"写好 {a.out}：{len(rig['parts'])} 个部件，动作 {', '.join(n for n, _ in subs if n != 'RESET')}")


if __name__ == "__main__":
    main()
