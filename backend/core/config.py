#API 키 등 환경변수 관리

from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # 발급받은 공공데이터포털 e약은요 API 키
    DRUG_API_KEY: str
    DRUG_API_BASE_URL: str

    class Config:
        env_file = ".env"

settings = Settings()