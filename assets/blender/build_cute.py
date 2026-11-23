"""Pilot, cute style (toon shading, rounded edges, chunky parts): three pieces of furniture modelled at real size in Blender and rendered with the
game's 45-degree camera (2:1 diamonds), one transparent PNG each, plus a scale sheet.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_cute.py

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
    sc.render.line_thickness = 2.0
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
    ls.linestyle.color = srgb("#4A3424")[:3]
    ls.linestyle.thickness = 2.0
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


def toon(m, color_socket_or_rgba):
    """Three flat bands of light (lit, mid, shade) times the base colour, as emission."""
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].position = 0.0
    e[0].color = (0.62, 0.55, 0.58, 1)
    e[1].position = 0.12
    e[1].color = (0.84, 0.80, 0.80, 1)
    e3 = e.new(0.42)
    e3.color = (1.0, 0.98, 0.95, 1)
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mul.inputs[7])
    if isinstance(color_socket_or_rgba, tuple):
        mul.inputs[6].default_value = color_socket_or_rgba
    else:
        nt.links.new(color_socket_or_rgba, mul.inputs[6])
    nt.links.new(mul.outputs[2], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return nt


def mat(name, hexcol, rough=0.75):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    toon(m, srgb(hexcol))
    _mats[name] = m
    return m


def wood(name, hexcol, dark):
    """A warm wood: base colour streaked along X by a stretched noise."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.5, 18.0, 18.0)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.0
    nz.inputs["Detail"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = srgb(dark)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = srgb(hexcol)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    grain = ramp.outputs["Color"]
    tc.location = (-2000, 0)
    _keep = [tc, mp, nz, ramp]
    # toon() clears all but the output, so rebuild the grain chain after it.
    toon(m, (1, 1, 1, 1))
    nt = m.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.5, 14.0, 14.0)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 2.5
    nz.inputs["Detail"].default_value = 1.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = srgb(hexcol)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = srgb(dark)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    mix = [n for n in nt.nodes if n.type == "MIX"][0]
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    _mats[name] = m
    return m


