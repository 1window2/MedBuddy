# File Name: test_release_ingress_gate.py
# Role: Regression coverage for public route checks before Android signing.

import importlib.util
import io
from pathlib import Path
from urllib.error import HTTPError

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_ingress_gate", ROOT / "scripts/check_release_ingress.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


# Function Name: test_ingress_response_rejects_edge_blocks_and_wrong_routes
# Description: HTML challenge pages, public success and missing routes cannot prove protected API routing.
# Parameters: status, media, body: Synthetic HTTP response.
# Returns: None.
@pytest.mark.parametrize("status,media,body", [
    (403, "text/html", b"<html>blocked</html>"),
    (200, "application/json", b'{"detail":"login"}'),
    (404, "application/json", b'{"detail":"Not Found"}'),
    (302, "application/json", b'{"detail":"redirect"}'),
    (403, "application/json", b'{"error":"blocked"}'),
    (401, "application/json", b'[]'),
    (401, "application/json", b'{"detail":[]}'),
    (401, "application/json", b'not JSON'),
])
def test_ingress_response_rejects_edge_blocks_and_wrong_routes(status: int, media: str, body: bytes) -> None:
    with pytest.raises(ValueError):
        gate.validate_response(status, media, body)


# Function Name: test_ingress_accepts_backend_authentication_denials
# Description: Bearer and App Check enforcement both satisfy credential-free route probes.
# Parameters: status: Authentication rejection code.
# Returns: None.
@pytest.mark.parametrize("status", [401, 403])
def test_ingress_accepts_backend_authentication_denials(status: int) -> None:
    gate.validate_response(status, "application/json; charset=utf-8", b'{"detail":"Authentication required"}')


# Function Name: test_ingress_command_probes_without_credentials_and_fails_closed
# Description: Distinguish edge blocking from an undeployed API route without leaking response bodies.
# Parameters: monkeypatch, capsys: Isolated runtime; outcome: Simulated hospital response.
# Returns: None.
@pytest.mark.parametrize("outcome", ["ready", "edge", "missing"])
def test_ingress_command_probes_without_credentials_and_fails_closed(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture, outcome: str,
) -> None:
    urls = []

    # Class Name: Opener
    # Role: HTTP transport double for unauthenticated probes.
    # Responsibilities: Record requested routes and return API denials or an HTML edge block.
    class Opener:
        # Function Name: open
        # Description: Verify finite timeout and absent credentials, then return the selected denial.
        # Parameters: request: Prepared URL and headers; timeout: Finite network budget.
        # Returns: Never returns; raises an HTTP response consumed by the command.
        def open(self, request: object, timeout: int) -> None:
            urls.append(request.full_url)
            assert timeout == 15 and request.get_header("Authorization") is None
            assert request.get_header("X-firebase-appcheck") is None
            hospital_failure = outcome != "ready" and "hospitals" in request.full_url
            status = 403 if outcome == "edge" and hospital_failure else 404 if hospital_failure else 401
            body = (
                b"private-body-never-print" if status == 403
                else b'{"detail":"Not Found"}' if status == 404
                else b'{"detail":"Authentication required"}'
            )
            raise HTTPError(request.full_url, status, "denied",
                            {"Content-Type": "text/html" if status == 403 else "application/json"},
                            io.BytesIO(body))

    monkeypatch.setattr(gate, "build_opener", lambda *args: Opener())
    assert gate.main(["--origin", "https://example.test"]) == (0 if outcome == "ready" else 1)
    assert len(urls) == (3 if outcome == "ready" else 2)
    captured = capsys.readouterr()
    assert "private-body-never-print" not in captured.out + captured.err
    if outcome == "edge":
        assert "hospital: Non-JSON authentication response" in captured.err
    if outcome == "missing":
        assert "hospital: API route returned HTTP 404" in captured.err
    assert gate.NoRedirect().redirect_request(None, None, 302, "", None, "https://other.test") is None


# Function Name: test_signing_workflow_checks_ingress_before_signing_material
# Description: Keep routing verification before restoring Firebase config and keystore secrets.
# Parameters: None.
# Returns: None.
def test_signing_workflow_checks_ingress_before_signing_material() -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    assert workflow.index("check_release_ingress.py") < workflow.index("Restore release keystore")
    assert workflow.index("check_release_ingress.py") < workflow.index("Restore Firebase Android configuration")
