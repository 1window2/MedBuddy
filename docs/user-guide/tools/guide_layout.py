"""Render the manual as PDF and Markdown, without editing input or screenshots.

Run with the bundled Python:
    python -B render_manual.py --input content.json --out candidate

Relative --input paths use the working directory. Relative --out paths use the
input directory. Output is restricted to this renderer's work directory.
pages.json is a public, path-free manifest, not a replacement for content.json.
All layout and PDF assembly finish in memory before successful outputs are saved.
Redraw images require explicit crops in original pixel coordinates; capture
dimensions may vary. Both real-device and headless UI captures are supported.

Input is a JSON list, in chapter/subsection order:
  divider: kind, chapter, section (headings begin with numeric identifiers).
  steps: kind, chapter, section, steps; optional wide (two slots, not four).
  Reused step pages need integer source_page in the approved source PDF.
  New/changed step pages need redraw=true; source_page is then not used.
  Each step needs identity, number, label, text. Number is unique per subsection.
  Redrawn steps also need image, crop=[left, top, right, bottom] in integer pixels.
  boxes is a list of rectangles in original-image pixels, before cropping.
  Multiple boxes require callouts=[{box_index: 0, text: ...}, ...], one per box.
  source_note is optional; exact strings dedupe only within the same subsection.
  Relative image paths resolve beside the input JSON. No image is fabricated.
  Legacy reference pages are ignored. Dividers are always rebuilt.
"""

from collections import Counter, OrderedDict
from copy import copy, deepcopy
from hashlib import sha256
from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape
import argparse
import json
import math
import re
import sys

from PIL import Image
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import Link
from pypdf.generic import ContentStream, NameObject
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / ".build/cover.pdf"
FONT_DIR = None
PDF_NAME = "MedBuddy_User_Guide_ko.pdf"
W, H = 595.32, 841.92
MM = 72 / 25.4
LEFT, RIGHT = 10 * MM, W - 10 * MM
REG, BOLD = "NanumBarunGothic", "NanumBarunGothicBold"
FOOTER_Y, FOOTER_SIZE, FOOTER_LEADING = 23.904, 9.96, 11
BODY_BOTTOM = 281 * MM
TOC_FIRST = 62
TOC_LAST = BODY_BOTTOM - 3
TEXT_SIZE, TEXT_LEADING = 11, 13.5
GAP = 4 * MM
BADGE_RADIUS, BADGE_STROKE, BADGE_GAP = 2.3 * MM, 0.7, 1
BOX_STROKE = 1.2
BLUE = (5 / 255, 99 / 255, 193 / 255)
LOCAL_PATH = re.compile(r"(?:[A-Za-z]:[\\/]|file://|\\\\[A-Za-z0-9_.-]+\\|/(?:Users|home)/)", re.I)


class LayoutError(ValueError):
    """A machine-readable failure with the affected step/page and measurements."""

    def __init__(self, message, **details):
        self.details = dict(message=message, **details)
        super().__init__(json.dumps(self.details, ensure_ascii=True))


def require(condition, message, **details):
    if not condition:
        raise LayoutError(message, **details)


def register_fonts():
    if REG in pdfmetrics.getRegisteredFontNames() and BOLD in pdfmetrics.getRegisteredFontNames():
        return
    require(FONT_DIR is not None, "Pass --font-dir through rebuild_guide.py")
    directories = [Path(FONT_DIR)]
    for name in (REG, BOLD):
        font = next((d / (name + ".ttf") for d in directories if (d / (name + ".ttf")).is_file()), None)
        require(font is not None, "Required approved font is unavailable", font=name)
        pdfmetrics.registerFont(TTFont(name, str(font)))


def check_public(text, identity):
    require(isinstance(text, str), "Expected text", identity=identity)
    require(not LOCAL_PATH.search(text), "Local path in published text", identity=identity)
    require(not re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", text),
            "Control character in published text", identity=identity)
    return text


def paragraph(text, width, size=TEXT_SIZE, leading=TEXT_LEADING, bold=False):
    require(width > 0, "Nonpositive paragraph width", width_pt=width)
    style = ParagraphStyle(
        "manual", fontName=BOLD if bold else REG, fontSize=size,
        leading=leading, wordWrap="CJK", splitLongWords=True,
        allowWidows=0, allowOrphans=0, spaceBefore=0, spaceAfter=0,
    )
    # Input is literal user copy, never ReportLab markup.
    value = escape(text).replace("\r\n", "\n").replace("\r", "\n").replace("\n", "<br/>")
    result = Paragraph(value, style)
    _, height = result.wrap(width, H * 100)
    return result, height


