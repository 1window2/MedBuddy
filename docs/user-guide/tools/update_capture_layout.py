# File Name: update_capture_layout.py
# Role: Apply the explicitly reviewed November 16 screenshot selection and geometry.
"""Register only reviewed current screenshots; preserve unrelated layout entries."""
from collections import OrderedDict
from pathlib import Path
from typing import Any
import shutil
from PIL import Image
from rebuild_guide import ROOT, digest, dump, parse_markdown, read_json

ASSETS = 'assets/current-2026-11-16'
WORK = ROOT.parents[2] / 'work'
IMPORTS = {
    'widget-chooser': 'widget-placeholder-preview-final-20261115.png',
    'widget-sizes': 'widget-time-centered-final-20261115.png',
    'widget-caregiver': 'caregiver-background-final-20261115.png',
    'pill-candidates': 'pill-candidates-final-20261115.png',
    'pill-header': 'pill-header-aligned-final-20261115.png',
    'pill-candidate-modal': 'pill-image-heading-final-20261115.png',
}
# Rectangles are normalized to the original image, never to a re-created UI.
MAP: dict[str, tuple[Any, ...]] = {
    '2.3:2': ('prescription-review', (.04, .15, .96, .30)),
    '2.3:3': ('prescription-review', (.04, .36, .96, .77)),
    '2.3:4': ('prescription-photo-dialog', (.04, .36, .96, .72)),
    '2.3:9': ('prescription-review', (.62, .09, .96, .15)),
    '2.4:1': ('prescription-candidate-action', (.04, .16, .96, .26)),
    '2.4:2': ('prescription-review', (.04, .88, .49, .96)),
    '2.4:3': ('prescription-candidate-action', (.07, .41, .93, .47)),
    '2.4:4': ('prescription-candidate-dialog', [(.15, .38, .85, .41), (.15, .52, .85, .58)], (0, .28, 1, .72)),
    '2.4:5': ('prescription-candidate-selected', [(.15, .52, .85, .58), (.51, .61, .85, .67)], (0, .28, 1, .72)),
    '2.4:6': ('prescription-confirmed', (.04, .15, .96, .26)),
    '2.4:7': ('prescription-review', (.04, .88, .96, .96)),
    '2.5:1': ('prescription-result', (.04, .24, .96, .34)),
    '2.5:2': ('prescription-radar', (.04, .25, .96, .58)),
    '2.6:1': ('prescription-result', (.04, .13, .96, .23)),
    '2.6:2': ('prescription-result-expanded', (.04, .36, .96, .58)),
    '2.6:3': ('prescription-result', (.04, .88, .96, .96)),
    '2.6:4': ('prescription-result', (.73, .36, .83, .43)),
    '2.6:5': ('prescription-save-complete', (.06, .33, .94, .72)),
    '2.7:1': ('manual-entry', (.05, .20, .95, .55)),
    '2.7:4': ('manual-multiple', (.04, .12, .96, .51)),
    '2.7:9': ('manual-review-action', (.04, .91, .96, .99)),
    '2.7:14': ('manual-result', (.04, .88, .96, .96)),
    '2.7:15': ('manual-save-complete', (.06, .33, .94, .72)),
    '2.8:2': ('manual-as-needed', (.04, .91, .96, .99)),
    '2.9:2': ('pill-upload-placeholder', (.04, .19, .96, .43), (0, 0, 1, .55)),
    '2.9:3': ('pill-header', (.04, .20, .96, .43), (0, .045, 1, .975)),
    '2.9:4': ('pill-header', (.72, .15, .96, .19), (0, .045, 1, .975)),
    '2.9:5': ('pill-upload-notice', (.04, .095, .96, .18), (0, 0, 1, .55)),
    '2.10:1': ('pill-individual-empty', (.04, .20, .96, .41), (0, 0, 1, .55)),
    '2.10:2': ('pill-individual-paired', (.04, .20, .96, .41)),
    '2.10:3': ('pill-individual-added', (.04, .48, .96, .77)),
    '2.10:4': ('pill-individual-paired', (.04, .92, .96, .99)),
    '2.11:1': ('pill-header', (.07, .57, .93, .65), (0, .045, 1, .975)),
    '2.11:2': ('pill-partial-selected', (.08, .44, .92, .60)),
    '2.11:3': ('pill-candidates', (.08, .89, .93, .94), (0, .13, 1, .96)),
    '2.11:4': ('pill-header', (.08, .66, .92, .79), (0, .45, 1, .89)),
    '2.11:5': ('pill-header', (.07, .50, .93, .56), (0, .045, 1, .975)),
    '2.11:7': ('pill-candidate-modal', (.04, .37, .96, .66), (0, .30, 1, .72)),
    '2.12:1': ('pill-partial-selected', (.04, .93, .96, .99)),
    '2.12:2': ('pill-partial-review', (.04, .08, .96, .17)),
    '2.12:3': ('pill-partial-edit', (.16, .10, .84, .40)),
    '2.12:4': ('pill-review-edit', (.16, .46, .84, .63)),
    '2.12:5': ('pill-review-edit', (.64, .86, .81, .92)),
    '2.12:6': ('pill-photo-dialog', (.04, .26, .96, .75), (0, .20, 1, .81)),
    '2.12:7': ('pill-review', (.04, .89, .96, .96)),
    '2.12:8': ('pillPhoto-result', (.04, .88, .96, .96)),
    '2.12:9': ('pillPhoto-save-complete', (.06, .33, .94, .72)),
    '3.4:3': ('pill-candidate-modal', (.04, .37, .96, .66), (0, .30, 1, .72)),
    '5.2:3': ('patient-history', (.02, .01, .98, .13)),
    '5.2:4': ('patient-history-first', (.04, .06, .96, .13)),
    '6.1:1': ('patient-link-home', (.04, .86, .50, .99)),
    '6.1:2': ('patient-code-waiting', (.15, .34, .85, .43)),
    '6.1:4': ('patient-code-auto-success', (.10, .36, .90, .64), (0, .20, 1, .76)),
    '6.3:1': ('patient-linked-list', (.04, .20, .96, .41)),
    '6.4:2': ('patient-schedule', (.04, .16, .96, .24)),
    '6.4:3': ('patient-schedule-second', (.04, .16, .96, .24)),
    '6.4:4': ('patient-schedule', (.87, .22, .98, .27)),
    '6.4:6': ('patient-link-error', (.04, .10, .96, .18), (0, 0, 1, .38)),
    '6.9:1': ('chat-medication-request', (.16, .935, .98, .99), (0, .925, 1, 1)),
    '6.9:3': ('chat-medication-request', (.04, .74, .80, .90), (0, .65, 1, 1)),
    '6.9:4': ('chat-medication-request', (.07, .80, .76, .86), (0, .65, 1, 1)),
    '6.9:5': ('chat-medication-completed', (.07, .74, .76, .80), (0, .60, 1, 1)),
    '6.9:6': ('chat-slot-request', (.04, .62, .80, .90), (0, .50, 1, 1)),
    '6.9:7': ('chat-slot-completed', (.07, .74, .76, .80), (0, .48, 1, 1)),
    '7.11:2': ('widget-chooser', (.04, .40, .96, .55), (0, .28, 1, .96)),
    '7.11:3': ('widget-chooser', (.04, .57, .96, .95), (0, .28, 1, .96)),
    '7.11:4': ('widget-sizes', [( .05, .19, .95, .52), (.05, .53, .95, .64)], (0, .17, 1, .65)),
    '7.11:5': ('widget-sizes', (.05, .19, .95, .52), (0, .17, 1, .65)),
    '7.11:6': ('widget-sizes', (.08, .45, .92, .51), (0, .17, 1, .65)),
    '7.11:8': ('widget-sizes', [(.08, .43, .92, .45), (.60, .56, .93, .62)], (0, .17, 1, .65)),
    '7.12:1': ('widget-caregiver', (.12, .20, .78, .26), (0, .17, 1, .54)),
    '7.12:2': ('widget-caregiver', (.08, .38, .18, .41), (0, .17, 1, .54)),
    '7.12:3': ('widget-caregiver', (.27, .38, .73, .41), (0, .17, 1, .54)),
    '7.12:4': ('widget-caregiver', (.08, .45, .92, .51), (0, .17, 1, .54)),
    '10.2:1': ('analysis-failure', (.08, .13, .92, .54)),
    '10.3:1': ('pill-partial-unselected', (.06, .71, .94, .92)),
    '10.3:2': ('pill-header', [(.07, .50, .52, .56), (.72, .15, .96, .19)], (0, .045, 1, .975)),
    '10.5:1': ('widget-caregiver', (.81, .20, .92, .25), (0, .17, 1, .54)),
}


