"""White models of the house's starting furniture, in the chunky kitchen's proportions (fat
tops, round edges, stubby legs). Every piece is modelled facing south: its long side along x,
its front toward -y (the camera sees the south and east faces), the middle of its footprint
at `at`, standing on z = 0. Real sizes follow game/packs/qijia/art.json iso.sizes and stay
inside the footprint (design/PLACEMENT.md section 4).

Used by build_white.py and build_ruler.py; materials come from their palette dict `m`.
"""
import math

from build_toon3d_kitchen import box, cyl, sphere, lathe
from build_chunky_kitchen import torus


def _legs(m, at, w, d, h, t, inset=0.04, key="wood_dark"):
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((t, t, h), (at.x + sx * (w / 2 - inset - t / 2), at.y + sy * (d / 2 - inset - t / 2), 0), m[key], bevel=0.03)


def dining_table(m, at):
    """A square-ish eight-immortals table with a long bench on each long side, a teapot and
    two bowls on top. 1.6 x 1.3."""
    w, d, h = 1.4, 0.78, 0.78
    box((w, d, 0.08), (at.x, at.y, h - 0.08), m["wood"], bevel=0.035)
    _legs(m, at, w, d, h - 0.08, 0.1)
    for sy in (-1, 1):  # aprons under the top
        box((w - 0.2, 0.04, 0.09), (at.x, at.y + sy * (d / 2 - 0.08), h - 0.17), m["wood_dark"], bevel=0.015)
    for sx in (-1, 1):
        box((0.04, d - 0.2, 0.09), (at.x + sx * (w / 2 - 0.08), at.y, h - 0.17), m["wood_dark"], bevel=0.015)
    for sy in (-1, 1):  # benches
        by = at.y + sy * 0.53
        box((1.5, 0.24, 0.06), (at.x, by, 0.42), m["wood"], bevel=0.025)
        for sx in (-1, 1):
            box((0.07, 0.18, 0.42), (at.x + sx * 0.62, by, 0), m["wood_dark"], bevel=0.02)
        box((1.2, 0.04, 0.05), (at.x, by, 0.14), m["wood_dark"], bevel=0.015)
    # A round-bellied teapot and two bowls.
    lathe([(0.0, 0.0), (0.07, 0.0), (0.1, 0.05), (0.1, 0.1), (0.07, 0.15), (0.04, 0.16)], (at.x + 0.15, at.y + 0.05, h), m["white"])
    sphere(0.025, (at.x + 0.15, at.y + 0.05, h + 0.18), m["blue"])
    cyl(0.016, 0.1, (at.x + 0.26, at.y + 0.05, h + 0.06), m["white"], rot=(0, math.radians(50), 0))
    for k, x in enumerate((-0.2, -0.38)):
        lathe([(0.0, 0.0), (0.04, 0.0), (0.07, 0.04), (0.075, 0.055)], (at.x + x, at.y - 0.12 + k * 0.14, h), m["white"])


def altar(m, at):
    """A long narrow offering table with turned-up ends against the north wall: a brass
    censer in the middle, a candlestick each side, a plate of fruit. 1.3 x 0.45."""
    w, d, h = 1.3, 0.42, 0.88
    box((w - 0.1, d, 0.06), (at.x, at.y, h - 0.06), m["wood_dark"], bevel=0.02)
    for sx in (-1, 1):  # the turned-up ends
        box((0.12, d, 0.05), (at.x + sx * (w / 2 - 0.06), at.y, h - 0.04), m["wood_dark"], bevel=0.02)
        box((0.06, d, 0.06), (at.x + sx * (w / 2 - 0.03), at.y, h + 0.0), m["wood_dark"], bevel=0.025)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.07, 0.07, h - 0.06), (at.x + sx * (w / 2 - 0.2), at.y + sy * (d / 2 - 0.06), 0), m["wood_dark"], bevel=0.02)
        box((0.05, d - 0.14, 0.04), (at.x + sx * (w / 2 - 0.2), at.y, 0.16), m["wood_dark"], bevel=0.012)
    box((w - 0.5, 0.04, 0.12), (at.x, at.y - d / 2 + 0.05, h - 0.18), m["wood"], bevel=0.015)
    top = h
    lathe([(0.0, 0.0), (0.06, 0.0), (0.09, 0.03), (0.1, 0.08), (0.08, 0.11), (0.085, 0.12)], (at.x, at.y + 0.02, top), m["brass"])
    for k in range(3):
        cyl(0.006, 0.14, (at.x - 0.03 + k * 0.03, at.y + 0.02, top + 0.1), m["dark"], verts=8, bevel=0)
    for sx in (-1, 1):
        x = at.x + sx * 0.36
        lathe([(0.0, 0.0), (0.05, 0.0), (0.05, 0.02), (0.02, 0.04), (0.015, 0.16), (0.04, 0.18)], (x, at.y + 0.04, top), m["brass"])
        cyl(0.022, 0.12, (x, at.y + 0.04, top + 0.18), m["red"], bevel=0.005)
    lathe([(0.0, 0.0), (0.08, 0.0), (0.11, 0.02)], (at.x + 0.18, at.y - 0.05, top), m["white"])
    for k in range(3):
        a = k * math.tau / 3
        sphere(0.04, (at.x + 0.18 + 0.04 * math.cos(a), at.y - 0.05 + 0.04 * math.sin(a), top + 0.05), m["orange"])
    sphere(0.04, (at.x + 0.18, at.y - 0.05, top + 0.11), m["orange"])


