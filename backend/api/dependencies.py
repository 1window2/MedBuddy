# File Name: dependencies.py
# Role: Provides FastAPI dependency factories for backend use-case collaborators.

from _thread import LockType
import asyncio
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
import logging
from threading import Lock

from fastapi import Depends, Header, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from boundaries.firebase_identity_boundary import (
    FirebaseIdentityDeletionBoundary,
)
from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    PillVisionBoundary,
)
from boundaries.public_drug_api_boundary import (
    PillImageAPI,
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
    _PublicDrugTransport,
)
from boundaries.oidc_token_verifier_boundary import (
    OIDCTokenVerifier,
    TokenVerificationError,
    TokenVerificationUnavailableError,
)
from boundaries.app_check_token_verifier_boundary import (
    AppCheckTokenVerificationError,
    AppCheckTokenVerificationUnavailableError,
    AppCheckTokenVerifier,
)
from boundaries.push_notification_boundary import (
    DisabledPushNotificationBoundary,
    FirebasePushNotificationBoundary,
    PushNotificationBoundary,
)
from core.config import settings
from core.database import get_db
from core.request_rate_limits import (
    DEFAULT_RATE_LIMIT_RULES,
    RequestRateLimitStore,
)
from controls.authorization_control import AuthorizationControl
from controls.check_medication_detail_control import (
    CheckMedicationDetail,
    _MedicationDetailCache,
)
from controls.check_prescription_change_control import CheckPrescriptionChange
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.input_prescription_control import InputPrescription
from controls.identify_pill_control import IdentifyPill
from controls.manage_user_setting_control import ManageUserSetting
from controls.manage_account_control import (
    AccountDeletionPendingError,
    ManageAccount,
)
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.check_health_recommendation_control import CheckHealthRecommendation
from controls.check_caregiver_medication_control import CheckCaregiverMedication
from controls.manage_push_token_control import ManagePushToken
from controls.request_voice_guide_control import RequestVoiceGuide
from controls.set_caregiver_notification_control import SetCaregiverNotification
from controls.set_notification_control import SetNotification
from entities.authenticated_principal_entity import AuthenticatedPrincipal

logger = logging.getLogger(__name__)
_medication_detail_cache: _MedicationDetailCache | None = None
_public_drug_transport = _PublicDrugTransport()
_public_drug_small_api = PublicDrugSmallAPI(transport=_public_drug_transport)
_public_drug_large_api = PublicDrugLargeAPI(transport=_public_drug_transport)
_pill_image_api = PillImageAPI(transport=_public_drug_transport)
_pill_boundary_lock = Lock()
_pill_vision_boundary: PillVisionBoundary | None = None
_pill_catalog_boundary: MFDSPillCatalogBoundary | None = None
_pill_ranking_semaphore = asyncio.Semaphore(2)
_oidc_token_verifier_lock = Lock()
_oidc_token_verifier: OIDCTokenVerifier | None = None
_app_check_token_verifier_lock = Lock()
_app_check_token_verifier: AppCheckTokenVerifier | None = None
_push_notification_boundary_lock = Lock()
_push_notification_boundary: PushNotificationBoundary | None = None
_sqlite_account_lock_registry_guard = Lock()
_sqlite_account_locks: dict[str, LockType] = {}
_sqlite_account_lock_references: dict[str, int] = {}
_bearer_scheme = HTTPBearer(auto_error=False)


def get_oidc_token_verifier() -> OIDCTokenVerifier:
    global _oidc_token_verifier
    with _oidc_token_verifier_lock:
        if _oidc_token_verifier is None:
            _oidc_token_verifier = OIDCTokenVerifier(
                settings.FIREBASE_PROJECT_ID,
                check_revoked=settings.FIREBASE_CHECK_REVOKED_TOKENS,
            )
        return _oidc_token_verifier


