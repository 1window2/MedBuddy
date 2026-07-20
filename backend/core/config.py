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
#   - PILL_IMAGE_API_BASE_URL: Medication pill-identification API endpoint.
#   - PILL_IMAGE_API_ENABLED: Enables optional MFDS pill-image enrichment.
#   - PILL_IMAGE_API_TIMEOUT_SECONDS: Maximum optional image lookup duration.
#   - PILL_IDENTIFICATION_MODEL_NAME: Visual feature extraction model.
#   - PILL_IDENTIFICATION_TIMEOUT_SECONDS: Maximum pill image analysis duration.
#   - PILL_IDENTIFICATION_CATALOG_TTL_HOURS: Local MFDS catalog cache lifetime.
#   - PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS: Maximum full catalog
#     refresh duration.
#   - PRESCRIPTION_OCR_TIMEOUT_SECONDS: Maximum structured OCR request duration.
#   - PRESCRIPTION_NAME_FALLBACK_TIMEOUT_SECONDS: Maximum optional AI correction
#     duration.
#   - MEDICATION_SUMMARY_TIMEOUT_SECONDS: Maximum approval summary duration.
#   - HEALTH_RECOMMENDATION_TIMEOUT_SECONDS: Maximum health recommendation duration.
#   - REDIS_URL: Optional Redis cache URL.
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    GEMINI_API_KEY: str
    PUBLIC_DATA_API_KEY: str
    BASIC_DRUG_API_BASE_URL: str = (
        "https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"
    )
    ADVANCED_DRUG_API_BASE_URL: str = (
        "https://apis.data.go.kr/1471000/"
        "DrugPrdtPrmsnInfoService07/getDrugPrdtPrmsnDtlInq06"
    )
    PILL_IMAGE_API_BASE_URL: str = (
        "https://apis.data.go.kr/1471000/"
        "MdcinGrnIdntfcInfoService03/getMdcinGrnIdntfcInfoList03"
    )
    PILL_IMAGE_API_ENABLED: bool = True
    PILL_IMAGE_API_TIMEOUT_SECONDS: float = 8.0
    PILL_IDENTIFICATION_MODEL_NAME: str = "gemini-3.1-flash-lite"
    PILL_IDENTIFICATION_TIMEOUT_SECONDS: float = 20.0
    PILL_IDENTIFICATION_CATALOG_TTL_HOURS: int = 168
    PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS: float = 30.0
    PRESCRIPTION_OCR_TIMEOUT_SECONDS: float = 30.0
    PRESCRIPTION_NAME_FALLBACK_TIMEOUT_SECONDS: float = 8.0
    MEDICATION_SUMMARY_TIMEOUT_SECONDS: float = 20.0
    HEALTH_RECOMMENDATION_TIMEOUT_SECONDS: float = 20.0
    REDIS_URL: str = "redis://localhost:6379"


settings = Settings()
