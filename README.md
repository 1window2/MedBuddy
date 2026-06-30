[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![FastAPI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/backend-ci.yml?label=FastAPI&logo=fastapi)](https://github.com/1window2/MedBuddy/actions/workflows/backend-ci.yml) [![Flutter](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/frontend-ci.yml?label=Flutter&logo=flutter)](https://github.com/1window2/MedBuddy/actions/workflows/frontend-ci.yml)

# MedBuddy

> **AI-Powered Medication Management System**
>
> A Flutter and FastAPI medication assistant that analyzes prescription or pill-envelope photos, enriches medication information with Korean public drug data and Gemini, and helps patients manage saved medications, schedules, reminders, and caregiver-linked views.

## Key Features

### Prescription and Pill-Envelope Analysis

- The Flutter app captures or selects a prescription or pill-envelope image and sends it to FastAPI as multipart data.
- The backend preprocesses the image, requests structured extraction from Gemini Vision, validates the response schema, and applies secondary masking before returning medication candidates.
- The analysis result can be saved into the user's medication list while preserving prescription-derived schedule fields such as dose per time, daily frequency, and total days.

### Medication Detail and Guidance

- Extracted medication names are normalized before lookup.
- When `backend/medbuddy.db` contains the mirrored public drug catalog, SQLite is used first.
- Redis and Korean public drug APIs remain fallback paths for records missing from the local catalog.
- Gemini Text generates patient-friendly medication guidance from the retrieved drug information.
- The Flutter app can present medication details and voice guidance through the TTS service.

### Saved Medication and Schedule Management

- Users can save, list, and delete medications in a patient-scoped pillbox.
- Saved medications retain dosage schedule fields for today's medication schedule.
- Today's schedule supports patient-scoped and caregiver-scoped status updates.
- Multi-dose medications are rendered and updated by schedule slot, so morning, lunch, evening, and bedtime doses can be checked independently.
- Slot completion state is stored separately from saved medication snapshots and is cleaned up with deleted or expired medication records.
- Saved medication records are retained through their medication period and cleaned up after the configured retention window.

### Patient and Caregiver Link Flow

- Patients can create a temporary link code.
- Caregivers can register the code, view linked patient medication data, and unlink when needed.
- Patient/caregiver scope resolution is handled in control-layer classes so UI screens do not bypass backend authorization scope.

### Health Recommendations and Reminders

- The backend can generate patient-scoped health recommendations using saved medication context.
- The frontend includes health recommendation UI state and API controls.
- Local notification support provides per-slot medication reminder scheduling for demo use.

## Architecture Discipline

MedBuddy is implemented around the project UML diagrams and follows a Boundary-Control-Entity style structure:

- **Boundary/UI** classes render screens and collect user input.
- **Control** classes coordinate use cases, API calls, scope resolution, persistence, and external services.
- **Entity/Model** classes preserve application data contracts such as medication schedules, saved medication snapshots, user settings, and patient-caregiver links.
- Backend routers remain thin boundary adapters around control classes.

When adding code, prefer extending the existing class skeletons and UML-aligned flow instead of adding ad hoc shortcuts between unrelated layers.

## Tech Stack

### Frontend

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)

### Backend

![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)
![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)
![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)

### AI and Data

![Gemini](https://img.shields.io/badge/Google%20Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white)
![OpenCV](https://img.shields.io/badge/opencv-%23white.svg?style=for-the-badge&logo=opencv&logoColor=white)
![Redis](https://img.shields.io/badge/redis-%23DD0031.svg?style=for-the-badge&logo=redis&logoColor=white)
![Public Data](https://img.shields.io/badge/공공데이터포털-009900?style=for-the-badge)

### Collaboration

![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)
![Figma](https://img.shields.io/badge/figma-%23F24E1E.svg?style=for-the-badge&logo=figma&logoColor=white)

## UI / UX Design

#### Figma: [MedBuddy Design](https://www.figma.com/design/YS6yFzx1dpT7a0FxnefWUy/MedBuddy)
- Designed by [@onlyone130](https://github.com/onlyone130)

## Getting Started

### Prerequisites

- Python 3.11 for the backend CI target
- Flutter SDK and Android Studio
- A running Android emulator or physical Android device
- Gemini API key
- Korean public data portal API key for the drug APIs
- Redis server, optional for faster repeated drug lookups
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

To install test dependencies as well:

```powershell
python -m pip install -r requirements-dev.txt
python -m pytest
```

Open `backend/.env` and set at least:

```dotenv
GEMINI_API_KEY=your_gemini_api_key
PUBLIC_DATA_API_KEY=your_public_data_api_key
```

Start the API server:

```powershell
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

API documentation is available at:

```text
http://127.0.0.1:8000/docs
```

Use `0.0.0.0` when testing with an Android emulator, because the Flutter app reaches the host machine through `10.0.2.2`.

### Optional Local Drug Catalog

If a local medication catalog database exists at `backend/medbuddy.db`, the backend uses it before Redis and public API fallback. Generated `.db` files are intentionally ignored by Git.

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
flutter run -d emulator-5554
```

By default, the Android emulator build calls:

```text
http://10.0.2.2:8000/api/v1/medication
```

Override the backend URL at run time when needed:

```powershell
flutter run -d emulator-5554 --dart-define=MEDBUDDY_API_BASE_URL=http://10.0.2.2:8000/api/v1/medication
```

### Release Build

For the v0.0.4-alpha Android demo APK:

```powershell
cd frontend
flutter build apk --release
```

The APK is written to:

```text
frontend/build/app/outputs/flutter-apk/app-release.apk
```

## Verification Checklist

Run these checks before tagging or uploading a demo release:

```powershell
cd backend
..\.venv\Scripts\Activate.ps1
python -m pytest
```

```powershell
cd frontend
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release
```

Before committing, also check:

- No `.env`, `.db`, local SDK path, generated build output, or emulator-specific file is staged.
- `frontend/pubspec.yaml` contains the intended app version.
- UML-aligned control/entity boundaries are preserved for new features.

## Contributors

| Profile | Name | Role | GitHub |
| :---: | :---: | :---: | :---: |
| <img src="https://github.com/1window2.png" width="80"> | **1window2** | Full-Stack Architecture & AI Pipeline Lead | [@1window2](https://github.com/1window2) |
| <img src="https://github.com/tmdgusdl9647.png" width="80"> | **tmdgusdl9647** | Full-Stack Feature Developer | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://github.com/jeeon0318.png" width="80"> | **jeeon0318** | UML Documentation & Legal Compliance Lead | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://github.com/onlyone130.png" width="80"> | **onlyone130** | UI/UX Design Lead | [@onlyone130](https://github.com/onlyone130) |