def get_app_check_token_verifier() -> AppCheckTokenVerifier:
    global _app_check_token_verifier
    with _app_check_token_verifier_lock:
        if _app_check_token_verifier is None:
            _app_check_token_verifier = AppCheckTokenVerifier(
                settings.FIREBASE_PROJECT_ID
            )
        return _app_check_token_verifier


def verify_app_check_token(
    x_firebase_appcheck: str | None = Header(default=None),
) -> None:
    if not settings.FIREBASE_APP_CHECK_REQUIRED:
        return
    if x_firebase_appcheck is None or not x_firebase_appcheck.strip():
        raise HTTPException(
            status_code=403,
            detail="A Firebase App Check token is required.",
        )
    try:
        get_app_check_token_verifier().verifyToken(x_firebase_appcheck)
    except AppCheckTokenVerificationUnavailableError as exc:
        raise HTTPException(
            status_code=503,
            detail="App attestation verification is temporarily unavailable.",
            headers={"Retry-After": "5"},
        ) from exc
    except AppCheckTokenVerificationError as exc:
        raise HTTPException(
            status_code=403,
            detail="The Firebase App Check token is invalid or expired.",
        ) from exc


def get_authenticated_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> AuthenticatedPrincipal:
    if settings.AUTH_MODE == "disabled":
        return AuthenticatedPrincipal.development_principal()
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="A Firebase bearer token is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        claims = get_oidc_token_verifier().verifyIdToken(credentials.credentials)
        principal = AuthenticatedPrincipal.from_verified_claims(claims)
    except TokenVerificationUnavailableError as exc:
        logger.warning(
            "Firebase token verification is unavailable: %s",
            type(exc.__cause__).__name__ if exc.__cause__ else type(exc).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Authentication verification is temporarily unavailable.",
            headers={"Retry-After": "5"},
        ) from exc
    except (TokenVerificationError, ValueError) as exc:
        raise HTTPException(
            status_code=401,
            detail="The Firebase bearer token is invalid or expired.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    if principal.anonymous and not settings.FIREBASE_ALLOW_ANONYMOUS_AUTH:
        raise HTTPException(
            status_code=403,
            detail="Anonymous Firebase authentication is disabled.",
        )
    if (
        principal.sign_in_provider == "phone"
        and not settings.FIREBASE_ALLOW_PHONE_AUTH
    ):
        raise HTTPException(
            status_code=403,
            detail="Phone Firebase authentication is disabled.",
        )
    provider_requires_verified_email = principal.sign_in_provider not in {
        "anonymous",
        "phone",
    }
    if (
        settings.FIREBASE_REQUIRE_VERIFIED_EMAIL
        and provider_requires_verified_email
        and (not principal.email or not principal.email_verified)
    ):
        raise HTTPException(
            status_code=403,
            detail="A verified email address is required.",
        )
    return principal

# Function Name: get_recently_authenticated_principal
# Description:
# - Requires recent Firebase authentication before irreversible account deletion.
# - Preserves the authenticated server-derived subject and explicitly exempts
#   anonymous guests because they have no reusable credential for step-up auth.
# Parameters:
# - principal: Verified request principal supplied by Firebase authentication.
# Returns:
# - The same principal when the deletion freshness policy is satisfied.
def get_recently_authenticated_principal(
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
) -> AuthenticatedPrincipal:
    if principal.authentication_disabled or principal.anonymous:
        return principal

    authenticated_at = principal.authenticated_at
    now = datetime.now(UTC)
    maximum_age = timedelta(
        seconds=settings.ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS
    )
    if (
        authenticated_at is None
        or authenticated_at > now + timedelta(seconds=60)
        or now - authenticated_at > maximum_age
    ):
        raise HTTPException(
            status_code=401,
            detail=(
                "Recent authentication is required before deleting this account. "
                "Sign in again and retry."
            ),
            headers={"WWW-Authenticate": "Bearer"},
        )
    return principal


# Function Name: _lock_account_operation
# Description:
# - Serializes each authenticated account request with account deletion.
# - Uses a transaction-scoped PostgreSQL advisory lock in beta deployments and
#   a short SQLite write transaction while registering the account scope.
# - SQLite request-lifetime serialization is provided by the per-account lock
#   retained by get_registered_principal because endpoint controls commit.
# Parameters:
# - db: Request-scoped SQLAlchemy session shared by endpoint controls.
# - user_hash: Server-derived account scope used only as a lock namespace.
# Returns:
# - None. PostgreSQL holds the lock for its transaction; SQLite holds it until
#   account registration commits inside _register_account_scope.
def _lock_account_operation(db: Session, user_hash: str) -> None:
    if db.in_transaction():
        return
    dialect_name = db.get_bind().dialect.name
    if dialect_name == "postgresql":
        db.execute(
            text("SELECT set_config('lock_timeout', :timeout, true)"),
            {"timeout": "5s"},
        )
        db.execute(
            text(
                "SELECT pg_advisory_xact_lock("
                "hashtextextended(:user_hash, 0))"
            ),
            {"user_hash": user_hash},
        )
        return
    if dialect_name == "sqlite":
        db.connection().exec_driver_sql("BEGIN IMMEDIATE")
        return
    raise RuntimeError(
        "Authenticated account-operation locking requires PostgreSQL or SQLite."
    )


def _register_account_scope(db: Session, user_hash: str) -> None:
    """Acquires the account lock and rejects deleted account tombstones."""

    _lock_account_operation(db, user_hash)
    ManageAccount(db).ensureAccount(user_hash)
    # 로컬 SQLite는 데이터베이스 전체에 쓰기 잠금을 잡으므로 사용자 확인 직후
    # 해제한다. 실제 요청 처리까지 잠금을 유지하면 앱 초기 병렬 조회가 503으로
    # 실패한다. 운영 PostgreSQL의 사용자 단위 잠금은 기존대로 요청 끝까지 유지한다.
    if db.get_bind().dialect.name == "sqlite":
        db.commit()


# Function Name: _retain_sqlite_account_lock
# Description:
# - Returns one process-local lock per authenticated account for SQLite mode.
# - Reference counting removes idle locks so anonymous account churn cannot grow
#   the registry without bound.
# Parameters:
# - user_hash: Server-derived account scope used as the serialization key.
# Returns:
# - The retained per-account lock.
def _retain_sqlite_account_lock(user_hash: str) -> LockType:
    with _sqlite_account_lock_registry_guard:
        account_lock = _sqlite_account_locks.setdefault(user_hash, Lock())
        _sqlite_account_lock_references[user_hash] = (
            _sqlite_account_lock_references.get(user_hash, 0) + 1
        )
        return account_lock


# Function Name: _drop_sqlite_account_lock_reference
# Description:
# - Releases one registry reference and removes an idle per-account lock.
# Parameters:
# - user_hash: Server-derived account scope used as the serialization key.
# - account_lock: Exact lock instance retained for the current request.
# Returns:
# - None.
def _drop_sqlite_account_lock_reference(
    user_hash: str,
    account_lock: LockType,
) -> None:
    with _sqlite_account_lock_registry_guard:
        references = _sqlite_account_lock_references.get(user_hash, 0) - 1
        if references <= 0 and _sqlite_account_locks.get(user_hash) is account_lock:
            _sqlite_account_lock_references.pop(user_hash, None)
            _sqlite_account_locks.pop(user_hash, None)
            return
        _sqlite_account_lock_references[user_hash] = references


# Function Name: _release_sqlite_account_lock
# Description:
# - Releases request ownership before dropping its registry reference.
# Parameters:
# - user_hash: Server-derived account scope used as the serialization key.
# - account_lock: Lock held for the completed request.
# Returns:
# - None.
def _release_sqlite_account_lock(user_hash: str, account_lock: LockType) -> None:
    account_lock.release()
    _drop_sqlite_account_lock_reference(user_hash, account_lock)

# 함수명: get_registered_principal
# 역할:
# - 검증된 인증 주체를 내부 user_accounts 범위에 등록하고 반환한다.
# - 보호된 모든 API에서 FK 기준 사용자가 먼저 존재하도록 보장한다.
async def get_registered_principal(
    request: Request,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    db: Session = Depends(get_db),
) -> AsyncGenerator[AuthenticatedPrincipal, None]:
    rule = DEFAULT_RATE_LIMIT_RULES.get(
        (request.method.upper(), request.url.path)
    )
    if settings.RATE_LIMIT_ENABLED and rule is not None:
        try:
            rate_limit_store = get_request_rate_limit_store(request)
            allowed, retry_after = await rate_limit_store.consume(
                identity=f"user:{principal.user_hash}",
                request_scope=f"{request.method.upper()}:{request.url.path}",
                rule=rule,
            )
        except RuntimeError as exc:
            raise HTTPException(
                status_code=503,
                detail="Request quota storage is temporarily unavailable.",
                headers={"Retry-After": "5"},
            ) from exc
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="요청이 너무 많습니다. 잠시 후 다시 시도해주세요.",
                headers={"Retry-After": str(max(1, retry_after))},
            )
    sqlite_account_lock: LockType | None = None
    if db.get_bind().dialect.name == "sqlite":
        sqlite_account_lock = _retain_sqlite_account_lock(principal.user_hash)
        acquired = await run_in_threadpool(
            sqlite_account_lock.acquire,
            True,
            5.0,
        )
        if not acquired:
            _drop_sqlite_account_lock_reference(
                principal.user_hash,
                sqlite_account_lock,
            )
            raise HTTPException(
                status_code=503,
                detail="This account is busy. Retry the request shortly.",
                headers={"Retry-After": "5"},
            )

    try:
        if db.get_bind().dialect.name == "postgresql":
            await run_in_threadpool(
                _register_account_scope,
                db,
                principal.user_hash,
            )
        else:
            _register_account_scope(db, principal.user_hash)
    except AccountDeletionPendingError as exc:
        is_account_deletion_retry = (
            request.method.upper() == "DELETE"
            and request.url.path == "/api/v1/auth/account-data"
        )
        if is_account_deletion_retry:
            pass
        else:
            if sqlite_account_lock is not None:
                _release_sqlite_account_lock(
                    principal.user_hash,
                    sqlite_account_lock,
                )
                sqlite_account_lock = None
            raise HTTPException(
                status_code=410,
                detail="This MedBuddy account has been deleted.",
            ) from exc
    except OperationalError as exc:
        db.rollback()
        if sqlite_account_lock is not None:
            _release_sqlite_account_lock(
                principal.user_hash,
                sqlite_account_lock,
            )
            sqlite_account_lock = None
        raise HTTPException(
            status_code=503,
            detail="This account is busy. Retry the request shortly.",
            headers={"Retry-After": "5"},
        ) from exc
    except BaseException:
        if sqlite_account_lock is not None:
            _release_sqlite_account_lock(
                principal.user_hash,
                sqlite_account_lock,
            )
            sqlite_account_lock = None
        raise
    try:
        yield principal
    finally:
        if sqlite_account_lock is not None:
            _release_sqlite_account_lock(
                principal.user_hash,
                sqlite_account_lock,
            )


