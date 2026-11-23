"""The pieces carrying needs (see game/kernel/sim/carry_system.gd), in the style of
build_ref.py: 土筐 (a woven bamboo basket in the yard, where litter goes), 旧物匣 (a
lacquered keepsake chest in the hall, where finds go), 簸箕 (a dustpan of sweepings, held
while carrying). Rendered on the game's 45-degree camera at real size into the pack's iso art.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_carry_art.py
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cute as bc  # noqa: E402
from build_cute import box, ball, cyl, mat, wood, srgb  # noqa: E402
from build_ref import _tex_mat, _coords  # noqa: E402

GAME = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../game/packs/qijia/art/iso"))


def weave_mat(name, c1, c2):
    """Bamboo weave: a fine checker of light and dark strips."""
    def build(nt):
        v = _coords(nt, (1, 1, 1))
        chk = nt.nodes.new("ShaderNodeTexChecker")
        chk.inputs["Scale"].default_value = 26.0
        chk.inputs["Color1"].default_value = srgb(c1)
        chk.inputs["Color2"].default_value = srgb(c2)
        nt.links.new(v, chk.inputs["Vector"])
        return chk.outputs["Color"]
    return _tex_mat(name, build)


def basket():
    """土筐: a round bamboo basket, wider at the mouth, a thick rim, a couple of crumpled
    papers peeking out; 1 x 1 cell."""
    weave = weave_mat("weave", "#E9C27A", "#D6A95E")
    rim = wood("rim", "#C98A4A", "#B5783E")
    paper = mat("paper", "#F4E6C8")
    core = mat("core", "#B96A3A")
    bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=0.20, radius2=0.26, depth=0.42, location=(0, 0, 0.21))
    b = bpy.context.active_object
    b.data.materials.append(weave)
    bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_torus_add(major_radius=0.26, minor_radius=0.025, location=(0, 0, 0.42))
    t = bpy.context.active_object
    t.data.materials.append(rim)
    bpy.ops.object.shade_smooth()
    cyl("inside", 0.24, 0.01, (0, 0, 0.36), mat("dark", "#6B4A2E"), 40)
    ball("paper1", 0.08, (-0.06, 0.04, 0.40), paper, 0.7)
    ball("paper2", 0.06, (0.08, -0.03, 0.39), paper, 0.7)
    ball("core", 0.04, (0.02, 0.09, 0.40), core, 1.1)
    return (1, 1)


def chest():
    """旧物匣: a red-lacquered wooden chest on a low stand, brass corners and a brass lock
    plate on the front (south), its long side along east; 1 x 1 cell."""
    lac = wood("lacquer", "#C8503C", "#B2442F")
    lid_m = wood("lacquer_lid", "#D25A44", "#BC4C38")
    brass = mat("brass", "#F0C15A")
    stand = wood("stand", "#8C5A36", "#7A4C2C")
    box("stand", (0.56, 0.34, 0.08), (0, 0.04, 0), stand, bevel=0.02)
    box("body", (0.52, 0.30, 0.26), (0, 0.04, 0.08), lac, bevel=0.025)
    box("lid", (0.55, 0.33, 0.07), (0, 0.04, 0.34), lid_m, bevel=0.03)
    box("lock", (0.09, 0.02, 0.10), (0, -0.115, 0.22), brass, bevel=0.01)
    ball("knob", 0.02, (0, -0.13, 0.25), brass, 1.0)
    for sx in (-1, 1):
        box("corner", (0.05, 0.02, 0.07), (sx * 0.24, -0.115, 0.30), brass, bevel=0.008)
        box("handle", (0.02, 0.10, 0.03), (sx * 0.275, 0.04, 0.24), brass, bevel=0.008)
    return (1, 1)


def dustpan():
    """簸箕: a bamboo dustpan with a little heap of sweepings, held flat."""
    weave = weave_mat("weave_pan", "#E9C27A", "#D6A95E")
    rim = wood("rim_pan", "#C98A4A", "#B5783E")
    dirt = mat("sweepings", "#9C7B5A")
    leaf = mat("leaf", "#C9A040")
    box("pan", (0.36, 0.30, 0.03), (0, 0, 0), weave, bevel=0.012)
    box("back", (0.36, 0.03, 0.10), (0, 0.15, 0), rim, bevel=0.012)
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(sx * 0.17, 0.02, 0.045))
        s = bpy.context.active_object
        s.scale = (0.03, 0.27, 0.09)
        s.data.materials.append(rim)
    ball("heap", 0.10, (0.0, 0.05, 0.03), dirt, 0.45)
    ball("leaf", 0.04, (0.07, 0.0, 0.06), leaf, 0.4)
    return (1, 1)


SCALE = 3.0  # small pieces: render larger so they stay sharp when the game zooms in


def render(name, fn, out_dir, height_m=1.0):
    bc.PX_PER_M = bc.GAME_PX_PER_M * 2.0 * SCALE
    sc = bc.reset()
    # (the two thicknesses multiply: 2 x 2 at the pilot's scale)
    sc.render.line_thickness = 1.0
    sc.view_layers[0].freestyle_settings.linesets[0].linestyle.thickness = 4.0 * SCALE * 0.85
    bc._mats.clear()
    w, h = fn()
    span = (w + h) * bc.CELL_M * math.cos(math.radians(45)) + 0.2
    bc.camera(sc, (0, 0, 0.25), span, span * 0.5 + height_m * 0.87)
    sc.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


if __name__ == "__main__":
    render("trash_basket", basket, GAME)
    render("keepsake_chest", chest, GAME)
    render("dustpan", dustpan, GAME, 0.4)
