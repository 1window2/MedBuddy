# Medication Care and History

## Scope

This workflow supplements the existing schedule, chat and Android widget. Dose
records are patient reports, not proof that medication was swallowed. Medication
changes must follow the prescription or professional instructions; the app does
not select a treatment or recommend stopping one.

## Medication Lifecycle

- The pillbox exposes edit, stop and replace actions with an effective date and
  confirmation. Edit and replacement create a new regimen snapshot rather than
  rewriting the old medication's recorded doses.
- The server checks patient ownership, account state, the expected revision and
  a stable operation ID. A retry cannot apply the same change twice. A conflicting
  revision requires a fresh lookup.
- Changes take effect today or within the next 365 days, never before the
  original course begins. If the selected date or a later date already has dose
  records, edit or replacement requires a later date. Stopping today preserves
  earlier records and excludes the stopped regimen from subsequent schedules.
- A future change keeps the old regimen active until its effective date, subject
  to its original course end. The old snapshot ends before the effective date;
  the new snapshot starts no earlier than that date. Editing preserves the
  original course anchor, including non-daily dose cycles. Replacement starts a
  newly confirmed course. Renaming clears the previous product's reference ID,
  image and guidance rather than attributing them to the new name.
- The pillbox opens in the all-medications view. Stopping retains the name,
  photo, details and earlier dose records, with a stopped date shown in the list;
  a future stop is labeled as scheduled. Stopping from a filtered list switches
  back to all medications so the result remains visible. The active-only filter
  excludes effective stops, and the ended filter includes them even when the
  original course end is later. Within these pillbox actions, only the separate
  delete action removes a row; server retention and account deletion are separate.
- Scheduled and as-needed medication are explicit modes. As-needed medication
  remains in the pillbox but does not create daily schedule slots or missed-dose
  alerts. Each reported as-needed intake has its own event ID, allowing multiple
  records on the same date without overwriting the earlier intake.
  Legacy PRN directions in dose/frequency text are also recognized; general drug
  descriptions are not used to infer this mode.

## As-Needed Checks and Notifications

- The patient's schedule has a separate as-needed section. The first check each
  day records one intake immediately; later checks ask to confirm the displayed
  count increase. The bulk control records unchecked medicines first; once all
  have been checked, it confirms one additional intake per medicine. It also
  works when no scheduled medications are due. These events do not change
  scheduled-dose progress, bulk completion or reminders. The server supplies
  eligibility for the queried day; future, expired and stopped regimens cannot
  receive new checks for today. Existing reports can still be corrected.
- New checks record the current time. The history editor can correct an existing
  intake time. A failed transmission retries the same event and operation IDs;
  bulk retries retain only unresolved requests. These pending intentions live
  in the current login session, not a durable offline queue. A later, intentional
  intake receives a different event ID. Bulk recording is a sequence of
  individual requests, not an all-or-nothing transaction.
- The as-needed bell configures an optional, one-time check at the next selected
  time. It defaults off and has no missed-dose warning, automatic repeat, dose
  action or snooze button. Its neutral notification only opens the schedule.
  Local preferences are patient-scoped, and the master medication notification
  switch and session cleanup also cancel this reminder.
- The linked caregiver's daily schedule also shows an as-needed card, including
  the patient's reported count for today and available photos, even when there
  are no scheduled doses. It refreshes with the existing schedule refresh and
  keeps dose entry read-only: no dose check, bulk check or patient reminder controls.
  Its bell opens the same caregiver notification settings as regular slots, with
  only Off and notification on a newly recorded dose. No missed-dose deadline is
  offered for as-needed medication. Settings are scoped to the caregiver-patient
  pair and default to Off; enabling a regular-slot alert does not enable this one.
  Each distinct intake can notify, while retries, time-only corrections and
  uncheck/recheck of the same report do not create another event. The server
  rechecks the report, link and preferences before push delivery. Local demo
  polling tracks new report identities without replaying the first snapshot or
  reports recorded while alerts were off. Device-only
  photos are not transferred to the caregiver; an unavailable photo uses the
  usual placeholder. As-needed counts do not inflate scheduled-dose progress.

### Caregiver Delivery and Deduplication

A transition to `taken` for today's PRN record queues `as_needed_dose_completed` in
`caregiver_alert_outbox` in the same transaction as the report, audit and care
operation receipt. The stable event key hashes patient, medication, scheduled
date and `as_needed:<UUID>`; it excludes actual intake time and revision. Past
corrections do not generate a new event. This is distinct from the aggregate
scheduled-slot completion event and does not create an automatic chat message.

The router requests immediate processing after commit; the existing outbox worker
recovers and retries pending delivery. Dispatch checks that the record is still
taken on the current Korea date, the link is active, the PRN preference explicitly
allows completion alerts, the caregiver's master switch permits them and a push
token exists. Expired, undone or deleted records are not delivered. Exhausted or
no-longer-current events retain the outbox's terminal state for inspection.

Push uses `caregiver_dose_completed`, `slot_key=as_needed` and `event_key`.
The client uses this event identity for the local inbox and foreground alert;
Android push tags also reuse it. Different intakes keep separate identities.
This deduplicates repeated delivery displays, not a guarantee of exactly-once
network delivery. Opening the alert navigates to the linked patient's schedule.

## History and Corrections

- Calendar icons in patient and linked-caregiver schedule headers open medication
  history. Only the patient can write; linked caregivers have read-only access.
- New intake is recorded from the schedule, not from history. History provides
  daily review, correction of existing reports and period export; correcting an
  as-needed report preserves the original event ID.
