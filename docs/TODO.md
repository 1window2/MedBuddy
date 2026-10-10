# MedBuddy Release TODO

## v0.2.2 security review

An external scan of the repository history (33 findings, two of them for
another repository) was checked against the released code on October 9. Work
continues on `beta/v0.2.2`.

Corrected on `beta/v0.2.2`:

- [x] The push notification of a server-written dose record no longer carries
      medication names.
- [x] A link's two display names are returned only to the participant who set
      them.
- [x] Hospital sharing to chat accepts only the date window of the search.
- [x] Multi-pill image decoding shares the decode capacity limit, also after a
      timed-out request.
- [x] Daily quotas per account and per IP address on the AI-backed routes and
      on hospital search; the hospital provider is queried with a coordinate
      rounded to about 100 m.
- [x] A session ended by the server cancels the account's local reminders and
      deletes the device push token; an action taken while signed out is not
      applied to a different account.
- [x] Removing a notification from the inbox erases its stored content.
- [x] English dosage lines no longer rewrite directions that are not a plain
      per-day count ("2일 1회", "12시간마다") or durations that are not days.
- [x] A malformed `Retry-After` header no longer turns a rate-limit answer
      into an unknown failure.

Also corrected on `beta/v0.2.2` (recorded defects from earlier reviews):

- [x] Switching a reminder off and changing its time in the same save keeps
      the new time. Needs the 0.2.2 server and app together; an older app
      sends no time and behaves as before.
- [x] In the medication box, a back press in selection mode only ends the
      selection; it no longer also returns to Home.
- [x] A device language change while the app is running is written back to
      the "use device language" setting, so reminders and server pushes
      follow it without a restart.
- [x] The pharmacy provider is queried with a coordinate rounded to about
      100 m, like hospital search.
- [x] The three quota checks (per minute, per day, chat per day) share one
      helper; the unused three-field settings saver is removed; test runs no
      longer reach a developer's local Redis.

Open, owner decisions:

- [ ] Chat notifications show the message preview by default; the recipient
      can switch to type-only. Decide whether type-only should be the default.
- [ ] The off-Play build runs without App Check and the production backend
      accepts anonymous sign-in. The new daily quotas bound the cost per
      account and per address, not across many addresses.
- [ ] The public hospital API budget (800 requests per day and process) is
      shared by all users; a specialty search can cost up to 41 requests, so a
      few uncached searches use it up. Needs a larger provider quota or a
      reserved share per user.
- [ ] A low-score multi-pill photo is cropped to one pill. Changing the rule
      needs real photographs.
- [ ] The off-Play exception and the release workflow are pinned to
      `beta/v0.2.1`. A signed 0.2.2 build needs them re-pointed, and the
      branch added to the `beta-android` environment.
- Not automated: dropping a held notification action when a different account
  signs in has no widget test (no test seam for a second account).

## v0.2.1 maintenance line

`v0.2.0-beta` was published on October 8 as a limited GitHub pre-release for
direct-install testers; its notes are on the
[releases page](https://github.com/1window2/MedBuddy/releases/tag/v0.2.0-beta).
Work for 0.2.1 continues on `beta/v0.2.1` and is limited to corrections and
small improvements. See the [v0.2.1 notes](releases/v0.2.1-beta.md).

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

- [ ] On Android 14 a reminder set for 13:19 was delivered at 13:21:10. Exact
      alarms are denied by default there and the app falls back to an inexact
      alarm. Owner decision: prompt for the permission or declare
      `USE_EXACT_ALARM`.
- [ ] The server sends every push, chat included, on the caregiver-updates
      channel. The client now creates its channels at start-up, so a push no
      longer lands on the Firebase fallback channel on a fresh install; moving
      chat pushes to the chat channel must wait until clients older than 0.2.1
      are gone.
- [ ] A health recommendation is generated with specific advice for a
      medication whose stored information is empty.
- [ ] A completion alert is sent once per patient, slot and day. A slot first
      completed before a caregiver was linked produces no alert when it is
      undone and completed again after linking.
- [ ] Push tokens that FCM reports as unregistered stay enabled until a send
      to them fails; two such rows exist in production.

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
      code, but no client reads close codes and the released client resets its
      reconnect delay on connect, so it would reconnect every second. Ship a
      client that backs off and reads the codes first.
- [ ] Rate-limit values that took effect in v0.2.1 (including 120 per minute
      for per-item deletes), retention of dose-sync and tombstone rows, and
      HTTP 403 wording and retry behaviour before App Check is enabled. Owner
      decisions.
- [ ] Database: 31 of 64 secondary indexes have no query that uses them, a
      stored course-end column and `pg_trgm` would need migrations.
- [ ] A partial AI summary is stored with "정보 없음" in the missing fields and
      stays until the source document changes.
- [ ] Sign-out does not upload doses recorded offline before suspending the
      worker; they wait until the same account signs in again on the device.
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

- [ ] Non-daily directions ("주 1회", "격일", "8시간마다") are stored as a daily
      count, and week or month durations are read as days. Needs a product
      decision.
- [ ] A caregiver missed-dose deadline is accepted without comparing it with
      the slot's reminder time; the dialog default (21:00) precedes the default
      bedtime reminder (22:00).
- [ ] The weekly catalog refresh sleeps a full interval after every container
      start, so deployments spaced under a week postpone it indefinitely.
- [ ] The chat socket is authenticated once and not re-validated when the
      token expires.
- [ ] Reminder reconciliation trusts the plugin's pending list after a
      force-stop, and a course with unknown duration is scheduled one day at a
      time. A reminder time moved to earlier than now leaves today's alarm at
      the old time, and the reminder worker does not see a dose recorded
      offline that has not been uploaded yet.
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