def get_request_rate_limit_store(request: Request) -> RequestRateLimitStore:
    rate_limit_store = getattr(request.app.state, "request_rate_limit_store", None)
    if not isinstance(rate_limit_store, RequestRateLimitStore):
        raise RuntimeError("Request rate-limit store is not initialized.")
    return rate_limit_store


# 함수명: get_push_notification_boundary
# 역할:
# - 인증 모드에 맞는 푸시 전송 경계를 애플리케이션 단위로 생성하고 재사용한다.
# 반환값:
# - Firebase 또는 비활성 푸시 전송 경계
def get_push_notification_boundary() -> PushNotificationBoundary:
    global _push_notification_boundary
    with _push_notification_boundary_lock:
        if _push_notification_boundary is None:
            if settings.AUTH_MODE == "firebase":
                _push_notification_boundary = FirebasePushNotificationBoundary(
                    settings.FIREBASE_PROJECT_ID
                )
            else:
                _push_notification_boundary = DisabledPushNotificationBoundary()
        return _push_notification_boundary


def get_authorization_control(
    db: Session = Depends(get_db),
) -> AuthorizationControl:
    return AuthorizationControl(db=db)


def get_manage_account(
    db: Session = Depends(get_db),
) -> ManageAccount:
    identity_boundary = (
        FirebaseIdentityDeletionBoundary(settings.FIREBASE_PROJECT_ID)
        if settings.AUTH_MODE == "firebase"
        else None
    )
    return ManageAccount(
        db=db,
        identity_deletion_boundary=identity_boundary,
    )


