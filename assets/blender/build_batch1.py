"""Furniture, batch 1 (饭桌, 土炕, 灶台, 书案): modelled after the pack's pictures in the
style of build_ref.py, at the real sizes of art.json iso.sizes, rendered on the game's
45-degree camera so they share the floor's perspective, into game/packs/qijia/art/iso.

Each picture is cropped to its footprint, not to what is drawn: left and right are the
projected corners of the real-size footprint rectangle, the bottom is its front corner
(plus the outline), the top is the highest drawn pixel. The game scales a picture's width
to the footprint (HouseView.iso_picture), so the drawing lands at its real size and place.
Long side along X (east), standing against the north wall, as the game's 45° art is drawn.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_batch1.py
"""
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cute as bc  # noqa: E402
from build_cute import box, ball, cyl, mat, wood, srgb  # noqa: E402
from build_ref import brick_mat, straw_mat, flower_mat, plank_mat, _tex_mat, _earth  # noqa: E402

GAME = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../game/packs/qijia/art/iso"))
SCALE = 2.0      # times the pilot's resolution: sharp when the game zooms in
PAD = 6          # pixels kept round the footprint for the outline


# ---------------------------------------------------------------- pieces (centred on the origin)

def dining_table():
    """饭桌 1.8 x 1.3 m: a square table 0.96 m, 0.78 m high, plank top with brass-capped
    corners, a wooden bowl; a bench west and east, along north-south."""
    top = plank_mat("b1_top", "#E9894A", "#DD7E42", "#A9552A")
    leg = wood("b1_leg", "#D27A42", "#BC6A37")
    cap = mat("b1_cap", "#F3E6D0")
    bowl = mat("b1_bowl", "#E2B26A")
    bowl_in = mat("b1_bowl_in", "#C98F4C")
    box("top", (0.96, 0.96, 0.08), (0, 0, 0.70), top, bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("cap", (0.11, 0.11, 0.085), (sx * 0.43, sy * 0.43, 0.70), cap, bevel=0.015)
            box("leg", (0.08, 0.08, 0.70), (sx * 0.40, sy * 0.40, 0), leg, bevel=0.02)
    for sx in (-1, 1):
        box("apron", (0.045, 0.72, 0.07), (sx * 0.40, 0, 0.60), leg)
        box("stretch", (0.035, 0.72, 0.035), (sx * 0.40, 0, 0.16), leg)
    for sy in (-1, 1):
        box("apron", (0.72, 0.045, 0.07), (0, sy * 0.40, 0.60), leg)
    cyl("bowl", 0.14, 0.08, (0.05, 0.02, 0.78), bowl, 40)
    cyl("bowl_in", 0.118, 0.01, (0.05, 0.02, 0.855), bowl_in, 40)
    for sx in (-1, 1):  # benches west and east, along y
        x = sx * 0.76
        box("seat", (0.26, 1.04, 0.07), (x, 0, 0.38), top, bevel=0.025)
        for sy in (-1, 1):
            for t in (-1, 1):
                lg = box("bleg", (0.055, 0.055, 0.40), (x + t * 0.07, sy * 0.38, 0), leg, bevel=0.015)
                lg.rotation_euler = (math.radians(-8 * sy), math.radians(6 * t), 0)
            box("bstr", (0.16, 0.035, 0.035), (x, sy * 0.38, 0.16), leg)
        box("bstr_long", (0.035, 0.7, 0.035), (x, 0, 0.22), leg)


def kang():
    """土炕 2.0 x 1.5 m, 0.52 m high: an earthen platform with rosy patches, a raised rim
    along the back (north) and the west, an orange wooden edge along the front and east, a
    woven straw mat, two folded quilts of white blossoms on blue and a pale blue pillow."""
    earth = _tex_mat("b1_earth", lambda nt: _earth(nt))
    rim_m = mat("b1_kang_rim", "#F3CF8E")
    edge = wood("b1_kang_edge", "#EE8A3C", "#DD7A32")
    straw = straw_mat("b1_straw")
    q = flower_mat("b1_quilt", "#3F63B0", "#FFFFFF")
    pillow = mat("b1_pillow", "#7FA9E0")
    W, D, H = 2.0, 1.5, 0.52
    box("body", (W, D, H), (0, 0, 0), earth, bevel=0.04)
    box("rim_n", (W, 0.16, 0.24), (0, D / 2 - 0.08, H - 0.02), rim_m, bevel=0.05)
    box("rim_w", (0.16, D, 0.24), (-W / 2 + 0.08, 0, H - 0.02), rim_m, bevel=0.05)
    box("edge_s", (W, 0.10, 0.07), (0, -D / 2 + 0.05, H), edge, bevel=0.03)
    box("edge_e", (0.10, D, 0.07), (W / 2 - 0.05, 0, H), edge, bevel=0.03)
    box("mat", (W - 0.30, D - 0.30, 0.025), (0.04, -0.04, H), straw, bevel=0.008)
    box("quilt0", (1.00, 0.58, 0.15), (0.25, 0.30, H + 0.02), q, bevel=0.06)
    box("quilt1", (0.94, 0.54, 0.14), (0.26, 0.31, H + 0.165), q, bevel=0.06)
    box("pillow", (0.56, 0.32, 0.12), (0.32, 0.34, H + 0.30), pillow, bevel=0.05)


def stove():
    """灶台 1.3 x 0.7 m, 0.72 m high: ochre brick, a big iron wok (steam) and a small pot,
    a brick chimney at the north-east corner, an arched fire mouth on the south face."""
    brick = brick_mat("b1_brick", "#F1C27A", "#E9B56C", "#C98F52")
    brick_red = brick_mat("b1_brick_red", "#E08A5E", "#D27C52", "#A85A3A", (0.16, 0.08))
    rim = brick_mat("b1_rim", "#F6CF8A", "#EFC27C", "#C98F52", (0.30, 0.10))
    iron = mat("b1_iron", "#45464B")
    iron_in = mat("b1_iron_in", "#2F3034")
    soot = mat("b1_soot", "#3B2A25")
    fire = mat("b1_fire", "#FFA53A")
    fire2 = mat("b1_fire2", "#FFE07A")
    steam = mat("b1_steam", "#FFFFFF")
    W, D = 1.3, 0.7
    box("foot", (W, D, 0.10), (0, 0, 0), brick, bevel=0.03)
    box("body", (W - 0.04, D - 0.04, 0.56), (0, 0, 0.10), brick, bevel=0.04)
    box("rim", (W + 0.02, D + 0.02, 0.07), (0, 0, 0.65), rim, bevel=0.03)
    cyl("wok_lip", 0.28, 0.03, (-0.28, -0.02, 0.715), iron, 56)
    cyl("wok_in", 0.25, 0.012, (-0.28, -0.02, 0.738), iron_in, 56)
    for i, (dx, dz, r) in enumerate(((0.0, 0.92, 0.05), (0.05, 1.02, 0.04), (0.01, 1.10, 0.03))):
        ball("steam%d" % i, r, (-0.28 + dx, -0.02, dz), steam, 0.8)
    cyl("pot", 0.13, 0.12, (0.20, -0.05, 0.72), iron, 32)
    ball("pot_lid", 0.11, (0.20, -0.05, 0.84), iron, 0.4)
    box("chimney", (0.22, 0.22, 0.60), (0.50, 0.20, 0.72), brick_red, bevel=0.025)
    box("chimney_top", (0.26, 0.26, 0.07), (0.50, 0.20, 1.32), brick_red, bevel=0.02)
    cyl("flue", 0.06, 0.01, (0.50, 0.20, 1.39), soot, 24)
    box("mouth", (0.24, 0.06, 0.16), (-0.28, -0.33, 0.12), soot, bevel=0.005)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.12, depth=0.06, location=(-0.28, -0.33, 0.28),
                                        rotation=(math.radians(90), 0, 0))
    bpy.context.active_object.data.materials.append(soot)
    ball("flame", 0.06, (-0.28, -0.36, 0.20), fire, 1.4)
    ball("flame_core", 0.03, (-0.28, -0.38, 0.18), fire2, 1.3)
    box("sill", (0.30, 0.10, 0.04), (-0.28, -0.37, 0.08), rim, bevel=0.01)


