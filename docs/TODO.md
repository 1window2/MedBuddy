# MedBuddy Release TODO

## v0.2.3 development line

v0.2.3 starts from `v0.2.2-beta` on `beta/v0.2.3`. It collects small
corrections and improvements found by reviewing the released code and by using
the app, leaving out the switches that belong to a public release (Google Play,
App Check enforcement). If it reaches a state worth publishing as 1.0.0, it is
released under that version instead. Changes are listed in the
[v0.2.3 notes](releases/v0.2.3-beta.md).

### Open on this line

- [ ] The missed-dose scan re-reads every slot that was completed before its
      deadline on each 15-second pass for the rest of the day, two to four
      queries per patient and slot. Negligible at beta size; it grows with
      users. Remembering "complete at the deadline" would change what happens
      when a dose is undone after the deadline, so it needs a decision.
- [ ] The home dose-record notice may not scroll fully at 2x text with a longer
      English message (seen in a widget test while shortening the missed-dose
      text).
- [ ] Device check of the 0.2.3 changes.
- Decided: the home-screen widget's undo button keeps undoing a slot in one
  tap. A widget cannot show a confirmation, and the button is disabled while a
  record is being saved, so a double tap does not reach the undo. The in-app
  slot undo asks for confirmation.

## v0.2.2 release candidate

v0.2.2 is the hardening line before a 1.0.0 release decision. An external scan
of the repository history (33 findings, two of them for another repository)
and every item recorded in this file were checked against the released code;
what could be decided and corrected without an external account is corrected
on `beta/v0.2.2`. The changes are listed in the
[v0.2.2 notes](releases/v0.2.2-beta.md).

### October 11 integration verification

The local audit changes were integrated with upstream `e32c183` without
rewriting either migration history. Final automated checks on this combined
source passed:

- Flutter: 1,939 passed, 8 skipped; static analysis reported no issues.
- The map-marker suite passed all 11 tests with a synthetic client ID,
  including the 7 skipped in the normal run. The remaining skipped Flutter
  test requires Windows symbolic-link permission.
- Backend: 1,716 passed and 68 subtests passed; 2 PostgreSQL integration tests
  were skipped and 3 Bash-dependent release-script cases were deselected on
  Windows. Tests used isolated SQLite and blocked external HTTP/Redis access.
- Class and overall-sequence PNGs were regenerated from their PlantUML sources.

These are automated integration checks, not a new emulator, physical-device,
FCM delivery or iOS acceptance run. Earlier device records below retain their
original scope and date.

### Blocking a 1.0.0 release

These need the owner, an external account or a physical device, and are not
closed by any code on this branch:

- [ ] Google Play distribution with App Check (Play Integrity). The off-Play
      build runs without App Check and the production backend accepts
      anonymous sign-in; daily quotas bound the cost per account and per
      address, not across many addresses. See the App Check section below.
- [ ] The public hospital API budget (800 requests per day and process) is
      shared by all users, and one specialty search can cost up to 41
      requests. Needs a larger provider quota (the operating account is
      requested on the public data portal by registering a use case). Since
      0.2.3 the budget is counted per provider operation, as the provider's
      quota is, which roughly triples the usable calls without a new quota.
