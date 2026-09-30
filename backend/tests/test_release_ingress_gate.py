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
# Description: Exercise response handling and prevent auth tokens or error bodies from being printed.
# Parameters: monkeypatch, capsys: Isolated runtime; blocked: Simulate a hospital edge block.
# Returns: None.
@pytest.mark.parametrize("blocked", [False, True])
def test_ingress_command_probes_without_credentials_and_fails_closed(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture, blocked: bool,
) -> None:
    urls = []

    # Class Name: Opener
    # Role: HTTP transport double for unauthenticated probes.
    # Responsibilities: Record requested routes and return API denials or an HTML edge block.
    class Opener:
        # Function Name: open
        # Description: Verify finite timeout and absent credentials, then raise a response-shaped HTTP error.
        # Parameters: request: Prepared URL and headers; timeout: Finite network budget.
        # Returns: Never returns; raises an HTTP response consumed by the command.
        def open(self, request: object, timeout: int) -> None:
            urls.append(request.full_url)
            assert timeout == 15 and request.get_header("Authorization") is None
            assert request.get_header("X-firebase-appcheck") is None
            edge = blocked and "hospitals" in request.full_url
            raise HTTPError(request.full_url, 403 if edge else 401, "denied",
                            {"Content-Type": "text/html" if edge else "application/json"},
                            io.BytesIO(b"private-body-never-print" if edge else b'{"detail":"Authentication required"}'))

    monkeypatch.setattr(gate, "build_opener", lambda *args: Opener())
    assert gate.main(["--origin", "https://example.test"]) == (1 if blocked else 0)
    assert len(urls) == (2 if blocked else 3)
    captured = capsys.readouterr()
    assert "private-body-never-print" not in captured.out + captured.err
    assert gate.NoRedirect().redirect_request(None, None, 302, "", None, "https://other.test") is None


# Function Name: test_signing_workflow_checks_ingress_before_signing_material
# Description: Keep routing verification before restoring Firebase config and keystore secrets.
# Parameters: None.
# Returns: None.
def test_signing_workflow_checks_ingress_before_signing_material() -> None:
    workflow = (ROOT / ".github/workflows/release-android.yml").read_text()
    assert workflow.index("check_release_ingress.py") < workflow.index("Restore release keystore")
    assert workflow.index("check_release_ingress.py") < workflow.index("Restore Firebase Android configuration")
