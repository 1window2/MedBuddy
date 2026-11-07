"""Build the full four-column landscape guide from the portrait's content manifest."""

from collections import OrderedDict
from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape
import argparse
import hashlib
import json
import re

from PIL import Image
from pypdf import PdfReader
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph

import guide_layout


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'
W, H = landscape(A4)
MM = 72 / 25.4
MARGIN, GAP = 8 * MM + 7.5, 5 * MM + 15
COL = (W - MARGIN * 2 - GAP * 3) / 4
BOTTOM, TOP = 38, H - MARGIN - 36
TITLE_IMAGE_GAP, IMAGE_CAPTION_GAP = 6, 8
MAX_IMAGE_HEIGHT = 366
REG, BOLD = guide_layout.REG, guide_layout.BOLD


def para(text, width=COL, bold=False, size=11, leading=15):
    style = ParagraphStyle('guide', fontName=BOLD if bold else REG,
                           fontSize=size, leading=leading, wordWrap='CJK',
                           allowWidows=0, allowOrphans=0, splitLongWords=True)
    p = Paragraph(escape(text).replace('\n', '<br/>'), style)
    p.guide_text = text
    _, h = p.wrap(width, H * 100)
    return p, h


def consume(blocks, width, available):
    """Keep overflow as measured paragraph fragments for the next column."""
    placed, pending, used = [], list(blocks), 0
    while pending:
        p = pending[0]
        _, height = p.wrap(width, H * 100)
        gap = 4 if placed else 0
        room = available - used - gap
        if getattr(p, 'guide_heading', False) and room < height + 30:
            break
        if getattr(p, 'guide_keep_height', 0) <= available and room < getattr(p, 'guide_keep_height', 0):
            break
        if height <= room + 0.01:
            placed.append((p, height, gap))
            used += height + gap
            pending.pop(0)
            continue
        low, high, fit = 1, len(p.guide_text), 0
        while low <= high:
            middle = (low + high) // 2
            trial, height = para(p.guide_text[:middle], width,
                                 p.style.fontName == BOLD, p.style.fontSize, p.style.leading)
            if height <= room:
                fit, low = middle, middle + 1
            else:
                high = middle - 1
        if fit:
            boundary = max(p.guide_text.rfind(' ', 0, fit), p.guide_text.rfind('\n', 0, fit))
            if boundary >= fit // 2:
                fit = boundary + 1
            first, height = para(p.guide_text[:fit], width,
                                 p.style.fontName == BOLD, p.style.fontSize, p.style.leading)
            rest, _ = para(p.guide_text[fit:], width,
                           p.style.fontName == BOLD, p.style.fontSize, p.style.leading)
            if hasattr(p, 'guide_section'):
                rest.guide_section = p.guide_section
            placed.append((first, height, gap))
            used += height + gap
            pending = [rest] + pending[1:]
        break
    return placed, pending, used


def step_slots(step):
    guide_layout.image_info(step, ROOT)
    title, th = para(f'{step["number"]}. {step["label"]}', bold=True, size=12, leading=16)
    crop = step['crop']
    aspect = (crop[3] - crop[1]) / (crop[2] - crop[0])
    blocks = [para(step['text'])[0]]
    if len(step.get('boxes', [])) > 1:
        blocks.extend(para(f'{item["box_index"] + 1}. {item["text"]}')[0]
                      for item in sorted(step['callouts'], key=lambda item: item['box_index']))
    assert th <= 48, (step['identity'], 'step title exceeds three lines')
    image_top = TOP - th - TITLE_IMAGE_GAP
    caption_height = sum(p.wrap(COL, H * 100)[1] for p in blocks) + 4 * (len(blocks) - 1)
    # 설명이 긴 단계는 사진 확대 폭을 줄여 같은 칸에 함께 배치합니다.
    original_height = min(340, (COL - 18) * aspect)
    caption_room = image_top - IMAGE_CAPTION_GAP - BOTTOM - caption_height
    image_height = min(MAX_IMAGE_HEIGHT, COL * aspect,
                       max(original_height, caption_room))
    text_top = image_top - image_height - IMAGE_CAPTION_GAP
    placed, remaining, used = consume(blocks, COL, text_top - BOTTOM)
    assert placed, step['identity']
    slots = [dict(step=step, title=title, title_height=th,
                  image_top=image_top, image_height=image_height,
                  text_top=text_top, blocks=placed, text_height=used)]
    while remaining:
        title, th = para(f'{step["number"]}. {step["label"]}\n설명 계속',
                         bold=True, size=12, leading=16)
        placed, rest, used = consume(remaining, COL, TOP - th - 12 - BOTTOM)
        assert placed and len(rest) <= len(remaining), step['identity']
        slots.append(dict(step=step, title=title, title_height=th, continuation=True,
                          text_top=TOP - th - 12, blocks=placed, text_height=used))
        remaining = rest
    return slots


