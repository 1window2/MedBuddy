# File Name: check_release_metadata.py
# Role: Rejects inconsistent release versions or missing Android signing safeguards.

"""Validate that Android release metadata and documentation agree."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


# Function Name: _read
# Description: Reads a repository document without depending on the caller's working directory.
# Parameters: relative_path - path relative to the repository root.
# Returns: The file's UTF-8 text; file access failures propagate to the caller.
def _read(relative_path: str) -> str:
    return ROOT.joinpath(relative_path).read_text(encoding="utf-8")


# 함수이름: main
# 함수역할: 앱 버전·문서·API 계약의 일치를 확인하고 서명·ABI별 APK·앱 번들·공개 접속·App Check 검사 항목이 워크플로에 있는지 검사한다.
# 매개변수: 없음. 저장소 루트 기준 버전·문서·워크플로 파일을 읽는다.
# 반환값: 일치하면 종료 코드 0, 발견된 불일치를 stderr에 모두 출력하면 1. 파일 읽기 오류는 전달하며 실제 빌드는 실행하지 않는다.
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
        # 0.x lines are betas (vX.Y.Z-beta); from 1.0.0 on the tag is the plain version.
        is_beta_line = semantic_version.startswith("0.")
        release_tag = f"v{semantic_version}-beta" if is_beta_line else f"v{semantic_version}"
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

    # The app refuses a server with another contract, so a build whose default differs from the
    # backend's file could not talk to the backend released from the same commit.
    client_contract = re.search(
        r"'MEDBUDDY_API_CONTRACT_VERSION',\s*defaultValue:\s*'([^']+)'",
        _read("frontend/lib/services/api_config.dart"),
    )
    if (
        client_contract is None
        or client_contract.group(1) != _read("backend/API_CONTRACT_VERSION").strip()
    ):
        errors.append(
            "The app's default API contract does not match backend/API_CONTRACT_VERSION."
        )

    release_workflow = _read(".github/workflows/release-android.yml")
    required_release_controls = {
        "exact-ref signed release": "github.ref == 'refs/heads/main'",
        "mandatory release signing": "MEDBUDDY_REQUIRE_RELEASE_SIGNING: 'true'",
        "APK build": "flutter build apk --release --no-pub",
        "app bundle build": "flutter build appbundle --release --no-pub",
        "direct APK pair": "for ABI in armeabi-v7a arm64-v8a; do",
        "32-bit APK target": "armeabi-v7a) TARGET=android-arm ;;",
        "64-bit APK target": "arm64-v8a) TARGET=android-arm64 ;;",
        "single-ABI APK build": '--target-platform "${TARGET}"',
        "public feature ingress": "python3 ../scripts/check_release_ingress.py",
        "live App Check preflight": "python3 ../scripts/check_release_app_check.py",
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
