# MedBuddy Release TODO

## v0.2.2 release candidate

v0.2.2 is the hardening line before a 1.0.0 release decision. An external scan
of the repository history (33 findings, two of them for another repository)
and every item recorded in this file were checked against the released code;
what could be decided and corrected without an external account is corrected
on `beta/v0.2.2`. The changes are listed in the
[v0.2.2 notes](releases/v0.2.2-beta.md).

### Blocking a 1.0.0 release

These need the owner, an external account or a physical device, and are not
closed by any code on this branch:

- [ ] Google Play distribution with App Check (Play Integrity). The off-Play
      build runs without App Check and the production backend accepts
      anonymous sign-in; daily quotas bound the cost per account and per
      address, not across many addresses. See the App Check section below.
- [ ] The public hospital API budget (800 requests per day and process) is
      shared by all users, and one specialty search can cost up to 41
      requests. Needs a larger provider quota.
- [ ] Device verification of this branch. Nothing changed on `beta/v0.2.2`
      has run on a physical phone yet; the lists below under "without a
      device check" still apply as well. A signed build needs `beta/v0.2.2`
      added to the `beta-android` environment.
- [ ] Chat notifications show the message preview by default; the recipient
      can switch to type-only. Decide the default.

### Decided on this branch

- A medication that is not taken every day is scheduled on its dose days,
  read from the frequency text. "N times a week" without weekdays is spread
  over the week from the start date (2: days 1 and 4; 3: days 1, 3 and 5), and
  a monthly direction repeats every 30 days. The review screen states the
  resulting days before saving.
- Exact reminders on Android 14 and later are asked for with a notice and the
  system "Alarms & reminders" screen; `USE_EXACT_ALARM` is not declared
  because Play restricts it to alarm-clock and calendar apps.
- A caregiver missed-dose alert waits for the patient's reminder time plus 30
  minutes. The caregiver dialog proposes the slot time plus one hour and
  refuses an earlier deadline than the standard slot time; it cannot read the
  patient's own reminder time.
- A reminder time moved to earlier than now keeps today's alarm at the old
  time, because cancelling it would leave today's dose without a reminder.
- Push tokens are disabled when a send to them fails; FCM offers no other way
  to learn that a token is gone.
- A released app (0.2.1 or older) keeps receiving every medication of an
  active course in today's schedule, because it switches a slot's reminder off
  when the slot is empty. Only an app that sends the `dose-days` client
  feature gets the dose-day schedule.

### Known limits of this branch

- [ ] A medication saved from a pill photograph can only be given a daily
      count; a non-daily direction needs manual or prescription registration.
- [ ] A slot that holds only non-daily medications has no card on a rest day,
      so its reminder can be configured only on a dose day.
- [ ] "As needed" directions are scheduled like daily ones, on the slots the
      user confirmed.
- [ ] A weekly prescription often prints the number of doses as its total
      days ("4" for four weeks). The review screen shows how many dose days
      result so the user can correct it, but the value is not guessed.
- [ ] No cap on saved medications or links per account; list responses and
      the recommendation prompt grow with them.
- [ ] Dropping a pill-photo crop for a low-score multi-pill image needs real
      photographs before the rule is changed.

## Carried over from v0.2.1

`v0.2.1-beta` is the current limited GitHub pre-release for direct-install
testers ([v0.2.1 notes](releases/v0.2.1-beta.md)). The lists below record what
it left open; items closed on `beta/v0.2.2` have been removed from them.

### Carried over from v0.2.0

Physical acceptance that was not performed for v0.2.0:

- [ ] A notification "taken" or snooze action from a cold start, and the first
      launch after the application day changes. The "taken" action was checked
      with the app in the background only.
- [ ] Prescription capture with the on-device privacy filter, and saving
      several identified pills, on a physical device.
- [ ] Android 16 background work. Android 14 was exercised on an emulator
      only.
- [ ] Native map-marker recovery after a partially failed marker addition.

Introduced in v0.2.1 and not yet checked on a device:

