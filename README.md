[![CodeQL](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/github-code-scanning/codeql) [![Python App Workflow](https://github.com/1window2/MedBuddy/actions/workflows/main.yml/badge.svg)](https://github.com/1window2/MedBuddy/actions/workflows/main.yml)

# 💊 MedBuddy
> **AI-Powered Medication Management System** <br/>
> OCR과 LLM 기술을 활용하여 처방전을 디지털화하고, 환자의 안전한 복약을 돕는 맞춤형 AI 약사 서비스입니다.
<br/>

## 🌟 Key Features

* **📸 AI 비전 처방전 인식 (Auto-Parsing)**
  * 스마트폰 카메라로 처방전/약봉투를 촬영하면 AI가 즉시 정형 데이터(병원명, 조제일자, 약품명, 투약량 등)로 추출합니다.
  * 개인정보(환자 이름, 주민번호)를 자동으로 마스킹하여 보안을 유지합니다.
* **👩‍⚕️ AI 맞춤형 약사 가이드**
  * 식약처 공공데이터를 기반으로 어려운 의약품 전문 용어를 일반인이 이해하기 쉬운 '친절한 동네 약사' 말투로 요약해 제공합니다.
* **🗂️ 내 약통 관리 (Pillbox)**
  * 현재 복용 중인 약의 효능, 복용법, 주의사항을 언제든 쉽게 확인하고 관리할 수 있습니다.

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
   [처방전 촬영] ---------------------> [이미지 전처리 (OpenCV)]
                                              |
                                              v
   [구조화된 UI 출력] <---------------- [Gemini 1.5 Flash (데이터 추출 및 마스킹)]
                                              |
   [상세 분석 요청] ------------------> [식약처 공공 API 검색]
                                              |
                                              v
   [내 약통 저장 완료] <--------------- [Gemini 2.5 Flash (AI 요약 생성) & DB 저장]
