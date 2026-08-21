[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![FastAPI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/backend-ci.yml?label=FastAPI&logo=fastapi)](https://github.com/1window2/MedBuddy/actions/workflows/backend-ci.yml) [![Flutter](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/frontend-ci.yml?label=Flutter&logo=flutter)](https://github.com/1window2/MedBuddy/actions/workflows/frontend-ci.yml) [![Android CI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/release-android.yml?label=Android%20CI&logo=android)](https://github.com/1window2/MedBuddy/actions/workflows/release-android.yml) [![Dependabot](https://img.shields.io/github/issues-pr/1window2/MedBuddy/dependencies?label=Dependabot&logo=dependabot)](https://github.com/1window2/MedBuddy/pulls?q=is%3Apr+is%3Aopen+author%3Aapp%2Fdependabot)

# MedBuddy

> **AI-Powered Medication Management System**
>
> A Flutter and FastAPI medication assistant that analyzes prescription or pill-envelope photos, enriches medication information with Korean public drug data and Gemini, and helps patients manage saved medications, schedules, reminders, and patient-caregiver linked views with caregiver notification preferences.

## Key Features

### Prescription and Pill-Envelope Analysis

- The Flutter app captures or selects a prescription or pill-envelope image and performs Korean OCR on the device with Google ML Kit.
- Before any prescription analysis request, the local privacy filter removes patient-identifying lines and masks resident numbers, phone numbers, email addresses, and other inline identifiers. The original prescription image remains on the device during this text-analysis flow.
- Only the de-identified OCR text is sent to FastAPI through the prescription-text endpoint. The backend parses and validates that text, normalizes the result into UML-aligned prescription analysis entities, and uses bounded Gemini text recovery only where the structured pipeline requires it.
- Extracted medication names are verified against the local medication catalog before the detail lookup pipeline runs.
- Common Korean OCR vowel confusions are corrected through bounded local-catalog candidates; unresolved ambiguous names can use a Gemini fallback that is constrained to catalog candidates and cached by model/request.
- Low-confidence, malformed, or out-of-candidate fallback results are rejected conservatively rather than silently replacing a medication name.
- Recognized text regions and masked sensitive areas are shown in the Flutter preview. Users can correct medication names and confirm the prescription date and morning, lunch, evening, or bedtime schedule slots before analysis.
- When parsing or medication lookup fails, the UI replaces technical exception text with an actionable connection, timeout, data, or OCR review message. Users can retry the analysis, return to the OCR review, retake the photo, or select another image as appropriate.
- The analysis result can be saved into the user's medication list while preserving user-confirmed prescription dates, schedule slots, dose per time, daily frequency, and total days.
- After saving all analyzed medications, users can continue directly to today's schedule or the saved-medication list.

### Medication Detail and Guidance

- Extracted medication names are normalized before lookup.
- When `backend/medbuddy.db` contains the mirrored public drug catalog, SQLite is used first.
- Redis and Korean public drug APIs remain fallback paths for records missing from the local catalog.
- Gemini Text generates patient-friendly medication guidance from the retrieved drug information.
- The Flutter app can present medication details and voice guidance through the TTS service.
- Voice guidance reads only the medication name, administration method, and warnings, in that order.
- Medication images use validated `e약은요` URLs first, then the MFDS pill-identification API for exact solid-medication matches; unsupported dosage forms retain the placeholder.
- OCR-derived search candidates are generated with bounded string handling to avoid ReDoS-prone regular expression behavior on untrusted OCR text.

### Experimental Loose-Pill Identification

- Users can provide a front photo and an optional reverse-side photo of one loose pill.
- A dedicated vision boundary extracts only visible shape, color, imprint, score-line, and quality attributes; it does not ask the AI to name the product.
- The backend ranks those attributes deterministically against the authoritative MFDS pill-identification catalog. Local development stores reference rows in `backend/medbuddy.db`; beta deployment seeds the same Alembic-managed table in shared PostgreSQL before deploying the API revision.
- Results are candidate matches rather than diagnoses. The UI requires explicit selection, never saves a candidate automatically, and directs users to verify packaging or consult a pharmacist.
- This v0.0.9 extension is documented separately from the original UML baseline in [`docs/MedBuddy - v0.0.9 Pill Identification Extension.md`](docs/MedBuddy%20-%20v0.0.9%20Pill%20Identification%20Extension.md).

### User Settings and Voice Playback

- Users can save display font size, reading speed, and language settings.
- User settings are persisted through the backend and cached locally for offline fallback.
- Medication voice guidance uses the selected language and reading speed, with local guide text fallback when the backend voice-guide endpoint is unavailable.

### Saved Medication and Schedule Management

- Users can save, list, and delete medications in a patient-scoped pillbox.
- Saved medications retain the confirmed prescription date, dosage fields, medication period, and schedule slots used to build today's medication schedule.
- The saved-medication list can be filtered by active, completed, or all courses and sorted by registration date or medication date in either direction.
- The home schedule card summarizes the next medication slot, the number of medications due, and today's completion progress.
- Today's schedule supports patient-scoped and caregiver-scoped status updates.
- Multi-dose medications are rendered and updated by schedule slot, so morning, lunch, evening, and bedtime doses can be checked independently.
- Completing a dose provides immediate feedback and an undo action, while reminder setup and cancellation display a clear result message at the bottom of the schedule screen.
- Slot completion state is stored separately from saved medication snapshots and is cleaned up when the owning medication or account is deleted.
- Ended medication records remain visible in the completed-history section by default. Operators may configure a nonzero retention window, but the beta self-hosted profile preserves history until user deletion.

### Patient and Caregiver Link Flow

- Patients can create a temporary link code.
- Caregivers can register the code, view linked patient medication data, and unlink when needed.
- Caregivers can configure each linked patient's morning, lunch, evening, and bedtime alert independently. Each slot supports alerts when a dose is completed or when it remains unchecked after a selected deadline.
- Firebase Authentication establishes the user identity in beta mode, and the
  backend derives the user's internal scope from the verified token. A
  caregiver can select another patient only when an active server-side link
  authorizes that scope; client hashes are selectors, never credentials.
- In Firebase beta mode, authenticated device tokens receive transition-based
  FCM push alerts when a dose is newly completed. Missed-deadline checks remain
  an authenticated Android background task. Local demo mode polls for both
  completion and missed-deadline changes and displays local notifications.

### Health Recommendations and Reminders

- The backend can generate patient-scoped health recommendations using saved medication context.
- The frontend includes health recommendation UI state and API controls.
- Local notification support provides persisted per-slot medication reminder scheduling for demo use.
- Reminder times can be selected with rotating time wheels before the existing alarm control persists and registers them.
- Caregiver notification settings persist the UC-13 preference state per caregiver, patient, and schedule slot.
- Reminder and schedule views use the shared Figma-derived theme tokens for top bars, slot colors, dividers, card borders, and text shades.

## Roadmap

1. **Android beta verification:** Validate the dedicated
   FastAPI/PostgreSQL/Redis production host behind Cloudflare Tunnel, complete
   backup and restore rehearsal, and finish authenticated two-device, Wi-Fi,
   cellular, outage-recovery, and signed-device smoke tests.
2. **Local pill-vision model:** Evaluate a licensed or locally trained lightweight model against the current `PillVisualFeatures` boundary before replacing the external visual-attribute adapter. The current MFDS ranking and mandatory confirmation contract must remain unchanged.

## Architecture

MedBuddy is implemented around the project UML diagrams and follows a Boundary-Control-Entity style structure:

- **Boundary/UI** classes render screens and collect user input.
- **Frontend boundary/service** classes wrap on-device prescription OCR, text-region mapping, and privacy filtering. Backend boundaries receive de-identified prescription text and isolate public drug APIs, Gemini text recovery, loose-pill vision extraction, and FCM delivery from the use-case controls.
- **Control** classes coordinate use cases, API calls, scope resolution, persistence, OCR correction policy, and external services.
- **Entity/Model** classes preserve application data contracts such as prescription analysis results, medication schedules, saved medication snapshots, user settings, notification preferences, and patient-caregiver links.
- Backend routers remain thin boundary adapters around control classes.

The implementation-grounded class view is maintained in
[`docs/MedBuddy - Class Diagram.md`](docs/MedBuddy%20-%20Class%20Diagram.md).
The frozen Android beta boundary and planned security architecture are defined
in [`docs/MedBuddy - Beta Scope.md`](docs/MedBuddy%20-%20Beta%20Scope.md) and
[`docs/MedBuddy - Beta Security Architecture.md`](docs/MedBuddy%20-%20Beta%20Security%20Architecture.md).
Contribution rules for preserving the UML-aligned structure are documented in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Tech Stack

### Frontend

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)

