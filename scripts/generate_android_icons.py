# File Name: generate_android_icons.py
# Role: Builds the adaptive launcher foreground, the monochrome layer and the status-bar
#   notification icon from the MedBuddy logo (1080 px): the mark only (heart, cross, ECG),
#   without the wordmark or the white tile. Needs Pillow, which the app does not depend on.
# Usage: python scripts/generate_android_icons.py frontend/assets/app_icon/medbuddy_logo.png \
#          frontend/android/app/src/main/res
import math
import os
import sys

from PIL import Image

src, res = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
W, H = im.size
px = im.load()

# The mark ends at the widest band of empty rows above the wordmark, wherever the layout puts it.
inked = [any(px[x, y][3] == 255 and px[x, y][0] <= 250 for x in range(W)) for y in range(H)]  # same reach as alpha > 0.02
rows = [y for y in range(H) if inked[y]]
gaps, start = [], None
for y in range(rows[0], rows[-1] + 1):
    if not inked[y]:
        start = y if start is None else start
    elif start is not None:
        gaps.append((y - start, start))
        start = None
cut = max(gaps)[1]

# Ink colour and alpha: the mark is one green drawn over white.
inks = [px[x, y][:3] for y in range(0, cut, 2) for x in range(W) if px[x, y][3] > 250 and px[x, y][0] < 40]
ink = tuple(sorted(c[i] for c in inks)[len(inks) // 2] for i in range(3))
def alpha(p):
    if p[3] < 255:
        return 0.0  # outside the tile
    # Unblend from white on the channel with the most contrast (red).
    return max(0.0, min(1.0, (255 - p[0]) / (255 - ink[0])))

# Mark area: everything inked above the wordmark.
mask = Image.new('L', (W, H), 0)
mp = mask.load()
for y in range(0, cut):
    for x in range(W):
        a = alpha(px[x, y])
        if a > 0.02:
            mp[x, y] = int(round(a * 255))
bbox = mask.getbbox()
cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
radius = max(math.hypot(x - cx, y - cy) for y in range(bbox[1], bbox[3]) for x in range(bbox[0], bbox[2]) if mp[x, y] > 128)
mark = mask.crop(bbox)
print('ink', ink, 'cut', cut, 'bbox', bbox, 'radius px %.1f' % radius)

def layer(canvas_dp, radius_dp, density, colour):
    size = int(round(canvas_dp * density))
    scale = radius_dp * density / radius
    w, h = max(1, round(mark.width * scale)), max(1, round(mark.height * scale))
    a = mark.resize((w, h), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    solid = Image.new('RGBA', (w, h), colour + (255,))
    solid.putalpha(a)
    out.alpha_composite(solid, ((size - w) // 2, (size - h) // 2))
    return out, w / density, h / density

densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, d in densities.items():
    # 108 dp layers; the mark reaches 23 dp from the centre, inside the 33 dp safe circle.
    os.makedirs(f'{res}/mipmap-{name}', exist_ok=True)
    fg, w, h = layer(108, 23, d, ink)
    fg.save(f'{res}/mipmap-{name}/ic_launcher_foreground.png', optimize=True)
    mono, _, _ = layer(108, 23, d, (255, 255, 255))
    mono.save(f'{res}/mipmap-{name}/ic_launcher_monochrome.png', optimize=True)
    # 24 dp status-bar icon: white silhouette, 2 dp clear margin.
    stat, _, _ = layer(24, 10.5, d, (255, 255, 255))
    os.makedirs(f'{res}/drawable-{name}', exist_ok=True)
    stat.save(f'{res}/drawable-{name}/ic_stat_medbuddy.png', optimize=True)
print('mark on canvas: %.1f x %.1f dp' % (w, h))
