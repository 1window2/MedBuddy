# MedBuddy Decision Log

Decisions that were a judgement call rather than a clear defect. Each entry says
what was chosen, why, what the alternative was, and how to undo it, so the team
can revisit a choice that later feels wrong.

## 2026-10-23: four follow-ups of the review of the 2026-10-22 commits

Decided by the project owner on the recommendation of the review, on
`beta/v0.2.4`. Implemented in the commit that adds this file.

### 1. A failed medication change keeps the offline schedule

- **Before:** changing, deleting or stopping a medication cleared today's
  schedule and the 14-day offline window before the request and again after
  it, whatever the outcome. Trying it offline left nothing to record until the
  server answered.
- **Now:** the schedule is still cleared while the request runs (so nothing is
  recorded against it meanwhile), but the cleared copy is kept. If the server
  did not apply the change (network failure, invalid request), the copy is put
  back, provided nothing else was stored for the account in between; otherwise
  it stays cleared as before. A change that was applied, or a conflict / missing
  result, still clears it. An exception, whose outcome is unknown, also clears it.
- **Why it is safe:** a request can fail after reaching the server (a lost
  response), so the app cannot know for certain that nothing changed. The
  server already refuses an offline dose whose regimen revision changed and a
  dose for a deleted medication, so a schedule restored after such a change can
  at worst produce a dose that shows as blocked, never a wrong record.
- **Alternative:** keep clearing after every attempt (safest against a stale
  screen, unusable offline).
- **Undo:** in `MedBuddySavedMedicationViewModel._changingRegimen`, call
  `invalidateSchedule` in the `finally` block regardless of `applied`, or stop
  passing `suspendSchedule`/`restoreSchedule` from `MedBuddyViewModel`.
- **Code:** `dose_offline_schedule_store.dart` (`suspendDoseSchedules`,
  `restoreDoseSchedules`), `dose_sync_service.dart` (`suspendSchedule`,
  `restoreSchedule`), `medbuddy_saved_medication_view_model.dart`.

### 2. The as-needed card stays visible when the local pending store fails

- **Before:** the card loaded the unconfirmed doses from the encrypted device
  store first; if the store could not be opened, the whole card failed to load.
- **Now:** the list and today's counts are shown from the server, and only a
  new dose is refused with "기기 저장소를 열 수 없어 지금은 기록할 수 없어요. 앱을
  다시 시작해 주세요." The next tap tries the store again.
- **Why:** recording while the store is unreadable could send a second dose next
  to an unsent one that is still in the store. Showing the list costs nothing.
- **Alternative:** record anyway (risk of a duplicate dose), or keep the card
  unavailable (no information at all).
- **Undo:** remove `_restorePending` and `_pendingStoreUnavailable` from
  `as_needed_schedule_section.dart`, calling `restorePendingAsNeeded` directly.

### 3. The phone notification switch shows off when medication alerts are off

- **Before:** with app notifications allowed but the medication channel turned
  off on the phone, the switch showed on and only the subtitle said
  "복약 알림 꺼짐".
- **Now:** the switch shows off in that state; the subtitle is unchanged and a
  tap still opens the phone settings.
- **Why:** older users read the switch, not the subtitle. A switch that looks on
  while medication alerts cannot arrive is the more dangerous misreading.
- **Alternative:** show the app-level permission as it is (the original design).
- **Undo:** `value: snapshot?.notifications` in
  `notification_readiness_ui_boundary.dart`, and the test expectation back to
  `isTrue`.

### 4. CSV export covers up to 90 days, with tidier columns

- **Before:** one export covered at most 31 days, so a one- to three-month visit
  interval needed several files. The record table had an internal "기록 버전"
  (revision) column and called the first column "예정일" even for as-needed
  doses, which have no scheduled date.
