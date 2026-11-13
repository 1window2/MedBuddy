[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![FastAPI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/backend-ci.yml?label=FastAPI&logo=fastapi)](https://github.com/1window2/MedBuddy/actions/workflows/backend-ci.yml) [![Flutter](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/frontend-ci.yml?label=Flutter&logo=flutter)](https://github.com/1window2/MedBuddy/actions/workflows/frontend-ci.yml) [![Android](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/release-android.yml?label=Android&logo=android)](https://github.com/1window2/MedBuddy/actions/workflows/release-android.yml)

# MedBuddy

> **AI-Powered Medication Management System**
>
> An Android app (Flutter) with a FastAPI backend that reads prescriptions and pill
> photos, keeps medication schedules and reminders, and connects patients with their
> caregivers.

- **Download:** [GitHub Releases](https://github.com/1window2/MedBuddy/releases) (Android APK, ARM 64-bit and 32-bit)
- **User guide (Korean):** [web](docs/user-guide/README.md) · [PDF](docs/user-guide/MedBuddy_User_Guide_ko.pdf)

## Features

- **Registration:** photograph a prescription or pill envelope (OCR and privacy masking run on the device), identify loose pills against the MFDS catalogue, search, or enter a medicine by hand.
- **Schedule and reminders:** per-slot reminders with Taken and snooze buttons, a home-screen widget, and dose records that work offline and sync later.
- **Medication information:** public drug data with plain-language guidance and read-aloud.
- **Patient and caregiver:** link by code, caregiver views, completion and missed-dose alerts, and a chat with medication, pharmacy and history cards.
- **Nearby care:** open hospitals and pharmacies on a map, including late-night and holiday hours.
- **History and health tips:** weekly and monthly records, and diet and activity tips for the current medicines.

## Architecture

| Part | Stack |
| --- | --- |
| App | Flutter / Dart (Android), Firebase Auth and Cloud Messaging |
| Server | FastAPI, PostgreSQL, Redis, Alembic; Cloudflare Tunnel in production |
| AI and data | Gemini, OpenCV, Korean public data APIs (MFDS, NEMC, KASI) |

The code follows the project UML in a Boundary-Control-Entity structure
([class view](docs/UML/class/README.md)). UI design:
[Figma](https://www.figma.com/design/YS6yFzx1dpT7a0FxnefWUy/MedBuddy) by
[@onlyone130](https://github.com/onlyone130).

## Getting Started

The Android app uses the production API by default, so app development needs no
local server:

```powershell
cd frontend
flutter pub get --enforce-lockfile
flutter run -d "[your-device-id]"
```

Use Flutter 3.41.5. For the backend, Firebase settings and the public-data API keys,
see the [frontend README](frontend/README.md), the [backend README](backend/README.md)
and [Production Deployment](docs/Production%20Deployment.md).

## Documentation

- [Release notes](docs/releases/v1.0.0.md) and the [release TODO](docs/TODO.md)
- [Scope](docs/MedBuddy%20-%20Beta%20Scope.md), [security architecture](docs/MedBuddy%20-%20Beta%20Security%20Architecture.md) and [decision log](docs/MedBuddy%20-%20Decision%20Log.md)
- [Contributing](CONTRIBUTING.md) and [security policy](SECURITY.md)

## Contributors

| Profile | Name | Role | GitHub |
| :---: | :---: | :---: | :---: |
| <img src="https://github.com/1window2.png" width="80"> | **1window2** | Full-Stack Architecture & AI Pipeline Lead | [@1window2](https://github.com/1window2) |
| <img src="https://github.com/tmdgusdl9647.png" width="80"> | **tmdgusdl9647** | Team Lead & Developer | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://github.com/jeeon0318.png" width="80"> | **jeeon0318** | UML Documentation & Legal Compliance Lead | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://github.com/onlyone130.png" width="80"> | **onlyone130** | UI/UX Design Lead | [@onlyone130](https://github.com/onlyone130) |
