#!/usr/bin/env python3
"""Put a raw white-model render (assets/gen/ref/_white_<name>_raw.png, transparent) on the
1536 x 1536 #F0F0F0 canvas the image model paints over: the piece scaled so its box is about
950 px tall or 1100 px wide (never smaller than rendered), centred.

  python3 assets/gen/white_canvas.py <name> [name ...]
"""
import sys
from pathlib import Path

from PIL import Image

REF = Path(__file__).resolve().parent / "ref"
for n in sys.argv[1:]:
    raw = Image.open(REF / ("_white_%s_raw.png" % n)).convert("RGBA")
    raw = raw.crop(raw.getbbox())
    k = max(1.0, min(950 / raw.height, 1100 / raw.width))
    raw = raw.resize((round(raw.width * k), round(raw.height * k)), Image.LANCZOS)
    out = Image.new("RGB", (1536, 1536), (240, 240, 240))
    out.paste(raw, ((1536 - raw.width) // 2, (1536 - raw.height) // 2), raw)
    out.save(REF / ("white_%s.png" % n))
    print(n, raw.size)
