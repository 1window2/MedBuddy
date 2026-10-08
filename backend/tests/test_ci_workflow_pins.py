# File Name: test_ci_workflow_pins.py
# Role: Pin the structure of the CI and signing workflows that the exact-commit release gate relies on.

import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github/workflows"
SPEC = importlib.util.spec_from_file_location("release_ci_gate_pins", ROOT / "scripts/check_release_ci.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
LIVE = (*gate.REQUIRED_WORKFLOWS, "release-android.yml")
REF_CONDITION = (
    "    if: >-\n      github.ref == 'refs/heads/main' ||\n"
    "      github.ref == 'refs/heads/beta/v0.2.1'\n"
)
APK_ABI_CHECK = '"${APK_NATIVE_ABIS}" != "arm64-v8a,armeabi-v7a" || "${APK_ENGINE_ABIS}" != "${APK_NATIVE_ABIS}"'


# Function Name: _workflow
# Description: Read one workflow file as text so the pins see comments, indentation and expressions.
# Parameters: name: File name under .github/workflows.
# Returns: The workflow's UTF-8 text.
def _workflow(name: str) -> str:
    return (WORKFLOWS / name).read_text(encoding="utf-8")


# Function Name: test_live_workflows_do_not_suppress_step_or_job_failures
# Description: A failing step must fail its job in both CI workflows and in the signing workflow.
# Parameters: None.
# Returns: None; fails if any failure-suppressing marker appears.
def test_live_workflows_do_not_suppress_step_or_job_failures() -> None:
    for name in LIVE:
        workflow = _workflow(name)
        for marker in ("continue-on-error", "|| true", "always()", "!cancelled()", "failure()"):
            assert marker not in workflow, f"{name}: {marker}"


# Function Name: test_release_gate_workflows_run_every_job_for_pushes
# Description: The gate reads push runs, so both CI workflows keep the push trigger and no job is conditional.
# Parameters: None.
# Returns: None; fails if the push trigger changes or a job-level condition is added.
def test_release_gate_workflows_run_every_job_for_pushes() -> None:
    for name in gate.REQUIRED_WORKFLOWS:
        workflow = _workflow(name)
        assert '  push:\n    branches: [ "main", "beta/**" ]\n' in workflow, name
        assert re.findall(r"^    if:.*$", workflow, flags=re.MULTILINE) == [], name


# Function Name: test_release_gate_workflows_never_cancel_or_queue_push_runs
# Description: Push runs get one concurrency group per commit; only superseded pull-request runs are cancelled.
# Parameters: None.
# Returns: None; fails if a push run could be cancelled or made to wait behind another commit.
def test_release_gate_workflows_never_cancel_or_queue_push_runs() -> None:
    for name in gate.REQUIRED_WORKFLOWS:
        workflow = _workflow(name)
        assert (
            "concurrency:\n"
            "  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}\n"
            "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n"
        ) in workflow, name
        assert workflow.count("cancel-in-progress") == 1, name
    assert "concurrency:" not in _workflow("release-android.yml")


# Function Name: test_signing_jobs_keep_the_exact_ref_condition
# Description: Both signing jobs stay limited to main and the single named beta branch, behind the CI gate.
# Parameters: None.
# Returns: None; fails if a ref condition is removed, widened or duplicated elsewhere.
def test_signing_jobs_keep_the_exact_ref_condition() -> None:
    workflow = _workflow("release-android.yml")
    assert workflow.count(REF_CONDITION) == 2
    assert workflow.count("refs/heads/beta/v0.2.1") == 5
    assert "        run: python3 scripts/check_release_ci.py\n" in workflow


# Function Name: test_ci_and_release_keep_their_verification_commands
# Description: The commands whose success the release gate treats as evidence must stay in the workflows.
# Parameters: None.
# Returns: None; fails if a verification command or the direct-APK ABI assertion is missing.
def test_ci_and_release_keep_their_verification_commands() -> None:
    frontend = _workflow("frontend-ci.yml")
    for command in (
        "run: python3 ../scripts/check_release_metadata.py\n",
        "run: flutter pub get --enforce-lockfile\n",
        "run: flutter analyze --no-pub\n",
        "run: flutter test --no-pub\n",
        "run: flutter build apk --release --no-pub --target-platform android-arm,android-arm64\n",
        "- name: Verify APK native ABIs\n",
        APK_ABI_CHECK,
    ):
        assert command in frontend, command
    backend = _workflow("backend-ci.yml")
    assert "run: python -m pytest -p no:cacheprovider tests\n" in backend
    assert "python -m alembic -c alembic.ini downgrade base\n" in backend
    release = _workflow("release-android.yml")
    assert "run: flutter pub get --enforce-lockfile\n" in release
    assert "flutter build apk --release --no-pub \\\n              --target-platform android-arm,android-arm64 \\\n" in release
    assert APK_ABI_CHECK in release
    assert release.count("if-no-files-found: error") == 2


# Function Name: test_dormant_cloud_workflows_stay_disabled
# Description: The three cloud workflows keep their single job behind an always-false condition.
# Parameters: None.
# Returns: None; fails if a dormant job is enabled or a second job is added.
def test_dormant_cloud_workflows_stay_disabled() -> None:
    for name in ("deploy-backend.yml", "data-maintenance.yml", "sync-drug-catalog.yml"):
        workflow = _workflow(name)
        assert workflow.count("\n    if: ${{ false }}\n") == 1, name
        assert workflow.count("\n    runs-on:") == 1, name


# Function Name: test_flutter_sdk_pin_is_identical_in_ci_and_signing
# Description: The signed artifact must be built with the Flutter version that CI analyzed and tested.
# Parameters: None.
# Returns: None; fails if either workflow pins a different version or more than one.
def test_flutter_sdk_pin_is_identical_in_ci_and_signing() -> None:
    pins = {
        name: re.findall(r"flutter-version: '([0-9.]+)'", _workflow(name))
        for name in ("frontend-ci.yml", "release-android.yml")
    }
    assert pins["frontend-ci.yml"] == pins["release-android.yml"] and len(pins["frontend-ci.yml"]) == 1
