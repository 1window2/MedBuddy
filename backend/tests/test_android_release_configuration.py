# File Name: test_android_release_configuration.py
# Role: Cover extracted Android backend/Firebase configuration contracts without live services or YAML execution.

import importlib.util
import json
import subprocess
import sys
from copy import deepcopy
from dataclasses import FrozenInstanceError
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/check_android_release_configuration.py"
SPEC = importlib.util.spec_from_file_location("android_release_configuration", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gate
SPEC.loader.exec_module(gate)


# Function Name: backend_configuration
# Description: Build the expected production API identity for isolated release checks.
# Parameters: required: Expected App Check policy.
# Returns: Backend configuration with no network access.
def backend_configuration(required: bool = True) -> gate.BackendReleaseConfiguration:
    return gate.BackendReleaseConfiguration(
        "https://api.example.com/api/v1/medication", "test-project", required,
    )


# Function Name: readiness_payloads
# Description: Supply matching liveness, readiness and catalog evidence.
# Parameters: required: Backend-reported App Check flag.
# Returns: Independent synthetic probe objects.
def readiness_payloads(required: bool = True) -> dict[str, dict[str, object]]:
    return {
        "backend-health.json": {"api_contract": "1", "status": "ok"},
        "backend-ready.json": {
            "api_contract": "1", "status": "ready", "app_env": "production",
            "runtime_role": "api", "auth_mode": "firebase",
            "firebase_project_id": "test-project", "app_check_required": required,
        },
        "backend-catalogs.json": {"api_contract": "1", "status": "ready"},
    }


# Function Name: firebase_configuration
# Description: Build protected expectations using a synthetic non-secret Firebase client.
# Parameters: None.
# Returns: Immutable Firebase release configuration.
def firebase_configuration() -> gate.FirebaseReleaseConfiguration:
    return gate.FirebaseReleaseConfiguration("test-project", "12345", "test-app", "test-api-key", "AA:BB")


# Function Name: firebase_payload
# Description: Model google-services.json with a unique MedBuddy client and registered upload certificate.
# Parameters: None.
# Returns: Independent synthetic Firebase configuration.
def firebase_payload() -> dict[str, object]:
    return {
        "project_info": {"project_id": "test-project", "project_number": 12345},
        "client": [{
            "client_info": {
                "android_client_info": {"package_name": "com.medbuddy.app"},
                "mobilesdk_app_id": "test-app",
            },
            "api_key": [{"current_key": "test-api-key"}],
            "oauth_client": [{"client_type": 1, "android_info": {"certificate_hash": "aabb"}}],
        }],
    }


# Function Name: test_backend_origin_rejects_non_standalone_release_targets
# Description: Reject local/private endpoints, credentials and paths incompatible with the API contract.
# Parameters: url: Invalid build target.
# Returns: None.
@pytest.mark.parametrize("url", [
    "", "http://api.example.com/api/v1/medication", "https://localhost/api/v1/medication",
    "https://127.0.0.1/api/v1/medication", "https://10.0.0.1/api/v1/medication",
    "https://[::1]/api/v1/medication", "https://api.example.com/api/v1/pharmacy",
    "https://user:private-key@api.example.com/api/v1/medication",
    "https://api.example.com/api/v1/medication?key=private-key",
    "https://api.example.com/api/v1/medication#fragment", "https://[broken/api/v1/medication",
])
def test_backend_origin_rejects_non_standalone_release_targets(url: str) -> None:
    with pytest.raises(ValueError) as rejected:
        gate.BackendReleaseConfiguration(url, "test-project", True).origin
    assert "private-key" not in str(rejected.value)


# Function Name: test_backend_origin_preserves_the_public_origin
# Description: Parse the endpoint once while retaining HTTPS ports and IPv6 authorities.
# Parameters: url: Public medication API target; expected: Origin consumed by curl and ingress checks.
# Returns: None.
@pytest.mark.parametrize("url,expected", [
    (" https://api.example.com/api/v1/medication ", "https://api.example.com"),
    ("https://api.example.com:8443/api/v1/medication", "https://api.example.com:8443"),
    ("https://[2606:4700:4700::1111]/api/v1/medication", "https://[2606:4700:4700::1111]"),
])
def test_backend_origin_preserves_the_public_origin(url: str, expected: str) -> None:
    assert gate.BackendReleaseConfiguration(url, "test-project", True).origin == expected


# Function Name: test_backend_readiness_accepts_both_reviewed_attestation_modes
# Description: Preserve the temporary off-Play beta exception without relaxing other identity checks.
# Parameters: required: Expected/reported App Check flag.
# Returns: None.
@pytest.mark.parametrize("required", [True, False])
def test_backend_readiness_accepts_both_reviewed_attestation_modes(required: bool) -> None:
    backend_configuration(required).validate_readiness(readiness_payloads(required), "1")


# Function Name: test_backend_readiness_rejects_mismatched_release_evidence
# Description: A valid origin cannot compensate for incompatible contracts, catalogs or auth identity.
# Parameters: name, field, value: Probe field to replace; diagnostic: Rejection category.
# Returns: None.
@pytest.mark.parametrize("name,field,value,diagnostic", [
    ("backend-health.json", "api_contract", "other", "API contract"),
    ("backend-ready.json", "api_contract", "other", "API contract"),
    ("backend-catalogs.json", "api_contract", "other", "API contract"),
    ("backend-catalogs.json", "status", "not_ready", "catalogs"),
    ("backend-ready.json", "app_env", "development", "production API"),
    ("backend-ready.json", "runtime_role", "catalog_sync", "production API"),
    ("backend-ready.json", "auth_mode", "disabled", "Firebase Authentication"),
    ("backend-ready.json", "firebase_project_id", "other", "Firebase project"),
    ("backend-ready.json", "app_check_required", False, "App Check policy"),
    ("backend-ready.json", "app_check_required", "true", "App Check policy"),
    ("backend-ready.json", "app_check_required", 1, "App Check policy"),
])
def test_backend_readiness_rejects_mismatched_release_evidence(
    name: str, field: str, value: object, diagnostic: str,
) -> None:
    payloads = readiness_payloads()
    payloads[name][field] = value
    with pytest.raises(ValueError, match=diagnostic):
        backend_configuration().validate_readiness(payloads, "1")


# Function Name: test_backend_readiness_rejects_missing_or_malformed_probe_objects
# Description: Missing and non-object responses cannot bypass the extracted evidence validator.
# Parameters: value: Missing or malformed readiness payload.
# Returns: None.
@pytest.mark.parametrize("value", [None, [], "ready"])
def test_backend_readiness_rejects_missing_or_malformed_probe_objects(value: object) -> None:
    payloads = readiness_payloads() | {"backend-ready.json": value}
    with pytest.raises(ValueError, match="response must be an object"):
        backend_configuration().validate_readiness(payloads, "1")


# Function Name: test_firebase_configuration_checks_the_intended_unique_android_client
# Description: Unrelated package clients are permitted, but duplicate or missing MedBuddy clients fail.
# Parameters: count: Number of intended Android clients.
# Returns: None.
@pytest.mark.parametrize("count", [0, 1, 2])
def test_firebase_configuration_checks_the_intended_unique_android_client(count: int) -> None:
    payload = firebase_payload()
    client = payload["client"][0]
    unrelated = deepcopy(client)
    unrelated["client_info"]["android_client_info"]["package_name"] = "com.other.app"
    payload["client"] = [unrelated] + [deepcopy(client) for _ in range(count)]
    if count == 1:
        firebase_configuration().validate(payload)
    else:
        with pytest.raises(ValueError, match="exactly one MedBuddy Android client"):
            firebase_configuration().validate(payload)


# Function Name: test_firebase_configuration_reports_fields_without_values
# Description: Cross-project, app, API-key and certificate mismatches fail without revealing config values.
# Parameters: field: Protected expectation to mismatch; diagnostic: Safe field label.
# Returns: None.
@pytest.mark.parametrize("field,diagnostic", [
    ("project_id", "project ID"), ("sender_id", "sender ID"),
    ("app_id", "app ID"), ("api_key", "API key"), ("certificate_sha1", "release SHA-1"),
])
def test_firebase_configuration_reports_fields_without_values(field: str, diagnostic: str) -> None:
    expected = {
        "project_id": "test-project", "sender_id": "12345", "app_id": "test-app",
        "api_key": "test-api-key", "certificate_sha1": "AA:BB",
    }
    expected[field] = "private-value-never-print"
    with pytest.raises(ValueError, match=diagnostic) as rejected:
        gate.FirebaseReleaseConfiguration(**expected).validate(firebase_payload())
    assert "private-value-never-print" not in str(rejected.value)


# Function Name: test_release_policy_is_immutable
# Description: Prevent accidental artifact-plan changes after configuration normalization.
# Parameters: None.
# Returns: None.
def test_release_policy_is_immutable() -> None:
    policy = gate.AndroidReleasePolicy.from_environment({"GITHUB_REF": "refs/heads/main"})
    with pytest.raises(FrozenInstanceError):
        policy.distribution = "both"
    assert "test-api-key" not in repr(firebase_configuration())


# Function Name: test_release_policy_rejects_invalid_direct_construction
# Description: The policy cannot bypass normalization invariants through a direct constructor call.
# Parameters: required, channel: Invalid policy fields.
# Returns: None.
@pytest.mark.parametrize("required,channel", [("true", "play"), (1, "play"), (True, "unknown")])
def test_release_policy_rejects_invalid_direct_construction(required: object, channel: str) -> None:
    with pytest.raises(ValueError):
        gate.AndroidReleasePolicy(required, channel)


# Function Name: test_configuration_cli_adapts_workflow_files_and_environment
# Description: Execute all extracted configuration commands using only synthetic local inputs.
# Parameters: monkeypatch, tmp_path, capsys: Isolated configuration and output fixtures.
# Returns: None.
def test_configuration_cli_adapts_workflow_files_and_environment(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture,
) -> None:
    monkeypatch.setenv("MEDBUDDY_API_BASE_URL", "https://api.example.com/api/v1/medication")
    monkeypatch.setenv("MEDBUDDY_APP_CHECK_REQUIRED_NORMALIZED", "true")
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "test-project")
    monkeypatch.setenv("FIREBASE_MESSAGING_SENDER_ID", "12345")
    monkeypatch.setenv("FIREBASE_APP_ID", "test-app")
    monkeypatch.setenv("FIREBASE_API_KEY", "test-api-key")
    monkeypatch.setenv("FIREBASE_ANDROID_CERT_SHA1", "AA:BB")
    assert gate.main(["backend-origin"]) == 0
    assert capsys.readouterr().out == "https://api.example.com\n"
    for name, payload in readiness_payloads().items():
        tmp_path.joinpath(name).write_text(json.dumps(payload))
    contract = tmp_path / "contract"
    contract.write_text("1\n")
    assert gate.main([
        "backend-readiness", "--probe-directory", str(tmp_path), "--contract-file", str(contract),
    ]) == 0
    config = tmp_path / "google-services.json"
    config.write_text(json.dumps(firebase_payload()))
    assert gate.main(["firebase", "--configuration", str(config)]) == 0
    config.write_text('["private-value-never-print"]')
    assert gate.main(["firebase", "--configuration", str(config)]) == 1
    assert "private-value-never-print" not in capsys.readouterr().err