async def get_medication_detail_cache() -> _MedicationDetailCache:
    global _medication_detail_cache
    if _medication_detail_cache is None:
        _medication_detail_cache = _MedicationDetailCache()
    return _medication_detail_cache


async def close_medication_detail_cache() -> None:
    global _medication_detail_cache
    medication_detail_cache = _medication_detail_cache
    _medication_detail_cache = None
    if medication_detail_cache is None:
        return
    try:
        await medication_detail_cache.close()
    except Exception as exc:
        logger.warning(
            "Medication detail cache shutdown failed: %s",
            type(exc).__name__,
        )


# 함수명: close_public_drug_boundaries
# 역할:
# - 공공데이터 API가 공유하는 HTTP 연결 풀을 서버 종료 시 정리한다.
async def close_public_drug_boundaries() -> None:
    try:
        await _public_drug_transport.close()
    except Exception as exc:
        logger.warning(
            "Public drug API transport shutdown failed: %s",
            type(exc).__name__,
        )


# Function Name: get_input_prescription
# Description:
# - Builds the image prescription analysis control service.
# Returns:
# - InputPrescription instance.
def get_input_prescription(
    db: Session = Depends(get_db),
) -> InputPrescription:
    return InputPrescription(db=db)


def _get_pill_identification_boundaries() -> tuple[
    PillVisionBoundary,
    MFDSPillCatalogBoundary,
]:
    global _pill_vision_boundary, _pill_catalog_boundary
    with _pill_boundary_lock:
        if _pill_vision_boundary is None:
            _pill_vision_boundary = PillVisionBoundary()
        if _pill_catalog_boundary is None:
            _pill_catalog_boundary = MFDSPillCatalogBoundary()
        return _pill_vision_boundary, _pill_catalog_boundary


