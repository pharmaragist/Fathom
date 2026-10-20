#!/usr/bin/env python3
"""Build Fathom's fallback launcher icon.

Draws an iOS-style rounded square (superellipse, n=5) in black, then centres
the white wave emblem from `assets/branding/icons/fg.png` on top. The result
is `assets/branding/icons/icon_fallback.png`, which `flutter_launcher_icons`
uses as `image_path` for pre-API 26 launchers.

Usage: python3 tool/gen_fallback_icon.py
Requires: pillow
"""
import os
from PIL import Image

S = 1024        # output size
SS = 4          # supersampling factor for smooth corners
N = 5.0         # superellipse exponent, approximates iOS continuous corners
EMBLEM_W = 480  # emblem width in output pixels

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets/branding/icons/fg.png')
OUT = os.path.join(ROOT, 'assets/branding/icons/icon_fallback.png')

# black squircle background
big = S * SS
mask = Image.new('L', (big, big), 0)
px = mask.load()
a = big / 2.0
for y in range(big):
    ny = (y + 0.5 - a) / a
    t = 1.0 - abs(ny) ** N
    if t <= 0:
        continue
    half = a * (t ** (1.0 / N))
    x0 = max(int(a - half), 0)
    x1 = min(int(a + half), big)
    for x in range(x0, x1):
        px[x, y] = 255

bg = Image.new('RGBA', (big, big), (0, 0, 0, 0))
bg.putalpha(mask)
bg = bg.resize((S, S), Image.LANCZOS)

# white emblem, cropped to its bounding box and centred
fg = Image.open(SRC).convert('RGBA').crop(Image.open(SRC).getbbox())
fg = fg.resize((round(fg.width * EMBLEM_W / fg.width), round(fg.height * EMBLEM_W / fg.width)), Image.LANCZOS)
ex = (S - fg.width) // 2
ey = (S - fg.height) // 2

out = bg.copy()
out.alpha_composite(fg, (ex, ey))
out.save(OUT)
print('wrote', OUT, out.size)
