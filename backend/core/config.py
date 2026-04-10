#API 키 등 환경변수 관리

from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    GEMINI_API_KEY: str
    PUBLIC_DATA_API_KEY: str
    BASIC_DRUG_API_BASE_URL: str = "http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"
    ADVANCED_DRUG_API_BASE_URL: str = "http://apis.data.go.kr/1471000/DrugPrdtPrmsnInfoService07/getDrugPrdtPrmsnDtlInq06"

    class Config:
        env_file = ".env"

settings = Settings()