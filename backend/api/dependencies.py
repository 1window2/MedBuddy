# File Name: dependencies.py
# Role: Builds request controls and shared external clients while composing authentication, account registration and quota dependencies.

import asyncio
from collections.abc import AsyncGenerator
from contextlib import AsyncExitStack
from datetime import UTC, datetime, timedelta
import logging
from threading import Lock

from fastapi import Depends, Header, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from boundaries.firebase_identity_boundary import (
    FirebaseIdentityDeletionBoundary,
)
from boundaries.korean_holiday_api_boundary import (
    KoreanHolidayAPI,
    PersistentKoreanHolidayLookup,
)
from boundaries.holiday_emergency_pharmacy_api_boundary import (
    HolidayEmergencyPharmacyAPI,
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
from boundaries.pharmacy_api_boundary import (
    NationalEmergencyMedicalCenterPharmacyAPI,
)
from boundaries.hospital_api_boundary import NationalEmergencyMedicalCenterHospitalAPI
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
from core.account_operation_locks import AccountOperationLocks
from core.account_database_lock import lock_account_operations
from core.database import get_db
from core.request_database_work import run_request_database_work
from core.request_rate_limits import (
    RequestRateLimitStore,
    resolve_rate_limit_rule,
)
from controls.authorization_control import AuthorizationControl
from controls.check_medication_detail_control import (
    CheckMedicationDetail,
)
from boundaries.medication_detail_cache_boundary import MedicationDetailCache
from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy
from controls.check_nearby_hospital_control import CheckNearbyHospital
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
from controls.check_caregiver_monitoring_control import CheckCaregiverMonitoring
from controls.manage_push_token_control import ManagePushToken
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.request_voice_guide_control import RequestVoiceGuide
from controls.set_caregiver_notification_control import SetCaregiverNotification
from controls.set_notification_control import SetNotification
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from repositories.async_pharmacy_catalog import AsyncPharmacyCatalog
from repositories.korean_holiday_cache import SessionScopedKoreanHolidayCache

logger = logging.getLogger(__name__)
_medication_detail_cache: MedicationDetailCache | None = None
_public_drug_transport = _PublicDrugTransport()
_public_drug_small_api = PublicDrugSmallAPI(transport=_public_drug_transport)
_public_drug_large_api = PublicDrugLargeAPI(transport=_public_drug_transport)
_pill_image_api = PillImageAPI(transport=_public_drug_transport)
_pharmacy_api = NationalEmergencyMedicalCenterPharmacyAPI()
_hospital_api = NationalEmergencyMedicalCenterHospitalAPI()
_korean_holiday_api = KoreanHolidayAPI()
_holiday_emergency_pharmacy_api = HolidayEmergencyPharmacyAPI()
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
_sqlite_account_lock_registry = AccountOperationLocks()
_SQLITE_ACCOUNT_LOCK_WAIT_SECONDS = 5.0
_bearer_scheme = HTTPBearer(auto_error=False)

# 공개 정보 조회만 조기에 연결을 반환한다. 사용자 데이터 변경 경로는 포함하지 않는다.
# 건강 추천은 별도로 읽기·저장 양쪽에서 계정 삭제와 연동 변경을 재검증한다.
_DETACHED_LOOKUP_ROUTES = frozenset({
    ("POST", "/api/v1/medication/identify"),
    ("POST", "/api/v1/medication/analyze-prescription-text"),
    ("POST", "/api/v1/medication/pill-identification/candidates"),
    ("POST", "/api/v1/medication/pill-identification/multiple-candidates"),
    ("POST", "/api/v1/medication/voice-guide"),
    ("GET", "/api/v1/pharmacy/nearby"),
    ("GET", "/api/v1/hospitals/nearby"),
    ("GET", "/api/v1/medication/health/recommendation"),
})


# Function Name: get_oidc_token_verifier
# Description:
# - Lazily creates the shared Firebase ID-token verifier under a lock, including the configured revocation policy.
# Parameters:
# - None.
# Returns:
# - Process-shared OIDC token verifier.
def get_oidc_token_verifier() -> OIDCTokenVerifier:
    global _oidc_token_verifier
    with _oidc_token_verifier_lock:
        if _oidc_token_verifier is None:
            _oidc_token_verifier = OIDCTokenVerifier(
                settings.FIREBASE_PROJECT_ID,
                check_revoked=settings.FIREBASE_CHECK_REVOKED_TOKENS,
            )
        return _oidc_token_verifier


# Function Name: get_app_check_token_verifier
# Description:
# - Lazily creates the shared Firebase App Check verifier for the configured project under a lock.
# Parameters:
# - None.
# Returns:
# - Process-shared application-attestation verifier.
def get_app_check_token_verifier() -> AppCheckTokenVerifier:
    global _app_check_token_verifier
    with _app_check_token_verifier_lock:
        if _app_check_token_verifier is None:
            _app_check_token_verifier = AppCheckTokenVerifier(
                settings.FIREBASE_PROJECT_ID
            )
        return _app_check_token_verifier


# Function Name: verify_app_check_token
# Description:
# - Enforces App Check when enabled, mapping invalid tokens to HTTP 403 and verifier outages to retryable HTTP 503.
# Parameters:
# - x_firebase_appcheck (str | None): Firebase application-attestation token from the request header.
# Returns:
# - None.
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


# Function Name: get_authenticated_principal
# Description:
# - Verifies the bearer token and enforces configured provider and verified-email policies, or returns the explicit development identity.
# Parameters:
# - credentials (HTTPAuthorizationCredentials | None): Optional HTTP bearer credentials from the request.
# Returns:
# - Trusted principal; HTTP 401/403 for rejected authentication and 503 for verifier outages.
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
# - Requires recent verified Firebase authentication for irreversible account deletion; anonymous and authentication-disabled identities are exempt.
# Parameters:
# - principal (AuthenticatedPrincipal): Server-verified identity and trusted account scope.
# Returns:
# - Same principal when its authentication time meets policy, or HTTP 401 requesting a new sign-in.
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
# - Uses a transaction-scoped PostgreSQL advisory lock in beta deployments and a short SQLite write transaction while registering the account scope.
# - SQLite request-lifetime serialization is provided by the per-account lock retained by get_registered_principal because endpoint controls commit.
# Parameters:
# - db (Session): Request-scoped SQLAlchemy session shared by endpoint controls.
# - user_hash (str): Server-derived account scope used only as a lock namespace.
# Returns:
# - None. PostgreSQL holds the lock for its transaction; SQLite holds it until account registration commits inside _register_account_scope.
def _lock_account_operation(db: Session, user_hash: str) -> None:
    if db.in_transaction():
        return
    lock_account_operations(db, [user_hash])


# 함수이름: _register_account_scope
# 함수역할:
# - 계정 작업 잠금을 획득하고 삭제 표식을 검사해 사용자를 등록하며 SQLite의 짧은 쓰기 트랜잭션은 즉시 커밋한다.
# 매개변수:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# 반환값:
# - 없음.
def _register_account_scope(db: Session, user_hash: str) -> None:
    """Acquires the account lock and rejects deleted account tombstones."""

    _lock_account_operation(db, user_hash)
    ManageAccount(db).ensureAccount(user_hash)
    # 로컬 SQLite는 데이터베이스 전체에 쓰기 잠금을 잡으므로 사용자 확인 직후
    # 해제한다. 실제 요청 처리까지 잠금을 유지하면 앱 초기 병렬 조회가 503으로
    # 실패한다. 운영 PostgreSQL의 사용자 단위 잠금은 기존대로 요청 끝까지 유지한다.
    if db.get_bind().dialect.name == "sqlite":
        db.commit()


# 외부 조회 등록과 연결 반환을 한 작업으로 묶어 중간에 연결을 빌린 채 대기하지 않는다.
# 함수이름: _register_detached_lookup_scope
# 함수역할: 인증 계정 등록을 commit하고 실패·취소 시 rollback한다.
# 매개변수: db: 요청 세션, user_hash: 인증된 계정 식별자. 반환값: 없음.
def _register_detached_lookup_scope(db: Session, user_hash: str) -> None:
    try:
        _register_account_scope(db, user_hash)
        db.commit()
    except BaseException:
        db.rollback()
        raise


# Function Name: get_registered_principal
# Description:
# - Enforces per-user request quotas and account registration, holding the SQLite account lock through endpoint execution and allowing deletion retries.
# Parameters:
# - request (Request): Incoming FastAPI request used to access application state.
# - principal (AuthenticatedPrincipal): Server-verified identity and trusted account scope.
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Yields the registered principal once; releases the SQLite lock during dependency teardown.
async def get_registered_principal(
    request: Request,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    db: Session = Depends(get_db),
) -> AsyncGenerator[AuthenticatedPrincipal, None]:
    route = request.scope.get("route")
    route_path = str(getattr(route, "path", request.url.path))
    detach_registration = (request.method.upper(), route_path) in _DETACHED_LOOKUP_ROUTES
    resolved_rule = resolve_rate_limit_rule(
        request.method,
        route_path,
    )
    if settings.RATE_LIMIT_ENABLED and resolved_rule is not None:
        rule, canonical_path = resolved_rule
        try:
            rate_limit_store = get_request_rate_limit_store(request)
            allowed, retry_after = await rate_limit_store.consume(
                identity=f"user:{principal.user_hash}",
                request_scope=f"{request.method.upper()}:{canonical_path}",
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
    # Step 1: Hold SQLite ownership through registration and endpoint teardown.
    async with AsyncExitStack() as account_scope:
        # 공개 조회와 재검증형 추천은 DB 단계만 잠그고 외부 응답 대기에는 계정을 붙잡지 않는다.
        if db.get_bind().dialect.name == "sqlite" and not detach_registration:
            try:
                await account_scope.enter_async_context(
                    _sqlite_account_lock_registry.hold(
                        principal.user_hash,
                        timeout=_SQLITE_ACCOUNT_LOCK_WAIT_SECONDS,
                    )
                )
            except TimeoutError as exc:
                raise HTTPException(
                    status_code=503,
                    detail="This account is busy. Retry the request shortly.",
                    headers={"Retry-After": "5"},
                ) from exc

        # Step 2: Keep PostgreSQL registration off-loop and map account failures.
        try:
            register_scope = (
                _register_detached_lookup_scope if detach_registration else _register_account_scope
            )
            # 외부 조회의 짧은 등록도 잠금 대기 때문에 이벤트 루프를 막지 않게 한다.
            bind = db.get_bind()
            # 연결마다 DB가 분리되는 인메모리 SQLite의 기존 실행 스레드는 유지한다.
            file_backed_sqlite = (
                bind.dialect.name == "sqlite"
                and bind.engine.url.database not in {None, "", ":memory:"}
            )
            if bind.dialect.name == "postgresql" or (detach_registration and file_backed_sqlite):
                await run_request_database_work(
                    register_scope,
                    db,
                    principal.user_hash,
                )
            else:
                register_scope(db, principal.user_hash)
        except AccountDeletionPendingError as exc:
            is_account_deletion_retry = (
                request.method.upper() == "DELETE"
                and request.url.path == "/api/v1/auth/account-data"
            )
            if not is_account_deletion_retry:
                raise HTTPException(
                    status_code=410,
                    detail="This MedBuddy account has been deleted.",
                ) from exc
        except OperationalError as exc:
            db.rollback()
            raise HTTPException(
                status_code=503,
                detail="This account is busy. Retry the request shortly.",
                headers={"Retry-After": "5"},
            ) from exc

        # Step 3: Yield the principal; the scope handles every cleanup path.
        yield principal


# 함수이름: get_authenticated_app_principal
# 함수역할:
# - App Check·사용자 인증·계정 등록·호출 제한을 채팅 REST 요청의 공통 보호 의존성으로 묶는다.
# 매개변수:
# - _app_check (None): App Check 선행 검증 완료 표식.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# 반환값:
# - 선행 검증과 등록을 통과한 동일 사용자 주체.
async def get_authenticated_app_principal(
    _app_check: None = Depends(verify_app_check_token),
    principal: AuthenticatedPrincipal = Depends(get_registered_principal),
) -> AuthenticatedPrincipal:
    return principal


# Function Name: get_request_rate_limit_store
# Description:
# - Reads the application's initialized quota store and rejects missing or invalid shared state.
# Parameters:
# - request (Request): Incoming FastAPI request used to access application state.
# Returns:
# - Application-wide RequestRateLimitStore.
def get_request_rate_limit_store(request: Request) -> RequestRateLimitStore:
    rate_limit_store = getattr(request.app.state, "request_rate_limit_store", None)
    if not isinstance(rate_limit_store, RequestRateLimitStore):
        raise RuntimeError("Request rate-limit store is not initialized.")
    return rate_limit_store


# 함수이름: get_push_notification_boundary
# 함수역할:
# - 인증 모드에 맞는 푸시 전송 경계를 애플리케이션 단위로 생성하고 재사용한다.
# 매개변수:
# - 없음.
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


# Function Name: get_authorization_control
# Description:
# - Binds patient/guardian scope resolution to the request database session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - AuthorizationControl for the current request.
def get_authorization_control(
    db: Session = Depends(get_db),
) -> AuthorizationControl:
    return AuthorizationControl(db=db)


# Function Name: get_manage_account
# Description:
# - Binds account export/deletion to the request session and enables external identity deletion only in Firebase mode.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - ManageAccount with the authentication-mode-appropriate deletion boundary.
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


# Function Name: get_medication_detail_cache
# Description:
# - Lazily reuses a process-wide Redis medication-detail cache.
# Parameters:
# - None.
# Returns:
# - Shared medication-detail cache instance.
async def get_medication_detail_cache() -> MedicationDetailCache:
    global _medication_detail_cache
    if _medication_detail_cache is None:
        _medication_detail_cache = MedicationDetailCache()
    return _medication_detail_cache


# Function Name: close_medication_detail_cache
# Description:
# - Clears the shared cache reference and closes its client, logging shutdown failures without interrupting other cleanup.
# Parameters:
# - None.
# Returns:
# - None.
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


# 함수이름: close_public_drug_boundaries
# 함수역할:
# - 공공데이터 API가 공유하는 HTTP 연결 풀을 서버 종료 시 정리한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
async def close_public_drug_boundaries() -> None:
    try:
        await _public_drug_transport.close()
    except Exception as exc:
        logger.warning(
            "Public drug API transport shutdown failed: %s",
            type(exc).__name__,
        )


# 함수이름: close_pharmacy_boundary
# 함수역할:
# - 약국 공공데이터 API가 재사용한 HTTP 연결 풀을 서버 종료 시 정리한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
async def close_pharmacy_boundary() -> None:
    for boundary in (
        _pharmacy_api,
        _korean_holiday_api,
        _holiday_emergency_pharmacy_api,
    ):
        try:
            await boundary.close()
        except Exception as exc:
            # 한 경계의 종료 실패가 다른 연결 풀 정리를 막지 않게 각각 처리한다.
            logger.warning(
                "Pharmacy API boundary shutdown failed: %s",
                type(exc).__name__,
            )


# 병원 경계의 공유 캐시와 연결을 서버 종료 시 회수한다.
async def close_hospital_boundary() -> None:
    await _hospital_api.close()


# Function Name: get_input_prescription
# Description:
# - Binds OCR prescription parsing and local catalog verification to the request session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped InputPrescription control.
def get_input_prescription(
    db: Session = Depends(get_db),
) -> InputPrescription:
    return InputPrescription(db=db)


# Function Name: _get_pill_identification_boundaries
# Description:
# - Creates and reuses visual-analysis and MFDS catalog boundaries under a shared initialization lock.
# Parameters:
# - None.
# Returns:
# - Shared vision and catalog boundary pair.
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


# Function Name: close_pill_identification_boundaries
# Description:
# - Releases reusable external clients and invalidates in-memory catalog data.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: get_identify_pill
# Description:
# - Builds pill identification from shared visual/catalog boundaries and the process-wide ranking semaphore.
# Parameters:
# - None.
# Returns:
# - IdentifyPill control with bounded concurrent ranking.
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
# - Binds local drug lookup to the request session while reusing Redis and public drug/image clients.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# - medication_cache (MedicationDetailCache): Shared Redis cache of medication detail results.
# Returns:
# - Request-scoped CheckMedicationDetail control.
def get_check_medication_detail(
    db: Session = Depends(get_db),
    medication_cache: MedicationDetailCache = Depends(
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


# 함수이름: get_check_nearby_pharmacy
# 함수역할:
# - 공유 약국 API와 DB 카탈로그·공휴일 캐시를 연결해 위치 기반 조회를 구성한다.
# 매개변수:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# 반환값:
# - 독립적인 작업 세션을 사용하는 CheckNearbyPharmacy.
def get_check_nearby_pharmacy(
    db: Session = Depends(get_db),
) -> CheckNearbyPharmacy:
    session_factory = sessionmaker(bind=db.get_bind())
    return CheckNearbyPharmacy(
        pharmacy_boundary=_pharmacy_api,
        pharmacy_repository=AsyncPharmacyCatalog(session_factory),
        holiday_boundary=PersistentKoreanHolidayLookup(
            cache=SessionScopedKoreanHolidayCache(session_factory),
            upstream=_korean_holiday_api,
        ),
        holiday_emergency_boundary=_holiday_emergency_pharmacy_api,
    )


# 요청 DB의 검증된 공휴일 캐시만 공유하고 약국 당번표와 지정 정보는 사용하지 않는다.
def get_check_nearby_hospital(
    db: Session = Depends(get_db),
) -> CheckNearbyHospital:
    return CheckNearbyHospital(
        _hospital_api,
        holiday_boundary=PersistentKoreanHolidayLookup(
            cache=SessionScopedKoreanHolidayCache(sessionmaker(bind=db.get_bind())),
            upstream=_korean_holiday_api,
        ),
    )


# 함수이름: get_check_prescription_change
# 함수역할:
# - 요청 단위 DB 세션을 포함한 처방 변화 비교 Control을 생성한다.
# 매개변수:
# - db (Session): FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckPrescriptionChange 인스턴스
def get_check_prescription_change(
    db: Session = Depends(get_db),
) -> CheckPrescriptionChange:
    return CheckPrescriptionChange(db=db)


# Function Name: get_check_saved_medication
# Description:
# - Binds pillbox persistence and retrieval to the request database session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped CheckSavedMedication control.
def get_check_saved_medication(
    db: Session = Depends(get_db),
) -> CheckSavedMedication:
    return CheckSavedMedication(db=db)


# 함수이름: get_check_schedule
# 함수역할:
# - 요청 범위 DB 세션을 사용하는 복약 일정 Control을 생성한다.
# 매개변수:
# - db (Session): FastAPI 의존성 주입으로 받은 SQLAlchemy 세션
# 반환값:
# - CheckSchedule 인스턴스
def get_check_schedule(
    db: Session = Depends(get_db),
) -> CheckSchedule:
    return CheckSchedule(db=db)


# 함수이름: get_manage_push_token
# 함수역할:
# - 요청 단위 DB 세션을 사용하는 기기 푸시 토큰 관리 Control을 생성한다.
# 매개변수:
# - db (Session): FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - ManagePushToken 인스턴스
def get_manage_push_token(
    db: Session = Depends(get_db),
) -> ManagePushToken:
    return ManagePushToken(db=db)


# Function Name: get_check_today_medication_info
# Description:
# - Binds daily dose totals and completion summaries to the request database session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped CheckTodayMedicationInfo control.
def get_check_today_medication_info(
    db: Session = Depends(get_db),
) -> CheckTodayMedicationInfo:
    return CheckTodayMedicationInfo(db=db)


# Function Name: get_check_health_recommendation
# Description:
# - Binds medication-based health guidance and its persisted cache to the request database session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped CheckHealthRecommendation control.
def get_check_health_recommendation(
    db: Session = Depends(get_db),
) -> CheckHealthRecommendation:
    return CheckHealthRecommendation(db=db)


# Function Name: get_link_patient_caregiver_control
# Description:
# - Binds temporary patient-code and caregiver-link operations to the request session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped LinkPatientCaregiver control.
def get_link_patient_caregiver_control(
    db: Session = Depends(get_db),
) -> LinkPatientCaregiver:
    return LinkPatientCaregiver(db=db)


# 함수이름: get_manage_linked_chat
# 함수역할:
# - 요청 세션을 사용해 활성 환자·보호자 연동 채팅 Control을 구성한다.
# 매개변수:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# 반환값:
# - 요청 범위 ManageLinkedChat.
def get_manage_linked_chat(
    db: Session = Depends(get_db),
) -> ManageLinkedChat:
    return ManageLinkedChat(db=db)


# Function Name: get_check_caregiver_medication
# Description:
# - Binds read-only linked-patient medication lookup to the request session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped CheckCaregiverMedication control.
def get_check_caregiver_medication(
    db: Session = Depends(get_db),
) -> CheckCaregiverMedication:
    return CheckCaregiverMedication(db=db)


# 함수이름: get_check_caregiver_monitoring
# 함수역할:
# - 연동 환자들의 알림 설정과 오늘 복약 감시 정보를 조회할 Control을 구성한다.
# 매개변수:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# 반환값:
# - 요청 범위 CheckCaregiverMonitoring.
def get_check_caregiver_monitoring(
    db: Session = Depends(get_db),
) -> CheckCaregiverMonitoring:
    return CheckCaregiverMonitoring(db=db)


# Function Name: get_set_notification
# Description:
# - Binds patient medication-alarm preferences to the request database session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped SetNotification control.
def get_set_notification(
    db: Session = Depends(get_db),
) -> SetNotification:
    return SetNotification(db=db)


# Function Name: get_set_caregiver_notification
# Description:
# - Binds linked-patient caregiver notification preferences to the request session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped SetCaregiverNotification control.
def get_set_caregiver_notification(
    db: Session = Depends(get_db),
) -> SetCaregiverNotification:
    return SetCaregiverNotification(db=db)


# Function Name: get_manage_user_setting
# Description:
# - Binds accessibility, language and notification preferences to the request session.
# Parameters:
# - db (Session): SQLAlchemy session for this unit of work.
# Returns:
# - Request-scoped ManageUserSetting control.
def get_manage_user_setting(
    db: Session = Depends(get_db),
) -> ManageUserSetting:
    return ManageUserSetting(db=db)


# Function Name: get_request_voice_guide
# Description:
# - Creates the stateless adapter that prepares speech text from medication details.
# Parameters:
# - None.
# Returns:
# - RequestVoiceGuide control.
def get_request_voice_guide() -> RequestVoiceGuide:
    return RequestVoiceGuide()
