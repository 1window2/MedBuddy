#API 키 등 환경변수 관리

from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # 발급받은 공공데이터포털 e약은요 API 키
    DRUG_API_KEY: str = "4cf19e7d3e17c0ede086056af6eb7ae06b88e85631f90f7aff7c1d0f324df013"
    DRUG_API_BASE_URL: str = "http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"

settings = Settings()