- [ ] Device-to-device transfer: the new extraction rules exclude all app data
      so the encrypted dose store cannot arrive without its device-bound key.
      This needs two phones.

Checked on October 8 with signed builds (Galaxy Note10+, Android 12,
replace-only updates from 0.2.0; an Android 14 emulator with a guest account as
the second device; backend `014aaf4`). The last build checked was `490ef7c`:

- [x] Start without credential entry; saved medications and notification
      history identical before and after the update.
- [x] Manual registration with a photo from the system picker (no storage
      permission), dose check, undo and re-check, whole-slot check, and the
      notification "taken" action with the app in the background.
- [x] A reminder scheduled as an exact alarm fired on the minute; a slot
      already taken was not re-armed when its reminder was enabled again.
- [x] Home-screen widget "taken" and undo: uploaded from the background within
      seconds; with background network blocked by power saving the record
      stayed queued and was uploaded once when the app was opened.
- [x] Update with the moved background entry points: a widget tap made before
      the app was opened logged a callback lookup failure without a crash, was
      kept, and was applied and uploaded at the first launch; background
      handling worked afterwards.
- [x] Two devices: linking by code, chat in both directions, the caregiver's
      view of the patient's schedule, a dose recorded from chat with exactly
      one confirmation, the completion alert, and a missed-dose alert 13
      seconds after its deadline with its two actions.
- [x] Push to the phone arrived within five seconds on the app's own channel.
      It did not arrive on a network where Google's messaging connection
      failed behind a VPN; that was the device's connection, not the app.
- [x] Language switching (English, device language, Korean), settings save,
      voice guide, nearby pharmacy and hospital search, medication detail and
      health recommendation.
- [x] The direct APK (112.9 MB, `arm64-v8a` and `armeabi-v7a`) installs and
      runs on the phone and on an arm64 emulator.
- [x] Backend: per-user rate-limit counters exist for the prefixed routes, row
      counts and the migration head are unchanged by the deployment.

Changed in v0.2.1 and still without a device check (automated tests only):

- [ ] A dose tapped right after midnight, and the widget refresh button.
- [ ] Reminders after a reboot and through the 12-hour worker; cancellation
      after a widget "taken" and again after undo and retake.
- [ ] Push registration after a cold start without network.
- [ ] Session: a network loss during a token refresh keeps the session; a
      401 in chat signs out; ending the session with a pushed screen open.
- [ ] Privacy filter on a real prescription (the label rules are judgments
      and the OCR line order is unverified); cleanup of picked photo copies.
- [ ] Marker retry on the native map and recovery of the dose store on a real
      Keystore.
- [ ] Two devices: unlink while a chat is open, and more than three sessions
      on one link.
- [ ] The periodic WorkManager tasks after an update and before the first
      launch. Their entry point moved like the widget's; only the widget path
      was exercised.

Found during the October 8 checks:

- [ ] The server sends every push, chat included, on the caregiver-updates
      channel. The client now creates its channels at start-up, so a push no
      longer lands on the Firebase fallback channel on a fresh install; moving
      chat pushes to the chat channel must wait until clients older than 0.2.1
      are gone.

Reviewed for v0.2.1 and deferred:

- [ ] Ranking fuzzy catalogue candidates by matched fragments raised recall on
      a synthetic catalogue from 5 to 189 of 200, but every name it moves from
      `unverified` to `llm_catalog_candidate` (0.86–0.89) stops requiring user
      review, because the client flags only `unverified` or a confidence below
      0.75. Needs a check on the production catalogue and a decision on
      review flagging. The same ranking on the local catalogue window turned
      correct automatic matches into review lists without the true product
      and must not be applied as is.
- [ ] Accepting the chat WebSocket before closing it would deliver the close
      code. The 0.2.2 app reads the close codes and backs off, but the 0.2.0
      app resets its reconnect delay on connect, so the server change must
      wait until 0.2.0 is no longer in use.
- [ ] Rate-limit values that took effect in v0.2.1 (including 120 per minute
      for per-item deletes), retention of dose-sync and tombstone rows, and
      HTTP 403 wording and retry behaviour before App Check is enabled. Owner
      decisions.
