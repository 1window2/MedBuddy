# MedBuddy Release TODO

## v0.2.1 maintenance line

`v0.2.0-beta` was published on October 8 as a limited GitHub pre-release for
direct-install testers; its notes are on the
[releases page](https://github.com/1window2/MedBuddy/releases/tag/v0.2.0-beta).
Work for 0.2.1 continues on `beta/v0.2.1` and is limited to corrections and
small improvements. See the [v0.2.1 notes](releases/v0.2.1-beta.md).

### Carried over from v0.2.0

Physical acceptance that was not performed for v0.2.0:

- [ ] Two-device checks: caregiver linking, chat, push delivery and missed-dose
      alerts between a patient and a caregiver phone.
- [ ] A notification "taken" or snooze action from a cold start, and the first
      launch after the application day changes. Both were corrected in v0.2.0
      and are covered by automated tests only.
- [ ] Prescription capture with the on-device privacy filter, and saving
      several identified pills, on a physical device.
- [ ] Devices other than Android 12, including Android 16 background work.
- [ ] Native map-marker recovery after a partially failed marker addition.

Defects and limits recorded during the v0.2.0 audits and not changed:

- [ ] Non-daily directions ("주 1회", "격일", "8시간마다") are stored as a daily
      count, and week or month durations are read as days. Needs a product
      decision.
- [ ] A caregiver missed-dose deadline is accepted without comparing it with
      the slot's reminder time; the dialog default (21:00) precedes the default
      bedtime reminder (22:00).
- [ ] The weekly catalog refresh sleeps a full interval after every container
      start, so deployments spaced under a week postpone it indefinitely.
- [ ] The strength guard reads one number from combination names
      ("5/50밀리그램"), and an ambiguous name prefix can fall through to a vowel
      variant; both can pre-fill a wrong suggestion on the review screen.
- [ ] The chat socket is authenticated once and not re-validated when the
      token expires; a binary frame raises an unhandled error.
- [ ] Reminder reconciliation trusts the plugin's pending list after a
      force-stop, a changed reminder time leaves old inbox entries, and a
      course with unknown duration is scheduled one day at a time.
- [ ] A transient failure while re-synchronizing the session after a token
      refresh drops the signed-in session until it is restored.
- [ ] "Use device language" is resolved once and does not follow a later
      device change; caregivers using English see a Korean default patient
      label.
- [ ] The release gate does not compare the client's API contract default with
      `backend/API_CONTRACT_VERSION`.
- [ ] Tests do not cover weekly or interval frequencies, combination
      strengths, fuzzy candidate recall on a realistic catalog, a PostgreSQL
      run of the migrations, or route wiring for many endpoints.

Unexplained observations from v0.2.0, analysed without a confirmed cause:

- The home unread badge differed across one signed update on October 5. A
  controlled check on October 7 showed that an in-place update preserves
  unread state, so the update itself is not the cause.
- The first health-recommendation request failed once on an emulator with a
  local backend. The server makes a single generation attempt and maps any
  failure to HTTP 500; production generation measured about two seconds.

Firebase console items for the owner: one registered SHA-256 fingerprint that
is not the release certificate could not be attributed, and the phone sign-in
provider is enabled although the app and backend disable phone
authentication.

## Hospital provider access: restored on October 1

The September 30 production lookup received HTTP 403 with XML reason code `30`.
On October 1, the [public-data portal](https://www.data.go.kr/data/15000736/openapi.do)
confirmed an approved hospital-service development account, valid through
October 1, 2028, with 1,000 calls per day per operation. Bounded browser requests
using the portal credential returned `00 / NORMAL SERVICE` and nonempty results
for location, hospital details, and specialty-filtered list operations.

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
