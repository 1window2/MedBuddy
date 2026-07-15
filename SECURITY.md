# Security Policy

## Project Status

MedBuddy is in active alpha demo development. Current demo releases are
pre-release builds, not production-ready stable releases.

## Supported Versions

| Version | Status | Security Handling |
| --- | --- | --- |
| `main` / next alpha | Current development target | Security fixes should be applied here first. |
| `v0.0.8-alpha` | Latest alpha demo | Current supported demo release. |
| `v0.0.7-alpha` | Superseded alpha demo | Update to `v0.0.8-alpha` unless a targeted backport is explicitly needed. |
| `v0.0.6-alpha` | Superseded alpha demo | Update to `v0.0.8-alpha` unless a targeted backport is explicitly needed. |
| `v0.0.5-alpha` | Superseded alpha demo | Update to `v0.0.8-alpha` unless a targeted backport is explicitly needed. |
| `v0.0.4-alpha` | Superseded alpha demo | Update to `v0.0.8-alpha` unless a targeted backport is explicitly needed. |
| `v0.0.3-alpha` | Superseded alpha demo | No routine security backports. |
| `v0.0.2-alpha` | Superseded alpha demo | No routine security backports. |
| `v0.0.1-alpha` | Superseded alpha demo | No routine security backports. |

The `main` branch is the source of truth for the next alpha release. When a
security fix lands on `main`, the next alpha tag should be cut from a commit
that includes the fix.

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
`backend/medbuddy.db`.

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
- Keep user-facing guidance clearly informational and avoid presenting it as a
  substitute for professional medical advice.
