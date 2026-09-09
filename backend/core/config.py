# File Name: config.py
# Role: Loads and validates backend environment, database, authentication and external-service settings.

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


# Class Name: Settings
# Role:
# - Provides validated application configuration from environment values.
# Responsibilities:
# - Load external API keys and public-drug service URLs.
# - Build the shared backend settings instance and validate database, host and time-zone values.
# - Reject unsafe production authentication, storage and rate-limiting combinations.
# Attributes:
# - GEMINI_API_KEY (str): Gemini API credential.
# - PUBLIC_DATA_API_KEY (str): Government public-data credential.
# - BASIC_DRUG_API_BASE_URL (str): Consumer medication-information endpoint.
# - ADVANCED_DRUG_API_BASE_URL (str): Drug approval-detail endpoint.
# - PILL_IMAGE_API_BASE_URL (str): MFDS pill-identification endpoint.
# - PILL_IMAGE_API_ENABLED (bool): Enables optional MFDS image enrichment.
# - PILL_IMAGE_API_TIMEOUT_SECONDS (float): Maximum optional image lookup duration.
# - PILL_IDENTIFICATION_MODEL_NAME (str): Visual feature extraction model.
# - PILL_IDENTIFICATION_TIMEOUT_SECONDS (float): Maximum pill image analysis duration.
# - PILL_IDENTIFICATION_CATALOG_TTL_HOURS (int): Local MFDS snapshot lifetime.
# - PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS (float): Maximum full refresh duration.
# - PILL_IDENTIFICATION_KPIC_PRODUCT_FLOOR (int): Dated KPIC product-count floor required before publication.
# - PRESCRIPTION_OCR_TIMEOUT_SECONDS (float): Maximum structured OCR request duration.
# - PRESCRIPTION_NAME_FALLBACK_TIMEOUT_SECONDS (float): Maximum optional AI correction duration.
# - MEDICATION_SUMMARY_TIMEOUT_SECONDS (float): Maximum approval-summary duration.
# - HEALTH_RECOMMENDATION_TIMEOUT_SECONDS (float): Maximum recommendation duration.
# - REDIS_URL (str): Redis cache and distributed-counter URL.
# - DATABASE_URL (str): Effective SQLAlchemy database URL.
# - APP_ENV / RUNTIME_ROLE (str): Environment and process role selecting production safeguards.
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
    FIREBASE_OFF_PLAY_BETA_MODE: bool = False
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
    PILL_IDENTIFICATION_KPIC_PRODUCT_FLOOR: int = Field(
        default=24_667,
        ge=1_000,
        le=50_000,
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
    CHAT_MESSAGE_DAILY_LIMIT: int = Field(default=500, ge=50, le=10_000)
    CHAT_MESSAGE_RETENTION_DAYS: int = Field(
        default=90,
        ge=1,
        le=3650,
        description="환자·보호자 채팅 메시지를 보관하는 일수",
    )
    CHAT_PUSH_MIN_INTERVAL_SECONDS: int = Field(default=10, ge=1, le=300)
    CHAT_WEBSOCKET_MAX_CONNECTIONS_PER_USER: int = Field(
        default=3,
        ge=1,
        le=10,
    )
    CHAT_WEBSOCKET_CONNECTIONS_PER_MINUTE: int = Field(
        default=12,
        ge=1,
        le=120,
    )
    CHAT_WEBSOCKET_IDLE_TIMEOUT_SECONDS: int = Field(
        default=90,
        ge=30,
        le=600,
    )
    CHAT_WEBSOCKET_MIN_PING_INTERVAL_SECONDS: int = Field(
        default=10,
        ge=1,
        le=60,
    )
    CHAT_WEBSOCKET_MAX_FRAME_BYTES: int = Field(
        default=4_096,
        ge=256,
        le=65_536,
    )
    API_CONTRACT_VERSION: str = _DEFAULT_API_CONTRACT_VERSION

    # Function Name: build_structured_database_url
    # Description:
    # - Build a PostgreSQL URL from complete structured fields, letting SQLAlchemy escape reserved password characters; reject mixed URL/field configuration.
    # Parameters:
    # - values (Any): Raw settings values collected by Pydantic before validation.
    # Returns:
    # - Original nonmapping or unstructured values, or a copied mapping with the rendered DATABASE_URL.
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
    # - value (str): 환경변수에서 읽은 외부 API 주소
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

    # Function Name: validate_trusted_hosts
    # Description:
    # - Normalize and deduplicate the comma-separated host allowlist; reject empty lists and the unrestricted wildcard.
    # Parameters:
    # - value (str): Comma-separated allowed hostnames or IP addresses.
    # Returns:
    # - Lowercase, comma-separated explicit hosts.
    @field_validator("TRUSTED_HOSTS")
    @classmethod
    def validate_trusted_hosts(cls, value: str) -> str:
        hosts = [host.strip().lower() for host in value.split(",") if host.strip()]
        if not hosts or "*" in hosts:
            raise ValueError("TRUSTED_HOSTS requires an explicit host allowlist.")
        return ",".join(dict.fromkeys(hosts))

    # Function Name: trusted_host_list
    # Description:
    # - Expose the validated host allowlist as entries suitable for host-checking middleware.
    # Parameters:
    # - None.
    # Returns:
    # - Hostnames or IP addresses split from TRUSTED_HOSTS.
    @property
    def trusted_host_list(self) -> list[str]:
        return self.TRUSTED_HOSTS.split(",")

    # 함수이름: validate_application_time_zone
    # 함수역할:
    # - 복약 일정 계산에 사용할 IANA 시간대 이름이 실제로 존재하는지 검증한다.
    # 매개변수:
    # - value (str): 환경변수에서 읽은 시간대 이름
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

    # Function Name: validate_security_configuration
    # Description:
    # - Validate production requirements by runtime role, including credentials, authentication, Redis quotas, catalog refresh mode and PostgreSQL migrations.
    # Parameters:
    # - None.
    # Returns:
    # - This Settings instance when accepted; raises ValueError for an unsafe production configuration.
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
            if (
                not self.FIREBASE_APP_CHECK_REQUIRED
                and not self.FIREBASE_OFF_PLAY_BETA_MODE
            ):
                raise ValueError(
                    "Production API requires FIREBASE_APP_CHECK_REQUIRED=true "
                    "unless FIREBASE_OFF_PLAY_BETA_MODE=true is explicitly set."
                )
            if (
                self.FIREBASE_APP_CHECK_REQUIRED
                and self.FIREBASE_OFF_PLAY_BETA_MODE
            ):
                raise ValueError(
                    "FIREBASE_OFF_PLAY_BETA_MODE requires "
                    "FIREBASE_APP_CHECK_REQUIRED=false."
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
