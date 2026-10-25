# Frontend feature state isolation

The first extraction from the shared `MedBuddyViewModel` library is health
recommendation presentation state. The existing UC-10 and overall sequence remain
unchanged at the API boundary; this note refines the frontend ViewModel step in
the class and sequence diagrams.

`HealthRecommendationUI` calls the compatibility facade in `MedBuddyViewModel`.
The facade owns an independent `MedBuddyHealthRecommendationViewModel`, which
delegates requests to the existing patient-scoped `CheckHealthRecommendation`.
The control still owns API adaptation; no authorization or HTTP logic moves into
the presentation model. The parent disposes the borrowed control exactly once.

The feature model owns loading, confirmed-empty, result and message state. It is
an imported library, not a `part` extension, so it cannot access unrelated private
schedule, prescription or reminder state. Its notifications are bridged to the
existing health feature channel and parent listeners for compatibility. Health
feedback no longer overwrites the global prescription/reminder status message;
the health screen reads `healthRecommendationStatusMessage` instead.

Each request captures a generation and language. Only the newest generation may
publish a result, empty state, failure or loading completion. Disposal invalidates
all pending completions. This does not cancel server work or change backend
recommendation caching. All six feature state owners are now independent Dart
libraries. Only stateless compatibility forwarding and explicit application-level
coordination remain `part` extensions; they are not feature state owners.

Regression coverage includes reversed completion, an old failure during a newer
request, disposal, feature notification isolation, and existing health UI tests.

## Saved medications

The saved-medication feature now owns its list, loading generation and feedback
in a separate library. A compatibility-only facade forwards existing methods;
it owns no list state. Cross-feature coordination uses explicit schedule-refresh
and reminder-synchronization callbacks, preserving existing overridden methods
and refresh sequencing. Shared deletion results live outside the facade library
to avoid a circular import. Controls remain borrowed and parent-disposed.

Only the latest list request may publish. Confirmed deletion invalidates earlier
reads; clearing account data or disposing the feature also invalidates late list
and image completions. Deletions publish a saved-medication update explicitly.

Regimen edit, stop and replacement use the same feature boundary, with a separate
confirmed `MedicationRegimenEditorUI` and immutable `MedicationRegimenChange`
with a server revision/operation ID. `CheckSavedMedication.changeRegimen` adapts
the care API. The feature coalesces the same in-flight operation per medication
and rejects a different simultaneous intent. Account changes invalidate late
results. Successful changes refresh the saved list and current schedule before
reminder reconciliation; failed refresh does not undo a confirmed server write.
As-needed medications remain in the saved list but do not become automatic slots.

`MedicationHistoryUI` owns an independent patient-scoped `MedicationHistoryControl`.
It clears
stale results during reload and invalidates open edits and exports when the
authenticated session changes. Caregiver access is read-only. Explicit refresh
callbacks coordinate a confirmed correction with the existing schedule and
widget flow; the history editor does not replace the durable offline dose queue.
The same control reads a separate selected range for export without changing the
day being reviewed. Pure history model/export helpers handle Korea-time dates,
state totals and CSV escaping; the Android method channel only stages and shares
the confirmed file. Session checks also apply after export reads and before share.
See [Medication Care and History](Medication%20Care%20and%20History.md).

## Schedules

The schedule feature owns courses, loading/error state and request generations.
The facade forwards screen operations and supplies a read-only durable-queue
provider. Queue projection uses an explicit operation that does not claim a
fresh server read. Reminder reconciliation reads the feature's freshness flag;
account clearing invalidates pending reads. Slot interpretation is a shared pure
policy rather than a private helper inside prescription processing.

The facade coalesces concurrent refreshes and may reuse a successful same-day
schedule/reminder read for less than 15 seconds on tab revisits. Explicit refresh
still reads the server, and schedule changes invalidate this reuse window.

### As-needed schedule boundary

