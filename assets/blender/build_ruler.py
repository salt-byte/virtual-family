"""White models on one ruler: every piece rendered at PX_PER_M (twice the game's 45-degree
view, where a 0.7 m cell's diamond is 64 px wide), the middle of its footprint at the world
origin. For each piece writes
  assets/gen/ref/ruler_<name>.png   the clay render, transparent, at the ruler (to fit the AI picture back to)
  assets/gen/ref/white_<name>.png   the same on #F0F0F0, 1536 x 1536 (what the image model paints over)
and records in assets/gen/ref/ruler.json {name: {px_per_m, anchor: [x, y] (the footprint's
middle on ruler_<name>.png), size: [w, h]}}.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_ruler.py [-- name ...]
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_toon3d_kitchen as tk  # noqa: E402
import build_chunky_kitchen as ck  # noqa: E402
import build_white as bw  # noqa: E402
import build_furniture as fu  # noqa: E402

REF = os.path.normpath(os.path.join(HERE, "..", "gen", "ref"))
GAME_PX_PER_M = 64.0 / (2 * 0.7 * math.cos(math.radians(45)))  # 64.65 at zoom 1
PX_PER_M = 2 * GAME_PX_PER_M
MARGIN = 0.15  # metres round the piece

ORIGIN = Vector((0, 0, 0))
PIECES = {
    "stove": lambda m: ck.stove(m, ORIGIN),
    "vat": lambda m: ck.vat(m, ORIGIN),
    "cupboard": bw.facing_south(lambda m: ck.cupboard(m, ORIGIN, W=0.66)),
    # Facing east (against a west wall): as modelled, no turn (design/PLACEMENT.md section 3).
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
}


def render(name):
    ck.WALL_H = 1.7
    sc = tk.scene()
    sc.render.film_transparent = True
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    PIECES[name](bw.clay())
    lo, hi = bw.bounds()
    # The camera's picture plane: x along (1, -1, 0)/sqrt2 ... measure the piece there.
    rot = Vector((math.radians(60), 0, math.radians(45)))
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = rot
    m = co.rotation_euler.to_matrix()
    right, up, back = m.col[0], m.col[1], m.col[2]
    xs, ys = [], []
    for o in sc.objects:
        if o.type == "MESH":
            for c in o.bound_box:
                p = o.matrix_world @ Vector(c)
                xs.append(p.dot(right))
                ys.append(p.dot(up))
    x0, x1 = min(xs) - MARGIN, max(xs) + MARGIN
    y0, y1 = min(ys) - MARGIN, max(ys) + MARGIN
    w, h = x1 - x0, y1 - y0
    cam.ortho_scale = max(w, h)
    centre = right * (x0 + x1) / 2 + up * (y0 + y1) / 2
    co.location = centre + back * 30
    cam.clip_end = 100
    sc.camera = co
    sc.render.resolution_x = int(round(w * PX_PER_M))
    sc.render.resolution_y = int(round(h * PX_PER_M))
    path = os.path.join(REF, "ruler_%s.png" % name)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    v = world_to_camera_view(sc, co, ORIGIN)
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    return {"px_per_m": round(PX_PER_M, 3), "anchor": [round(v.x * rx, 1), round((1 - v.y) * ry, 1)], "size": [rx, ry]}


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PIECES)
    book_path = os.path.join(REF, "ruler.json")
    book = json.load(open(book_path)) if os.path.exists(book_path) else {}
    for n in only:
        book[n] = render(n)
        print("RULER", n, book[n])
    json.dump(book, open(book_path, "w"), indent=1)
