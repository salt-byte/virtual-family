"""Cast shadows of the ruler pieces, one picture per sun: the white model is hidden from the
camera but casts onto a shadow-catcher floor, so the render is only the shadow (black, its
darkness in alpha). Same camera and ruler as build_ruler.py (PX_PER_M, 45-degree view), the
footprint's middle at the world origin. World: +x east, -y south (the camera stands south-east).

For each piece and sun writes game/packs/qijia/art/iso/shadow/<name>_<sun>.png (cropped to the
shadow) and records {name: {sun: {anchor: [x, y]}}} in assets/gen/ref/shadow.json, the anchor
being the footprint's middle on that picture.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_shadow.py [-- name ...]
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_toon3d_kitchen as tk  # noqa: E402
import build_white as bw  # noqa: E402
import build_ruler as br  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "game", "packs", "qijia", "art", "iso", "shadow")
BOOK = os.path.join(ROOT, "assets", "gen", "ref", "shadow.json")
REACH = 3.0  # metres of floor round the piece the camera sees
# (azimuth: degrees from east toward north, elevation in degrees)
SUNS = {"morning": (-30, 38), "noon": (-90, 62), "evening": (210, 38)}


def render(name, sun_key):
    sc = tk.scene()
    for o in list(sc.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    sc.cycles.samples = 64
    sc.render.film_transparent = True
    before = set(sc.objects)
    br.PIECES[name](bw.clay())
    bpy.context.view_layer.update()
    for o in sc.objects:
        if o not in before and o.type == "MESH":
            o.visible_camera = False
    bpy.ops.mesh.primitive_plane_add(size=REACH * 2, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.is_shadow_catcher = True

    az, el = (math.radians(a) for a in SUNS[sun_key])
    to_sun = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
    light = bpy.data.lights.new("sun", "SUN")
    light.energy = 3.0
    light.angle = math.radians(6)
    lo = bpy.data.objects.new("sun", light)
    sc.collection.objects.link(lo)
    lo.rotation_euler = to_sun.to_track_quat("Z", "Y").to_euler()

    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.rotation_euler = (math.radians(60), 0, math.radians(45))
    m = co.rotation_euler.to_matrix()
    right, up, back = m.col[0], m.col[1], m.col[2]
    corners = [Vector((x, y, 0)) for x in (-REACH, REACH) for y in (-REACH, REACH)]
    xs = [c.dot(right) for c in corners]
    ys = [c.dot(up) for c in corners]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cam.ortho_scale = max(w, h)
    co.location = right * (max(xs) + min(xs)) / 2 + up * (max(ys) + min(ys)) / 2 + back * 30
    cam.clip_end = 100
    sc.camera = co
    sc.render.resolution_x = int(round(w * br.PX_PER_M))
    sc.render.resolution_y = int(round(h * br.PX_PER_M))
    raw = os.path.join(OUT, "_raw.png")
    sc.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    v = world_to_camera_view(sc, co, Vector((0, 0, 0)))
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    ax, ay = v.x * rx, (1 - v.y) * ry

    img = bpy.data.images.load(raw)
    px = np.array(img.pixels[:]).reshape(ry, rx, 4)[::-1]  # top row first
    alpha = px[..., 3]
    ys_, xs_ = np.nonzero(alpha > 0.02)
    x0, x1 = max(0, xs_.min() - 4), min(rx, xs_.max() + 5)
    y0, y1 = max(0, ys_.min() - 4), min(ry, ys_.max() + 5)
    print('BOX', name, sun_key, x0, x1, y0, y1, rx, ry)
    crop = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.float32)
    crop[..., 3] = alpha[y0:y1, x0:x1]
    out = bpy.data.images.new("crop", x1 - x0, y1 - y0, alpha=True)
    out.pixels[:] = crop[::-1].ravel()
    path = os.path.join(OUT, "%s_%s.png" % (name, sun_key))
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    os.remove(raw)
    return {"anchor": [round(ax - x0, 1), round(ay - y0, 1)]}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(br.PIECES)
    book = json.load(open(BOOK)) if os.path.exists(BOOK) else {}
    for n in only:
        book[n] = {s: render(n, s) for s in SUNS}
        print("SHADOW", n, book[n])
    json.dump(book, open(BOOK, "w"), indent=1)
