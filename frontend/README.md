# MedBuddy Frontend

Flutter client for the MedBuddy Android beta source and local demo.

Declared app version: **0.1.0+11**. Active development line:
**`beta/v0.2.0`**.

## Role

The frontend follows the same Boundary-Control-Entity structure as the project
UML diagrams:

- `lib/boundaries`: UI screens and user interaction boundaries.
- `lib/controls`: API and use-case controls.
- `lib/entities`: Flutter-side data contracts.
- `lib/viewmodels`: app state coordination for the screens.
- `lib/services`: local services such as notifications and TTS.

`MedBuddyViewModel` remains the screen-facing state facade, while its behavior
is organized into feature-scoped parts for prescription analysis, saved
medications, schedules, reminders, health recommendations, and user settings.
Large UI boundaries keep route and screen state ownership in their primary
files and move repeated list, empty-state, image-preview, and medication-row
widgets into companion parts. This preserves the existing public screen API
while limiting the change scope of each feature.

## Current Scope

Prescription input uses on-device Google ML Kit Korean OCR. Before the
prescription-text request leaves the device, the privacy filter removes
sensitive lines and masks inline identifiers. The preview shows recognized and
masked regions, and users can correct medication names, manually add an
OCR-missed medication row, and confirm the prescription date and morning,
lunch, evening, or bedtime slots. Medication-detail responses preserve their
original OCR-row identity. If only some rows fail, verified rows are locked and
struck through while unresolved rows remain editable and are retried alone.
The guided camera adapts its document frame to portrait or landscape use and
crops app-owned captures to the confirmed guide region before OCR. After
prescription analysis, users review and can correct the start date, course
duration, daily frequency, dose, and schedule slots before continuing.
Analysis and medication-lookup failures are converted into actionable messages
for connection, timeout, response-data, and OCR review cases. Depending on the
failed step, users can retry the analysis, return to OCR review, retake the
photo, choose another image, or explicitly confirm continuing with verified
medications without restarting the entire flow.

The guided prescription camera uses one shared guide rectangle for both the
screen overlay and the captured-image crop. After a successful capture, only
the area shown inside the guide is retained and passed to on-device OCR; the
uncropped app-created camera file is removed. Gallery images remain owned by
the user and are never deleted by this flow.

The frontend also supports saved medication management, patient- and
caregiver-scoped per-slot schedule views, patient health recommendations,
persisted medication reminders, and independent completion for multi-dose
schedules. The home card exposes the next medication slot and daily progress,
while the saved list supports active/completed filters, registration- or
medication-date sorting, and ascending or descending order. Successful
all-medication saves link directly to today's schedule or the saved list. Dose
completion supports immediate undo, and reminder setup or cancellation reports
its result at the bottom of the schedule screen. In Firebase mode the frontend
uses authenticated APIs, manages the Android FCM token lifecycle, and displays
completed-dose pushes. The authenticated background monitor checks missed-dose
deadlines. Local demo mode uses hash-scoped data and polling-based local
caregiver notifications instead of remote push delivery. Each polling cycle
prefers one aggregate caregiver snapshot for all linked patients and falls back
to bounded per-patient requests when connected to an older backend. Patient
aliases are synchronized on the caregiver-owned server link and cached locally
for offline display.

The experimental loose-pill flow introduced in v0.0.9 presents identification
candidates with mandatory user confirmation. The v0.2.0 frontend can collect
up to ten separate pill photo sets and processes at most two sets concurrently,
preserving successful candidates when another set fails. Rate-limited items
honor the server's bounded retry delay and retry independently while the UI
reports completed and waiting counts. It follows a separate image-analysis
path, does not save a candidate automatically, and requires a schedule review
before a confirmed candidate is stored.

Direct medication entry supports an optional locally owned medication image,
name, dose and unit, start and end dates, and schedule slots. It produces the
same saved-medication contract used by analyzed medications, so schedules,
reminders, caregiver views, and filtering do not branch into a second storage
model.