def desk():
    """书案 1.2 x 0.6 m, 0.75 m high: a plank top, square legs with stretchers, a rolled
    scroll tied with red, a brush and an inkstone."""
    top = plank_mat("b1_desk_top", "#B7743F", "#AD6B38", "#7A4524")
    leg = wood("b1_desk_leg", "#A8693A", "#935A30")
    paper = mat("b1_paper", "#F4E6C8")
    tie = mat("b1_tie", "#E07A72")
    stone = mat("b1_inkstone", "#4A4D55")
    ink = mat("b1_ink", "#1E1E22")
    brush = mat("b1_brush", "#C9803E")
    tip = mat("b1_tip", "#F1EBDD")
    box("top", (1.2, 0.6, 0.06), (0, 0, 0.69), top, bevel=0.025)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("leg", (0.07, 0.07, 0.69), (sx * 0.53, sy * 0.24, 0), leg, bevel=0.015)
        box("str_y", (0.035, 0.48, 0.035), (sx * 0.53, 0, 0.16), leg)
    box("apron_s", (1.0, 0.035, 0.07), (0, -0.24, 0.60), leg)
    box("apron_n", (1.0, 0.035, 0.07), (0, 0.24, 0.60), leg)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.045, depth=0.36, location=(-0.32, 0.02, 0.795),
                                        rotation=(0, math.radians(90), math.radians(20)))
    bpy.context.active_object.data.materials.append(paper)
    bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.048, depth=0.03, location=(-0.30, 0.03, 0.795),
                                        rotation=(0, math.radians(90), math.radians(20)))
    bpy.context.active_object.data.materials.append(tie)
    box("inkstone", (0.22, 0.15, 0.035), (0.32, 0.08, 0.75), stone, bevel=0.015)
    cyl("ink", 0.04, 0.005, (0.34, 0.08, 0.785), ink, 24)
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.008, depth=0.26, location=(0.02, -0.08, 0.758),
                                        rotation=(0, math.radians(90), math.radians(-30)))
    bpy.context.active_object.data.materials.append(brush)
    ball("tip", 0.012, (0.13, -0.145, 0.758), tip, 1.0)


