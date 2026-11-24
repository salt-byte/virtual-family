"""Furniture, batch 2 (供桌, 井台, 葡萄架, 石磨): as build_batch1.py (after the pack's pictures,
real sizes of art.json iso.sizes, the game's 45-degree camera, cropped to the footprint).

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_batch2.py [-- name ...]
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_cute import box, ball, cyl, mat, wood  # noqa: E402
from build_ref import brick_mat  # noqa: E402
import build_batch1 as b1  # noqa: E402


def altar():
    """供桌 1.3 x 0.5 m, 0.85 m high: red lacquer, the top's ends turned up a little, square
    legs with stretchers, a brass censer on three feet and two candlesticks with red candles."""
    lac = wood("b2_lac", "#B4432E", "#9E3826")
    lac_dark = wood("b2_lac_dark", "#8E3022", "#7A281C")
    brass = mat("b2_brass", "#E9B44C")
    candle = mat("b2_candle", "#E0453A")
    flame = mat("b2_flame", "#FFD25A")
    box("top", (1.3, 0.5, 0.06), (0, 0, 0.79), lac, bevel=0.02)
    for sx in (-1, 1):
        box("end", (0.06, 0.5, 0.05), (sx * 0.62, 0, 0.84), lac, bevel=0.02)
        for sy in (-1, 1):
            box("leg", (0.07, 0.07, 0.79), (sx * 0.56, sy * 0.19, 0), lac_dark, bevel=0.015)
        box("str", (0.04, 0.34, 0.04), (sx * 0.56, 0, 0.18), lac_dark)
    box("apron", (1.06, 0.04, 0.10), (0, -0.21, 0.69), lac_dark, bevel=0.01)
    cyl("censer", 0.11, 0.10, (0, 0, 0.88), brass, 32)
    ball("censer_belly", 0.12, (0, 0, 0.93), brass, 0.6)
    for a in range(3):
        t = math.radians(90 + a * 120)
        cyl("foot", 0.015, 0.05, (0.08 * math.cos(t), 0.08 * math.sin(t), 0.84), brass, 8)
    for sx in (-1, 1):
        cyl("stick", 0.045, 0.03, (sx * 0.42, 0, 0.85), brass, 24)
        cyl("stem", 0.015, 0.10, (sx * 0.42, 0, 0.88), brass, 12)
        cyl("candle", 0.028, 0.14, (sx * 0.42, 0, 0.98), candle, 16)
        ball("flame", 0.02, (sx * 0.42, 0, 1.14), flame, 1.6)


def well_head():
    """井台 1.2 x 1.2 m: a square wall of grey stone blocks 0.6 m high round a dark shaft,
    two wooden posts and a cross beam over it, a rope and a wooden bucket."""
    stone = brick_mat("b2_stone", "#AEB2B6", "#9EA3A8", "#6E747B", (0.36, 0.19))
    stone_top = brick_mat("b2_stone_top", "#BDC1C4", "#B0B5B9", "#7A8088", (0.34, 0.22))
    dark = mat("b2_shaft", "#2B2F36")
    water = mat("b2_water", "#4F7FA8")
    post = wood("b2_post", "#D98A42", "#C27536")
    rope = mat("b2_rope", "#D8B27A")
    bucket = wood("b2_bucket", "#C98A4A", "#B5783E")
    band = mat("b2_band", "#6A6E75")
    box("wall", (1.2, 1.2, 0.58), (0, 0, 0), stone, bevel=0.04)
    box("cap", (1.24, 1.24, 0.08), (0, 0, 0.56), stone_top, bevel=0.035)
    cyl("shaft", 0.38, 0.02, (0, 0, 0.635), dark, 48)
    cyl("water", 0.26, 0.01, (0, 0, 0.645), water, 40)
    for sx in (-1, 1):
        box("post", (0.10, 0.10, 1.05), (sx * 0.48, 0.05, 0.62), post, bevel=0.025)
    box("beam", (1.20, 0.10, 0.10), (0, 0.05, 1.62), post, bevel=0.03)
    for sx in (-1, 1):
        cyl("beam_end", 0.055, 0.02, (sx * 0.62, 0.05, 1.62), post, 16)
    cyl("rope_coil", 0.07, 0.12, (0, 0.05, 1.61), rope, 20)
    cyl("rope", 0.012, 0.62, (0, 0.05, 1.0), rope, 8)
    cyl("bucket", 0.15, 0.20, (0, 0.05, 0.80), bucket, 24)
    for z in (0.83, 0.95):
        cyl("hoop", 0.153, 0.02, (0, 0.05, z), band, 24)


def grape_trellis():
    """葡萄架 2.6 x 1.4 m, 2.0 m high: six bamboo posts, a lattice of poles on top covered in
    leaves, bunches of purple grapes hanging under it, vines up two posts."""
    random.seed(7)
    bamboo = mat("b2_bamboo", "#8DBA4E")
    node = mat("b2_node", "#6E9A38")
    pole = wood("b2_pole", "#B7814A", "#A06E3C")
    leaf = mat("b2_leaf", "#6DB04A")
    leaf2 = mat("b2_leaf2", "#5A9C3C")
    grape = mat("b2_grape", "#8A4FB8")
    grape2 = mat("b2_grape2", "#6E3B9A")
    W, D, H = 2.6, 1.4, 2.0
    xs = (-W / 2 + 0.08, 0.0, W / 2 - 0.08)
    for x in xs:
        for y in (-D / 2 + 0.08, D / 2 - 0.08):
            cyl("post", 0.045, H, (x, y, 0), bamboo, 16)
            for z in (0.5, 1.0, 1.5):
                cyl("node", 0.05, 0.03, (x, y, z), node, 16)
    for y in (-D / 2 + 0.08, 0.0, D / 2 - 0.08):
        box("pole_x", (W + 0.1, 0.06, 0.06), (0, y, H), pole, bevel=0.015)
    for x in (-W / 2 + 0.08, -W / 4, 0.0, W / 4, W / 2 - 0.08):
        box("pole_y", (0.06, D + 0.1, 0.06), (x, 0, H + 0.05), pole, bevel=0.015)
    # Leaves on a jittered grid so the top is covered (inside the footprint: the picture is cropped to it).
    nx, ny = 11, 6
    for i in range(nx):
        for j in range(ny):
            x = -W / 2 + 0.12 + (W - 0.24) * (i + 0.5) / nx + random.uniform(-0.05, 0.05)
            y = -D / 2 + 0.1 + (D - 0.2) * (j + 0.5) / ny + random.uniform(-0.05, 0.05)
            b = ball("leaf", random.uniform(0.15, 0.2), (x, y, H + 0.12 + random.uniform(0, 0.1)),
                     leaf if (i + j) % 3 else leaf2, 0.3)
            b.rotation_euler = (random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3))
    # Bunches of grapes under the front and the sides, where the camera sees them.
    spots = [(-0.9, -0.55), (-0.3, -0.6), (0.35, -0.58), (0.95, -0.5), (1.15, 0.1), (-1.15, -0.1), (0.6, 0.0)]
    for (x, y) in spots:
        top = H - 0.02
        rows = [4, 4, 3, 3, 2, 1]
        for r, n in enumerate(rows):
            for k in range(n):
                a = k * math.tau / n + r
                rad = 0.05 * (n - 1) / 3
                ball("grape", 0.05, (x + rad * math.cos(a), y + rad * math.sin(a), top - r * 0.075),
                     grape if (k + r) % 2 else grape2, 1.0)
    for x in (xs[0], xs[2]):  # vines up the front posts
        for k in range(6):
            ball("vine_leaf", 0.08, (x + 0.06 * math.sin(k), -D / 2 + 0.02, 0.3 + k * 0.28), leaf, 0.4)


def millstone():
    """石磨 0.9 x 0.9 m: a square stone base 0.45 m high, the lower and the upper round
    stones (grooved round the upper one's side, a hole in its top), a wooden handle east."""
    stone = mat("b2_mstone", "#BFC3C6")
    stone2 = mat("b2_mstone2", "#AEB3B7")
    dark = mat("b2_mhole", "#55595E")
    groove = mat("b2_groove", "#8E9398")
    handle = wood("b2_handle", "#D98A42", "#C27536")
    box("base", (0.9, 0.9, 0.45), (0, 0, 0), stone2, bevel=0.05)
    cyl("lower", 0.42, 0.16, (0, 0, 0.45), stone, 48)
    cyl("upper", 0.40, 0.20, (0, 0, 0.61), stone, 48)
    cyl("seam", 0.415, 0.025, (0, 0, 0.60), groove, 48)
    cyl("hole", 0.06, 0.01, (0.08, 0.05, 0.81), dark, 24)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.05, depth=0.55, location=(0.55, -0.25, 0.70),
                                        rotation=(0, math.radians(90), math.radians(-30)))
    bpy.context.active_object.data.materials.append(handle)
    bpy.ops.object.shade_smooth()


PIECES = {"altar": (altar, (1.3, 0.5)), "well_head": (well_head, (1.2, 1.2)),
          "grape_trellis": (grape_trellis, (2.6, 1.4)), "millstone": (millstone, (0.9, 0.9))}


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PIECES)
    for name in only:
        fn, size = PIECES[name]
        b1.render(name, fn, size)