def desk(m, at):
    """A writing desk: a thick top, a drawer under one end with a brass ring, stubby legs; an
    ink stone, a brush pot with brushes, a stack of thread-bound books, a sheet of paper.
    1.2 x 0.6."""
    w, d, h = 1.18, 0.58, 0.76
    box((w, d, 0.07), (at.x, at.y, h - 0.07), m["wood"], bevel=0.03)
    _legs(m, at, w, d, h - 0.07, 0.08)
    box((0.42, d - 0.1, 0.14), (at.x + 0.3, at.y, h - 0.21), m["wood"], bevel=0.02)
    sphere(0.025, (at.x + 0.3, at.y - d / 2 + 0.03, h - 0.14), m["brass"])
    for sx in (-1, 1):
        box((0.05, d - 0.16, 0.04), (at.x + sx * (w / 2 - 0.08), at.y, 0.12), m["wood_dark"], bevel=0.012)
    box((0.18, 0.12, 0.03), (at.x - 0.3, at.y - 0.06, h), m["dark"], bevel=0.01)
    cyl(0.05, 0.13, (at.x - 0.42, at.y + 0.14, h), m["blue"], bevel=0.01)
    for k in range(3):
        cyl(0.007, 0.16, (at.x - 0.43 + k * 0.015, at.y + 0.14, h + 0.1), m["wood_pale"], verts=8, bevel=0)
    for k in range(3):
        box((0.22, 0.15, 0.03), (at.x + 0.3 + k * 0.01, at.y + 0.08, h + k * 0.032), m["blue_dk"] if k % 2 else m["blue"], bevel=0.008)
    box((0.26, 0.18, 0.004), (at.x - 0.02, at.y - 0.04, h), m["white"], bevel=0)


def keepsake_chest(m, at):
    """A small old chest on the floor: a rounded lid, brass corner plates and a hasp at the
    front. 0.55 x 0.33."""
    w, d = 0.52, 0.32
    box((w, d, 0.24), (at.x, at.y, 0.04), m["wood"], bevel=0.025)
    box((w + 0.02, d + 0.02, 0.09), (at.x, at.y, 0.28), m["wood_dark"], bevel=0.04)
    for sx in (-1, 1):
        box((0.06, 0.06, 0.04), (at.x + sx * (w / 2 - 0.04), at.y - d / 2 + 0.03, 0), m["wood_dark"], bevel=0.015)
        box((0.06, 0.06, 0.04), (at.x + sx * (w / 2 - 0.04), at.y + d / 2 - 0.03, 0), m["wood_dark"], bevel=0.015)
        box((0.07, 0.012, 0.07), (at.x + sx * (w / 2 - 0.035), at.y - d / 2 - 0.004, 0.22), m["brass"], bevel=0.005)
    box((0.08, 0.014, 0.11), (at.x, at.y - d / 2 - 0.006, 0.2), m["brass"], bevel=0.006)
    sphere(0.018, (at.x, at.y - d / 2 - 0.02, 0.22), m["brass"])


