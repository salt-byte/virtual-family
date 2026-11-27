#!/usr/bin/env python3
"""Spread the qijia plan K times wider in place (rooms bigger, furniture and people at their
real size): rooms.json, pack.json (site, start_objects), art.json (scenery), stories.json
(marks). Edits the numbers inside the hand-formatted files, so their layout stays.

Map cells (rooms, compound, walls, fences): each edge maps on its own, x' = round(x * K), so
neighbours stay touching. Doors keep their width, centred where they were. A piece's cell in
its room: 0 stays 0 (against the west / north wall), a piece on the far side stays on the far
side, the rest spread about their middles. Ground patches (paths, water) and scenery spread
as points; strips thinner than half a cell keep their width.

  python3 assets/gen/migrate_rooms.py 1.5
"""
import json
import math
import re
import sys
from pathlib import Path

PACK = Path(__file__).resolve().parents[2] / "game" / "packs" / "qijia"
K = float(sys.argv[1]) if len(sys.argv) > 1 else 1.5
NUM = r"-?\d+(?:\.\d+)?"


def e(v):
    return int(math.floor(v * K + 0.5))


def fmt(v):
    if isinstance(v, int) or float(v).is_integer():
        return str(int(v))
    return ("%.2f" % v).rstrip("0").rstrip(".")


def set_keys(chunk, values):
    """`chunk` (one flat JSON object's text) with "key": number replaced for each key given."""
    for k, v in values.items():
        chunk, n = re.subn(r'("%s"\s*:\s*)(%s)' % (k, NUM), lambda m: m.group(1) + fmt(v), chunk, count=1)
        assert n == 1, (k, chunk)
    return chunk


def flat_objects(text, start, end):
    """(open, close) spans of the brace-delimited objects between start and end, outermost."""
    out, depth, at = [], 0, None
    for i in range(start, end):
        c = text[i]
        if c == "{":
            if depth == 0:
                at = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                out.append((at, i + 1))
    return out


def array_span(text, key, after=0):
    i = text.index('"%s"' % key, after)
    i = text.index("[", i)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "[":
            depth += 1
        elif text[j] == "]":
            depth -= 1
            if depth == 0:
                return i, j + 1
    raise ValueError(key)


def edit_objects(text, start, end, fn):
    """Apply fn(obj_text, obj_dict) -> new text to each object in [start, end), back to front."""
    for a, b in reversed(flat_objects(text, start, end)):
        chunk = text[a:b]
        text = text[:a] + fn(chunk, json.loads(chunk)) + text[b:]
    return text


def rect(x, y, w, h):
    nx, ny = e(x), e(y)
    return nx, ny, e(x + w) - nx, e(y + h) - ny


def cell(c, size, old_room, new_room):
    if c == 0:
        return 0
    if c + size >= old_room:
        return new_room - size
    return min(int(math.floor((c + size / 2) * K - size / 2 + 0.5)), new_room - size)