- **Now:** a CSV can cover any period within the 90-day history; the app reads it
  in 31-day parts (the server's limit per request) and merges them, newest
  first. Chat sharing stays limited to 31 days because the server builds that
  summary in one request; the dialog explains this and disables only the chat
  button for longer periods. The revision column is gone and the first column is
  "날짜 (필요시는 기록일)".
- **Why:** a doctor's visit usually looks back one to three months, and the
  revision number meant nothing to a reader of the file.
- **Alternative:** keep 31 days and let users export several files.
- **Undo:** in `MedicationHistoryControl.readRangeForExport` read one range with
  `readRange`, use the default `validate` limit in the export dialog, and restore
  the columns in `medication_history_export.dart`.

## 2026-10-29: review of the final feature commits

### 1. The CSV export path is removed

- **Before:** after the switch to readable text sharing, the CSV builder, the
  Android `shareCsv` handler and its FileProvider stayed in the app "for
  compatibility".
- **Now:** they are removed. The Dart caller and the Android handler ship in
  the same APK, so nothing can still call them. Account deletion still clears
  the export cache that earlier builds may have left.
- **Undo:** restore them from `edf1262` (`medication_history_export.dart`,
  `MainActivity.kt`, the manifest provider and `medication_export_paths.xml`).

### 2. Unknown rather than "not open yet" for live-only pharmacy hours

- **Before:** a pharmacy shared from the live lookup (not in the catalog) had
  only today's hours; after midnight an overnight pharmacy read "영업 전".
- **Now:** without yesterday's hours, a time before today's opening is shown
  as "운영 확인 필요"; "영업 종료" after today's closing stays.
- **Alternative:** look up yesterday's hours too (one more external call per
  share).

### 3. The search-mode control stays as the collaborator made it

- The setting shows a slider and three buttons for one value (four controls
  for a screen reader), while the reading-speed setting uses the common
  choice sheet. The user decided not to revert the collaborator's design.
- **Alternative:** the common choice sheet (`_buildSettingChoice`).

### 4. Cabinet date groups open while searching

- **Before:** a date group the user had collapsed stayed collapsed during a
  search, so a match showed only as "2026-10-29 · 1개".
- **Now:** while a search is active every group with a match is open; groups
  collapsed during the search are remembered only until the search changes,
  and the user's own collapsed groups return when the search is cleared.
- **Why:** a search is for finding a medicine by name; an extra tap to see
  the match defeats it, especially for older users.
- **Undo:** use `_collapsedDateGroups` for both cases in
  `check_saved_medication_ui_boundary.dart`.

## 2026-10-31: review of the v0.2.5 collaborator commits

### 1. An as-needed medicine in the chat selection blocks "taken"

- **Before:** the medicines with a slot were recorded and the as-needed one was
  left out without a word; with only as-needed medicines the message said no
  schedule was found.
- **Now:** nothing is recorded, and the message points to the schedule's as-needed
  section. A partial write that looks complete is worse than a refusal.
- **Alternative:** record as-needed doses from chat. That is a new feature with
  its own undo and caregiver alert rules, so it is not part of this review.
- **Undo:** remove the `asNeededSelected` check in `LinkedChatDoseRecorder.plan`.

### 2. More wording counts as urgent in department search

- **Before:** nine fixed phrases; "호흡곤란" or "가슴이 아파요" found no department
  and no 119 notice.
- **Now:** explicit emergency wording shows emergency medicine and the conditional
  119 notice, and so does a search with no result. Chest pain leaves out
  internal medicine on purpose: the app must not steer it to a routine visit.
- **Alternative:** keep the short list and list departments for chest pain.
- **Undo:** edit the list in `FindHospitalDepartment.needsUrgentHelp` and the
  `results.isEmpty` condition in `hospital_department_sheet.dart`.

### 3. Two notices stay removed

- **Decided by the project owner** after comparing both screens with and without
  the text: the note that unrecorded does not mean not taken on the chat history
  card, and the note that one test notification does not guarantee later alerts.
- **Why:** the screens read better without them. This overrides the 2026-10-23
  review, which had restored both, so a later review should not reopen it.
- **What remains:** the record wording stays in the text shared to other apps and
  in the user guide, and the user guide still covers test notifications.
- **Undo:** restore the `chat-history-unrecorded-notice` text in
  `linked_chat_ui_boundary.dart` and `notificationSettingsTestLimitations` in
  `notification_readiness_ui_boundary.dart`, and their test expectations.

## 2026-11-01: opening the dose store from two Flutter engines

