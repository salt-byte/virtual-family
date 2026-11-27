"""A test, 3D cartoon by shape: the 灶间 with toy proportions (thick tops, fat legs, bellied
jars, big round edges, rounded floor tiles), filled up, accents of blue, red and green
against the wood. Materials and light from build_toon3d_kitchen.py. Not used by the game.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_chunky_kitchen.py
Writes assets/blender/out/chunky_kitchen.png
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_toon3d_kitchen as tk  # noqa: E402
from build_toon3d_kitchen import box, cyl, sphere, lathe, pbr, wood_mat, plaster, glow  # noqa: E402

OUT = os.path.join(tk.HERE, "out", "chunky_kitchen.png")
ROOM = tk.ROOM
H = ROOM / 2
WALL_H = 2.2
WALL_T = 0.32
random.seed(11)


def torus(R, r, at, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=at, major_segments=48, minor_segments=16)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def M():
    """The palette."""
    return {
        "wood": wood_mat("c_wood", "#E59A55", "#C97A3A", 0.5),
        "wood_dark": wood_mat("c_wood_dark", "#B86A36", "#9A5428", 0.5),
        "wood_pale": wood_mat("c_wood_pale", "#F2C27E", "#DDA460", 0.5),
        "cream": pbr("c_cream", "#FFF1D6", 0.7),
        "stove": pbr("c_stove", "#F3DDBB", 0.75),
        "stove_top": pbr("c_stove_top", "#C9BBA8", 0.6),
        "iron": pbr("c_iron", "#45414A", 0.35, 0.5),
        "blue": pbr("c_blue", "#4F8EE0", 0.25),
        "blue_dk": pbr("c_blue_dk", "#2F65B8", 0.25),
        "red": pbr("c_red", "#E9473B", 0.3),
        "green": pbr("c_green", "#6CC35A", 0.4),
        "green_lt": pbr("c_green_lt", "#BDEB8A", 0.4),
        "white": pbr("c_white", "#FBF8F2", 0.2),
        "orange": pbr("c_orange", "#FF9A3C", 0.4),
        "yellow": pbr("c_yellow", "#F7CF5A", 0.45),
        "jar": pbr("c_jar", "#B35E3E", 0.18, 0.0, 0.6),
        "water": pbr("c_water", "#66B6E8", 0.05),
        "straw": pbr("c_straw", "#F0C86A", 0.7),
        "brass": pbr("c_brass", "#F2B640", 0.3, 0.8),
        "dark": pbr("c_dark", "#3A2A22", 0.9),
        "fire": glow("c_fire", "#FF9A3A", 14),
        "paper": glow("c_paper", "#FFF0CC", 1.4),
    }


def floor_tiles(m):
    """Rounded square tiles, two shades in a soft checker, a little gap between them."""
    t1 = pbr("c_tile1", "#C2C7CC", 0.55)
    t2 = pbr("c_tile2", "#B1B7BE", 0.55)
    grout = pbr("c_grout", "#8E949A", 0.9)
    box((ROOM, ROOM, 0.04), (0, 0, -0.04), grout, bevel=0)
    n = 7
    s = ROOM / n
    for i in range(n):
        for j in range(n):
            x = -H + s * (i + 0.5)
            y = -H + s * (j + 0.5)
            box((s - 0.035, s - 0.035, 0.05), (x, y, -0.04), t1 if (i + j) % 2 else t2, bevel=0.012)


def walls(m):
    wall = plaster("c_wall")
    beam = m["wood_dark"]
    # Back walls thick and low, rounded caps; front walls a low kerb.
    box((ROOM + 2 * WALL_T, WALL_T, WALL_H), (0, H + WALL_T / 2, -0.04), wall, bevel=0.06)
    box((WALL_T, ROOM + WALL_T, WALL_H), (-H - WALL_T / 2, WALL_T / 2, -0.04), wall, bevel=0.06)
    box((ROOM + 2 * WALL_T, WALL_T, 0.3), (0, -H - WALL_T / 2, -0.04), wall, bevel=0.08)
    box((WALL_T, ROOM, 0.3), (H + WALL_T / 2, 0, -0.04), wall, bevel=0.08)
    # Skirting and a fat beam along the top.
    box((ROOM, 0.06, 0.2), (0, H - 0.03, 0), beam, bevel=0.03)
    box((0.06, ROOM, 0.2), (-H + 0.03, 0, 0), beam, bevel=0.03)
    box((ROOM + 0.1, 0.2, 0.2), (0, H - 0.06, WALL_H - 0.24), beam, bevel=0.05)
    box((0.2, ROOM + 0.1, 0.2), (-H + 0.06, 0, WALL_H - 0.24), beam, bevel=0.05)
    for (x, y) in ((-H + 0.1, H - 0.1), (0.75, H - 0.08)):
        box((0.2, 0.2, WALL_H - 0.1), (x, y, 0), beam, bevel=0.05)
    # A round-cornered window with a chunky lattice.
    wx, wz = -0.55, 1.15
    box((0.8, 0.04, 0.6), (wx, H - 0.01, wz), m["paper"], bevel=0)
    box((0.96, 0.1, 0.1), (wx, H - 0.04, wz - 0.08), beam, bevel=0.04)
    box((0.96, 0.1, 0.1), (wx, H - 0.04, wz + 0.6), beam, bevel=0.04)
    for dx in (-0.45, 0.45):
        box((0.1, 0.1, 0.78), (wx + dx, H - 0.04, wz - 0.08), beam, bevel=0.04)
    for dx in (-0.14, 0.14):
        box((0.045, 0.07, 0.6), (wx + dx, H - 0.03, wz), beam, bevel=0.015)
    box((0.8, 0.07, 0.045), (wx, H - 0.03, wz + 0.28), beam, bevel=0.015)
    # Sill with a flower pot.
    box((0.9, 0.16, 0.06), (wx, H - 0.1, wz - 0.12), beam, bevel=0.025)
    lathe([(0.0, 0.0), (0.07, 0.0), (0.09, 0.12), (0.1, 0.13)], (wx + 0.25, H - 0.1, wz - 0.06), m["red"])
    for k in range(5):
        sphere(0.05, (wx + 0.25 + random.uniform(-0.04, 0.04), H - 0.1 + random.uniform(-0.03, 0.03), wz + 0.12 + k * 0.025), m["green"])


def stove(m, at):
    """A fat, soft-cornered stove: a thick slab top overhanging it, a big wok with a domed
    wooden lid, a stack of steamers, an arched fire mouth, a stout chimney with a cap."""
    box((1.4, 0.8, 0.66), (at.x, at.y, 0), m["stove"], bevel=0.14)
    box((1.52, 0.92, 0.14), (at.x, at.y, 0.62), m["stove_top"], bevel=0.06)
    cx = at.x - 0.25
    torus(0.33, 0.04, (cx, at.y, 0.78), m["iron"])
    lathe([(0.0, 0.0), (0.12, 0.0), (0.24, 0.04), (0.33, 0.1)], (cx, at.y, 0.68), m["iron"])
    sphere(0.33, (cx, at.y, 0.80), m["wood_pale"], (1, 1, 0.38))
    sphere(0.06, (cx, at.y, 0.93), m["wood_dark"], (1, 1, 0.8))
    # Steamers on the small pot.
    sx = at.x + 0.38
    lathe([(0.0, 0.0), (0.16, 0.0), (0.2, 0.12), (0.2, 0.16)], (sx, at.y - 0.05, 0.74), m["iron"])
    for k in range(3):
        cyl(0.21, 0.11, (sx, at.y - 0.05, 0.9 + k * 0.115), m["straw"], bevel=0.03)
        torus(0.21, 0.018, (sx, at.y - 0.05, 0.9 + k * 0.115 + 0.08), m["wood_dark"])
    sphere(0.2, (sx, at.y - 0.05, 1.25), m["straw"], (1, 1, 0.35))
    # Fire mouth: dark arch, glowing.
    box((0.34, 0.1, 0.2), (cx, at.y - 0.38, 0.1), m["dark"], bevel=0.04)
    cyl(0.17, 0.1, (cx, at.y - 0.38, 0.3), m["dark"], rot=(math.radians(90), 0, 0))
    box((0.24, 0.05, 0.16), (cx, at.y - 0.42, 0.12), m["fire"], bevel=0.02)
    # Chimney.
    box((0.42, 0.38, WALL_H - 0.6), (at.x + 0.5, at.y + 0.26, 0.6), m["stove"], bevel=0.1)
    box((0.52, 0.48, 0.12), (at.x + 0.5, at.y + 0.26, WALL_H - 0.12), m["stove_top"], bevel=0.05)


def vat(m, at):
    """A big round-bellied water jar, a thick rolled rim, a round lid and a red ladle."""
    lathe([(0.0, 0.0), (0.2, 0.0), (0.3, 0.08), (0.37, 0.25), (0.38, 0.4), (0.33, 0.56), (0.28, 0.62)], at, m["jar"])
    torus(0.29, 0.045, (at.x, at.y, at.z + 0.63), m["jar"])
    cyl(0.27, 0.01, (at.x, at.y, at.z + 0.6), m["water"], bevel=0)
    cyl(0.2, 0.05, (at.x + 0.12, at.y + 0.06, at.z + 0.66), m["wood_pale"], bevel=0.02)
    sphere(0.08, (at.x - 0.1, at.y - 0.1, at.z + 0.72), m["red"], (1, 1, 0.6))
    cyl(0.022, 0.3, (at.x - 0.02, at.y - 0.18, at.z + 0.76), m["wood_dark"], rot=(math.radians(80), 0, math.radians(-30)))


def cupboard(m, at, W=0.95):
    """A chunky dresser against the west wall (faces east): a fat crowned top, two open
    shelves of blue, white and red bowls, two doors with big round knobs, bun feet."""
    D = 0.5
    k_w = W / 0.95  # things along its width spread with it
    for sy in (-1, 1):
        for sx in (-1, 1):
            sphere(0.06, (at.x + sx * 0.15, at.y + sy * 0.38 * k_w, 0.06), m["wood_dark"])
    box((D, W, 0.62), (at.x, at.y, 0.08), m["wood"], bevel=0.06)
    for sy in (-1, 1):
        box((0.04, W / 2 - 0.07, 0.48), (at.x + D / 2, at.y + sy * W / 4, 0.15), m["wood_pale"], bevel=0.03)
        sphere(0.045, (at.x + D / 2 + 0.04, at.y + sy * 0.07 * k_w, 0.4), m["brass"])
    # Open shelves.
    for sy in (-1, 1):
        box((D, 0.08, 0.8), (at.x, at.y + sy * (W / 2 - 0.04), 0.66), m["wood"], bevel=0.035)
    box((0.06, W, 0.8), (at.x - D / 2 + 0.03, at.y, 0.66), m["wood_dark"], bevel=0.02)
    box((D, W, 0.07), (at.x, at.y, 1.06), m["wood"], bevel=0.03)
    box((D + 0.1, W + 0.12, 0.12), (at.x, at.y, 1.44), m["wood"], bevel=0.05)
    box((D + 0.02, W - 0.1, 0.08), (at.x, at.y, 1.56), m["wood_dark"], bevel=0.035)
    cols = [m["blue"], m["white"], m["red"], m["blue_dk"]]
    for k, y in enumerate((-0.26 * k_w, 0.0, 0.26 * k_w)):
        for s in range(3):
            lathe([(0.0, 0.0), (0.06 * k_w, 0.0), (0.11 * k_w, 0.05), (0.12 * k_w, 0.08)], (at.x + 0.03, at.y + y, 0.73 + s * 0.06), cols[(k + s) % 4])
    for k in range(3):
        y = (-0.27 + k * 0.27) * k_w
        lathe([(0.0, 0.0), (0.06 * k_w, 0.0), (0.1 * k_w, 0.12), (0.08 * k_w, 0.2), (0.07 * k_w, 0.24)], (at.x + 0.02, at.y + y, 1.13),
              [m["red"], m["green"], m["blue"]][k])
        sphere(0.06 * k_w, (at.x + 0.02, at.y + y, 1.39), m["wood_pale"], (1, 1, 0.5))


def stool(m, at):
    """A round, thick-seated stool on three stubby legs."""
    cyl(0.2, 0.09, (at.x, at.y, 0.3), m["wood"], bevel=0.035)
    for k in range(3):
        a = k * math.tau / 3 + 0.3
        o = cyl(0.045, 0.32, (at.x + 0.12 * math.cos(a), at.y + 0.12 * math.sin(a), 0), m["wood_dark"], bevel=0.015)


def table(m, at):
    """A stout work table: a thick top, fat legs, a round chopping block, a chunky cleaver,
    a big cabbage, carrots and a radish, a bowl of eggs."""
    box((1.1, 0.62, 0.12), (at.x, at.y, 0.6), m["wood"], bevel=0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.11, 0.11, 0.62), (at.x + sx * 0.44, at.y + sy * 0.22, 0), m["wood_dark"], bevel=0.04)
    box((0.9, 0.06, 0.06), (at.x, at.y + 0.22, 0.14), m["wood_dark"], bevel=0.025)
    cyl(0.2, 0.1, (at.x - 0.22, at.y, 0.72), m["wood_pale"], bevel=0.035)
    box((0.2, 0.025, 0.12), (at.x - 0.2, at.y + 0.04, 0.82), pbr("c_steel", "#C9CED4", 0.25, 0.9), bevel=0.01)
    box((0.12, 0.04, 0.04), (at.x - 0.04, at.y + 0.04, 0.84), m["wood_dark"], bevel=0.015)
    sphere(0.15, (at.x + 0.2, at.y + 0.06, 0.84), m["green_lt"], (1, 1, 0.9))
    for k in range(6):
        a = k * math.tau / 6
        s = sphere(0.11, (at.x + 0.2 + 0.08 * math.cos(a), at.y + 0.06 + 0.08 * math.sin(a), 0.82), m["green"], (0.55, 1, 0.95))
        s.rotation_euler = (0, 0, a)
    for k in range(2):
        c = sphere(0.04, (at.x + 0.38, at.y - 0.18 + k * 0.1, 0.76), m["orange"], (2.6, 1, 1))
        sphere(0.035, (at.x + 0.5, at.y - 0.18 + k * 0.1, 0.77), m["green"], (1.4, 1, 1.2))
    lathe([(0.0, 0.0), (0.07, 0.0), (0.12, 0.06), (0.13, 0.08)], (at.x - 0.05, at.y - 0.2, 0.72), m["blue"])
    for k in range(3):
        a = k * math.tau / 3
        sphere(0.04, (at.x - 0.05 + 0.04 * math.cos(a), at.y - 0.2 + 0.04 * math.sin(a), 0.8), m["white"], (1, 1, 1.25))


def woodpile(m, at):
    rows = [4, 3, 2]
    end = wood_mat("c_end", "#FFDDA0", "#F0C27C", 0.6, (1, 1, 1), 30)
    for k, n in enumerate(rows):
        for i in range(n):
            x = at.x - (n - 1) * 0.08 + i * 0.16
            o = cyl(0.075, 0.6, (x, at.y, 0.08 + k * 0.13), m["wood_dark"], verts=24, bevel=0.02,
                    rot=(math.radians(90), 0, random.uniform(-0.05, 0.05)))
            o.data.materials.append(end)
            for poly in o.data.polygons:
                if abs(poly.normal.y) > 0.9:
                    poly.material_index = 1


def wall_things(m):
    """A shelf of jars on the north wall, garlic and chillies, a ladle and a pan on pegs on
    the west wall, a broom and a bucket."""
    # Shelf east of the chimney on the north wall.
    sx = 1.45
    box((0.9, 0.24, 0.06), (sx, H - 0.12, 1.35), m["wood"], bevel=0.025)
    for dx in (-0.35, 0.35):
        box((0.05, 0.18, 0.14), (sx + dx, H - 0.1, 1.21), m["wood_dark"], bevel=0.02)
    for k, c in enumerate((m["red"], m["blue"], m["green"])):
        x = sx - 0.27 + k * 0.27
        lathe([(0.0, 0.0), (0.07, 0.0), (0.1, 0.08), (0.09, 0.18), (0.06, 0.21)], (x, H - 0.12, 1.41), c)
        sphere(0.065, (x, H - 0.12, 1.63), m["wood_pale"], (1, 1, 0.45))
    # Chillies hanging under the shelf.
    for k in range(8):
        sphere(0.028, (sx + 0.3 + (0.015 if k % 2 else -0.015), H - 0.08, 1.15 - k * 0.055), m["red"], (1, 1, 2.0))
    # Garlic braid, west wall.
    x = -H + 0.08
    for k in range(7):
        sphere(0.06, (x + 0.04, 1.15 + (0.03 if k % 2 else -0.03), 1.0 + k * 0.08), m["white"], (1, 1, 0.85))
    sphere(0.05, (x + 0.03, 1.15, 1.6), m["straw"], (1, 1, 1.4))
    # Pegs: a frying pan and a ladle.
    for yy in (0.35, 0.7):
        cyl(0.025, 0.12, (x + 0.05, yy, 1.62), m["wood_dark"], verts=16, bevel=0.008, rot=(0, math.radians(90), 0))
    pan = cyl(0.17, 0.05, (x + 0.06, 0.35, 1.32), m["iron"], bevel=0.02, rot=(0, math.radians(90), 0))
    box((0.04, 0.04, 0.26), (x + 0.06, 0.35, 1.46), m["wood_dark"], bevel=0.015)
    box((0.04, 0.05, 0.36), (x + 0.05, 0.7, 1.24), m["wood_pale"], bevel=0.02)
    sphere(0.09, (x + 0.08, 0.7, 1.2), m["wood_pale"], (0.6, 1, 1))
    # Broom in the south-west corner, a bucket by the vat, a basket by the table.
    box((0.05, 0.05, 1.0), (-H + 0.25, -H + 0.4, 0.28), m["wood_dark"], bevel=0.02, rot=(0, math.radians(-10), 0))
    b = sphere(0.18, (-H + 0.2, -H + 0.4, 0.17), m["straw"], (0.9, 0.55, 1.1))
    lathe([(0.0, 0.0), (0.17, 0.0), (0.2, 0.34)], (1.5, 0.55, 0), m["wood_pale"])
    for z in (0.07, 0.26):
        torus(0.18 + z * 0.08, 0.02, (1.5, 0.55, z), m["blue_dk"])
    cyl(0.19, 0.005, (1.5, 0.55, 0.3), m["water"], bevel=0)
    lathe([(0.0, 0.0), (0.16, 0.0), (0.22, 0.12), (0.24, 0.2)], (1.35, -1.0, 0), m["straw"])
    for k in range(4):
        sphere(0.07, (1.35 + random.uniform(-0.08, 0.08), -1.0 + random.uniform(-0.08, 0.08), 0.2), [m["orange"], m["red"], m["yellow"]][k % 3])
    # A round straw mat before the stove.
    cyl(0.5, 0.025, (-0.75, 0.75, 0.0), m["straw"], bevel=0.012).scale = (1.3, 0.8, 1)


def build():
    m = M()
    floor_tiles(m)
    walls(m)
    stove(m, Vector((-0.6, H - 0.44, 0)))
    vat(m, Vector((1.4, H - 0.65, 0)))
    cupboard(m, Vector((-H + 0.27, -0.35, 0)))
    woodpile(m, Vector((-1.65, 1.2, 0)))
    stool(m, Vector((-0.8, 0.55, 0)))
    table(m, Vector((0.45, -0.55, 0)))
    stool(m, Vector((0.35, -1.2, 0)))
    wall_things(m)


if __name__ == "__main__":
    tk.WALL_H = WALL_H
    sc = tk.scene()
    build()
    tk.camera(sc)
    sc.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print("WROTE", OUT)
