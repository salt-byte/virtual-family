"""The whole game scene as a white model (clay render): every room, wall, door gap and piece
of furniture where the game puts them (assets/gen/ref/layout.json, from
game/tools/dump_layout.gd), each piece at its real size and turned and set against its wall by
design/PLACEMENT.md, a 1.6 m figure wherever a person stands, seen from the game's 45-degree
camera. Pieces with a modelled white model (stove, vat, cupboard, stool, woodpile) use it; the
rest are plain blocks of their real size and a guessed height.

Map cells to metres: x east, y south (world -y), 0.7 m a cell.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_white_scene.py [-- room ...]
Writes assets/gen/review/white_scene.png (whole compound), or white_scene_<room>.png for each room named.
"""
import json
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
import build_white_room as wr  # noqa: E402
from build_toon3d_kitchen import box, cyl  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
# env LAYOUT: another plan (e.g. layout_x1.5.json); its name tags the pictures.
_LP = os.environ.get("LAYOUT", "layout.json")
LAYOUT = json.load(open(os.path.join(ROOT, "assets", "gen", "ref", _LP)))
TAG = "" if _LP == "layout.json" else "_" + _LP[len("layout_"):-len(".json")]
MPC = float(os.environ.get("MPC", LAYOUT["metres_per_cell"]))
SIZES = LAYOUT["sizes"]
OUT = os.path.join(ROOT, "assets", "gen", "review")

WALL_H = {"house": 2.4, "compound": 1.8, "fence": 0.9}
LOW = 0.35        # walls the camera looks over (a room's south and east sides), cut down
THICK = 0.14
GAP = 0.05        # a piece's back off its wall
# Heights (m) of the pieces drawn as blocks.
HEIGHT = {"kang": 0.7, "desk": 0.8, "dining_table": 0.8, "altar": 0.95, "keepsake_chest": 0.45, "coop": 0.9,
          "millstone": 0.8, "grape_trellis": 2.2, "clothesline": 1.7, "trash_basket": 0.5, "well_head": 0.75,
          "threshold": 0.15, "stone_bench": 0.45, "bookshelf": 1.9, "trough": 0.4, "grain_heap": 0.9,
          "washtub": 0.35, "loom": 1.5, "carpenter_bench": 0.7, "herb_grinder": 0.3, "embroidery_frame": 0.9,
          "tofu_box": 0.6, "peddler_pole": 1.0, "bird_cage": 0.5, "garden": 0.25, "ayun_hoop": 0.6}
MODELLED = {
    "stove": lambda m: ck.stove(m, Vector()),
    "vat": lambda m: ck.vat(m, Vector()),
    # modelled facing east: a quarter turn makes it face south like the rest
    "cupboard": lambda m: _turned(lambda: ck.cupboard(m, Vector(), W=0.66), -90),
    "stool": lambda m: ck.stool(m, Vector()),
    "woodpile": lambda m: ck.woodpile(m, Vector()),
}
ROUND = {"vat", "stool", "millstone", "well_head", "grain_heap", "washtub", "trash_basket", "bird_cage"}


def W(x, y, z=0.0):
    return Vector((x * MPC, -y * MPC, z))


def _turned(fn, deg):
    before = set(bpy.context.scene.objects)
    fn()
    piv = bpy.data.objects.new("piv", None)
    bpy.context.scene.collection.objects.link(piv)
    for o in bpy.context.scene.objects:
        if o not in before and o is not piv and o.parent is None:
            o.parent = piv
    piv.rotation_euler = (0, 0, math.radians(deg))
    return piv


def room_of(name):
    for r in LAYOUT["rooms"]:
        if r["id"] == name:
            return r
    return None


def facing(t):
    """'south' or 'east' by design/PLACEMENT.md section 3, and which wall it backs onto."""
    room = room_of(t["room"])
    indoor = room and room["indoor"]
    cx, cy = t["cell"]
    if indoor and cy == 0:
        return "south", "north"
    if indoor and cx == 0:
        return "east", "west"
    if t["type"] in ROUND:
        return "south", None
    return ("east", None) if t["h"] > t["w"] else ("south", None)


def piece(m, t):
    typ = t["type"]
    face, wall = facing(t)
    fw, fd = t["w"] * MPC, t["h"] * MPC   # footprint along x (east), along y (south)
    real = SIZES.get(typ, [fw * 0.85, fd * 0.85])
    length, depth = float(real[0]), float(real[1])
    # Real size across x and y once turned.
    sx, sy = (length, depth) if face == "south" else (depth, length)
    centre = W(t["x"], t["y"]) + Vector((fw / 2, -fd / 2, 0))

    if wall == "north":
        centre.y += (fd - sy) / 2 - GAP
    elif wall == "west":
        centre.x -= (fw - sx) / 2 - GAP
    before = set(bpy.context.scene.objects)
    if typ in MODELLED:
        MODELLED[typ](m)
    else:
        h = HEIGHT.get(typ, 0.8)
        if typ in ROUND:
            cyl(min(length, depth) / 2, h, (0, 0, 0), m["cream"], verts=40, bevel=0.03)
        elif typ in ("grape_trellis", "clothesline"):
            for px in (-length / 2 + 0.06, length / 2 - 0.06):
                for py in ((-depth / 2 + 0.06, depth / 2 - 0.06) if typ == "grape_trellis" else (0,)):
                    cyl(0.05, h, (px, py, 0), m["cream"], verts=16)
            if typ == "grape_trellis":
                box((length, depth, 0.08), (0, 0, h - 0.08), m["cream"])
            else:
                box((length, 0.02, 0.02), (0, 0, h - 0.15), m["cream"])
        else:
            box((length, depth, h), (0, 0, 0), m["cream"], bevel=0.03)
    piv = bpy.data.objects.new("piv_" + typ, None)
    bpy.context.scene.collection.objects.link(piv)
    for o in bpy.context.scene.objects:
        if o not in before and o is not piv and o.parent is None:
            o.parent = piv
    piv.rotation_euler = (0, 0, math.radians(90 if face == "east" else 0))
    piv.location = centre


