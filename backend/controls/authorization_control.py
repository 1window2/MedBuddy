"""Server-side authorization policy for MedBuddy ownership scopes."""

from fastapi import HTTPException
from sqlalchemy.orm import Session

from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_hash_entity import normalize_patient_hash
from entities.user_account_entity import _UserAccount
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)


class AuthorizationControl:
    """Resolves trusted user and patient scopes from an authenticated principal."""

    def __init__(self, db: Session | None) -> None:
        self.db = db
        self.link_repository = (
            PatientCaregiverLinkRepository(db) if db is not None else None
        )

    def resolveOwnUserHash(
        self,
        principal: AuthenticatedPrincipal,
        requested_user_hash: str | None = None,
    ) -> str:
        if principal.authentication_disabled:
            return self._ensure_user_account(requested_user_hash)
        return self._ensure_user_account(principal.user_hash)

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

    # 함수명: _ensure_user_account
    # 역할:
    # - 로컬 임의 hash를 포함해 FK가 참조할 사용자 범위를 현재 트랜잭션에 준비한다.
    def _ensure_user_account(self, user_hash: str | None) -> str:
        normalized_user_hash = normalize_patient_hash(user_hash)
        if self.db is None:
            return normalized_user_hash
        if self.db.get(_UserAccount, normalized_user_hash) is None:
            self.db.add(_UserAccount(user_hash=normalized_user_hash))
            self.db.flush()
        return normalized_user_hash

    def _has_active_link(self, caregiver_hash: str, patient_hash: str) -> bool:
        if self.db is None:
            return False
        if self.link_repository is None:
            return False
        return self.link_repository.has_active_pair(caregiver_hash, patient_hash)
