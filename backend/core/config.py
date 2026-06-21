# 파일명: config.py
# 역할: 백엔드 환경변수와 외부 서비스 설정값을 로드한다.

from pydantic_settings import BaseSettings, SettingsConfigDict


# 클래스명: Settings
# 역할: 환경변수와 .env 파일에서 애플리케이션 설정을 읽어온다.
# 주요 책임:
#   - 외부 API 키와 API endpoint를 환경변수로부터 읽는다.
#   - 공공데이터 의약품 API 기본 endpoint를 제공한다.
#   - 백엔드 전체에서 공유할 settings 객체를 생성한다.
# 속성:
#   - GEMINI_API_KEY: Gemini API 호출에 사용하는 키 값
#   - PUBLIC_DATA_API_KEY: 공공데이터포털 API 호출에 사용하는 키 값
#   - BASIC_DRUG_API_BASE_URL: e약은요 API endpoint
#   - ADVANCED_DRUG_API_BASE_URL: 의약품 제품 허가정보 API endpoint
#   - REDIS_URL: 선택적으로 사용할 Redis 캐시 주소
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    GEMINI_API_KEY: str
    PUBLIC_DATA_API_KEY: str
    BASIC_DRUG_API_BASE_URL: str = (
        "http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"
    )
    ADVANCED_DRUG_API_BASE_URL: str = (
        "http://apis.data.go.kr/1471000/"
        "DrugPrdtPrmsnInfoService07/getDrugPrdtPrmsnDtlInq06"
    )
    REDIS_URL: str = "redis://localhost:6379"


settings = Settings()