def main():
    objects = {o["id"]: o for o in json.load(open(PACK / "objects.json"))}
    rooms_text = (PACK / "rooms.json").read_text()
    rooms = json.loads(rooms_text)
    old = {r["id"]: r for r in rooms}
    new = {}
    for r in rooms:
        x, y, w, h = rect(r["x"], r["y"], r["w"], r["h"])
        new[r["id"]] = {"x": x, "y": y, "w": w, "h": h}

    def place(chunk, o, room):
        t = objects.get(o.get("type"), {"w": 1, "h": 1})
        a, b = old[room], new[room]
        return set_keys(chunk, {"x": cell(o["x"], int(t.get("w", 1)), a["w"], b["w"]),
                                "y": cell(o["y"], int(t.get("h", 1)), a["h"], b["h"])})

    # rooms.json: each room's own numbers (before its props), then its props.
    def room_fn(chunk, r):
        cut = chunk.find('"props"')
        head, tail = (chunk, "") if cut < 0 else (chunk[:cut], chunk[cut:])
        head = set_keys(head, new[r["id"]])
        if tail:
            s, t = array_span(tail, "props")
            tail = edit_objects(tail, s, t, lambda c, o: place(c, o, r["id"]))
        return head + tail
    s, t = 0, len(rooms_text)
    rooms_text = edit_objects(rooms_text, rooms_text.index("["), t, room_fn)
    (PACK / "rooms.json").write_text(rooms_text)

    # pack.json
    p = (PACK / "pack.json").read_text()
    s, t = array_span(p, "start_objects")
    p = edit_objects(p, s, t, lambda c, o: place(c, o, o["room"]))
    site_at = p.index('"site"')
    for key in ("doors", "fences", "decor"):
        s, t = array_span(p, key, site_at)
        if key == "doors":
            def door(c, d):
                n = int(d["len"])
                if d["along"] == "x":
                    return set_keys(c, {"y": e(d["y"]), "x": int(math.floor((d["x"] + n / 2) * K - n / 2 + 0.5))})
                return set_keys(c, {"x": e(d["x"]), "y": int(math.floor((d["y"] + n / 2) * K - n / 2 + 0.5))})
            p = edit_objects(p, s, t, door)
        elif key == "fences":
            def fence(c, d):
                a = d["x"] if d["along"] == "x" else d["y"]
                return set_keys(c, {"x": e(d["x"]), "y": e(d["y"]), "len": e(a + d["len"]) - e(a)})
            p = edit_objects(p, s, t, fence)
        else:
            def patch(c, d):
                v = {"x": d["x"] * K, "y": d["y"] * K}
                for k in ("w", "h"):
                    if k in d:
                        v[k] = d[k] * K if d[k] >= 0.5 else d[k]
                return set_keys(c, v)
            p = edit_objects(p, s, t, patch)
    # site size and compound (the site object's own keys: before "doors")
    site_obj_start = p.index("{", site_at)
    doors_at = p.index('"doors"', site_at)
    head = p[site_obj_start:doors_at]
    sw = int(re.search(r'"w"\s*:\s*(\d+)', head).group(1))
    sh = int(re.search(r'"h"\s*:\s*(\d+)', head).group(1))
    comp = re.search(r'"compound"\s*:\s*\{[^}]*\}', head)
    cd = json.loads(comp.group(0)[comp.group(0).index("{"):])
    cx, cy, cw, ch = rect(cd["x"], cd["y"], cd["w"], cd["h"])
    new_comp = set_keys(comp.group(0), {"x": cx, "y": cy, "w": cw, "h": ch})
    head2 = head[:comp.start()] + new_comp + head[comp.end():]
    head2 = set_keys(head2[:comp.start()], {"w": e(sw), "h": e(sh)}) + head2[comp.start():]
    p = p[:site_obj_start] + head2 + p[doors_at:]
    (PACK / "pack.json").write_text(p)

    # art.json scenery: points spread, sizes kept
    a = (PACK / "art.json").read_text()
    s, t = array_span(a, "scenery")
    a = edit_objects(a, s, t, lambda c, o: set_keys(c, {"x": o["x"] * K, "y": o["y"] * K}))
    (PACK / "art.json").write_text(a)

    # stories.json: marks are room cells
    st = (PACK / "stories.json").read_text()
    for m in reversed(list(re.finditer(r'"mark"\s*:\s*\{[^}]*\}', st))):
        o = json.loads(m.group(0)[m.group(0).index("{"):])
        if "room" in o and "x" in o:
            st = st[:m.start()] + place(m.group(0), o, o["room"]) + st[m.end():]
    (PACK / "stories.json").write_text(st)

    for rid, r in new.items():
        print("%-12s %2d x %-2d at (%d, %d)" % (rid, r["w"], r["h"], r["x"], r["y"]))
    print("site", e(sw), "x", e(sh), "compound", (cx, cy, cw, ch))


if __name__ == "__main__":
    main()
