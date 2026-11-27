#!/usr/bin/env python3
"""Spread the game plan (assets/gen/ref/layout.json) k times wider, in whole cells: every room,
the compound, the wall lines and where each piece and person stands; pieces keep their
footprint (real size), doors keep their width. Neighbouring rooms stay touching (each edge
maps on its own: x' = round(x * k)). Writes assets/gen/ref/layout_x<k>.json — the numbers
rooms.json would take.

  python3 assets/gen/scale_layout.py 1.5
"""
import json
import math
import sys
from pathlib import Path

REF = Path(__file__).resolve().parent / "ref"


def main(k):
    d = json.load(open(REF / "layout.json"))
    def e(v):  # an edge
        return int(math.floor(v * k + 0.5))
    rooms = {}
    for r in d["rooms"]:
        x, y = e(r["x"]), e(r["y"])
        r2 = dict(r, x=x, y=y, w=e(r["x"] + r["w"]) - x, h=e(r["y"] + r["h"]) - y)
        rooms[r["id"]] = (r, r2)
    c = d["compound"]
    d["compound"] = [e(c[0]), e(c[1]), e(c[0] + c[2]) - e(c[0]), e(c[1] + c[3]) - e(c[1])]
    d["size"] = [e(d["size"][0]), e(d["size"][1])]
    walls = []
    for w in d["walls"]:
        opens = sorted(w["open"])
        new_open = []
        # each door (a run of open cells) keeps its width, centred where it was
        i = 0
        while i < len(opens):
            j = i
            while j + 1 < len(opens) and opens[j + 1] == opens[j] + 1:
                j += 1
            n = j - i + 1
            mid = (opens[i] + opens[j] + 1) / 2 * k
            a = int(math.floor(mid - n / 2 + 0.5))
            new_open += list(range(a, a + n))
            i = j + 1
        walls.append(dict(w, line=e(w["line"]), a=e(w["a"]), b=e(w["b"]), open=new_open))
    d["walls"] = walls
    for t in d["things"]:
        old, new = rooms[t["room"]]
        cx, cy = t["cell"]
        nx = 0 if cx == 0 else min(int(math.floor((cx + t["w"] / 2) * k - t["w"] / 2 + 0.5)), new["w"] - int(t["w"]))
        ny = 0 if cy == 0 else min(int(math.floor((cy + t["h"] / 2) * k - t["h"] / 2 + 0.5)), new["h"] - int(t["h"]))
        if cx + t["w"] >= old["w"]:
            nx = new["w"] - int(t["w"])   # against the east side: stays there
        if cy + t["h"] >= old["h"]:
            ny = new["h"] - int(t["h"])
        t["cell"] = [nx, ny]
        t["x"], t["y"] = new["x"] + nx, new["y"] + ny
    for p in d["people"]:
        p["x"], p["y"] = p["x"] * k, p["y"] * k
    d["rooms"] = [n for _, n in rooms.values()]
    out = REF / ("layout_x%g.json" % k)
    json.dump(d, open(out, "w"), ensure_ascii=False, indent=1)
    for _, r in rooms.values():
        print("%-12s %s %2d x %-2d  (%.1f x %.1f m)" % (r["id"], r["name"], r["w"], r["h"], r["w"] * 0.7, r["h"] * 0.7))
    print("WROTE", out)


if __name__ == "__main__":
    main(float(sys.argv[1]))
