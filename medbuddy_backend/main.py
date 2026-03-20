from fastapi import FastAPI
from api.router import router as medication_router

app = FastAPI(title="MedBuddy API", version="1.0.0")

# 라우터 등록
app.include_router(medication_router, prefix="/api/v1/medication", tags=["Medication"])

if __name__ == "__main__":
    import uvicorn
    # uvicorn main:app --reload 로 실행
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)