`AsNeededScheduleSection` composes a separate history-backed list alongside regular
slots. `MedBuddyViewModel.asNeededHistory` owns the patient's control for the login
session, so unresolved PRN submissions survive closing and reopening the schedule.
New PRN intentions are persisted through `AsNeededPendingStore` in the account's
encrypted store before transmission and restored for the same account after a
restart. They remain separate from the regular `DoseSyncService` background queue;
existing-report corrections and undo are not added to this pending workflow.
Each intended intake has an event UUID and a distinct operation UUID; partial
bulk success removes only acknowledged requests. The section reloads before
recording and rechecks eligibility/counts after additional-dose confirmation.
Resume, day rollover and explicit parent refresh reload the PRN data.

During an initial schedule read with no regular schedule yet, `CheckScheduleUI`
keeps the content mounted but offstage and shows one loading indicator, so the
PRN read continues without exposing a partial card. The PRN section independently
shows loading until its first snapshot or error. Later reads retain a same-day
snapshot; an error or a confirmed PRN-only day is not treated as initial loading.
Additional-dose confirmation includes today's latest intake time and elapsed
time. If the pending store is unavailable, readable counts remain visible but
new intake is blocked.

The caregiver schedule uses the same section in read-only mode with its own
patient-scoped control. It cannot write reports, read the patient's device-only
photos or restore/change the patient's local reminder. Its bell is supplied by
the parent and opens `SetCaregiverNotificationUI` for the independent `as_needed`
preference, supporting only Off or completion alerts.

## Reminders

Reminder settings and read freshness are owned by the reminder feature. Schedule
lists, schedule freshness and user settings are supplied through read-only
callbacks, not mutable sibling state. The facade retains the coordination point
for post-save reconciliation. Reminder save/rollback, privacy and snooze-preserving
refresh semantics are unchanged. Superseded or disposed loads cannot publish.

`AsNeededCheckReminderControl` owns the separate patient-scoped local PRN reminder
preference. It requests a single future booking through `NotificationService`,
not a periodic dose plan. The shared payload codec forces PRN selection to open
the schedule, with no dose action or snooze. The medication master switch and
session cleanup cancel it.

PRN caregiver delivery is separate from that local patient reminder. Production
push carries a stable per-intake event key used for the inbox and foreground
notification identity; it does not claim that all regular slots are complete.
`CaregiverNotificationMonitorService` compares server-supplied PRN event keys in
local/demo mode. Initial snapshots and re-enabling establish a baseline, and
already-seen identities remain seen after report corrections.

## User settings and application flows

Settings now own their immutable setting value in an independent library.
Persistence still uses `ManageUserSetting`; local notification policy and explicit
refresh callbacks preserve the existing save behavior. The facade reads settings
through an accessor rather than sharing a mutable field. Disposed settings reads
cannot publish or initiate subsequent refresh work.

`ManageUserSetting` owns durable synchronization, independently of presentation
request generations. Controllers in the same isolate share a per-account critical
section for local read/validate/write; HTTP waits stay outside it and other
accounts do not wait. The authoritative `user_setting_<owner>_snapshot` stores the
setting, pending token, latest intent and server revision in one JSON write before
mirroring legacy keys. Production background consumers read local snapshots only;
this is not a lock for concurrent remote writers in separate isolates.

PUT uses `expected_revision`, backed by server comparison and ORM version checks.
Only the still-current pending token may apply its ACK or retry a recognized 409,
with at most three attempts including the initial request. Late GETs recheck
pending work, intent and revision before caching. A timeout does not cancel server
work; failed sends retain the latest durable pending state for recovery.

Cross-feature recovery, account deletion and overview/schedule refresh remain
application orchestration, not settings state. The application-flow adapter
preserves the contributors' same-day 15-second schedule reuse, in-flight refresh
coalescing and explicit retry behavior. Widget publication retains configuration
deduplication while reading the isolated settings value.

After confirmed server-side account deletion, `ManageAccount` also removes that
account's snapshot, latest-intent and server-revision keys alongside pending state.
Other accounts' keys and local state after a failed deletion remain intact.