def kang(m, at):
    """A heated earthen bed against the north wall: a plastered platform with a wooden edge
    along the front and a stoke hole, a straw mat, folded quilts stacked at the back and a
    low kang table. 2.0 x 1.38 (inside its 3 x 2 cells)."""
    w, d, h = 2.0, 1.38, 0.55
    box((w, d, h), (at.x, at.y, 0), m["stove"], bevel=0.04)
    box((w + 0.02, 0.1, 0.08), (at.x, at.y - d / 2 + 0.04, h - 0.05), m["wood_dark"], bevel=0.025)
    box((0.22, 0.03, 0.16), (at.x + 0.6, at.y - d / 2 - 0.0, 0.08), m["dark"], bevel=0.02)
    box((w - 0.1, d - 0.16, 0.025), (at.x, at.y + 0.02, h), m["straw"], bevel=0.01)
    # Quilts folded and stacked at the back, a pillow on top.
    for k, key in enumerate(("blue", "red", "blue_dk")):
        box((0.7, 0.34, 0.1), (at.x - 0.45, at.y + d / 2 - 0.26, h + 0.025 + k * 0.1), m[key], bevel=0.045)
    box((0.42, 0.2, 0.1), (at.x - 0.45, at.y + d / 2 - 0.26, h + 0.33), m["cream"], bevel=0.045)
    # A low kang table.
    box((0.55, 0.38, 0.04), (at.x + 0.35, at.y - 0.05, h + 0.24), m["wood"], bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.05, 0.05, 0.22), (at.x + 0.35 + sx * 0.22, at.y - 0.05 + sy * 0.14, h + 0.025), m["wood_dark"], bevel=0.015)
    lathe([(0.0, 0.0), (0.04, 0.0), (0.065, 0.04), (0.07, 0.05)], (at.x + 0.3, at.y - 0.05, h + 0.28), m["white"])


def bookshelf(m, at):
    """A tall open bookshelf against the north wall: a heavy frame, four shelves of
    thread-bound books lying flat and standing, a few scrolls and a vase. 1.7 x 0.4."""
    w, d, h = 1.7, 0.38, 1.65
    for sx in (-1, 1):
        box((0.07, d, h), (at.x + sx * (w / 2 - 0.035), at.y, 0), m["wood_dark"], bevel=0.025)
    box((w, 0.03, h - 0.1), (at.x, at.y + d / 2 - 0.015, 0.05), m["wood_dark"], bevel=0.01)
    box((w + 0.08, d + 0.04, 0.07), (at.x, at.y, h), m["wood"], bevel=0.03)
    shelves = [0.06, 0.45, 0.85, 1.25]
    for z in shelves:
        box((w - 0.1, d - 0.02, 0.04), (at.x, at.y, z), m["wood"], bevel=0.012)
    cols = ["blue", "blue_dk", "cream", "red", "yellow", "blue"]
    for i, z in enumerate(shelves):
        x = at.x - w / 2 + 0.14
        k = i
        while x < at.x + w / 2 - 0.2:
            if (k + i) % 4 == 0:  # a stack lying flat
                for s in range(3):
                    box((0.2, 0.15, 0.035), (x + 0.1, at.y + 0.02, z + 0.04 + s * 0.037), m[cols[(k + s) % 6]], bevel=0.008)
                x += 0.26
            elif (k + i) % 4 == 2:  # scrolls
                for s in range(3):
                    cyl(0.025, 0.28, (x + 0.06, at.y - 0.05 + s * 0.06, z + 0.07), m["cream"], bevel=0.005,
                        rot=(0, math.radians(90), 0))
                x += 0.12
            else:  # books standing
                for s in range(4):
                    box((0.035, 0.16, 0.24 - (s % 2) * 0.03), (x + s * 0.04, at.y + 0.02, z + 0.04), m[cols[(k + s) % 6]], bevel=0.006)
                x += 0.2
            k += 1
    lathe([(0.0, 0.0), (0.05, 0.0), (0.08, 0.08), (0.06, 0.16), (0.03, 0.2), (0.04, 0.23)], (at.x + w / 2 - 0.16, at.y, 1.29), m["blue"])


def woodpile(m, at):
    """Split firewood stacked against the north wall, the cut ends toward the camera, a
    stump with a hatchet in front. 1.8 x 1.0."""
    r = 0.075
    L = 0.7
    rows = [10, 9, 8, 7, 5]
    for k, n in enumerate(rows):
        for i in range(n):
            x = at.x - (n - 1) * r + i * 2 * r
            cyl(r * (0.92 + 0.08 * ((i * 7 + k * 3) % 3) / 2), L, (x, at.y + 0.1, r + k * r * 1.75), m["wood_dark"],
                verts=7, bevel=0.012, rot=(math.radians(-90), 0, 0))
    cyl(0.17, 0.32, (at.x + 0.55, at.y - 0.32, 0), m["wood"], bevel=0.03)
    box((0.03, 0.14, 0.1), (at.x + 0.55, at.y - 0.36, 0.32), m["iron"], bevel=0.01)
    cyl(0.018, 0.36, (at.x + 0.55, at.y - 0.3, 0.4), m["wood_pale"], bevel=0.006, rot=(math.radians(-70), 0, 0))


