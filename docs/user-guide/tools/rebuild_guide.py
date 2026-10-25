"""Rebuild the full illustrated guide from README and repository-local source assets."""
from collections import OrderedDict
from copy import deepcopy
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw
from pypdf import PdfReader
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
PDF = "MedBuddy_User_Guide_ko.pdf"
SOURCE = ROOT / "source"


def read_json(path):
    """Read the reviewed UTF-8 layout data, including legacy BOM files."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dump(path, value):
    """Write generated authoring or verification data inside the guide directory."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def digest(path):
    """Identify the exact input or output used for this build."""
    return sha256(path.read_bytes()).hexdigest()


def pixel_digest(image):
    """Identify decoded screenshot pixels independently of their PNG/PDF compression."""
    rgb = image.convert("RGB")
    return sha256(f"{rgb.width}x{rgb.height}:RGB:".encode() + rgb.tobytes()).hexdigest()


def extract_pdf_images(pdf):
    """Reuse approved screenshots embedded in the shipped PDF, not another raw asset archive."""
    expected = read_json(SOURCE / "pdf-images.json")
    folder = BUILD / "pdf-images"
    folder.mkdir(exist_ok=True)
    missing = set(expected)
    for key in expected:
        path = folder / f"{key}.png"
        if path.exists():
            with Image.open(path) as image:
                if pixel_digest(image) == key:
                    missing.remove(key)
    if missing:
        reader = PdfReader(pdf)
        seen = set()
        for page in reader.pages:
            for name, ref in page.get("/Resources", {}).get("/XObject", {}).items():
                if ref.get_object().get("/Subtype") != "/Image" or ref.idnum in seen:
                    continue
                seen.add(ref.idnum)
                image = page.images[name].image.convert("RGB")
                key = pixel_digest(image)
                if key in missing:
                    assert image.size == (expected[key]["width"], expected[key]["height"])
                    image.save(folder / f"{key}.png")
                    missing.remove(key)
            if not missing:
                break
    assert not missing, f"The source PDF is missing {len(missing)} reviewed screenshots."


def parse_markdown(text):
    """Parse this manual's explicit headings, numbered steps and linked reference notes."""
    sections = OrderedDict()
    notes = []
    current = step = note = None
    chapter = ""
    for line in text.splitlines():
        match = re.match(r"^## (\d+ .+)$", line)
        if match:
            chapter = match[1]
            step = note = None
        match = re.match(r"^### (\d+\.\d+ .+)$", line)
        if match:
            current = dict(chapter=chapter, section=match[1], steps=[])
            sections[match[1].split()[0]] = current
            step = note = None
            continue
        match = re.match(r"^#### (\d+)\. (.+)$", line)
        if match:
            step = dict(number=int(match[1]), label=match[2], lines=[], callouts=[])
            current["steps"].append(step)
            note = None
            continue
        if line == "### 참고":
            step = note = None
            continue
        if line.startswith("**["):
            note = dict(targets=[], lines=[])
            for section, numbers in re.findall(
                r"(\d+\.\d+) - \d+페이지 - ([\d, ~]+)번 사진", line
            ):
                for part in numbers.split(","):
                    bounds = [int(value) for value in part.strip().split("~")]
                    note["targets"].extend((section, n) for n in range(bounds[0], bounds[-1] + 1))
            assert note["targets"], line
            notes.append(note)
            step = None
            continue
        if line.startswith(("<a ", "<img ", "[소섹션:", "[화면 예시:")):
            continue
        if note is not None:
            note["lines"].append(line)
        elif step is not None:
            match = re.match(r"^(\d+)\. (.+)$", line)
            if match:
                step["callouts"].append(dict(box_index=int(match[1]) - 1, text=match[2]))
            else:
                step["lines"].append(line)
    for group in sections.values():
        for item in group["steps"]:
            item["text"] = "\n".join(item.pop("lines")).strip()
            item["source_note"] = ""
    for item in notes:
        body = "\n".join(item["lines"]).strip()
        for section, number in item["targets"]:
            target = sections[section]["steps"][number - 1]
            assert target["number"] == number
            target["source_note"] = (target["source_note"] + "\n\n" + body).strip()
    assert len(sections) == 84
    return sections


