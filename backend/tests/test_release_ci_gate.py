# File Name: test_release_ci_gate.py
# Role: Protect the exact-commit release gate against stale, incomplete and unsuccessful evidence.

import importlib.util
import io
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_ci_gate", ROOT / "scripts/check_release_ci.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


# Function Name: run
# Description: Build a GitHub workflow-run fixture with overridable evidence.
# Parameters: changes - fields differing from a successful matching push run.
# Returns: Workflow-run dictionary.
def run(**changes: object) -> dict:
    return dict(head_sha="target", event="push", run_number=10, run_attempt=1,
                status="completed", conclusion="success") | changes


# Function Name: test_gate_rejects_missing_stale_and_unsuccessful_evidence
# Description: Neither an older success nor PR-only evidence may authorize signing.
# Parameters: runs - GitHub response entries to reject.
# Returns: None; fails if the gate accepts unsafe evidence.
@pytest.mark.parametrize("runs", [
    [], [run(head_sha="other")], [run(event="pull_request")],
    [run(status="in_progress", conclusion=None)],
    [run(conclusion="failure")], [run(conclusion="cancelled")],
    [run(conclusion="skipped")],
    [run(), run(run_attempt=2, status="queued", conclusion=None)],
    [run(), run(run_number=11, conclusion="failure")],
])
def test_gate_rejects_missing_stale_and_unsuccessful_evidence(runs: list[dict]) -> None:
    with pytest.raises(ValueError):
        gate.validate_runs({"workflow_runs": runs}, "target", "backend-ci.yml")


# Function Name: test_gate_accepts_latest_successful_rerun
# Description: A successful rerun supersedes its earlier failed attempt.
# Parameters: None. Returns: None; a rejected valid run fails the test.
def test_gate_accepts_latest_successful_rerun() -> None:
    gate.validate_runs({"workflow_runs": [run(run_attempt=2), run(conclusion="failure")]},
                       "target", "frontend-ci.yml")


# Function Name: test_signing_job_depends_on_secret_free_ci_gate
# Description: Keep signing behind a separate read-only job without the signing environment.
# Parameters: None. Returns: None; fails on removed dependency or leaked environment access.
def test_signing_job_depends_on_secret_free_ci_gate() -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    check, build = workflow.split("\n  build:\n", 1)
    assert "needs: verify-ci" in build
    assert "actions: read" in check
    assert "python3 scripts/check_release_ci.py" in check
    assert "environment: beta-android" not in check
    assert "secrets." not in check


# Function Name: test_gate_command_requires_both_workflows_and_fails_closed
# Description: Exercise real command orchestration without network access or real credentials.
# Parameters: monkeypatch - isolated environment/hooks; failure - second-workflow failure mode.
# Returns: None; fails on accepted bad evidence or credential disclosure.
@pytest.mark.parametrize("failure", [None, "network", "malformed", "pending"])
def test_gate_command_requires_both_workflows_and_fails_closed(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture, failure: str | None,
) -> None:
    monkeypatch.setenv("GITHUB_REPOSITORY", "owner/repository")
    monkeypatch.setenv("GITHUB_SHA", "target")
    monkeypatch.setenv("GH_TOKEN", "test-secret-never-print")
    urls = []

    # Function Name: fetch
    # Description: Supply backend success and a selected Flutter response/failure.
    # Parameters: request - prepared API request; timeout - required finite deadline.
    # Returns: JSON stream, or OSError for unavailable API.
    def fetch(request: object, timeout: int) -> io.StringIO:
        assert timeout == 30
        urls.append(request.full_url)
        if "frontend-ci.yml" in request.full_url:
            if failure == "network":
                raise OSError("test-secret-never-print")
            if failure == "malformed":
                return io.StringIO('{}')
            if failure == "pending":
                return io.StringIO(json.dumps({"workflow_runs": [run(status="queued", conclusion=None)]}))
        return io.StringIO(json.dumps({"workflow_runs": [run()]}))

    monkeypatch.setattr(gate, "urlopen", fetch)
    assert gate.main() == (0 if failure is None else 1)
    assert len(urls) == 2
    assert all("head_sha=target" in url and "event=push" in url for url in urls)
    output = capsys.readouterr()
    assert "test-secret-never-print" not in output.out + output.err