def built_indoor_at(cx, cy):
    for r in LAYOUT["rooms"]:
        if r["indoor"] and r["built"] and r["x"] <= cx < r["x"] + r["w"] and r["y"] <= cy < r["y"] + r["h"]:
            return True
    return False


def wall_height(kind, along, line, at):
    """As the game's IsoWall.face_height: only the compound's outer north and west walls stand
    full height (a house's where a built room is inside); every other wall is cut low."""
    if kind == "fence":
        return WALL_H["fence"]
    c = LAYOUT["compound"]
    back = (along == "x" and line == c[1]) or (along == "y" and line == c[0])
    if not back:
        return LOW
    inside = (at, line) if along == "x" else (line, at)
    return WALL_H["house"] if built_indoor_at(*inside) or kind == "house" else WALL_H["compound"]


def walls(m):
    for run in LAYOUT["walls"]:
        open_ = set(run["open"])
        a = run["a"]
        while a < run["b"]:
            h = wall_height(run["kind"], run["along"], run["line"], a)
            if a in open_:
                a += 1
                continue
            b = a
            while b < run["b"] and b not in open_ and wall_height(run["kind"], run["along"], run["line"], b) == h:
                b += 1
            n = (b - a) * MPC
            if run["along"] == "x":
                box((n, THICK, h), W((a + b) / 2, run["line"]), m["cream"], bevel=0.02)
            else:
                box((THICK, n, h), W(run["line"], (a + b) / 2), m["cream"], bevel=0.02)
            a = b


def ground(m, grout):
    sx, sy = LAYOUT["size"]
    box((sx * MPC, sy * MPC, 0.02), W(sx / 2, sy / 2, -0.02), grout, bevel=0)
    c = LAYOUT["compound"]
    box((c[2] * MPC, c[3] * MPC, 0.02), W(c[0] + c[2] / 2, c[1] + c[3] / 2, -0.01), m["yard"], bevel=0)
    for r in LAYOUT["rooms"]:
        if r["indoor"] and r["built"]:
            box((r["w"] * MPC, r["h"] * MPC, 0.03), W(r["x"] + r["w"] / 2, r["y"] + r["h"] / 2, -0.01), m["water"], bevel=0)
        elif r["indoor"]:  # not built yet: its foundation only
            box((r["w"] * MPC - 0.1, r["h"] * MPC - 0.1, 0.06), W(r["x"] + r["w"] / 2, r["y"] + r["h"] / 2), grout, bevel=0.02)


def frame(sc, cells, px_per_m):
    """The game camera over map rectangle `cells` (x, y, w, h)."""
    x, y, w, h = cells
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = (math.radians(60), 0, math.radians(45))
    mat = co.rotation_euler.to_matrix()
    right, up, back = mat.col[0], mat.col[1], mat.col[2]
    pts = [W(x + dx, y + dy, z) for dx in (0, w) for dy in (0, h) for z in (0, 2.4)]
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(up) for p in pts]
    pw, ph = max(xs) - min(xs) + 0.6, max(ys) - min(ys) + 0.6
    cam.ortho_scale = max(pw, ph)
    co.location = right * (max(xs) + min(xs)) / 2 + up * (max(ys) + min(ys)) / 2 + back * 60
    cam.clip_end = 200
    sc.camera = co
    sc.render.resolution_x = int(pw * px_per_m)
    sc.render.resolution_y = int(ph * px_per_m)


def build():
    sc = tk.scene()
    sc.render.film_transparent = False
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.87, 0.87, 0.87, 1)
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    sc.view_settings.exposure = -0.35
    m = bw.clay()
    for k in ("fire", "paper"):
        m[k] = m["cream"]
    grout = tk.pbr("clay_grout", "#A9A49C", 0.9)
    m["water"] = tk.pbr("clay_floor", "#C9C3BA", 0.9)   # indoor floors
    m["yard"] = tk.pbr("clay_yard", "#D6D1C9", 0.9)
    ground(m, grout)
    walls(m)
    for t in LAYOUT["things"]:
        piece(m, t)
    people = [Vector((p["x"], p["y"])) for p in LAYOUT["people"]] + [Vector((13.6, 13.4)), Vector((19.5, 16.5))]
    for p in people:
        wr.figure(m, W(p.x, p.y))
    return sc


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sc = build()
    sc.cycles.samples = 96
    if not only:
        c = LAYOUT["compound"]
        frame(sc, (c[0] - 1, c[1] - 1, c[2] + 2, c[3] + 2), 45)
        sc.render.filepath = os.path.join(OUT, "white_scene%s.png" % TAG)
        bpy.ops.render.render(write_still=True)
        print("WROTE", sc.render.filepath)
    for name in only:
        r = room_of(name)
        frame(sc, (r["x"] - 0.5, r["y"] - 0.5, r["w"] + 1, r["h"] + 1), 110)
        sc.render.filepath = os.path.join(OUT, "white_scene_%s%s.png" % (name, TAG))
        bpy.ops.render.render(write_still=True)
        print("WROTE", sc.render.filepath)
