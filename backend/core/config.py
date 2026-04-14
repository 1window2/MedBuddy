# 파일명: config.py
# 역할: 애플리케이션 전역 환경변수 및 외부 서비스 설정 관리

from pydantic_settings import BaseSettings

# 클래스명: Settings
# 역할: 환경변수(.env 포함)를 로드하여 설정값을 제공하는 클래스
# 주요 책임:
#   - API 키 및 외부 서비스 URL 로드
#   - 기본 설정값 제공
#   - 전역 설정 객체 생성 지원
# 속성 :
#   - GEMINI_API_KEY : Gemini API 키 (str)
#   - PUBLIC_DATA_API_KEY : 공공 데이터 API 키 (str)
#   - BASIC_DRUG_API_BASE_URL : 기본 의약품 API URL (str)
#   - ADVANCED_DRUG_API_BASE_URL : 상세 의약품 API URL (str)
#   - REDIS_URL : Redis 연결 주소 (str)
class Settings(BaseSettings):
    GEMINI_API_KEY: str
    PUBLIC_DATA_API_KEY: str
    BASIC_DRUG_API_BASE_URL: str = "http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"
    ADVANCED_DRUG_API_BASE_URL: str = "http://apis.data.go.kr/1471000/DrugPrdtPrmsnInfoService07/getDrugPrdtPrmsnDtlInq06"
    REDIS_URL: str = "redis://localhost:6379"

    class Config:
        env_file = ".env"

settings = Settings() # # 전역 설정 객체 생성 (.env 기반)