- [ ] Device verification of this branch on a physical phone; the lists
      below under "without a device check" still apply as well. The
      `beta-android` environment allows `beta/v0.2.2` since October 12.
      Independently recorded upstream on October 11 with a debug build on an
      Android 14 emulator
      against a local server: today's schedule hides medications that are not
      due; a slot whose only medication is not due today can still have its
      reminder switched on; alarms for a Monday-Wednesday-Friday medication
      exist on those days only; the exact-alarm notice opens the system
      screen and, once allowed, all 21 pending alarms were re-armed as exact
      on return to the app; marking a slot as taken updates the server and
      cancels today's alarm.
      Also on October 11, the released 0.2.1 app on an emulator against the
      new production server: start, chat list, history and the live stream
      work, and the app reconnected by itself after a backend redeployment.
      With its chat left open for five and a half hours, across several ID
      token lifetimes, network changes and host sleeps, the server accepted 15
      connections at intervals of 2 to 78 minutes, refused none and logged no
      error: closing the stream at token expiry does not make the released
      app reconnect in a loop. Individual closes were not attributed to their
      cause, because the server did not log close codes then; refusals are
      logged with their code since October 12.
      On October 12, the released 0.2.1 app on the physical phone (Galaxy
      Note10+, Android 12) against the production server, with a caregiver
      on the emulator: the app starts and loads its schedule; a weekly test
      medication on a rest day is still listed for this app, as intended for
      apps without the dose-days feature; a reminder switched on for its slot
      stayed enabled on the server across restarts, and its alarms were
      reserved; recording the dose was stored; completing a daily test
      medication produced the caregiver alert within a second and the chat
      record appeared in the caregiver's app. Completing the weekly
      medication on its rest day queued an alert that the worker dropped as
      no longer current, because that dose is not due that day. The same
      session confirmed on the device that a force-stop removes the app's
      alarms and 0.2.1 does not reserve them again; 0.2.2 re-arms them, which
      was not yet verified on a phone at that point.
      Also on October 12, a debug build of this branch on the Android 14
      emulator: six reserved reminders were all removed by a force-stop and
      all six were reserved again at the same times when the app was opened;
      the medication box showed the next dose day of the non-daily test
      medications and none for the daily one.
      Later on October 12 the `beta-android` environment accepted the branch
      and the signed 0.2.2 build of `9baccff` (same signing certificate as
      0.2.1, checksum verified) was installed over 0.2.1 on the phone (Galaxy
      Note10+, Android 12) against the production server. The update kept the
      session and the data, and the package no longer requests microphone or
      storage access. Today's schedule hid the weekly test medication on its
      rest day. A medication registered manually was saved and scheduled. A
      reminder switched on for its slot was reserved as an exact alarm; a
      force-stop removed it and opening the app reserved it again. With the
      app process not running, the notification appeared at its minute; its
      "taken" action started the app, recorded the dose and cleared the
      notification, the server stored the completion and sent the caregiver
      alert in the same second, and the record appeared in the chat. The chat
      stream connected and a message was sent. The guided prescription camera
      took a photograph, and the pharmacy map listed 30 pharmacies.
      The signed build of `55ddaf5` followed on the same phone: manual
      registration offers the dose days and states them ("every 7 days", two
      dose days in a 14-day period); the medication was stored with the
      weekly direction, appeared in today's schedule on its first dose day,
      and the medication box showed its next dose day.
      A second pass on October 12 used the phone as the patient and the
      signed 0.2.2 build on an Android 14 emulator as the caregiver, both
      against the production server:
      the reminder's snooze action, pressed with the app not running, started
      the app and reserved the alarm ten minutes later; the home-screen widget
      showed today's state, its refresh ran, and its "taken" stored the dose
      and cancelled the snoozed alarm; a dose undone in the app was shown as
      open in the widget again.
      On the emulator the exact-alarm notice appeared in the settings, opened
      the system screen, and was gone on return once the permission was
      allowed. Three reserved reminders were all reserved again after a
      reboot without opening the app.
      Between the two devices: the caregiver saw the patient's schedule with
      the weekly medication on its dose day; a missed-dose deadline produced
      the alert 15 seconds after the deadline with the caregiver app not
      running; its snooze action queued the alert again on the server and it
      returned ten minutes later; its chat action sent the request and the
      phone received the push. A message sent from the phone appeared live on
      the emulator and "delete for everyone" replaced it on both at once.
      A second link in the other direction was created by code and removed by
      one side while the other had its chat open: the open chat showed
      "disconnected" within a minute and a send failed with "try again" —
      the link's end was not stated. Fixed after this pass (see below) and
      checked again the same evening with the signed build of `c87b14a` on
      both devices: left alone, the open chat showed "link ended" and the
      notice in place of the input 68 seconds after the link was removed;
      with a message sent right after the removal it did so three seconds
      after the send. In selection mode a tap on the message or beside it
      toggled the selection.
      Not checked: two physical phones, more than three sessions on one link,
      a transient FCM failure, and Android 16.
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
- The background reminder refresh reads today's schedule through the device's
  dose store, so that a dose recorded offline is not reminded again. When the
  store cannot be read, the refresh fails and is retried, leaving the reserved
  14-day window as it is; it does not fall back to the server's state, which
  could re-arm a reminder for a dose already taken. A store that stays
  unreadable therefore stops the window from being extended until the app is
  opened.
