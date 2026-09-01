"""Validate that Android release metadata and documentation agree."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _read(relative_path: str) -> str:
    return ROOT.joinpath(relative_path).read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    pubspec = _read("frontend/pubspec.yaml")
    version_match = re.search(
        r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
        pubspec,
        flags=re.MULTILINE,
    )
    if version_match is None:
        errors.append(
            "frontend/pubspec.yaml must declare version MAJOR.MINOR.PATCH+BUILD."
        )
    else:
        semantic_version, build_number = version_match.groups()
        release_tag = f"v{semantic_version}-beta"
        release_notes_path = f"docs/releases/{release_tag}.md"

        if int(build_number) < 1:
            errors.append("The Android build number must be positive.")
        if f"Current app version: **{semantic_version}+{build_number}**." not in _read(
            "frontend/README.md"
        ):
            errors.append("frontend/README.md does not match pubspec.yaml.")
        if f"Target release tag: `{release_tag}`" not in _read(
            "docs/MedBuddy - Beta Scope.md"
        ):
            errors.append("The beta scope target does not match pubspec.yaml.")
        if f"`{release_tag}` source" not in _read("SECURITY.md"):
            errors.append("SECURITY.md does not list the candidate release.")
        if not ROOT.joinpath(release_notes_path).is_file():
            errors.append(f"Missing release notes: {release_notes_path}")

    release_workflow = _read(".github/workflows/release-android.yml")
    required_release_controls = {
        "main-only signed release": "github.ref == 'refs/heads/main'",
        "mandatory release signing": "MEDBUDDY_REQUIRE_RELEASE_SIGNING: 'true'",
        "APK build": "flutter build apk --release --no-pub",
        "app bundle build": "flutter build appbundle --release --no-pub",
    }
    for label, expected_text in required_release_controls.items():
        if expected_text not in release_workflow:
            errors.append(f"Missing release workflow control: {label}.")

    if errors:
        print("Release metadata validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Release metadata and signing workflow controls are consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
