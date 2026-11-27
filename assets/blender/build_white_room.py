"""The whole 灶间 as a white model (clay render), every piece at its real size where the
game puts it, and a 1.6 m white figure for scale: the layout the image model paints over.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_white_room.py
Writes assets/gen/ref/white_room_kitchen.png (on #F0F0F0)
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_toon3d_kitchen as tk  # noqa: E402
import build_chunky_kitchen as ck  # noqa: E402
import build_white as bw  # noqa: E402
from build_toon3d_kitchen import cyl, sphere, box  # noqa: E402

OUT = os.path.join(HERE, "..", "gen", "ref", "white_room_kitchen.png")


def figure(m, at, h=1.6):
    """A plain standing person `h` tall, cartoon-ish (head about 1:4.5): legs, body, arms, head."""
    c = m["cream"]
    head = h / 4.5
    for sx in (-1, 1):  # legs, feet
        cyl(0.07, h * 0.46, (at.x + sx * 0.085, at.y, 0.04), c, verts=24, bevel=0.03)
        sphere(0.08, (at.x + sx * 0.085, at.y - 0.04, 0.05), c, (1, 1.5, 0.6))
    torso = cyl(0.19, h * 0.33, (at.x, at.y, h * 0.45), c, verts=32, bevel=0.07)
    torso.scale = (1, 0.7, 1)
    for sx in (-1, 1):  # arms hanging by the sides
        o = cyl(0.05, h * 0.32, (at.x + sx * 0.24, at.y, h * 0.47), c, verts=24, bevel=0.025)
        o.rotation_euler = (0, math.radians(8 * sx), 0)
    cyl(0.06, 0.08, (at.x, at.y, h * 0.77), c, verts=24, bevel=0.02)
    sphere(head * 0.55, (at.x, at.y, h - head * 0.55), c)
    sphere(head * 0.58, (at.x, at.y + 0.03, h - head * 0.42), c, (1, 1, 0.6))  # hair bun of a cap


if __name__ == "__main__":
    ck.WALL_H = 2.2
    tk.WALL_H = 2.2
    sc = tk.scene()
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    m = bw.clay()
    for k in ("fire", "paper"):
        m[k] = m["cream"]
    ck.M = lambda: m
    ck.build()
    figure(m, Vector((0.9, 0.55, 0)))
    grout = tk.pbr("clay_grout", "#BDB9B3", 0.9)
    for o in sc.objects:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            n = slot.material.name if slot.material else ""
            if n.startswith("clay"):
                continue
            slot.material = grout if "grout" in n else m["cream"]
    tk.camera(sc)
    sc.render.filepath = OUT + ".raw.png"
    bpy.ops.render.render(write_still=True)
    print("WROTE", OUT)
