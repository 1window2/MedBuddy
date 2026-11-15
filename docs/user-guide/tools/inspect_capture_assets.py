# File Name: inspect_capture_assets.py
# Role: Make review-only contact sheets of explicitly supplied product screenshots.
"""Make review-only contact sheets of explicitly supplied product screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw
import argparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('folder', type=Path)
parser.add_argument('--name', default='capture-review-current')
args = parser.parse_args()
assert Path(args.name).name == args.name
paths = sorted(args.folder.glob('*.png'))
output = ROOT / '.build' / args.name
output.mkdir(parents=True, exist_ok=True)
for start in range(0, len(paths), 8):
    sheet = Image.new('RGB', (1800, 1200), '#dce0e2')
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(paths[start:start+8]):
        with Image.open(path) as image:
            image.thumbnail((430, 550))
            x, y = (i % 4)*450, (i//4)*600
            sheet.paste(image, (x+(450-image.width)//2, y+30))
            draw.text((x+5, y+5), path.stem, fill='black')
    sheet.save(output / f'sheet-{start//8+1:02}.png')
print(len(paths))
