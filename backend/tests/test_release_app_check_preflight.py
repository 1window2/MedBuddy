# File Name: test_release_app_check_preflight.py
# Role: Keep live attestation preflight fail-closed, read-only and free of credential leaks.

import copy
import importlib.util
import io
import json
import os
import subprocess
from email.message import Message
from pathlib import Path
from urllib.error import HTTPError

import pytest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_app_check_preflight", ROOT / "scripts/check_release_app_check.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
APP_ID = "1:123456789:android:example"
UPLOAD = "AB" * 32
PLAY = "CD" * 32
EXPECTATIONS = {
    "project_id": "medbuddy-test", "project_number": "123456789", "app_id": APP_ID,
    "upload_certificate": UPLOAD, "play_certificate": PLAY,
    "distribution": "play", "device_integrity": "NO_INTEGRITY",
}
ANDROID_APP = {
    "name": f"projects/medbuddy-test/androidApps/{APP_ID}", "projectId": "medbuddy-test",
    "appId": APP_ID, "packageName": "com.medbuddy.app", "state": "ACTIVE",
    "sha256Hashes": [UPLOAD, PLAY],
}
INTEGRITY = {
    "name": f"projects/123456789/apps/{APP_ID}/playIntegrityConfig",
    "accountDetails": {"requireLicensed": True},
}
ARGV = [
    "--project-id", "medbuddy-test", "--project-number", "123456789", "--app-id", APP_ID,
    "--upload-cert-sha256", UPLOAD, "--play-cert-sha256", PLAY,
]


# Function Name: test_preflight_accepts_default_and_explicit_reviewed_policies
# Description: Honor protobuf omission defaults and distinguish Play-only licensing from dual channels.
# Parameters: distribution, licensed, device: Reviewed channel/device combinations.
# Returns: None.
@pytest.mark.parametrize("distribution,licensed,device", [
    ("both", False, "NO_INTEGRITY"),
    ("play", True, "NO_INTEGRITY"),
    ("both", False, "MEETS_DEVICE_INTEGRITY"),
])
def test_preflight_accepts_default_and_explicit_reviewed_policies(
    distribution: str, licensed: bool, device: str,
) -> None:
    expectations = {
        **EXPECTATIONS, "distribution": distribution, "device_integrity": device,
        "play_certificate": UPLOAD if distribution == "both" else PLAY,
    }
    integrity = {
        **INTEGRITY, "accountDetails": {"requireLicensed": licensed},
        "appIntegrity": {"allowUnrecognizedVersion": False},
        "deviceIntegrity": {"minDeviceRecognitionLevel": device}, "tokenTtl": "3600s",
    }
    gate.validate_configuration(ANDROID_APP, integrity, **expectations)
    if distribution == "both" and device == "NO_INTEGRITY":
        omitted_defaults = {"name": INTEGRITY["name"]}
        gate.validate_configuration(ANDROID_APP, omitted_defaults, **expectations)
        gate.validate_configuration(ANDROID_APP, {
            **omitted_defaults, "deviceIntegrity": {"minDeviceRecognitionLevel": "DEVICE_RECOGNITION_LEVEL_UNSPECIFIED"},
        }, **expectations)


# Function Name: test_preflight_rejects_wrong_android_identity_or_certificates
# Description: A valid upload certificate cannot substitute for Firebase's Play signing registration.
# Parameters: field, value: Identity or certificate corruption.
# Returns: None.
@pytest.mark.parametrize("field,value", [
    ("name", "projects/other-project/androidApps/other"), ("projectId", "other-project"),
    ("appId", "other-app"), ("packageName", "com.other.app"), ("state", "DELETED"),
    ("sha256Hashes", [UPLOAD]), ("sha256Hashes", []),
    ("sha256Hashes", "not-a-list"), ("sha256Hashes", [UPLOAD, None]),
])
def test_preflight_rejects_wrong_android_identity_or_certificates(field: str, value: object) -> None:
    with pytest.raises(gate.PreflightError):
        gate.validate_configuration({**ANDROID_APP, field: value}, INTEGRITY, **EXPECTATIONS)