### Backend

![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)
![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)
![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Firebase](https://img.shields.io/badge/firebase-%23FFCA28.svg?style=for-the-badge&logo=firebase&logoColor=black)

### AI and Data

![Gemini](https://img.shields.io/badge/Google%20Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white)
![OpenCV](https://img.shields.io/badge/opencv-%23white.svg?style=for-the-badge&logo=opencv&logoColor=white)
![Redis](https://img.shields.io/badge/redis-%23DD0031.svg?style=for-the-badge&logo=redis&logoColor=white)
![Public Data](https://img.shields.io/badge/Public%20Data-009900?style=for-the-badge)

### Collaboration

![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)
![Figma](https://img.shields.io/badge/figma-%23F24E1E.svg?style=for-the-badge&logo=figma&logoColor=white)

## UI / UX Design

#### Figma: [MedBuddy Design](https://www.figma.com/design/YS6yFzx1dpT7a0FxnefWUy/MedBuddy)
- Designed by [@onlyone130](https://github.com/onlyone130)
- Flutter UI colors are centralized in `frontend/lib/theme/medbuddy_theme.dart` from the Figma palette, including primary greens, mint borders, schedule slot colors, surface shades, dividers, and text colors.

## Getting Started

### Prerequisites

- Python 3.11 for the backend CI target
- Flutter SDK and Android Studio
- A running Android emulator or physical Android device
- Gemini API key
- Korean public data portal API key for the drug APIs
- Redis server, optional for local cache and rate-limit testing; required for distributed production quotas
- Optional local medication catalog database at `backend/medbuddy.db`

### Backend Setup

From the repository root:

```powershell
cd backend
py -3.11 -m venv ..\.venv
..\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Open `backend/.env` and set at least:

```dotenv
GEMINI_API_KEY=your_gemini_api_key
PUBLIC_DATA_API_KEY=your_public_data_api_key
APP_ENV=development
AUTH_MODE=disabled
AUTO_CREATE_SCHEMA=true
PILL_IMAGE_API_ENABLED=true
PILL_IMAGE_API_TIMEOUT_SECONDS=8
PILL_IDENTIFICATION_MODEL_NAME=gemini-3.1-flash-lite
PILL_IDENTIFICATION_TIMEOUT_SECONDS=20
PILL_IDENTIFICATION_CATALOG_TTL_HOURS=168
PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS=30
```

The public-data key must be authorized for the `e약은요`, medication approval,
and medication pill-identification APIs. Pill images are optional; lookups keep
working with the existing placeholder when that API is unavailable or the dosage
form has no public pill image. Set `PILL_IMAGE_API_ENABLED=false` only when the
optional saved-medication image enrichment must be disabled. The experimental
loose-pill flow still requires the MFDS identification catalog.

Start the API server:

```powershell
python -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

API documentation is available at:

```text
http://127.0.0.1:8000/docs
```

This loopback-only server is retained for backend development and automated
testing only. The Android application does not use it as its default API
endpoint.

Production runs on the dedicated Ubuntu host behind Cloudflare Tunnel. See
[MedBuddy Production Deployment](docs/Production%20Deployment.md).

### Optional Local Drug Catalog

Local development stores medication and pill-reference catalog rows in `backend/medbuddy.db`; the backend uses those records before Redis and public API fallback. Production uses the same ORM mappings in Alembic-managed PostgreSQL, and the catalog synchronization job is the sole production writer. Generated `.db` files are intentionally ignored by Git.

Build or refresh the optional local medication catalog from the public drug APIs:

```powershell
python scripts/sync_drug_catalog.py --dataset all --page-size 500 --max-retries 5
```

Resume an interrupted long-running sync from a known API page:

```powershell
python scripts/sync_drug_catalog.py --dataset approval --page-size 500 --start-page 120 --max-retries 5
```

### Frontend Setup

Open another terminal from the repository root:

```powershell
cd frontend
flutter pub get
flutter devices
flutter run -d "[your-device-id]"
```

Use the device id shown by `flutter devices`.

The Android application defaults to the production API endpoint:

```text
https://api.medbuddy.pp.ua/api/v1/medication
```

ADB debugging, Flutter hot reload, breakpoints, and physical-device testing do
not require a backend process on the development laptop or a device on the same
LAN. The Android client reaches the production API over ordinary HTTPS.

`MEDBUDDY_API_BASE_URL` remains a compile-time `String.fromEnvironment` value.
If it is overridden, the value must still be a public HTTPS endpoint whose path
is `/api/v1/medication`. Localhost, private-network addresses, and clear-text
HTTP endpoints are rejected in debug, profile, and release builds.

For authenticated beta testing, keep the real `google-services.json` in
`frontend/android/app` and out of Git. Provide the Firebase configuration that
matches the registered `com.medbuddy.app` Android application:

```powershell
flutter run -d "[your-device-id]" `
  --dart-define=MEDBUDDY_AUTH_MODE=firebase `
  --dart-define=MEDBUDDY_FIREBASE_API_KEY=your_api_key `
  --dart-define=MEDBUDDY_FIREBASE_APP_ID=your_android_app_id `
  --dart-define=MEDBUDDY_FIREBASE_MESSAGING_SENDER_ID=your_sender_id `
  --dart-define=MEDBUDDY_FIREBASE_PROJECT_ID=medbuddy-26 `
  --dart-define=MEDBUDDY_PHONE_AUTH_ENABLED=false
```

Release and profile builds require Firebase authentication and the same public
HTTPS backend contract. Production deployment details are documented in
[`docs/Production Deployment.md`](docs/Production%20Deployment.md), and
authentication, App Check, and signing requirements are documented in
[`docs/MedBuddy - Beta Security Architecture.md`](docs/MedBuddy%20-%20Beta%20Security%20Architecture.md).
For an already installed physical-device beta, increment `frontend/pubspec.yaml`
version code and use `frontend/tool/install_update_preserving_data.ps1`. The
helper verifies the package/signing identity, performs only `adb install -r`,
and refuses any fallback that would uninstall the app or clear Firebase and
reminder state. Server-side medication history remains in the named PostgreSQL
Compose volume; never use `docker compose down -v` during a rebuild. See the
self-hosted guide above for the complete update and backup procedure.

## Contributing

Development workflow, verification commands, UML alignment rules, documentation standards, and commit message conventions are maintained in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Contributors

| Profile | Name | Role | GitHub |
| :---: | :---: | :---: | :---: |
| <img src="https://github.com/1window2.png" width="80"> | **1window2** | Full-Stack Architecture & AI Pipeline Lead | [@1window2](https://github.com/1window2) |
| <img src="https://github.com/tmdgusdl9647.png" width="80"> | **tmdgusdl9647** | Full-Stack Feature Developer | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://github.com/jeeon0318.png" width="80"> | **jeeon0318** | UML Documentation & Legal Compliance Lead | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://github.com/onlyone130.png" width="80"> | **onlyone130** | UI/UX Design Lead | [@onlyone130](https://github.com/onlyone130) |
