#!/usr/bin/env python3
"""Regenerates every app icon PNG from one geometry definition.

Design (2026-09-19): two hand-wobbled rings (outer = pace, lavender, 75% closed;
inner = actual, green, 68% closed) on brand violet (light) / deep indigo (dark).
Writes: iOS light/dark/tinted 1024s, macOS 16-512 @1x/@2x, watchOS 1024, and the
tinted WiggleRoomMark used by the widgets' corner brand mark.
Requires Pillow. Run from the repo root: python3 scripts/generate_app_icon.py
"""
import math
from PIL import Image, ImageDraw

SRC, SS, DESIGN = 1024, 4, 200.0  # output px, supersample, design-space units
OUTER = [(100, 32), (144, 26, 172, 60, 168, 102), (166, 148, 130, 176, 96, 170),
         (54, 168, 26, 138, 32, 96), (34, 56, 60, 30, 100, 32)]
INNER = [(100, 56), (128, 52, 148, 76, 144, 102), (142, 130, 120, 150, 96, 146),
         (70, 144, 54, 126, 56, 98), (58, 72, 76, 54, 100, 56)]
OUTER_FRAC, INNER_FRAC, STROKE = 0.75, 0.68, 16

THEMES = {  # name: (background, outer ring, inner ring)
    "light": ("#7062D8", "#DAD5F7", "#52C799"),
    "dark": ("#0F0C2A", "#9E8FFA", "#52C799"),
    "tinted": ("#3A3A3C", "#7A7A7C", "#D9D9D9"),  # grayscale; iOS applies the user's tint
}

def sample(path, n=400):
    pts, (x0, y0) = [], path[0]
    for seg in path[1:]:
        x1, y1, x2, y2, x3, y3 = seg
        for i in range(n):
            t = i / n
            a, b, c, d = (1-t)**3, 3*(1-t)**2*t, 3*(1-t)*t*t, t**3
            pts.append((a*x0+b*x1+c*x2+d*x3, a*y0+b*y1+c*y2+d*y3))
        x0, y0 = x3, y3
    pts.append((x0, y0))
    return pts

def draw_arc(d, pts, frac, color, scale):
    lens = [0.0]
    for p, q in zip(pts, pts[1:]):
        lens.append(lens[-1] + math.dist(p, q))
    limit, r = lens[-1] * frac, STROKE / 2 * scale
    for p, s in zip(pts, lens):
        if s > limit:
            break
        x, y = p[0] * scale, p[1] * scale
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)

def render(theme):
    bg, outer, inner = THEMES[theme]
    scale = SRC * SS / DESIGN
    img = Image.new("RGB", (SRC * SS,) * 2, bg)
    d = ImageDraw.Draw(img)
    draw_arc(d, sample(OUTER), OUTER_FRAC, outer, scale)
    draw_arc(d, sample(INNER), INNER_FRAC, inner, scale)
    return img.resize((SRC, SRC), Image.LANCZOS)

if __name__ == "__main__":
    ios = "src/WiggleRoom/Assets.xcassets/AppIcon.appiconset/"
    light, dark, tinted = render("light"), render("dark"), render("tinted")
    light.save(ios + "icon-light-1024.png")
    dark.save(ios + "icon-dark-1024.png")
    tinted.save(ios + "icon-tinted-1024.png")
    tinted.save("src/WiggleRoomShared/Assets.xcassets/WiggleRoomMark.imageset/icon-tinted-1024.png")
    light.save("src/WiggleRoomWatch/Assets.xcassets/AppIcon.appiconset/icon-light-1024.png")
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            light.resize((pt * sc,) * 2, Image.LANCZOS).save(f"{ios}icon-mac-{pt}x{pt}@{sc}x.png")
    print("done")