- [ ] Database: 31 of 64 secondary indexes have no query that uses them, a
      stored course-end column and `pg_trgm` would need migrations.
- Decided, not planned: backend controls keep querying ORM models directly.
  Only three of fourteen models have a repository (the ones several controls
  share), and controls reference models in about 290 places. Wrapping the rest
  would move the queries that were just fixed to a query budget without
  changing behaviour. Add a repository when a second control needs the same
  query. The two background workers in `services/` drive controls by design.
- [ ] Home screen: lifecycle work still runs inside `build`, the shell
      rebuilds on every inbox or chat notification, and the link list is
      polled every 15 seconds under a pushed screen (there is no route
      observer to pause it). The merged facade status message is read only by
      tests.
- [ ] Class diagrams: the operations and classes added in v0.2.1 are not
      drawn, 195 code classes are in no class diagram although the README
      calls the full diagram complete, and stereotypes and package placement
      differ between the full diagram and the feature diagrams. Owner
      decisions on scope and vocabulary.

Defects and limits recorded during the v0.2.0 audits and not changed:

- [ ] The release gate does not compare the client's API contract default with
      `backend/API_CONTRACT_VERSION`.
- [ ] Tests do not cover weekly or interval frequencies, fuzzy candidate
      recall on a realistic catalog, or a PostgreSQL run of the full test suite
      (CI runs only the migration round trip and two integration files on
      PostgreSQL 16). Nothing ties the entities to the migrations, and the
      server strings the client matches are not pinned by a test.

Platform and pipeline items reviewed for v0.2.1 and deferred:

- [ ] The two disabled scheduled workflows (`data-maintenance.yml`,
      `sync-drug-catalog.yml`) still create a skipped run on every schedule
      tick.
- [ ] Both CI workflows report a job named `build`. Making the names unique
      changes the required-check names and needs a branch-protection change by
      the owner.
- [ ] `subosito/flutter-action` and `google-github-actions/auth` are referenced
      by major-version tag, not by commit SHA. Owner decision.
- [ ] `check_release_ingress.py` does not require the
      `X-MedBuddy-Api-Contract` response header; this must be checked against
      the live edge first, because a false rejection blocks a release.
- [ ] Dependabot does not watch the `gradle` and `docker` ecosystems. Owner
      decision on pull-request volume.
- [ ] Exact alarms on Android 14 and later: `SCHEDULE_EXACT_ALARM` is denied by
      default and nothing requests it, so reminders fall back to inexact
      delivery. Needs an owner decision (settings prompt or `USE_EXACT_ALARM`)
      and an Android 14+ device.
- [ ] The merged manifest still carries `RECORD_AUDIO` from the camera plugin
      although capture disables audio. Removal needs a capture check on a
      device.
- [ ] Further APK size reduction (arm64 only, compressed native libraries, or
      per-ABI splits) changes device support or update mechanics. Owner
      decision.
- [ ] The Android instrumented tests run in no workflow; that needs an emulator
      job. A text-level contract test covers the widget names and keys instead.
- [ ] This file and the beta scope still describe the open App Check and
      acceptance gates as v0.2.0 release conditions although v0.2.0-beta was
      published with them open. Owner decision: retitle them as Google Play
      release criteria or record the exception.

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

### Product backlog — outside the v0.2.1 maintenance scope

These ideas remain recorded but are outside the v0.2.1 maintenance scope.
Existing-flow acceptance tests above remain release requirements.

- [ ] Add caregiver escalation levels with explicit consent, quiet hours,
      cooldowns, acknowledgement, and deduplication. Do not implement literal
      notification flooding: it increases alarm fatigue and can hide urgent events.
- [ ] Add a remotely controlled maintenance notice with a clear start/end time
      and retry guidance before a future planned service interruption.
- [ ] Continue the evidence-gated intake automation stages in
      `MedBuddy - Medication Intake Automation Roadmap.md`. A camera or model
      may preselect a dose, but ambiguous identity, count, or timing must still
      require one clear confirmation and must never write a completion record.
