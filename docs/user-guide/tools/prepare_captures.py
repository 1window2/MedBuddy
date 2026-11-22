# File Name: prepare_captures.py
# Role: Prepare an isolated product-widget snapshot without changing production.
"""Create an isolated, read-only-production Flutter capture snapshot.

Run with --prepare, then run Flutter test in .build/capture-app with --no-pub.
No emulator, account, production build directory or real transport is used.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT.parents[1] / 'frontend'
TARGET = ROOT / '.build/capture-app'


# Function Name: prepare
# Description: Copy product sources, inject test fonts, and assemble fixture tests.
# Parameters: None; paths are resolved relative to this guide.
# Returns: None; missing inputs and unsupported font overrides raise errors.
def prepare() -> None:
    """Prepare reproducible captures in .build; never edit frontend sources."""
    TARGET.mkdir(parents=True, exist_ok=True)
    for name in ('lib', 'assets', 'test'):
        shutil.copytree(FRONTEND / name, TARGET / name, dirs_exist_ok=True)
    # Test-only font injection: explicit product TextStyles otherwise use Ahem.
    for path in (TARGET / 'lib').rglob('*.dart'):
        text = path.read_text(encoding='utf-8')
        assert 'fontFamily:' not in text, path
        path.write_text(re.sub(r'\bTextStyle\(', "TextStyle(fontFamily: 'Noto Sans KR',", text), encoding='utf-8')
    for name in ('pubspec.yaml', 'pubspec.lock'):
        shutil.copyfile(FRONTEND / name, TARGET / name)
    (TARGET / '.dart_tool').mkdir(exist_ok=True)
    for name in ('package_config.json', 'package_graph.json'):
        shutil.copyfile(FRONTEND / '.dart_tool' / name, TARGET / '.dart_tool' / name)
    captures = ROOT / 'tools/captures'
    shutil.copyfile(captures / 'capture_support.dart', TARGET / 'test/capture_support.dart')
    shutil.copyfile(captures / 'registration.dart', TARGET / 'test/guide_registration_capture_test.dart')
    sources = {
        'pill': 'pill_identification_ui_boundary_test.dart',
        'patient': 'home_patient_destinations_test.dart',
        'link': 'patient_link_code_polling_test.dart',
        'manual': 'manual_medication_review_handoff_test.dart',
        'chat': 'linked_chat_ui_boundary_test.dart',
    }
    for key, source in sources.items():
        prefix = (FRONTEND / 'test' / source).read_text(encoding='utf-8').split('void main() {', 1)[0]
        prefix = prefix.replace('MedBuddyTheme.light()', 'captureTheme()')
        prefix = prefix.replace('MaterialApp(', 'MaterialApp(debugShowCheckedModeBanner: false,')
        if key == 'patient':
            prefix = prefix.replace("'$patientHash schedule'", "'예시 정기약'").replace("'$patient history'", "'예시 복용약'")
            prefix = prefix.replace('isEnglish: true,', 'isEnglish: false,')
        if key == 'pill':
            prefix = "import 'dart:io';\n" + prefix
            prefix = prefix.replace('MaterialApp(', 'MaterialApp(theme: captureTheme(),')
        if key == 'manual':
            prefix = prefix.replace('MaterialApp(', 'MaterialApp(theme: captureTheme(),')
        if key == 'chat':
            prefix = prefix.replace('MaterialApp(', 'MaterialApp(theme: captureTheme(),')
        prefix = "import 'capture_support.dart';\n" + prefix
        snippet = (captures / f'{key}.dart').read_text(encoding='utf-8')
        (TARGET / 'test' / f'guide_{key}_capture_test.dart').write_text(prefix + snippet, encoding='utf-8')
    manifest = {
        str(path.relative_to(FRONTEND)).replace('\\', '/'): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((FRONTEND / 'lib').rglob('*.dart'))
    }
    (ROOT / '.build/capture-source-hashes.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(TARGET)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true', required=True)
    parser.parse_args()
    prepare()
