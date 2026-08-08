# Security Policy

## Project Status

MedBuddy is preparing its first Android beta. Published alpha demos remain
pre-release builds and are not production-ready stable releases.

## Supported Versions

| Version | Status | Security Handling |
| --- | --- | --- |
| `v0.1.0-beta` source | Beta candidate | Security fixes are applied to the beta branch before publication. |
| `v0.0.9-alpha` and earlier | Published alpha demos | Superseded demos receive no routine backports. |

The release tag and default branch must include all applicable security fixes.
Superseded alpha demos are not supported release lines.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues,
pull requests, discussions, or screenshots.

If you believe you have found a vulnerability, report it by email:

```text
pretax.rescues.8n@icloud.com
```

Please include:

- A short description of the vulnerability
- Steps to reproduce the issue
- The affected component, endpoint, screen, or configuration file
- The potential impact
- Any relevant logs with secrets, tokens, and personal information removed

We will acknowledge receipt within 72 hours when possible and provide follow-up
updates as the issue is triaged.

## Secret Handling

Never commit API keys, `.env` files, database dumps, private certificates, or
access tokens to the repository. Local secrets should stay in ignored files such
as `backend/.env`.

If a secret is accidentally exposed in a commit, issue, pull request, terminal
log, or screenshot, rotate or revoke the credential immediately. Removing the
text from the repository after exposure is not sufficient by itself.

## Local Data and Generated Files

The local medication catalog database can be large and may be generated from
public data sources. Do not commit generated database files such as
`backend/medbuddy.db`. Production catalog rows belong in the shared,
Alembic-managed PostgreSQL database rather than a container-local file.

Do not commit local SDK paths, generated Flutter build files, tool telemetry
state, emulator-specific configuration, Python virtual environments, pytest
caches, or Android/iOS build outputs. These files reduce portability and can
expose private local paths or user-specific identifiers.

## Dependency Security

Backend runtime dependencies are tracked in `backend/requirements.txt`.
Development and test dependencies are tracked in `backend/requirements-dev.txt`.

Security updates should be evaluated by impact:

- Runtime dependency fixes should be prioritized before a demo release.
- Development/test dependency fixes should be applied when they are compatible
  with the CI Python version.
- Python version compatibility must be checked before accepting dependency
  upgrades. For example, do not merge a package release that requires a newer
  Python version than the backend CI target.

## External Services

MedBuddy uses Gemini and Korean public drug data APIs. Treat all API responses
as untrusted input:

- Validate structured model/API responses before using them.
- Do not log secrets or raw personal medical data.
- Prescription analysis performs Korean OCR and best-effort privacy filtering
  on the device. The original prescription image is not sent through the
  prescription-text endpoint and is not stored in the backend database.
- Only privacy-filtered OCR text is sent for prescription analysis and may be
  processed by Gemini. Local masking reduces exposure but cannot guarantee
  detection of every identifier; the UI and privacy notice must describe this
  limitation accurately.
- Loose-pill photos follow a separate flow and may be sent to an external AI
  service for visible-attribute extraction. Do not persist or log those
  images.
- Keep user-facing guidance clearly informational and avoid presenting it as a
  substitute for professional medical advice.

## Push Notification Data

Firebase Cloud Messaging tokens are delivery addresses associated with a
verified MedBuddy principal; they are not login or authorization credentials.
The client registers the current token after authentication, replaces it when
Firebase refreshes it, and requests deactivation on sign-out. The backend also
disables tokens that Firebase reports as unregistered or associated with a
different sender.

Caregiver notification titles, bodies, and routing data can reveal medication
context. Treat them as sensitive delivery data: minimize the payload, never log
tokens or full notification bodies, and require an active caregiver link and
per-slot preference before dispatch. Firebase mode sends newly completed-dose
events through FCM. Missed-deadline checks currently run through the
authenticated Android background monitor; local demo mode polls for both event
types and displays local notifications without remote push delivery.

## Identity and Authorization Boundary

Published alpha builds use patient and caregiver hashes to select demo data and
must not be used for real multi-user medical data. The beta source supports
Firebase ID-token verification at the FastAPI boundary and maps verified
issuer/subject claims to an opaque internal user key. Medication, schedule,
notification, settings, and link operations derive ownership from that
principal. A requested patient hash is accepted only as a selector after an
active caregiver link has been verified.

Production configuration fails closed unless Firebase authentication and App
Check, a Firebase project, a durable non-SQLite database, external schema
migrations, and Redis-backed distributed quotas are configured. The
unauthenticated `/health` route returns only process liveness, while `/ready`
returns only binary database-revision, Firebase-verifier, App Check, and Redis
readiness. App Check and rate limiting are defense in depth; neither replaces
user authentication or authorization.

The approved migration boundary and delivery order are documented in
[`docs/MedBuddy - Beta Security Architecture.md`](docs/MedBuddy%20-%20Beta%20Security%20Architecture.md).

## Release Integrity

Published alpha artifacts remain development-signed sideloading builds. The
beta source removes debug signing from the release build type, keeps release
keystores ignored, and provides a protected GitHub Environment workflow that
requires release signing credentials. Ordinary pull requests can compile an
unsigned release artifact but never receive signing material.

The main Android manifest rejects clear-text traffic. Only the debug manifest
overlay permits HTTP for emulator or trusted-LAN development. Release runtime
configuration additionally rejects a non-HTTPS API URL. The Cloud Run workflow
uses Workload Identity Federation, Secret Manager values, a migration job, and
Cloud SQL before deploying the API service. The signed Android workflow also
requires the release SHA-1 to be registered in the restored Firebase
configuration and rejects Firebase identifiers that differ from the compiled
Dart configuration.