# Function Name: test_configuration_cli_runs_standalone_from_the_frontend_directory
# Description: Preserve the workflow's execution path without importing backend runtime dependencies.
# Parameters: None.
# Returns: None.
def test_configuration_cli_runs_standalone_from_the_frontend_directory() -> None:
    result = subprocess.run(
        [sys.executable, "../scripts/check_android_release_configuration.py", "--help"],
        cwd=ROOT / "frontend", capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0
    assert "backend-readiness" in result.stdout and "firebase" in result.stdout


# Function Name: test_workflow_wires_configuration_checks_to_the_original_gates
# Description: Keep public probes and local config verification before signing without inline Python or unused job state.
# Parameters: None.
# Returns: None.
def test_workflow_wires_configuration_checks_to_the_original_gates() -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    for command in ("policy", "backend-origin", "backend-readiness", "firebase"):
        assert workflow.count(f"check_android_release_configuration.py {command}") == 1
    assert workflow.index("backend-origin") < workflow.index("check_release_ingress.py")
    assert workflow.index("backend-readiness") < workflow.index("Restore Firebase Android configuration")
    assert workflow.index("check_android_release_configuration.py firebase") < workflow.index("Restore release keystore")
    endpoint_step = workflow.split("      - name: Validate standalone backend endpoint\n", 1)[1].split(
        "      - name: Restore Firebase Android configuration\n", 1,
    )[0]
    assert 'BACKEND_ORIGIN="$(python3 ../scripts/check_android_release_configuration.py backend-origin)"' in endpoint_step
    assert 'python3 ../scripts/check_release_ingress.py --origin "${BACKEND_ORIGIN}"' in endpoint_step
    for endpoint, filename in (
        ("health", "backend-health.json"),
        ("ready", "backend-ready.json"),
        ("ready/catalogs", "backend-catalogs.json"),
    ):
        assert f'"${{BACKEND_ORIGIN}}/{endpoint}" > "${{RUNNER_TEMP}}/{filename}"' in endpoint_step
    assert "${GITHUB_ENV}" not in endpoint_step
    later_steps = workflow.split("      - name: Restore Firebase Android configuration\n", 1)[1]
    assert "BACKEND_ORIGIN" not in later_steps