Chosen after the schedule stalled on the phone. Details are in the
[v0.2.5 notes](releases/v0.2.5-beta.md).

- **Chosen:** a gate on `IsolateNameServer` makes engines in one process open the
  store in turn, which keeps sqflite's single shared connection.
- **Alternatives:** more sqflite threads (`androidThreadCount`) is a dev-only
  option, and a task of another connection can still land on the thread a
  transaction is pinned to, so the stall stays possible. Skipping background work
  while the app runs needs a check at every background entry point, and an app
  started just after a task would still race it.
- **Trade-off:** an engine that stops while opening leaves the gate taken, so the
  next engine takes it over after 5 seconds. If the first engine was only slow,
  the two opens can overlap, which is the old behaviour rather than a new failure.
- **To undo:** pass the database opener directly in `DoseOutboxStore.openWith`.

## 2026-11-04: Korean text wraps by word

Chosen in the large-text review after the project owner compared screenshots.

- **Chosen:** `KeepWordsText` paints the text with invisible word joiners
  between the letters of each Korean word, so lines break only at spaces. The
  span's semantics label keeps the original text for screen readers, finders and
  copies.
- **Alternative:** Flutter has no `word-break: keep-all`, and changing every
  `Text` in the app would touch about 680 widgets and 1,400 test finders. The
  joiner only changes the widgets that hold descriptions and names.
- **Limits:** a word longer than the line still breaks. Selectable text should
  not use it, because selection offsets would count the joiners.
- **To undo:** replace `KeepWordsText(` with `Text(` in the files that import
  `keep_words_text.dart`.

## 2026-11-04: chat + menu as a list

- **Decided by the project owner** from emulator screenshots: a full-width list
  with one choice per line, instead of the collaborator's row of icons made full
  width.
- **Why:** the list keeps each label on one line at the large text size and
  shows the reason under a disabled choice.
- **To undo:** restore the icon row in `_ChatActionSheet.build`.

## 2026-11-04: one source for reminder wording

Chosen in the review of the 2026-11-04 commits. Details are in the
[v0.2.5 notes](releases/v0.2.5-beta.md).

- **Chosen:** `medication_reminder_text.dart` holds the reminder title and body.
  The notification service schedules with it, and the inbox compares stored
  entries with it to show them in the current language.
- **Alternative:** keep the inbox's own copy and a test that compares the two.
  The copy would still have to be edited by hand at every wording change.
- **Kept:** wording the app no longer produces stays as it was stored.
- **To undo:** put the strings back in `NotificationService._scheduleWithMode`
  and in `ManageNotificationInbox`.

## 2026-11-04: a past-day reminder is corrected in the history

Chosen in the 1.0.0 readiness review. Details are in the
[v0.2.5 notes](releases/v0.2.5-beta.md).

- **Chosen:** "taken" on a reminder of an earlier day still records nothing, and
  the message now names that day and points to the history. Yesterday's reminder
  that is still pending in the first hour of the day (a snooze before midnight)
  is not cancelled by a refresh of the new day. Older pending reminders are
  alarms Android dropped, and the plugin would re-arm them all at the next
  reboot, so they are cancelled (corrected on 2026-11-06).
- **Alternative:** record the earlier day from the notification. The server
  accepts earlier days, but the app only holds today's slot list, which may name
  other medicines than that day's; it would need that day's list first.
- **To undo:** restore the message in `_performMedicationNotificationAction` and
  remove `_mayBeLiveSnoozeFromYesterday` from the stale-reminder loop.

## 2026-11-06: reminder quick actions are signed

Chosen in the security audit after an emulator test showed another app could record
a dose through the exported launcher activity.

- **Chosen:** the app signs each reminder payload with an HMAC key kept in its own
  preferences, bound to the account, and runs "taken" or "remind in 10 minutes" only
  when the tag matches. A missing or wrong tag opens the schedule instead.