# Function Name: test_preflight_rejects_unreviewed_or_malformed_verdict_policy
# Description: Reject wrong projects, unrecognized builds, incompatible licensing and implicit type coercion.
# Parameters: patch: Integrity settings overriding the default response.
# Returns: None.
@pytest.mark.parametrize("patch", [
    {"name": "projects/987654321/apps/other/playIntegrityConfig"},
    {"appIntegrity": {"allowUnrecognizedVersion": True}},
    {"appIntegrity": {"allowUnrecognizedVersion": "false"}},
    {"appIntegrity": {"allowUnrecognizedVersion": 0}},
    {"appIntegrity": None}, {"accountDetails": []}, {"deviceIntegrity": None},
    {"accountDetails": {"requireLicensed": False}},
    {"accountDetails": {"requireLicensed": "false"}},
    {"deviceIntegrity": {"minDeviceRecognitionLevel": "MEETS_STRONG_INTEGRITY"}},
    {"deviceIntegrity": {"minDeviceRecognitionLevel": "MEETS_DEVICE_INTEGRITY"}},
    {"tokenTtl": "1799s"}, {"tokenTtl": "604801s"}, {"tokenTtl": "Infinitys"},
    {"tokenTtl": "1e4s"}, {"tokenTtl": 3600}, {"tokenTtl": "3600.1234567890s"},
])
def test_preflight_rejects_unreviewed_or_malformed_verdict_policy(patch: dict[str, object]) -> None:
    with pytest.raises(gate.PreflightError):
        gate.validate_configuration(ANDROID_APP, {**INTEGRITY, **patch}, **EXPECTATIONS)


# Function Name: test_preflight_accepts_sha256_separator_variants_and_equal_keys
# Description: Normalize displayed digests and permit an existing app using the same signing/upload key.
# Parameters: None.
# Returns: None.
def test_preflight_accepts_sha256_separator_variants_and_equal_keys() -> None:
    colon_hash = ":".join(["ab"] * 32)
    assert gate.normalize_fingerprint(f"  {colon_hash}\n") == UPLOAD
    gate.validate_configuration(
        {**ANDROID_APP, "sha256Hashes": [colon_hash]}, {"name": INTEGRITY["name"]},
        **{**EXPECTATIONS, "play_certificate": UPLOAD, "distribution": "both"},
    )
    for invalid in ("", "AB" * 31, "AG" * 32, None, 123):
        with pytest.raises(gate.PreflightError):
            gate.normalize_fingerprint(invalid)


# Function Name: test_dual_channel_cannot_use_a_different_upload_certificate
# Description: Firebase registration alone cannot make a separately signed APK Play-recognized.
# Parameters: None.
# Returns: None.
def test_dual_channel_cannot_use_a_different_upload_certificate() -> None:
    with pytest.raises(gate.PreflightError, match="Dual-channel APK signing"):
        gate.validate_configuration(
            ANDROID_APP, {"name": INTEGRITY["name"]}, **{**EXPECTATIONS, "distribution": "both"},
        )
    # Play-only builds deliver only the AAB; Firebase need not trust its upload key.
    gate.validate_configuration({**ANDROID_APP, "sha256Hashes": [PLAY]}, INTEGRITY, **EXPECTATIONS)


# Class Name: Response
# Role: Bounded Google JSON response double.
# Responsibilities: Provide response metadata and record the requested read limit.
# Attributes: status (int): HTTP code; headers (Message): Synthetic provider metadata.
class Response(io.BytesIO):
    # Function Name: __init__
    # Description: Store a synthetic body and content type for the real transport reader.
    # Parameters: body, media, status: Synthetic provider response.
    # Returns: None.
    def __init__(self, body: bytes, media: str = "application/json", status: int = 200) -> None:
        super().__init__(body)
        self.status = status
        self.headers = Message()
        self.headers["Content-Type"] = media

    # Function Name: read
    # Description: Enforce a bounded read even when the provider claims success.
    # Parameters: size: Maximum requested bytes.
    # Returns: Synthetic response bytes.
    def read(self, size: int = -1) -> bytes:
        assert size == gate.MAX_RESPONSE_BYTES + 1
        return super().read(size)


