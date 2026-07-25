# MedBuddy Android Beta Scope

## Status

- Scope frozen: 2026-07-20
- Functional baseline: `v0.0.9-alpha`
- Target release line: `v0.1.0-beta.*`
- Target platform: Android
- iOS: deferred until after the Android public-release decision, no earlier than
  October 2026

This document is the release boundary for the first beta. New feature ideas do
not enter the beta unless they close a safety, security, data-integrity, or
release-operability gap.

## Functional Scope Included

The following implemented flows are frozen for beta hardening:

1. Prescription and pill-envelope image input, OCR extraction, bounded
   medication-name correction, result review, medication detail lookup, and
   saved-medication creation.
2. Saved-medication listing, detail guidance, image enrichment, deletion, and
   medication-course retention.
3. Today's schedule generation, per-slot completion, progress display, local
   medication reminders, and notification-to-schedule navigation.
4. Medication voice guidance in the order medication name, administration
   method, and cautions.
5. User display, language, and reading-speed settings.
6. Patient-caregiver code linking, linked-patient medication views, unlinking,
   and caregiver notification preference persistence.
7. Patient-scoped health recommendations.
8. Experimental loose-pill candidate identification with explicit user
   confirmation and no automatic medication save.

## Required Beta Hardening

### P0: Identity and Transport Security

- Authenticate every non-health-check API request with a verifiable principal.
- Derive patient ownership and caregiver access on the server. Client-supplied
  hashes may select a linked patient only after authorization; they must not be
  credentials.
- Deploy the backend behind HTTPS and reject clear-text traffic in release
  builds.
- Produce signed Android release artifacts with protected key custody.
- Remove every demo-identity fallback from production configuration.

### P1: Data and Operational Safety

- Introduce versioned database migrations and a durable production database.
- Define retention, deletion, consent, and incident-response behavior for
  medical text and externally processed images.
- Add structured, redacted operational logs, health checks, request tracing,
  timeout metrics, and error-rate monitoring.
- Verify backup and restore procedures before accepting real user data.
- Complete end-to-end caregiver alert delivery, or remove/rename any UI that
  implies remote delivery. Persisting a preference alone is not delivery.

### P1: Release Verification

- Run backend and Flutter unit/widget suites on every pull request.
- Compile an Android release APK on every pull request.
- Add authenticated API integration tests for patient ownership, caregiver
  access, revoked links, expired tokens, and cross-user denial.
- Add two-device Android smoke tests for link, schedule, reminder, and
  caregiver flows.
- Validate prescription and loose-pill latency, timeout, offline, malformed
  response, and external-service failure paths.

## Explicitly Out of Scope

- iOS application packaging, signing, distribution, and platform-specific
  notification behavior.
- Automatic diagnosis or medication selection from a loose-pill image.
- Replacing the current pill-attribute boundary with a new local vision model.
- New health recommendation, pharmacy, commerce, or social features.
- Any feature that bypasses the BCE control layer or introduces a second API
  path around `api.router`.

## Beta Exit Criteria

The first beta may be published only when all of the following are true:

- P0 identity, authorization, HTTPS, and signing requirements are complete.
- Release configuration has no clear-text, demo-scope, debug-signing, or local
  host fallback.
- Database migrations and rollback are tested from a clean database and from
  the latest alpha schema.
- CI is green for backend tests, Flutter analysis/tests, CodeQL, dependency
  validation, and Android release compilation.
- The security and privacy review covers all external AI/public-data calls.
- A signed artifact passes physical-device smoke testing on supported Android
  versions.
- README, SECURITY, UML, API contracts, and release notes describe the same
  behavior as the shipped artifact.