def notes_pages(notes, chapter):
    pages, slots = [], []
    width = (W - 2 * MARGIN - GAP) / 2
    remaining = []
    for section, note in notes:
        heading, height = para(section, width, True, 12, 16)
        body, body_height = para(note, width)
        heading.guide_heading = True
        heading.guide_keep_height = height + body_height + 4
        body.guide_section = section
        remaining.extend([heading, body])
    while remaining:
        blocks, remaining, used = consume(remaining, width, TOP - BOTTOM)
        assert blocks
        if remaining and hasattr(remaining[0], 'guide_section'):
            heading, _ = para(remaining[0].guide_section + ' (계속)', width, True, 12, 16)
            heading.guide_heading = True
            heading.guide_continuation = True
            remaining.insert(0, heading)
        title, _ = para('', width)
        slots.append(dict(title=title, title_height=0, text_top=TOP,
                          blocks=blocks, text_height=used))
        if len(slots) == 2:
            pages.append(dict(kind='notes', chapter=chapter, section='참고·주의', slots=slots))
            slots = []
    if slots:
        pages.append(dict(kind='notes', chapter=chapter, section='참고·주의', slots=slots))
    return pages


def make_pages(content):
    groups = OrderedDict()
    for page in content:
        if page['kind'] == 'steps':
            key = (page['chapter'], page['section'])
            groups.setdefault(key, []).extend(page['steps'])
    pages, entries, notes = [], [], []
    chapter = None
    for (ch, section), steps in groups.items():
        if ch != chapter:
            if chapter:
                pages.extend(notes_pages(notes, chapter))
            notes = []
            chapter = ch
            entries.append(dict(text=ch, level=0, index=len(pages)))
        entries.append(dict(text=section, level=1, index=len(pages)))
        slots = []
        for step in steps:
            slots.extend(step_slots(step))
            note = step.get('source_note', '').strip()
            if note and (section, note) not in notes:
                notes.append((section, note))
        for i in range(0, len(slots), 4):
            pages.append(dict(kind='steps', chapter=ch, section=section, slots=slots[i:i + 4]))
    pages.extend(notes_pages(notes, chapter))
    toc_rows, toc_chunks, rows = [], [], []
    # Two columns; each row is measured before assigning a table-of-contents page.
    width = (W - 2 * MARGIN - GAP) / 2
    y = TOP
    column = 0
    for index, entry in enumerate(entries):
        p, h = para(entry['text'], width - 46, entry['level'] == 0, 11, 15)
        height = h + (10 if entry['level'] == 0 else 5)
        reserve = height
        if entry['level'] == 0 and index + 1 < len(entries):
            _, next_height = para(entries[index + 1]['text'], width - 46, False, 11, 15)
            reserve += next_height + 5
        if y - reserve < BOTTOM:
            column += 1
            y = TOP
        if column == 2:
            toc_chunks.append(rows)
            rows, column = [], 0
        rows.append(dict(entry=entry, paragraph=p, height=h, top=y, column=column))
        y -= height
    if rows:
        toc_chunks.append(rows)
    offset = 1 + len(toc_chunks)
    for entry in entries:
        entry['page'] = offset + entry['index'] + 1
        entry['anchor'] = ('chapter-' if entry['level'] == 0 else 'section-') + entry['text'].split()[0]
    return pages, entries, toc_chunks, groups


