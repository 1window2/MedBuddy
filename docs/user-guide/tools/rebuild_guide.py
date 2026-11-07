# 파일명: rebuild_guide.py
# 역할: 저장소 원문·캡처로 설명서를 재생성하고 검토가 끝난 산출물만 배포 위치에 반영한다.
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
PDF = "MedBuddy_User_Guide_ko_portrait.pdf"
SOURCE = ROOT / "source"


# 함수이름: read_json
# 함수역할: 이전 BOM 파일을 포함한 UTF-8 JSON을 읽는다.
# 매개변수: path(Path)는 입력 파일이다.
# 반환값: 역직렬화한 object. 파일 접근·JSON 오류는 호출자에게 전달한다.
def read_json(path):
    """Read the reviewed UTF-8 layout data, including legacy BOM files."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


# 함수이름: dump
# 함수역할: 생성 데이터와 검증 기록을 UTF-8 JSON으로 저장한다.
# 매개변수: path(Path)는 출력 파일, value(object)는 직렬화 가능한 값이다.
# 반환값: None. 쓰기·직렬화 오류는 호출자에게 전달한다.
def dump(path, value):
    """Write generated authoring or verification data inside the guide directory."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


# 함수이름: digest
# 함수역할: 검토 입력과 출력이 바뀌지 않았는지 대조할 파일 해시를 계산한다.
# 매개변수: path(Path)는 검사할 파일이다.
# 반환값: SHA-256의 16진수 str. 파일 접근 오류는 호출자에게 전달한다.
def digest(path):
    """Identify the exact input or output used for this build."""
    return sha256(path.read_bytes()).hexdigest()


# 함수이름: parse_markdown
# 함수역할: 원문의 소절·단계·강조 설명·참고를 읽어 작성 순서대로 묶는다.
# 매개변수: text(str)는 설명서 Markdown 원문이다.
# 반환값: 소절별 OrderedDict. 소절 수나 필수 형식이 맞지 않으면 AssertionError.
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


# 함수이름: engine
# 함수역할: 저장소의 배치 모듈을 불러와 빌드 경로·글꼴·출력 이름을 설정한다.
# 매개변수: font_dir(Path)는 승인된 글꼴 디렉터리다.
# 반환값: 설정된 guide_layout 모듈. 모듈 로딩 오류는 호출자에게 전달한다.
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


# 함수이름: collect_content
# 함수역할: 최신 문장을 기존 캡처 좌표에 결합하고 배치 가능 여부에 따라 페이지를 나눈다.
# 매개변수: groups(OrderedDict)는 소절별 문장, layout(module)은 설정된 배치 엔진이다.
# 반환값: 페이지 list[dict]. 원본 해시·단계가 달라지거나 배치가 불가능하면 예외를 발생시킨다.
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
            step["callouts"] = item["callouts"]
            step["section"] = group["section"]
            step["action"] = step["text"]
            step["alt"] = step["label"] + ": " + step["text"]
            steps.append(step)
        output.append(dict(kind="divider", chapter=group["chapter"], section=group["section"], steps=[]))
        # Place captions below photos; use two steps only when four do not fit.
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


# 함수이름: build
# 함수역할: 표지·본문·탐색 정보를 재생성하고 Markdown 왕복 변환과 단계 누락을 검증한다.
# 매개변수: font_dir(Path)는 승인된 글꼴 디렉터리다.
# 반환값: None. 산출물은 .build에 저장하며 검증·입출력 실패는 호출자에게 전달한다.
def build(font_dir):
    """Create a candidate full PDF plus synchronized Markdown and structural checks."""
    BUILD.mkdir(exist_ok=True)
    source = (ROOT / "README.md").read_text(encoding="utf-8-sig")
    (BUILD / "input-README.md").write_text(source, encoding="utf-8", newline="\n")
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
    cover.drawCentredString(layout.W / 2, layout.H / 2 - 172, "ver 1.0.0")
    layout.draw_footer(cover, layout.footer_layout(1, plan["total_pages"], ""))
    cover.showPage()
    cover.save()
    (BUILD / "cover.pdf").write_bytes(cover_data.getvalue())
    pdf, navigation, audit = layout.render_pdf(plan, source=BUILD / "cover.pdf")
    (BUILD / PDF).write_bytes(pdf)
    generated = layout.markdown(plan)
    preamble = source.split("## 차례", 1)[0]
    result = preamble + "## 차례" + generated.split("## 차례", 1)[1]
    (BUILD / "README.md").write_text(result, encoding="utf-8", newline="\n")
    rebuilt = parse_markdown(result)
    for key, group in groups.items():
        for before, after in zip(group["steps"], rebuilt[key]["steps"], strict=True):
            for field in ("number", "label", "text", "callouts", "source_note"):
                assert before[field] == after[field], (key, before["number"], field)
    reader = PdfReader(BytesIO(pdf))
    all_text = "\n".join(page.extract_text() or "" for page in reader.pages)
    compact = re.sub(r"\s+", "", all_text)
    for page in content:
        for step in page.get("steps", []):
            texts = [step["label"], step["text"], step.get("source_note", "")]
            if len(step.get("boxes", [])) > 1:
                texts.extend(item["text"] for item in step["callouts"])
            for value in texts:
                assert re.sub(r"\s+", "", value) in compact, step["identity"]
    assets = {s["image"]: digest(ROOT / s["image"]) for p in content for s in p.get("steps", [])}
    audit.update(pages=len(reader.pages), subsections=len(groups), steps=sum(len(g["steps"]) for g in groups.values()),
                 pdf_sha256=digest(BUILD / PDF), markdown_sha256=digest(BUILD / "README.md"),
                 all_step_text_verified=True, all_source_note_text_verified=True,
                 baseline_step_ids_preserved=True, visual_qa="pending",
                 source_layout_sha256=digest(SOURCE / "layout.json"),
                 fonts={name: digest(font_dir / name) for name in ("NanumBarunGothic.ttf", "NanumBarunGothicBold.ttf")},
                 included_sections=list(groups))
    dump(BUILD / "audit.json", audit)
    dump(BUILD / "navigation.json", navigation)
    dump(BUILD / "pages.json", layout.public_pages(plan["pages"]))
    dump(BUILD / "layout.json", plan["layout"])
    dump(BUILD / "assets.json", assets)
    print(json.dumps({key: audit[key] for key in ("pages", "steps", "subsections", "verified_internal_links", "verified_bookmarks", "pdf_sha256", "visual_qa")}, ensure_ascii=False))


# 함수이름: render
# 함수역할: 빌드한 PDF의 모든 쪽을 이미지와 모아보기 이미지로 렌더링한다.
# 매개변수: poppler(Path)는 PDF 이미지 변환 프로그램의 디렉터리다.
# 반환값: None. 결과는 검토 폴더에 저장하며 외부 프로그램 실패는 예외로 전달한다.
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


# 함수이름: publish
# 함수역할: 시각 검토 완료와 입력·출력 해시를 확인한 뒤 PDF와 README를 반영한다.
# 매개변수: 없음. .build의 검토 기록과 원본 파일을 사용한다.
# 반환값: None. 검토 누락이나 검토 후 변경이 있으면 AssertionError로 반영을 막는다.
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
    parser.add_argument("--poppler", type=Path, default=Path("pdftoppm"))
    args = parser.parse_args()
    if args.command == "build":
        if args.font_dir is None:
            parser.error("build requires --font-dir")
        build(args.font_dir.resolve())
    elif args.command == "render":
        render(args.poppler)
    else:
        publish()
