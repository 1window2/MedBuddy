# MedBuddy Release TODO

## v0.2.0 feature freeze and stabilization

As of October 5, finish the existing candidate without new features or implementation
paths. Cleanup may reorganize existing responsibilities, remove proven dead code and
reduce duplication, but must preserve behavior, API/storage contracts, dependencies
and safety/release gates. Use bounded reviewed commits on `beta/v0.2.0`; no shared
history rewrite or automatic merge/tag/publication. See the
[candidate boundary and release gates](releases/v0.2.0-beta.md) and
[latest refactoring evidence](qa/v0.2.0-architecture-gates.md).

Code cleanup is not release acceptance. The owner-authorized signed candidate
`866db67` was installed as a verified matching-signer update on the synthetic
Android 12 phone on October 5. Startup and bounded physical checks are recorded
in [the candidate evidence](qa/v0.2.0-map-direct-filter-device-validation.md#signed-candidate-update--2026-10-05).
Full physical acceptance remains incomplete. Google Play enrollment remains
deferred and two-device checks remain unperformed.
Unimplemented enhancements below are explicitly outside this candidate.

October 6 cleanup consolidates existing pill-upload transport and settings draft
handling and removes a map callback wrapper; see [the cleanup evidence](qa/v0.2.0-architecture-gates.md#cleanup-evidence--2026-10-06).
October 7 cleanup removes unreferenced frontend members and the test-only
pre-Alembic schema patchers, shares the home choice-sheet widgets and tidies the
visual tokens (AA brand green, distinct dose-time colors, flat headers); see
[the latest evidence](qa/v0.2.0-architecture-gates.md#latest-cleanup-evidence--2026-10-07).
Neither changes dependencies or public contracts. The signed build of `2d85e6e`
replaced the phone's `866db67` build on October 7 with exact-source CI, preserved
account data and a physical large-text pass; see
[the signed update evidence](qa/v0.2.0-map-direct-filter-device-validation.md#signed-candidate-update--2026-10-07).
A pre-merge audit then corrected reminder, account-deletion, chat dose-record
and proxy-trust defects; the signed build of `e328bab` is the installed
candidate. See [the audit record](qa/v0.2.0-architecture-gates.md#pre-merge-audit-and-corrections--2026-10-07).
The backend corrections still need a deployment.
A test medication then exercised the dose-time cards and whole-slot toggle.
Caregiver screens were not exercised on the device because the test account
has no linked caregiver.

### Current stabilization acceptance follow-up

- [ ] Diagnose the observed notification unread-state difference across the
      signed update: the baseline home badge showed four, while the candidate
      showed none and retained four historical inbox rows. Do not equate preserved
      rows with preserved read flags or infer data loss without reproduction.
- [ ] Reproduce and diagnose the first health-recommendation request failure
      observed in the [October 5 contributor emulator checks](qa/v0.2.0-2026-10-05-refactor-validation.md).
      Later generation/cache/retry success does not establish the original cause
      or close this finding. Preserve sanitized failure evidence before changing
      existing behavior; do not add product functionality as part of this triage.
- [ ] Physically confirm corrected native map-marker recovery after a partially
      successful addition, failed call and then empty/changed results. The queue
      now clears uncertain marker state before the next diff; synthetic platform
      regressions cover empty/same results, failed clearing and controller
      replacement. This is not yet physical-device acceptance.

Current implementation, verification evidence, and remaining work are summarized
in [the September 21 architecture and roadmap review](qa/v0.2.0-2026-09-21-architecture-review.md).
The subsequent offline-dose date-boundary correction and SDK/lockfile follow-up
are recorded in [the September 22 review](qa/v0.2.0-2026-09-22-dose-midnight-review.md).
The latest contributor work, Home guidance follow-up, and new pharmacy-cache
migration prerequisite are summarized in
[the September 25 follow-up](qa/v0.2.0-2026-09-25-contributor-followup.md).
The migration data-preservation CI gate and rollout/rollback guidance are recorded
in [the September 26 follow-up](qa/v0.2.0-2026-09-26-migration-release-gate.md).
The event-loop blocking correction and exact-commit signing gate are recorded in
[the P1 architecture follow-up](qa/v0.2.0-2026-09-26-p1-architecture-fixes.md).
Ordinary chat push now has a transactional queue; migration and acceptance
requirements are in [the durable delivery design](MedBuddy%20-%20Durable%20Chat%20Delivery.md).
The September 30 production backup, isolated restore and migration rehearsal,
deployment, and public ingress checks are recorded in
[the rollout evidence](qa/v0.2.0-2026-09-30-production-rollout.md).
Individual physical checks below remain open unless their exact scope has evidence;
the September 13 slot-specific cancellation pass does not close global-toggle or
account-cleanup acceptance.

## Hospital provider access: restored on October 1

The September 30 production lookup received HTTP 403 with XML reason code `30`.
On October 1, the [public-data portal](https://www.data.go.kr/data/15000736/openapi.do)
confirmed an approved hospital-service development account, valid through
October 1, 2028, with 1,000 calls per day per operation. Bounded browser requests
using the portal credential returned `00 / NORMAL SERVICE` and nonempty results
for location, hospital details, and specialty-filtered list operations.
See [the provider approval evidence](qa/v0.2.0-2026-10-01-hospital-provider-approval.md).

The deployed backend at `16191b2` now passes bounded location, detail and
specialty-list checks with its existing `PUBLIC_DATA_API_KEY` fallback. No
hospital-key override, secret replacement, code deployment or restart was needed.
The actual search control and calendar dependency also returned one verified
internal-medicine result for both `all` and `open_at_time`, with consultation
hours and successful response serialization. The searches reported truncation
and uncertain region scope; this is not a completeness certificate.

The upstream credential/parser blocker is closed. Authenticated client acceptance,
provider outage/quota behavior and the deferred physical-device checks remain
separate release gates. Core and catalog readiness return HTTP 200, and public
feature routes still reach FastAPI authentication. Do not commit or print keys.

## v0.2.0 release blocker: restore Firebase App Check with Play Integrity

**Status:** Deferred only for direct-install functionality testing. This item
must be completed before the public v0.2.0 Google Play release.

On October 2, Firebase Console showed `com.medbuddy.app` registered with Play
Integrity. The signed-in account had no Google Play developer account; the
owner has deferred enrollment until further notice. Registration alone does
not prove signing fingerprints, verdict policy, Play project linkage, or a
working device token. No console settings or backend enforcement were changed.

The repository now has a tested, read-only live-configuration preflight before
protected Android builds receive Firebase/signing secrets. Its federated
identity and Play signing fingerprint still need owner configuration after
enrollment; see [the setup instructions](Production%20Deployment.md#protected-android-app-check-preflight).

The current off-Play beta keeps Firebase Authentication, HTTPS, trusted-host
validation, and Redis-backed rate limiting enabled, but temporarily builds the
directly installable APK and deploys the backend with App Check enforcement
disabled:

```dotenv
FIREBASE_APP_CHECK_REQUIRED=false
FIREBASE_OFF_PLAY_BETA_MODE=true
```

This exception permits a modified client operated by a valid Firebase user to
call the API without device/app attestation. Do not treat it as the final
public-release security posture. The Google Play AAB remains built with App
Check enabled.

### Completion criteria

- [ ] Create or select the Google Play Console app for `com.medbuddy.app`.
- [ ] Link its Play Integrity API configuration to the same Google Cloud/Firebase
      project used by the MedBuddy Android client and backend.
- [ ] Verify the production signing certificate SHA-256 fingerprint in Firebase
      Android app and App Check registration settings.
- [ ] Configure Firebase App Check verdict requirements for the intended v0.2.0
      distribution channels and confirm the production device-integrity level.
- [ ] Configure the dedicated read-only preflight identity and protected
      `beta-android` variables, then pass `check_release_app_check.py` against
      the live project. Local regression tests are not live acceptance.
- [ ] Deploy the backend with `FIREBASE_APP_CHECK_REQUIRED=true` and
      `FIREBASE_OFF_PLAY_BETA_MODE=false`.
- [ ] Set the `beta-android` GitHub environment variable
      `FIREBASE_APP_CHECK_REQUIRED=true`.
- [ ] Confirm public `/ready` reports `production`, `api`, `firebase`, the
      expected Firebase project ID, and `app_check_required: true`.
- [ ] Build the protected signed artifacts from `main` and verify their signing
      certificate fingerprints and checksums.
- [ ] Install through a Google Play internal-testing track and verify login,
      authenticated API access, restart, network transitions, and temporary
      outage recovery on a physical device.
- [ ] Remove any release documentation that still describes the off-Play
      exception as active.

## Patient burden reduction track

**Product rule:** Prefer removing a repeated patient action over adding another
feature. A one-time setup step is acceptable when it eliminates recurring
typing, navigation, or confirmation. Medication completion must never be
silently inferred from weak evidence.

### Implemented on `beta/v0.2.0`

- [x] Keep the existing atomic whole-slot completion endpoint as the only batch
      writer, so one action records every active medication in a time slot.
- [x] Add a large home-screen `복용했어요` / `Taken` action for the next pending
      medication slot, with duplicate-request protection and schedule review.
      Bulk review must not reset doses completed before the original action.
- [x] Add Android medication-notification actions for `복용했어요` / `Taken`
      and `10분 후 다시 알림` / `Remind in 10 min`. Completion uses the same
      authenticated atomic endpoint; snoozed text does not disclose medication
      names on the lock screen.
- [x] Use the MedBuddy nurse mascot for every Android launcher density.
- [x] Retain per-slot caregiver completion and missed-deadline settings, FCM
      completion delivery, local/background missed-dose monitoring, and chat
      medication context instead of creating a second caregiver workflow.
- [x] Move Firebase-mode missed-deadline detection to the backend maintenance
      worker and durable outbox. Outbox events are deduplicated by their event
      key, but FCM delivery is at least once: retries after partial delivery or
      a crash can produce duplicate receipts. Delivery revalidates consent, the active link,
      the deadline, and the live incomplete state immediately before FCM send.

### Required follow-up

- [ ] Physically verify that disabling medication notifications removes both
      pending alarms and already-displayed medication quick actions while
      preserving caregiver/chat alerts. Android channel regression coverage
      exists; actual device rendering/cleanup remains a separate check.

- [ ] Verify both notification actions on a physical Android device while the
      app is foregrounded, backgrounded, and terminated; also test a locked
      screen, reboot, battery saver, offline completion failure, retry, snooze,
      and explicit per-dose correction after accidental completion.
      Two-device checks below are deferred at the user's request for this
      single-device validation pass; they are not considered passed.
- [ ] Deploy and smoke-test the server-scheduled missed-deadline path with two
      linked physical devices, including patient/caregiver force-stop and
      transient FCM failure. The Android polling path is retained only for
      local/demo authentication mode.
- [x] Define and implement selected-message deletion: private deletion at any
      age; sender-only shared redaction before 24 hours, with server validation,
      confirmation, and retention/export semantics in [Chat Message Deletion.md](Chat%20Message%20Deletion.md).
- [ ] Verify selected-message deletion on two physical devices, including
      reconnect, offline failure, delivered previews and the 24-hour deadline.
- [ ] Run a short task-count usability study with older adults or proxy users:
      record taps, text entry, completion time, error recovery, large-text
      layout, TalkBack labels, and one-handed reachability for the medication,
      caregiver, and chat flows.

### Post-v0.2.0 product backlog — not release-blocking implementation work

These ideas remain recorded, but feature freeze defers their implementation until
after v0.2.0. Existing-flow acceptance tests above remain release requirements.

- [ ] Add caregiver escalation levels with explicit consent, quiet hours,
      cooldowns, acknowledgement, and deduplication. Do not implement literal
      notification flooding: it increases alarm fatigue and can hide urgent events.
- [ ] Add a remotely controlled maintenance notice with a clear start/end time
      and retry guidance before a future planned service interruption.
- [ ] Continue the evidence-gated intake automation stages in
      `MedBuddy - Medication Intake Automation Roadmap.md`. A camera or model
      may preselect a dose, but ambiguous identity, count, or timing must still
      require one clear confirmation and must never write a completion record.
