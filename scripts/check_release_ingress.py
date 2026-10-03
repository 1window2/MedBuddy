# File Name: check_release_ingress.py
# Role: Reject signed builds when public feature routes are blocked before API authentication.

from __future__ import annotations

import argparse
import json
import sys
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROUTES = {
    "pharmacy": "/api/v1/pharmacy/nearby",
    "hospital": "/api/v1/hospitals/nearby",
    "chat": "/api/v1/chat/links/1/messages",
}


# Class Name: NoRedirect
# Role: Keep probes on the requested API route.
# Responsibilities: Treat redirects to login, challenge or other destinations as release failures.
class NoRedirect(HTTPRedirectHandler):
    # Function Name: redirect_request
    # Description: Disable automatic redirect following for route verification.
    # Parameters: req, fp, code, msg, headers, newurl: urllib redirect context.
    # Returns: None so urllib raises the redirect response.
    def redirect_request(self, req: object, fp: object, code: int, msg: str,
                         headers: object, newurl: str) -> None:
        return None


# Function Name: validate_response
# Description: Accept only JSON authentication denials; HTML edge blocks and route errors fail.
# Parameters: status: HTTP status; content_type: Response media type; body: Bounded bytes.
# Returns: None; raises ValueError on unusable ingress evidence.
def validate_response(status: int, content_type: str, body: bytes) -> None:
    if status == 404:
        raise ValueError("API route returned HTTP 404; deploy the matching backend revision.")
    if status not in {401, 403}:
        raise ValueError(f"Unexpected HTTP {status}; expected an authentication denial.")
    if content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise ValueError("Non-JSON authentication response; check the ingress security rules.")
    try:
        payload = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ValueError("Invalid API authentication JSON.") from None
    if not isinstance(payload, dict) or not isinstance(payload.get("detail"), str) or not payload["detail"]:
        raise ValueError("Route did not return the API error contract.")


# Function Name: check_routes
# Description: Verify public feature routing without sending credentials or performing user operations.
# Parameters: origin: HTTPS backend origin without a path, query, fragment or credentials.
# Returns: None; network, redirect, response or validation failures reject release.
def check_routes(origin: str) -> None:
    parsed = urlsplit(origin)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.path not in {"", "/"} or parsed.query or parsed.fragment):
        raise ValueError("Expected a standalone HTTPS backend origin.")
    opener = build_opener(NoRedirect())
    for feature, path in ROUTES.items():
        request = Request(origin.rstrip("/") + path, headers={"Accept": "application/json"})
        try:
            response = opener.open(request, timeout=15)
        except HTTPError as error:
            response = error
        with response:
            try:
                validate_response(response.code, response.headers.get("Content-Type", ""), response.read(65537))
            except ValueError as exc:
                raise ValueError(f"{feature}: {exc}") from None
        print(f"{feature}: public route reaches API authentication")


# Function Name: main
# Description: Run credential-free probes and report failures without echoing response bodies or URLs.
# Parameters: argv: Optional command-line arguments.
# Returns: Zero when every feature route reaches authentication, one on failure.
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", required=True)
    args = parser.parse_args(argv)
    try:
        check_routes(args.origin)
        return 0
    except ValueError as exc:
        print(f"Release ingress gate rejected: {exc}", file=sys.stderr)
        return 1
    except Exception:
        print("Release ingress gate rejected: network or transport failure.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