- Push tokens are disabled when a send to them fails; FCM offers no other way
  to learn that a token is gone.
- One account may hold 300 saved medications and 20 active links as a
  patient and 20 as a caregiver (`SAVED_MEDICATION_MAX_PER_ACCOUNT`,
  `PATIENT_CAREGIVER_LINK_MAX_PER_ACCOUNT`); the next one is refused with
  HTTP 409 and a message for the user.
- The dependency updates proposed in 1window2/MedBuddy#124 (nine backend
  packages, among them SQLAlchemy 2.1 and websockets 17) are not taken into
  the release candidate; they change behaviour without a stated security fix.
- A released app (0.2.1 or older) keeps receiving every medication of an
  active course in today's schedule, because it switches a slot's reminder off
  when the slot is empty. Only an app that sends the `dose-days` client
  feature gets the dose-day schedule.

### Known limits of this branch

- [ ] A medication saved from a pill photograph or registered manually can be
      given four rhythms (every day, every other day, once a week, once a
      month); others such as named weekdays need prescription registration.
      Manual registration offered no rhythm at all until October 12, so a
      weekly medication entered by hand was scheduled every day; found while
      using the signed build on the phone.
- [ ] "As needed" directions are scheduled like daily ones, on the slots the
      user confirmed.
- [ ] A dose of a medication that is not taken every day can be recorded
      only on its dose day; the day after, it is no longer on the schedule, so
      a weekly dose taken a day late cannot be recorded. The medication box
      shows the next dose day of such a medication, so that its absence from
      today's schedule is explained.
- [ ] A weekly prescription often prints the number of doses as its total
      days ("4" for four weeks). The review screen shows how many dose days
      result so the user can correct it, but the value is not guessed.
- [ ] Dropping a pill-photo crop for a low-score multi-pill image needs real
      photographs before the rule is changed.

## Carried over from v0.2.1

`v0.2.1-beta` is the current limited GitHub pre-release for direct-install
testers ([v0.2.1 notes](releases/v0.2.1-beta.md)). The lists below record what
it left open; items closed on `beta/v0.2.2` have been removed from them.

### Carried over from v0.2.0

Physical acceptance that was not performed for v0.2.0:

- [x] A notification "taken" or snooze action from a cold start: both checked
      on the phone on October 12 with the signed 0.2.2 build.
- [ ] The first launch after the application day changes.
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

- [x] The widget refresh button, and cancellation of a pending reminder after
      a widget "taken" following an undo: checked on the phone on October 12.
      Reminders after a reboot: checked on the Android 14 emulator with the
      signed build.
- [ ] A dose tapped right after midnight, and reminders through the 12-hour
      worker.
- [ ] Push registration after a cold start without network.
- [ ] Session: a network loss during a token refresh keeps the session; a
      401 in chat signs out; ending the session with a pushed screen open.
- [ ] Privacy filter on a real prescription (the label rules are judgments
      and the OCR line order is unverified); cleanup of picked photo copies.
- [ ] Marker retry on the native map and recovery of the dose store on a real
      Keystore.
- [x] Two devices: unlink while a chat is open. Checked on October 12 between
      the phone and an emulator; the open chat did not say that the link had
      ended, which is fixed: the chat now replaces its input with a notice and
      shows "link ended" once the server refuses the link, and a failed send
      asks for the history once so that this is recognised without waiting
      for the stream to close. Regression:
      [chat screen](../frontend/test/linked_chat_ui_boundary_test.dart).