The nearby-pharmacy laboratory flow requests foreground location only when
opened, calls the authenticated MedBuddy pharmacy endpoint, and defaults to
pharmacies that are open now. One explained filter sheet offers open-now,
late-hours, weekend/holiday, and all-result views. The late-hours view combines
official public late-night designations with reported late operating hours,
while date-based views ask for a date without requiring a time. Filters are
applied by the backend before its result limit. A Naver Map view is rendered
above the filter. Selecting a pharmacy card or map marker
updates one shared selection and centers the map. Device-scoped favorites are
applied after open and late-hours pharmacies are prioritized, and each
card distinguishes closing-soon, next-opening, and catalog-refresh information. A pharmacy's
24-hour operating status remains available as card information. Public-data
credentials remain on the backend; the client only receives the pharmacy
fields needed for display, calling, mapping, and external directions. Manual
refresh is throttled in the UI to avoid accidental repeat traffic, and the map
keeps Naver attribution visible. Phone, exact-coordinate directions, map
attribution, and pharmacy sharing use one validated external-action boundary.
If the Naver client identifier is absent, the screen explains the map setup
state while retaining the pharmacy list and actions.
The source notice distinguishes exact-date holiday schedules from stale or
weekly fallback data and tells users to call before visiting.

The linked medication chat laboratory flow is available only for an active
patient-caregiver link with active patient medication. The screen combines
authenticated REST history with a reconnecting WebSocket event source, lets a
participant select and remove multiple medication contexts through the same
time-slot layout as today's schedule, and opens the authorized medication-detail
screen when an attached medication card is pressed. Quick replies use separate
patient and caregiver wording. A patient can press a schedule context to open
today's schedule at that slot, while caregiver schedule cards remain read-only.
Client message identifiers provide retry-safe
sends, reads are tracked per participant, and local or push notifications show
a whitespace-normalized message preview capped at 120 characters. The server
also provides verified time-slot schedule cards and stores structured check
requests, slot-completion events, medication-shortage or discomfort reports,
and pharmacy shares as typed snapshots. Caregiver check-request notifications
open the corresponding schedule slot, and repeated completion processing does
not create duplicate completion messages.

Medication detail and today's schedule share one full-screen image viewer. A
validated public medication image can be tapped to inspect it with pan and zoom
without duplicating image-loading policy in each screen.

Settings starts from an account-aware hub that separates Medication &
Notifications, Display & Voice, Labs, and Account actions. The account summary
masks email or phone details, and moving between sections preserves unsaved
choices. Users can independently control medication, caregiver, and chat
notifications, open Android notification settings, set defaults for newly
created morning/lunch/evening/bedtime schedules, and limit lock-screen content
to the notification type. Existing schedules retain their confirmed times.
Font-size and device/Korean/English language choices preview immediately while
Settings remains open, and the time display can use either 12-hour or 24-hour
formatting. Saving persists the complete settings contract without closing the
screen. A fixed back button remains in the same position while each settings
section scrolls. Stopping a TTS preview intentionally is handled as a normal
action rather than a playback error.

## Common Commands

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

## Quality Assurance

Automated widget tests cover compact viewports, large system text, accessibility
labels, app pause/resume, network recovery, guided-camera layout and crop math,
manual-entry validation, schedule review, multi-pill ordering and partial
failure, pharmacy location states, linked-chat retry and lifecycle behavior,
and laboratory feature visibility. They also verify the home
schedule summary, OCR-review recovery, post-save navigation, medication-course
filtering and sorting, dose-completion undo, and reminder result feedback.
Android behaviors that require real devices, including TalkBack, reboot
persistence, battery saver, and patient-caregiver two-device synchronization,
use the
[`beta accessibility and device regression checklist`](../docs/qa/beta_accessibility_device_regression_checklist.md).

The Android application defaults to the production API endpoint:

```text
https://api.medbuddy.pp.ua/api/v1/medication
```

Use the device id reported by `flutter devices`:

```powershell
flutter run -d "[your-device-id]"
```

ADB debugging, Flutter hot reload, breakpoints, and physical-device testing do
not require the backend to run on the development computer or on the same LAN.
The Android client reaches the production backend over ordinary HTTPS.

`MEDBUDDY_API_BASE_URL` remains a compile-time value. Profile and release
builds require a public HTTPS endpoint ending in `/api/v1/medication`. Debug
builds may use the local demo backend only when
`MEDBUDDY_ALLOW_LOCAL_HTTP=true`; accepted hosts are `10.0.2.2`, `127.0.0.1`,
`localhost`, and `::1`, all on port `8000`. Other private-network and
clear-text endpoints are rejected.

See the repository-level [`README.md`](../README.md) for complete backend and
device setup, and [`CONTRIBUTING.md`](../CONTRIBUTING.md) for release
verification commands.
