"""A test, the 3D-cartoon way (bright warm colours, round edges, quiet textures, soft light
and shadows, no outlines), after build_real_kitchen.py: the 灶间 (4.2 x 4.2 m, the game's 6 x 6 cells) pre-rendered the Virtual Families
way: physical materials (grey brick floor, whitewashed walls, wood grain, glaze, cast iron),
one sun and the sky lighting the whole room, shadows and ambient occlusion from Cycles, no
outlines. The game's 45-degree orthographic camera. Not used by the game.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_real_kitchen.py
Writes assets/blender/out/real_kitchen.png
"""
import math
import os
import random

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "toon3d_kitchen.png")
ROOM = 4.2
WALL_H = 2.5
WALL_T = 0.22
PX_PER_M = 190
random.seed(4)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


# ------------------------------------------------------------------------- materials
def _new(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    return m, nt, nt.nodes["Principled BSDF"]


def pbr(name, col, rough=0.6, metal=0.0, coat=0.0):
    m, nt, b = _new(name)
    b.inputs["Base Color"].default_value = srgb(col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if coat:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.08
    return m


def _coord(nt, scale=(1, 1, 1), space="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    nt.links.new(tc.outputs[space], mp.inputs["Vector"])
    return mp.outputs["Vector"]


def _ramp(nt, fac, c1, c2):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].color = srgb(c1)
    r.color_ramp.elements[1].color = srgb(c2)
    nt.links.new(fac, r.inputs["Fac"])
    return r.outputs["Color"]


def _bump(nt, b, height, strength=0.3):
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = strength
    nt.links.new(height, bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])


def wood_mat(name, light, dark, rough=0.55, axis_scale=(1, 1, 6), bands=6.0):
    """Wood grain: stretched wave bands warped by noise, a little bump."""
    m, nt, b = _new(name)
    v = _coord(nt, axis_scale)
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = "BANDS"
    wv.inputs["Scale"].default_value = bands * 2.5
    wv.inputs["Distortion"].default_value = 3.0
    wv.inputs["Detail"].default_value = 3.0
    nt.links.new(v, wv.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 30.0
    nt.links.new(v, nz.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    mix.inputs["Factor"].default_value = 0.5
    nt.links.new(wv.outputs["Fac"], mix.inputs[2])
    nt.links.new(nz.outputs["Fac"], mix.inputs[3])
    # Grain is a quiet variation: the dark end only part way to `dark`.
    a, c = srgb(light), srgb(dark)
    mid = "#%02X%02X%02X" % tuple(int(255 * ((0.82 * x + 0.18 * y) ** (1 / 2.2))) for x, y in zip(a[:3], c[:3]))
    nt.links.new(_ramp(nt, mix.outputs[0], mid, light), b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    _bump(nt, b, wv.outputs["Fac"], 0.0)
    return m


def brick_floor(name):
    """Square grey bricks (方砖) with lime mortar, each brick its own shade, worn and dusty."""
    m, nt, b = _new(name)
    v = _coord(nt, (1, 1, 1))
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.offset = 0.0
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Brick Width"].default_value = 0.35
    br.inputs["Row Height"].default_value = 0.35
    br.inputs["Mortar Size"].default_value = 0.008
    br.inputs["Mortar Smooth"].default_value = 0.3
    br.inputs["Color1"].default_value = srgb("#BDB6AA")
    br.inputs["Color2"].default_value = srgb("#ADA699")
    br.inputs["Mortar"].default_value = srgb("#E4DCCB")
    nt.links.new(v, br.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 6.0
    nz.inputs["Detail"].default_value = 8.0
    nt.links.new(v, nz.inputs["Vector"])
    dust = _ramp(nt, nz.outputs["Fac"], "#A69F92", "#CFC8BA")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "OVERLAY"
    mix.inputs["Factor"].default_value = 0.2
    nt.links.new(br.outputs["Color"], mix.inputs[6])
    nt.links.new(dust, mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(br.outputs["Fac"], inv.inputs[1])
    _bump(nt, b, inv.outputs[0], 0.35)
    return m


def plaster(name):
    """Whitewash over earth: off-white, blotchy, darker and browner near the floor."""
    m, nt, b = _new(name)
    v = _coord(nt, (1, 1, 1))
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.0
    nz.inputs["Detail"].default_value = 10.0
    nz.inputs["Roughness"].default_value = 0.65
    nt.links.new(v, nz.inputs["Vector"])
    wall = _ramp(nt, nz.outputs["Fac"], "#F4E4C6", "#FBF1DC")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 0.3
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
    mix.inputs[6].default_value = srgb("#E2C79C")
    nt.links.new(wall, mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    return m


def soot_plaster(name):
    """The stove's lime render, smoked dark round the fire mouth and up the chimney."""
    m, nt, b = _new(name)
    v = _coord(nt, (1, 1, 1))
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 4.0
    nz.inputs["Detail"].default_value = 8.0
    nt.links.new(v, nz.inputs["Vector"])
    nt.links.new(_ramp(nt, nz.outputs["Fac"], "#E8D6B8", "#F6EAD2"), b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.9
    _bump(nt, b, nz.outputs["Fac"], 0.2)
    return m


def glow(name, col, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(col)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


# ------------------------------------------------------------------------- shapes
def _finish(o, m, bevel):
    o.data.materials.append(m)
    if bevel:
        bv = o.modifiers.new("bevel", "BEVEL")
        bv.width = min(bevel * 1.6, min(o.dimensions) * 0.45) if o.dimensions.length else bevel
        bv.segments = 4
        bv.limit_method = "ANGLE"
    return o


def box(size, at, m, bevel=0.025, rot=(0, 0, 0)):
    """A box `size` (x, y, z metres), its bottom's middle at `at`."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(at[0], at[1], at[2] + size[2] / 2), rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, m, bevel)


def cyl(r, h, at, m, verts=48, bevel=0.005, rot=None):
    loc = (at[0], at[1], at[2] + h / 2) if rot is None else at
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot or (0, 0, 0))
    o = bpy.context.active_object
    _finish(o, m, bevel)
    bpy.ops.object.shade_smooth()
    return o


def sphere(r, at, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=at, segments=32, ring_count=16)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def lathe(profile, at, m, verts=64):
    """A turned shape (jar, bowl, wok): `profile` is [(radius, z), ...] bottom to top."""
    mesh = bpy.data.meshes.new("lathe")
    vs, fs = [], []
    n = len(profile)
    for i in range(verts):
        a = i * math.tau / verts
        for (r, z) in profile:
            vs.append((r * math.cos(a), r * math.sin(a), z))
    for i in range(verts):
        j = (i + 1) % verts
        for k in range(n - 1):
            fs.append((i * n + k, j * n + k, j * n + k + 1, i * n + k + 1))
    mesh.from_pydata(vs, [], fs)
    o = bpy.data.objects.new("lathe", mesh)
    bpy.context.scene.collection.objects.link(o)
    o.location = at
    o.data.materials.append(m)
    for p in mesh.polygons:
        p.use_smooth = True
    sol = o.modifiers.new("thick", "SOLIDIFY")
    sol.thickness = 0.012
    return o


# ------------------------------------------------------------------------- the room
def room():
    floor = brick_floor("floor")
    wall = plaster("wall")
    beam = wood_mat("beam", "#B8743C", "#8A5226", 0.6)
    sill = pbr("sill", "#C99A68", 0.6)
    box((ROOM, ROOM, 0.05), (0, 0, -0.05), floor, bevel=0)
    h = ROOM / 2
    # Back walls (north, west) full height, front walls (south, east) cut low, as in the game.
    box((ROOM + 2 * WALL_T, WALL_T, WALL_H), (0, h + WALL_T / 2, -0.05), wall, bevel=0.02)
    box((WALL_T, ROOM, WALL_H), (-h - WALL_T / 2, 0, -0.05), wall, bevel=0.02)
    box((ROOM + 2 * WALL_T, WALL_T, 0.35), (0, -h - WALL_T / 2, -0.05), wall, bevel=0.02)
    box((WALL_T, ROOM, 0.35), (h + WALL_T / 2, 0, -0.05), wall, bevel=0.02)
    # A grey brick plinth along the foot of the back walls.
    box((ROOM, 0.03, 0.28), (0, h - 0.015, 0), sill, bevel=0.005)
    box((0.03, ROOM, 0.28), (-h + 0.015, 0, 0), sill, bevel=0.005)
    # Timber posts in the back corners and the middle of the north wall.
    for (x, y) in ((-h + 0.08, h - 0.08), (0.6, h - 0.06)):
        box((0.14, 0.14, WALL_H), (x, y, 0), beam, bevel=0.012)
    box((ROOM, 0.12, 0.16), (0, h - 0.06, WALL_H - 0.16), beam, bevel=0.012)
    box((0.12, ROOM, 0.16), (-h + 0.06, 0, WALL_H - 0.16), beam, bevel=0.012)
    window(Vector((-0.7, h - 0.02, 1.25)))


def window(at):
    """A lattice window in the north wall: dark frame, paper panes lit from outside."""
    frame = wood_mat("win", "#9C5E30", "#6E3E1C", 0.5)
    paper = glow("paper", "#F4E6C4", 1.6)
    box((0.9, 0.02, 0.7), (at.x, at.y, at.z), paper, bevel=0)
    box((1.0, 0.06, 0.06), (at.x, at.y - 0.02, at.z - 0.06), frame)
    box((1.0, 0.06, 0.06), (at.x, at.y - 0.02, at.z + 0.7), frame)
    for dx in (-0.47, 0.47):
        box((0.06, 0.06, 0.82), (at.x + dx, at.y - 0.02, at.z - 0.06), frame)
    for k in range(1, 5):
        box((0.022, 0.04, 0.7), (at.x - 0.45 + k * 0.18, at.y - 0.02, at.z), frame, bevel=0)
    for k in range(1, 4):
        box((0.9, 0.04, 0.022), (at.x, at.y - 0.02, at.z + k * 0.175), frame, bevel=0)


def stove(at):
    """灶台 1.3 x 0.7 m, 0.8 m high, against the north wall: lime render over brick, a brick
    top, a cast-iron wok under a wooden lid, the fire mouth glowing, a chimney up the wall."""
    body = soot_plaster("stove")
    top = brick_floor("stove_top")
    iron = pbr("iron", "#3E3A3A", 0.35, 0.6)
    lid = wood_mat("lid", "#E0A860", "#C08440", 0.5, (1, 6, 1), 9)
    fire = glow("fire", "#FF8A2A", 18)
    dark = pbr("mouth", "#1A1512", 0.9)
    box((1.3, 0.7, 0.74), (at.x, at.y, 0), body, bevel=0.03)
    box((1.36, 0.76, 0.06), (at.x, at.y, 0.74), top, bevel=0.02)
    lathe([(0.0, 0.0), (0.12, 0.01), (0.22, 0.05), (0.29, 0.12), (0.31, 0.16)], (at.x - 0.22, at.y, 0.66), iron)
    lathe([(0.0, 0.10), (0.12, 0.09), (0.25, 0.05), (0.30, 0.0)], (at.x - 0.22, at.y, 0.82), lid)
    cyl(0.025, 0.06, (at.x - 0.22, at.y, 0.92), lid)
    # A second, smaller pot east.
    lathe([(0.0, 0.0), (0.14, 0.0), (0.17, 0.08), (0.17, 0.2), (0.15, 0.22)], (at.x + 0.35, at.y + 0.05, 0.8), iron)
    # Fire mouth on the south face.
    box((0.26, 0.04, 0.22), (at.x - 0.22, at.y - 0.34, 0.16), dark, bevel=0.01)
    box((0.2, 0.02, 0.12), (at.x - 0.22, at.y - 0.355, 0.17), fire, bevel=0)
    # Chimney.
    box((0.34, 0.3, WALL_H - 0.8), (at.x + 0.42, at.y + 0.2, 0.8), body, bevel=0.03)
    # Ash and a few sticks before the mouth.
    sphere(0.12, (at.x - 0.22, at.y - 0.48, 0.0), pbr("ash", "#6D6863", 0.95), (1.3, 0.8, 0.15))


def vat(at):
    """水缸: a dark brown glazed jar, wide shouldered, a wooden lid half over it, a gourd ladle."""
    glaze = pbr("glaze", "#A0553A", 0.2, 0.0, 0.6)
    lid = wood_mat("vat_lid", "#C29560", "#8E6538", 0.6, (6, 1, 1), 8)
    water = pbr("water", "#5A9EC8", 0.05)
    gourd = pbr("gourd", "#C8A060", 0.5)
    lathe([(0.0, 0.0), (0.18, 0.0), (0.24, 0.12), (0.30, 0.35), (0.30, 0.5), (0.26, 0.62), (0.25, 0.68), (0.27, 0.70)], at, glaze)
    cyl(0.25, 0.01, (at.x, at.y, 0.64), water, bevel=0)
    box((0.27, 0.54, 0.03), (at.x + 0.13, at.y, 0.70), lid, bevel=0.008)
    sphere(0.07, (at.x + 0.08, at.y - 0.08, 0.76), gourd, (1, 1, 0.55))
    cyl(0.014, 0.24, (at.x + 0.18, at.y + 0.05, 0.765), gourd, rot=(math.radians(90), 0, math.radians(-40)))


def cupboard(at):
    """碗柜 0.9 x 0.45 m, 1.4 m high, against the west wall (faces east): open shelves of
    blue-and-white bowls and plates over two panelled doors."""
    wood = wood_mat("cup", "#D08A4C", "#A86430", 0.45)
    inner = wood_mat("cup_in", "#A8693A", "#8A522A", 0.6)
    brass = pbr("brass", "#C8963E", 0.3, 1.0)
    china = pbr("china", "#F1EEE6", 0.15)
    blue = pbr("blue", "#4C86D0", 0.2)
    W, D, H = 0.9, 0.42, 1.4
    x0 = at.x
    box((D, W, 0.04), (x0, at.y, 0.06), wood)
    for sy in (-1, 1):
        box((D, 0.04, H), (x0, at.y + sy * (W / 2 - 0.02), 0), wood, bevel=0.008)
    box((0.03, W, H), (x0 - D / 2 + 0.015, at.y, 0), inner, bevel=0)
    for z in (0.62, 0.98, H - 0.04):
        box((D + 0.02, W + 0.02, 0.04), (x0, at.y, z), wood, bevel=0.008)
    for sy in (-1, 1):
        d = box((0.025, W / 2 - 0.03, 0.52), (x0 + D / 2 - 0.01, at.y + sy * (W / 4 - 0.005), 0.08), wood, bevel=0.006)
        box((0.012, W / 2 - 0.14, 0.38), (x0 + D / 2 + 0.006, at.y + sy * (W / 4 - 0.005), 0.15), inner, bevel=0.004)
        sphere(0.018, (x0 + D / 2 + 0.02, at.y + sy * 0.05, 0.36), brass)
    # Plates standing on the upper shelf, bowls stacked on the lower.
    for k in range(4):
        p = cyl(0.12, 0.012, (x0 - 0.08, at.y - 0.27 + k * 0.18, 1.14), china, bevel=0.002,
                rot=(0, math.radians(75), 0))
        cyl(0.122, 0.006, (x0 - 0.075, at.y - 0.27 + k * 0.18, 1.14), blue, bevel=0, rot=(0, math.radians(75), 0))
    for k, y in enumerate((-0.25, 0.0, 0.25)):
        for s in range(3 - (k % 2)):
            lathe([(0.0, 0.0), (0.05, 0.0), (0.1, 0.05), (0.11, 0.07)], (x0 + 0.02, at.y + y, 0.66 + s * 0.035),
                  blue if s == 2 - (k % 2) else china)


def stool(at, rot=0.0):
    wood = wood_mat("stool", "#E08A48", "#C06A30", 0.5)
    box((0.36, 0.3, 0.04), (at.x, at.y, 0.38), wood, bevel=0.01, rot=(0, 0, rot))
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.04, 0.04, 0.38), (at.x + sx * 0.13, at.y + sy * 0.1, 0), wood, bevel=0.006)


def chopping_table(at):
    """案板桌 1.0 x 0.5 m: an unpainted table, a thick round chopping block with a cleaver,
    a cabbage, white radishes, a bamboo basket of green onions."""
    wood = wood_mat("table", "#E6A462", "#C8823E", 0.5)
    block = wood_mat("block", "#D7B488", "#A8845A", 0.7, (1, 1, 1), 14)
    steel = pbr("steel", "#9A9C9E", 0.3, 1.0)
    handle = wood_mat("handle", "#4A3020", "#2A1A10", 0.5)
    cabbage = pbr("cabbage", "#C8E890", 0.5)
    cab2 = pbr("cabbage2", "#8CCB5A", 0.5)
    radish = pbr("radish", "#F2EDE2", 0.4)
    leafy = pbr("leafy", "#5EB548", 0.5)
    bamboo = wood_mat("bamboo", "#D8B878", "#B08E52", 0.6, (1, 12, 1), 10)
    box((1.0, 0.5, 0.05), (at.x, at.y, 0.72), wood, bevel=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.05, 0.05, 0.72), (at.x + sx * 0.44, at.y + sy * 0.19, 0), wood, bevel=0.006)
        box((0.04, 0.38, 0.04), (at.x + sx * 0.44, at.y, 0.15), wood)
    cyl(0.17, 0.08, (at.x - 0.18, at.y, 0.77), block, bevel=0.01)
    box((0.16, 0.003, 0.08), (at.x - 0.16, at.y + 0.02, 0.85), steel, bevel=0)
    box((0.10, 0.02, 0.02), (at.x - 0.03, at.y + 0.02, 0.86), handle, bevel=0.004)
    sphere(0.12, (at.x + 0.2, at.y + 0.05, 0.86), cabbage, (1, 1, 0.85))
    for k in range(5):
        a = k * math.tau / 5
        s = sphere(0.09, (at.x + 0.2 + 0.07 * math.cos(a), at.y + 0.05 + 0.07 * math.sin(a), 0.84), cab2, (0.6, 1, 0.9))
        s.rotation_euler = (0, 0, a)
    for k in range(2):
        r = sphere(0.04, (at.x + 0.35, at.y - 0.12 + k * 0.08, 0.80), radish, (2.4, 1, 1))
        sphere(0.03, (at.x + 0.45, at.y - 0.12 + k * 0.08, 0.80), leafy, (1.6, 1.4, 1))
    # A bamboo basket on the floor beside it.
    lathe([(0.0, 0.0), (0.14, 0.0), (0.18, 0.08), (0.2, 0.2)], (at.x + 0.75, at.y - 0.05, 0), bamboo)
    for k in range(7):
        cyl(0.012, 0.3, (at.x + 0.75 + random.uniform(-0.08, 0.08), at.y - 0.05 + random.uniform(-0.08, 0.08), 0.12),
            leafy, verts=8, bevel=0)


def woodpile(at):
    """A stack of split firewood by the stove."""
    bark = wood_mat("bark", "#A06A3C", "#7E4E28", 0.7, (1, 1, 1), 20)
    end = wood_mat("end", "#F4D094", "#E0B070", 0.7, (1, 1, 1), 30)
    rows = [5, 4, 3]
    for k, n in enumerate(rows):
        for i in range(n):
            x = at.x - (n - 1) * 0.055 + i * 0.11
            o = cyl(0.05 * random.uniform(0.85, 1.05), 0.55, (x, at.y, 0.05 + k * 0.088), bark, verts=9, bevel=0.004,
                    rot=(math.radians(90), 0, random.uniform(-0.06, 0.06)))
            o.data.materials.append(end)
            for poly in o.data.polygons:
                if abs(poly.normal.y) > 0.9:
                    poly.material_index = 1


def hangings():
    """On the walls: a braid of garlic, a string of red chillies, a broom in the corner, a
    wooden ladle and a strainer on pegs."""
    h = ROOM / 2
    garlic = pbr("garlic", "#EDE3CE", 0.5)
    straw = wood_mat("straw", "#C9A862", "#9C7C3E", 0.8, (1, 1, 10), 12)
    chilli = pbr("chilli", "#E8352A", 0.3, 0.0, 0.5)
    peg = wood_mat("peg", "#9C5E30", "#6E3E1C", 0.5)
    # Garlic braid on the west wall.
    x = -h + 0.05
    cyl(0.012, 0.75, (x, 0.95, 1.2), straw, verts=8, bevel=0)
    for k in range(9):
        sphere(0.045, (x + 0.04, 0.95 + (0.03 if k % 2 else -0.03), 1.25 + k * 0.075), garlic, (1, 1, 0.8))
    # Chillies on the north wall beside the window.
    y = h - 0.05
    for k in range(14):
        c = sphere(0.022, (0.15 + (0.015 if k % 2 else -0.015), y - 0.03, 1.3 + k * 0.05), chilli, (1, 1, 2.4))
        c.rotation_euler = (0.3 * (1 if k % 2 else -1), 0, 0)
    # Pegs and a ladle on the west wall.
    for yy in (-0.6, -0.3):
        cyl(0.015, 0.08, (x + 0.04, yy, 1.55), peg, verts=12, bevel=0, rot=(0, math.radians(90), 0))
    ladle = wood_mat("ladle", "#B88A58", "#8A6239", 0.5)
    box((0.02, 0.03, 0.4), (x + 0.03, -0.6, 1.15), ladle, bevel=0.006)
    sphere(0.07, (x + 0.05, -0.6, 1.12), ladle, (0.6, 1, 1))
    # A broom leaning in the south-west corner.
    box((0.03, 0.03, 1.1), (-h + 0.20, -h + 0.35, 0.3), peg, bevel=0.006, rot=(0, math.radians(-14), 0))
    b = cyl(0.11, 0.36, (-h + 0.30, -h + 0.35, 0), straw, verts=24, bevel=0.01)
    b.scale = (1, 0.45, 1)


def extras():
    """A stack of bamboo steamers on the small pot, a wooden pail of water."""
    bamboo = wood_mat("steamer", "#E8C47C", "#C9A05A", 0.5, (1, 1, 1), 30)
    band = pbr("band", "#B8863E", 0.5)
    for k in range(3):
        cyl(0.17, 0.09, (-0.2, ROOM / 2 - 0.30, 1.02 + k * 0.095), bamboo, bevel=0.012)
        cyl(0.175, 0.015, (-0.2, ROOM / 2 - 0.30, 1.02 + k * 0.095 + 0.07), band, bevel=0.004)
    pail = wood_mat("pail", "#D89A58", "#B87A3C", 0.5, (1, 1, 1), 30)
    hoop = pbr("hoop", "#6A6A70", 0.35, 0.7)
    lathe([(0.0, 0.0), (0.15, 0.0), (0.17, 0.32)], (1.55, 0.6, 0), pail)
    for z in (0.06, 0.25):
        cyl(0.165 + z * 0.06, 0.025, (1.55, 0.6, z), hoop, bevel=0.004)
    cyl(0.155, 0.005, (1.55, 0.6, 0.27), pbr("pail_water", "#5A9EC8", 0.05), bevel=0)


def build():
    h = ROOM / 2
    room()
    stove(Vector((-0.55, h - 0.35, 0)))
    vat(Vector((1.35, h - 0.45, 0)))
    cupboard(Vector((-h + 0.21, -0.2, 0)))
    woodpile(Vector((-1.6, 1.25, 0)))
    stool(Vector((-0.5, 0.95, 0)))
    chopping_table(Vector((0.75, -0.6, 0)))
    stool(Vector((0.55, -1.15, 0)))
    hangings()
    extras()


# ------------------------------------------------------------------------- scene
def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception as e:  # noqa: BLE001
        print("cpu render:", e)
    sc.cycles.samples = 160
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = 0.15
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = srgb("#F2E8DA")
    bg.inputs["Strength"].default_value = 0.85
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.6
    sun.angle = math.radians(18)
    sun.color = srgb("#FFF1DC")[:3]
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    # From the south-west, high: lights the north wall's face, the west wall in shade,
    # shadows falling north-east onto the back walls.
    d = Vector((1.0, 1.4, -1.9)).normalized()
    so.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return sc


def camera(sc):
    span = ROOM * 2 * math.cos(math.radians(45)) + 0.8
    height = span * 0.5 + WALL_H * 0.87 + 0.6
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(span, height)
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = (math.radians(60), 0, math.radians(45))
    back = co.rotation_euler.to_matrix() @ Vector((0, 0, 1))
    co.location = Vector((0, 0, WALL_H * 0.4)) + back * 30
    cam.clip_end = 100
    sc.camera = co
    sc.render.resolution_x = int(span * PX_PER_M)
    sc.render.resolution_y = int(height * PX_PER_M)


if __name__ == "__main__":
    sc = scene()
    build()
    camera(sc)
    sc.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print("WROTE", OUT)
