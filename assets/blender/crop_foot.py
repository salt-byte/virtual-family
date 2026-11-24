"""Crops Blender renders to their footprints, from the FOOT lines the build scripts print:
FOOT <name> <left> <right> <bottom> <rx> <ry>. Top is the highest drawn pixel.

    python3 assets/blender/crop_foot.py <foot lines file> <picture dir>
"""
import sys

from PIL import Image

lines, out = sys.argv[1], sys.argv[2]
for line in open(lines):
    if not line.startswith("FOOT"):
        continue
    _, name, left, right, bottom, _rx, _ry = line.split()
    path = "%s/%s.png" % (out, name)
    im = Image.open(path)
    top = im.getbbox()[1]
    im.crop((int(left), top, int(right), int(bottom))).save(path)
    print(name, int(right) - int(left), int(bottom) - top)
