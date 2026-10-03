# File Name: check_release_app_check.py
# Role: Reject protected Android releases with mismatched live Firebase attestation configuration.

"""Read-only Firebase App Check preflight; does not replace Play/device acceptance."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections.abc import Mapping
from decimal import Decimal
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


MAX_RESPONSE_BYTES = 65_536
DEVICE_LEVELS = ("NO_INTEGRITY", "MEETS_DEVICE_INTEGRITY")


# Class Name: PreflightError
# Role: Carry only locally authored, credential-free diagnostics.
# Responsibilities: Keep arbitrary transport exception messages out of release logs.
class PreflightError(ValueError):
    """An expected rejection safe to report in CI output."""


# Class Name: NoRedirect
# Role: Keep the OAuth credential on the explicitly addressed Google API.
# Responsibilities: Reject redirects instead of forwarding authorization headers.
class NoRedirect(HTTPRedirectHandler):
    # Function Name: redirect_request
    # Description: Disable redirects for authenticated configuration reads.
    # Parameters: req, fp, code, msg, headers, newurl: urllib redirect context.
    # Returns: None so urllib rejects the redirect response.
    def redirect_request(
        self, req: object, fp: object, code: int, msg: str,
        headers: object, newurl: str,
    ) -> None:
        return None


# Function Name: normalize_fingerprint
# Description: Accept only complete SHA-256 certificate digests, without logging their input.
# Parameters: value: Protected expected digest or Firebase-registered digest.
# Returns: Uppercase digest without separators; raises ValueError for malformed values.
def normalize_fingerprint(value: object) -> str:
    if not isinstance(value, str):
        raise PreflightError("Certificate SHA-256 fingerprint is malformed.")
    normalized = re.sub(r"[:\s]", "", value).upper()
    if re.fullmatch(r"[0-9A-F]{64}", normalized) is None:
        raise PreflightError("Certificate SHA-256 fingerprint is malformed.")
    return normalized


# Function Name: _settings_object
# Description: Apply protobuf's omitted-object defaults while rejecting malformed JSON shapes.
# Parameters: payload: Live Play Integrity response; field: Nested settings field.
# Returns: The settings object or an empty default object.
def _settings_object(payload: Mapping[str, object], field: str) -> dict[str, object]:
    value = payload.get(field, {})
    if not isinstance(value, dict):
        raise PreflightError("Play Integrity settings have an invalid structure.")
    return value


# Function Name: validate_configuration
# Description: Bind certificates and verdict policy to the intended active Firebase Android app.
# Parameters: android_app, integrity: Live API responses; remaining values: Protected release expectations.
# Returns: None; mismatches fail closed without printing provider responses.
def validate_configuration(
    android_app: Mapping[str, object], integrity: Mapping[str, object], *,
    project_id: str, project_number: str, app_id: str,
    upload_certificate: str, play_certificate: str,
    distribution: str, device_integrity: str,
) -> None:
    # Step 1: Require the intended active Android app and its channel-appropriate signing identity.
    if (
        android_app.get("name") != f"projects/{project_id}/androidApps/{app_id}"
        or android_app.get("projectId") != project_id
        or android_app.get("appId") != app_id
        or android_app.get("packageName") != "com.medbuddy.app"
        or android_app.get("state") != "ACTIVE"
    ):
        raise PreflightError("Firebase Android app identity or lifecycle mismatch.")
    hashes = android_app.get("sha256Hashes", [])
    if not isinstance(hashes, list):
        raise PreflightError("Firebase certificate registration has an invalid structure.")
    registered = {normalize_fingerprint(value) for value in hashes}
    if distribution not in {"play", "both"}:
        raise PreflightError("Release distribution must be play or both.")
    # A direct APK with a different certificate cannot match Play's recognized app.
    # Merely registering both certificates with Firebase does not change that verdict.
    upload_hash = normalize_fingerprint(upload_certificate)
    play_hash = normalize_fingerprint(play_certificate)
    if distribution == "both" and upload_hash != play_hash:
        raise PreflightError("Dual-channel APK signing must match the Play app-signing certificate.")
    if play_hash not in registered:
        raise PreflightError("Firebase is missing the Play app-signing SHA-256 registration.")
    expected_name = f"projects/{project_number}/apps/{app_id}/playIntegrityConfig"
    if integrity.get("name") != expected_name:
        raise PreflightError("Play Integrity configuration belongs to a different app/project.")
    # Step 2: Match recognition, licensing and device verdicts to the reviewed channel policy.
    app_settings = _settings_object(integrity, "appIntegrity")
    account_settings = _settings_object(integrity, "accountDetails")
    device_settings = _settings_object(integrity, "deviceIntegrity")
    if app_settings.get("allowUnrecognizedVersion", False) is not False:
        raise PreflightError("Protected releases must require PLAY_RECOGNIZED.")
    if account_settings.get("requireLicensed", False) is not (distribution == "play"):
        raise PreflightError("Play Integrity licensing does not match the release channels.")
    actual_level = device_settings.get("minDeviceRecognitionLevel", "NO_INTEGRITY")
    if actual_level == "DEVICE_RECOGNITION_LEVEL_UNSPECIFIED":
        actual_level = "NO_INTEGRITY"
    if device_integrity not in DEVICE_LEVELS or actual_level != device_integrity:
        raise PreflightError("Play Integrity device level differs from the reviewed release policy.")
    # Step 3: Validate the provider's explicit or default token lifetime.
    ttl = integrity.get("tokenTtl", "3600s")
    if not isinstance(ttl, str) or re.fullmatch(r"[0-9]+(?:\.[0-9]{1,9})?s", ttl) is None:
        raise PreflightError("Play Integrity token lifetime is malformed.")
    if not Decimal(1800) <= Decimal(ttl[:-1]) <= Decimal(604800):
        raise PreflightError("Play Integrity token lifetime is outside Firebase's supported range.")


# Function Name: read_configuration
# Description: Fetch bounded JSON from fixed Google API hosts using an environment-only OAuth token.
# Parameters: url: Internally constructed Google endpoint; token: Short-lived access token.
# Returns: A JSON object; transport, authorization and response failures reject release.
def read_configuration(url: str, token: str) -> dict[str, object]:
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or parsed.hostname not in {"firebase.googleapis.com", "firebaseappcheck.googleapis.com"}
        or parsed.username or parsed.password or parsed.port not in {None, 443}
        or parsed.query or parsed.fragment
    ):
        raise PreflightError("Configuration reads must stay on the expected Google API hosts.")
    request = Request(url, headers={"Accept": "application/json", "Authorization": f"Bearer {token}"})
    try:
        with build_opener(NoRedirect()).open(request, timeout=15) as response:
            if response.status != 200:
                raise PreflightError("Google configuration API did not return HTTP 200.")
            if response.headers.get_content_type() != "application/json":
                raise PreflightError("Google configuration API did not return JSON.")
            body = response.read(MAX_RESPONSE_BYTES + 1)
    except HTTPError as exc:
        exc.close()
        raise PreflightError(f"Google configuration read failed (HTTP {exc.code}).") from None
    if len(body) > MAX_RESPONSE_BYTES:
        raise PreflightError("Google configuration response exceeded the size limit.")
    try:
        payload = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise PreflightError("Google configuration API returned invalid JSON.") from None
    if not isinstance(payload, dict):
        raise PreflightError("Google configuration response is not an object.")
    return payload


# Function Name: main
# Description: Verify live attestation setup without changing Firebase, IAM, Play or backend enforcement.
# Parameters: argv: Optional release expectations; GOOGLE_ACCESS_TOKEN: Environment-only OAuth credential.
# Returns: Zero for matching live configuration, one for a sanitized failure.
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--project-number", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--upload-cert-sha256", required=True)
    parser.add_argument("--play-cert-sha256", required=True)
    parser.add_argument("--distribution", choices=("play", "both"), default="play")
    parser.add_argument("--device-integrity", choices=DEVICE_LEVELS, default="NO_INTEGRITY")
    args = parser.parse_args(argv)
    try:
        # Step 1: Validate identifiers, signing expectations and the short-lived credential before any read.
        if re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", args.project_id) is None:
            raise PreflightError("Firebase project ID is missing or malformed.")
        if re.fullmatch(r"[1-9][0-9]*", args.project_number) is None:
            raise PreflightError("Firebase project number is missing or malformed.")
        if not args.app_id or len(args.app_id) > 256 or re.search(r"[\s/]", args.app_id):
            raise PreflightError("Firebase Android app ID is missing or malformed.")
        upload = normalize_fingerprint(args.upload_cert_sha256)
        play = normalize_fingerprint(args.play_cert_sha256)
        token = os.environ.get("GOOGLE_ACCESS_TOKEN", "").strip()
        if re.fullmatch(r"[A-Za-z0-9._~+/-]+=*", token) is None:
            raise PreflightError("A short-lived GOOGLE_ACCESS_TOKEN is required.")
        # Step 2: Read only the intended Firebase Android app and its Play Integrity configuration.
        app_id = quote(args.app_id, safe="")
        android_app = read_configuration(
            f"https://firebase.googleapis.com/v1beta1/projects/{args.project_id}/androidApps/{app_id}",
            token,
        )
        integrity = read_configuration(
            f"https://firebaseappcheck.googleapis.com/v1beta/projects/{args.project_number}/apps/{app_id}/playIntegrityConfig",
            token,
        )
        # Step 3: Compare live configuration with protected release expectations, not artifact signatures alone.
        validate_configuration(
            android_app, integrity, project_id=args.project_id,
            project_number=args.project_number, app_id=args.app_id,
            upload_certificate=upload, play_certificate=play,
            distribution=args.distribution, device_integrity=args.device_integrity,
        )
        print("Live Firebase certificates and Play Integrity release policy match.")
        print("Play project linkage and real-device acceptance still require separate evidence.")
        return 0
    except PreflightError as exc:
        print(f"Release App Check preflight rejected: {exc}", file=sys.stderr)
        return 1
    except Exception:
        print("Release App Check preflight rejected: network or transport failure.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