def well_head(m, at):
    """A round stone well curb with a wooden windlass over it: two posts, a crank roller with
    rope wound on, a wooden bucket on the rim. 1.2 x 1.2."""
    lathe([(0.36, 0.0), (0.5, 0.0), (0.52, 0.05), (0.5, 0.5), (0.53, 0.55), (0.52, 0.6), (0.36, 0.6), (0.36, 0.0)], at, m["stove_top"])
    cyl(0.36, 0.02, (at.x, at.y, at.z + 0.35), m["dark"], bevel=0)
    for sx in (-1, 1):
        box((0.09, 0.09, 1.25), (at.x + sx * 0.55, at.y, 0), m["wood_dark"], bevel=0.025)
    cyl(0.07, 1.0, (at.x, at.y, 1.08), m["wood"], bevel=0.02, rot=(0, math.radians(90), 0))
    cyl(0.085, 0.3, (at.x - 0.05, at.y, 1.08), m["straw"], bevel=0.02, rot=(0, math.radians(90), 0))
    box((0.04, 0.04, 0.22), (at.x + 0.66, at.y, 0.98), m["wood_dark"], bevel=0.01)
    box((0.18, 0.04, 0.04), (at.x + 0.74, at.y, 0.94), m["wood_pale"], bevel=0.01)
    cyl(0.008, 0.5, (at.x - 0.05, at.y - 0.08, 0.58), m["straw"], verts=8, bevel=0)
    lathe([(0.0, 0.0), (0.12, 0.0), (0.14, 0.2), (0.135, 0.22)], (at.x + 0.3, at.y - 0.35, 0.6), m["wood"])
    torus(0.14, 0.012, (at.x + 0.3, at.y - 0.35, 0.78), m["iron"])


def millstone(m, at):
    """A stone mill: a wide round base with a lip and a spout, the turning upper stone with
    its feed hole, a wooden push pole stuck out to the east. 0.9 x 0.9."""
    cyl(0.45, 0.3, at, m["stove_top"], bevel=0.03)
    cyl(0.42, 0.06, (at.x, at.y, 0.3), m["stove_top"], bevel=0.02)
    box((0.14, 0.12, 0.06), (at.x, at.y - 0.47, 0.26), m["stove_top"], bevel=0.02)
    cyl(0.33, 0.13, (at.x, at.y, 0.36), m["stove_top"], bevel=0.02)
    cyl(0.33, 0.13, (at.x, at.y, 0.49), m["stove_top"], bevel=0.02)
    cyl(0.05, 0.02, (at.x + 0.1, at.y, 0.62), m["dark"], bevel=0)
    cyl(0.035, 0.55, (at.x + 0.55, at.y, 0.56), m["wood"], bevel=0.01, rot=(0, math.radians(90), 0))
    box((0.06, 0.06, 0.12), (at.x + 0.3, at.y, 0.5), m["wood_dark"], bevel=0.015)


def grape_trellis(m, at):
    """A bamboo-and-wood grape arbour: four posts, beams and slats on top heaped with broad
    leaves, bunches of grapes hanging under. 2.6 x 1.4."""
    w, d, h = 2.5, 1.3, 1.9
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.06, h, (at.x + sx * (w / 2 - 0.08), at.y + sy * (d / 2 - 0.08), 0), m["wood"], bevel=0.015)
    for sy in (-1, 1):
        cyl(0.05, w, (at.x, at.y + sy * (d / 2 - 0.08), h), m["wood_dark"], bevel=0.01, rot=(0, math.radians(90), 0))
    for k in range(6):
        cyl(0.03, d + 0.1, (at.x - w / 2 + 0.2 + k * (w - 0.4) / 5, at.y, h + 0.07), m["wood_pale"], bevel=0.008,
            rot=(math.radians(90), 0, 0))
    k = 0
    for ix in range(9):
        for iy in range(5):
            x = at.x - w / 2 + 0.15 + ix * (w - 0.3) / 8 + ((iy * 13) % 5 - 2) * 0.02
            y = at.y - d / 2 + 0.12 + iy * (d - 0.24) / 4
            sphere(0.17, (x, y, h + 0.14 + (ix + iy) % 3 * 0.03), m["green"], (1.15, 1.0, 0.45))
    for x, y in ((-0.7, -0.4), (0.1, -0.45), (0.8, -0.35), (-0.3, 0.3)):
        for j in range(6):
            sphere(0.045, (at.x + x + (j % 2) * 0.06 - 0.03, at.y + y, h - 0.08 - j * 0.045), m["blue_dk"])
    for sy in (-1, 1):  # vines up the front posts
        cyl(0.025, h, (at.x - w / 2 + 0.14, at.y + sy * (d / 2 - 0.14), 0), m["green"], verts=8, bevel=0)