async def close_pill_identification_boundaries() -> None:
    """Releases reusable external clients and invalidates in-memory catalog data."""

    global _pill_vision_boundary, _pill_catalog_boundary
    with _pill_boundary_lock:
        vision_boundary = _pill_vision_boundary
        catalog_boundary = _pill_catalog_boundary
        _pill_vision_boundary = None
        _pill_catalog_boundary = None
    if catalog_boundary is not None:
        catalog_boundary.invalidateMemoryCache()
    if vision_boundary is None:
        return
    try:
        await vision_boundary.close()
    except Exception as exc:
        logger.warning(
            "Pill identification boundary shutdown failed: %s",
            type(exc).__name__,
        )


def get_identify_pill() -> IdentifyPill:
    """Builds the experimental loose-pill identification control."""

    vision_boundary, catalog_boundary = _get_pill_identification_boundaries()
    return IdentifyPill(
        vision_boundary=vision_boundary,
        catalog_boundary=catalog_boundary,
        ranking_semaphore=_pill_ranking_semaphore,
    )


# Function Name: get_check_medication_detail
# Description:
# - Builds the medication detail lookup control service with optional local DB access.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckMedicationDetail instance.
def get_check_medication_detail(
    db: Session = Depends(get_db),
    medication_cache: _MedicationDetailCache = Depends(
        get_medication_detail_cache
    ),
) -> CheckMedicationDetail:
    return CheckMedicationDetail(
        db=db,
        medication_cache=medication_cache,
        public_drug_small_api=_public_drug_small_api,
        public_drug_large_api=_public_drug_large_api,
        pill_image_api=_pill_image_api,
    )


