"""Treatment A (墙立起来) for compose_house: tall back walls, low-cut front walls, roof eave along the north
row, a north-west sun casting soft shadows south and east of walls, ambient occlusion at wall bases,
door openings with lintels. Called from compose_house.render(tall=True)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HA = 76          # visible height of a back wall's south face (px)
HL = 18          # height of a front wall after the cut (px)
T = 12           # plan thickness (px)
LINTEL = 24      # wall left above a door opening (px)
EAVE = 26        # roof-eave strip above the north walls (px)
CAP = (96, 74, 58)        # dark cut top
BEAM = (110, 74, 46)
BASE = (138, 90, 54)
SHADE = 0.82              # south faces are away from the sun
SH_S, SH_E = 38, 26       # cast shadow depth south of east-west walls / east of north-south walls (px)
SH_A = 0.38               # cast shadow opacity at the wall base
AO_W, AO_A = 9, 0.20      # ambient-occlusion band at every wall base


def face(ch, w, h, compound=False):
    """South-facing wall face: plaster (or rammed earth), beam line under the cap, timber base."""
    w, h = max(1, int(w)), max(1, int(h))
    src = ch.ct.load(ch.ROOT / f"assets/tiles/{'a_wall_compound' if compound else 'a_wall'}.png")
    k = max(h, 60) / src.height
    t = src.resize((max(1, int(src.width * k)), max(h, 60)), Image.LANCZOS).crop((0, 0, int(src.width * k), h))
    out = Image.new("RGBA", (w, h))
    for x in range(0, w, t.width):
        out.paste(t, (x, 0))
    a = np.array(out).astype(float)
    a[..., :3] *= SHADE
    out = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(out)
    if h >= 30:
        d.rectangle((0, 0, w, 6), fill=BEAM)
    if not compound:
        b = min(14, h // 3)
        d.rectangle((0, h - b, w, h), fill=BASE)
        d.line([(0, h - b), (w, h - b)], fill=ch.ct.LINE, width=2)
    return out


def shadow_layer(size):
    return Image.new("L", size, 0)


def grad_rect(m, box, a0, direction):
    """Paint a linear opacity ramp (a0 -> 0) into mask m over box, along 'down' or 'right'."""
    x0, y0, x1, y1 = [int(v) for v in box]
    if x1 <= x0 or y1 <= y0:
        return
    n = (y1 - y0) if direction == "down" else (x1 - x0)
    ramp = (np.linspace(a0, 0, n) ** 1.2 * 255).astype(np.uint8)
    block = np.tile(ramp[:, None], (1, x1 - x0)) if direction == "down" else np.tile(ramp[None, :], (y1 - y0, 1))
    cur = np.array(m.crop((x0, y0, x1, y1)))
    m.paste(Image.fromarray(np.maximum(cur, block)), (x0, y0))


def draw(img, d, ch):
    px, OX, OY = ch.px, ch.OX, ch.OY
    ROOMS, DOORS, COMPOUND, GATE = ch.ROOMS, ch.DOORS, ch.COMPOUND, ch.GATE
    indoor = {rid for rid, (_, k, b) in ROOMS.items() if b and k not in ("out", "paved")}

    def room_at(cx, cy):
        for rid, ((x, y, w, h), k, b) in ROOMS.items():
            if x <= cx < x + w and y <= cy < y + h:
                return rid
        return None

    # wall lines from built indoor rooms plus the compound's west, north, east sides
    hw, vw = {}, {}
    for rid in indoor:
        (x, y, w, h), _, _ = ROOMS[rid]
        for Y in (y, y + h):
            if Y != COMPOUND[3]:
                for cx in range(x, x + w):
                    hw.setdefault(Y, set()).add(cx)
        for X in (x, x + w):
            for cy in range(y, y + h):
                vw.setdefault(X, set()).add(cy)
    for cx in range(COMPOUND[2]):
        hw.setdefault(0, set()).add(cx)
    for cy in range(COMPOUND[3]):
        vw.setdefault(0, set()).add(cy)
        vw.setdefault(COMPOUND[2], set()).add(cy)

    def door_cells(o, line):
        out = set()
        for oo, l, g0, g1 in DOORS:
            if oo == o and l == line:
                out |= set(range(g0, g1))
        return out

    def runs(cells):
        cells = sorted(cells)
        out, start, prev = [], None, None
        for c in cells:
            if start is None:
                start = prev = c
            elif c == prev + 1:
                prev = c
            else:
                out.append((start, prev + 1)); start = prev = c
        if start is not None:
            out.append((start, prev + 1))
        return out

    def is_back(Y, cx):
        """A wall is a back wall (tall) when the cell south of it is an indoor room; else it is cut low."""
        return room_at(cx, Y) in indoor

    # 1. shadows and ambient occlusion on the ground
    m = shadow_layer(img.size)
    for Y, cells in hw.items():
        Yp = px(0, OY + Y)[1]
        for a, b in runs(cells):
            x0, x1 = px(OX + a, 0)[0], px(OX + b, 0)[0]
            depth = SH_S if any(is_back(Y, c) for c in range(a, b)) else 10
            grad_rect(m, (x0, Yp + T / 2, x1, Yp + T / 2 + depth), SH_A, "down")
    for X, cells in vw.items():
        Xp = px(OX + X, 0)[0]
        for a, b in runs(cells):
            y0, y1 = px(0, OY + a)[1], px(0, OY + b)[1]
            grad_rect(m, (Xp + T / 2, y0, Xp + T / 2 + SH_E, y1), SH_A * 0.8, "right")
            grad_rect(m, (Xp - T / 2 - AO_W, y0, Xp - T / 2, y1), AO_A, "right")
    m = m.filter(ImageFilter.GaussianBlur(3))
    dark = Image.new("RGBA", img.size, (40, 28, 20, 255))
    dark.putalpha(m)
    img.alpha_composite(dark)

    # 2. tall back faces (east-west), with lintels over doors
    tall_runs = []
    for Y, cells in sorted(hw.items()):
        Yp = px(0, OY + Y)[1]
        doors = door_cells("h", Y)
        back = {c for c in cells if is_back(Y, c)}
        for a, b in runs(back):
            x0, x1 = px(OX + a, 0)[0] - T / 2, px(OX + b, 0)[0] + T / 2
            f = face(ch, x1 - x0, HA, compound=False)
            img.alpha_composite(f, (int(x0), int(Yp + T / 2 - HA)))
            for dc in runs(doors & back):  # door opening: cut the face below the lintel, frame it
                g0, g1 = px(OX + dc[0], 0)[0], px(OX + dc[1], 0)[0]
                hole = (int(g0), int(Yp + T / 2 - HA + LINTEL), int(g1), int(Yp + T / 2))
                floor_behind = img.crop(hole)  # the opening shows the room behind, darker
                fa = np.array(floor_behind).astype(float); fa[..., :3] *= 0.55
                img.paste(Image.fromarray(fa.clip(0, 255).astype(np.uint8)), hole[:2])
                d.rectangle((g0, hole[1] - 6, g1, hole[1]), fill=BEAM, outline=ch.ct.LINE, width=2)
                d.rectangle((g0 - 3, hole[1], g0 + 3, hole[3]), fill=BEAM)
                d.rectangle((g1 - 3, hole[1], g1 + 3, hole[3]), fill=BEAM)
            d.rectangle((x0, Yp + T / 2 - HA, x1, Yp + T / 2), outline=ch.ct.LINE, width=2)
            tall_runs.append((x0, x1, Yp))
    # roof eave along the compound's north wall: tiles seen from above, dark lower edge
    ax0, ay0 = px(OX, OY)
    ax1 = px(OX + COMPOUND[2], 0)[0]
    top = ay0 - T / 2 - HA - EAVE
    d.rectangle((ax0 - 20, top, ax1 + 20, top + EAVE), fill=(118, 128, 142))
    for x in range(int(ax0 - 20), int(ax1 + 20), 14):
        d.line([(x, top), (x, top + EAVE)], fill=(92, 100, 114), width=2)
        d.arc((x - 7, top + EAVE - 10, x + 7, top + EAVE + 4), 0, 180, fill=(70, 76, 88), width=2)
    d.rectangle((ax0 - 20, top, ax1 + 20, top + EAVE), outline=ch.ct.LINE, width=2)
    grad = Image.new("L", (int(ax1 - ax0 + 40), 14))
    grad_rect(grad, (0, 0, grad.width, 14), 0.35, "down")
    sh = Image.new("RGBA", grad.size, (40, 28, 20, 255)); sh.putalpha(grad)
    img.alpha_composite(sh, (int(ax0 - 20), int(top + EAVE)))

    # 3. caps of the tall walls
    for x0, x1, Yp in tall_runs:
        d.rectangle((x0, Yp - T / 2 - HA, x1, Yp + T / 2 - HA), fill=CAP, outline=ch.ct.LINE, width=2)

    # 4. north-south walls: full height, cap continues over doors as a lintel
    for X, cells in vw.items():
        Xp = px(OX + X, 0)[0]
        doors = door_cells("v", X)
        for a, b in runs(cells):
            y0, y1 = px(0, OY + a)[1], px(0, OY + b)[1]
            h_end = HA
            for dc in runs(doors & set(range(a, b))):
                g0, g1 = px(0, OY + dc[0])[1], px(0, OY + dc[1])[1]
                d.rectangle((Xp - T / 2 - 2, g0 - HA + LINTEL, Xp + T / 2 + 2, g1), fill=(60, 44, 34))
            d.rectangle((Xp - T / 2, y0 - T / 2 - HA, Xp + T / 2, y1 + T / 2 - HA), fill=CAP, outline=ch.ct.LINE, width=2)
            f = face(ch, T + 4, h_end, compound=False)
            img.alpha_composite(f, (int(Xp - T / 2 - 2), int(y1 + T / 2 - h_end)))
            d.rectangle((Xp - T / 2 - 2, y1 + T / 2 - h_end, Xp + T / 2 + 2, y1 + T / 2), outline=ch.ct.LINE, width=2)

    # 5. front walls, cut low so people behind them stay visible
    for Y, cells in sorted(hw.items()):
        Yp = px(0, OY + Y)[1]
        front = {c for c in cells if not is_back(Y, c)} - door_cells("h", Y)
        for a, b in runs(front):
            x0, x1 = px(OX + a, 0)[0] - T / 2, px(OX + b, 0)[0] + T / 2
            img.alpha_composite(face(ch, x1 - x0, HL), (int(x0), int(Yp + T / 2 - HL)))
            d.rectangle((x0, Yp - T / 2 - HL, x1, Yp + T / 2 - HL), fill=CAP, outline=ch.ct.LINE, width=2)
            d.rectangle((x0, Yp + T / 2 - HL, x1, Yp + T / 2), outline=ch.ct.LINE, width=2)
    for o, line, g0, g1 in DOORS:
        if o == "h" and not is_back(line, g0):
            Yp = px(0, OY + line)[1]
            sill = ch.sprite("a_door_sill", w=(g1 - g0) * ch.CW - 6)
            img.alpha_composite(sill, (int(px(OX + g0, 0)[0] + 3), int(Yp - sill.height / 2)))

    # 6. compound south wall stays as before (low), gate on top
    ay1 = px(0, OY + COMPOUND[3])[1]
    gl, gr = px(OX + GATE[0], 0)[0], px(OX + GATE[1], 0)[0]
    for s0, s1 in ((ax0, gl), (gr, ax1)):
        img.alpha_composite(face(ch, s1 - s0 + T, 34, compound=True), (int(s0 - T / 2), int(ay1 + T / 2 - 34)))
        d.rectangle((s0 - T / 2, ay1 - T / 2 - 34, s1 + T / 2, ay1 + T / 2 - 34), fill=(128, 132, 142), outline=ch.ct.LINE, width=2)
    gh = ch.sprite("a_gatehouse", w=(GATE[1] - GATE[0] + 1.6) * ch.CW)
    ch.put(img, gh, (gl + gr) / 2, ay1 + T / 2 + 4, shadow=False)
