# File Name: config.py
# Role: Loads backend environment variables and external service settings.

from urllib.parse import urlparse

from pydantic import Field, field_validator
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

    GEMINI_API_KEY: str = Field(min_length=1)
    PUBLIC_DATA_API_KEY: str = Field(min_length=1)
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
    PILL_IMAGE_API_TIMEOUT_SECONDS: float = Field(default=8.0, gt=0, le=120)
    PILL_IDENTIFICATION_MODEL_NAME: str = Field(
        default="gemini-3.1-flash-lite",
        min_length=1,
    )
    PILL_IDENTIFICATION_TIMEOUT_SECONDS: float = Field(
        default=20.0,
        gt=0,
        le=120,
    )
    PILL_IDENTIFICATION_CATALOG_TTL_HOURS: int = Field(
        default=168,
        gt=0,
        le=8_760,
    )
    PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS: float = Field(
        default=30.0,
        gt=0,
        le=600,
    )
    PRESCRIPTION_OCR_TIMEOUT_SECONDS: float = Field(
        default=30.0,
        gt=0,
        le=120,
    )
    PRESCRIPTION_NAME_FALLBACK_TIMEOUT_SECONDS: float = Field(
        default=8.0,
        gt=0,
        le=120,
    )
    MEDICATION_SUMMARY_TIMEOUT_SECONDS: float = Field(
        default=20.0,
        gt=0,
        le=120,
    )
    HEALTH_RECOMMENDATION_TIMEOUT_SECONDS: float = Field(
        default=20.0,
        gt=0,
        le=120,
    )
    REDIS_URL: str = "redis://localhost:6379"

    # 함수이름: validate_external_api_url
    # 함수역할:
    # - 공공데이터 API 주소가 암호화된 HTTPS 절대주소인지 시작 시점에 검증한다.
    # 매개변수:
    # - value: 환경변수에서 읽은 외부 API 주소
    # 반환값:
    # - 앞뒤 공백을 제거한 HTTPS API 주소
    @field_validator(
        "BASIC_DRUG_API_BASE_URL",
        "ADVANCED_DRUG_API_BASE_URL",
        "PILL_IMAGE_API_BASE_URL",
    )
    @classmethod
    def validate_external_api_url(cls, value: str) -> str:
        normalized_url = value.strip()
        parsed_url = urlparse(normalized_url)
        if parsed_url.scheme.lower() != "https" or not parsed_url.netloc:
            raise ValueError("External public-data API URL must use HTTPS.")
        return normalized_url


settings = Settings()
