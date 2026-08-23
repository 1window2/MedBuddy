# MedBuddy Android Beta Scope

## Status

- Scope review: 2026-08-23
- Stable functional baseline: `v0.1.0`
- Active development branch: `beta/v0.2.0`
- Target release line: `v0.2.0-beta.*`
- Target platform: Android
- iOS: deferred until after the Android public-release decision, no earlier than
  October 2026

This document is the release boundary for the v0.2.0 Android beta. Features
outside the list below do not enter the release without an explicit scope
review covering safety, privacy, data integrity, and release operability.

## Functional Scope Included

The following implemented flows are in v0.2.0 verification:

1. Prescription and pill-envelope image input, on-device Korean OCR,
   best-effort privacy filtering, bounded medication-name correction, OCR
   result editing, adaptive portrait/landscape camera guidance, app-owned image
   cropping, prescription-date and schedule-slot confirmation,
   medication detail lookup, actionable failure recovery back to OCR review,
   schedule review for start date, duration, frequency, dose and slots, and
   saved-medication creation with post-save navigation.
2. Saved-medication listing, detail guidance, image enrichment, shared
   full-screen image inspection, deletion, and medication-course retention,
   with active/completed filtering and registration- or medication-date
   sorting in either direction.
3. Today's schedule generation, per-slot completion, progress display, local
   medication reminders, notification-to-schedule navigation, next-dose home
   summaries, tappable medication-image inspection, completion undo, and
   reminder setup or cancellation feedback.
4. Medication voice guidance in the order medication name, administration
   method, and cautions.
5. User display, Korean/English language, reading-speed, and laboratory feature
   settings, including immediate font/language preview, in-place saving, and a
   fixed back control that remains available while settings content scrolls.
6. Patient-caregiver code linking, linked-patient per-slot schedule views,
   unlinking, per-slot caregiver notification preferences, Firebase
   dose-completion delivery, and background missed-deadline checks.
7. Patient-scoped health recommendations.
8. Experimental loose-pill candidate identification with explicit user
   confirmation, up to ten separately photographed pills, bounded two-request
   concurrency, per-pill partial failure, and schedule review before save.
9. Direct medication entry with optional app-owned local image, dose and unit,
   start/end dates, and schedule slots using the shared saved-medication model.
10. Laboratory nearby-pharmacy lookup using foreground location, backend-held
    public-data credentials, open/all filters, an attributed in-app
    OpenStreetMap view with synchronized card/marker selection, 24-hour
    operating-status metadata, refresh cooldown, phone launch, and external
    directions.
11. Laboratory linked medication chat for active patient-caregiver links and
    active patient medications, with a schedule-style medication picker,
    authorized medication-detail navigation, authenticated REST history,
    WebSocket updates, idempotent retries, read state, and bounded recipient
    notification previews.

## Required Beta Hardening

Implementation status as of 2026-08-23: P0 controls and release configuration
are present in source. The source also includes versioned Alembic migrations,
Firebase App Check, Redis-backed distributed quotas, a shared PostgreSQL pill
catalog, on-device prescription OCR and privacy filtering, authenticated FCM
token management, dose-completion push delivery, persisted per-slot caregiver
settings, and tested recovery and feedback paths for the medication workflow.
The v0.2.0 source also includes direct medication entry, bounded multi-pill
identification, schedule review, guided-camera cropping, backend-mediated
nearby-pharmacy lookup, and authorized medication-context chat. The two new
network features remain disabled by default through laboratory settings.
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
  optional manual-entry images, medication and chat data, transient location
  queries, and push tokens.
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
- Verify chat history retention, unread/read transitions, WebSocket reconnect,
  idempotent send retries, revoked-link denial, and generic notification content.
- Verify that pharmacy coordinates are not persisted or logged and that public
  data refresh limits are enforced at both frontend and backend boundaries.

### P1: Release Verification

- Run backend and Flutter unit/widget suites on every pull request. Automated
  frontend coverage includes compact viewports, large system text, semantic
  labels, app pause/resume, scroll reachability, network recovery, OCR-review
  recovery, post-save navigation, saved-list filtering and sorting,
  dose-completion undo, and reminder result feedback.
- Automated frontend coverage must also include manual-entry validation,
  schedule review, multi-pill partial failure, camera-guide layout/cropping,
  pharmacy permission and cooldown states, linked-chat lifecycle, laboratory
  feature visibility, and health-recommendation bottom reachability.
- Compile an Android release APK on every pull request.
- Add authenticated API integration tests for patient ownership, caregiver
  access, revoked links, expired tokens, and cross-user denial.
- Complete the
  [`beta accessibility and device regression checklist`](qa/beta_accessibility_device_regression_checklist.md)
  for TalkBack, reboot persistence, battery saver, and other Android behaviors
  that automated widget tests cannot prove. Untested physical-device items
  remain release gates.
- Add two-device Android smoke tests for link, schedule, reminder, and
  caregiver flows, including linked medication chat and recipient notifications.
- Validate prescription and loose-pill latency, timeout, offline, malformed
  response, partial-failure, and external-service failure paths.
- Validate nearby-pharmacy permission denial, disabled location service, empty
  result, map tile failure, card/marker selection synchronization, attribution,
  holiday-hours disclaimer, repeated refresh, call, and directions paths.

## Explicitly Out of Scope

- iOS application packaging, signing, distribution, and platform-specific
  notification behavior.
- Automatic diagnosis or medication selection from a loose-pill image.
- Replacing the current pill-attribute boundary with a new local vision model.
- Embedded turn-by-turn navigation, pharmacy inventory guarantees, or automatic
  claims that a pharmacy is open without user confirmation.
- General-purpose social messaging, group chat, attachments, or unlinked chat;
  v0.2.0 chat is limited to an active link and active medication context.
- Any feature that bypasses the BCE control layer or introduces a second API
  path around the medication, pharmacy, or chat routers and shared dependencies.

## Beta Exit Criteria

The first beta may be published only when all of the following are true:

- P0 identity, authorization, HTTPS, and signing requirements are complete.
- Release configuration has no clear-text, demo-scope, debug-signing, or local
  host fallback.
- Database migrations and rollback are tested from a clean database and from
  the v0.1.0 schema, including linked-chat tables and medication context.
- CI is green for backend tests, Flutter analysis/tests, CodeQL, dependency
  validation, and Android release compilation.
- The security and privacy review covers all external AI/public-data calls,
  manual-entry images, location queries, chat storage, and notification payloads.
- A signed artifact passes physical-device smoke testing on supported Android
  versions.
- README, SECURITY, UML, API contracts, and release notes describe the same
  behavior as the shipped artifact.