- **Alternatives:** a nonce stored per notification (more state, and snoozes would
  need their own); routing actions through a non-exported receiver (the plugin then
  runs them in a background isolate without the app's session); Android 16's
  `intentMatchingFlags` (also blocks the plugin's own action intents and does not
  cover older phones).
- **Trade-off:** reminders already scheduled by an earlier build have no tag, so their
  buttons open the schedule until the app re-arms them on its next start.
- **To undo:** remove the `MedicationReminderActionTag.verify` check in
  `_performMedicationNotificationAction` and the tag in
  `NotificationService._scheduleWithMode`.

## 2026-11-06: limits on public-API and pill-upload work

- **Chosen:** a process-wide daily budget for pharmacy location lookups (800, like the
  hospital API of the same provider), a cap of 12 pill uploads in flight, and a limit
  of 100 scans per JPEG.
- **Not chosen:** a budget for the MFDS drug lookups. Their quota on the production
  key is not known, and a wrong default would refuse real lookups; it waits for the
  owner's reading of the data.go.kr console.
- **To undo:** raise `PHARMACY_API_DAILY_REQUEST_BUDGET`, `_PILL_UPLOADS_IN_FLIGHT_LIMIT`
  or `MAX_PILL_JPEG_SCANS`.

## 2026-11-06: the 1.0.0 release candidate line

- **Chosen:** branch `beta/v1.0.0` from `main` after `v0.2.5-beta`, app version
  `1.0.0+27`, server version `1.0.0-rc`. The off-Play exception of the signed
  workflow moves to this branch so that candidate builds can be installed over the
  betas.
- **Alternatives:** a `release/1.0.0` branch (CI and the deploy workflow match only
  `main` and `beta/**`); keeping 0.2.x numbers for the candidates.
- **To undo:** rename the branch and the references in `release-android.yml`,
  `scripts/check_android_release_configuration.py` and their tests.

## 2026-11-07: owner decisions for 1.0.0

- **Distribution:** 1.0.0 goes to Google Play and stays available as a GitHub APK.
  App Check with Play Integrity therefore blocks 1.0.0, and the GitHub APK needs its
  own way through App Check before the server requires it.
- **Crisis wording in department search:** no special handling.
- **Chat notification default:** the message preview stays the default; recipients
  can switch to type only.
- **A tap on yesterday's list after midnight:** refused. Nothing is recorded, today's
  list is loaded and the user is asked to tap again. Reminder actions pass their own
  day and are unaffected. To undo: remove `_refuseTapOnEarlierDayList` in
  `medbuddy_schedule_view_model.dart`.

## 2026-11-07: data-only database role

- **Chosen:** an opt-in role (`MEDBUDDY_APP_DB_USER`, `MEDBUDDY_APP_DB_PASSWORD`)
  that the migration provisions with data rights only; the API and catalog jobs use
  it once both settings exist, and the owner role until then.
- **Alternatives:** switching at once (needs a new secret on the host before the
  next deploy); row-level security (no tenant column common to all tables).
- **To undo:** remove both settings and redeploy.

## 2026-11-07: English developer text in the Korean UI

- **Chosen:** a `StateError` whose text is not Korean gives the Korean UI the generic
  message; the English UI still shows the text.
- **Alternative:** translating every developer message (many are never shown).
- **To undo:** remove the `_isKoreanSentence` check in `UserFacingErrorMessage.resolve`.

## 2026-11-07: per-IP daily quota after sign-in

- **Chosen:** the per-IP daily quota (20 times the account quota) is counted in the
  authentication dependency, after the account is verified, instead of in the
  middleware. Unauthenticated requests leave only the per-minute address counter.
- **Why:** the second security audit showed that day-long counters written before
  sign-in let unauthenticated addresses fill the 128 MB noeviction counter store, and
  a full store makes the limiter answer 503 to everyone. The daily quota exists to
  bound spending by signed-in accounts, which an unauthenticated request cannot do.
- **Alternatives:** eviction in the counter store (a full store would then reset
  quotas instead of refusing requests); a larger store (raises the bar only).
- **To undo:** move the `enforce_address_quota` call in `get_registered_principal`
  back into `RequestRateLimitMiddleware`.

## 2026-11-07: findings of the second audit left to the owner

- **Hospital budget:** one free account can spend the shared hospital API budget
  inside its own daily search quota. The provider's operating-account quota is the
  real fix; a per-call share per account would also limit ordinary users, so no code
  change was made.
- **Database pool:** same-account requests waiting for the account lock hold pooled
  connections for up to 5 s. The audit rejected it as a finding (any client with
  several requests in flight fills the pool too), so the PostgreSQL lock path was not
  changed without a PostgreSQL concurrency test.
- **Anonymous-era accounts:** a link or push token created before a uid proves an
  email carries over to whoever proves it later. The fix (an identity epoch per
  account) changes sign-up behaviour and waits for the owner's decision.

## 2026-11-07: searched medications in chat are rebuilt on the server

The owner chose server verification of searched-medication cards. The server keeps
only public product fields per item number for 24 hours, as the shared-pharmacy cache
does, rather than a per-account record of what each user searched: that would be new
health-related personal data, and per-item public data is enough to stop a sender from
choosing the name, manufacturer or picture. A card whose item no search returned in
the last day is refused; results from the live public API work because the search
stores whatever it returned, not only catalogue items.

## 2026-11-07: launch work moved off the start-up path

The collaborator suggested replacing the native Naver map SDK with the web map in a
WebView to shrink the APK. Both are billed as the same Dynamic Map item (6,000,000
free calls a month for the representative account), and a smaller APK does not make
the app start faster: native libraries are stored uncompressed and mapped on demand.
The WebView map would make each map screen slower to open (WebView start-up and the
map script) and would need the map screens rewritten, so the native SDK stays.

Measuring the launch showed two costs that had nothing to do with APK size. `main()`
awaited the map SDK initialization, which loads its native library, before the first
frame; it now starts after the first frame and the map screens await the same attempt.
The `flutter_tts` plugin created `TextToSpeech` when attached to any Flutter engine,
including the WorkManager and home-widget engines, and on connection read every voice
of the engine on the main thread. It is replaced by a small app channel that binds the
engine on the first read-aloud request and keeps the same rates, ranges and audio focus.
The `SystemChrome` portrait call repeated the manifest's `screenOrientation`.
On a Galaxy Note10 the median cold launch went from 378 ms to 336 ms (24 runs each,
release builds under a separate test package). Emulator launches looked far slower
because of shader compilation in emulated GL, which a phone does not show.

## 2026-11-08: revocation state reused for 30 seconds

The owner accepted that a session revoked in Firebase (password reset, console
disablement) may keep working for up to 30 seconds, in exchange for removing the
Firebase account lookup from every authenticated request. Signature and expiry are still
checked on every request, the revocation rule is unchanged (disabled account, or token
issued before the account's sessions-valid-after time), and an account deleted by this
server is dropped from the cache at once; a lookup that started before the deletion is
not stored. The compose file pins the value so a typo cannot lengthen it, and the code
caps it at 60 seconds.

For link polling only the low-risk part was taken: the home screen's 15-second link
read pauses while another screen covers home. Slowing the poll for users without links
was left out, because the patient-code dialog has no refresh of its own and a new link
would show on the patient's home up to a minute later.

## 2026-11-08: the 15-minute dose-sync job only while network work remains

The owner chose to keep the periodic dose-sync job only while records wait or the
widget needs today's data, provided two risks are designed out and tested: a queued
record left without background delivery, and a widget left on a past day. Records:
every path that queues one registers the one-off upload (retrying a rejected record
now does too), the app start, pause and resume reconcile the jobs, and removal is
followed by a second read so a record queued meanwhile gets its jobs back. Widget: a
widget-started refresh that still lacks today's data registers the retry, which
fixes the widget once a connection returns. The periodic job stays while the
condition holds, so the 15-minute cadence remains as a backstop to the one-off job's
growing back-off. One gap remains by design: a periodic run that removes itself is
stopped by WorkManager at once, so it cannot read again afterwards; a record queued in
that instant still has its own one-off upload, and the next app start restores the
periodic job.

## Earlier decisions

- 2026-10-21: an as-needed dose can be undone from the save notice (the
  2026-10-20 meeting had leaned to "not needed"; see `docs/TODO.md`).
- 2026-10-21: the medication history opens on a month calendar; it is one
  commit and can be dropped before the merge if the team does not want it.
