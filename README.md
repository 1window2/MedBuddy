[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![FastAPI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/backend-ci.yml?label=FastAPI&logo=fastapi)](https://github.com/1window2/MedBuddy/actions/workflows/backend-ci.yml) [![Flutter](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/frontend-ci.yml?label=Flutter&logo=flutter)](https://github.com/1window2/MedBuddy/actions/workflows/frontend-ci.yml) [![Android](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/release-android.yml?label=Android&logo=android)](https://github.com/1window2/MedBuddy/actions/workflows/release-android.yml) [![Dependabot](https://img.shields.io/github/issues-pr/1window2/MedBuddy/dependencies?label=Dependabot&logo=dependabot)](https://github.com/1window2/MedBuddy/pulls?q=is%3Apr+is%3Aopen+author%3Aapp%2Fdependabot)

# MedBuddy

> **AI-Powered Medication Management System**
>
> A Flutter and FastAPI medication assistant that analyzes prescriptions and loose-pill photos, supports direct medication entry, enriches medication information with Korean public data and Gemini, and helps patients and caregivers manage schedules, reminders, linked medication context, and experimental nearby-pharmacy and chat flows.

## Key Features

### Prescription and Pill-Envelope Analysis

- Capture or select prescription and pill-envelope images, with a guided prescription camera that supports portrait and landscape framing only while the camera is active.
- Perform Korean OCR and privacy masking on-device, then send only de-identified text to the authenticated FastAPI analysis pipeline.
- Review recognized fields, correct or add medications, confirm schedule details, and save verified results to the medication list.

### Medication Detail and Guidance

- Resolve normalized medication names through the local catalog, Redis cache, and Korean public drug APIs.
- Present validated medication information, images, patient-friendly guidance, and focused TTS playback.

### Experimental Loose-Pill Identification

- Compare front and optional reverse-side photos against the MFDS pill-identification catalog using visible attributes and deterministic ranking.
- Treat results as candidates requiring explicit user confirmation, with guidance to verify packaging or consult a pharmacist.
- See [`docs/MedBuddy - v0.0.9 Pill Identification Extension.md`](docs/MedBuddy%20-%20v0.0.9%20Pill%20Identification%20Extension.md) for the detailed pipeline.

### Direct Medication Entry

- Users can register a medication without a prescription or pill-identification request by entering its name, dose, unit, start date, end date, and schedule slots.
- An optional camera or gallery image is copied into app-owned patient storage. Orphaned local images are removed when they are no longer referenced.
- Direct entries reuse the same saved-medication and schedule contracts as analyzed medications, so filtering, reminders, completion tracking, caregiver views, and medication-context chat do not require a separate data path.

### Nearby Operating Pharmacies

- This v0.2.0 laboratory feature is hidden by default and appears on the home screen only after the user enables it in Settings.
- Users can request nearby pharmacies after granting foreground location permission. Location is requested only while this feature is in use.
- The Flutter client sends coordinates to the authenticated MedBuddy API. The backend keeps the public-data credential private and adapts the National Emergency Medical Center pharmacy response into the app contract.
- Results are filtered on the server before the 30-result limit is applied. The default view shows pharmacies that are open now without asking the user to enter a time. One filter button offers open-now, late-hours, exact-date weekend/holiday, and all-nearby views; the late-hours view combines officially designated public late-night pharmacies with pharmacies whose reported schedules run late. Date-based views ask only for a date. A Naver Map view appears above the filter; selecting either a pharmacy card or marker synchronizes the selection and centers the map on that pharmacy. Open pharmacies are ranked before closed pharmacies and late-hours pharmacies are prioritized next, followed by user-scoped favorites and distance within the same operating group.
- Weekly National Emergency Medical Center schedules, Korean legal holidays, and exact-date NEMC holiday emergency rosters are cached in PostgreSQL. Responses expose catalog freshness and whether an exact roster, a bounded stale cache, or a weekly fallback supplied the schedule. Official designation records retain their authority URL and verification date and are not inferred from closing time alone.
- Naver Dynamic Map is initialized with a compile-time client identifier. Each pharmacy card lets the user choose an installed map app or Google Maps; if neither can be opened, MedBuddy copies the validated pharmacy address for use in another map or notes app.
- The screen distinguishes pharmacies that are closing soon from closed pharmacies with a known next regular opening, and shows the public-catalog refresh time when available. If optional map configuration is unavailable, the list, phone, and directions actions remain usable with a clear configuration message instead of a misleading coordinate error.
- Manual refresh uses a cooldown to prevent accidental repeated public-data requests. Telephone and directions launches are centralized in one validated external-action service.
- Operating hours are informational public data and may change on holidays or at short notice, so the screen asks users to confirm by phone before visiting. A selected pharmacy can be shared into an authorized medication conversation, with phone-confirmed sharing represented separately from an ordinary location share.

### User Settings and Voice Playback

- Persist medication, caregiver, and chat notification preferences; lock-screen privacy; schedule defaults; font size; reading speed; language; and time format with a local fallback.
- Apply display and voice preferences consistently without changing existing confirmed medication schedules.

### Saved Medication and Schedule Management

- Save patient-scoped medications with prescription dates, dosage details, treatment periods, and schedule slots.
- Filter active and completed courses, track each daily dose independently, and undo accidental completion updates.
- Surface the next dose and daily progress on the home screen while retaining completed medication history.

### Patient and Caregiver Link Flow

- Link patients and caregivers through temporary codes backed by authenticated, server-derived ownership.
- Let caregivers view linked medication data, unlink safely, and configure per-slot completion or missed-dose alerts.
- Deliver transition-based FCM alerts in beta mode without exposing internal patient identifiers.
- Support opt-in medication-context chat with server-verified schedules, medication cards, pharmacy snapshots, idempotent events, and participant-scoped unread state.

### Health Recommendations and Reminders

- Generate patient-scoped health recommendations from saved medication context.
- Schedule persistent per-slot medication reminders and caregiver notification preferences.

## Roadmap

1. **v0.2.0 beta verification:** Validate direct entry, multi-pill partial failure, schedule review, laboratory feature toggles, pharmacy location states, medication-context chat, and two-device notification behavior on supported Android devices.
2. **Android production verification:** Validate the dedicated
   FastAPI/PostgreSQL/Redis production host behind Cloudflare Tunnel, complete
   backup and restore rehearsal, and finish authenticated two-device, Wi-Fi,
   cellular, outage-recovery, and signed-device smoke tests.
3. **Local pill-vision model:** Evaluate a licensed or locally trained lightweight model against the current `PillVisualFeatures` boundary before replacing the external visual-attribute adapter. The current MFDS ranking and mandatory confirmation contract must remain unchanged.

## Architecture

MedBuddy is implemented around the project UML diagrams and follows a Boundary-Control-Entity style structure:

- **Boundary/UI** classes render screens and collect user input.
- **Frontend boundary/service** classes wrap on-device prescription OCR, text-region mapping, privacy filtering, camera-guide cropping, local manual-entry images, foreground location, embedded pharmacy-map rendering, pharmacy favorites and validated external actions, local notifications, TTS, and linked-chat WebSocket events.
- **Backend boundaries** receive de-identified prescription text and isolate public drug and pharmacy APIs, Gemini text recovery, loose-pill vision extraction, and FCM delivery from the use-case controls.
- **Control** classes coordinate use cases, API calls, scope resolution, persistence, OCR correction policy, bounded multi-pill work, nearby-pharmacy queries, and linked chat without placing domain logic in screens or routers.
- **Entity/Model** classes preserve application data contracts such as prescription analysis results, medication schedules, saved medication snapshots, manual entries, nearby pharmacies, chat messages and medication context, user settings, notification preferences, and patient-caregiver links.
- Backend medication, pharmacy, and chat routers remain thin boundary adapters around cohesive controls.

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
- Korean public data portal API key authorized for the drug APIs and the National Emergency Medical Center pharmacy service
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
medication pill-identification, and pharmacy-location APIs. Pill images are optional; lookups keep
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

### Optional Local Public-Data Catalogs

Local development stores medication, pill-reference, and weekly pharmacy schedule rows in `backend/medbuddy.db`. Production uses the same ORM mappings in Alembic-managed PostgreSQL, and the catalog synchronization job is the sole production writer. Generated `.db` files are intentionally ignored by Git.

Build or refresh the optional local medication catalog from the public drug APIs:

```powershell
python scripts/sync_drug_catalog.py --dataset all --page-size 500 --max-retries 5
python scripts/sync_pharmacy_catalog.py --page-size 1000 --max-retries 5
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
Profile and release builds accept only a public HTTPS endpoint whose path is
`/api/v1/medication`. Debug builds additionally accept only the local demo
hosts `10.0.2.2`, `127.0.0.1`, `localhost`, or `::1` over port `8000` when
`MEDBUDDY_ALLOW_LOCAL_HTTP=true` is supplied. Other private-network and
clear-text endpoints remain rejected.

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
  --dart-define=MEDBUDDY_NAVER_MAP_CLIENT_ID=your_naver_dynamic_map_client_id `
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
| <img src="https://github.com/tmdgusdl9647.png" width="80"> | **tmdgusdl9647** | Team Lead & Developer | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://github.com/jeeon0318.png" width="80"> | **jeeon0318** | UML Documentation & Legal Compliance Lead | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://github.com/onlyone130.png" width="80"> | **onlyone130** | UI/UX Design Lead | [@onlyone130](https://github.com/onlyone130) |
