# MedBuddy Frontend

Flutter client for the MedBuddy Android beta source and local demo.

Current app version: **0.0.9+9**.

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
masked regions, and users can correct medication names and confirm the
prescription date and morning, lunch, evening, or bedtime slots.

The frontend also supports saved medication management, patient- and
caregiver-scoped per-slot schedule views, patient health recommendations,
persisted medication reminders, and independent completion for multi-dose
schedules. In Firebase mode it uses authenticated APIs, manages the Android FCM
token lifecycle, and displays completed-dose pushes. The authenticated
background monitor checks missed-dose deadlines. Local demo mode uses
hash-scoped data and polling-based local caregiver notifications instead of
remote push delivery.

The experimental v0.0.9 flow presents loose-pill identification candidates
with mandatory user confirmation. It follows a separate image-analysis path
and does not save a candidate automatically or assert a diagnosis.

## Common Commands

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

## Quality Assurance

Automated widget tests cover compact viewports, large system text, accessibility
labels, app pause/resume, and network recovery. Android behaviors that require
real devices, including TalkBack, reboot persistence, battery saver, and
patient-caregiver two-device synchronization, use the
[`beta accessibility and device regression checklist`](../docs/qa/beta_accessibility_device_regression_checklist.md).

For Android emulator testing, the default API base URL points to:

```text
http://10.0.2.2:8000/api/v1/medication
```

Use the device id reported by `flutter devices`. For a physical Android device
on the same network, replace the example host with the development machine's
LAN IP address:

```powershell
flutter run -d "[your-device-id]" --dart-define=MEDBUDDY_API_BASE_URL=http://192.168.1.100:8000/api/v1/medication
```

See the repository-level [`README.md`](../README.md) for complete backend and
device setup, and [`CONTRIBUTING.md`](../CONTRIBUTING.md) for release
verification commands.