def draw_screenshot(c, slot, left, report):
    step, crop = slot['step'], slot['step']['crop']
    height, top = slot['image_height'], slot['image_top']
    scale = height / (crop[3] - crop[1])
    width = (crop[2] - crop[0]) * scale
    x, bottom = left, top - height
    assert width <= COL + 0.01, step['identity']
    with Image.open(ROOT / step['image']) as original:
        c.drawImage(ImageReader(original.crop(crop)), x, bottom, width, height, mask='auto')
    c.setStrokeColorRGB(0, 0, 0)
    c.setLineWidth(0.6)
    c.rect(x, bottom, width, height)
    box_positions = []
    for index, box in enumerate(step.get('boxes', [])):
        a, b, d, e = max(box[0], crop[0]), max(box[1], crop[1]), min(box[2], crop[2]), min(box[3], crop[3])
        bx, by = x + (a - crop[0]) * scale, top - (e - crop[1]) * scale
        bw, bh = (d - a) * scale, (e - b) * scale
        c.setStrokeColorRGB(1, 0, 0)
        c.setLineWidth(1.2)
        c.rect(bx, by, bw, bh)
        if len(step['boxes']) > 1:
            box_positions.append((index, by + bh - 5.5))
    if box_positions:
        radius, cx, separation = 5.5, x - 7, 13
        assert height >= 2 * radius + separation * (len(box_positions) - 1), step['identity']
        ceiling = top - radius
        for rank, (index, desired) in enumerate(sorted(box_positions, key=lambda item: -item[1])):
            floor = bottom + radius + separation * (len(box_positions) - rank - 1)
            cy = max(floor, min(ceiling, desired))
            ceiling = cy - separation
            c.setFillColorRGB(1, 0, 0)
            c.setStrokeColorRGB(1, 1, 1)
            c.setLineWidth(0.6)
            c.circle(cx, cy, radius, fill=1, stroke=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont(BOLD, 8)
            c.drawCentredString(cx, cy - 2.5, str(index + 1))
    report.update(image_rect=[x, bottom, x + width, top], image=step['image'], crop=crop)


def footer(c, number, total, label):
    c.setFillColorRGB(0.25, 0.28, 0.27)
    c.setFont(REG, 9)
    c.drawString(MARGIN, 14, 'MedBuddy 1.0.0')
    c.drawCentredString(W / 2, 14, f'{number} / {total}')
    size = min(9, 9 * (W / 2 - MARGIN - 45) / max(1, pdfmetrics.stringWidth(label, REG, 9)))
    c.setFont(REG, size)
    c.drawRightString(W - MARGIN, 14, label)


def build(font_dir, output):
    guide_layout.FONT_DIR = font_dir
    guide_layout.register_fonts()
    content_bytes = (BUILD / 'content.json').read_bytes()
    content = json.loads(content_bytes)
    pages, entries, toc, groups = make_pages(content)
    total = 1 + len(toc) + len(pages)
    data, records, step_pages, text_records = BytesIO(), [], {}, []
    c = canvas.Canvas(data, pagesize=(W, H), pageCompression=1, invariant=1)
    c.setTitle('MedBuddy 사용설명서 - ver 1.0.0')
    c.setAuthor('MedBuddy')
    c.setCreator('MedBuddy')
    c.drawImage(ImageReader(str(ROOT / 'assets/medbuddy_logo.png')),
                W / 2 - 90, H / 2 - 20, 180, 180, mask='auto', preserveAspectRatio=True)
    c.setFont(BOLD, 28)
    c.drawCentredString(W / 2, H / 2 - 60, 'MedBuddy 사용설명서')
    c.setFont(REG, 12)
    c.drawCentredString(W / 2, H / 2 - 86, 'ver 1.0.0')
    c.showPage()
    for number, rows in enumerate(toc, 2):
        c.setFont(BOLD, 18)
        c.drawString(MARGIN, H - MARGIN - 15, '차례')
        width = (W - 2 * MARGIN - GAP) / 2
        for row in rows:
            entry = row['entry']
            x = MARGIN + row['column'] * (width + GAP)
            y = row['top'] - row['height']
            row['paragraph'].drawOn(c, x, y)
            c.setFont(REG, 11)
            c.drawRightString(x + width, y + 3, str(entry['page']))
            c.linkRect('', entry['anchor'], (x, y - 2, x + width, row['top'] + 2), relative=0, thickness=0)
        footer(c, number, total, '차례')
        c.showPage()
    for index, page in enumerate(pages):
        number = index + len(toc) + 2
        for entry in entries:
            if entry['index'] == index:
                c.bookmarkPage(entry['anchor'])
                c.addOutlineEntry(entry['text'], entry['anchor'], entry['level'], closed=False)
        c.setFillColorRGB(0, 0, 0)
        if page['kind'] == 'chapter':
            p, h = para(page['chapter'], W - 2 * MARGIN, True, 28, 36)
            p.drawOn(c, MARGIN, H / 2 - h / 2)
        else:
            heading = page['section'] if page['kind'] == 'steps' else page['chapter'] + ' · 참고·주의'
            title, th = para(heading, W - 2 * MARGIN, True, 15, 19)
            assert th <= 22, heading
            title.drawOn(c, MARGIN, H - MARGIN - th)
            width = COL if page['kind'] == 'steps' else (W - 2 * MARGIN - GAP) / 2
            for col, slot in enumerate(page['slots']):
                x = MARGIN + col * (width + GAP)
                slot['title'].drawOn(c, x, TOP - slot['title_height'])
                rec = dict(page=number, column=col + 1, kind=page['kind'],
                           column_left=x, column_width=width,
                           text_bottom=slot['text_top'] - slot['text_height'])
                assert rec['text_bottom'] >= BOTTOM - 0.01, rec
                if page['kind'] == 'steps':
                    rec.update(identity=slot['step']['identity'], continuation=bool(slot.get('continuation')))
                    if not slot.get('continuation'):
                        draw_screenshot(c, slot, x, rec)
                        rec.update(title_image_gap=TITLE_IMAGE_GAP,
                                   image_caption_gap=IMAGE_CAPTION_GAP,
                                   title_height=slot['title_height'])
                        step_pages[slot['step']['identity']] = number
                y = slot['text_top']
                c.setFillColorRGB(0, 0, 0)
                for p, height, gap in slot['blocks']:
                    y -= gap + height
                    p.drawOn(c, x, y)
                    if not getattr(p, 'guide_continuation', False):
                        text_records.append((number, p.getPlainText()))
                records.append(rec)
        footer(c, number, total, page['section'] or page['chapter'])
        c.showPage()
    c.save()
    pdf = data.getvalue()
    reader = PdfReader(BytesIO(pdf))
    compact = re.sub(r'\s+', '', '\n'.join(p.extract_text() or '' for p in reader.pages))
    body_compact = re.sub(r'\s+', '', ''.join(text for _, text in text_records))
    page_texts = [re.sub(r'\s+', '', p.extract_text() or '') for p in reader.pages]
    for number, text in text_records:
        assert re.sub(r'\s+', '', text) in page_texts[number - 1], (number, text)
    expected = [s for steps in groups.values() for s in steps]
    for step in expected:
        assert re.sub(r'\s+', '', step['label']) in compact, step['identity']
        texts = [step['text'], step.get('source_note', '')]
        if len(step.get('boxes', [])) > 1:
            texts.extend(item['text'] for item in step['callouts'])
        for text in texts:
            assert re.sub(r'\s+', '', text) in body_compact, (step['identity'], text)
    assert len(step_pages) == len(expected)
    assert len(reader.pages) == total
    assert all(abs(float(p.mediabox.width) - W) < .1 for p in reader.pages)
    assert not guide_layout.LOCAL_PATH.search(compact)
    page_numbers = {p.indirect_reference.idnum: n for n, p in enumerate(reader.pages, 1)}
    actual_targets = []
    for page in reader.pages:
        for reference in page.get('/Annots', []):
            annotation = reference.get_object()
            if annotation.get('/Subtype') == '/Link':
                actual_targets.append(page_numbers[annotation['/Dest'][0].idnum])
    assert actual_targets == [entry['page'] for entry in entries]
    def flatten_outline(items):
        for item in items:
            if isinstance(item, list):
                yield from flatten_outline(item)
            else:
                yield item
    outline = list(flatten_outline(reader.outline))
    assert [(item.title, reader.get_destination_page_number(item) + 1) for item in outline] == [
        (entry['text'], entry['page']) for entry in entries]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(pdf)
    audit = dict(pages=total, sections=len(groups), steps=len(expected), columns=4,
                 page_margin_pt=MARGIN, column_gap_pt=GAP, column_width_pt=COL,
                 screenshots_aligned_to_step_numbers=True,
                 all_step_text_verified=True, all_notes_verified=True,
                 continuation_columns=sum(r.get('continuation', False) for r in records),
                 pdf_sha256=hashlib.sha256(pdf).hexdigest(),
                 content_sha256=hashlib.sha256(content_bytes).hexdigest(),
                 verified_internal_links=len(actual_targets), verified_bookmarks=len(outline),
                 screenshot_count=len(step_pages), step_pages=step_pages,
                 records=records, visual_qa='pending')
    (BUILD / 'landscape-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: audit[k] for k in ('pages', 'sections', 'steps', 'columns', 'continuation_columns')}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--font-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=BUILD / 'MedBuddy_User_Guide_ko.pdf')
    args = parser.parse_args()
    build(args.font_dir, args.output)