def wrap_lines(text, width, font, size):
    """Measured CJK wrapping, preferring whitespace when there is a useful break."""
    lines = []
    for block in text.split("\n"):
        if not block:
            lines.append("")
            continue
        while block:
            count = 0
            for i in range(1, len(block) + 1):
                if pdfmetrics.stringWidth(block[:i], font, size) > width + 0.01:
                    break
                count = i
            require(count > 0, "A glyph exceeds available width", width_pt=width, font_size=size)
            if count < len(block):
                split = block.rfind(" ", 0, count + 1)
                if split >= max(1, count // 2):
                    count = split
            lines.append(block[:count].rstrip())
            block = block[count:].lstrip()
    return lines


def balanced_lines(text, width, font, size):
    lines = wrap_lines(text, width, font, size)
    if len(lines) != 2 or "\n" in text:
        return lines
    candidates = []
    for n in range(1, len(text)):
        left, right = text[:n].rstrip(), text[n:].lstrip()
        if not left or not right:
            continue
        a, b = (pdfmetrics.stringWidth(t, font, size) for t in (left, right))
        if max(a, b) <= width + 0.01:
            inside_word = not any(ch.isspace() for ch in text[n - 1:n + 1])
            candidates.append((inside_word, abs(a - b), [left, right]))
    return min(candidates, key=lambda item: item[:2])[2] if candidates else lines


def footer_layout(page, total, label):
    number = f"{page} / {total}"
    number_right = W / 2 + pdfmetrics.stringWidth(number, REG, FOOTER_SIZE) / 2
    label_left = number_right + 12
    width = RIGHT - label_left
    lines = balanced_lines(label, width, REG, FOOTER_SIZE) if label else []
    shortened = len(lines) > 2
    if shortened:
        # Only the footer may be abbreviated. The full heading remains in TOC/body/MD.
        low, high = 1, len(label)
        best = "..."
        while low <= high:
            mid = (low + high) // 2
            candidate = label[:mid].rstrip() + "..."
            trial = balanced_lines(candidate, width, REG, FOOTER_SIZE)
            if len(trial) <= 2:
                best, low = candidate, mid + 1
            else:
                high = mid - 1
        lines = balanced_lines(best, width, REG, FOOTER_SIZE)
    ascent = pdfmetrics.getAscent(REG, FOOTER_SIZE)
    top = FOOTER_Y + max(0, len(lines) - 1) * FOOTER_LEADING + ascent
    require(top < H - BODY_BOTTOM - 1, "Footer overlaps content", page=page,
            label=label, footer_top_pt=top, content_bottom_pt=H - BODY_BOTTOM)
    return dict(page=page, number=number, label=label, lines=lines,
                label_left_pt=label_left, available_width_pt=width,
                font_size=FOOTER_SIZE, shortened=shortened, top_pt=top)


def draw_footer(c, record):
    c.saveState()
    c._code.append("/Artifact << /Type /Pagination /Subtype /Footer >> BDC")
    c.setFillColorRGB(0, 0, 0)
    c.setFont(REG, FOOTER_SIZE)
    c.drawString(LEFT, FOOTER_Y, "MedBuddy 0.2.5")
    c.drawCentredString(W / 2, FOOTER_Y, record["number"])
    for i, line in enumerate(record["lines"]):
        baseline = FOOTER_Y + (len(record["lines"]) - 1 - i) * FOOTER_LEADING
        c.drawRightString(RIGHT, baseline, line)
    c._code.append("EMC")
    c.restoreState()


def strip_original_footer(page, reader):
    """Retain every body operator; remove only the approved tagged footer."""
    stream = ContentStream(page.get_contents(), reader)
    kept, skip_depth, removed = [], 0, 0
    before = len(stream.operations)
    for operands, operator in stream.operations:
        if skip_depth:
            if operator in (b"BDC", b"BMC"):
                skip_depth += 1
            elif operator == b"EMC":
                skip_depth -= 1
            continue
        if (operator == b"BDC" and len(operands) == 2
                and isinstance(operands[1], dict)
                and operands[1].get("/Subtype") == "/Footer"):
            skip_depth = 1
            removed += 1
            continue
        kept.append((operands, operator))
    require(removed == 1 and skip_depth == 0, "Expected exactly one tagged original footer",
            removed=removed, unclosed_depth=skip_depth)
    stream.operations = kept
    page[NameObject("/Contents")] = stream
    return dict(removed_footer_count=removed, source_operations=before,
                retained_operations=len(kept), body_stream_sha256=sha256(stream.get_data()).hexdigest())


def anchor(text, level):
    key = text.split()[0]
    require(re.fullmatch(r"\d+(?:\.\d+)*", key) is not None,
            "Heading must begin with its numeric identifier", heading=text)
    return ("section-" if level else "chapter-") + key.replace(".", "-")


def toc_chunks(entries):
    chunks, current, top = [], [], TOC_FIRST
    # Reserve four page-number digits so wrapping does not depend on pagination.
    reserved = pdfmetrics.stringWidth("8888", REG, 11) + 12
    rows = []
    for entry in entries:
        x = LEFT + (14 if entry["level"] else 0)
        lines = wrap_lines(entry["text"], RIGHT - x - reserved,
                           REG if entry["level"] else BOLD, 11)
        rows.append(dict(entry, lines=lines, height=len(lines) * 17))
    i = 0
    while i < len(rows):
        group = rows[i:i + 2] if rows[i]["level"] == 0 else rows[i:i + 1]
        require(len(group) == 1 or group[1]["level"] == 1, "Chapter lacks subsection in TOC")
        need = sum(row["height"] for row in group)
        require(TOC_FIRST + need - 17 <= TOC_LAST, "TOC heading group exceeds page",
                heading=group[0]["text"], height_pt=need)
        if current and top + need - 17 > TOC_LAST:
            chunks.append(current)
            current, top = [], TOC_FIRST
        for row in group:
            current.append(dict(row, top=top))
            top += row["height"]
        i += len(group)
    if current:
        chunks.append(current)
    return chunks


def number_ranges(numbers):
    values = sorted(set(numbers))
    groups = []
    for value in values:
        if groups and value == groups[-1][-1] + 1:
            groups[-1].append(value)
        else:
            groups.append([value])
    return ", ".join(str(g[0]) if len(g) == 1 else f"{g[0]}~{g[-1]}" for g in groups)


def reference_parts(item, locations):
    grouped = OrderedDict()
    for identity in item["identities"]:
        loc = locations[identity]
        require(loc["section"] == item["section"], "Reference crossed subsection", identity=identity)
        grouped.setdefault(loc["page"], []).append(loc["number"])
    section = item["section"].split()[0]
    return [
        dict(text=f"{section} - {page}\ud398\uc774\uc9c0 - {number_ranges(numbers)}\ubc88 \uc0ac\uc9c4",
             target_page=page, anchor=f"manual_page_{page}")
        for page, numbers in grouped.items()
    ]


def reference_metrics(item):
    link_lines = [wrap_lines(part["text"], 184 * MM, BOLD, 11) for part in item["link_parts"]]
    _, text_height = paragraph(item["text"], 184 * MM, size=12, leading=17)
    height = sum(len(lines) * 15 for lines in link_lines) + 3 * MM + text_height + 7 * MM
    return dict(link_lines=link_lines, text_height_pt=text_height, height_pt=height)


def paginate_references(items, chapter, start_page):
    result, current, top = [], [], 22 * MM
    limit = 278 * MM
    for item in items:
        metrics = reference_metrics(item)
        require(metrics["height_pt"] <= limit - 22 * MM, "Reference does not fit a page",
                identities=item["identities"], section=item["section"],
                required_height_pt=metrics["height_pt"], available_height_pt=limit - 22 * MM)
        if current and top + metrics["height_pt"] > limit:
            result.append(current)
            current, top = [], 22 * MM
        item.update(y=top / MM, height=metrics["height_pt"] / MM)
        current.append(item)
        top += metrics["height_pt"]
    if current:
        result.append(current)
    return [
        dict(kind="references", chapter=chapter, section="", steps=[], items=chunk,
             continuation=i + 1, wide=False, note="", page=start_page + i)
        for i, chunk in enumerate(result)
    ]


def validate_content(content):
    require(isinstance(content, list), "Input must be a list of pages")
    body, chapters, sections, identities, numbers = [], set(), set(), set(), set()
    current_chapter = current_section = None
    ignored = 0
    for index, original in enumerate(content):
        require(isinstance(original, dict), "Page must be an object", input_index=index)
        if original.get("kind") == "references":
            ignored += 1
            continue
        page = deepcopy(original)
        require(page.get("kind") in ("divider", "steps"), "Unsupported page kind", input_index=index)
        for key in ("chapter", "section"):
            require(isinstance(page.get(key), str) and page[key].strip(),
                    "Missing heading", input_index=index, field=key)
            check_public(page[key], f"page:{index}:{key}")
        if page["kind"] == "divider":
            if page["chapter"] != current_chapter:
                require(page["chapter"] not in chapters, "Chapter is not contiguous", chapter=page["chapter"])
                chapters.add(page["chapter"])
            require(page["section"] not in sections, "Duplicate subsection divider", section=page["section"])
            sections.add(page["section"])
            current_chapter, current_section = page["chapter"], page["section"]
            page["steps"] = []
        else:
            require((page["chapter"], page["section"]) == (current_chapter, current_section),
                    "Steps must follow their subsection divider", input_index=index)
            require(isinstance(page.get("steps"), list) and page["steps"], "Empty step page", input_index=index)
            require(isinstance(page.get("wide", False), bool), "wide must be boolean", input_index=index)
            require(isinstance(page.get("redraw", False), bool), "redraw must be boolean", input_index=index)
            require(len(page["steps"]) <= (2 if page.get("wide") else 4),
                    "Too many steps for fixed slots", section=page["section"], count=len(page["steps"]))
            if not page.get("redraw"):
                require(type(page.get("source_page")) is int and page["source_page"] > 1,
                        "Unchanged steps need approved source_page; new steps need redraw=true",
                        input_index=index, section=page["section"])
            for step in page["steps"]:
                identity = step.get("identity")
                require(isinstance(identity, str) and bool(identity), "Step needs identity", input_index=index)
                check_public(identity, identity)
                require(identity not in identities, "Duplicate step identity", identity=identity)
                identities.add(identity)
                require(type(step.get("number")) is int and step["number"] > 0,
                        "Step number must be a positive integer", identity=identity)
                key = (page["section"], step["number"])
                require(key not in numbers, "Duplicate photo number within subsection", identity=identity)
                numbers.add(key)
                for field in ("label", "text"):
                    require(isinstance(step.get(field), str) and step[field].strip(),
                            "Missing authoritative step copy", identity=identity, field=field)
                    check_public(step[field], identity)
                check_public(step.get("source_note", ""), identity)
                require(isinstance(step.get("boxes", []), list), "boxes must be a list", identity=identity)
                if len(step.get("boxes", [])) > 1:
                    callouts = step.get("callouts", [])
                    require(isinstance(callouts, list) and all(isinstance(c, dict) for c in callouts),
                            "callouts must be objects", identity=identity)
                    indices = [c.get("box_index") for c in callouts]
                    require(all(type(i) is int for i in indices)
                            and sorted(indices) == list(range(len(step["boxes"]))),
                            "Every box needs exactly one matching callout", identity=identity,
                            box_count=len(step["boxes"]), callout_indices=indices)
                    for callout in callouts:
                        check_public(callout.get("text"), identity)
                        require(callout["text"].strip(), "Empty callout", identity=identity)
        body.append(page)
    require(body and any(p["kind"] == "steps" for p in body), "Input contains no steps")
    return body, ignored


def make_plan(content, input_dir=HERE):
    register_fonts()
    body, ignored = validate_content(content)
    entries, seen = [], set()
    for index, page in enumerate(body):
        if page["kind"] != "divider":
            continue
        if page["chapter"] not in seen:
            entries.append(dict(text=page["chapter"], level=0, body_index=index,
                                anchor=anchor(page["chapter"], 0)))
            seen.add(page["chapter"])
        entries.append(dict(text=page["section"], level=1, body_index=index,
                            anchor=anchor(page["section"], 1)))
    require(len({e["anchor"] for e in entries}) == len(entries), "Duplicate navigation anchor")
    chunks = toc_chunks(entries)
    pages, locations, notes = [], {}, OrderedDict()
    chapter = None

    def finish_chapter():
        if not notes:
            return
        items = list(notes.values())
        for item in items:
            item["link_parts"] = reference_parts(item, locations)
            item["reference"] = "\n".join(p["text"] for p in item["link_parts"])
        pages.extend(paginate_references(items, chapter, 2 + len(chunks) + len(pages)))
        notes.clear()

    for page in body:
        if chapter is not None and page["chapter"] != chapter:
            finish_chapter()
        chapter = page["chapter"]
        page["page"] = 2 + len(chunks) + len(pages)
        pages.append(page)
        for step in page.get("steps", []):
            identity = step["identity"]
            locations[identity] = dict(page=page["page"], number=step["number"], section=page["section"])
            note = step.get("source_note", "")
            if note.strip():
                key = (page["section"], note)
                item = notes.setdefault(key, dict(section=page["section"], text=note, identities=[]))
                item["identities"].append(identity)
    finish_chapter()
    for entry in entries:
        entry["page"] = body[entry.pop("body_index")]["page"]
    by_anchor = {entry["anchor"]: entry["page"] for entry in entries}
    for chunk in chunks:
        for entry in chunk:
            entry.pop("body_index")
            entry["page"] = by_anchor[entry["anchor"]]
    total = 1 + len(chunks) + len(pages)
    require(total <= 9999, "TOC page-number reserve exceeded", total_pages=total)
    layout = dict(
        units="pt unless key ends in _mm or _px", page_size_pt=[W, H],
        body_bottom_mm=281, row_title_tops_mm=[6, 147.5],
        image_tops_mm=[14, 155.5], panel_x_mm=[10, 108], panel_width_mm=92,
        wide_panel_width_mm=190, text_font_size=TEXT_SIZE, text_leading=TEXT_LEADING,
        max_screenshot_width_mm=61, min_screenshot_width_mm=40,
        badge_policy="9 pt digits; prefer outside left, then right; clear all targets, captions and badges by 1 pt; paint after photo clipping and frame.",
        footer_policy="Balance/wrap at 9.96 pt in up to two lines; abbreviate only longer footers with ...; retain full headings elsewhere.",
        steps={}, dividers=[], footers=[], references=[],
    )
    plan = dict(pages=pages, entries=entries, toc_chunks=chunks, locations=locations,
                total_pages=total, ignored_reference_pages=ignored, layout=layout,
                input_dir=Path(input_dir).resolve())
    for page in pages:
        if page["kind"] == "steps" and page.get("redraw"):
            layout["steps"].update(layout_steps(page, plan["input_dir"]))
    return plan


def image_info(step, input_dir):
    identity = step["identity"]
    require(isinstance(step.get("image"), str) and step["image"], "Missing screenshot", identity=identity)
    path = Path(step["image"])
    if not path.is_absolute():
        path = input_dir / path
    require(path.is_file(), "Screenshot file is missing", identity=identity)
    try:
        data = path.read_bytes()
        with Image.open(BytesIO(data)) as image:
            image.load()
            size = image.size
    except Exception as exc:
        raise LayoutError("Screenshot cannot be decoded", identity=identity, error_type=type(exc).__name__) from exc
    crop = step.get("crop")
    require(isinstance(crop, (list, tuple)) and len(crop) == 4
            and all(type(v) is int for v in crop),
            "Redraw screenshots require an explicit integer pixel crop", identity=identity,
            image_size_px=size)
    x0, y0, x1, y1 = crop
    require(0 <= x0 < x1 <= size[0] and 0 <= y0 < y1 <= size[1],
            "Crop exceeds actual screenshot", identity=identity, image_size_px=size, crop_px=crop)
    boxes = []
    for index, box in enumerate(step.get("boxes", [])):
        require(isinstance(box, (list, tuple)) and len(box) == 4
                and all(type(v) in (int, float) and math.isfinite(v) for v in box),
                "Invalid annotation box", identity=identity, box_index=index)
        a, b, d, e = box
        require(0 <= a < d <= size[0] and 0 <= b < e <= size[1],
                "Box exceeds original screenshot", identity=identity, box_index=index,
                box_px=box, image_size_px=size)
        clipped = [max(a, x0), max(b, y0), min(d, x1), min(e, y1)]
        require(clipped[0] < clipped[2] and clipped[1] < clipped[3],
                "Box is outside placed crop", identity=identity, box_index=index, box_px=box, crop_px=crop)
        boxes.append(dict(original_px=list(box), clipped_px=clipped))
    return dict(image_size_px=list(size), crop_px=list(crop), boxes=boxes,
                image_sha256=sha256(data).hexdigest())


def copy_blocks(step, width):
    blocks = [(step["text"], False)]
    if len(step.get("boxes", [])) > 1:
        blocks += [(f'{c["box_index"] + 1}. {c["text"]}', False)
                   for c in sorted(step["callouts"], key=lambda c: c["box_index"])]
    result, height = [], 0
    for i, (text, bold) in enumerate(blocks):
        gap = 3 if i else 0
        p, h = paragraph(text, width, bold=bold)
        result.append((p, h, gap))
        height += gap + h
    return result, height


def layout_steps(page, input_dir):
    slots = []
    for index, step in enumerate(page["steps"]):
        row = index if page.get("wide") else index // 2
        title_top = (6 + row * 141.5) * MM
        image_top = title_top + 8 * MM
        bottom = (139.5 + row * 141.5) * MM
        panel_width = (190 if page.get("wide") else 92) * MM
        x = (10 if page.get("wide") else 10 + index % 2 * 98) * MM
        title, title_height = paragraph(f'{step["number"]}. {step["label"]}', panel_width,
                                        size=12, leading=15, bold=True)
        require(title_height <= image_top - title_top - 2, "Step title does not fit fixed title band",
                identity=step["identity"], page=page["page"], panel_width_pt=panel_width,
                required_height_pt=title_height, available_height_pt=image_top - title_top - 2)
        info = image_info(step, input_dir)
        crop = info["crop_px"]
        aspect = (crop[3] - crop[1]) / (crop[2] - crop[0])
        available = bottom - image_top
        chosen = None
        for half_mm in range(122, 79, -1):
            width = half_mm / 2 * MM
            text_width = panel_width - width - GAP
            _, text_height = copy_blocks(step, text_width)
            if width * aspect <= available and text_height <= available:
                chosen = width
                break
        require(chosen is not None, "Step copy/screenshot does not fit; shorten copy or use wide=true",
                identity=step["identity"], page=page["page"], panel_width_pt=panel_width,
                available_height_pt=available, minimum_image_width_mm=40,
                required_text_height_at_min_width_pt=text_height,
                image_height_at_min_width_pt=40 * MM * aspect, image_size_px=info["image_size_px"])
        slots.append(dict(identity=step["identity"], page=page["page"], slot=index,
                          x_pt=x, panel_width_pt=panel_width, title_top_pt=title_top,
                          title_height_pt=title_height, image_top_pt=image_top,
                          content_bottom_pt=bottom, available_height_pt=available,
                          chosen_width_pt=chosen, aspect=aspect, **info))
    # One image width per redrawn page keeps all occupied slots aligned.
    common = min(slot["chosen_width_pt"] for slot in slots)
    for slot, step in zip(slots, page["steps"]):
        slot.pop("chosen_width_pt")
        aspect = slot.pop("aspect")
        text_width = slot["panel_width_pt"] - common - GAP
        _, text_height = copy_blocks(step, text_width)
        slot.update(image_width_mm=common / MM, image_height_mm=common * aspect / MM,
                    text_x_pt=slot["x_pt"] + common + GAP, text_width_pt=text_width,
                    text_height_pt=text_height)
        require(text_height <= slot["available_height_pt"], "Common-width copy overflow", identity=step["identity"])
    layout_annotations(slots, page.get("wide", False))
    return {slot["identity"]: slot for slot in slots}


def circle_rect_distance(cx, cy, rect):
    return math.hypot(max(rect[0] - cx, 0, cx - rect[2]),
                      max(rect[1] - cy, 0, cy - rect[3]))


def layout_annotations(slots, wide):
    targets, copy_areas = [], []
    for slot in slots:
        x, top = slot["x_pt"], H - slot["image_top_pt"]
        crop = slot["crop_px"]
        scale = slot["image_width_mm"] * MM / (crop[2] - crop[0])
        boxes = [[x + (a - crop[0]) * scale, top - (e - crop[1]) * scale,
                  x + (d - crop[0]) * scale, top - (b - crop[1]) * scale]
                 for a, b, d, e in (box["clipped_px"] for box in slot["boxes"])]
        slot.update(vector_boxes_pt=boxes, badge_centers_pt=[], badge_sides=[],
                    badge_radius_pt=BADGE_RADIUS, badge_gap_pt=BADGE_GAP)
        targets.extend(boxes)
        copy_areas.extend([
            [x, H - slot["title_top_pt"] - slot["title_height_pt"],
             x + slot["panel_width_pt"], H - slot["title_top_pt"]],
            [slot["text_x_pt"], top - slot["text_height_pt"],
             x + slot["panel_width_pt"], top],
        ])

    outer_radius = BADGE_RADIUS + BADGE_STROKE / 2
    clearance = outer_radius + BOX_STROKE / 2 + BADGE_GAP
    separation = 2 * outer_radius + BADGE_GAP
    placed = []
    for slot in slots:
        # The right column can use its gutter, but never the preceding caption.
        left = (slot["x_pt"] - 6 * MM + BADGE_GAP
                if not wide and slot["slot"] % 2 else BADGE_GAP)
        bounds = [left, H - slot["content_bottom_pt"] + BADGE_GAP,
                  slot["x_pt"] + slot["panel_width_pt"] - BADGE_GAP,
                  H - slot["image_top_pt"] - BADGE_GAP]
        slot["badge_allocation_pt"] = bounds
        boxes = slot["vector_boxes_pt"]
        if len(boxes) < 2:
            continue
        options = []
        for index, (a, b, d, e) in enumerate(boxes):
            require(pdfmetrics.stringWidth(str(index + 1), BOLD, 9) < 2 * BADGE_RADIUS - 1,
                    "Badge number does not fit", identity=slot["identity"], box_index=index)
            low = max(b - clearance, bounds[1] + outer_radius)
            high = min(e + clearance, bounds[3] - outer_radius)
            candidates = []
            if low <= high:
                ys = {low, high, max(low, min(e, high)), max(low, min(b, high)),
                      max(low, min((b + e) / 2, high))}
                ys.update(float(y) for y in range(math.ceil(low), math.floor(high) + 1))
                # Include exact clearance positions beside adjoining/nested controls.
                for rect in targets:
                    ys.update(y for y in (rect[1] - clearance, rect[3] + clearance)
                              if low <= y <= high)
                for side, cx in (("left", a - clearance), ("right", d + clearance)):
                    if cx - outer_radius < bounds[0] or cx + outer_radius > bounds[2]:
                        continue
                    for cy in ys:
                        if any(circle_rect_distance(cx, cy, rect) < clearance - 1e-6
                               for rect in targets):
                            continue
                        if any(circle_rect_distance(cx, cy, rect) < outer_radius + BADGE_GAP - 1e-6
                               for rect in copy_areas):
                            continue
                        if any(math.hypot(cx - px, cy - py) < separation - 1e-6 for px, py in placed):
                            continue
                        # Stay beside the edge before trying a short corner detour.
                        score = (not b <= cy <= e, side != "left", abs(cy - e))
                        candidates.append((score, cx, cy, side))
            candidates.sort(key=lambda value: value[0])
            require(candidates, "No clear position outside numbered annotation box",
                    identity=slot["identity"], page=slot["page"], box_index=index,
                    box_pt=boxes[index], allocation_pt=bounds,
                    badge_diameter_pt=2 * outer_radius, gap_pt=BADGE_GAP,
                    image_width_mm=slot["image_width_mm"])
            options.append(candidates)

        # Resolve tighter controls first; backtrack instead of silently obscuring UI.
        chosen = {}

        def choose():
            if len(chosen) == len(options):
                return True
            viable = {}
            for index, candidates in enumerate(options):
                if index not in chosen:
                    viable[index] = [candidate for candidate in candidates
                                     if all(math.hypot(candidate[1] - p[1], candidate[2] - p[2])
                                            >= separation - 1e-6 for p in chosen.values())]
            index = min(viable, key=lambda key: len(viable[key]))
            for candidate in viable[index]:
                chosen[index] = candidate
                if choose():
                    return True
                del chosen[index]
            return False

        require(choose(), "No nonoverlapping numbered badge arrangement",
                identity=slot["identity"], page=slot["page"], boxes_pt=boxes,
                allocation_pt=bounds, badge_diameter_pt=2 * outer_radius,
                candidate_counts=[len(candidates) for candidates in options])
        slot["badge_centers_pt"] = [[chosen[i][1], chosen[i][2]] for i in range(len(boxes))]
        slot["badge_sides"] = [chosen[i][3] for i in range(len(boxes))]
        placed.extend(slot["badge_centers_pt"])


def add_link(annotations, rect, target):
    require(0 <= rect[0] < rect[2] <= W and 0 <= rect[1] < rect[3] <= H,
            "Invalid navigation hitbox", target_page=target, rect_pt=rect)
    annotations.append(dict(rect=list(rect), target=target))


def draw_toc(c, entries, annotations):
    c.setFillColorRGB(0, 0, 0)
    c.setFont(BOLD, 19)
    c.drawString(LEFT, H - 34, "\ucc28\ub840")
    for entry in entries:
        x = LEFT + (14 if entry["level"] else 0)
        font = REG if entry["level"] else BOLD
        y = H - entry["top"]
        c.setFont(font, 11)
        for line_index, line in enumerate(entry["lines"]):
            baseline = y - line_index * 17
            c.drawString(x, baseline, line)
        last = y - (len(entry["lines"]) - 1) * 17
        c.setFont(REG, 11)
        number = str(entry["page"])
        c.drawRightString(RIGHT, last, number)
        start = x + pdfmetrics.stringWidth(entry["lines"][-1], font, 11) + 5
        end = RIGHT - pdfmetrics.stringWidth(number, REG, 11) - 5
        require(end > start, "TOC leaders collide", heading=entry["text"])
        c.saveState()
        c.setLineWidth(0.45)
        c.setDash(0.6, 2.2)
        c.line(start, last + 1, end, last + 1)
        c.restoreState()
        add_link(annotations, (x, last - 3, RIGHT, y + 11), entry["page"])


def draw_divider(c, page, layout):
    chapter = balanced_lines(page["chapter"], 190 * MM, BOLD, 32)
    section = balanced_lines(page["section"], 190 * MM, BOLD, 24)
    height = len(chapter) * 40 + 10 * MM + len(section) * 32
    top = (H - height) / 2
    require(top > 6 * MM and top + height < BODY_BOTTOM, "Divider exceeds available height",
            section=page["section"], required_height_pt=height)
    cursor = top
    c.setFillColorRGB(0, 0, 0)
    for lines, size, leading in ((chapter, 32, 40), (section, 24, 32)):
        c.setFont(BOLD, size)
        for line in lines:
            c.drawCentredString(W / 2, H - cursor - pdfmetrics.getAscent(BOLD, size), line)
            cursor += leading
        if size == 32:
            cursor += 10 * MM
    layout["dividers"].append(dict(page=page["page"], chapter_lines=chapter,
                                  section_lines=section, top_pt=top, height_pt=height))


def draw_steps(c, page, plan):
    for step in page["steps"]:
        slot = plan["layout"]["steps"][step["identity"]]
        width, height = slot["image_width_mm"] * MM, slot["image_height_mm"] * MM
        x, top = slot["x_pt"], slot["image_top_pt"]
        bottom = H - top - height
        title, title_height = paragraph(f'{step["number"]}. {step["label"]}', slot["panel_width_pt"],
                                        size=12, leading=15, bold=True)
        c.setFillColorRGB(0, 0, 0)
        title.drawOn(c, x, H - slot["title_top_pt"] - title_height)
        path = Path(step["image"])
        if not path.is_absolute():
            path = plan["input_dir"] / path
        data = path.read_bytes()
        require(sha256(data).hexdigest() == slot["image_sha256"],
                "Screenshot changed after layout measurement", identity=step["identity"])
        with Image.open(BytesIO(data)) as original:
            # Crop only for placement; red annotations remain PDF vector objects.
            cropped = original.crop(slot["crop_px"])
            c.drawImage(ImageReader(cropped), x, bottom, width, height, mask="auto")
        c.saveState()
        clip = c.beginPath()
        clip.rect(x, bottom, width, height)
        c.clipPath(clip, stroke=0, fill=0)
        c.setStrokeColorRGB(1, 0, 0)
        c.setLineWidth(BOX_STROKE)
        for bx, by, right, upper in slot["vector_boxes_pt"]:
            c.rect(bx, by, right - bx, upper - by, fill=0, stroke=1)
        c.restoreState()
        c.saveState()
        c.setStrokeColorRGB(0, 0, 0)
        c.setLineWidth(0.6)
        c.rect(x, bottom, width, height, fill=0, stroke=1)
        # Paint after restoring the photo clip and frame, including margin badges.
        for index, (cx, cy) in enumerate(slot["badge_centers_pt"]):
            c.setFillColorRGB(1, 0, 0)
            c.setStrokeColorRGB(1, 1, 1)
            c.setLineWidth(BADGE_STROKE)
            c.circle(cx, cy, BADGE_RADIUS, fill=1, stroke=1)
            c.setFillColorRGB(1, 1, 1)
            c.setFont(BOLD, 9)
            c.drawCentredString(cx, cy - (pdfmetrics.getAscent(BOLD, 9) + pdfmetrics.getDescent(BOLD, 9)) / 2,
                               str(index + 1))
        c.restoreState()
        blocks, measured = copy_blocks(step, slot["text_width_pt"])
        require(measured <= slot["available_height_pt"], "Copy overflow at draw time", identity=step["identity"])
        cursor = H - top
        for block, block_height, gap in blocks:
            cursor -= gap + block_height
            block.drawOn(c, slot["text_x_pt"], cursor)


def draw_references(c, page, annotations, layout):
    c.setFillColorRGB(0, 0, 0)
    c.setFont(BOLD, 18)
    c.drawString(LEFT, H - 6 * MM - 18, "\ucc38\uace0")
    for item in page["items"]:
        metrics = reference_metrics(item)
        y = H - item["y"] * MM
        for part, lines in zip(item["link_parts"], metrics["link_lines"]):
            c.setFont(BOLD, 11)
            c.setFillColorRGB(*BLUE)
            c.setStrokeColorRGB(*BLUE)
            for line in lines:
                baseline = y - 11
                width = pdfmetrics.stringWidth(line, BOLD, 11)
                c.drawString(LEFT, baseline, line)
                c.setLineWidth(0.5)
                c.line(LEFT, baseline - 1.7, LEFT + width, baseline - 1.7)
                add_link(annotations, (LEFT, baseline - 3, LEFT + width, baseline + 11), part["target_page"])
                y -= 15
        p, height = paragraph(item["text"], 184 * MM, size=12, leading=17)
        bottom = y - 3 * MM - height
        require(bottom >= H - (item["y"] + item["height"]) * MM + 4,
                "Reference text exceeds measured block", identities=item["identities"], page=page["page"])
        c.setFillColorRGB(0, 0, 0)
        p.drawOn(c, LEFT, bottom)
        layout["references"].append(dict(page=page["page"], identities=item["identities"],
                                          top_mm=item["y"], height_mm=item["height"],
                                          text_height_pt=height))


def render_pdf(plan, source=SOURCE):
    require(Path(source).is_file(), "Approved source PDF is missing")
    for key in ("dividers", "references", "footers"):
        plan["layout"][key] = []
    source_bytes = Path(source).read_bytes()
    original = PdfReader(BytesIO(source_bytes))
    total = plan["total_pages"]
    generated = BytesIO()
    c = canvas.Canvas(generated, pagesize=(W, H), pageCompression=1, invariant=1)
    c.setAuthor("MedBuddy")
    c.setCreator("MedBuddy")
    c.setTitle("MedBuddy \uc0ac\uc6a9\uc124\uba85\uc11c")
    indexed = {p["page"]: p for p in plan["pages"]}
    annotations, sources, labels = {}, {1: 1}, {}
    for n in range(1, total + 1):
        annotations[n] = []
        if n == 1:
            label = ""
        elif n <= 1 + len(plan["toc_chunks"]):
            label = "\ucc28\ub840"
            draw_toc(c, plan["toc_chunks"][n - 2], annotations[n])
        else:
            page = indexed[n]
            label = page["section"] or page["chapter"] + " \u00b7 \ucc38\uace0"
            if page["kind"] == "divider":
                draw_divider(c, page, plan["layout"])
            elif page["kind"] == "references":
                draw_references(c, page, annotations[n], plan["layout"])
            elif page.get("redraw"):
                draw_steps(c, page, plan)
            else:
                sources[n] = page["source_page"]
        labels[n] = label
        record = footer_layout(n, total, label)
        plan["layout"]["footers"].append(record)
        draw_footer(c, record)
        c.showPage()
    c.save()
    overlay = PdfReader(BytesIO(generated.getvalue()))
    writer = PdfWriter()
    preserved = []
    for n in range(1, total + 1):
        if n in sources:
            old = sources[n]
            require(1 <= old <= len(original.pages), "source_page out of range",
                    page=n, source_page=old, source_total=len(original.pages))
            source_page = copy(original.pages[old - 1])
            require(not source_page.get("/Annots"), "Retained source has unexpected annotations", source_page=old)
            require(source_page.rotation == 0
                    and abs(float(source_page.mediabox.width) - W) < 0.1
                    and abs(float(source_page.mediabox.height) - H) < 0.1,
                    "Retained source has unexpected page geometry", source_page=old)
            proof = strip_original_footer(source_page, original)
            preserved.append(dict(page=n, source_page=old, **proof))
            page = writer.add_page(source_page, excluded_keys=["/StructParents", "/Metadata", "/PieceInfo"])
            page.merge_page(overlay.pages[n - 1])
        else:
            writer.add_page(overlay.pages[n - 1])
    for n, links in annotations.items():
        for link in links:
            require(1 <= link["target"] <= total, "Broken internal link", page=n, target=link["target"])
            annotation = writer.add_annotation(
                n - 1, Link(rect=link["rect"], target_page_index=link["target"] - 1))
            annotation["/Dest"][0] = writer.pages[link["target"] - 1].indirect_reference
    chapter_mark = None
    for entry in plan["entries"]:
        mark = writer.add_outline_item(entry["text"], entry["page"] - 1,
                                       parent=chapter_mark if entry["level"] else None)
        if not entry["level"]:
            chapter_mark = mark
    writer.add_metadata({
        "/Title": "MedBuddy \uc0ac\uc6a9\uc124\uba85\uc11c", "/Author": "MedBuddy",
        "/Subject": "\ud658\uc790\uc640 \ubcf4\ud638\uc790\ub97c \uc704\ud55c Android \uc571 \uc0ac\uc6a9 \uc548\ub0b4 - \ubcd1\uc6d0\uacfc \uc57d\uad6d \ucc3e\uae30 \ud3ec\ud568",
        "/Creator": "MedBuddy", "/Producer": "MedBuddy",
    })
    output = BytesIO()
    writer.write(output)
    pdf = output.getvalue()
    navigation = dict(total_pages=total, toc_pages=list(range(2, 2 + len(plan["toc_chunks"]))),
                      toc_entries=plan["toc_chunks"], labels=labels, annotations=annotations,
                      retained_pages=sources, locations=plan["locations"],
                      source_to_output_pages={old: [n for n, src in sources.items() if src == old]
                                              for old in dict.fromkeys(sources.values())})
    verification = verify_pdf(pdf, plan, annotations)
    audit = dict(
        passed=True, **verification, source_pdf_sha256=sha256(source_bytes).hexdigest(),
        output_pdf_sha256=sha256(pdf).hexdigest(), page_counts=dict(Counter(p["kind"] for p in plan["pages"])),
        ignored_old_reference_pages=plan["ignored_reference_pages"],
        reference_items=sum(len(p.get("items", [])) for p in plan["pages"]),
        reference_dedupe="Exact source_note string within subsection; references rebuilt at chapter end.",
        retained_pages=preserved, redraw_pages=[p["page"] for p in plan["pages"] if p["kind"] == "steps" and p.get("redraw")],
        screenshot_policy="Original pixels cropped for placement; red boxes and badges are PDF vectors.",
        footer_adjustments=[r for r in plan["layout"]["footers"] if len(r["lines"]) > 1 or r["shortened"]],
        visual_qa="Required separately: no pixel-identical or visual-QA claim is made by this structural audit.",
    )
    return pdf, navigation, audit


def verify_pdf(data, plan, annotations):
    reader = PdfReader(BytesIO(data))
    require(len(reader.pages) == plan["total_pages"], "Written PDF page count differs")
    require(reader.metadata.get("/Author") == "MedBuddy", "Unexpected PDF author")
    require("/Metadata" not in reader.trailer["/Root"], "Unexpected document XMP")
    indices = {p.indirect_reference.idnum: n + 1 for n, p in enumerate(reader.pages)}
    checked = 0
    for n, page in enumerate(reader.pages, 1):
        require(abs(float(page.mediabox.width) - W) < 0.1 and abs(float(page.mediabox.height) - H) < 0.1,
                "Output page size differs", page=n)
        found = []
        for ref in page.get("/Annots", []):
            annotation = ref.get_object()
            require(annotation.get("/Subtype") == "/Link" and "/A" not in annotation,
                    "Unexpected external/action annotation", page=n)
            target = indices.get(annotation["/Dest"][0].idnum)
            found.append(target)
        require(found == [link["target"] for link in annotations[n]],
                "Written PDF link targets differ", page=n, targets=found)
        checked += len(found)
    require(not LOCAL_PATH.search(json.dumps(dict(reader.metadata))),
            "Local path in PDF metadata")
    outlines = []

    def visit(items):
        for item in items:
            if isinstance(item, list):
                visit(item)
            else:
                outlines.append((item.title, reader.get_destination_page_number(item) + 1))

    visit(reader.outline)
    require(outlines == [(e["text"], e["page"]) for e in plan["entries"]],
            "Written PDF bookmarks differ")
    return dict(total_pages=len(reader.pages), verified_internal_links=checked,
                verified_bookmarks=len(outlines), clean_metadata=True)


def markdown(plan):
    lines = [
        '<img src="../../frontend/assets/app_icon/medbuddy_logo.png" width="120" alt="MedBuddy \ub85c\uace0">',
        "", "# MedBuddy \uc0ac\uc6a9\uc124\uba85\uc11c", "",
        "\ud658\uc790\uc640 \ubcf4\ud638\uc790\ub97c \uc704\ud55c Android \uc571 \uc0ac\uc6a9 \uc548\ub0b4\uc785\ub2c8\ub2e4. \uc57d \ub4f1\ub85d\uacfc \ubcf5\uc57d \uae30\ub85d\ubd80\ud130 \ud658\uc790\u00b7\ubcf4\ud638\uc790 \uc5f0\uacb0, \uac00\uc871 \ucc44\ud305, \uc704\uc82f, \ubcd1\uc6d0\u00b7\uc57d\uad6d \ucc3e\uae30\uc640 \ud658\uacbd\uc124\uc815\uae4c\uc9c0 \uc774\uc6a9 \uc21c\uc11c\ub300\ub85c \uc124\uba85\ud569\ub2c8\ub2e4.",
        "", "\uc571 \ubc84\uc804: 0.2.0", "", f"[\ucea1\ucc98\uac00 \ud3ec\ud568\ub41c \uc0ac\uc6a9\uc124\uba85\uc11c PDF]({PDF_NAME})", "",
        "\ubcf8\ubb38\uc740 GitHub\uc5d0\uc11c \ubc14\ub85c \uc77d\uc744 \uc218 \uc788\uc2b5\ub2c8\ub2e4. \uac01 \uc18c\uc139\uc158\uc758 PDF \ub9c1\ud06c\uc5d0\uc11c \ud654\uba74\uc744 \ud655\uc778\ud558\uace0 \ub2e8\uacc4 \ubc88\ud638 \uc21c\uc11c\ub300\ub85c \uc9c4\ud589\ud558\uc138\uc694. \uc0ac\uc9c4 \uc548\uc758 \ube68\uac04 \ubc88\ud638\ub294 \ub2e8\uacc4 \uc544\ub798 \ubc88\ud638 \ubaa9\ub85d\uacfc \ub300\uc751\ud569\ub2c8\ub2e4.",
        "", "PDF \uc624\ub978\ucabd \uc544\ub798\uc5d0\ub294 \ud604\uc7ac \uc18c\uc139\uc158 \ubc88\ud638\uc640 \uc81c\ubaa9\uc774 \ud45c\uc2dc\ub429\ub2c8\ub2e4. \ucc38\uace0\ub294 \uac01 \ub300\uc139\uc158 \ub05d\uc5d0 \ubaa8\uc558\uc73c\uba70, \uc18c\uc139\uc158 \ubc88\ud638\u00b7\ud398\uc774\uc9c0\u00b7\uc0ac\uc9c4 \ubc88\ud638 \ub9c1\ud06c\ub97c \ub204\ub974\uba74 \uad00\ub828 \ud654\uba74\uc73c\ub85c \uc774\ub3d9\ud569\ub2c8\ub2e4. \uc0ac\uc9c4 \ubc88\ud638\ub294 \ubcf8\ubb38\uc758 \ub2e8\uacc4 \ubc88\ud638\uc785\ub2c8\ub2e4.",
        "", "**\uc548\ub0b4:** \uc124\uba85\uc11c\uc758 \uc57d\uacfc \uc6a9\ub7c9\uc740 \uc870\uc791 \uc608\uc2dc\uc785\ub2c8\ub2e4. \uc2e4\uc81c \ubcf5\uc6a9\uc740 \ucc98\ubc29\uacfc \ubcf5\uc57d\uc9c0\ub3c4\uc5d0 \ub530\ub974\uc138\uc694. \uc644\ub8cc \ud45c\uc2dc\ub294 \uc0ac\uc6a9\uc790\uac00 \ub0a8\uae34 \uae30\ub85d\uc785\ub2c8\ub2e4.",
        "", "## \ucc28\ub840", "",
    ]
    for entry in plan["entries"]:
        lines.append(("  " if entry["level"] else "") + f'- [{entry["text"]}](#{entry["anchor"]})')
    current_chapter = None
    for page in plan["pages"]:
        if page["chapter"] != current_chapter:
            current_chapter = page["chapter"]
            lines.extend(["", f'<a id="{anchor(current_chapter, 0)}"></a>', "", f"## {current_chapter}", ""])
        lines.extend([f'<a id="manual_page_{page["page"]}"></a>', ""])
        if page["kind"] == "divider":
            lines.extend([f'<a id="{anchor(page["section"], 1)}"></a>', "", f'### {page["section"]}', "",
                          f'[\uc18c\uc139\uc158: PDF {page["page"]}\ucabd]({PDF_NAME}#page={page["page"]})', ""])
        elif page["kind"] == "steps":
            lines.extend([f'[\ud654\uba74 \uc608\uc2dc: PDF {page["page"]}\ucabd]({PDF_NAME}#page={page["page"]})', ""])
            for step in page["steps"]:
                lines.extend([f'#### {step["number"]}. {step["label"]}', "", step["text"], ""])
                if len(step.get("boxes", [])) > 1:
                    lines.extend(f'{callout["box_index"] + 1}. {callout["text"]}'
                                 for callout in sorted(step["callouts"], key=lambda callout: callout["box_index"]))
                    lines.append("")
        else:
            if page["continuation"] == 1:
                lines.extend(["### \ucc38\uace0", ""])
            for item in page["items"]:
                links = [f'[{part["text"]}]({PDF_NAME}#page={part["target_page"]})' for part in item["link_parts"]]
                lines.extend(["**" + " / ".join(links) + "**", "", item["text"], ""])
    result = "\n".join(lines).rstrip() + "\n"
    check_public(result, "README.md")
    return result


def public_pages(pages):
    # Exclude capture paths, XML, tokens, old notes, previews, and private assembly metadata.
    result = []
    for page in pages:
        item = {key: page[key] for key in ("kind", "chapter", "section", "page", "source_page", "wide", "redraw", "continuation")
                if key in page}
        item["steps"] = [
            {key: step[key] for key in ("identity", "number", "label", "text", "crop", "boxes", "image_kind") if key in step}
            for step in page.get("steps", [])
        ]
        for new_step, step in zip(item["steps"], page.get("steps", [])):
            new_step["callouts"] = [
                {"box_index": c["box_index"], "text": c["text"]}
                for c in sorted(step.get("callouts", []), key=lambda c: c["box_index"])
            ] if len(step.get("boxes", [])) > 1 else []
        if page["kind"] == "references":
            item["items"] = page["items"]
        result.append(item)
    check_public(json.dumps(result, ensure_ascii=False), "pages.json")
    return result


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path, default=HERE / "content.json", help="List of divider/steps pages")
    parser.add_argument("--out", type=Path, default=Path("candidate"), help="Output directory, relative to input directory")
    args = parser.parse_args(argv)
    input_path = args.input.resolve()
    out = (args.out if args.out.is_absolute() else input_path.parent / args.out).resolve()
    require(out.is_relative_to(HERE) and out != HERE,
            "Output must be a child directory of this renderer work directory")
    try:
        content = json.loads(input_path.read_text(encoding="utf-8-sig"))
        plan = make_plan(content, input_path.parent)
        md = markdown(plan)
        manifest = public_pages(plan["pages"])
        pdf, navigation, audit = render_pdf(plan)
        audit["markdown_sha256"] = sha256(md.encode("utf-8")).hexdigest()
        audit["input_sha256"] = sha256(input_path.read_bytes()).hexdigest()
        for name, data in (("layout.json", plan["layout"]), ("navigation.json", navigation), ("audit.json", audit)):
            check_public(json.dumps(data, ensure_ascii=False), name)
        out.mkdir(parents=True, exist_ok=True)
        (out / PDF_NAME).write_bytes(pdf)
        (out / "README.md").write_text(md, encoding="utf-8", newline="\n")
        for name, data in (("pages.json", manifest), ("layout.json", plan["layout"]),
                           ("navigation.json", navigation), ("audit.json", audit)):
            dump(out / name, data)
    except Exception as exc:
        details = exc.details if isinstance(exc, LayoutError) else dict(
            message="Render failed", error_type=type(exc).__name__)
        out.mkdir(parents=True, exist_ok=True)
        dump(out / "audit.json", dict(passed=False, error=details, candidate_valid=False,
                                     stale_outputs_may_exist=True))
        print(json.dumps(dict(passed=False, error=details), ensure_ascii=True), file=sys.stderr)
        return 1
    print(json.dumps(dict(passed=True, pages=plan["total_pages"], toc_rows=[len(c) for c in plan["toc_chunks"]],
                          retained_pages=len(audit["retained_pages"]), redraw_pages=len(audit["redraw_pages"]),
                          reference_items=audit["reference_items"], files=[PDF_NAME, "README.md", "pages.json",
                                                                          "layout.json", "navigation.json", "audit.json"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
