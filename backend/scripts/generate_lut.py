#!/usr/bin/env python3
"""Generate a 3D LUT (.cube) baking: eq(contrast=1.03,brightness=-0.022,saturation=1.09) + curves(all='0/0 0.68/0.62 1/0.88') + hue(h=5)"""
SIZE = 33

def apply_eq(r, g, b):
    r -= 0.022; g -= 0.022; b -= 0.022
    r = (r - 0.5) * 1.03 + 0.5
    g = (g - 0.5) * 1.03 + 0.5
    b = (b - 0.5) * 1.03 + 0.5
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    r = luma + (r - luma) * 1.09
    g = luma + (g - luma) * 1.09
    b = luma + (b - luma) * 1.09
    return r, g, b

def apply_curves(v):
    if v <= 0.68:
        return v * (0.62 / 0.68)
    return 0.62 + (v - 0.68) * ((0.88 - 0.62) / (1.0 - 0.68))

def apply_hue(r, g, b, deg=5):
    cmax = max(r, g, b); cmin = min(r, g, b); delta = cmax - cmin
    if delta == 0: h = 0
    elif cmax == r: h = 60 * (((g - b) / delta) % 6)
    elif cmax == g: h = 60 * ((b - r) / delta + 2)
    else: h = 60 * ((r - g) / delta + 4)
    s = 0 if cmax == 0 else delta / cmax; v = cmax
    h = (h + deg) % 360
    c = v * s; x = c * (1 - abs((h / 60) % 2 - 1)); m = v - c
    if h < 60: r1, g1, b1 = c, x, 0
    elif h < 120: r1, g1, b1 = x, c, 0
    elif h < 180: r1, g1, b1 = 0, c, x
    elif h < 240: r1, g1, b1 = 0, x, c
    elif h < 300: r1, g1, b1 = x, 0, c
    else: r1, g1, b1 = c, 0, x
    return r1 + m, g1 + m, b1 + m

clamp = lambda v: max(0.0, min(1.0, v))

import sys
out = sys.argv[1] if len(sys.argv) > 1 else "moody.cube"
with open(out, "w") as f:
    f.write(f"LUT_3D_SIZE {SIZE}\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n\n")
    for bi in range(SIZE):
        for gi in range(SIZE):
            for ri in range(SIZE):
                r, g, b = ri/(SIZE-1), gi/(SIZE-1), bi/(SIZE-1)
                r, g, b = apply_eq(r, g, b)
                r, g, b = apply_curves(r), apply_curves(g), apply_curves(b)
                r, g, b = apply_hue(r, g, b)
                f.write(f"{clamp(r):.6f} {clamp(g):.6f} {clamp(b):.6f}\n")
print(f"Generated {out} ({SIZE}x{SIZE}x{SIZE})")
