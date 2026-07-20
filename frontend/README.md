# MedBuddy Frontend

Flutter client for the MedBuddy alpha demo.

Current app version: **0.0.9+9**.

## Role

The frontend follows the same Boundary-Control-Entity structure as the project
UML diagrams:

- `lib/boundaries`: UI screens and user interaction boundaries.
- `lib/controls`: API and use-case controls.
- `lib/entities`: Flutter-side data contracts.
- `lib/viewmodels`: app state coordination for the screens.
- `lib/services`: local services such as notifications and TTS.

## Current Scope

The frontend supports prescription analysis, saved medication management,
patient/caregiver scoped medication views, patient-scoped health
recommendations, persisted local reminders, and slot-level completion for
multi-dose schedules. The experimental v0.0.9 flow also presents loose-pill
identification candidates with mandatory user confirmation; it does not save a
candidate automatically or assert a diagnosis.

## Common Commands

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

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
