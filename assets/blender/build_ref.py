"""Pilot, modelled after the game's current AI pictures (game/packs/qijia/art/iso/
dining_table.png, stove.png, kang.png): their shapes, colours and surface patterns (brick
courses, straw weave, flowered quilts, plank seams), in the cute style of build_cute.py
(toon bands, rounded edges, warm outlines), at real size on the game's 45-degree camera.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_ref.py
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cute as bc  # noqa: E402

from build_cute import box, ball, cyl, mat, wood, srgb, toon  # noqa: E402


def _tex_mat(name, build):
    """A toon material whose base colour comes from `build(nt)` (returns a colour socket)."""
    if name in bc._mats:
        return bc._mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    toon(m, (1, 1, 1, 1))
    nt = m.node_tree
    sock = build(nt)
    mix = [n for n in nt.nodes if n.type == "MIX"][0]
    nt.links.new(sock, mix.inputs[6])
    bc._mats[name] = m
    return m


def _coords(nt, scale=(1, 1, 1), rot_z=0.0):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    mp.inputs["Rotation"].default_value = (0, 0, rot_z)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs["Vector"]


def brick_mat(name, c1, c2, mortar, size=(0.22, 0.09), axis="x"):
    """Brick courses on every face (box mapping by object coordinates)."""
    def build(nt):
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Color1"].default_value = srgb(c1)
        br.inputs["Color2"].default_value = srgb(c2)
        br.inputs["Mortar"].default_value = srgb(mortar)
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.008
        br.inputs["Brick Width"].default_value = size[0]
        br.inputs["Row Height"].default_value = size[1]
        br.offset = 0.5
        # Bricks run along X on the south/north faces and along Y on the east/west ones:
        # feed (x + y, z) so both visible faces show courses.
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        add = nt.nodes.new("ShaderNodeMath")
        add.operation = "ADD"
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        nt.links.new(sep.outputs[0], add.inputs[0])
        nt.links.new(sep.outputs[1], add.inputs[1])
        nt.links.new(add.outputs[0], comb.inputs[0])
        nt.links.new(sep.outputs[2], comb.inputs[1])
        nt.links.new(comb.outputs[0], br.inputs["Vector"])
        return br.outputs["Color"]
    return _tex_mat(name, build)


def straw_mat(name):
    """A woven straw mat: fine stripes one way, a checker of light and dark across."""
    def build(nt):
        v = _coords(nt, (1, 1, 1), math.radians(0))
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "X"
        wave.inputs["Scale"].default_value = 90.0
        wave.inputs["Distortion"].default_value = 0.0
        chk = nt.nodes.new("ShaderNodeTexChecker")
        chk.inputs["Scale"].default_value = 30.0
        chk.inputs["Color1"].default_value = srgb("#F2CC6E")
        chk.inputs["Color2"].default_value = srgb("#E3B55A")
        nt.links.new(v, wave.inputs["Vector"])
        nt.links.new(v, chk.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.55
        ramp.color_ramp.elements[0].color = (0.82, 0.78, 0.72, 1)
        ramp.color_ramp.elements[1].position = 0.75
        ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(chk.outputs["Color"], mul.inputs[6])
        nt.links.new(ramp.outputs["Color"], mul.inputs[7])
        return mul.outputs[2]
    return _tex_mat(name, build)


def flower_mat(name, base, dot):
    """Blue cloth with small white blossoms (cells of a Voronoi turned to round dots)."""
    def build(nt):
        v = _coords(nt, (1, 1, 1))
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "F1"
        vor.inputs["Scale"].default_value = 11.0
        vor.inputs["Randomness"].default_value = 0.35
        nt.links.new(v, vor.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].position = 0.0
        ramp.color_ramp.elements[0].color = srgb(dot)
        ramp.color_ramp.elements[1].position = 0.22
        ramp.color_ramp.elements[1].color = srgb(base)
        nt.links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
        return ramp.outputs["Color"]
    return _tex_mat(name, build)


def plank_mat(name, c1, c2, seam):
    """Planks along X: long bricks with thin dark seams, a little grain."""
    def build(nt):
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Color1"].default_value = srgb(c1)
        br.inputs["Color2"].default_value = srgb(c2)
        br.inputs["Mortar"].default_value = srgb(seam)
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.006
        br.inputs["Brick Width"].default_value = 2.0
        br.inputs["Row Height"].default_value = 0.24
        nt.links.new(_coords(nt), br.inputs["Vector"])
        return br.outputs["Color"]
    return _tex_mat(name, build)


# ---------------------------------------------------------------- the three pieces

def dining_table():
    """After dining_table.png: a thick plank top with metal-capped corners, square legs
    with aprons and stretchers, a wooden bowl; two benches with splayed legs, one along
    the south side and one along the east side."""
    top = plank_mat("ref_top", "#E9894A", "#DD7E42", "#A9552A")
    leg = wood("ref_leg", "#D27A42", "#BC6A37")
    cap = mat("ref_cap", "#F3E6D0")
    bowl = mat("ref_bowl", "#E2B26A")
    bowl_in = mat("ref_bowl_in", "#C98F4C")
    box("top", (0.96, 0.96, 0.09), (0, 0.08, 0.70), top, bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("cap", (0.11, 0.11, 0.095), (sx * 0.43, 0.08 + sy * 0.43, 0.70), cap, bevel=0.015)
            box("leg", (0.09, 0.09, 0.70), (sx * 0.40, 0.08 + sy * 0.40, 0), leg, bevel=0.02)
    for sx in (-1, 1):
        box("apron", (0.05, 0.72, 0.07), (sx * 0.40, 0.08, 0.60), leg)
        box("stretch", (0.04, 0.72, 0.04), (sx * 0.40, 0.08, 0.16), leg)
    for sy in (-1, 1):
        box("apron", (0.72, 0.05, 0.07), (0, 0.08 + sy * 0.40, 0.60), leg)
    cyl("bowl", 0.15, 0.09, (0.0, 0.10, 0.79), bowl, 40)
    cyl("bowl_in", 0.125, 0.01, (0.0, 0.10, 0.875), bowl_in, 40)

    def bench(cx, cy, along_x):
        sx, sy = (1.0, 0.26) if along_x else (0.26, 1.0)
        box("seat", (sx, sy, 0.07), (cx, cy, 0.38), top, bevel=0.025)
        for s in (-1, 1):
            for t in (-1, 1):
                ox, oy = (s * 0.36, t * 0.07) if along_x else (t * 0.07, s * 0.36)
                lg = box("bleg", (0.06, 0.06, 0.40), (cx + ox, cy + oy, 0), leg, bevel=0.015)
                # splay outwards along the bench and a little across it
                if along_x:
                    lg.rotation_euler = (math.radians(-6 * t), math.radians(8 * s), 0)
                else:
                    lg.rotation_euler = (math.radians(-8 * s), math.radians(6 * t), 0)
            ox, oy = (s * 0.36, 0) if along_x else (0, s * 0.36)
            box("bstr", (0.04, 0.16, 0.035) if along_x else (0.16, 0.04, 0.035), (cx + ox, cy + oy, 0.16), leg)
        box("bstr_long", (0.66, 0.035, 0.035) if along_x else (0.035, 0.66, 0.035), (cx, cy, 0.22), leg)

    bench(-0.05, -0.60, True)   # south
    bench(0.70, 0.05, False)    # east
    return (3, 2)


def stove():
    """After stove.png: an ochre brick block, nearly all its top taken by a big iron wok
    (wisps of steam), a small brick chimney at the north-east corner with its own cap, an
    arched fire mouth with a flame on the south face, a brick footing."""
    brick = brick_mat("ref_brick", "#F1C27A", "#E9B56C", "#C98F52")
    brick_red = brick_mat("ref_brick_red", "#E08A5E", "#D27C52", "#A85A3A", (0.16, 0.08))
    rim = brick_mat("ref_rim", "#F6CF8A", "#EFC27C", "#C98F52", (0.30, 0.10))
    iron = mat("ref_iron", "#45464B")
    iron_in = mat("ref_iron_in", "#2F3034")
    soot = mat("ref_soot", "#3B2A25")
    fire = mat("ref_fire", "#FFA53A")
    fire2 = mat("ref_fire2", "#FFE07A")
    steam = mat("ref_steam", "#FFFFFF")
    box("foot", (1.02, 0.92, 0.10), (0, 0, 0), brick, bevel=0.03)
    box("body", (0.98, 0.88, 0.58), (0, 0, 0.10), brick, bevel=0.04)
    box("rim", (1.04, 0.94, 0.08), (0, 0, 0.66), rim, bevel=0.035)
    cyl("wok_lip", 0.40, 0.03, (-0.04, -0.03, 0.735), iron, 56)
    cyl("wok_in", 0.36, 0.012, (-0.04, -0.03, 0.758), iron_in, 56)
    for i, (dx, dz, r) in enumerate(((0.0, 0.92, 0.05), (0.05, 1.02, 0.04), (0.01, 1.10, 0.03))):
        ball("steam%d" % i, r, (-0.04 + dx, -0.03, dz), steam, 0.8)
    box("chimney", (0.22, 0.22, 0.52), (0.36, 0.30, 0.74), brick_red, bevel=0.025)
    box("chimney_top", (0.26, 0.26, 0.07), (0.36, 0.30, 1.26), brick_red, bevel=0.02)
    cyl("flue", 0.06, 0.01, (0.36, 0.30, 1.33), soot, 24)
    # The arched fire mouth: a dark box topped by a half cylinder, set into the south face.
    box("mouth", (0.24, 0.06, 0.16), (-0.22, -0.43, 0.12), soot, bevel=0.005)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.12, depth=0.06, location=(-0.22, -0.43, 0.28),
                                        rotation=(math.radians(90), 0, 0))
    arch = bpy.context.active_object
    arch.data.materials.append(soot)
    ball("flame", 0.06, (-0.22, -0.46, 0.20), fire, 1.4)
    ball("flame_core", 0.03, (-0.22, -0.48, 0.18), fire2, 1.3)
    box("sill", (0.30, 0.10, 0.04), (-0.22, -0.47, 0.08), rim, bevel=0.01)
    return (2, 1)


def kang():
    """After kang.png: an earthen platform with rosy patches, a low raised rim along the
    back (north) and the west, an orange wooden edge along the front (south) and east, a
    woven straw mat, two folded quilts of white blossoms on blue and a pale blue pillow."""
    earth = _tex_mat("ref_earth", lambda nt: _earth(nt))
    rim_m = mat("ref_kang_rim", "#F3CF8E")
    edge = wood("ref_kang_edge", "#EE8A3C", "#DD7A32")
    straw = straw_mat("ref_straw")
    q = flower_mat("ref_quilt", "#3F63B0", "#FFFFFF")
    pillow = mat("ref_pillow", "#7FA9E0")
    W, D, H = 2.0, 1.35, 0.52
    box("body", (W, D, H), (0, 0, 0), earth, bevel=0.04)
    box("rim_n", (W, 0.16, 0.24), (0, D / 2 - 0.08, H - 0.02), rim_m, bevel=0.05)
    box("rim_w", (0.16, D, 0.24), (-W / 2 + 0.08, 0, H - 0.02), rim_m, bevel=0.05)
    box("edge_s", (W + 0.04, 0.10, 0.07), (0, -D / 2 + 0.03, H), edge, bevel=0.03)
    box("edge_e", (0.10, D + 0.04, 0.07), (W / 2 - 0.03, 0, H), edge, bevel=0.03)
    box("mat", (W - 0.30, D - 0.30, 0.025), (0.04, -0.04, H), straw, bevel=0.008)
    box("quilt0", (1.00, 0.58, 0.15), (0.25, 0.22, H + 0.02), q, bevel=0.06)
    box("quilt1", (0.94, 0.54, 0.14), (0.26, 0.23, H + 0.165), q, bevel=0.06)
    box("pillow", (0.56, 0.32, 0.12), (0.32, 0.26, H + 0.30), pillow, bevel=0.05)
    return (3, 2)


def _earth(nt):
    """Ochre rammed earth with soft rosy patches near the ground."""
    v = _coords(nt, (1, 1, 1))
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.0
    nt.links.new(v, nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = srgb("#F2C477")
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = srgb("#EBA27C")
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    return ramp.outputs["Color"]


if __name__ == "__main__":
    os.makedirs(bc.OUT, exist_ok=True)
    for name, fn in (("dining_table", dining_table), ("stove", stove), ("kang", kang)):
        sc = bc.reset()
        bc._mats.clear()
        w, h = fn()
        span = (w + h) * bc.CELL_M * math.cos(math.radians(45)) + 0.3
        bc.camera(sc, (0, 0, 0.6), span, max(span * 0.5 + 2.4 * 0.87, 1.2))
        sc.render.filepath = os.path.join(bc.OUT, "ref_" + name + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", sc.render.filepath)