def stone_bench(m, at):
    """A bench of dressed stone: a thick slab on two blocks. 1.2 x 0.4."""
    box((1.15, 0.38, 0.1), (at.x, at.y, 0.32), m["stove_top"], bevel=0.03)
    for sx in (-1, 1):
        box((0.22, 0.3, 0.32), (at.x + sx * 0.38, at.y, 0), m["stove_top"], bevel=0.03)


def trash_basket(m, at):
    """A woven bamboo basket for sweepings, a thick rim, a little rubbish heaped inside.
    0.5 x 0.5."""
    lathe([(0.0, 0.0), (0.16, 0.0), (0.2, 0.05), (0.24, 0.3), (0.25, 0.34)], at, m["straw"])
    torus(0.245, 0.03, (at.x, at.y, 0.34), m["wood_pale"])
    # Sweepings: a low uneven layer of straw and a few leaves lying flat, not a ball.
    cyl(0.215, 0.03, (at.x, at.y, 0.29), m["wood_dark"], bevel=0.01)
    for k, (x, y, a) in enumerate(((-0.08, -0.06, 20), (0.06, 0.02, 70), (-0.02, 0.09, 130), (0.1, -0.08, 160),
                                   (-0.12, 0.05, 45), (0.03, -0.12, 100))):
        box((0.12, 0.05, 0.015), (at.x + x, at.y + y, 0.315 + (k % 3) * 0.008), m["green" if k % 2 else "straw"],
            bevel=0.006, rot=(0, 0, math.radians(a)))


def clothesline(m, at):
    """Two wooden posts with a cross piece each and a rope between, a blue jacket, a pale
    sheet and a red cloth pegged on. 2.6 x 0.3."""
    w = 2.5
    for sx in (-1, 1):
        cyl(0.045, 1.55, (at.x + sx * w / 2, at.y, 0), m["wood"], bevel=0.012)
        box((0.06, 0.3, 0.05), (at.x + sx * w / 2, at.y, 1.48), m["wood_dark"], bevel=0.012)
    cyl(0.01, w, (at.x, at.y, 1.5), m["straw"], verts=8, bevel=0, rot=(0, math.radians(90), 0))
    box((0.55, 0.02, 0.6), (at.x - 0.6, at.y, 0.9), m["blue"], bevel=0.01)
    box((0.7, 0.02, 0.8), (at.x + 0.15, at.y, 0.7), m["cream"], bevel=0.01)
    box((0.35, 0.02, 0.45), (at.x + 0.8, at.y, 1.05), m["red"], bevel=0.01)


def grain_heap(m, at):
    """A heap of threshed grain on a round reed mat, a wooden shovel stuck in it. 1.2 x 1.2."""
    cyl(0.6, 0.03, at, m["straw"], bevel=0.01)
    lathe([(0.0, 0.03), (0.52, 0.03), (0.45, 0.14), (0.32, 0.32), (0.16, 0.46), (0.0, 0.5)], at, m["yellow"])
    box((0.2, 0.03, 0.28), (at.x + 0.2, at.y - 0.12, 0.3), m["wood_pale"], bevel=0.01, rot=(math.radians(-15), math.radians(25), 0))
    cyl(0.02, 0.55, (at.x + 0.3, at.y - 0.18, 0.62), m["wood"], bevel=0.005, rot=(math.radians(-15), math.radians(25), 0))


def trough(m, at):
    """A long stone pig trough, thick walls, slop inside. 1.6 x 0.4."""
    w, d, h, t = 1.6, 0.4, 0.3, 0.08
    box((w, d, 0.08), (at.x, at.y, 0), m["stove_top"], bevel=0.03)
    for sy in (-1, 1):
        box((w, t, h), (at.x, at.y + sy * (d / 2 - t / 2), 0), m["stove_top"], bevel=0.03)
    for sx in (-1, 1):
        box((t, d, h), (at.x + sx * (w / 2 - t / 2), at.y, 0), m["stove_top"], bevel=0.03)
    box((w - 2 * t, d - 2 * t, 0.12), (at.x, at.y, 0.08), m["cream"], bevel=0.01)


