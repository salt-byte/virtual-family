"""Key the #F0F0F0 background out of the iso sheets without punching holes in cream/white parts.
Border-connected bg-ish pixels go; enclosed pockets go only if they are almost exactly the bg colour."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

def key(src, dst_sheet, bg=(240, 240, 240), tol=34, inner_tol=13):
    a = np.array(Image.open(src).convert("RGBA")).astype(np.int16)
    d = np.abs(a[..., :3] - np.array(bg)).max(-1)
    near = d < tol
    lab, n = ndimage.label(near)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    kill = np.isin(lab, list(border))
    for k in range(1, n + 1):
        if k in border:
            continue
        m = lab == k
        if m.sum() > 40 and np.median(d[m]) <= inner_tol:
            kill |= m
    alpha = np.where(kill, 0, 255).astype(np.uint8)
    # soft edge: 1px feather where the kept pixel is still close to bg
    edge = ndimage.binary_dilation(kill) & ~kill
    alpha[edge & (d < tol + 20)] = 140
    out = a.clip(0, 255).astype(np.uint8)
    out[..., 3] = alpha
    Image.fromarray(out).save(dst_sheet)

if __name__ == "__main__":
    key(sys.argv[1], sys.argv[2], inner_tol=float(sys.argv[3]) if len(sys.argv) > 3 else 13)
