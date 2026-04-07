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

```text
📱 Client (Flutter)                  🚀 Server (FastAPI)                       🤖 AI & API
   [Capture Prescription] -----------> [Image Preprocessing (OpenCV)]
                                              |
                                              v
   [Structured UI Display] <-------- [Fine-Tuned LLM (Data Extraction & PII Masking)]
                                              |
   [Detailed Analysis Req.] -------> [Public Drug Safety API]
                                              |
                                              v
   [Save to Pillbox] <-------------- [Fine-Tuned LLM (Personalized Summary) & DB Storage]
```
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
| <img src="https://avatars.githubusercontent.com/u/1window2?v=4" width="80"> | **1window2** | Lead Full-Stack Developer & AI Pipeline Architecture | [@1window2](https://github.com/1window2) |
| <img src="https://avatars.githubusercontent.com/u/tmdgusdl9647?v=4" width="80"> | **tmdgusdl9647** | Backend Developer & AI Logic | [@tmdgusdl9647](https://github.com/tmdgusdl9647) |
| <img src="https://avatars.githubusercontent.com/u/jeeon0318?v=4" width="80"> | **jeeon0318** | Backend Developer & Compliance Specialist | [@jeeon0318](https://github.com/jeeon0318) |
| <img src="https://avatars.githubusercontent.com/u/onlyone130?v=4" width="80"> | **onlyone130** | Frontend Designer & UI/UX Lead | [@onlyone130](https://github.com/onlyone130) |

<br/>
