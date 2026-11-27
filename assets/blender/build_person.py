"""White model of a person on the game's 45-degree camera, for the image model to paint over
(the family: PEOPLE). The same chunky toy proportions as the furniture. Modelled facing +x
(east), which the camera sees as turned 45 degrees toward the lower right ("front34"); a
quarter turn to +y (north) is "back34", walking to the upper right.

Writes, per facing, under assets/gen/ref/:
  _white_p_<who>_<facing>_raw.png     the whole person standing (white_canvas.py puts it on #F0F0F0)
  _wm_<who>_<facing>_<part>.png       head, torso, a whole arm, a whole leg, each alone, same camera, same scale
  wm_<who>_<facing>.json              px_per_m and, per part, the joints' pixel positions on its picture

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_person.py [-- who ... facing ...]
Give several people to one run rather than starting one Blender per person: they go one after another.
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_toon3d_kitchen as tk  # noqa: E402
import build_chunky_kitchen as ck  # noqa: E402
import build_white as bw  # noqa: E402

REF = os.path.normpath(os.path.join(HERE, "..", "gen", "ref"))
PX_WHOLE = 600.0   # px per metre, the standing figure
PX_PART = 1200.0    # px per metre, the parts
MARGIN = 0.06
TURN = {"front34": 0.0, "back34": math.radians(90)}

# The father: joint heights (metres) of a figure 1.66 tall with a 0.40 head, and his build.
# The game scales every figure to its own height, so the others differ in proportion only.
BASE = dict(ANKLE=0.07, KNEE=0.40, HIP=0.72, WAIST=0.68, SHOULDER=1.13, NECK=1.22, HEAD_C=1.45, HEAD_R=0.2,
            ARM_Y=0.25, LEG_Y=0.105, ELBOW=0.86, WRIST=0.62, ARM_R=0.064, LEG_R=0.085,
            BODY=(0.25, 0.42), HEM=(0.27, 0.435, 0.14, 0.06),   # hem: depth, width, height, drop below the waist
            HAIR="cloth", FRONT="buttons", LEGS="wraps", BEARD=False)
PEOPLE = {
    "father": {},
    # A slighter woman: narrower shoulders, a bun, a side-fastened jacket under a short apron.
    "mother": dict(SHOULDER=1.11, NECK=1.2, HEAD_C=1.43, ARM_Y=0.232, ARM_R=0.058, LEG_R=0.08, LEG_Y=0.098,
                   BODY=(0.235, 0.385), HEM=(0.265, 0.41, 0.2, 0.1), HAIR="bun", FRONT="apron", LEGS="plain"),
    # The old ones: a bigger head on a shorter, thicker body in padded clothes.
    "grandpa": dict(KNEE=0.37, HIP=0.66, WAIST=0.62, SHOULDER=1.04, NECK=1.13, HEAD_C=1.36, ELBOW=0.79, WRIST=0.56,
                    ARM_R=0.067, BODY=(0.275, 0.44), HEM=(0.295, 0.455, 0.16, 0.07), HAIR="short", LEGS="plain",
                    BEARD=True),
    "grandma": dict(KNEE=0.36, HIP=0.64, WAIST=0.60, SHOULDER=1.0, NECK=1.09, HEAD_C=1.32, ELBOW=0.76, WRIST=0.54,
                    ARM_Y=0.24, ARM_R=0.062, LEG_R=0.082, LEG_Y=0.1, BODY=(0.27, 0.42), HEM=(0.295, 0.44, 0.2, 0.1),
                    HAIR="bun", FRONT="plain", LEGS="plain"),
    # A child of seven or eight: three heads tall, short round limbs, two little top-knots.
    "child": dict(ANKLE=0.06, KNEE=0.23, HIP=0.42, WAIST=0.40, SHOULDER=0.7, NECK=0.78, HEAD_C=1.0,
                  ARM_Y=0.2, LEG_Y=0.085, ELBOW=0.53, WRIST=0.38, ARM_R=0.055, LEG_R=0.074,
                  BODY=(0.22, 0.33), HEM=(0.24, 0.35, 0.12, 0.05), HAIR="knots", FRONT="plain", LEGS="plain"),
}
globals().update(BASE)
WHO = "father"


def use(who):
    global WHO
    WHO = who
    globals().update(BASE)
    globals().update(PEOPLE[who])


def capsule(r, z0, z1, x, y, m):
    """A limb: a cylinder from z0 to z1 with a ball on each end."""
    tk.cyl(r, z1 - z0, (x, y, z0), m, bevel=0)
    tk.sphere(r, (x, y, z0), m)
    tk.sphere(r, (x, y, z1), m)


def head(m):
    tk.sphere(HEAD_R, (0, 0, HEAD_C), m, scale=(0.97, 0.98, 1.0))                # skull
    tk.sphere(HEAD_R, (-0.022, 0, HEAD_C + 0.03), m, scale=(0.98, 1.03, 0.98))   # hair, back and top
    tk.sphere(0.03, (HEAD_R * 0.95, 0, HEAD_C - 0.045), m)                        # nose
    for s in (-1, 1):
        tk.sphere(0.042, (-0.01, s * HEAD_R * 0.97, HEAD_C - 0.03), m, scale=(0.6, 0.45, 1.0))  # ears
    if HAIR == "cloth":
        # The head cloth: a band round the brow, a knot and two tails at the back.
        ck.torus(HEAD_R * 0.9, 0.026, (-0.004, 0, HEAD_C + 0.092), m, scale=(1.0, 1.0, 1.7))
        tk.sphere(0.05, (-HEAD_R - 0.03, 0, HEAD_C + 0.06), m, scale=(0.8, 1.0, 0.9))
        for s in (-1, 1):
            tk.box((0.03, 0.07, 0.15), (-HEAD_R - 0.045, s * 0.04, HEAD_C - 0.11), m, bevel=0.012,
                   rot=(s * math.radians(14), math.radians(-12), 0))
    elif HAIR == "bun":      # a round bun low on the back of the head
        tk.sphere(0.085, (-HEAD_R - 0.03, 0, HEAD_C - 0.01), m, scale=(0.85, 1.1, 1.0))
    elif HAIR == "knots":    # two little top-knots
        for s in (-1, 1):
            tk.sphere(0.062, (-0.02, s * 0.115, HEAD_C + HEAD_R + 0.03), m)
    if BEARD:                # a goatee
        tk.sphere(0.045, (HEAD_R * 0.8, 0, HEAD_C - 0.17), m, scale=(0.7, 0.8, 1.5))


def torso(m):
    """Shoulders to hip: a short jacket with a standing collar, the hem a little wider than
    the waist. No shoulder balls (the upper arm's round top is the shoulder) and the neck
    stands in the collar: the head is a ball that sits on it, in front of the torso."""
    d, w = BODY
    tk.box((d, w, SHOULDER + 0.06 - WAIST), (0, 0, WAIST), m, bevel=0.1)
    tk.box((HEM[0], HEM[1], HEM[2]), (0, 0, WAIST - HEM[3]), m, bevel=0.06)        # the hem
    tk.cyl(0.058, 0.1, (0, 0, NECK - 0.06), m, bevel=0.02)                         # neck
    ck.torus(0.07, 0.022, (0, 0, NECK - 0.035), m, scale=(1.0, 1.0, 1.6))        # collar
    x = d / 2
    if FRONT == "buttons":
        tk.box((0.012, 0.03, 0.42), (x + 0.003, 0, WAIST + 0.0), m, bevel=0.004)   # the front opening
        n = 4 if SHOULDER - WAIST > 0.43 else 3
        for k in range(n):                                                         # knot buttons
            tk.box((0.014, 0.075, 0.018), (x + 0.007, 0, WAIST + 0.1 + k * 0.095), m, bevel=0.005)
    elif FRONT == "apron":   # a short apron tied at the waist, down to the hem
        top = WAIST + 0.17
        tk.box((0.02, w * 0.8, top - (WAIST - HEM[3])), (HEM[0] / 2 + 0.004, 0, WAIST - HEM[3]), m, bevel=0.008)
        tk.box((d + 0.02, w + 0.02, 0.035), (0, 0, top - 0.02), m, bevel=0.012)    # its waistband
    else:                    # a jacket fastened at the side: one flap line slanting from the collar
        tk.box((0.012, 0.024, 0.2), (x + 0.003, 0.06, SHOULDER - 0.2), m, bevel=0.004, rot=(math.radians(-35), 0, 0))


def arm(m, s=-1):
    """A whole arm hanging straight: one sleeve from shoulder to cuff (no elbow joint to see;
    build_wm_rig.py cuts the painted arm at the elbow), the hand below."""
    capsule(ARM_R, WRIST + 0.03, SHOULDER - 0.02, 0, s * ARM_Y, m)
    tk.cyl(ARM_R + 0.01, 0.075, (0, s * ARM_Y, WRIST + 0.005), m, bevel=0.012)    # turned-back cuff
    tk.sphere(0.058, (0.008, s * ARM_Y, WRIST - 0.05), m, scale=(0.85, 0.62, 1.15))  # hand
    tk.sphere(0.022, (0.045, s * ARM_Y, WRIST - 0.035), m, scale=(0.8, 0.8, 1.5))    # thumb


def leg(m, s=-1):
    """A whole leg standing straight: one trouser leg from hip to ankle, cut at the knee later."""
    capsule(LEG_R, ANKLE + 0.03, HIP, 0, s * LEG_Y, m)
    if LEGS == "wraps":
        for k in range(3):                                                         # leg wrappings
            ck.torus(LEG_R + 0.001, 0.012, (0, s * LEG_Y, ANKLE + 0.09 + k * 0.075), m)
    else:
        ck.torus(LEG_R + 0.001, 0.014, (0, s * LEG_Y, ANKLE + 0.05), m)           # the trouser's bottom edge
    tk.sphere(LEG_R + 0.015, (0.05, s * LEG_Y, 0.052), m, scale=(1.38, 0.8, 0.52))  # cloth shoe


PARTS = {"head": head, "torso": torso, "arm": arm, "leg": leg}


def joints(name):
    """Joints of a part in the standing figure: where it hangs (pivot) and where it bends."""
    return {
        "head": {"pivot": (0, 0, NECK)},
        "torso": {"pivot": (0, 0, WAIST), "neck": (0, 0, NECK), "shoulder_l": (0, -ARM_Y, SHOULDER - 0.02),
                  "shoulder_r": (0, ARM_Y, SHOULDER - 0.02), "hip_l": (0, -LEG_Y, HIP), "hip_r": (0, LEG_Y, HIP)},
        "arm": {"pivot": (0, -ARM_Y, SHOULDER - 0.02), "bend": (0, -ARM_Y, ELBOW)},
        "leg": {"pivot": (0, -LEG_Y, HIP), "bend": (0, -LEG_Y, KNEE), "foot": (0, -LEG_Y, 0)},
    }[name]


def whole(m):
    head(m)
    torso(m)
    for s in (-1, 1):
        arm(m, s)
        leg(m, s)


def shoot(build, turn, path, px_per_m, points):
    """Build, turn the lot about z, render it tight on the game's camera. Returns the picture
    size and where `points` (world, before the turn) land on it."""
    sc = tk.scene()
    # A white clay reference needs no path tracing: EEVEE takes a second or two a picture
    # where Cycles at 160 samples took tens of seconds and choked the machine.
    sc.render.engine = "BLENDER_EEVEE"
    sc.eevee.taa_render_samples = 32
    # Without these the clay reads flat: no dark in the creases between legs, under the
    # buttons, below the hem. Screen-space ray tracing plus fast GI puts that occlusion back.
    sc.eevee.use_shadows = True
    sc.eevee.use_raytracing = True
    sc.eevee.ray_tracing_method = "SCREEN"
    sc.eevee.use_fast_gi = True
    sc.eevee.fast_gi_method = "GLOBAL_ILLUMINATION"
    sc.eevee.fast_gi_distance = 0.4
    sc.eevee.fast_gi_quality = 0.5
    sc.render.film_transparent = True
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    build(bw.clay()["wood"])
    rz = Matrix.Rotation(turn, 4, "Z")
    for o in sc.objects:
        if o.type == "MESH":
            o.matrix_world = rz @ o.matrix_world
    bpy.context.view_layer.update()
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = (math.radians(60), 0, math.radians(45))
    mat = co.rotation_euler.to_matrix()
    right, up, back = mat.col[0], mat.col[1], mat.col[2]
    xs, ys = [], []
    deps = bpy.context.evaluated_depsgraph_get()
    for o in sc.objects:
        if o.type == "MESH":
            ev = o.evaluated_get(deps)
            for v in ev.data.vertices:
                p = ev.matrix_world @ v.co
                xs.append(p.dot(right))
                ys.append(p.dot(up))
    x0, x1 = min(xs) - MARGIN, max(xs) + MARGIN
    y0, y1 = min(ys) - MARGIN, max(ys) + MARGIN
    w, h = x1 - x0, y1 - y0
    cam.ortho_scale = max(w, h)
    co.location = right * (x0 + x1) / 2 + up * (y0 + y1) / 2 + back * 30
    cam.clip_end = 100
    sc.camera = co
    sc.render.resolution_x = int(round(w * px_per_m))
    sc.render.resolution_y = int(round(h * px_per_m))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    out = {}
    for k, p in points.items():
        v = world_to_camera_view(sc, co, rz @ Vector(p))
        out[k] = [round(v.x * rx, 1), round((1 - v.y) * ry, 1)]
    return {"size": [rx, ry], "points": out}


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for who in [a for a in args if a in PEOPLE] or ["father"]:
        use(who)
        for facing in [a for a in args if a in TURN] or list(TURN):
            book = {"px_per_m": PX_PART, "px_per_m_whole": PX_WHOLE, "parts": {}}
            book["whole"] = shoot(whole, TURN[facing], os.path.join(REF, "_white_p_%s_%s_raw.png" % (who, facing)),
                                  PX_WHOLE, {"foot": (0, 0, 0), "top": (0, 0, HEAD_C + HEAD_R)})
            for name, fn in PARTS.items():
                book["parts"][name] = shoot(fn, TURN[facing], os.path.join(REF, "_wm_%s_%s_%s.png" % (who, facing, name)),
                                            PX_PART, joints(name))
            json.dump(book, open(os.path.join(REF, "wm_%s_%s.json" % (who, facing)), "w"), indent=1)
            print("WROTE", who, facing)
