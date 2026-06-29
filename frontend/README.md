# MedBuddy Frontend

Flutter client for the MedBuddy alpha demo.

Current app version: **0.0.4+4**.

## Role

The frontend follows the same Boundary-Control-Entity structure as the project
UML diagrams:

- `lib/boundaries`: UI screens and user interaction boundaries.
- `lib/controls`: API and use-case controls.
- `lib/entities`: Flutter-side data contracts.
- `lib/viewmodels`: app state coordination for the screens.
- `lib/services`: local services such as notifications and TTS.

## Demo Scope

The v0.0.4-alpha frontend supports prescription analysis, saved medication
management, patient/caregiver scoped medication views, patient-scoped health
recommendations, local reminders, and slot-level medication completion for
multi-dose schedules.

## Common Commands

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release
```

For Android emulator testing, the default API base URL points to:

```text
http://10.0.2.2:8000/api/v1/medication
```

Override it when needed:

```powershell
flutter run --dart-define=MEDBUDDY_API_BASE_URL=http://10.0.2.2:8000/api/v1/medication
```