def washtub(m, at):
    """A round wooden washtub of staves with two iron hoops and side handles, water, a
    washboard leaning in and a blue shirt over the rim. 0.62 x 0.62."""
    lathe([(0.0, 0.0), (0.25, 0.0), (0.27, 0.05), (0.3, 0.3), (0.31, 0.32)], at, m["wood"])
    for z in (0.07, 0.24):
        torus(0.282 + z * 0.09, 0.012, (at.x, at.y, z), m["iron"])
    for sx in (-1, 1):
        box((0.05, 0.1, 0.05), (at.x + sx * 0.31, at.y, 0.25), m["wood_dark"], bevel=0.015)
    cyl(0.285, 0.02, (at.x, at.y, 0.25), m["water"], bevel=0)
    box((0.2, 0.03, 0.42), (at.x + 0.08, at.y + 0.12, 0.12), m["wood_pale"], bevel=0.015, rot=(math.radians(-25), 0, math.radians(10)))
    box((0.24, 0.16, 0.03), (at.x - 0.17, at.y - 0.12, 0.3), m["blue"], bevel=0.015, rot=(math.radians(20), 0, math.radians(-30)))


def coop(m, at):
    """A bamboo hen coop: a dome of woven strips on a ring, a hen standing beside it.
    1.3 x 1.0."""
    cx = at.x - 0.15
    torus(0.45, 0.03, (cx, at.y, 0.04), m["straw"])
    lathe([(0.45, 0.04), (0.46, 0.3), (0.4, 0.55), (0.25, 0.72), (0.0, 0.78)], (cx, at.y, 0), m["straw"], verts=20)
    torus(0.05, 0.015, (cx, at.y, 0.79), m["wood_dark"])
    hx, hy = at.x + 0.45, at.y - 0.2  # the hen
    sphere(0.14, (hx, hy, 0.22), m["orange"], (1.25, 0.85, 0.9))
    sphere(0.08, (hx + 0.15, hy, 0.37), m["orange"])
    box((0.05, 0.02, 0.06), (hx + 0.15, hy, 0.43), m["red"], bevel=0.01)
    cyl(0.015, 0.03, (hx + 0.24, hy, 0.36), m["yellow"], rot=(0, math.radians(90), 0))
    sphere(0.1, (hx - 0.16, hy, 0.3), m["dark"], (0.6, 0.5, 1.0))
    for dy in (-0.04, 0.04):
        cyl(0.012, 0.1, (hx, hy + dy, 0.0), m["yellow"])


def loom(m, at):
    """A wooden hand loom with a bench seat at the front: two tall side frames, the warp
    threads stretched from the back beam to the cloth beam, a heddle frame hanging in the
    middle. 1.2 x 1.0."""
    w, d = 1.1, 0.95
    for sx in (-1, 1):
        x = at.x + sx * (w / 2 - 0.04)
        box((0.07, 0.07, 1.25), (x, at.y + d / 2 - 0.1, 0), m["wood_dark"], bevel=0.02)  # back posts
        box((0.07, 0.07, 0.75), (x, at.y - 0.05, 0), m["wood_dark"], bevel=0.02)          # front posts
        box((0.06, d - 0.15, 0.06), (x, at.y + 0.02, 0.7), m["wood_dark"], bevel=0.015)   # side rails
        box((0.06, d - 0.15, 0.05), (x, at.y + 0.02, 0.12), m["wood_dark"], bevel=0.015)
    cyl(0.05, w, (at.x, at.y + d / 2 - 0.1, 1.2), m["wood"], rot=(0, math.radians(90), 0))     # back beam
    cyl(0.06, w, (at.x, at.y - 0.05, 0.72), m["wood"], rot=(0, math.radians(90), 0))          # cloth beam
    box((w - 0.18, 0.005, 0.5), (at.x, at.y + 0.17, 0.72), m["cream"], bevel=0, rot=(math.radians(-48), 0, 0))
    box((w - 0.2, 0.05, 0.3), (at.x, at.y + 0.15, 0.95), m["wood_pale"], bevel=0.01)          # heddle frame
    box((w - 0.25, 0.008, 0.2), (at.x, at.y - 0.06, 0.78), m["blue"], bevel=0)                 # woven cloth
    box((w - 0.1, 0.25, 0.05), (at.x, at.y - d / 2 + 0.05, 0.4), m["wood"], bevel=0.02)       # seat
    for sx in (-1, 1):
        box((0.06, 0.2, 0.4), (at.x + sx * (w / 2 - 0.15), at.y - d / 2 + 0.05, 0), m["wood_dark"], bevel=0.015)