- A query covers up to 31 days within the last 90 days. This is a lookup limit,
  not a promise that records are deleted after 90 days. The independent
  `SAVED_MEDICATION_RETENTION_DAYS_AFTER_END` setting defaults to zero (automatic
  cleanup disabled); enabling it can remove ended courses and their related
  reports. Versioning does not promise indefinite retention after deletion.
- States are taken, skipped and unrecorded. Unrecorded does not mean not taken;
  skipped is not counted as taken. Reasons and corrections are retained in the
  server audit trail.
- Marking a report skipped does not turn off the existing dose or missed-dose
  reminders. The schedule and widget still regard it as incomplete; a report is
  not an instruction to stop the prescribed regimen.
- Actual intake time and server recording time are separate. Earlier legacy
  records do not invent an actual intake time. Dates and displayed timestamps use
  Korea time (UTC+09:00); future intake times are rejected.
- An intake can occur after its scheduled date. Correction does not silently move
  that record to another scheduled dose.
- The existing completion, undo, chat and offline-sync paths update the same
  report state. A history write is confirmed only after the server acknowledges
  it; this editor is not a second offline queue.

## Ownership and API Contracts

`api/medication_care_router.py` is a thin boundary under the authenticated router.
`ManageMedicationCare` resolves patient scope, checks active accounts, locks the
medication and coordinates the shared course policy and report-recording helper.
Caregivers can query only actively linked patients; writes remain patient-only.

| Endpoint | Contract |
| --- | --- |
| `POST /care/medications/{id}/change` | Confirmed `edit`, `stop` or `replace`, effective date, expected regimen revision and operation UUID. |
| `GET /care/history` | Inclusive start/end dates and authorized patient scope; combines persisted reports with due scheduled slots, but synthesizes no PRN slots. |
| `PUT /care/history/{id}/{date}/{slot}` | Report status, actual time when taken, optional reason, expected report revision and operation UUID. PRN uses `as_needed:<UUID>` as the slot. |

An identical successful operation replays its original response. Reusing an
operation ID for different content or writing an outdated revision returns a
conflict. `medication_care_operations` stores successful receipts;
`medication_care_audits` stores before/after snapshots. Both are committed with
the underlying change. The history API returns current report state, not an
audit-browser view. These are not a new source of clinical verification.

## Export and Data Use

The daily history screen summarizes statuses for the day being viewed. Its
export dialog separately offers start/end dates, the allowed range and a short
health-data notice; it does not display a selected-period summary or status
counts. Changing these dates does not fetch export records or change the day
being reviewed.

Selecting Share CSV triggers `readRangeForExport` to fetch the selected period
with current access and session checks. A failed read leaves the dialog open for
retry. Only a successful read with the same session and active dialog closes it;
the screen rechecks the session before generating CSV and invoking native sharing.
The CSV itself includes the selected-period metadata and status counts, followed
by self-reported records and details of medications represented in that period,
but not unrelated medications or internal account identifiers. Cancelling before
sharing sends nothing through MedBuddy. Opening the Android chooser is not
evidence that another app delivered the file.

CSV is UTF-8 with a BOM; cells are quoted and spreadsheet-formula prefixes are
escaped. Android shares a temporary content URI through a non-exported
FileProvider limited to the medication-export cache directory. Older cache files
are cleaned on later exports;
account deletion also attempts cleanup. Copies saved by another app cannot be
recalled. Unsupported platforms offer CSV-text copying after separate consent;
the app does not claim that a file was saved or shared.

Settings > Account > Privacy & Data includes a data-use guide covering
authentication, medication data, on-device OCR, external AI processing, caregiver
sharing, location, cached data and deletion. It is not a finalized publication
privacy policy or an AI-consent flow. User-facing text explains deletion scope
and the unpaid-AI restriction,
without instructions addressed to the operator. Unpaid-AI warnings are not
technical transmission gates; production health-data use requires resolving
the provider terms and applicable processing requirements first.

## Setup and Notification Check

Settings > Medication & Notifications provides a setup/notification check; the
home dashboard keeps its existing four action cards without a separate check
shortcut. It shows medication setup, notification permission, schedule settings,
exact-alarm availability and useful widget/caregiver entry points. Opening the
screen does not request permission automatically.

The check distinguishes app-level permission, medication-channel permission and
exact-alarm availability. Failed or unsupported checks remain unknown or
unsupported rather than reporting success or claiming that no medication exists.
Permission requests remain explicit user actions. After exact-alarm permission
is granted, the existing service upgrades eligible inexact reminders.

The test alert uses the medication notification channel but has no dose action,
no medication navigation payload and no inbox record. The screen distinguishes
requesting a test alert from the user confirming that it appeared. Device battery
policies and operating-system restrictions can still delay real reminders.

## Deployment

Apply migration `c8d3e7a92104` before deploying the backend that reads the new
regimen/report fields. Upgrade the backend before distributing the matching app.
The migration keeps existing medications and completions; unknown actual intake
times remain unknown. Back up the database before applying or rolling back schema
changes. Downgrading removes new history metadata and is not a lossless undo;
also review PRN scheduling before returning to an older app/backend.

Related design: [Medication classes](UML/class/03_MedicationManagement.puml),
[caregiver classes](UML/class/04_CaregiverNotifications.puml),
[settings classes](UML/class/05_AuthenticationSettingsAccessibility.puml),
[medication care sequence](UML/sequence/MedicationCareHistory.puml) and
[as-needed delivery sequence](UML/sequence/AsNeededCaregiverNotification.puml).
