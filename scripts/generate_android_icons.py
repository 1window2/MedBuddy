# File Name: generate_android_icons.py
# Role: Builds the adaptive launcher foreground, the monochrome layer and the status-bar
#   notification icon from the MedBuddy logo (1080 px): the mark only (heart, cross, ECG),
#   without the wordmark or the white tile. With a third argument it also writes the home
#   wordmark's two transparent crops (mark and name). Needs Pillow, which the app does not
#   depend on.
# Usage: python scripts/generate_android_icons.py frontend/assets/app_icon/medbuddy_logo.png \
#          frontend/android/app/src/main/res [frontend/assets/brand]
import math
import os
import sys

from PIL import Image

src, res = sys.argv[1], sys.argv[2]
brand = sys.argv[3] if len(sys.argv) > 3 else None
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
inked_mark = [(x, y) for y in range(bbox[1], bbox[3]) for x in range(bbox[0], bbox[2]) if mp[x, y] > 128]
# The mark's size is kept as before: its farthest ink from the box centre sets the scale.
radius = max(math.hypot(x - cx, y - cy) for x, y in inked_mark)
mark = mask.crop(bbox)

# The heart, not the whole mark, is centred on the icon: the cross above it and the ECG tail
# left of it would pull a box centre up and to the left. The cross is the topmost separate
# part; the heart spans the remaining ink vertically, and its lobes (the top quarter, above
# the ECG line) give its width.
inked_set = set(inked_mark)
parts, seen = [], set()
for start in inked_mark:
    if start in seen:
        continue
    seen.add(start)
    stack, part = [start], []
    while stack:
        x, y = stack.pop()
        part.append((x, y))
        for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if q in inked_set and q not in seen:
                seen.add(q)
                stack.append(q)
    parts.append(part)
cross = min(parts, key=lambda part: min(y for _, y in part))
body = [p for part in parts if part is not cross for p in part]
heart_top, heart_bottom = min(y for _, y in body), max(y for _, y in body)
lobes = [x for x, y in body if y < heart_top + (heart_bottom - heart_top) / 4]
hx, hy = (min(lobes) + max(lobes)) / 2, (heart_top + heart_bottom) / 2
far = max(math.hypot(x - hx, y - hy) for x, y in inked_mark)
up, down = hy - bbox[1], bbox[3] - hy
left, right = hx - bbox[0], bbox[2] - hx
print('ink', ink, 'cut', cut, 'bbox', bbox, 'radius px %.1f' % radius)
print('heart centre (%.1f, %.1f), cross centre x %.1f, reach from heart px %.1f' % (
    hx, hy, (min(x for x, _ in cross) + max(x for x, _ in cross)) / 2, far))

def layer(canvas_dp, radius_dp, density, colour, half_dp=None):
    size = int(round(canvas_dp * density))
    scale = radius_dp * density / radius
    if half_dp is not None:
        # Small canvases: shrink until the off-centre mark stays inside the clear margin.
        scale = min(scale, half_dp * density / max(up, down, left, right))
    w, h = max(1, round(mark.width * scale)), max(1, round(mark.height * scale))
    a = mark.resize((w, h), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    solid = Image.new('RGBA', (w, h), colour + (255,))
    solid.putalpha(a)
    # The heart's centre lands on the canvas centre.
    out.alpha_composite(solid, (round(size / 2 - (hx - bbox[0]) * scale), round(size / 2 - (hy - bbox[1]) * scale)))
    return out, w / density, h / density, far * scale / density

densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, d in densities.items():
    # 108 dp layers: the mark keeps its size (23 dp from its box centre) and must stay inside
    # the 33 dp safe circle around the heart's centre.
    os.makedirs(f'{res}/mipmap-{name}', exist_ok=True)
    fg, w, h, reach = layer(108, 23, d, ink)
    assert reach <= 33, reach
    fg.save(f'{res}/mipmap-{name}/ic_launcher_foreground.png', optimize=True)
    mono, _, _, _ = layer(108, 23, d, (255, 255, 255))
    mono.save(f'{res}/mipmap-{name}/ic_launcher_monochrome.png', optimize=True)
    # 24 dp status-bar icon: white silhouette, 2 dp clear margin.
    stat, _, _, _ = layer(24, 10.5, d, (255, 255, 255), half_dp=10)
    os.makedirs(f'{res}/drawable-{name}', exist_ok=True)
    stat.save(f'{res}/drawable-{name}/ic_stat_medbuddy.png', optimize=True)
print('mark on canvas: %.1f x %.1f dp, reach from the heart centre %.1f dp' % (w, h, reach))

if brand:
    # Home wordmark (MedBuddyWordmark): the mark 46 dp wide and the name 148 dp wide, drawn at
    # 3x so the app decodes two small images instead of the whole 1080 px logo.
    word_rows = [y for y in range(cut, H) if inked[y]]
    word_box = (0, word_rows[0], W, word_rows[-1] + 1)
    word_mask = Image.new('L', (W, H), 0)
    wp = word_mask.load()
    word_inks = [px[x, y][:3] for y in range(word_box[1], word_box[3], 2) for x in range(W) if px[x, y][3] > 250 and px[x, y][0] < 40]
    word_ink = tuple(sorted(c[i] for c in word_inks)[len(word_inks) // 2] for i in range(3))
    for y in range(word_box[1], word_box[3]):
        for x in range(W):
            p = px[x, y]
            a = 0.0 if p[3] < 255 else max(0.0, min(1.0, (255 - p[0]) / (255 - word_ink[0])))
            if a > 0.02:
                wp[x, y] = int(round(a * 255))
    os.makedirs(brand, exist_ok=True)
    for name, alpha_mask, colour, width in (('medbuddy_mark', mark, ink, 46), ('medbuddy_name', word_mask.crop(word_mask.getbbox()), word_ink, 148)):
        w = width * 3
        h = round(alpha_mask.height * w / alpha_mask.width)
        solid = Image.new('RGBA', (w, h), colour + (255,))
        solid.putalpha(alpha_mask.resize((w, h), Image.LANCZOS))
        solid.save(f'{brand}/{name}.png', optimize=True)
        print(name, 'colour', colour, 'size', (w, h))