# Function Name: test_preflight_command_reads_only_expected_google_resources
# Description: Exercise the command and reader together; send OAuth only in headers and never log responses.
# Parameters: monkeypatch, capsys: Isolated credential/transport/output.
# Returns: None.
def test_preflight_command_reads_only_expected_google_resources(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str],
) -> None:
    requests = []
    token = "private-oauth-token"

    # Class Name: Opener
    # Role: Recording Google transport double.
    # Responsibilities: Verify GET-only, fixed hosts, credential headers and finite timeouts.
    class Opener:
        # Function Name: open
        # Description: Return live-shaped Android/Integrity responses for the command's two reads.
        # Parameters: request: Prepared read; timeout: Network budget.
        # Returns: Bounded Google JSON response.
        def open(self, request: object, timeout: int) -> Response:
            requests.append(request)
            assert request.get_method() == "GET" and request.data is None
            assert request.get_header("Authorization") == f"Bearer {token}"
            assert timeout == 15 and token not in request.full_url
            payload = copy.deepcopy(ANDROID_APP if len(requests) == 1 else INTEGRITY)
            payload["private-provider-field"] = "private-response-never-print"
            return Response(json.dumps(payload).encode())

    monkeypatch.setenv("GOOGLE_ACCESS_TOKEN", token)
    monkeypatch.setattr(gate, "build_opener", lambda *args: Opener())
    assert gate.main(ARGV) == 0
    assert [request.full_url for request in requests] == [
        "https://firebase.googleapis.com/v1beta1/projects/medbuddy-test/androidApps/1%3A123456789%3Aandroid%3Aexample",
        "https://firebaseappcheck.googleapis.com/v1beta/projects/123456789/apps/1%3A123456789%3Aandroid%3Aexample/playIntegrityConfig",
    ]
    output = capsys.readouterr()
    assert token not in output.out + output.err and "private-response-never-print" not in output.out + output.err
    assert "real-device acceptance still require separate evidence" in output.out
    assert gate.NoRedirect().redirect_request(None, None, 302, "", None, "https://other.test") is None


# Function Name: test_preflight_rejects_bad_http_json_and_redirects_without_disclosure
# Description: Credential expiry, missing registration, edge HTML, oversized bodies and redirects are blockers.
# Parameters: monkeypatch, capsys: Isolated runtime; outcome: Transport corruption.
# Returns: None.
@pytest.mark.parametrize("outcome", [
    "401", "403", "404", "302", "html", "array", "invalid-json", "oversized", "transport",
])
def test_preflight_rejects_bad_http_json_and_redirects_without_disclosure(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], outcome: str,
) -> None:
    private = "private-response-or-credential"

    # Class Name: Opener
    # Role: Failed Google transport double.
    # Responsibilities: Simulate denial/error responses without real credentials or network.
    class Opener:
        # Function Name: open
        # Description: Raise or return the selected credential-bearing failure.
        # Parameters: request, timeout: Transport context.
        # Returns: Corrupted response or raises a failure.
        def open(self, request: object, timeout: int) -> Response:
            if outcome.isdigit():
                raise HTTPError(request.full_url, int(outcome), private, {}, io.BytesIO(private.encode()))
            if outcome == "transport":
                raise ValueError(private)
            body = (
                b"[]" if outcome == "array" else b"not-json" if outcome == "invalid-json"
                else b"a" * (gate.MAX_RESPONSE_BYTES + 1) if outcome == "oversized" else private.encode()
            )
            return Response(body, "text/html" if outcome == "html" else "application/json")

    monkeypatch.setenv("GOOGLE_ACCESS_TOKEN", private)
    monkeypatch.setattr(gate, "build_opener", lambda *args: Opener())
    assert gate.main(ARGV) == 1
    output = capsys.readouterr()
    assert private not in output.out + output.err


# Function Name: test_preflight_rejects_untrusted_endpoint_before_sending_oauth
# Description: Prevent future callers from sending the token to redirected or caller-supplied hosts.
# Parameters: url: Disallowed endpoint.
# Returns: None.
@pytest.mark.parametrize("url", [
    "http://firebase.googleapis.com/path", "https://other.test/path",
    "https://firebase.googleapis.com.evil.test/path", "https://user@firebase.googleapis.com/path",
    "https://firebase.googleapis.com:8443/path", "https://firebase.googleapis.com/path?token=private",
    "https://firebase.googleapis.com/path#private",
])
def test_preflight_rejects_untrusted_endpoint_before_sending_oauth(url: str) -> None:
    with pytest.raises(gate.PreflightError):
        gate.read_configuration(url, "private-token")


# Function Name: test_preflight_rejects_missing_or_header_unsafe_oauth_before_network
# Description: Missing credentials and malformed headers cannot fall back to an unauthenticated check.
# Parameters: monkeypatch, capsys: Isolated runtime; token: Missing or malformed credential.
# Returns: None.
@pytest.mark.parametrize("token", ["", "private\nheader", "private token", "private-\u2603-token"])
def test_preflight_rejects_missing_or_header_unsafe_oauth_before_network(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], token: str,
) -> None:
    monkeypatch.setenv("GOOGLE_ACCESS_TOKEN", token)
    monkeypatch.setattr(gate, "read_configuration", lambda *args: pytest.fail("Unexpected credential transmission"))
    assert gate.main(ARGV) == 1
    output = capsys.readouterr()
    if token:
        assert token not in output.out + output.err