def engine(font_dir):
    """Load the checked-in typesetter and explicitly supplied portable font directory."""
    path = ROOT / "tools/guide_layout.py"
    spec = importlib.util.spec_from_file_location("guide_layout", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.HERE = BUILD
    module.PDF_NAME = PDF
    module.FONT_DIR = font_dir
    return module


def collect_content(groups, layout):
    """Join authoritative Markdown copy with reviewed, repository-relative image geometry."""
    old = OrderedDict()
    for page in read_json(SOURCE / "layout.json"):
        key = page["section"].split()[0]
        old.setdefault(key, []).extend(page.get("steps", []))
    assert list(old) == list(groups)
    for name, expected in read_json(SOURCE / "assets.sha256.json").items():
        path = (ROOT / name).resolve()
        assert path.is_relative_to(ROOT) and digest(path) == expected, name
    output = []
    for section, group in groups.items():
        steps = []
        for item, previous in zip(group["steps"], old[section], strict=True):
            assert item["number"] == previous["number"], section
            step = deepcopy(previous)
            step.update(item)
            step["callouts"] = previous["callouts"]
            step["section"] = group["section"]
            step["action"] = step["text"]
            step["alt"] = step["label"] + ": " + step["text"]
            steps.append(step)
        output.append(dict(kind="divider", chapter=group["chapter"], section=group["section"], steps=[]))
        # Use the original four-slot layout unless a longer explanation needs two wide slots.
        for start in range(0, len(steps), 4):
            batch = steps[start:start + 4]
            page = dict(kind="steps", chapter=group["chapter"], section=group["section"], steps=batch, redraw=True, wide=False, page=0)
            try:
                layout.layout_steps(page, ROOT)
                output.append(page)
            except layout.LayoutError:
                for offset in range(0, len(batch), 2):
                    wide = dict(page, steps=batch[offset:offset + 2], wide=True)
                    layout.layout_steps(wide, ROOT)
                    output.append(wide)
    baseline_ids = {s["identity"] for steps in old.values() for s in steps}
    current_ids = {s["identity"] for page in output for s in page.get("steps", [])}
    assert baseline_ids.issubset(current_ids)
    return output


def build(font_dir, image_source):
    """Create a candidate full PDF plus synchronized Markdown and structural checks."""
    BUILD.mkdir(exist_ok=True)
    source = (ROOT / "README.md").read_text(encoding="utf-8-sig")
    (BUILD / "input-README.md").write_text(source, encoding="utf-8", newline="\n")
    extract_pdf_images(image_source)
    groups = parse_markdown(source)
    layout = engine(font_dir)
    layout.register_fonts()
    content = collect_content(groups, layout)
    dump(BUILD / "content.json", content)
    plan = layout.make_plan(content, ROOT)
    cover_data = BytesIO()
    cover = canvas.Canvas(cover_data, pagesize=(layout.W, layout.H), invariant=1)
    side = 100 * layout.MM
    cover.drawImage(ImageReader(str(ROOT / "assets/medbuddy_logo.png")), (layout.W - side) / 2,
                    layout.H / 2 - 85, width=side, height=side, preserveAspectRatio=True, mask="auto")
    cover.setFont(layout.BOLD, 30)
    cover.drawCentredString(layout.W / 2, layout.H / 2 - 145, "MedBuddy 사용설명서")
    cover.setFont(layout.REG, 12)
    cover.drawCentredString(layout.W / 2, layout.H / 2 - 172, "0.2.4 개발 브랜치 | 2026-10-25")
    layout.draw_footer(cover, layout.footer_layout(1, plan["total_pages"], ""))
    cover.showPage()
    cover.save()
    (BUILD / "cover.pdf").write_bytes(cover_data.getvalue())
    pdf, navigation, audit = layout.render_pdf(plan, source=BUILD / "cover.pdf")
    (BUILD / PDF).write_bytes(pdf)
    generated = layout.markdown(plan)
    preamble = source.split("## 차례", 1)[0]
    result = preamble + "## 차례" + generated.split("## 차례", 1)[1]
    anchor = '### 9.12 휴대폰 알림 확인과 테스트하기\n'
    result = result.replace(anchor, anchor + '\n<img src="assets/notification_settings_2026-10-22.png" width="340" alt="복약 및 알림 안의 휴대폰 알림 권한과 테스트 버튼">\n\n휴대폰 권한과 앱의 알림 수신 설정을 한 화면에서 확인하는 현재 설정 화면입니다.\n', 1)
    (BUILD / "README.md").write_text(result, encoding="utf-8", newline="\n")
    rebuilt = parse_markdown(result)
    for key, group in groups.items():
        for before, after in zip(group["steps"], rebuilt[key]["steps"], strict=True):
            assert before["text"] == after["text"], (key, before["number"])
    reader = PdfReader(BytesIO(pdf))
    all_text = "\n".join(page.extract_text() or "" for page in reader.pages)
    compact = re.sub(r"\s+", "", all_text)
    for page in content:
        for step in page.get("steps", []):
            assert re.sub(r"\s+", "", step["text"]) in compact, step["identity"]
    assets = {s["image"]: digest(ROOT / s["image"]) for p in content for s in p.get("steps", [])}
    audit.update(pages=len(reader.pages), subsections=len(groups), steps=sum(len(g["steps"]) for g in groups.values()),
                 pdf_sha256=digest(BUILD / PDF), markdown_sha256=digest(BUILD / "README.md"),
                 all_step_text_verified=True, baseline_step_ids_preserved=True, visual_qa="pending",
                 source_layout_sha256=digest(SOURCE / "layout.json"),
                 fonts={name: digest(font_dir / name) for name in ("NanumBarunGothic.ttf", "NanumBarunGothicBold.ttf")},
                 updated_sections=[key for key in groups if key in {"1.6", "1.7", "3.3", "3.9", "3.10", "6.3", "9.1", "9.4"}])
    dump(BUILD / "audit.json", audit)
    dump(BUILD / "navigation.json", navigation)
    dump(BUILD / "pages.json", layout.public_pages(plan["pages"]))
    dump(BUILD / "layout.json", plan["layout"])
    dump(BUILD / "assets.json", assets)
    print(json.dumps({key: audit[key] for key in ("pages", "steps", "subsections", "verified_internal_links", "verified_bookmarks", "pdf_sha256", "visual_qa")}, ensure_ascii=False))


def render(poppler):
    """Render all pages and build numbered contact sheets for visual inspection."""
    review = BUILD / "review"
    review.mkdir(exist_ok=True)
    subprocess.run([str(poppler), "-r", "60", "-png", str(BUILD / PDF), str(review / "page")], check=True)
    pages = sorted(review.glob("page-*.png"))
    for start in range(0, len(pages), 16):
        sheet = Image.new("RGB", (1600, 2320), "#d9dce0")
        pen = ImageDraw.Draw(sheet)
        for i, path in enumerate(pages[start:start + 16]):
            with Image.open(path) as im:
                im.thumbnail((390, 550))
                x, y = (i % 4) * 400, (i // 4) * 580
                sheet.paste(im, (x + (400 - im.width) // 2, y + 24))
                pen.text((x + 12, y + 6), path.stem, fill="black")
        sheet.save(review / f"sheet-{start // 16 + 1:02}.png")
    print(json.dumps(dict(rendered_pages=len(pages), contact_sheets=(len(pages) + 15) // 16)))


def publish():
    """Publish reviewed candidates without staging or committing any repository file."""
    audit = read_json(BUILD / "audit.json")
    assert audit["visual_qa"] == "reviewed", "Record visual review before publishing."
    assert digest(BUILD / PDF) == audit["pdf_sha256"]
    assert digest(BUILD / "README.md") == audit["markdown_sha256"]
    assert (ROOT / "README.md").read_text(encoding="utf-8-sig") == (BUILD / "input-README.md").read_text(encoding="utf-8-sig"), "README changed during review; rebuild first."
    for name in (PDF, "README.md"):
        shutil.copyfile(BUILD / name, ROOT / name)
    print(json.dumps(dict(published=[PDF, "README.md"], pages=audit["pages"])))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "render", "publish"])
    parser.add_argument("--font-dir", type=Path, help="Directory containing NanumBarunGothic.ttf and NanumBarunGothicBold.ttf")
    parser.add_argument("--image-source", type=Path, default=ROOT / PDF, help="Existing published guide containing the reviewed screenshots")
    parser.add_argument("--poppler", type=Path, default=Path("pdftoppm"))
    args = parser.parse_args()
    if args.command == "build":
        if args.font_dir is None:
            parser.error("build requires --font-dir")
        build(args.font_dir.resolve(), args.image_source.resolve())
    elif args.command == "render":
        render(args.poppler)
    else:
        publish()