LEGACY_CROPS = {
    '2.3:5': [145, 80, 935, 2165],
    '2.3:6': [145, 80, 935, 2165],
    '2.3:8': [145, 80, 935, 2165],
    '2.11:6': [0, 1730, 1080, 2250],
    '7.11:7': [50, 560, 1030, 1115],
    '7.11:9': [50, 500, 1030, 1135],
}
LEGACY_BOXES = {
    '7.11:7': [[90, 665, 990, 770], [90, 900, 990, 945]],
    '7.11:9': [[90, 592, 990, 705], [90, 915, 990, 963]],
}


# Function Name: apply
# Description: Import selected captures and update matching steps, hashes and provenance.
# Parameters: None; all selection and geometry are explicit constants above.
# Returns: None; invalid step counts, files or geometry raise exceptions.
def apply() -> None:
    """Apply the reviewed mapping, leaving all non-selected existing assets intact."""
    target = ROOT / ASSETS
    target.mkdir(exist_ok=True)
    for name, original in IMPORTS.items():
        shutil.copyfile(WORK / original, target / f'{name}.png')
    groups = parse_markdown((ROOT / 'README.md').read_text(encoding='utf-8-sig'))
    old: OrderedDict[str, list[dict[str, Any]]] = OrderedDict()
    for page in read_json(ROOT / 'source/layout.json'):
        old.setdefault(page['section'].split()[0], []).extend(page.get('steps', []))
    result = []
    used: dict[str, list[str]] = {}
    for section, group in groups.items():
        steps = old[section]
        while len(steps) < len(group['steps']):
            number = len(steps) + 1
            steps.append(dict(identity=f'UG-20261116-{section}:{number}', number=number, callouts=[]))
        assert len(steps) == len(group['steps']), section
        for step, copy in zip(steps, group['steps'], strict=True):
            key = f"{section}:{step['number']}"
            if key in LEGACY_CROPS:
                step['crop'] = LEGACY_CROPS[key]
            if key in LEGACY_BOXES:
                step['boxes'] = LEGACY_BOXES[key]
            if key not in MAP:
                continue
            name, boxes, *crop = MAP[key]
            path = target / f'{name}.png'
            with Image.open(path) as image:
                width, height = image.size
            if isinstance(boxes, tuple):
                boxes = [boxes]
            assert all(0 <= v <= 1 for box in boxes for v in box), key
            step['image'] = f'{ASSETS}/{name}.png'
            step['crop'] = [round(v * (width if i % 2 == 0 else height))
                            for i, v in enumerate(crop[0] if crop else (0, 0, 1, 1))]
            step['boxes'] = [[round(v * (width if i % 2 == 0 else height)) for i, v in enumerate(box)]
                             for box in boxes]
            step['callouts'] = copy['callouts']
            assert not copy['callouts'] or len(copy['callouts']) == len(boxes), key
            used.setdefault(name, []).append(key)
        result.extend([
            dict(kind='divider', chapter=group['chapter'], section=group['section'], steps=[]),
            dict(kind='steps', chapter=group['chapter'], section=group['section'], steps=steps),
        ])
    dump(ROOT / 'source/layout.json', result)
    hashes = read_json(ROOT / 'source/assets.sha256.json')
    provenance = []
    for name, steps in used.items():
        path = target / f'{name}.png'
        relative = path.relative_to(ROOT).as_posix()
        hashes[relative] = digest(path)
        provenance.append(dict(
            image=relative, sha256=hashes[relative], steps=steps,
            kind='supplied_android_capture' if name in IMPORTS else 'isolated_product_widget_fixture',
            origin=f'work/{IMPORTS[name]}' if name in IMPORTS else 'tools/captures',
            synthetic_data=True,
            notes=('Previously supplied November 15 capture; current native layouts confirmed unchanged by parent. '
                   'Chooser date/time are intentional native preview placeholders, not missing data.'
                   if name.startswith('widget-') else
                   'Example data only; not evidence of real AI identification, account linking, chat delivery or server save.'),
        ))
    dump(ROOT / 'source/assets.sha256.json', hashes)
    dump(ROOT / 'source/current-captures.json', dict(
        date='2026-11-16', version='v1.0.1 development branch', baseline='bbbdef53',
        fixture_viewport='412x915 logical, 2x PNG; manual helper 412x900',
        font_override='Noto Sans KR in isolated .build/capture-app source snapshot only; production source unchanged.',
        sources=provenance,
    ))
    # Exclude unused trials from the maintained assets, but retain local review evidence.
    unused = ROOT / '.build/capture-unused'
    unused.mkdir(exist_ok=True)
    for path in target.glob('*.png'):
        if path.stem not in used:
            assert path.resolve().is_relative_to(target.resolve())
            destination = unused / path.name
            assert destination.resolve().is_relative_to((ROOT / '.build').resolve())
            shutil.move(str(path), str(destination))
    print(f'{len(used)} selected images; {len(MAP)} updated screenshot steps')


if __name__ == '__main__':
    apply()