def embroidery_frame(m, at):
    """An embroidery hoop on a small wooden stand: a round hoop with stretched cloth and a
    red flower half stitched, three splayed legs. 0.6 x 0.5."""
    for sx in (-1, 1):
        box((0.05, 0.05, 0.9), (at.x + sx * 0.2, at.y - 0.05, 0), m["wood_dark"], bevel=0.015, rot=(math.radians(-8), math.radians(sx * 10), 0))
    box((0.05, 0.05, 0.85), (at.x, at.y + 0.18, 0), m["wood_dark"], bevel=0.015, rot=(math.radians(18), 0, 0))
    box((0.4, 0.04, 0.04), (at.x, at.y - 0.03, 0.45), m["wood_dark"], bevel=0.01)
    c = (at.x, at.y - 0.02, 0.82)
    cyl(0.22, 0.015, c, m["cream"], bevel=0, rot=(math.radians(80), 0, 0))
    o = torus(0.225, 0.022, c, m["wood_pale"])
    o.rotation_euler = (math.radians(80), 0, 0)
    sphere(0.06, (at.x - 0.02, at.y - 0.035, 0.84), m["red"], (1, 0.15, 1))
    sphere(0.03, (at.x + 0.07, at.y - 0.035, 0.76), m["green"], (1, 0.15, 0.6))


def carpenter_bench(m, at):
    """A long low workbench of thick timber on splayed legs, a wooden plane on top, curls
    of shavings, a saw leaning against it. 1.3 x 0.36."""
    w, d, h = 1.3, 0.34, 0.5
    box((w, d, 0.1), (at.x, at.y, h - 0.1), m["wood"], bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.07, 0.07, h - 0.08), (at.x + sx * (w / 2 - 0.16), at.y + sy * 0.1, 0), m["wood_dark"], bevel=0.02,
                rot=(math.radians(sy * 8), math.radians(-sx * 8), 0))
        box((0.05, 0.22, 0.05), (at.x + sx * (w / 2 - 0.15), at.y, 0.14), m["wood_dark"], bevel=0.015)
    box((0.3, 0.09, 0.08), (at.x + 0.05, at.y, h), m["wood_dark"], bevel=0.02)
    box((0.04, 0.07, 0.03), (at.x + 0.05, at.y, h + 0.08), m["iron"], bevel=0.008)
    cyl(0.02, 0.14, (at.x + 0.05, at.y, h + 0.15), m["wood_pale"], rot=(0, math.radians(90), 0))
    for k, x in enumerate((0.35, 0.42, 0.48)):
        o = torus(0.03, 0.008, (at.x + x, at.y + (k - 1) * 0.05, h + 0.02), m["wood_pale"])
        o.rotation_euler = (math.radians(70), 0, math.radians(k * 40))


def tofu_box(m, at):
    """A shallow wooden tofu press box with corner posts, a block of white tofu inside under a
    damp cloth folded back. 0.5 x 0.5."""
    s, h = 0.48, 0.26
    for sy in (-1, 1):
        box((s, 0.04, h), (at.x, at.y + sy * (s / 2 - 0.02), 0), m["wood"], bevel=0.012)
    for sx in (-1, 1):
        box((0.04, s - 0.08, h), (at.x + sx * (s / 2 - 0.02), at.y, 0), m["wood"], bevel=0.012)
        for sy in (-1, 1):
            box((0.05, 0.05, h + 0.05), (at.x + sx * (s / 2 - 0.02), at.y + sy * (s / 2 - 0.02), 0), m["wood_dark"], bevel=0.012)
    box((s - 0.1, s - 0.1, 0.2), (at.x, at.y, 0.04), m["white"], bevel=0.02)
    box((0.3, 0.42, 0.02), (at.x + 0.05, at.y, 0.24), m["cream"], bevel=0.008, rot=(0, math.radians(-4), 0))


def peddler_pole(m, at):
    """A peddler's carrying pole across two round baskets on ropes, the baskets piled with
    small wares. 1.35 x 0.4."""
    for sx in (-1, 1):
        x = at.x + sx * 0.48
        lathe([(0.0, 0.0), (0.14, 0.0), (0.18, 0.04), (0.19, 0.3), (0.2, 0.32)], (x, at.y, 0), m["straw"])
        torus(0.195, 0.018, (x, at.y, 0.32), m["wood_pale"])
        sphere(0.12, (x, at.y, 0.3), m["red" if sx < 0 else "blue"], (1, 1, 0.45))
        for a in (0, 120, 240):
            r = math.radians(a)
            dx, dy = math.cos(r) * 0.17, math.sin(r) * 0.17
            top = (x, at.y, 1.02)
            mid = (x + dx / 2, at.y + dy / 2, (0.32 + 1.02) / 2)
            ln = math.dist((x + dx, at.y + dy, 0.32), top)
            tilt = math.atan2(math.hypot(dx, dy), 0.7)
            cyl(0.006, ln, mid, m["straw"], verts=6, bevel=0, rot=(math.atan2(dy, 0.7) * -1, math.atan2(dx, 0.7), 0))
    cyl(0.03, 1.35, (at.x, at.y, 1.04), m["wood"], rot=(0, math.radians(90), 0))


