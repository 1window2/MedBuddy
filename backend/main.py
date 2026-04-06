import os
import google.generativeai as genai
from fastapi import FastAPI
from api.router import router as medication_router
from dotenv import load_dotenv
from core import database
from models import db_models

# .env에서 환경 변수 로드
load_dotenv()

gemini_key = os.getenv("GEMINI_API_KEY")
if not gemini_key: # API 키가 없을 경우
    raise ValueError("환경 변수에 GEMINI_API_KEY가 설정되지 않았습니다. Secrets 설정을 확인하세요.")

# Google Generative AI 초기화
genai.configure(api_key=gemini_key)

# 앱 실행 시 DB 테이블 생성
db_models.Base.metadata.create_all(bind=database.engine)

app = FastAPI(title="MedBuddy API", version="1.0.0")

# 라우터 등록
app.include_router(medication_router, prefix="/api/v1/medication", tags=["Medication"])

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)