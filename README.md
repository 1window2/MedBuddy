[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![Python App Workflow](https://github.com/1window2/MedBuddy/actions/workflows/main.yml/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/main.yml)

# 💊 MedBuddy
> **AI-Powered Medication Management System** <br/>
> An intelligent platform that digitizes prescriptions via OCR and fine-tuned LLMs, providing a personalized AI pharmacist for safe medication management.
<br/>

## 🌟 Key Features

* **📸 AI Vision Prescription Parsing**
  * Simply snap a photo of a prescription or pill envelope. Our AI instantly extracts structured data (hospital name, prescription date, medication names, and dosage).
  * Automatically masks Personally Identifiable Information (PII) to ensure data privacy.
* **👩‍⚕️ Personalized AI Pharmacist**
  * Leverages public health data to translate complex medical jargon into friendly, easy-to-understand instructions.
* **🗂️ Smart Pillbox Management**
  * Easily track and manage your current medications, their efficacy, and important precautions in one place.

<br/>

## 🛠 Tech Stack

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
![Public Data](https://img.shields.io/badge/식약처_공공데이터-009900?style=for-the-badge)

<br/>

## ⚙️ System Architecture

```mermaid
flowchart TD
    %% Custom Styling
    classDef client fill:#02569B,stroke:#fff,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef server fill:#005571,stroke:#fff,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef ai fill:#8E75B2,stroke:#fff,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef db fill:#07405e,stroke:#fff,stroke-width:2px,color:#fff,rx:8px,ry:8px

    subgraph Frontend [📱 Client Tier - Flutter]
        C1(📸 Capture<br/>Prescription):::client
        C2(🖥️ Structured<br/>UI Display):::client
        C3(🔍 Request<br/>Detail & Save):::client
        C4(🗂️ Update<br/>Pillbox UI):::client
    end

    subgraph Backend [🚀 Server Tier - FastAPI]
        S1(⚙️ Image Preprocessing<br/>OpenCV):::server
        S2(🛡️ PII Masking &<br/>Data Structuring):::server
        S3(🧠 Routing &<br/>Business Logic):::server
        DB[(💾 SQLite<br/>Database)]:::db
    end

    subgraph External [🤖 AI & External APIs]
        AI1{{✨ Fine-Tuned<br/>LLM Vision}}:::ai
        PUB{{🏛️ Public Drug<br/>Safety API}}:::ai
        AI2{{✨ Fine-Tuned<br/>LLM Text}}:::ai
    end

    %% Flow 1: Vision Parsing (Current)
    C1 -->|Multipart Image| S1
    S1 -->|Processed Bytes| AI1
    AI1 -->|Raw JSON| S2
    S2 -->|Response DTO| C2

    %% Flow 2: Detail & Save (Planned)
    C2 -.->|User Click| C3
    C3 -->|Drug Name| S3
    S3 -->|Query| PUB
    PUB -->|Raw Efficacy Data| AI2
    AI2 -->|Pharmacist Summary| S3
    S3 -->|ORM Entity| DB
    S3 -->|Success Response| C4
```

<details>
<summary><b><size=40>📊Class Diagram</b></size></summary>

```mermaid
classDiagram
    direction TD
    skinparam classAttributeIconSize 0

    %% ==========================================
    %% 📱 1. FRONTEND TIER (Flutter Dart Files)
    %% ==========================================
    namespace Frontend_Application {
        
        class main_dart {
            <<Entry Point : main.dart>>
            +main() void
        }
        
        class MedBuddyApp {
            <<Widget : main.dart>>
            +build(context) Widget
        }

        class HomeScreen {
            <<View : home_screen.dart>>
            +build(context) Widget
            -_buildInfoBadge(label, value) Widget
        }

        class PillboxScreen {
            <<View : pillbox_screen.dart>>
            +createState() _PillboxScreenState
        }

        class _PillboxScreenState {
            <<State : pillbox_screen.dart>>
            +initState() void
            +build(context) Widget
        }

        class MedicationViewModel {
            <<ViewModel : medication_viewmodel.dart>>
            -_apiService : ApiService
            -_picker : ImagePicker
            -_apiUrl : String
            -_isLoading : bool
            -_statusMessage : String
            -_hospitalName : String
            -_prescriptionDate : String
            -_parsedDrugList : List~dynamic~
            -_savedDrugs : List~DrugInfo~
            +processMedicationImage() void
            -_setLoading(value) void
            +saveDrugToPillbox(drug) bool
            +fetchPillbox() void
            +removeDrugFromPillbox(id) void
        }

        class ApiService {
            <<Service : api_service.dart>>
            +baseUrl : String
            +identifyMedication(text) List~DrugInfo~
            +saveMedication(drug) bool
            +getSavedMedications() List~DrugInfo~
            +deleteMedication(id) bool
            +parsePrescription(ocrText) Map
        }
        
        class VisionService {
            <<Service : vision_service.dart>>
            -_picker : ImagePicker
            -_textRecognizer : TextRecognizer
            +captureAndRecognizeText() String
            +dispose() void
        }
        
        class PrescriptionParser_Dart {
            <<Utility : prescription_parser.dart>>
            +maskPrivacyInfo(text) String
            +extractDosageInfo(text) Map
        }

        class DrugInfo_Dart {
            <<Model : drug_info.dart>>
            +itemName : String
            +efficacy : String
            +useMethod : String
            +warningMessage : String
            +aiGuide : String
            +id : int
            +fromJson(json) DrugInfo
        }
    }

    %% ==========================================
    %% 🚀 2. BACKEND API & CONTROLLER TIER
    %% ==========================================
    namespace Backend_API {
        
        class FastAPIApp {
            <<Entry Point : main.py>>
            +app : FastAPI
            +include_router() void
        }

        class MedicationRouter {
            <<Controller : api/router.py>>
            +identify_medication(request, ocr, drug) MedicationResponse
            +save_medication(medication, db) dict
            +get_saved_medications(db) dict
            +delete_medication(drug_id, db) dict
            +parse_prescription_endpoint(request, ocr) dict
            +upload_and_parse_prescription(file, ocr) PrescriptionData
        }
    }

    %% ==========================================
    %% 🧠 3. BACKEND BUSINESS LOGIC TIER
    %% ==========================================
    namespace Backend_Services {
        
        class Settings {
            <<Config : core/config.py>>
            +GEMINI_API_KEY : str
            +DRUG_API_KEY : str
            +DRUG_API_BASE_URL : str
        }

        class OCRService {
            <<Service : services/ocr_service.py>>
            +process_text(raw_text) str
            +split_lines(raw_text) List~str~
            +parse_prescription_text(raw_text) dict
            +extract_prescription_data(image_bytes) PrescriptionData
            -_apply_secondary_masking(data) dict
        }

        class DrugService {
            <<Service : services/drug_service.py>>
            +api_key : str
            +base_url : str
            +fetch_drug_info(drug_name) List~DrugInfo~
        }

        class PrescriptionParser_Python {
            <<Utility : utils/prescription_parser.py>>
            +normalize_text(text) str
            +normalize_date(text) str
            +extract_patient_name(line) str
            +parse_medication_line(line) dict
            +parse_prescription(lines) dict
        }
    }

    %% ==========================================
    %% 🗄️ 4. BACKEND DATA TIER (DB & Schemas)
    %% ==========================================
    namespace Backend_Data {
        
        class DatabaseModule {
            <<Config : core/database.py>>
            +engine : Engine
            +SessionLocal : sessionmaker
            +Base : declarative_base
            +get_db() Iterator~Session~
        }

        class SavedMedication {
            <<Entity : models/db_models.py>>
            +id : Integer
            +item_name : String
            +efficacy : String
            +use_method : String
            +warning_message : String
            +ai_guide : String
        }

        class MedicationSchemas {
            <<DTO : schemas/medication.py>>
            +class MedicationRequest
            +class DrugInfo
            +class SavedMedicationCreate
            +class MedicationResponse
        }

        class OCRSchemas {
            <<DTO : schemas/ocr.py>>
            +class MedicationItem
            +class PrescriptionData
        }
    }

    %% ==========================================
    %% 🔗 RELATIONSHIPS (관계망 연결)
    %% ==========================================
    
    %% Frontend Relationships
    main_dart ..> MedBuddyApp : Runs
    MedBuddyApp ..> HomeScreen : Uses
    MedBuddyApp ..> MedicationViewModel : Provides
    
    PillboxScreen ..> _PillboxScreenState : Creates
    HomeScreen ..> MedicationViewModel : Observes
    _PillboxScreenState ..> MedicationViewModel : Observes
    
    MedicationViewModel --> ApiService : Uses
    MedicationViewModel o-- DrugInfo_Dart : Aggregation
    ApiService ..> DrugInfo_Dart : Maps Data
    
    VisionService ..> PrescriptionParser_Dart : Can Use
    
    %% Client-Server Connection
    MedicationViewModel ..> FastAPIApp : HTTP Multipart Request
    ApiService ..> FastAPIApp : HTTP Network Protocol

    %% Backend Controller Relationships
    FastAPIApp --> MedicationRouter : Registers
    FastAPIApp ..> DatabaseModule : Creates Tables
    MedicationRouter ..> DatabaseModule : Uses get_db()
    MedicationRouter --> SavedMedication : DB CRUD Operations
    MedicationRouter --> OCRService : Injects
    MedicationRouter --> DrugService : Injects
    MedicationRouter ..> MedicationSchemas : Request/Response
    MedicationRouter ..> OCRSchemas : Request/Response

    %% Backend Service Dependencies
    OCRService --> PrescriptionParser_Python : Uses
    OCRService ..> OCRSchemas : Returns
    DrugService ..> Settings : Reads Config
    DrugService ..> MedicationSchemas : Returns
```
</details>
<br/>

## 🚀 Getting Started

### 1. Backend Setup
```bash
$ cd backend
$ pip install -r requirements.txt
$ uvicorn main:app --reload
```

### 2. Frontend Setup
```bash
$ cd frontend
$ flutter pub get
$ flutter run
```

<br/>

## 👥 Contributors

| Profile | Name | Role | GitHub |
| :---: | :---: | :---: | :---: |
| <img src="https://github.com/1window2.png" width="80"> | **1window2** | Lead Full-Stack Developer & AI Pipeline Architecture | [@1window2](https://github.com/1window2) |
| <img src="https://github.com/tmdgusdl9647.png" width="80"> | **tmdgusdl9647** | Backend Developer & AI Logic | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://github.com/jeeon0318.png" width="80"> | **jeeon0318** | Backend Developer & Compliance Specialist | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://github.com/onlyone130.png" width="80"> | **onlyone130** | Frontend Designer & UI/UX Lead | [@onlyone130](https://github.com/onlyone130) |

<br/>