def herb_grinder(m, at):
    """An iron boat-shaped herb roller: a long trough with a heavy grinding wheel in it and
    a wooden handle through the wheel. 0.55 x 0.25."""
    o = lathe([(0.0, 0.0), (0.04, 0.0), (0.1, 0.06), (0.12, 0.12), (0.125, 0.13)], (at.x, at.y, 0), m["iron"])
    o.scale = (2.2, 1.0, 1.0)
    cyl(0.1, 0.03, (at.x, at.y, 0.15), m["iron"], rot=(math.radians(90), 0, 0))
    cyl(0.018, 0.4, (at.x, at.y, 0.15), m["wood"], rot=(math.radians(90), 0, 0))
    cyl(0.025, 0.1, (at.x, at.y - 0.2, 0.15), m["wood_dark"], rot=(math.radians(90), 0, 0))
    cyl(0.025, 0.1, (at.x, at.y + 0.2, 0.15), m["wood_dark"], rot=(math.radians(90), 0, 0))
    for k, x in enumerate((-0.15, 0.17)):
        sphere(0.03, (at.x + x, at.y, 0.09), m["green" if k else "orange"], (1.4, 1, 0.5))


def garden(m, at):
    """A vegetable bed: dark tilled earth in ridged rows inside a low wattle fence, rows of
    leafy greens. 2.0 x 1.4."""
    w, d = 2.0, 1.4
    box((w - 0.1, d - 0.1, 0.06), (at.x, at.y, 0), m["wood_dark"], bevel=0.02)
    for k in range(3):
        y = at.y - d / 2 + 0.3 + k * (d - 0.6) / 2
        box((w - 0.3, 0.26, 0.06), (at.x, y, 0.05), m["wood_dark"], bevel=0.04)
        for j in range(5):
            x = at.x - w / 2 + 0.35 + j * (w - 0.7) / 4
            for a in range(5):
                r = math.radians(a * 72 + j * 20)
                sphere(0.07, (x + math.cos(r) * 0.06, y + math.sin(r) * 0.06, 0.16), m["green"], (1.1, 0.6, 0.45))
    n = 14
    for i in range(n + 1):
        for (x, y) in ((at.x - w / 2 + i * w / n, at.y - d / 2), (at.x - w / 2 + i * w / n, at.y + d / 2)):
            cyl(0.02, 0.32, (x, y, 0), m["wood"], verts=8, bevel=0)
    for i in range(1, 10):
        for x in (at.x - w / 2, at.x + w / 2):
            cyl(0.02, 0.32, (x, at.y - d / 2 + i * d / 10, 0), m["wood"], verts=8, bevel=0)
    for z in (0.12, 0.25):
        for sy in (-1, 1):
            cyl(0.012, w, (at.x, at.y + sy * d / 2, z), m["wood_pale"], verts=8, bevel=0, rot=(0, math.radians(90), 0))
        for sx in (-1, 1):
            cyl(0.012, d, (at.x + sx * w / 2, at.y, z), m["wood_pale"], verts=8, bevel=0, rot=(math.radians(90), 0, 0))


def bird_cage(m, at):
    """A round bamboo bird cage on a little stand: a domed top with a hook, thin bars, a
    perch, a yellow bird. 0.35 x 0.35, about 0.75 high with the stand."""
    base = 0.18
    box((0.3, 0.3, base), (at.x, at.y, 0), m["wood_dark"], bevel=0.02)
    cyl(0.16, 0.04, (at.x, at.y, base), m["wood"], bevel=0.01)
    n = 16
    for i in range(n):
        r = math.radians(i * 360 / n)
        cyl(0.006, 0.38, (at.x + math.cos(r) * 0.15, at.y + math.sin(r) * 0.15, base + 0.04), m["straw"], verts=6, bevel=0)
    for z in (0.14, 0.38):
        torus(0.15, 0.008, (at.x, at.y, base + z), m["straw"])
    lathe([(0.152, 0.0), (0.13, 0.06), (0.08, 0.11), (0.0, 0.13)], (at.x, at.y, base + 0.42), m["straw"], verts=24)
    o = torus(0.035, 0.008, (at.x, at.y, base + 0.6), m["brass"])
    o.rotation_euler = (math.radians(90), 0, 0)
    cyl(0.006, 0.26, (at.x, at.y, base + 0.18), m["wood"], verts=6, bevel=0, rot=(0, math.radians(90), 0))
    sphere(0.05, (at.x, at.y, base + 0.24), m["yellow"], (1.2, 0.9, 1.0))
    sphere(0.035, (at.x + 0.05, at.y, base + 0.3), m["yellow"])
