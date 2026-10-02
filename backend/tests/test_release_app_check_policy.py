# File Name: test_release_app_check_policy.py
# Role: Keep the temporary off-Play attestation exception out of main release artifacts.

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


# Function Name: test_signed_workflow_requires_attestation_on_main
# Description: Execute the actual workflow normalization step before it can access signing material.
# Parameters: monkeypatch, tmp_path: Isolated environment/output; ref: Source branch;
#   policy: Environment setting; expected: Accepted normalized value or rejection.
# Returns: None.
@pytest.mark.parametrize("ref,policy,expected", [
    ("refs/heads/main", "", "true"),
    ("refs/heads/main", " TRUE ", "true"),
    ("refs/heads/main", "false", None),
    ("refs/heads/beta/v0.2.0", "false", "false"),
    ("refs/heads/beta/v0.2.0", "", "true"),
    ("refs/heads/beta/v0.2.0", "invalid", None),
])
def test_signed_workflow_requires_attestation_on_main(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path,
    ref: str, policy: str, expected: str | None,
) -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    step = workflow.split("- name: Normalize release App Check policy", 1)[1].split("\n      - name:", 1)[0]
    script = step.split("python - <<'PY'\n", 1)[1].split("\n          PY", 1)[0]
    script = "\n".join(line[10:] for line in script.splitlines())
    output = tmp_path / "github-env"
    monkeypatch.setenv("GITHUB_REF", ref)
    monkeypatch.setenv("FIREBASE_APP_CHECK_REQUIRED", policy)
    monkeypatch.setenv("APP_CHECK_RELEASE_DISTRIBUTION", "")
    monkeypatch.setenv("GITHUB_ENV", str(output))
    if expected is None:
        with pytest.raises(SystemExit):
            exec(compile(script, "release-app-check-policy", "exec"), {})
        assert not output.exists()
    else:
        exec(compile(script, "release-app-check-policy", "exec"), {})
        assert output.read_text() == (
            f"MEDBUDDY_APP_CHECK_REQUIRED_NORMALIZED={expected}\n"
            "MEDBUDDY_RELEASE_DISTRIBUTION=play\n"
            f"MEDBUDDY_BUILD_DIRECT_APK={str(expected == 'false').lower()}\n"
        )


# Function Name: test_signed_workflow_normalizes_one_shared_artifact_plan
# Description: Play-only releases omit the direct APK, while dual-channel and off-Play beta builds retain it.
# Parameters: monkeypatch, tmp_path: Isolated environment; policy, channel, expected: Artifact plan.
# Returns: None.
@pytest.mark.parametrize("policy,channel,expected", [
    ("true", "play", "false"), ("true", " BOTH ", "true"),
    ("false", "play", "true"), ("false", "both", "true"),
    ("true", "unknown", None),
])
def test_signed_workflow_normalizes_one_shared_artifact_plan(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path,
    policy: str, channel: str, expected: str | None,
) -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    step = workflow.split("- name: Normalize release App Check policy", 1)[1].split("\n      - name:", 1)[0]
    script = step.split("python - <<'PY'\n", 1)[1].split("\n          PY", 1)[0]
    script = "\n".join(line[10:] for line in script.splitlines())
    output = tmp_path / "github-env"
    monkeypatch.setenv("GITHUB_REF", "refs/heads/beta/v0.2.0")
    monkeypatch.setenv("FIREBASE_APP_CHECK_REQUIRED", policy)
    monkeypatch.setenv("APP_CHECK_RELEASE_DISTRIBUTION", channel)
    monkeypatch.setenv("GITHUB_ENV", str(output))
    if expected is None:
        with pytest.raises(SystemExit):
            exec(compile(script, "release-app-check-policy", "exec"), {})
        assert not output.exists()
    else:
        exec(compile(script, "release-app-check-policy", "exec"), {})
        assert f"MEDBUDDY_BUILD_DIRECT_APK={expected}\n" in output.read_text()
        assert f"MEDBUDDY_RELEASE_DISTRIBUTION={channel.strip().lower()}\n" in output.read_text()
