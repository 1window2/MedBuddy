[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![FastAPI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/backend-ci.yml?label=FastAPI&logo=fastapi)](https://github.com/1window2/MedBuddy/actions/workflows/backend-ci.yml) [![Flutter](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/frontend-ci.yml?label=Flutter&logo=flutter)](https://github.com/1window2/MedBuddy/actions/workflows/frontend-ci.yml)

# MedBuddy
> **AI-Powered Medication Management System** <br/>
> A Flutter and FastAPI medication assistant that analyzes prescription or pill-envelope photos, enriches extracted medication names with public drug data, and stores selected medications in a personal pillbox.
<br/>

## Key Features

* **Prescription and Pill-Envelope Image Analysis**
  * The Flutter app captures a prescription or pill-envelope image and sends it to the FastAPI backend as multipart data.
  * The backend performs image preprocessing, requests structured extraction from Gemini Vision, and applies secondary masking before returning medication candidates.
* **Medication Detail Enrichment**
  * Extracted medication names are normalized and looked up through the public drug data pipeline.
  * Redis is used as an optional cache, with the e약은요 API as the primary source and the drug approval information API as a fallback.
  * Gemini Text generates patient-friendly guidance from the retrieved public drug information.
* **Saved Medication Management**
  * Users can save selected medication details to SQLite and reload or delete saved medication records from the pillbox screen.
* **Refactored Flutter Presentation Layer**
  * The frontend separates UI, state coordination, API boundary calls, control classes, and data models.
  * Current screens follow the Figma-based visual direction for prescription input, analysis progress, analysis results, and saved medication views.

<br/>

## Tech Stack

### Frontend
![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)

### Backend
![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)
![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)
![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)

### AI & API
![Gemini](https://img.shields.io/badge/Google%20Gemini-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white)
![OpenCV](https://img.shields.io/badge/opencv-%23white.svg?style=for-the-badge&logo=opencv&logoColor=white)
![Redis](https://img.shields.io/badge/redis-%23DD0031.svg?style=for-the-badge&logo=redis&logoColor=white)
![Public Data](https://img.shields.io/badge/식약처_공공DB-009900?style=for-the-badge)

### Collaboration
![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)
![Figma](https://img.shields.io/badge/figma-%23F24E1E.svg?style=for-the-badge&logo=figma&logoColor=white)

<br/>

## UI / UX Design

### [Figma Link](https://www.figma.com/design/YS6yFzx1dpT7a0FxnefWUy/MedBuddy)

<br/>

## Getting Started

### Prerequisites

* Python 3.11
* Flutter SDK and Android Studio
* A running Android emulator or physical Android device
* Gemini API key
* Korean public data portal API key for the drug APIs
* Redis server, optional but recommended for faster repeated drug lookups

### 1. Backend Setup

From the repository root:

```powershell
cd backend
py -3.11 -m venv ..\.venv
..\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Open `backend/.env` and set at least the following values:

```dotenv
GEMINI_API_KEY=your_gemini_api_key
PUBLIC_DATA_API_KEY=your_public_data_api_key
```

Start the API server:

```powershell
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

The API documentation should be available at:

```text
http://127.0.0.1:8000/docs
```

Use `0.0.0.0` when testing with an Android emulator, because the Flutter app reaches the host machine through `10.0.2.2`.

### 2. Frontend Setup

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

If you need a different backend address, override it at run time:

```powershell
flutter run -d emulator-5554 --dart-define=MEDBUDDY_API_BASE_URL=http://10.0.2.2:8000/api/v1/medication
```

<br/>

## Contributors

| Profile | Name | Role | GitHub |
| :---: | :---: | :---: | :---: |
| <img src="https://github.com/1window2.png" width="80"> | **1window2** | Full-Stack Developer & AI Pipeline Architecture | [@1window2](https://github.com/1window2) |
| <img src="https://github.com/tmdgusdl9647.png" width="80"> | **tmdgusdl9647** | Backend Developer & AI Logic | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://github.com/jeeon0318.png" width="80"> | **jeeon0318** | Backend Developer & Compliance Specialist | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://github.com/onlyone130.png" width="80"> | **onlyone130** | Frontend Designer & UI/UX Lead | [@onlyone130](https://github.com/onlyone130) |

<br/>
