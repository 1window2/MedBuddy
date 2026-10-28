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
state totals and a date-grouped plain-text message; the Android method channel
opens a text/plain chooser without creating a file. Session checks also apply
after export reads and before share. Oversized messages keep the dialog open and
ask for a shorter period rather than silently omitting records.
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
failed reads or stale sessions do not open it.
외부 텍스트 공유와 채팅 전송은 별도 사용자 선택과 기존 접근 권한 검증을 거친다.
[Feature Search](Feature%20Search.md) and its linked class/sequence diagrams.

## 채팅 알림과 공유 상세

채팅 알림은 수신 계정·연동별 서버 미확인 요약으로 갱신하고, 읽음 성공 이후
해당 운영체제 알림만 정리한다. 채팅의 복사·삭제 표시는 기존 메시지 권한과
삭제 정책을 유지한다. 공유 장소를 다시 열 때는 공유 당시 스냅샷과 별개로
수신 기기 기준의 현재 자료를 조회한다. 세부 흐름은
[채팅 읽음·알림](Chat%20Read%20State%20and%20Notification%20Entry.md),
[메시지 삭제](Chat%20Message%20Deletion.md),
[병원·약국 공유](Nearby%20Hospital%20Chat%20Sharing.md)를 따른다.

## Prescriptions and completion boundary

OCR 인식이 끝나면 중간 분석 시작 확인 없이 약품 1차 조회까지 이어진다.
`MedBuddyPrescriptionViewModel`은 인식 단계와 실제 조회 완료 건수를 분리하고,
약별로 확인 완료·후보 있음·검색 결과 없음·조회 실패·조회 전 상태를 보존한다.
전체 조회가 실패해도 인식된 약을 같은 검토 화면에 남겨 수정·재시도할 수 있다.
후보 확정과 약 저장은 자동으로 실행하지 않는다.

검토 화면의 조회 상태 요약과 결과 화면의 분석 약 개수 요약은 진입 즉시 상단에
고정한다. 중앙에서 2초 기다리거나 상단으로 슬라이딩하지 않으며 본문 탐색과
하단 동작을 막지 않는다. 모두 확인되면 결과 보기, 미확인 약이 있으면 재조회와
별도 확인을 거친 확인된 약만으로 계속 동작을 제공한다.

결과의 약별 상세와 처방 변화 레이더는 접고 펼칠 수 있다. 레이더는 처음에는
접혀 있으며 펼친 뒤 일정 변경·추가·이번 처방 미확인 분류를 선택하고, 필요한
경우 분류 불명 항목을 별도로 표시한다. 분류마다 세 건씩 넘겨 보며 한 항목의
상세를 펼친다. 이번 처방 미확인을 복용 중단으로 해석하지 않고 기존 비교·저장
권한과 개별·전체 저장 흐름을 유지한다.

약품 검색 방식은 계정별 기기 설정 `medicationSearchMode`에 보존하며
`fast`·`balanced`·`thorough` 중 기본값은 `balanced`다. 일반 설정 서버 동기화에는
포함하지 않고 약품 조회 요청의 `search_mode`로만 전달한다. 검색 범위가 달라도
후보 확인과 자동 확정의 안전 기준은 같다.
[약명 매칭과 후보 확인](Medication%20Matching%20Review.md)에 상세 기준을 둔다.

The review UI uses vertically stacked medication cards instead of a horizontally
scrolling table. Each candidate action belongs to its medication card; verified
items keep their existing edit lock and are labelled, not crossed out. Raw OCR
names remain in the model for matching/edit recovery but are not shown in the
card list. Editing, explicit candidate selection and retry use the same facade
callbacks and authorization boundaries as before.

Medication cards place the name and review status on one row, with dose/frequency/
duration and start date/time slots in two compact detail rows. Large text expands
vertically rather than clipping. Review status retains the existing unverified-name
and confidence rules. The progress screen keeps tips at the top: OCR waits use an
animated indicator, and medication lookup progress counts actual completed responses
(including unmatched/failed lookups), without counting busy retries twice or accepting
late responses after cancellation. It does not estimate remaining time.

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