def box(name, size, at, m, parent=None, bevel=None):
    """A box `size` (x, y, z metres) whose bottom-centre sits at `at`."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(at[0], at[1], at[2] + size[2] / 2))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel is None:
        bevel = min(0.035, min(size) * 0.3)
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        bpy.ops.object.shade_smooth()
    o.data.materials.append(m)
    if parent:
        o.parent = parent
    return o


def ball(name, r, at, m, squash=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=at, segments=24, ring_count=12)
    o = bpy.context.active_object
    o.name = name
    o.scale = (1, 1, squash)
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
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
    """八仙桌 0.9 m square, 0.8 m high, chunky legs, two benches east and west, a bowl of
    rice with chopsticks: footprint 3 x 2 cells."""
    top = wood("table_top", "#F0A766", "#DB8E52")
    leg = wood("table_leg", "#D98A4E", "#C2733C")
    box("top", (0.94, 0.94, 0.08), (0, 0, 0.72), top, bevel=0.035)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("leg", (0.10, 0.10, 0.72), (sx * 0.38, sy * 0.38, 0), leg, bevel=0.03)
    for sx in (-1, 1):
        box("apron", (0.05, 0.70, 0.08), (sx * 0.38, 0, 0.62), leg)
    for sy in (-1, 1):
        box("apron", (0.70, 0.05, 0.08), (0, sy * 0.38, 0.62), leg)
    for sx in (-1, 1):
        x = sx * 0.80
        box("bench_seat", (0.26, 0.96, 0.08), (x, 0, 0.36), top, bevel=0.035)
        for sy in (-1, 1):
            box("bench_leg", (0.09, 0.09, 0.36), (x, sy * 0.36, 0), leg, bevel=0.025)
    bowl = mat("bowl", "#FFFFFF")
    rim = mat("bowl_rim", "#6F9BD8")
    rice = mat("rice", "#FFF8EC")
    cyl("bowl", 0.10, 0.07, (0.06, -0.06, 0.80), bowl, 32)
    cyl("rim", 0.102, 0.015, (0.06, -0.06, 0.855), rim, 32)
    ball("rice", 0.085, (0.06, -0.06, 0.87), rice, 0.55)
    sticks = mat("sticks", "#B0743F")
    box("chop1", (0.02, 0.24, 0.015), (0.24, -0.02, 0.80), sticks, bevel=0.005)
    box("chop2", (0.02, 0.24, 0.015), (0.27, -0.02, 0.80), sticks, bevel=0.005)
    return (3, 2)


def stove():
    """灶台 1.4 x 0.7 m, 0.75 m high: a plump plastered stove with a terracotta skirt, a
    blue-grey tiled top, a wok with a lid and puffs of steam, a kettle, a round-capped
    chimney, the fire mouth facing south: footprint 2 x 1 cells."""
    plaster = mat("plaster", "#FFF0D6")
    brick = mat("brick", "#E08A68")
    tile = mat("top_tile", "#A9C3D9")
    iron = mat("iron", "#4A4E57")
    lid = wood("lid", "#E9A266", "#D18A50")
    soot = mat("soot", "#3A2B2A")
    fire = mat("fire", "#FFB347")
    steam = mat("steam", "#FFFFFF")
    box("base", (1.42, 0.72, 0.14), (0, 0, 0), brick, bevel=0.05)
    box("body", (1.36, 0.66, 0.58), (0, 0, 0.12), plaster, bevel=0.06)
    box("top", (1.46, 0.76, 0.07), (0, 0, 0.69), tile, bevel=0.03)
    cyl("wok", 0.27, 0.04, (-0.22, -0.02, 0.75), iron, 48)
    cyl("lid", 0.24, 0.05, (-0.22, -0.02, 0.78), lid, 48)
    ball("knob", 0.05, (-0.22, -0.02, 0.85), lid, 0.8)
    for i, (dx, dz, r) in enumerate(((-0.05, 0.98, 0.07), (0.03, 1.10, 0.06), (-0.02, 1.21, 0.045))):
        ball("steam%d" % i, r, (-0.22 + dx, -0.02, dz), steam, 0.85)
    cyl("kettle", 0.12, 0.16, (0.32, -0.02, 0.75), iron, 32)
    ball("kettle_lid", 0.10, (0.32, -0.02, 0.91), iron, 0.5)
    box("chimney", (0.28, 0.28, 1.05), (0.55, 0.20, 0.74), brick, bevel=0.06)
    ball("chimney_cap", 0.20, (0.55, 0.20, 1.82), tile, 0.45)
    box("mouth", (0.32, 0.06, 0.26), (-0.22, -0.32, 0.16), soot, bevel=0.06)
    ball("flame", 0.08, (-0.22, -0.34, 0.24), fire, 1.2)
    return (2, 1)


def kang():
    """土炕 2.0 x 1.35 m, 0.55 m high: a plastered platform with a wooden edge, a straw mat,
    two puffy folded quilts and a round pillow at the back, a low kang table with a teapot:
    footprint 3 x 2 cells."""
    plaster = mat("kang_plaster", "#FBE6C4")
    brick = mat("brick", "#E08A68")
    edge = wood("kang_edge", "#E59A58", "#CC8044")
    mat_m = mat("straw", "#F5D27A")
    quilt = mat("quilt", "#6C9BD8")
    quilt2 = mat("quilt_pink", "#F4A3A8")
    pillow = mat("pillow", "#F2786A")
    tw = wood("kang_table", "#F0A766", "#DB8E52")
    pot = mat("teapot", "#7FB7A4")
    box("base", (2.04, 1.38, 0.12), (0, 0, 0), brick, bevel=0.05)
    box("body", (2.00, 1.35, 0.42), (0, 0, 0.10), plaster, bevel=0.05)
    box("edge_s", (2.06, 0.10, 0.08), (0, -0.66, 0.50), edge, bevel=0.035)
    box("edge_e", (0.10, 1.40, 0.08), (1.00, 0, 0.50), edge, bevel=0.035)
    box("mat", (1.90, 1.24, 0.03), (-0.03, 0.03, 0.52), mat_m, bevel=0.01)
    box("quilt0", (0.80, 0.44, 0.13), (-0.45, 0.36, 0.55), quilt, bevel=0.06)
    box("quilt1", (0.76, 0.42, 0.12), (-0.45, 0.36, 0.67), quilt2, bevel=0.055)
    p = ball("pillow", 0.16, (0.25, 0.42, 0.63), pillow, 0.6)
    p.scale = (1.5, 0.9, 0.55)
    box("ktable_top", (0.62, 0.42, 0.06), (0.35, -0.22, 0.78), tw, bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("ktable_leg", (0.07, 0.07, 0.24), (0.35 + sx * 0.24, -0.22 + sy * 0.14, 0.54), tw, bevel=0.02)
    ball("teapot", 0.08, (0.42, -0.20, 0.89), pot, 0.85)
    ball("teapot_lid", 0.04, (0.42, -0.20, 0.96), pot, 0.6)
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
    sc.render.filepath = os.path.join(OUT, "cute_" + name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath, sc.render.resolution_x, sc.render.resolution_y)


def scale_sheet():
    """All three in one 6 x 6-cell room with a floor grid and a 1.6 m person card, to
    check the sizes against one another and against a person."""
    sc = reset()
    _mats.clear()
    room = 6 * CELL_M
    floor = mat("floor", "#E9D3AE", 0.95)
    grid = mat("grid", "#D2B788", 0.95)
    wall = mat("wall", "#FFF3E0", 0.95)
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
    sc.render.filepath = os.path.join(OUT, "cute_scale_sheet.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    render("dining_table", dining_table)
    render("stove", stove, 2.4)
    render("kang", kang)
    scale_sheet()
