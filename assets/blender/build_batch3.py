"""Furniture, batch 3 (晾衣绳, 石凳, 柴垛, 水缸, 矮凳, 碗柜): as build_batch1.py (after the pack's
pictures, real sizes of art.json iso.sizes, the game's 45-degree camera, cropped to the
footprint).

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_batch3.py [-- name ...]
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_cute import box, ball, cyl, mat, wood, srgb  # noqa: E402
from build_ref import plank_mat, _tex_mat, _coords  # noqa: E402
import build_batch1 as b1  # noqa: E402


def check_mat(name, c1, c2):
    def build(nt):
        v = _coords(nt, (1, 1, 1))
        chk = nt.nodes.new("ShaderNodeTexChecker")
        chk.inputs["Scale"].default_value = 9.0
        chk.inputs["Color1"].default_value = srgb(c1)
        chk.inputs["Color2"].default_value = srgb(c2)
        nt.links.new(v, chk.inputs["Vector"])
        return chk.outputs["Color"]
    return _tex_mat(name, build)


def clothesline():
    """晾衣绳 2.6 x 0.3 m: two posts 1.7 m high, a rope between them, a pale blue shirt and a
    red-checked cloth hung over it."""
    post = wood("b3_post", "#E0853C", "#C9742F")
    rope = mat("b3_rope", "#D8B27A")
    shirt = mat("b3_shirt", "#8CC0E6")
    cloth = check_mat("b3_cloth", "#E0505A", "#FFF4EE")
    for sx in (-1, 1):
        cyl("post", 0.04, 1.72, (sx * 1.2, 0, 0), post, 16)
        ball("knob", 0.05, (sx * 1.2, 0, 1.74), post, 1.0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.01, depth=2.4, location=(0, 0, 1.62),
                                        rotation=(0, math.radians(90), 0))
    bpy.context.active_object.data.materials.append(rope)
    box("shirt", (0.44, 0.04, 0.58), (-0.5, 0, 1.04), shirt, bevel=0.015)
    box("collar", (0.16, 0.05, 0.05), (-0.5, 0, 1.58), mat("b3_collar", "#6FA6D0"), bevel=0.012)
    for sx in (-1, 1):  # sleeves hanging from the shoulders
        box("sleeve", (0.13, 0.04, 0.34), (-0.5 + sx * 0.285, 0, 1.27), shirt, bevel=0.015)
    box("cloth", (0.55, 0.03, 0.70), (0.45, 0, 0.92), cloth, bevel=0.01)


def stone_bench():
    """石凳 1.2 x 0.4 m, 0.45 m high: a grey stone slab on two stone blocks."""
    stone = mat("b3_stone", "#AEB4BA")
    stone2 = mat("b3_stone2", "#9AA0A7")
    box("slab", (1.2, 0.4, 0.12), (0, 0, 0.33), stone, bevel=0.04)
    for sx in (-1, 1):
        box("leg", (0.22, 0.34, 0.33), (sx * 0.40, 0, 0), stone2, bevel=0.035)


def woodpile():
    """柴垛 1.8 x 1.0 m, about 0.9 m high: split logs lying north-south, their pale cut ends
    to the south, stacked in rows that narrow to the top."""
    random.seed(3)
    bark = wood("b3_bark", "#B8743E", "#9E6234")
    end = mat("b3_end", "#F2CF92")
    r = 0.095
    rows = [9, 9, 8, 7, 5]
    for k, n in enumerate(rows):
        z = r + k * r * 1.72
        x0 = -(n - 1) * r
        for i in range(n):
            x = x0 + i * 2 * r + (r if k % 2 else 0) * 0
            ln = random.uniform(0.86, 0.96)
            bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r * random.uniform(0.9, 1.0), depth=ln,
                                                location=(x, 0, z), rotation=(math.radians(90), 0, random.uniform(-0.05, 0.05)))
            o = bpy.context.active_object
            o.data.materials.append(bark)
            o.data.materials.append(end)
            for poly in o.data.polygons:  # the two caps take the cut-end colour
                if abs(poly.normal.z) > 0.9:
                    poly.material_index = 1


def vat():
    """水缸 0.6 x 0.6 m, 0.7 m high: a glazed brown jar, wide at the shoulder, half covered by
    a wooden lid with a ladle on it."""
    glaze = mat("b3_glaze", "#9A6A4C")
    rim = mat("b3_rim", "#7E553C")
    water = mat("b3_water", "#3F5F7A")
    lid = plank_mat("b3_lid", "#D9A15E", "#CE9654", "#9C6A38")
    ladle = wood("b3_ladle", "#D49A58", "#C08848")
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.3, location=(0, 0, 0.36), segments=32, ring_count=16)
    body = bpy.context.active_object
    body.scale = (1, 1, 1.1)
    body.data.materials.append(glaze)
    bpy.ops.object.shade_smooth()
    cyl("foot", 0.2, 0.06, (0, 0, 0), glaze, 32)
    cyl("neck", 0.25, 0.08, (0, 0, 0.62), glaze, 40)
    cyl("lip", 0.27, 0.03, (0, 0, 0.69), rim, 40)
    cyl("water", 0.24, 0.005, (0, 0, 0.70), water, 32)
    # Half the mouth covered: two planks on the east half, inside the rim.
    box("lid", (0.25, 0.48, 0.03), (0.125, 0.0, 0.715), lid, bevel=0.01)
    ball("ladle_bowl", 0.065, (0.10, -0.06, 0.765), ladle, 0.55)
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.014, depth=0.30, location=(0.20, 0.06, 0.775),
                                        rotation=(math.radians(90), 0, math.radians(-40)))
    bpy.context.active_object.data.materials.append(ladle)


def stool():
    """矮凳 0.35 x 0.3 m, 0.45 m high: a square top with pale corner caps, splayed legs and
    stretchers."""
    top = plank_mat("b3_stool_top", "#E9894A", "#DD7E42", "#A9552A")
    leg = wood("b3_stool_leg", "#D27A42", "#BC6A37")
    cap = mat("b3_cap", "#F3E6D0")
    box("top", (0.35, 0.30, 0.05), (0, 0, 0.40), top, bevel=0.015)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("cap", (0.05, 0.05, 0.052), (sx * 0.15, sy * 0.125, 0.40), cap, bevel=0.008)
            lg = box("leg", (0.04, 0.04, 0.41), (sx * 0.13, sy * 0.10, 0), leg, bevel=0.01)
            lg.rotation_euler = (math.radians(-5 * sy), math.radians(5 * sx), 0)
        box("str", (0.03, 0.22, 0.025), (sx * 0.13, 0, 0.14), leg)
    for sy in (-1, 1):
        box("str", (0.24, 0.025, 0.025), (0, sy * 0.10, 0.22), leg)


def cupboard():
    """碗柜 0.9 x 0.45 m, 1.1 m high: an open shelf on top with two bowls, two doors below
    with brass knobs, on short feet."""
    body = plank_mat("b3_cup", "#D7864A", "#CC7C42", "#9C5A2E")
    dark = mat("b3_cup_in", "#8E5530")
    door = wood("b3_door", "#E0904F", "#CF8045")
    brass = mat("b3_brass", "#E9B44C")
    bowl = mat("b3_bowl", "#F3EDE2")
    bowl2 = mat("b3_bowl2", "#9EC3E0")
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("foot", (0.06, 0.06, 0.06), (sx * 0.41, sy * 0.18, 0), body)
    box("back", (0.9, 0.04, 1.04), (0, 0.205, 0.06), body)
    for sx in (-1, 1):
        box("side", (0.04, 0.45, 1.04), (sx * 0.43, 0, 0.06), body, bevel=0.01)
    box("bottom", (0.9, 0.45, 0.04), (0, 0, 0.06), body)
    box("mid", (0.9, 0.45, 0.04), (0, 0, 0.62), body)
    box("top", (0.96, 0.49, 0.05), (0, 0, 1.10), body, bevel=0.015)
    box("inside", (0.82, 0.02, 0.44), (0, 0.18, 0.66), dark)
    for sx in (-1, 1):
        box("door", (0.40, 0.03, 0.50), (sx * 0.205, -0.21, 0.10), door, bevel=0.01)
        ball("knob", 0.022, (sx * 0.04, -0.235, 0.36), brass, 1.0)
    cyl("bowl1", 0.11, 0.08, (-0.18, 0.0, 0.66), bowl, 32)
    cyl("bowl2", 0.10, 0.07, (0.15, 0.0, 0.66), bowl2, 32)
    cyl("bowl3", 0.10, 0.07, (0.15, 0.0, 0.73), bowl, 32)


PIECES = {"clothesline": (clothesline, (2.6, 0.3)), "stone_bench": (stone_bench, (1.2, 0.4)),
          "woodpile": (woodpile, (1.8, 1.0)), "vat": (vat, (0.6, 0.6)), "stool": (stool, (0.35, 0.3)),
          "cupboard": (cupboard, (0.9, 0.45))}


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PIECES)
    for name in only:
        fn, size = PIECES[name]
        b1.render(name, fn, size)
