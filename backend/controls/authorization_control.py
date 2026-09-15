# File Name: authorization_control.py
# Role: Resolves trusted account and patient data scopes, including explicitly allowed active caregiver links.
"""Server-side authorization policy for MedBuddy ownership scopes."""

from fastapi import HTTPException
from sqlalchemy.orm import Session

from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_hash_entity import normalize_patient_hash
from entities.user_account_entity import _UserAccount
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)


# 클래스명: AuthorizationControl
# 역할:
# - 인증 주체와 활성 환자 연동을 기준으로 데이터 접근 범위를 결정한다.
# 주요 책임:
# - 검증된 본인 범위와 허용된 활성 보호자 연동만 승인하고 필요한 사용자 기준 행을 보장한다.
# 속성:
# - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
# - link_repository: 활성 환자·보호자 연동 저장소.
class AuthorizationControl:
    """Resolves trusted user and patient scopes from an authenticated principal."""

    # 함수이름: __init__
    # 함수역할:
    # - 사용자 등록 세션과 환자·보호자 연동 저장소를 준비한다.
    # 매개변수:
    # - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
    # 반환값:
    # - 없음.
    def __init__(self, db: Session | None) -> None:
        self.db = db
        self.link_repository = (
            PatientCaregiverLinkRepository(db) if db is not None else None
        )

    # 함수이름: resolveOwnUserHash
    # 함수역할:
    # - 인증 모드에서는 검증된 사용자, 개발 모드에서는 요청한 사용자 범위를 등록한다.
    # 매개변수:
    # - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
    # - requested_user_hash (str | None): 선택적 클라이언트 식별자; 인증 모드에서는 검증된 사용자를 사용한다.
    # 반환값:
    # - 등록된 내부 사용자 식별자.
    def resolveOwnUserHash(
        self,
        principal: AuthenticatedPrincipal,
        requested_user_hash: str | None = None,
    ) -> str:
        if principal.authentication_disabled:
            return self._ensure_user_account(requested_user_hash)
        return self._ensure_user_account(principal.user_hash)

    # 함수이름: resolvePatientScope
    # 함수역할:
    # - 본인 범위를 기본으로 사용하고 허용된 보호자 조회에만 활성 연동 환자를 선택한다.
    # 매개변수:
    # - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
    # - requested_patient_hash (str | None): 인증 주체와 연동 권한으로 확인할 선택적 환자 식별자.
    # - allow_caregiver (bool): 활성 보호자 연동으로 다른 환자 조회를 허용할지 여부.
    # 반환값:
    # - 접근 가능한 환자 식별자; 권한이 없으면 HTTP 403.
    def resolvePatientScope(
        self,
        principal: AuthenticatedPrincipal,
        requested_patient_hash: str | None = None,
        *,
        allow_caregiver: bool = False,
    ) -> str:
        if principal.authentication_disabled:
            return self._ensure_user_account(requested_patient_hash)

        if not allow_caregiver:
            return self._ensure_user_account(principal.user_hash)

        requested = (requested_patient_hash or "").strip()
        if not requested or requested == principal.user_hash:
            return self._ensure_user_account(principal.user_hash)
        if allow_caregiver and self._has_active_link(principal.user_hash, requested):
            return self._ensure_user_account(requested)
        raise HTTPException(status_code=403, detail="Patient scope is not permitted.")

    # Function Name: requireLinkedPatient
    # Description:
    # - Requires an active caregiver link before exposing the selected patient; development mode only normalizes the selector.
    # Parameters:
    # - principal (AuthenticatedPrincipal): Server-verified identity and trusted account scope.
    # - patient_hash (str): Patient ownership scope for the operation.
    # Returns:
    # - Normalized patient identifier, or HTTP 403 when no active link exists.
    def requireLinkedPatient(
        self,
        principal: AuthenticatedPrincipal,
        patient_hash: str,
    ) -> str:
        if principal.authentication_disabled:
            return normalize_patient_hash(patient_hash)
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        if not self._has_active_link(principal.user_hash, normalized_patient_hash):
            raise HTTPException(
                status_code=403,
                detail="An active patient-caregiver link is required.",
            )
        return normalized_patient_hash

    # 함수이름: _ensure_user_account
    # 함수역할:
    # - 식별자를 정규화하고 세션이 있으면 누락된 사용자 기준 행을 추가·flush한다.
    # 매개변수:
    # - user_hash (str | None): 작업 대상 계정의 데이터 소유 범위 식별자.
    # 반환값:
    # - 정규화된 사용자 식별자.
    def _ensure_user_account(self, user_hash: str | None) -> str:
        normalized_user_hash = normalize_patient_hash(user_hash)
        if self.db is None:
            return normalized_user_hash
        if self.db.get(_UserAccount, normalized_user_hash) is None:
            self.db.add(_UserAccount(user_hash=normalized_user_hash))
            self.db.flush()
        return normalized_user_hash

    # 함수이름: _has_active_link
    # 함수역할:
    # - 저장소에서 보호자와 환자의 활성 연동 존재 여부를 확인한다.
    # 매개변수:
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # 반환값:
    # - 활성 연동이면 True; DB 또는 저장소가 없으면 False.
    def _has_active_link(self, caregiver_hash: str, patient_hash: str) -> bool:
        if self.db is None:
            return False
        if self.link_repository is None:
            return False
        return self.link_repository.has_active_pair(caregiver_hash, patient_hash)