# Function Name: test_protected_workflow_runs_live_preflight_before_signing_secrets
# Description: Require federated read-only configuration evidence for every protected build, not off-Play beta.
# Parameters: None.
# Returns: None.
def test_protected_workflow_runs_live_preflight_before_signing_secrets() -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    authentication = workflow.split("- name: Authenticate read-only Firebase preflight", 1)[1].split("\n      - name:", 1)[0]
    preflight = workflow.split("- name: Verify live Firebase App Check release configuration", 1)[1].split("\n      - name:", 1)[0]
    for step in (authentication, preflight):
        assert "if: env.MEDBUDDY_APP_CHECK_REQUIRED_NORMALIZED == 'true'" in step
    assert "GCP_APP_CHECK_SERVICE_ACCOUNT" in authentication and "GCP_APP_CHECK_WORKLOAD_IDENTITY_PROVIDER" in authentication
    assert "create_credentials_file: false" in authentication and "export_environment_variables: false" in authentication
    assert "access_token_lifetime: 300s" in authentication and "credentials_json" not in authentication
    assert "ANDROID_PLAY_SIGNING_CERT_SHA256" in preflight and "ANDROID_SIGNING_CERT_SHA256" in preflight
    assert "GOOGLE_ACCESS_TOKEN:" in preflight and '--token' not in preflight
    assert workflow.index("check_release_app_check.py") < workflow.index("Restore Firebase Android configuration")
    assert workflow.index("check_release_app_check.py") < workflow.index("Restore release keystore")
    assert "id-token: write" in workflow.split("  build:", 1)[1].split("    defaults:", 1)[0]


# Function Name: _workflow_bash
# Description: Extract the actual Bash step, not a duplicate implementation of the release policy.
# Parameters: name: Workflow step display name.
# Returns: Dedented step script.
def _workflow_bash(name: str) -> str:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    step = workflow.split(f"- name: {name}", 1)[1].split("\n      - name:", 1)[0]
    script = step.split("run: |\n", 1)[1]
    return "\n".join(line[10:] for line in script.splitlines())