# 함수이름: get_check_prescription_change
# 함수역할:
# - 요청 단위 DB 세션을 포함한 처방 변화 비교 Control을 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckPrescriptionChange 인스턴스
def get_check_prescription_change(
    db: Session = Depends(get_db),
) -> CheckPrescriptionChange:
    return CheckPrescriptionChange(db=db)


# Function Name: get_check_saved_medication
# Description:
# - Builds the saved medication control service with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckSavedMedication instance.
def get_check_saved_medication(
    db: Session = Depends(get_db),
) -> CheckSavedMedication:
    return CheckSavedMedication(db=db)


# Function Name: get_check_schedule
# Description:
# - Builds the medication schedule control service with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckSchedule instance.
def get_check_schedule(
    db: Session = Depends(get_db),
) -> CheckSchedule:
    return CheckSchedule(db=db)


# 함수명: get_manage_push_token
# 역할:
# - 요청 단위 DB 세션을 사용하는 기기 푸시 토큰 관리 Control을 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - ManagePushToken 인스턴스
def get_manage_push_token(
    db: Session = Depends(get_db),
) -> ManagePushToken:
    return ManagePushToken(db=db)


# Function Name: get_check_today_medication_info
# Description:
# - Builds the today medication summary control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckTodayMedicationInfo instance.
def get_check_today_medication_info(
    db: Session = Depends(get_db),
) -> CheckTodayMedicationInfo:
    return CheckTodayMedicationInfo(db=db)


# Function Name: get_check_health_recommendation
# 함수역할:
# - 요청 단위 DB 세션을 포함한 건강 관리 추천 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckHealthRecommendation instance.
def get_check_health_recommendation(
    db: Session = Depends(get_db),
) -> CheckHealthRecommendation:
    return CheckHealthRecommendation(db=db)


# Function Name: get_link_patient_caregiver_control
# Description:
# - Builds the patient-caregiver link control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - LinkPatientCaregiver instance.
def get_link_patient_caregiver_control(
    db: Session = Depends(get_db),
) -> LinkPatientCaregiver:
    return LinkPatientCaregiver(db=db)


# Function Name: get_check_caregiver_medication
# Description:
# - Builds the read-only caregiver medication control for one request.
def get_check_caregiver_medication(
    db: Session = Depends(get_db),
) -> CheckCaregiverMedication:
    return CheckCaregiverMedication(db=db)


# Function Name: get_set_notification
# Description:
# - Builds the medication alarm control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - SetNotification instance.
def get_set_notification(
    db: Session = Depends(get_db),
) -> SetNotification:
    return SetNotification(db=db)


# Function Name: get_set_caregiver_notification
# Description:
# - Builds the caregiver notification control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - SetCaregiverNotification instance.
def get_set_caregiver_notification(
    db: Session = Depends(get_db),
) -> SetCaregiverNotification:
    return SetCaregiverNotification(db=db)


# Function Name: get_manage_user_setting
# Description:
# - Builds the user setting control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - ManageUserSetting instance.
def get_manage_user_setting(
    db: Session = Depends(get_db),
) -> ManageUserSetting:
    return ManageUserSetting(db=db)


# Function Name: get_request_voice_guide
# Description:
# - Builds the medication voice guide text control.
# Returns:
# - RequestVoiceGuide instance.
def get_request_voice_guide() -> RequestVoiceGuide:
    return RequestVoiceGuide()
