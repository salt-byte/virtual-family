"""Pilot: three pieces of furniture modelled at real size in Blender and rendered with the
game's 45-degree camera (2:1 diamonds), one transparent PNG each, plus a scale sheet.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_pilot.py

Ruler (from the game as it is): an adult stands about 90 view px = 1.6 m; one floor cell
is a 64 x 32 diamond, edge 35.8 px, which at that scale is 0.70 m. Renders are made at
twice the game's scale (PX_PER_M) so they stay sharp when the game scales them down.
Blender axes: +X east, +Y north, +Z up. The camera stands in the south-east looking
north-west, so east runs down-right on screen and south down-left, as in the game.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
CELL_M = 0.70
GAME_PX_PER_M = 90.0 / (1.6 * math.sin(math.radians(60)))  # ~65: 1.6 m upright -> 90 px
PX_PER_M = GAME_PX_PER_M * 2.0
LINE = (0x4A / 255, 0x34 / 255, 0x24 / 255)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (1.0,)


# ---------------------------------------------------------------- scene, camera, light

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = "ABSOLUTE"
    sc.render.line_thickness = 1.6
    vl = sc.view_layers[0]
    fs = vl.freestyle_settings
    ls = fs.linesets[0] if fs.linesets else fs.linesets.new("lines")
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    fs.crease_angle = math.radians(140)
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("ink")
    ls.linestyle.color = LINE
    ls.linestyle.thickness = 1.6
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = srgb("#FFF4E2")
    bg.inputs[1].default_value = 0.55
    sc.world = w
    # Sun from the north-west, high, soft.
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.5
    sun.angle = math.radians(12)
    sun.color = srgb("#FFF1DA")[:3]
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(40), 0, math.radians(-45 + 180 + 90))
    point_sun(so, Vector((1, -1, -1.25)))
    return sc


def point_sun(obj, direction):
    obj.rotation_euler = direction.normalized().to_track_quat("-Z", "Y").to_euler()


def camera(sc, centre, width_m, height_m):
    """Orthographic 2:1 camera centred on `centre`, framing width_m x height_m (camera
    plane metres) at PX_PER_M."""
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(width_m, height_m)
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = (math.radians(60), 0, math.radians(45))
    back = co.rotation_euler.to_matrix() @ Vector((0, 0, 1))
    co.location = Vector(centre) + back * 30
    cam.clip_end = 100
    sc.camera = co
    sc.render.resolution_x = int(round(width_m * PX_PER_M))
    sc.render.resolution_y = int(round(height_m * PX_PER_M))
    sc.render.resolution_percentage = 100
    return co


# ---------------------------------------------------------------- materials and shapes

_mats = {}


def mat(name, hexcol, rough=0.75):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(hexcol)
    b.inputs["Roughness"].default_value = rough
    _mats[name] = m
    return m


def wood(name, hexcol, dark):
    """A warm wood: base colour streaked along X by a stretched noise."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.7
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.5, 18.0, 18.0)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.0
    nz.inputs["Detail"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = srgb(dark)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = srgb(hexcol)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    _mats[name] = m
    return m


def box(name, size, at, m, parent=None, bevel=0.0):
    """A box `size` (x, y, z metres) whose bottom-centre sits at `at`."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(at[0], at[1], at[2] + size[2] / 2))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    o.data.materials.append(m)
    if parent:
        o.parent = parent
    return o


def cyl(name, r, h, at, m, verts=32, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=(at[0], at[1], at[2] + h / 2))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
    return o


# ---------------------------------------------------------------- the three pieces
# Each is built around the origin of its footprint (cells w x h along east x south), its
# long side along east, standing against the north wall, as the game's 45° art is drawn.

def dining_table():
    """八仙桌 0.9 m square, 0.82 m high, with two benches (长凳) east and west: footprint
    3 x 2 cells (2.1 x 1.4 m)."""
    top = wood("table_top", "#C98A52", "#9C5F34")
    leg = wood("table_leg", "#A86A3C", "#7A4826")
    box("top", (0.92, 0.92, 0.05), (0, 0, 0.77), top, bevel=0.01)
    box("apron_n", (0.80, 0.04, 0.08), (0, 0.40, 0.69), leg)
    box("apron_s", (0.80, 0.04, 0.08), (0, -0.40, 0.69), leg)
    box("apron_e", (0.04, 0.80, 0.08), (0.40, 0, 0.69), leg)
    box("apron_w", (0.04, 0.80, 0.08), (-0.40, 0, 0.69), leg)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("leg", (0.06, 0.06, 0.77), (sx * 0.40, sy * 0.40, 0), leg)
    for sx in (-1, 1):  # foot stretchers
        box("str", (0.035, 0.80, 0.035), (sx * 0.40, 0, 0.12), leg)
    for sx in (-1, 1):  # the benches
        x = sx * 0.78
        box("bench_seat", (0.20, 1.00, 0.05), (x, 0, 0.40), top, bevel=0.008)
        for sy in (-1, 1):
            box("bench_leg", (0.05, 0.05, 0.40), (x, sy * 0.40, 0), leg)
        box("bench_str", (0.03, 0.80, 0.03), (x, 0, 0.12), leg)
    bowl = mat("bowl", "#F2EAD8", 0.4)
    cyl("bowl", 0.08, 0.06, (0.05, -0.05, 0.82), bowl)
    return (3, 2)


def stove():
    """灶台: a brick stove 1.4 x 0.7 m, 0.78 m high, plastered, a tiled top with an iron wok
    and a half lid, a chimney at the north-east corner, the fire mouth facing south:
    footprint 2 x 1 cells."""
    plaster = mat("plaster", "#EFE3CC", 0.9)
    brick = mat("brick", "#9A6A55", 0.9)
    tile = mat("top_tile", "#8C9AA6", 0.6)
    iron = mat("iron", "#3B3A38", 0.45)
    lid = wood("lid", "#B98250", "#8A5A33")
    soot = mat("soot", "#2A2220", 0.95)
    glow = bpy.data.materials.new("glow")
    glow.use_nodes = True
    glow.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = srgb("#FF8A3A")
    glow.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2.0
    glow.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb("#C24A1E")
    box("base", (1.40, 0.70, 0.12), (0, 0, 0), brick)
    box("body", (1.36, 0.66, 0.62), (0, 0, 0.12), plaster)
    box("top", (1.42, 0.72, 0.05), (0, 0, 0.74), tile, bevel=0.01)
    cyl("wok_rim", 0.27, 0.025, (-0.22, -0.02, 0.79), iron, 48)
    lid_o = cyl("lid", 0.25, 0.03, (-0.22, -0.02, 0.815), lid, 48)
    box("lid_handle", (0.22, 0.04, 0.04), (-0.22, -0.02, 0.845), lid)
    cyl("kettle", 0.12, 0.14, (0.35, 0.0, 0.79), iron, 32)
    box("chimney", (0.26, 0.26, 1.20), (0.55, 0.20, 0.79), brick, bevel=0.01)
    box("chimney_cap", (0.32, 0.32, 0.05), (0.55, 0.20, 1.99), tile)
    box("mouth", (0.30, 0.04, 0.24), (-0.22, -0.335, 0.16), soot)
    box("fire", (0.24, 0.02, 0.10), (-0.22, -0.345, 0.17), glow)
    return (2, 1)


def kang():
    """土炕 2.0 x 1.35 m, 0.6 m high: a plastered brick platform with a wooden edge board,
    a straw mat, a folded blue quilt and a pillow at the back, a low kang table:
    footprint 3 x 2 cells."""
    plaster = mat("kang_plaster", "#E8D7B8", 0.9)
    brick = mat("brick", "#9A6A55", 0.9)
    edge = wood("kang_edge", "#B5793F", "#8A5528")
    mat_m = mat("straw", "#E2BE6E", 0.95)
    quilt = mat("quilt", "#4F78B0", 0.85)
    quilt2 = mat("quilt_flower", "#7395C2", 0.85)
    pillow = mat("pillow", "#C9543C", 0.8)
    tw = wood("kang_table", "#C98A52", "#9C5F34")
    box("base", (2.04, 1.38, 0.10), (0, 0, 0), brick)
    box("body", (2.00, 1.35, 0.48), (0, 0, 0.10), plaster)
    box("edge_s", (2.04, 0.08, 0.06), (0, -0.66, 0.56), edge, bevel=0.005)
    box("edge_e", (0.08, 1.38, 0.06), (0.99, 0, 0.56), edge, bevel=0.005)
    box("mat", (1.92, 1.25, 0.02), (-0.02, 0.03, 0.58), mat_m)
    for i, h in enumerate((0.08, 0.08, 0.08)):  # folded quilts stacked at the back
        box("quilt%d" % i, (0.78, 0.40, h), (-0.45, 0.38, 0.60 + i * 0.085), quilt if i != 1 else quilt2, bevel=0.03)
    box("pillow", (0.40, 0.22, 0.12), (0.30, 0.42, 0.60), pillow, bevel=0.04)
    box("ktable_top", (0.60, 0.40, 0.04), (0.35, -0.20, 0.86), tw, bevel=0.006)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("ktable_leg", (0.04, 0.04, 0.26), (0.35 + sx * 0.26, -0.20 + sy * 0.16, 0.60), tw)
    return (3, 2)


# ---------------------------------------------------------------- rendering

def render(name, build, height_m=2.4):
    sc = reset()
    _mats.clear()
    w, h = build()
    # Frame the footprint diamond plus height: its view width is (w + h) cells * 0.79 * edge.
    span = (w + h) * CELL_M * math.cos(math.radians(45)) + 0.3
    centre = (0, 0, 0.6)
    camera(sc, centre, span, max(span * 0.5 + height_m * 0.87, 1.2))
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath, sc.render.resolution_x, sc.render.resolution_y)


def scale_sheet():
    """All three in one 6 x 6-cell room with a floor grid and a 1.6 m person card, to
    check the sizes against one another and against a person."""
    sc = reset()
    _mats.clear()
    room = 6 * CELL_M
    floor = mat("floor", "#D9C7A6", 0.95)
    grid = mat("grid", "#BFA982", 0.95)
    wall = mat("wall", "#F3E9D6", 0.95)
    box("floor", (room, room, 0.02), (0, 0, -0.02), floor)
    for i in range(7):
        t = -room / 2 + i * CELL_M
        box("gx", (room, 0.01, 0.003), (0, t, 0), grid)
        box("gy", (0.01, room, 0.003), (t, 0, 0), grid)
    box("wall_n", (room, 0.14, 2.2), (0, room / 2 + 0.07, -0.02), wall)
    box("wall_w", (0.14, room, 2.2), (-room / 2 - 0.07, 0, -0.02), wall)
    import bpy as _b

    def place(fn, x, y):
        before = set(_b.data.objects)
        fn()
        for o in set(_b.data.objects) - before:
            if o.type == "MESH" and o.parent is None:
                o.location.x += x
                o.location.y += y

    # Cells counted from the north-west corner: (i east, j south) -> centre of a w x h block.
    def at(i, j, w, h):
        return (-room / 2 + (i + w / 2) * CELL_M, room / 2 - (j + h / 2) * CELL_M)

    place(kang, *at(0, 0, 3, 2))
    place(stove, *at(4, 0, 2, 1))
    place(dining_table, *at(2, 3, 3, 2))
    person = mat("person", "#C9543C", 0.8)
    box("person", (0.40, 0.25, 1.60), (at(1, 4, 1, 1)[0], at(1, 4, 1, 1)[1], 0), person, bevel=0.1)
    span = 2 * room * math.cos(math.radians(45)) + 0.4
    camera(sc, (0, 0, 0.9), span, span * 0.5 + 2.6)
    sc.render.filepath = os.path.join(OUT, "scale_sheet.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    render("dining_table", dining_table)
    render("stove", stove, 2.4)
    render("kang", kang)
    scale_sheet()
