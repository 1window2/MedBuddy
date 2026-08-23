# 파일명: config.py
# 역할: 백엔드 환경 변수와 외부 서비스 설정을 불러온다.

from pathlib import Path
from typing import Any, Literal
from urllib.parse import urlparse
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL, make_url
from sqlalchemy.exc import ArgumentError


_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_PROJECT_ROOT = _BACKEND_ROOT.parent
_DEFAULT_DATABASE_URL = f"sqlite:///{(_BACKEND_ROOT / 'medbuddy.db').as_posix()}"
_DEFAULT_API_CONTRACT_VERSION = (
    (_BACKEND_ROOT / "API_CONTRACT_VERSION").read_text(encoding="utf-8").strip()
)


# 클래스명: Settings
# 역할: 환경 변수에서 읽은 애플리케이션 설정을 제공한다.
# 주요 책임:
#   - API 인증키와 외부 서비스 주소를 불러온다.
#   - 공공 약품 데이터 API의 기본 주소를 제공한다.
#   - 백엔드 전역에서 사용하는 단일 설정 객체를 구성한다.
# 속성:
#   - GEMINI_API_KEY: Gemini API 인증키
#   - PUBLIC_DATA_API_KEY: 공공데이터포털 API 인증키
#   - BASIC_DRUG_API_BASE_URL: e약은요 API 주소
#   - ADVANCED_DRUG_API_BASE_URL: 의약품 허가 상세 API 주소
#   - PILL_IMAGE_API_BASE_URL: 낱알약 식별 API 주소
#   - PILL_IMAGE_API_ENABLED: 식약처 낱알 이미지 보강 사용 여부
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
    model_config = SettingsConfigDict(
        env_file=(_PROJECT_ROOT / ".env", _BACKEND_ROOT / ".env"),
        extra="ignore",
    )

    GEMINI_API_KEY: str = ""
    PUBLIC_DATA_API_KEY: str = ""
    APP_ENV: Literal["development", "test", "production"] = "development"
    RUNTIME_ROLE: Literal["api", "migration", "maintenance", "catalog_sync"] = (
        "api"
    )
    AUTH_MODE: Literal["disabled", "firebase"] = "disabled"
    FIREBASE_PROJECT_ID: str = ""
    FIREBASE_CHECK_REVOKED_TOKENS: bool = False
    FIREBASE_REQUIRE_VERIFIED_EMAIL: bool = True
    FIREBASE_ALLOW_PHONE_AUTH: bool = False
    FIREBASE_ALLOW_ANONYMOUS_AUTH: bool = False
    FIREBASE_APP_CHECK_REQUIRED: bool = False
    TRUSTED_HOSTS: str = (
        "api.medbuddy.pp.ua,localhost,127.0.0.1,backend,testserver"
    )
    ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS: int = Field(
        default=300,
        ge=60,
        le=3600,
        description=(
            "Maximum Firebase auth_time age accepted for permanent deletion "
            "of credential-backed accounts. Anonymous guests are exempt "
            "because Firebase provides no reusable credential for step-up."
        ),
    )
    DATABASE_URL: str = _DEFAULT_DATABASE_URL
    DATABASE_HOST: str = ""
    DATABASE_PORT: int = Field(default=5432, ge=1, le=65535)
    DATABASE_NAME: str = ""
    DATABASE_USER: str = ""
    DATABASE_PASSWORD: str = Field(default="", repr=False)
    AUTO_CREATE_SCHEMA: bool = True
    DATABASE_POOL_SIZE: int = Field(default=5, gt=0, le=20)
    DATABASE_MAX_OVERFLOW: int = Field(default=0, ge=0, le=20)
    DATABASE_POOL_TIMEOUT_SECONDS: int = Field(default=10, gt=0, le=120)
    DATABASE_POOL_RECYCLE_SECONDS: int = Field(default=1_800, gt=0, le=86_400)
    APPLICATION_TIME_ZONE: str = "Asia/Seoul"
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
    PHARMACY_API_BASE_URL: str = (
        "https://apis.data.go.kr/B552657/ErmctInsttInfoInqireService"
    )
    PHARMACY_API_TIMEOUT_SECONDS: float = Field(default=12.0, gt=0, le=120)
    PILL_IMAGE_API_ENABLED: bool = True
    PILL_IMAGE_API_TIMEOUT_SECONDS: float = Field(default=8.0, gt=0, le=120)
    PUBLIC_API_MAX_CONCURRENCY: int = Field(default=6, ge=1, le=20)
    PUBLIC_API_FAILURE_CACHE_SECONDS: int = Field(default=30, ge=1, le=300)
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
    PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH: bool = True
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
    PERIODIC_MAINTENANCE_ENABLED: bool = True
    PERIODIC_MAINTENANCE_INTERVAL_SECONDS: int = Field(
        default=21_600,
        ge=300,
        le=86_400,
    )
    CAREGIVER_ALERT_OUTBOX_POLL_SECONDS: int = Field(
        default=15,
        ge=5,
        le=300,
    )
    CAREGIVER_ALERT_OUTBOX_RETENTION_DAYS: int = Field(
        default=30,
        ge=1,
        le=365,
    )
    HEALTH_RECOMMENDATION_CACHE_RETENTION_DAYS: int = Field(
        default=90,
        ge=1,
        le=365,
    )
    SAVED_MEDICATION_RETENTION_DAYS_AFTER_END: int = Field(
        default=0,
        ge=0,
        le=3650,
        description=(
            "Days to retain ended medication history before maintenance removes "
            "it. Zero preserves ended history until the user deletes it."
        ),
    )
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_REQUIRE_REDIS: bool = False
    REDIS_URL: str = "redis://localhost:6379"
    API_CONTRACT_VERSION: str = _DEFAULT_API_CONTRACT_VERSION

    # 함수이름: build_structured_database_url
    # 함수역할:
    # - 배포 환경이 분리된 PostgreSQL 연결 값을 제공하면 DATABASE_URL을 구성한다.
    # - 비밀번호의 예약 문자가 주소 구분자로 해석되지 않도록 SQLAlchemy에 변환을 맡긴다.
    # 매개변수: values - Pydantic이 수집한 원시 설정값
    # 반환값: 안전하게 구성한 DATABASE_URL을 포함한 설정값
    @model_validator(mode="before")
    @classmethod
    def build_structured_database_url(cls, values: Any) -> Any:
        if not isinstance(values, dict):
            return values

        structured_fields = (
            "DATABASE_HOST",
            "DATABASE_NAME",
            "DATABASE_USER",
            "DATABASE_PASSWORD",
        )
        uses_structured_database = any(
            str(values.get(field_name, "")).strip()
            for field_name in structured_fields
        )
        if not uses_structured_database:
            return values

        missing_fields = [
            field_name
            for field_name in structured_fields
            if not str(values.get(field_name, "")).strip()
        ]
        if missing_fields:
            raise ValueError(
                "Structured database configuration requires "
                + ", ".join(missing_fields)
                + "."
            )
        if str(values.get("DATABASE_URL", "")).strip():
            raise ValueError(
                "Set either DATABASE_URL or structured database fields, not both."
            )

        try:
            database_port = int(values.get("DATABASE_PORT", 5432))
        except (TypeError, ValueError) as exc:
            raise ValueError("DATABASE_PORT must be an integer.") from exc

        database_url = URL.create(
            drivername="postgresql+psycopg",
            username=str(values["DATABASE_USER"]),
            password=str(values["DATABASE_PASSWORD"]),
            host=str(values["DATABASE_HOST"]),
            port=database_port,
            database=str(values["DATABASE_NAME"]),
        )
        rendered_values = dict(values)
        rendered_values["DATABASE_URL"] = database_url.render_as_string(
            hide_password=False
        )
        return rendered_values

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
        "PHARMACY_API_BASE_URL",
    )
    @classmethod
    def validate_external_api_url(cls, value: str) -> str:
        normalized_url = value.strip()
        parsed_url = urlparse(normalized_url)
        if parsed_url.scheme.lower() != "https" or not parsed_url.netloc:
            raise ValueError("External public-data API URL must use HTTPS.")
        return normalized_url

    # 함수이름: validate_trusted_hosts
    # 함수역할:
    # - 운영 ASGI에서 사용하는 쉼표 구분 Host 허용 목록을 정규화한다.
    # - 와일드카드와 빈 설정을 거부해 Host 검증이 우회되지 않게 한다.
    # 매개변수: value - 쉼표로 구분한 호스트 이름 또는 IP 주소
    # 반환값: 정규화된 Host 허용 목록
    @field_validator("TRUSTED_HOSTS")
    @classmethod
    def validate_trusted_hosts(cls, value: str) -> str:
        hosts = [host.strip().lower() for host in value.split(",") if host.strip()]
        if not hosts or "*" in hosts:
            raise ValueError("TRUSTED_HOSTS requires an explicit host allowlist.")
        return ",".join(dict.fromkeys(hosts))

    @property
    def trusted_host_list(self) -> list[str]:
        return self.TRUSTED_HOSTS.split(",")

    # 함수이름: validate_application_time_zone
    # 함수역할:
    # - 복약 일정 계산에 사용할 IANA 시간대 이름이 실제로 존재하는지 검증한다.
    # 매개변수:
    # - value: 환경변수에서 읽은 시간대 이름
    # 반환값:
    # - 앞뒤 공백을 제거한 유효한 IANA 시간대 이름
    @field_validator("APPLICATION_TIME_ZONE")
    @classmethod
    def validate_application_time_zone(cls, value: str) -> str:
        normalized_time_zone = value.strip()
        try:
            ZoneInfo(normalized_time_zone)
        except (ValueError, ZoneInfoNotFoundError) as exc:
            raise ValueError("APPLICATION_TIME_ZONE must be a valid IANA time zone.") from exc
        return normalized_time_zone

    @model_validator(mode="after")
    def validate_security_configuration(self) -> "Settings":
        if self.APP_ENV != "production":
            return self
        if self.RUNTIME_ROLE == "api":
            if not self.GEMINI_API_KEY.strip():
                raise ValueError("Production API requires GEMINI_API_KEY.")
            if not self.PUBLIC_DATA_API_KEY.strip():
                raise ValueError("Production API requires PUBLIC_DATA_API_KEY.")
            if self.AUTH_MODE != "firebase":
                raise ValueError("Production API requires AUTH_MODE=firebase.")
            if not self.FIREBASE_PROJECT_ID.strip():
                raise ValueError("Production API requires FIREBASE_PROJECT_ID.")
            if not self.FIREBASE_APP_CHECK_REQUIRED:
                raise ValueError(
                    "Production API requires FIREBASE_APP_CHECK_REQUIRED=true."
                )
            if not self.RATE_LIMIT_ENABLED:
                raise ValueError("Production API requires RATE_LIMIT_ENABLED=true.")
            if not self.RATE_LIMIT_REQUIRE_REDIS:
                raise ValueError(
                    "Production API requires RATE_LIMIT_REQUIRE_REDIS=true."
                )
            if self.PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH:
                raise ValueError(
                    "Production API requires "
                    "PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH=false."
                )
        if (
            self.RUNTIME_ROLE == "catalog_sync"
            and not self.PUBLIC_DATA_API_KEY.strip()
        ):
            raise ValueError(
                "Production catalog synchronization requires PUBLIC_DATA_API_KEY."
            )
        try:
            database_url = make_url(self.DATABASE_URL)
        except ArgumentError as exc:
            raise ValueError("Production DATABASE_URL is invalid.") from exc
        if database_url.get_backend_name() != "postgresql":
            raise ValueError("Production requires a PostgreSQL DATABASE_URL.")
        if self.AUTO_CREATE_SCHEMA:
            raise ValueError("Production requires AUTO_CREATE_SCHEMA=false.")
        return self


settings = Settings()
