from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware

###테스트용###

# FastAPI 앱 객체 생성
app = FastAPI(
    title="MedBuddy API Server",
    description="처방전 분석 및 복약 관리를 위한 백엔드 API",
    version="0.1.0"
)

# CORS 설정 (프론트엔드와 통신을 위해 필요)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 모든 도메인 허용 (개발 시)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 1. 루트 엔드포인트: 서버 작동 여부 확인용
@app.get("/")
async def root():
    return {
        "project": "MedBuddy",
        "status": "Online",
        "message": "MedBuddy 백엔드 서버에 연결되었습니다."
    }

# 2. 이미지 분석 엔드포인트 (임시 뼈대)
# 나중에 이곳에 OCR 및 LLM 로직이 들어갑니다.
@app.post("/analyze-prescription")
async def analyze_prescription(file: UploadFile = File(...)):
    # 파일 정보를 수신하는 로직만 구현
    return {
        "filename": file.filename,
        "content_type": file.content_type,
        "message": "파일이 성공적으로 업로드되었습니다. 분석 로직을 구현해주세요."
    }

# 3. 건강 상태 체크 엔드포인트
@app.get("/health")
async def health_check():
    return {"status": "healthy"}