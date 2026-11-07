"""Render every guide page and report text bounds for visual review."""

from pathlib import Path
import argparse
import hashlib
import json

from PIL import Image, ImageDraw
import pypdfium2 as pdfium


def review(pdf, output):
    output.mkdir(parents=True, exist_ok=True)
    data = pdf.read_bytes()
    doc = pdfium.PdfDocument(data)
    defects, images, glyphs = [], [], 0
    for index in range(len(doc)):
        page = doc[index]
        width, height = page.get_size()
        text = page.get_textpage()
        for char in range(text.count_chars()):
            value = text.get_text_range(char, 1)
            if not value.strip():
                continue
            left, bottom, right, top = text.get_charbox(char)
            glyphs += 1
            if left < -0.5 or bottom < -0.5 or right > width + 0.5 or top > height + 0.5:
                defects.append(dict(page=index + 1, text=value, bounds=[left, bottom, right, top]))
        text.close()
        path = output / f'page-{index + 1:03}.png'
        page.render(scale=1.35).to_pil().save(path)
        images.append(path)
        page.close()
    cell_w, cell_h = (520, 390) if width > height else (430, 640)
    sheets = []
    for start in range(0, len(images), 16):
        sheet = Image.new('RGB', (cell_w * 4, cell_h * 4), '#dfe3e3')
        draw = ImageDraw.Draw(sheet)
        for slot, path in enumerate(images[start:start + 16]):
            x, y = slot % 4 * cell_w, slot // 4 * cell_h
            with Image.open(path) as image:
                image.thumbnail((cell_w - 12, cell_h - 30))
                sheet.paste(image, (x + (cell_w - image.width) // 2, y + 24))
            draw.text((x + 12, y + 6), f'Page {start + slot + 1}', fill='#111111')
        path = output / f'sheet-{start // 16 + 1:02}.png'
        sheet.save(path)
        sheets.append(path.name)
    report = dict(pages=len(doc), rendered_pages=len(images), sheets=sheets,
                  pdf_sha256=hashlib.sha256(data).hexdigest(),
                  page_images=[path.name for path in images],
                  glyphs_checked=glyphs, out_of_page_glyphs=defects, visual_review='pending')
    (output / 'review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({key: report[key] for key in ('pages', 'rendered_pages', 'glyphs_checked', 'out_of_page_glyphs')}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pdf', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    review(args.pdf, args.output)