# ---------------------------------------------------------------- rendering

PIECES = {"dining_table": (dining_table, (1.8, 1.3)), "kang": (kang, (2.0, 1.5)),
          "stove": (stove, (1.3, 0.7)), "desk": (desk, (1.2, 0.6))}


def render(name, fn, size):
    bc.PX_PER_M = bc.GAME_PX_PER_M * 2.0 * SCALE
    sc = bc.reset()
    sc.render.line_thickness = 1.0
    sc.view_layers[0].freestyle_settings.linesets[0].linestyle.thickness = 4.0 * SCALE * 0.85
    bc._mats.clear()
    fn()
    w, d = size
    span = (w + d) * math.cos(math.radians(45)) + 0.6
    cam = bc.camera(sc, (0, 0, 0.6), span, span * 0.5 + 2.0)
    path = os.path.join(GAME, name + ".png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    # Where the footprint's corners land on the picture (pixels, y down).
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    pts = []
    for cx in (-w / 2, w / 2):
        for cy in (-d / 2, d / 2):
            v = world_to_camera_view(sc, cam, Vector((cx, cy, 0)))
            pts.append((v.x * rx, (1 - v.y) * ry))
    left = min(p[0] for p in pts) - PAD
    right = max(p[0] for p in pts) + PAD
    bottom = max(p[1] for p in pts) + PAD
    print("FOOT", name, round(left), round(right), round(bottom), rx, ry)


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PIECES)
    for name in only:
        fn, size = PIECES[name]
        render(name, fn, size)
