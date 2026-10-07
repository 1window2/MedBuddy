# File Name: check_android_release_configuration.py
# Role: Validate local Android release policy and configuration independently of CI orchestration.

"""Read-only release configuration checks used before Android signing."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit


BACKEND_PROBE_FILES = ("backend-health.json", "backend-ready.json", "backend-catalogs.json")


# Class Name: AndroidReleasePolicy
# Role: Preserve the reviewed attestation, distribution and artifact invariants.
# Responsibilities: Normalize protected settings and prohibit unprotected main releases.
# Attributes: app_check_required: Attestation flag; distribution: Play-only or dual-channel output.
@dataclass(frozen=True)
class AndroidReleasePolicy:
    app_check_required: bool
    distribution: str

    # Function Name: __post_init__
    # Description: Keep invalid attestation/channel values out of every immutable policy instance.
    # Parameters: None; checks constructor fields.
    # Returns: None; raises ValueError for an unsupported artifact policy.
    def __post_init__(self) -> None:
        if not isinstance(self.app_check_required, bool):
            raise ValueError("The normalized App Check policy must be a boolean.")
        if self.distribution not in {"play", "both"}:
            raise ValueError("APP_CHECK_RELEASE_DISTRIBUTION must be play or both.")

    # Function Name: from_environment
    # Description: Normalize the exact-ref workflow settings before producing an artifact plan.
    # Parameters: environment: Workflow environment without any credential reads.
    # Returns: Validated policy; raises ValueError for unsupported values or main exceptions.
    @classmethod
    def from_environment(cls, environment: Mapping[str, str]) -> AndroidReleasePolicy:
        value = environment.get("FIREBASE_APP_CHECK_REQUIRED", "").strip().lower()
        if value not in {"", "true", "false"}:
            raise ValueError("FIREBASE_APP_CHECK_REQUIRED must be true or false.")
        required = value != "false"
        distribution = (
            environment.get("APP_CHECK_RELEASE_DISTRIBUTION", "").strip().lower() or "play"
        )
        if environment["GITHUB_REF"] == "refs/heads/main" and not required:
            raise ValueError(
                "Main release builds require Firebase App Check. "
                "The off-Play exception is restricted to beta/v0.2.1."
            )
        return cls(required, distribution)

    # Function Name: build_direct_apk
    # Description: Include a direct APK only for the temporary exception or dual-channel policy.
    # Parameters: None.
    # Returns: Whether the signed build may produce and publish a direct APK.
    @property
    def build_direct_apk(self) -> bool:
        return not self.app_check_required or self.distribution == "both"

    # Function Name: github_environment
    # Description: Serialize only normalized values consumed by downstream workflow steps.
    # Parameters: None.
    # Returns: Safe newline-delimited GitHub environment assignments.
    def github_environment(self) -> str:
        return (
            f"MEDBUDDY_APP_CHECK_REQUIRED_NORMALIZED={str(self.app_check_required).lower()}\n"
            f"MEDBUDDY_RELEASE_DISTRIBUTION={self.distribution}\n"
            f"MEDBUDDY_BUILD_DIRECT_APK={str(self.build_direct_apk).lower()}\n"
        )


# Class Name: BackendReleaseConfiguration
# Role: Bind the Android build to one public API and its readiness identity.
# Responsibilities: Validate target routing and compare all readiness evidence with release expectations.
# Attributes: api_base_url: Medication API target; project_id: Firebase identity; app_check_required: Policy.
@dataclass(frozen=True)
class BackendReleaseConfiguration:
    api_base_url: str
    project_id: str
    app_check_required: bool

    # Function Name: origin
    # Description: Reject non-public or non-standalone medication endpoints before any network probes.
    # Parameters: None.
    # Returns: Validated HTTPS origin; raises ValueError with a credential-free diagnostic.
    @property
    def origin(self) -> str:
        try:
            parsed = urlsplit(self.api_base_url.strip())
        except ValueError:
            raise ValueError("MEDBUDDY_API_BASE_URL is malformed.") from None
        if (
            parsed.scheme != "https" or not parsed.hostname
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path != "/api/v1/medication"
        ):
            raise ValueError(
                "MEDBUDDY_API_BASE_URL must be a public HTTPS URL ending in /api/v1/medication."
            )
        if parsed.hostname.lower() == "localhost":
            raise ValueError("The signed release cannot target localhost.")
        try:
            address = ipaddress.ip_address(parsed.hostname)
        except ValueError:
            pass
        else:
            if not address.is_global:
                raise ValueError("The signed release cannot target a private or loopback IP.")
        return f"{parsed.scheme}://{parsed.netloc}"

    # Function Name: validate_readiness
    # Description: Require matching contract, seeded catalogs and the intended production auth runtime.
    # Parameters: payloads: Three bounded workflow probe objects; api_contract: Source contract version.
    # Returns: None; raises ValueError for missing or mismatched release evidence.
    def validate_readiness(self, payloads: Mapping[str, object], api_contract: str) -> None:
        for name in BACKEND_PROBE_FILES:
            payload = payloads.get(name)
            if not isinstance(payload, dict):
                raise ValueError("The standalone backend readiness response must be an object.")
            if payload.get("api_contract") != api_contract:
                raise ValueError(
                    "The standalone backend API contract does not match "
                    "the Android release contract."
                )
            if name == "backend-catalogs.json" and payload.get("status") != "ready":
                raise ValueError("The backend catalogs must be ready before release.")
        ready = payloads["backend-ready.json"]
        if ready.get("app_env") != "production" or ready.get("runtime_role") != "api":
            raise ValueError(
                "The standalone backend must be a production API runtime "
                "before an Android release can be built."
            )
        if ready.get("auth_mode") != "firebase":
            raise ValueError(
                "The standalone backend must enforce Firebase Authentication "
                "before an Android release can be built."
            )
        if not self.project_id or ready.get("firebase_project_id") != self.project_id:
            raise ValueError(
                "The standalone backend Firebase project does not match "
                "the Android release configuration."
            )
        if ready.get("app_check_required") is not self.app_check_required:
            raise ValueError(
                "The standalone backend App Check policy does not match "
                "the Android release configuration."
            )


# Class Name: FirebaseReleaseConfiguration
# Role: Bind the restored Android Firebase client to protected build expectations.
# Responsibilities: Check the unique package client, project/app identifiers, API key and release SHA-1.
# Attributes: project_id, sender_id, app_id, api_key, certificate_sha1: Protected client expectations.
@dataclass(frozen=True)
class FirebaseReleaseConfiguration:
    project_id: str
    sender_id: str
    app_id: str
    api_key: str = field(repr=False)
    certificate_sha1: str

    # Function Name: from_environment
    # Description: Collect only the protected Firebase release expectations, without logging values.
    # Parameters: environment: Workflow-provided configuration.
    # Returns: Immutable client expectations.
    @classmethod
    def from_environment(cls, environment: Mapping[str, str]) -> FirebaseReleaseConfiguration:
        return cls(
            project_id=environment.get("FIREBASE_PROJECT_ID", ""),
            sender_id=environment.get("FIREBASE_MESSAGING_SENDER_ID", ""),
            app_id=environment.get("FIREBASE_APP_ID", ""),
            api_key=environment.get("FIREBASE_API_KEY", ""),
            certificate_sha1=environment.get("FIREBASE_ANDROID_CERT_SHA1", ""),
        )

    # Function Name: validate
    # Description: Compare the unique MedBuddy Android client with the protected release identity.
    # Parameters: config: Restored google-services.json object.
    # Returns: None; raises ValueError naming mismatched fields without exposing their values.
    def validate(self, config: Mapping[str, object]) -> None:
        project = config["project_info"]
        clients = [
            client for client in config.get("client", [])
            if client.get("client_info", {}).get("android_client_info", {}).get("package_name")
            == "com.medbuddy.app"
        ]
        if len(clients) != 1:
            raise ValueError(
                "google-services.json must contain exactly one MedBuddy Android client."
            )
        client = clients[0]
        checks = {
            "project ID": (project.get("project_id"), self.project_id),
            "sender ID": (str(project.get("project_number", "")), self.sender_id),
            "app ID": (client.get("client_info", {}).get("mobilesdk_app_id"), self.app_id),
            "API key": (
                next(
                    (item.get("current_key") for item in client.get("api_key", [])
                     if item.get("current_key")), None,
                ),
                self.api_key,
            ),
        }
        mismatches = [
            name for name, (actual, expected) in checks.items()
            if not expected or actual != expected
        ]
        sha1 = self.certificate_sha1.replace(":", "").strip().lower()
        registered = {
            item.get("android_info", {}).get("certificate_hash", "").lower()
            for item in client.get("oauth_client", []) if item.get("client_type") == 1
        }
        if not sha1 or sha1 not in registered:
            mismatches.append("release SHA-1")
        if mismatches:
            raise ValueError("Firebase release configuration mismatch: " + ", ".join(mismatches))


# Function Name: _backend_configuration
# Description: Adapt normalized workflow settings to backend release expectations.
# Parameters: environment: Protected workflow variables.
# Returns: Backend identity and attestation expectations.
def _backend_configuration(environment: Mapping[str, str]) -> BackendReleaseConfiguration:
    return BackendReleaseConfiguration(
        api_base_url=environment.get("MEDBUDDY_API_BASE_URL", ""),
        project_id=environment.get("FIREBASE_PROJECT_ID", "").strip(),
        app_check_required=environment["MEDBUDDY_APP_CHECK_REQUIRED_NORMALIZED"] == "true",
    )


# Function Name: main
# Description: Adapt CI environment/files to independently testable release configuration checks.
# Parameters: argv: Optional CLI arguments; configuration remains read-only except GitHub policy output.
# Returns: Zero on matching configuration or one with a credential-free rejection.
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("policy")
    commands.add_parser("backend-origin")
    readiness = commands.add_parser("backend-readiness")
    readiness.add_argument("--probe-directory", type=Path, required=True)
    readiness.add_argument("--contract-file", type=Path, required=True)
    firebase = commands.add_parser("firebase")
    firebase.add_argument("--configuration", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "policy":
            policy = AndroidReleasePolicy.from_environment(os.environ)
            with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
                output.write(policy.github_environment())
        elif args.command == "backend-origin":
            print(_backend_configuration(os.environ).origin)
        elif args.command == "backend-readiness":
            payloads = {
                name: json.loads(args.probe_directory.joinpath(name).read_text(encoding="utf-8"))
                for name in BACKEND_PROBE_FILES
            }
            _backend_configuration(os.environ).validate_readiness(
                payloads, args.contract_file.read_text(encoding="utf-8").strip(),
            )
        else:
            config = json.loads(args.configuration.read_text(encoding="utf-8"))
            FirebaseReleaseConfiguration.from_environment(os.environ).validate(config)
        return 0
    except (OSError, KeyError, TypeError, AttributeError, json.JSONDecodeError):
        print(
            "Android release configuration rejected: missing or malformed configuration inputs.",
            file=sys.stderr,
        )
        return 1
    except ValueError as exc:
        print(f"Android release configuration rejected: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
