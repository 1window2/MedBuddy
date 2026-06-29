# File Name: config.py
# Role: Loads backend environment variables and external service settings.

from pydantic_settings import BaseSettings, SettingsConfigDict


# Class Name: Settings
# Role: Provides application configuration loaded from environment variables.
# Responsibilities:
#   - Load API keys and external service URLs.
#   - Provide default URLs for public drug data APIs.
#   - Provide a single settings object for the backend.
# Attributes:
#   - GEMINI_API_KEY: Gemini API key.
#   - PUBLIC_DATA_API_KEY: Korean public data portal API key.
#   - BASIC_DRUG_API_BASE_URL: e약은요 API endpoint.
#   - ADVANCED_DRUG_API_BASE_URL: Detailed approval API endpoint.
#   - REDIS_URL: Optional Redis cache URL.
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
