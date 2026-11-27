"""White models (clay renders) of the kitchen pieces in cartoon proportions, for the image
model to paint over: one piece per picture, all one white clay material, soft light, no
outlines, the game's 45-degree camera, the long side along i (down-right on screen), backed
against a north wall. Composited on #F0F0F0, 1536 x 1536.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_white.py [-- name ...]
Writes assets/gen/ref/white_<name>.png
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
import build_furniture as fu  # noqa: E402
from build_toon3d_kitchen import pbr, srgb  # noqa: E402

OUT_DIR = os.path.join(HERE, "..", "gen", "ref")
KEYS = ["wood", "wood_dark", "wood_pale", "cream", "stove", "stove_top", "iron", "blue", "blue_dk", "red", "green",
        "green_lt", "white", "orange", "yellow", "jar", "water", "straw", "brass", "dark", "fire", "paper"]


def clay():
    c = pbr("clay", "#E9E6E1", 0.8)
    m = {k: c for k in KEYS}
    m["dark"] = pbr("clay_dark", "#9C9893", 0.9)   # openings read as holes
    m["water"] = pbr("clay_water", "#C9C6C1", 0.3)
    return m


def facing_south(fn):
    """Build with `fn`, then turn everything it made a quarter turn clockwise (a piece
    modelled facing east ends up facing south)."""
    def build(m):
        before = set(bpy.context.scene.objects)
        fn(m)
        piv = bpy.data.objects.new("piv", None)
        bpy.context.scene.collection.objects.link(piv)
        for o in bpy.context.scene.objects:
            if o not in before and o is not piv:
                o.parent = piv
        piv.rotation_euler = (0, 0, math.radians(-90))
    return build


ck.WALL_H = 1.7  # a short chimney on a piece standing alone
ORIGIN = Vector((0, 0, 0))
PIECES = {
    "stove": lambda m: ck.stove(m, ORIGIN),
    "vat": lambda m: ck.vat(m, ORIGIN),
    "cupboard": facing_south(lambda m: ck.cupboard(m, ORIGIN)),
    "cupboard_e": lambda m: ck.cupboard(m, ORIGIN, W=0.66),
    "stool": lambda m: ck.stool(m, ORIGIN),
    "dining_table": lambda m: fu.dining_table(m, ORIGIN),
    "altar": lambda m: fu.altar(m, ORIGIN),
    "desk": lambda m: fu.desk(m, ORIGIN),
    "keepsake_chest": lambda m: fu.keepsake_chest(m, ORIGIN),
    "kang": lambda m: fu.kang(m, ORIGIN),
    "bookshelf": lambda m: fu.bookshelf(m, ORIGIN),
    "woodpile": lambda m: fu.woodpile(m, ORIGIN),
    "well_head": lambda m: fu.well_head(m, ORIGIN),
    "millstone": lambda m: fu.millstone(m, ORIGIN),
    "grape_trellis": lambda m: fu.grape_trellis(m, ORIGIN),
    "stone_bench": lambda m: fu.stone_bench(m, ORIGIN),
    "trash_basket": lambda m: fu.trash_basket(m, ORIGIN),
    "clothesline": lambda m: fu.clothesline(m, ORIGIN),
    "grain_heap": lambda m: fu.grain_heap(m, ORIGIN),
    "trough": lambda m: fu.trough(m, ORIGIN),
    "washtub": lambda m: fu.washtub(m, ORIGIN),
    "coop": lambda m: fu.coop(m, ORIGIN),
    "loom": lambda m: fu.loom(m, ORIGIN),
    "embroidery_frame": lambda m: fu.embroidery_frame(m, ORIGIN),
    "carpenter_bench": lambda m: fu.carpenter_bench(m, ORIGIN),
    "tofu_box": lambda m: fu.tofu_box(m, ORIGIN),
    "peddler_pole": lambda m: fu.peddler_pole(m, ORIGIN),
    "herb_grinder": lambda m: fu.herb_grinder(m, ORIGIN),
    "garden": lambda m: fu.garden(m, ORIGIN),
    "bird_cage": lambda m: fu.bird_cage(m, ORIGIN),
    "chopping_table": lambda m: ck.table(m, ORIGIN),
}


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            for c in o.bound_box:
                p = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
    return lo, hi


def render(name):
    sc = tk.scene()
    sc.render.film_transparent = True
    PIECES[name](clay())
    lo, hi = bounds()
    centre = (lo + hi) / 2
    w, d, top = hi.x - lo.x, hi.y - lo.y, hi.z
    span = (w + d) * math.cos(math.radians(45)) + 0.3
    height = span * 0.5 + top * 0.87 + 0.3
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(span, height)
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = (math.radians(60), 0, math.radians(45))
    back = co.rotation_euler.to_matrix() @ Vector((0, 0, 1))
    co.location = Vector((centre.x, centre.y, top * 0.5)) + back * 30
    cam.clip_end = 100
    sc.camera = co
    side = 1100
    sc.render.resolution_x = side if span >= height else int(side * span / height)
    sc.render.resolution_y = side if height >= span else int(side * height / span)
    path = os.path.join(OUT_DIR, "_white_%s_raw.png" % name)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("WROTE", path)


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PIECES)
    for n in only:
        render(n)
