# MedBuddy Android Beta Scope

## Status

- Scope frozen: 2026-07-20
- Release-preparation review: 2026-08-27
- Stable baseline: `v0.1.0-beta`
- Active maintenance branch: `beta/v0.1.1`
- Target release tag: `v0.1.1-beta`
- Target platform: Android
- iOS: deferred until after the Android public-release decision, no earlier than
  October 2026

This document is the release boundary for the v0.1.1 maintenance beta. New
feature ideas do not enter this branch unless they close a safety, security,
data-integrity, accessibility, or release-operability gap.

Automated source verification continues while no Android physical device is
available. Physical-device and two-device checklist items remain unchecked and
are explicitly deferred; they are not represented as passed. This accepted
deferral does not block code preparation, merge review, or the v0.1.1
publication decision, but it remains a recorded release risk until the device
pass is completed.

## Functional Scope Included

The following implemented flows are frozen for beta hardening:

1. Prescription and pill-envelope image input, on-device Korean OCR,
   best-effort privacy filtering, bounded medication-name correction, OCR
   result editing and manual recovery of omitted medication rows,
   prescription-date and schedule-slot confirmation, row-preserving
   medication detail lookup, partial-failure review and unresolved-row retry,
   actionable technical-failure recovery, and saved-medication creation with
   post-save navigation.
2. Saved-medication listing, detail guidance, image enrichment, deletion, and
   medication-course retention, with active/completed filtering and
   registration- or medication-date sorting in either direction.
3. Today's schedule generation, per-slot completion, progress display, local
   medication reminders, notification-to-schedule navigation, next-dose home
   summaries, completion undo, and reminder setup or cancellation feedback.
4. Medication voice guidance in the order medication name, administration
   method, and cautions.
5. User display, language, and reading-speed settings.
6. Patient-caregiver code linking, linked-patient per-slot schedule views,
   unlinking, per-slot caregiver notification preferences, Firebase
   dose-completion delivery, and background missed-deadline checks.
7. Patient-scoped health recommendations.
8. Experimental loose-pill candidate identification with explicit user
   confirmation and no automatic medication save.

## Required Beta Hardening

Implementation status as of 2026-08-27: P0 controls and release configuration
are present in source. The source also includes versioned Alembic migrations,
Firebase App Check, Redis-backed distributed quotas, a shared PostgreSQL pill
catalog, on-device prescription OCR and privacy filtering, authenticated FCM
token management, dose-completion push delivery, persisted per-slot caregiver
settings, and tested recovery and feedback paths for the medication workflow.
The self-hosted FastAPI/PostgreSQL/Redis stack, public HTTPS ingress, protected
host secrets, scheduled server-side missed-deadline delivery, signed
physical-device testing, backup/restore, and operational abuse-control
validation remain release gates. Historical Google Cloud workflows are disabled.

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

- Validate the versioned Alembic migration chain against clean and upgraded
  PostgreSQL databases, including rollback, and provision the durable
  production database.
- Define retention, deletion, consent, and incident-response behavior for
  de-identified prescription text, loose-pill images processed externally,
  medication data, and push tokens.
- Add structured, redacted operational logs, health checks, request tracing,
  timeout metrics, and error-rate monitoring.
- Run Redis only on the private Compose network and verify that fail-closed
  quotas remain available during restart and outage tests.
- Seed and validate the shared PostgreSQL medication and pill-reference catalog
  before routing traffic to a new API revision.
- Verify backup and restore procedures before accepting real user data.
- Complete scheduled server-side delivery for missed-deadline alerts and
  validate dose-completion FCM delivery on two physical devices. Local Android
  background checks remain a beta fallback, not proof of remote delivery.

### P1: Release Verification

- Run backend and Flutter unit/widget suites on every pull request. Automated
  frontend coverage includes compact viewports, large system text, semantic
  labels, app pause/resume, scroll reachability, network recovery, OCR-review
  manual row recovery, partial medication-lookup recovery, post-save
  navigation, saved-list filtering and sorting,
  dose-completion undo, and reminder result feedback.
- Compile an Android release APK on every pull request.
- Add authenticated API integration tests for patient ownership, caregiver
  access, revoked links, expired tokens, and cross-user denial.
- Complete the
  [`beta accessibility and device regression checklist`](qa/beta_accessibility_device_regression_checklist.md)
  for TalkBack, reboot persistence, battery saver, and other Android behaviors
  that automated widget tests cannot prove. Untested physical-device items
  remain release gates.
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

Except for the explicitly accepted physical-device deferral above, the v0.1.1
maintenance beta may be published only when all of the following are true:

- P0 identity, authorization, HTTPS, and signing requirements are complete.
- Release configuration has no clear-text, demo-scope, debug-signing, or local
  host fallback.
- Database migrations and rollback are tested from a clean database and from
  the latest alpha schema.
- CI is green for backend tests, Flutter analysis/tests, CodeQL, dependency
  validation, and Android release compilation.
- The security and privacy review covers all external AI/public-data calls.
- Physical-device smoke testing remains a post-publication follow-up for this
  candidate and must not be represented as completed.
- README, SECURITY, UML, API contracts, and release notes describe the same
  behavior as the shipped artifact.

Release-candidate changes, deferred verification, and the required
post-publication merge-forward procedure are recorded in
[`docs/releases/v0.1.1-beta.md`](releases/v0.1.1-beta.md).
