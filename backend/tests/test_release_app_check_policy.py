# File Name: test_release_app_check_policy.py
# Role: Keep the temporary off-Play attestation exception out of every ref except the named beta branch.

import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "android_release_configuration_policy", ROOT / "scripts/check_android_release_configuration.py",
)
gate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gate
SPEC.loader.exec_module(gate)


# Function Name: test_signed_workflow_requires_attestation_on_main
# Description: Execute the workflow's shared policy command before it can access signing material.
# Parameters: monkeypatch, tmp_path: Isolated environment/output; ref: Source branch or tag;
#   policy: Environment setting; expected: Accepted normalized value or rejection.
# Returns: None.
@pytest.mark.parametrize("ref,policy,expected", [
    ("refs/heads/main", "", "true"),
    ("refs/heads/main", " TRUE ", "true"),
    ("refs/heads/main", "false", None),
    ("refs/heads/beta/v0.2.1", "false", "false"),
    ("refs/heads/beta/v0.2.1", "", "true"),
    ("refs/heads/beta/v0.2.1", "invalid", None),
    ("refs/tags/v0.2.1-beta", "false", None),
    ("refs/heads/beta/v0.3.0", "false", None),
    ("refs/heads/beta/v0.3.0", "", "true"),
])
def test_signed_workflow_requires_attestation_on_main(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path,
    ref: str, policy: str, expected: str | None,
) -> None:
    output = tmp_path / "github-env"
    monkeypatch.setenv("GITHUB_REF", ref)
    monkeypatch.setenv("FIREBASE_APP_CHECK_REQUIRED", policy)
    monkeypatch.setenv("APP_CHECK_RELEASE_DISTRIBUTION", "")
    monkeypatch.setenv("GITHUB_ENV", str(output))
    if expected is None:
        assert gate.main(["policy"]) == 1
        assert not output.exists()
    else:
        assert gate.main(["policy"]) == 0
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
    output = tmp_path / "github-env"
    monkeypatch.setenv("GITHUB_REF", "refs/heads/beta/v0.2.1")
    monkeypatch.setenv("FIREBASE_APP_CHECK_REQUIRED", policy)
    monkeypatch.setenv("APP_CHECK_RELEASE_DISTRIBUTION", channel)
    monkeypatch.setenv("GITHUB_ENV", str(output))
    if expected is None:
        assert gate.main(["policy"]) == 1
        assert not output.exists()
    else:
        assert gate.main(["policy"]) == 0
        assert f"MEDBUDDY_BUILD_DIRECT_APK={expected}\n" in output.read_text()
        assert f"MEDBUDDY_RELEASE_DISTRIBUTION={channel.strip().lower()}\n" in output.read_text()


# Function Name: test_workflow_uses_one_policy_implementation_before_signing
# Description: Keep policy validation in the module, with YAML only responsible for invoking it.
# Parameters: None.
# Returns: None.
def test_workflow_uses_one_policy_implementation_before_signing() -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    command = "python3 ../scripts/check_android_release_configuration.py policy"
    assert workflow.count(command) == 1
    assert workflow.index(command) < workflow.index("Restore release keystore")
    assert "python - <<'PY'" not in workflow