- [ ] More than three sessions on one link (needs four clients of one account).
- [ ] The periodic WorkManager tasks after an update and before the first
      launch. Their entry point moved like the widget's; only the widget path
      was exercised.

Found during the October 8 checks:

- [ ] The server sends every push, chat included, on the caregiver-updates
      channel. The client now creates its channels at start-up, so a push no
      longer lands on the Firebase fallback channel on a fresh install; moving
      chat pushes to the chat channel must wait until clients older than 0.2.1
      are gone.
- [x] Switching a reminder off and changing its time in the same save now
      persists both atomically. No body or `{}` preserves the existing time;
      an hour alone defaults minutes to `00`, and minutes alone is rejected.
      An older server that ignores it is not reported as a successful time save.
      Regressions: [disable API](../backend/tests/test_disabled_reminder_time.py),
      [client request](../frontend/test/set_notification_control_test.dart) and
      [schedule settings](../frontend/test/check_schedule_ui_boundary_test.dart).
      October 10 live check: while OFF, `18:55` changed to `19:55` and persisted;
      it was then restored to `18:55`, still OFF.

Confirmed in the October 10 working tree (live checks noted separately):

The October 10 audit and APK/backend installation preceded this integration.
Those live checks do not certify the October 11 combined branch.
Only the live checks explicitly recorded here are complete; the unchecked
device items remain open. This pass does not certify physical-device FCM,
battery-saver or iOS behavior.

- [x] Settings reads, manual saves and device-language updates are serialized;
      failed server saves retain local edits, and a late previous-account
      bootstrap cannot replace the current account's language.
      Regressions: [settings saves](../frontend/test/medbuddy_user_setting_view_model_test.dart)
      and [session language](../frontend/test/runtime_locale_session_test.dart).
- [x] Missing or blank push tokens remain pending for retry without another
      permission prompt. Failed Android channel creation is retried, with
      concurrent initializers sharing one attempt.
      Regressions: [push registration](../frontend/test/push_notification_service_test.dart)
      and [channel recovery](../frontend/test/notification_channel_recovery_test.dart).
- [x] Backend startup/shutdown failures still close the remaining workers and
      resources. Push-token revocation checks ownership in the update, so an
      old account's logout cannot disable a token transferred to a new account.
      Regressions: [backend cleanup and revocation](../backend/tests/test_backend_environment_regressions.py).
- [x] Prescription comparison treats `2`, `2회` and `1일 2회`, and `7` and
      `7일`, as equivalent labels. Actual counts, dosage units and additional
      directions remain distinct; displayed source values are preserved.
      Regressions: [schedule comparison](../backend/tests/test_prescription_change_schedule.py).
- [x] Unlinking requires explicit confirmation explaining stopped schedule
      sharing, deletion of link notification settings and shared chat history,
      and preservation of medications and dose records. Cancel is initially
      focused; dismissal sends no request, and duplicate or stale confirmations
      cannot submit another unlink. Regressions:
      [unlink confirmation](../frontend/test/unlink_confirmation_ui_test.dart).
      October 10 live check: the new confirmation opened, and cancelling it
      preserved the relationship. Confirmed deletion is outside this live check.
- [x] October 10 live widget check: offline completion reached `2/7` and
      survived force-stop/restart; reconnect synchronized it, then undo returned
      the count to `0/7`. This checks dose-record persistence and synchronization,
      not reboot alarms or the 12-hour reminder worker.

Significant October 11 integration regressions (automated coverage, not device acceptance):