# Function Name: _fake_tool
# Description: Install a disposable executable double in the test's isolated temporary directory.
# Parameters: path: Tool path; body: Script implementation.
# Returns: None.
def _fake_tool(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
    path.chmod(0o700)


# Function Name: test_actual_build_and_signature_scripts_share_artifact_plan
# Description: Execute workflow Bash with fake external tools for Play-only, dual-channel and off-Play builds.
# Parameters: tmp_path: Isolated files; policy, distribution, build_apk: Normalized artifact expectations.
# Returns: None.
@pytest.mark.parametrize("policy,distribution,build_apk", [
    ("true", "play", "false"), ("true", "both", "true"), ("false", "play", "true"),
])
def test_actual_build_and_signature_scripts_share_artifact_plan(
    tmp_path: Path, policy: str, distribution: str, build_apk: str,
) -> None:
    tools = tmp_path / "tools"
    frontend = tmp_path / "frontend"
    frontend.mkdir()
    calls = tmp_path / "tool-calls"
    summary = tmp_path / "summary"
    environment = {
        **os.environ, "PATH": f"{tools}:{os.environ['PATH']}",
        "MEDBUDDY_APP_CHECK_REQUIRED_NORMALIZED": policy, "MEDBUDDY_RELEASE_DISTRIBUTION": distribution,
        "MEDBUDDY_BUILD_DIRECT_APK": build_apk, "EXPECTED_SIGNING_CERT_SHA256": UPLOAD,
        "MEDBUDDY_KEYSTORE_PATH": "test-keystore", "MEDBUDDY_KEY_ALIAS": "test-alias",
        "MEDBUDDY_KEYSTORE_PASSWORD": "test-password", "TOOL_CALLS": str(calls),
        "GITHUB_STEP_SUMMARY": str(summary), "ANDROID_HOME": str(tmp_path / "android"),
        "MEDBUDDY_API_BASE_URL": "https://example.test/api/v1/medication",
        "FIREBASE_API_KEY": "fake-test-key", "FIREBASE_APP_ID": APP_ID,
        "FIREBASE_MESSAGING_SENDER_ID": "123456789", "FIREBASE_PROJECT_ID": "medbuddy-test",
        "NAVER_MAP_CLIENT_ID": "test-map-client",
    }
    _fake_tool(tools / "keytool", 'printf "SHA256: %s\\n" "${TEST_AAB_CERT:-$EXPECTED_SIGNING_CERT_SHA256}"\n')
    _fake_tool(tools / "flutter", '''
printf '%s\n' "$*" >> "$TOOL_CALLS"
if [[ "$2" == "apk" ]]; then
  mkdir -p build/app/outputs/flutter-apk
  printf 'fake-apk' > build/app/outputs/flutter-apk/app-release.apk
else
  mkdir -p build/app/outputs/bundle/release
  printf 'fake-aab' > build/app/outputs/bundle/release/app-release.aab
fi
''')
    _fake_tool(tools / "sha256sum", 'test -f "$1"\nprintf "%s  %s\\n" "$EXPECTED_SIGNING_CERT_SHA256" "$1"\n')
    _fake_tool(tools / "jarsigner", '''
test -f "$2"
if [[ "${TEST_JAR_VERIFIED:-true}" == "true" ]]; then
  printf 'jar verified.\n'
fi
if [[ "${TEST_UNSIGNED_AAB:-false}" == "true" ]]; then
  printf 'Warning: unsigned entries\n'
fi
exit "${TEST_JAR_VERIFY_STATUS:-0}"
''')
    _fake_tool(tmp_path / "android/build-tools/1/apksigner", '''
test -f "$4"
printf 'apksigner\n' >> "$TOOL_CALLS"
printf 'Signer #1: certificate SHA-256 digest: %s\n' "${TEST_APK_CERT:-$EXPECTED_SIGNING_CERT_SHA256}"
exit "${TEST_APK_VERIFY_STATUS:-0}"
''')
    subprocess.run(["bash", "-c", _workflow_bash("Build signed APK and app bundle")], cwd=frontend, env=environment, check=True, capture_output=True)
    apk = frontend / "build/app/outputs/flutter-apk/app-release.apk"
    assert apk.exists() is (build_apk == "true")
    assert (frontend / "build/app-release.apk.sha256").exists() is (build_apk == "true")
    assert (frontend / "build/app-release.aab.sha256").exists()
    subprocess.run(["bash", "-c", _workflow_bash("Verify signed release artifacts")], cwd=frontend, env=environment, check=True, capture_output=True)
    recorded = calls.read_text().splitlines()
    bundle_call = next(line for line in recorded if line.startswith("build appbundle"))
    assert "MEDBUDDY_FIREBASE_APP_CHECK_REQUIRED=true" in bundle_call
    assert ("apksigner" in recorded) is (build_apk == "true")
    failures = [
        {"TEST_AAB_CERT": PLAY}, {"TEST_AAB_CERT": "malformed"},
        {"TEST_JAR_VERIFY_STATUS": "1"}, {"TEST_UNSIGNED_AAB": "true"},
        {"TEST_JAR_VERIFIED": "false"},
    ]
    if build_apk == "true":
        failures.extend([{"TEST_APK_CERT": PLAY}, {"TEST_APK_VERIFY_STATUS": "1"}])
    for failure in failures:
        rejected = subprocess.run(
            ["bash", "-c", _workflow_bash("Verify signed release artifacts")],
            cwd=frontend, env={**environment, **failure}, capture_output=True,
        )
        assert rejected.returncode != 0, failure
    if build_apk == "true":
        apk_call = next(line for line in recorded if line.startswith("build apk"))
        assert f"MEDBUDDY_FIREBASE_APP_CHECK_REQUIRED={policy}" in apk_call
        apk.unlink()
        missing_apk = subprocess.run(["bash", "-c", _workflow_bash("Verify signed release artifacts")], cwd=frontend, env=environment, capture_output=True)
        assert missing_apk.returncode != 0
    assert f"Direct APK included: {build_apk}" in summary.read_text()
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    upload_apk = workflow.split("- name: Upload signed direct APK", 1)[1]
    assert "if: env.MEDBUDDY_BUILD_DIRECT_APK == 'true'" in upload_apk
    bundle_upload = workflow.split("- name: Upload signed Play bundle", 1)[1].split("- name: Upload signed direct APK", 1)[0]
    assert "app-release.apk" not in bundle_upload