Confirmed account deletion also attempts to remove temporary Android medication
export files. The FileProvider is restricted to that cache directory; external
copies are outside the app's control. Settings shows the phone's notification and
on-time reminder switches with a test notification at the top of Medication &
Notifications (there is no separate setup-check screen since 2026-10-22), and the
factual data-use guide under Account > Privacy & Data, distinct from finalized
publication policies.

`NotificationDeviceSettings` delegates device checks to
`NotificationReadinessControl` and the existing `NotificationService`. Its switches
show the state the phone reports and open the phone's settings instead of changing
a value. Concurrent checks share one read; unavailable checks remain unknown.
Opening Settings does not request permissions. Test notifications carry no
dose/navigation payload or inbox record, and a note says that one test does not
guarantee later reminders. `DataUseInfoUI` is explanatory only:
it does not collect AI consent or enforce a transmission gate.

`ManageUserSettingUI.initialDestination` selects the existing settings category
and scroll target through `UserSettingDestination`; it does not alter the draft
or save a setting. The existing save/discard checks remain in effect. The account
welcome panel uses the same noncompact alignment as the account presentation.
`AppLanguageControl` also updates the three Android notification channel names
and descriptions through `NotificationService.updateLanguage`, retaining channel
IDs, notification bookings and the user's channel choices. Dose labels in PRN
cards and regimen confirmation use the existing display-only localization helper.
Android widget resources provide Korean/English labels and previews; runtime
record-save failure text follows the widget state's language. These presentation
changes do not rewrite stored doses or change reminder classification.

At the native scheduling boundary, date-specific plans are reconciled with
pending notifications instead of cancelling and rebuilding every slot. Unchanged
bookings and snoozes survive; scheduling, snoozing and cancellation are serialized
within the service. See the [client refresh policy](MedBuddy%20-%20Client%20Refresh%20Policy.md)
for cache scope, widget publication and recovery behavior.

## Local feature navigation

`FeatureSearchUI` owns only transient query and result presentation. `FindAppFeature`
matches 27 static `FeatureSearchEntry` destinations using Korean/English names,
aliases and intent groups; no account data, external AI or search persistence is
involved. It is not a seventh feature-state owner inside `MedBuddyViewModel`.

`HomeScreen` accepts only an explicitly selected `AppFeature`, verifies the same
ViewModel and account after returning, and reuses existing routes and controls.
Personal history remains owner-scoped even when Home displays a linked patient.
Linked-patient navigation refreshes caregiver links, selects a patient when there
are several, then reuses the existing access revalidation. Missing or failed link
reads lead to connection management, not an assumed patient or chat permission.

`MedicationHistoryUI.initiallyShowExport` opens only the existing period/target
dialog after the initial read succeeds in the same session. Read-only entry,
failed reads or stale sessions do not open it. File sharing or chat sending still
requires a separate user choice and existing authorization checks. See
[Feature Search](Feature%20Search.md) and its linked class/sequence diagrams.

## Prescriptions and completion boundary

Prescription selection, OCR review, analysis, saving progress and reset now belong
to `MedBuddyPrescriptionViewModel`. It borrows the existing controls and uses the
saved-medication feature plus explicit refresh callbacks. Settings and account
flows call its reset operation rather than mutating its fields. Request generations
reject obsolete OCR/analysis results and save completions after reset/disposal.
An already accepted server save is not undone when the screen is reset.

Prescription and reminder screens read feature-specific status messages. The old
facade `statusMessage` remains a compatibility summary, not shared feature state.
The six owners do not import the facade or share a Dart library with one another.
Their intentional dependencies are explicit; this is not a claim of zero coupling
or complete release readiness. Completed device checks and remaining acceptance
gates are tracked separately in [the release TODO](TODO.md); this note does not
claim that the new local navigation or language changes passed those checks.

This note refines feature ownership inside the existing UML facade box. The
[settings class diagram](UML/class/05_AuthenticationSettingsAccessibility.puml)
documents the persistence boundary; the
[dose and widget class diagram](UML/class/06_DoseSyncAndWidget.puml) and
[offline dose sequence](UML/sequence/OfflineDoseSync.puml) document per-account
upload ordering. Their paired PNGs are regenerated with these contracts.
