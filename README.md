[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![FastAPI](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/backend-ci.yml?label=FastAPI&logo=fastapi)](https://github.com/1window2/MedBuddy/actions/workflows/backend-ci.yml) [![Flutter](https://img.shields.io/github/actions/workflow/status/1window2/MedBuddy/frontend-ci.yml?label=Flutter&logo=flutter)](https://github.com/1window2/MedBuddy/actions/workflows/frontend-ci.yml)

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
        CACHE[(⚡ Redis<br/>In-Memory Cache)]:::db
        DB[(💾 SQLite<br/>Database)]:::db
    end

    subgraph External [🤖 AI & External APIs]
        AI1{{✨ Gemini Vision<br/>Target: Fine-Tuned LLM}}:::ai
        PUB{{🏛️ Public Drug<br/>Safety API}}:::ai
        AI2{{✨ Gemini Text<br/>Target: Fine-Tuned LLM}}:::ai
    end

    %% Flow 1: Vision Parsing
    C1 -->|Multipart Image| S1
    S1 -->|Processed Bytes| AI1
    AI1 -->|Raw JSON| S2
    S2 -->|Response DTO| C2

    %% Flow 2: Detail & Save (Updated with Caching)
    C2 -.->|User Click| C3
    C3 -->|Drug Name| S3
    S3 <-->|1. Check Cache Hit/Miss| CACHE
    S3 -->|2. Cache Miss: Query| PUB
    PUB -->|3. Raw Efficacy Data| AI2
    AI2 -->|4. Pharmacist Summary| S3
    S3 -->|5. ORM Entity| DB
    S3 -->|6. Success Response| C4
```

<details>
<summary><b>📊Class Diagram</b></summary>

## Class Diagram
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
            +PUBLIC_DATA_API_KEY : str
            +BASIC_DRUG_API_BASE_URL : str
            +ADVANCED_DRUG_API_BASE_URL : str
            +REDIS_URL : str
        }
        class OCRService {
            <<Service : services/ocr_service.py>>
            +client : genai.Client
            +process_text(raw_text) str
            +split_lines(raw_text) List~str~
            +parse_prescription_text(raw_text) dict
            +extract_prescription_data(image_bytes) PrescriptionData
            -_apply_secondary_masking(data) dict
        }
        class DrugService {
            <<Service : services/drug_service.py>>
            +api_key : str
            +basic_url : str
            +advanced_url : str
            +ai_client : genai.Client
            +redis : redis.Redis
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
    %% 🔗 RELATIONSHIPS
    %% ==========================================
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
    MedicationViewModel ..> FastAPIApp : HTTP Multipart Request
    ApiService ..> FastAPIApp : HTTP Network Protocol

    FastAPIApp --> MedicationRouter : Registers
    FastAPIApp ..> DatabaseModule : Creates Tables
    MedicationRouter ..> DatabaseModule : Uses get_db()
    MedicationRouter --> SavedMedication : DB CRUD Operations
    MedicationRouter --> OCRService : Injects
    MedicationRouter --> DrugService : Injects
    MedicationRouter ..> MedicationSchemas : Request/Response
    MedicationRouter ..> OCRSchemas : Request/Response

    OCRService --> PrescriptionParser_Python : Uses
    OCRService ..> OCRSchemas : Returns
    OCRService ..> Settings : Reads Config
    DrugService ..> Settings : Reads Config
    DrugService ..> MedicationSchemas : Returns
```
</details>

<details>
<summary><b>📊Sequence Diagram</b></summary>

## Phase 1. AI Vision Parsing & Secure Data Extraction
```mermaid
sequenceDiagram
    autonumber
    
    actor User as 사용자
    participant View as HomeScreen
    participant VM as MedicationViewModel
    participant API as FastAPI (main.py)
    participant Router as MedicationRouter
    participant OCR as OCRService
    participant AI as Gemini Vision API
    
    User->>View: '처방전 촬영' 버튼 클릭
    
    activate View
    View->>VM: processMedicationImage()
    activate VM
    
    VM->>VM: _picker.pickImage(camera) 호출
    
    alt 촬영 완료 시
        VM->>VM: _setLoading(true)
        VM-->>View: notifyListeners() (스피너 렌더링)
        
        Note over VM, API: HTTP Multipart POST /upload-prescription
        VM->>API: 처방전 이미지 파일(imageFile) 전송
        activate API
        
        API->>Router: upload_and_parse_prescription()
        activate Router
        
        Router->>OCR: extract_prescription_data(image_bytes)
        activate OCR
        
        OCR->>OCR: preprocess_prescription_image() 전처리
        
        OCR->>AI: model.generate_content_async() 호출
        activate AI
        Note over OCR, AI: 보안 프롬프트 + 이미지 전송
        AI-->>OCR: 구조화된 JSON Text 응답 반환
        deactivate AI
        
        OCR->>OCR: 마크다운 제거 및 JSON 디코딩
        OCR->>OCR: _apply_secondary_masking() (정규식 2차 마스킹)
        
        OCR-->>Router: PrescriptionData (DTO 객체) 반환
        deactivate OCR
        
        Router-->>API: HTTP 200 OK
        deactivate Router
        
        API-->>VM: JSON 응답 수신 (decodedBody)
        deactivate API
        
        VM->>VM: _parsedDrugList 업데이트 & _setLoading(false)
        VM-->>View: notifyListeners() (결과 화면 렌더링)
    end
    deactivate VM
    View-->>User: 병원 정보 및 추출된 약품 목록 UI 표시
    deactivate View

    Note over User, View: 사용자가 화면의 약품 리스트를 확인하며 대기
```

## Phase 2. Public API Enrichment & AI Pharmacist Summary
```mermaid
sequenceDiagram
    autonumber
    
    actor User as 사용자
    participant View as HomeScreen
    participant VM as MedicationViewModel
    participant ApiS as ApiService (Dart)
    participant Router as MedicationRouter
    participant DrugS as DrugService
    participant Redis as Redis Cache
    participant PubAPI as 공공데이터 API
    participant AI as Gemini Text API
    participant DB as SQLite DB

    Note over User, View: Phase 1에서 추출된 약품 목록 중 하나를 선택하여 진행
    
    User->>View: 약품 리스트에서 '상세 분석 & 저장' 클릭
    activate View
    
    View->>VM: saveDrugToPillbox(DrugInfo)
    activate VM
    VM-->>View: 상태 메시지 업데이트 (저장 중...)
    
    VM->>ApiS: identifyMedication(text) 호출
    activate ApiS
    Note over ApiS, Router: HTTP POST /identify
    ApiS->>Router: 약품명(extracted_text) 전송
    activate Router
    
    Router->>DrugS: fetch_drug_info(search_keyword)
    activate DrugS
    
    %% Redis 캐시 확인 로직
    DrugS->>Redis: get("drug_info:{약품명}")
    activate Redis
    Redis-->>DrugS: Cache Hit / Miss 반환
    deactivate Redis

    alt Cache Miss (캐시에 데이터가 없을 경우)
        DrugS->>PubAPI: HTTP GET e약은요 / 허가정보 API 호출
        PubAPI-->>DrugS: XML/JSON 원본 데이터 반환
        
        DrugS->>AI: model.generate_content_async(식약처 원본 데이터)
        activate AI
        Note over DrugS, AI: "친절한 약사 말투로 1~2줄 요약해줘" 프롬프트 전송
        AI-->>DrugS: 친절한 AI 가이드 텍스트(ai_guide) 반환
        deactivate AI
        
        DrugS->>Redis: setex(완성된 JSON 데이터, 7일 보관)
        activate Redis
        Redis-->>DrugS: 캐시 저장 완료
        deactivate Redis
    else Cache Hit (캐시에 데이터가 있을 경우)
        Note over DrugS, Redis: 즉시 데이터 반환 (PubAPI 및 AI 호출 전면 생략)
    end
    
    DrugS-->>Router: List<DrugInfo> 반환 (ai_guide 포함)
    deactivate DrugS
    
    Router-->>ApiS: MedicationResponse JSON 반환
    deactivate Router
    
    ApiS->>ApiS: DrugInfo.fromJson() 모델 매핑
    
    Note over ApiS, Router: HTTP POST /save
    ApiS->>Router: 완성된 DrugInfo 전송
    activate Router
    
    Router->>DB: db.add(SavedMedication) & db.commit()
    activate DB
    DB-->>Router: DB 저장 성공 확인
    deactivate DB
    
    Router-->>ApiS: 저장 성공 응답
    deactivate Router
    
    ApiS-->>VM: boolean(success) 반환
    deactivate ApiS
    
    VM->>VM: fetchPillbox() 호출 (데이터 최신화)
    VM-->>View: 저장 완료 메시지 표시
    deactivate VM
    
    View-->>User: SnackBar 알림 ("성공적으로 저장되었습니다!")
    deactivate View
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
