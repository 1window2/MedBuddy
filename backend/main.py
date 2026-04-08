# 파일명 : main.py
# 역할 : MedBuddy FastAPI 애플리케이션을 초기화하고, 환경 변수 로드, 외부 API 설정,
#        데이터베이스 테이블 생성, 라우터 등록 및 서버 실행을 담당한다.

import os
from google import genai
from google.genai import types
from fastapi import FastAPI
from api.router import router as medication_router
from dotenv import load_dotenv
from core import database
from models import db_models

# Step 1 : .env 파일에서 환경 변수를 로드한다.
load_dotenv()

# Step 2 : Gemini API 키를 불러오고, 설정 여부를 검증한다.
gemini_key = os.getenv("GEMINI_API_KEY")
if not gemini_key: # API 키가 없을 경우
    raise ValueError("환경 변수에 GEMINI_API_KEY가 설정되지 않았습니다. Secrets 설정을 확인하세요.")

# Step 3 : 애플리케이션 실행 시 필요한 데이터베이스 테이블을 생성한다.
db_models.Base.metadata.create_all(bind=database.engine)

# Step 4 : FastAPI 애플리케이션 인스턴스를 생성한다.
app = FastAPI(title="MedBuddy API", version="1.0.0")

# Step 5 : 약품 관련 라우터를 애플리케이션에 등록한다.
app.include_router(medication_router, prefix="/api/v1/medication", tags=["Medication"])

# Step 6 : 현재 파일이 직접 실행된 경우 Uvicorn 서버를 실행한다.
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
