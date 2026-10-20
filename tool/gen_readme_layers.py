#!/usr/bin/env python3
"""Build `assets/branding/icons/readme_layers.png`: a README strip showing the
launcher icon layers on a mid-gray background (the layers are white, so a light
README background would hide them).

Left to right: adaptive composite (black bg + foreground, 28% inset, 66/108
safe mask), monochrome layer on a tint gray, legacy rounded fallback.

Usage: python3 tool/gen_readme_layers.py
Requires: pillow
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, 'assets/branding/icons')
RES = os.path.join(ROOT, 'android/app/src/main/res')
FG = os.path.join(ICON_DIR, 'fg.png')
FALLBACK = os.path.join(ICON_DIR, 'icon_fallback.png')
OUT = os.path.join(ICON_DIR, 'readme_layers.png')

TILE = 256          # tile size
GAP = 32            # gap between tiles
PAD = 32            # outer padding
BG = (58, 58, 60)   # mid gray, visible on light and dark README themes
MONO_TINT = (122, 144, 255)  # stand-in for a wallpaper-derived themed-icon tint
INSET = 0.28        # matches adaptive_icon_foreground_inset
MASK = 66 / 108     # adaptive icon visible safe zone

W = PAD * 2 + TILE * 3 + GAP * 2
H = PAD * 2 + TILE
sheet = Image.new('RGBA', (W, H), BG + (255,))

fg = Image.open(FG).convert('RGBA')


def mask_circle(size):
    """Rounded mask approximating the launcher's adaptive icon shape."""
    m = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1],
                                        radius=size * 4 // 2, fill=255)
    return m.resize((size, size), Image.LANCZOS)


# 1. adaptive composite
tile = Image.new('RGBA', (TILE, TILE), (0, 0, 0, 255))
layer = int(TILE * MASK * (1 - 2 * INSET))
tile.alpha_composite(fg.resize((layer, layer), Image.LANCZOS),
                     ((TILE - layer) // 2, (TILE - layer) // 2))
tile.putalpha(mask_circle(TILE))
sheet.alpha_composite(tile, (PAD, PAD))

# 2. monochrome layer on a tint
tile = Image.new('RGBA', (TILE, TILE), MONO_TINT + (255,))
layer = int(TILE * (1 - 2 * INSET))
tile.alpha_composite(fg.resize((layer, layer), Image.LANCZOS),
                     ((TILE - layer) // 2, (TILE - layer) // 2))
tile.putalpha(mask_circle(TILE))
sheet.alpha_composite(tile, (PAD + TILE + GAP, PAD))

# 3. legacy rounded fallback
legacy = Image.open(FALLBACK).convert('RGBA').resize((TILE, TILE), Image.LANCZOS)
sheet.alpha_composite(legacy, (PAD + (TILE + GAP) * 2, PAD))

sheet.convert('RGB').save(OUT)
print('wrote', OUT, sheet.size)