- [x] Delayed medication/chat actions cannot target newly allocated SQLite IDs;
      late push rejection matches the observed registration version, including
      same-owner re-registration. Existing rows and both migration histories
      are preserved through merge head `f2c8a6d4e901`. Regressions:
      [delayed actions](../backend/tests/test_delayed_action_regressions.py),
      [ID migration](../backend/tests/test_resource_id_migration.py) and
      [migration graph](../backend/tests/test_database_migrations.py).
      IDs deleted before the ID migration remain a rollout limitation; see
      [deployment precautions](Production%20Deployment.md#delayed-request-rollout-d19e7c4b2a60).
- [x] Cancelled or superseded picker/OCR/HTTP work cannot restore old results;
      cleared/disposed medication-save state cannot start later writes, attach
      photos or refresh a new session. Regressions:
      [prescription races](../frontend/test/prescription_input_race_test.dart) and
      [save lifecycle](../frontend/test/saved_medication_save_flow_test.dart).
      A server write accepted before cancellation is not rolled back locally.
- [x] Reminder save/cancel and reconciliation preserve ordering and session
      ownership; stale reads do not undo newer settings. Regression:
      [reminder races](../frontend/test/reminder_interaction_race_test.dart).

Reviewed for v0.2.1 (unchecked items remain deferred):

- [ ] Ranking fuzzy catalogue candidates by matched fragments raised recall on
      a synthetic catalogue from 5 to 189 of 200, but every name it moves from
      `unverified` to `llm_catalog_candidate` (0.86–0.89) stops requiring user
      review, because the client flags only `unverified` or a confidence below
      0.75. Needs a check on the production catalogue and a decision on
      review flagging. The same ranking on the local catalogue window turned
      correct automatic matches into review lists without the true product
      and must not be applied as is.
- [x] A refused chat stream is accepted and then closed with the code of its
      cause for an app that sends the `chat-close-codes` client feature (0.2.2
      and later), which reads the codes and backs off. Older apps keep the
      refusal before accept, because the 0.2.0 app resets its reconnect delay
      on connect and would reconnect every second.
- [ ] Rate-limit values that took effect in v0.2.1 (including 120 per minute
      for per-item deletes), retention of dose-sync and tombstone rows, and
      HTTP 403 wording and retry behaviour before App Check is enabled. Owner
      decisions.
- [ ] Database: 31 of 64 secondary indexes have no query that uses them, a
      stored course-end column and `pg_trgm` would need migrations.
- [x] With the medication box in selection mode, the first back press now
      ends selection only; the second returns to Home. Automated regression:
      [cabinet back navigation](../frontend/test/input_prescription_ui_boundary_test.dart).
      This exact sequence passed the October 10 final-APK live check; the
      integrated production path retains the upstream back handler.
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
- [x] Backend tests override the Redis URL and block real Redis connections,
      including explicitly constructed clients, so they cannot write to a
      developer's Redis. Regression:
      [test-environment isolation](../backend/tests/test_backend_environment_regressions.py).
- [x] UML scope is explicitly major responsibilities and contracts, not an
      exhaustive class inventory. The integrated class and overall sequence
      sources cover the significant v0.2.2 changes; minor UI fixes remain in
      tests and release notes. See the [diagram guide](UML/class/README.md).
- [ ] Class diagrams: align stereotypes and package placement between the
      overall and feature diagrams when those diagrams next change. Unchanged
      feature diagrams are not a complete inventory of v0.2.2 operations.

Defects and limits recorded during the v0.2.0 audits:

- [x] Moving a reminder to earlier than now preserves today's future old alarm;
      an unchanged snooze is also preserved. This retains the remote branch's
      no-missed-reminder policy, superseding the October 10 cancellation rule.
      Regression:
      [reminder content and cancellation](../frontend/test/medication_notification_content_test.dart).
- [x] The reminder worker overlays the same patient's current-day durable
      offline dose records without uploading them or activating an account.
      Undo/retake, partial completion, receipt races and midnight remain
      covered by [background refresh regressions](../frontend/test/medication_reminder_refresh_factory_test.dart).
- [x] "Use device language" synchronizes at startup, on runtime locale changes
      and on resume, with retry after failed lookup or save. Fixed language
      modes remain fixed. Regression:
      [runtime locale and session isolation](../frontend/test/runtime_locale_session_test.dart).
- [x] The release metadata check compares the app's default API contract
      with `backend/API_CONTRACT_VERSION`.
- [x] Weekly and interval frequencies have shared backend/client vectors:
      [backend rhythms](../backend/tests/test_medication_dose_rhythm.py),
      [client rhythms](../frontend/test/medication_dose_rhythm_test.dart) and
      [course policy](../backend/tests/test_medication_course_policy.py).
- [ ] Tests do not cover fuzzy candidate recall on a realistic catalog or a
      PostgreSQL run of the full test suite
      (CI runs only the migration round trip and two integration files on
      PostgreSQL 16). Missing ORM columns and both migration branches have
      [regression coverage](../backend/tests/test_database_migrations.py), but
      complete ORM/migration drift coverage and pinning the server strings the
      client matches remain open.

Platform and pipeline items reviewed for v0.2.1 and deferred:

- [ ] The two disabled scheduled workflows (`data-maintenance.yml`,
      `sync-drug-catalog.yml`) still create a skipped run on every schedule
      tick.
- [ ] Both CI workflows report a job named `build`. Making the names unique
      changes the required-check names and needs a branch-protection change by
      the owner.
- [x] `subosito/flutter-action`, `google-github-actions/auth` and
      `google-github-actions/setup-gcloud` are pinned to a commit with the
      version as a comment (v2.23.0, v3.0.0, v3.0.1). Regression:
      [workflow pins](../backend/tests/test_ci_workflow_pins.py). Dependabot's
      `github-actions` updates move the commit and the comment together.
      GitHub's own `actions/*` stay on major tags.
- [x] `check_release_ingress.py` requires the `X-MedBuddy-Api-Contract`
      response header. Checked against the live edge on October 11: all three
      probed routes return it with their authentication denial.
- [ ] Dependabot does not watch the `gradle` and `docker` ecosystems. Owner
      decision on pull-request volume.
- [x] The Android exact-alarm notice opens the system permission screen and
      return-to-app refresh upgrades pending alarms. Regression:
      [exact reminder notice](../frontend/test/exact_reminder_notice_test.dart).
      The upstream October 11 emulator check is recorded above; physical-device
      acceptance remains open.
- [x] `RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE` and the implied
      `READ_EXTERNAL_STORAGE`, all contributed by the camera plugin, are
      removed from the merged manifest. Regression:
      [manifest test](../frontend/test/android_recovery_manifest_test.dart).
      Checked on October 12 with a debug build on the Android 14 emulator: the
      installed package requests none of the three, the camera screen asks for
      the camera only, and a guided prescription photograph is taken and passed
      to the on-device text recognition. Capture on a physical phone belongs to
      the device verification above.
- [ ] Further APK size reduction (arm64 only, compressed native libraries, or
      per-ABI splits) changes device support or update mechanics. Owner
      decision.
- [ ] The Android instrumented tests run in no workflow; that needs an emulator
      job. A text-level contract test covers the widget names and keys instead.
- [x] App Check is explicitly a Google Play/public-release gate, with the
      limited off-Play testing exception recorded below. This is a documentation
      correction, not completion of the App Check or device acceptance gates.

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

## Google Play release blocker: restore Firebase App Check with Play Integrity

**Status:** Deferred only for direct-install functionality testing. This item
must be completed before public Google Play distribution, including a 1.0.0
release. The published off-Play betas do not close this gate.

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
- [ ] Configure Firebase App Check verdict requirements for the intended public
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
      local/demo authentication mode. Checked on October 12 between the phone
      and an emulator with the caregiver app not running (alert, snooze and
      chat action); force-stop and an FCM failure were not exercised.
- [x] Define and implement selected-message deletion: private deletion at any
      age; sender-only shared redaction before 24 hours, with server validation,
      confirmation, and retention/export semantics in [Chat Message Deletion.md](Chat%20Message%20Deletion.md).
- [ ] Verify selected-message deletion on two physical devices, including
      reconnect, offline failure, delivered previews and the 24-hour deadline.
      "Delete for everyone" was checked live between the phone and an emulator
      on October 12; the other cases were not. In selection mode only the
      checkbox reacted to a tap; a tap on the message now selects it too.
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
