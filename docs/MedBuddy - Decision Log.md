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

## Earlier decisions

- 2026-10-21: an as-needed dose can be undone from the save notice (the
  2026-10-20 meeting had leaned to "not needed"; see `docs/TODO.md`).
- 2026-10-21: the medication history opens on a month calendar; it is one
  commit and can be dropped before the merge if the team does not want it.
