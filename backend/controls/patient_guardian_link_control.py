# File Name: patient_guardian_link_control.py
# Role: Control mapped from the PatientGuardianLinkControl box in ClassDiagram2.

import logging
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from entities.patient_guardian_link_entity import (
    PatientGuardianLink,
    _PatientGuardianLink,
    _PatientLinkCode,
)
from entities.patient_hash_entity import (
    DEFAULT_PATIENT_HASH,
    PatientHash,
    normalize_patient_hash,
)

_PATIENT_CODE_TTL_MINUTES = 15
_MAX_CODE_GENERATION_ATTEMPTS = 10
# "caregiver" is accepted only as a legacy API role alias.
_GUARDIAN_ROLES = {"guardian", "caregiver"}
_PATIENT_ROLES = {"patient"}
logger = logging.getLogger(__name__)


def _utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: PatientGuardianLinkControl
# Role: Coordinates patient-guardian linking and unlinking.
# Responsibilities:
#   - Create temporary patient link codes.
#   - Register a guardian with a valid patient code.
#   - List or unlink existing patient-guardian links.
# Attributes:
#   - db: SQLAlchemy session used for link persistence operations.
class PatientGuardianLinkControl:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestPatientGuardianLink
    # Description:
    # - Class diagram compatible wrapper for the link page lookup.
    # Parameters:
    # - user_hash: Patient or guardian ownership key.
    # Returns:
    # - API-compatible link list response dictionary.
    def requestPatientGuardianLink(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_link_page(user_hash)

    # Function Name: requestLinkPage
    # Description:
    # - Class diagram compatible wrapper for reading link rows.
    # Parameters:
    # - user_hash: Patient or guardian ownership key.
    # Returns:
    # - API-compatible link list response dictionary.
    def requestLinkPage(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_link_page(user_hash)

    # Function Name: request_link_page
    # Description:
    # - Lists active links that include the current patient or guardian.
    # Parameters:
    # - user_hash: Patient or guardian ownership key.
    # Returns:
    # - API-compatible link list response dictionary.
    def request_link_page(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        links = (
            self.db.query(_PatientGuardianLink)
            .filter(
                _PatientGuardianLink.linked.is_(True),
                or_(
                    _PatientGuardianLink.patient_hash == normalized_user_hash,
                    _PatientGuardianLink.guardian_hash == normalized_user_hash,
                ),
            )
            .order_by(_PatientGuardianLink.id.asc())
            .all()
        )
        return {
            "success": True,
            "message": "Patient-guardian link lookup succeeded.",
            "data": [self._to_response_dict(link) for link in links],
        }

    # Function Name: request_patient_code
    # Description:
    # - Creates a temporary patient link code for guardian registration.
    # Parameters:
    # - patient_hash: Patient ownership key encoded in the generated code.
    # Returns:
    # - API-compatible code response dictionary.
    def request_patient_code(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        expires_at = _utc_now() + timedelta(minutes=_PATIENT_CODE_TTL_MINUTES)

        try:
            patient_code = self._generate_unique_patient_code(normalized_patient_hash)
            link_code = _PatientLinkCode(
                patient_hash=normalized_patient_hash,
                patient_code=patient_code,
                expires_at=expires_at,
            )
            self.db.add(link_code)
            self.db.commit()
            self.db.refresh(link_code)
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Patient link code creation failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Patient link code could not be created.",
            ) from exc

        return {
            "success": True,
            "message": "Patient link code was created.",
            "data": {
                "patient_hash": link_code.patient_hash,
                "patient_code": link_code.patient_code,
                "expires_at": link_code.expires_at.isoformat(),
            },
        }

    # Function Name: createPatientCode
    # Description:
    # - Class diagram compatible wrapper for creating a temporary patient code.
    # Parameters:
    # - patient_hash: Patient ownership key encoded in the generated code.
    # Returns:
    # - API-compatible code response dictionary.
    def createPatientCode(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_patient_code(patient_hash)

    # Function Name: registerPatientCode
    # Description:
    # - Class diagram compatible wrapper for guardian registration.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_code: Temporary patient code.
    # Returns:
    # - API-compatible link response dictionary.
    def registerPatientCode(
        self,
        guardian_hash: str,
        patient_code: str,
    ) -> dict[str, object]:
        return self.register_patient_code(guardian_hash, patient_code)

    # Function Name: register_patient_code
    # Description:
    # - Validates a patient code and creates or restores the guardian link.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_code: Temporary patient code.
    # Returns:
    # - API-compatible link response dictionary.
    def register_patient_code(
        self,
        guardian_hash: str,
        patient_code: str,
    ) -> dict[str, object]:
        normalized_guardian_hash = normalize_patient_hash(guardian_hash)
        normalized_patient_code = self._normalize_patient_code(patient_code)
        link_code = self._get_valid_link_code(normalized_patient_code)

        if link_code.patient_hash == normalized_guardian_hash:
            raise HTTPException(
                status_code=400,
                detail="A guardian cannot link to the same patient hash.",
            )

        try:
            reserved_count = (
                self.db.query(_PatientLinkCode)
                .filter(
                    _PatientLinkCode.id == link_code.id,
                    _PatientLinkCode.used.is_(False),
                )
                .update(
                    {
                        "used": True,
                        "guardian_hash": normalized_guardian_hash,
                    },
                    synchronize_session=False,
                )
            )
            if reserved_count != 1:
                raise HTTPException(
                    status_code=409,
                    detail="Patient code was already used.",
                )

            link = self._get_existing_pair(
                link_code.patient_hash,
                normalized_guardian_hash,
            )
            if link is None:
                link_state = PatientGuardianLink(
                    patient_id=link_code.patient_hash,
                    guardian_id=normalized_guardian_hash,
                ).createPatientGuardianLink()
                link = _PatientGuardianLink(
                    patient_hash=link_state.patient_id,
                    guardian_hash=link_state.guardian_id,
                    linked=link_state.linked,
                )
                self.db.add(link)
                self.db.flush()
            else:
                link_state = PatientGuardianLink(
                    link_id=link.id,
                    patient_id=link.patient_hash,
                    guardian_id=link.guardian_hash,
                    linked=link.linked,
                ).createPatientGuardianLink()
                link.linked = link_state.linked

            self.db.commit()
            self.db.refresh(link)
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Patient-guardian link registration failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Patient-guardian link could not be registered.",
            ) from exc

        return {
            "success": True,
            "message": "Patient-guardian link was created.",
            "data": self._to_response_dict(link),
        }

    # Function Name: requestUnlink
    # Description:
    # - Class diagram compatible wrapper for unlinking.
    # Parameters:
    # - link_id: Link row identifier.
    # - user_hash: Patient or guardian ownership key allowed to unlink.
    # Returns:
    # - API-compatible unlink response dictionary.
    def requestUnlink(
        self,
        link_id: int,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_unlink(link_id, user_hash)

    # Function Name: deletePatientGuardianLink
    # Description:
    # - Class diagram compatible wrapper for unlinking one patient-guardian link.
    # Parameters:
    # - link_id: Link row identifier.
    # - user_hash: Patient or guardian ownership key allowed to unlink.
    # Returns:
    # - API-compatible unlink response dictionary.
    def deletePatientGuardianLink(
        self,
        link_id: int,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_unlink(link_id, user_hash)

    # Function Name: request_unlink
    # Description:
    # - Soft-deletes a link when the requester participates in that link.
    # Parameters:
    # - link_id: Link row identifier.
    # - user_hash: Patient or guardian ownership key allowed to unlink.
    # Returns:
    # - API-compatible unlink response dictionary.
    def request_unlink(
        self,
        link_id: int,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        link = (
            self.db.query(_PatientGuardianLink)
            .filter(
                _PatientGuardianLink.id == link_id,
                _PatientGuardianLink.linked.is_(True),
                or_(
                    _PatientGuardianLink.patient_hash == normalized_user_hash,
                    _PatientGuardianLink.guardian_hash == normalized_user_hash,
                ),
            )
            .first()
        )
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Patient-guardian link was not found.",
            )

        try:
            link_state = PatientGuardianLink(
                link_id=link.id,
                patient_id=link.patient_hash,
                guardian_id=link.guardian_hash,
                linked=link.linked,
            ).deletePatientGuardianLink()
            link.linked = link_state.linked
            self.db.commit()
            self.db.refresh(link)
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Patient-guardian unlink failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Patient-guardian link could not be removed.",
            ) from exc

        return {
            "success": True,
            "message": "Patient-guardian link was removed.",
            "data": self._to_response_dict(link),
        }

    # Function Name: getLinkedPatientHash
    # Description:
    # - Reads the first linked patient hash for a guardian.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # Returns:
    # - Linked patient hash.
    def getLinkedPatientHash(
        self,
        guardian_hash: str,
        patient_hash: str | None = None,
    ) -> str:
        return self.get_linked_patient_hash(guardian_hash, patient_hash)

    # Function Name: resolve_patient_scope
    # Description:
    # - Resolves the patient scope for direct patient and linked guardian requests.
    # Parameters:
    # - patient_hash: Optional selected patient hash.
    # - user_hash: Requesting user hash.
    # - role: Requesting user role.
    # Returns:
    # - Patient hash authorized for this request.
    def resolve_patient_scope(
        self,
        patient_hash: str | None = None,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        normalized_role = (role or "patient").strip().lower()
        if normalized_role in _GUARDIAN_ROLES:
            if not user_hash or not user_hash.strip():
                raise HTTPException(
                    status_code=400,
                    detail="user_hash is required for guardian access.",
                )
            return self.get_linked_patient_hash(
                user_hash,
                patient_hash,
            )
        if normalized_role not in _PATIENT_ROLES:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported medication access role: {role}",
            )

        normalized_patient_hash = normalize_patient_hash(patient_hash or user_hash)
        if user_hash and patient_hash:
            normalized_user_hash = normalize_patient_hash(user_hash)
            if normalized_user_hash != normalized_patient_hash:
                raise HTTPException(
                    status_code=403,
                    detail="Patient access cannot target another patient hash.",
                )
        return normalized_patient_hash

    # Function Name: get_linked_patient_hash
    # Description:
    # - Reads the first linked patient hash for a guardian.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # Returns:
    # - Linked patient hash.
    def get_linked_patient_hash(
        self,
        guardian_hash: str,
        patient_hash: str | None = None,
    ) -> str:
        normalized_guardian_hash = normalize_patient_hash(guardian_hash)
        query = self.db.query(_PatientGuardianLink).filter(
            _PatientGuardianLink.guardian_hash == normalized_guardian_hash,
            _PatientGuardianLink.linked.is_(True),
        )
        requested_patient_hash = (patient_hash or "").strip()
        if requested_patient_hash:
            normalized_patient_hash = normalize_patient_hash(requested_patient_hash)
            query = query.filter(
                _PatientGuardianLink.patient_hash == normalized_patient_hash
            )

        link = query.order_by(_PatientGuardianLink.id.asc()).first()
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Linked patient was not found.",
            )
        return str(link.patient_hash)

    def _normalize_patient_code(self, patient_code: str) -> str:
        normalized_patient_code = (patient_code or "").strip().upper()
        if not normalized_patient_code:
            raise HTTPException(status_code=400, detail="Patient code is required.")
        return normalized_patient_code

    def _generate_unique_patient_code(self, patient_hash: str) -> str:
        for _ in range(_MAX_CODE_GENERATION_ATTEMPTS):
            patient_code = PatientHash(patient_hash=patient_hash).generatePatientHash()
            existing_code = (
                self.db.query(_PatientLinkCode)
                .filter(_PatientLinkCode.patient_code == patient_code)
                .first()
            )
            if existing_code is None:
                return patient_code
        raise RuntimeError("Unable to generate a unique patient link code.")

    def _get_valid_link_code(self, patient_code: str) -> _PatientLinkCode:
        normalized_patient_code = self._normalize_patient_code(patient_code)

        link_code = (
            self.db.query(_PatientLinkCode)
            .filter(
                _PatientLinkCode.patient_code == normalized_patient_code,
                _PatientLinkCode.used.is_(False),
            )
            .first()
        )
        if link_code is None or link_code.expires_at < _utc_now():
            raise HTTPException(
                status_code=404,
                detail="Patient code was not found or has expired.",
            )
        return link_code

    def _get_existing_pair(
        self,
        patient_hash: str,
        guardian_hash: str,
    ) -> _PatientGuardianLink | None:
        return (
            self.db.query(_PatientGuardianLink)
            .filter(
                _PatientGuardianLink.patient_hash == patient_hash,
                _PatientGuardianLink.guardian_hash == guardian_hash,
            )
            .first()
        )

    def _to_response_dict(self, link: _PatientGuardianLink) -> dict[str, object]:
        return {
            "id": link.id,
            "patient_hash": link.patient_hash,
            "guardian_hash": link.guardian_hash,
            "caregiver_hash": link.guardian_hash,
            "linked": link.linked,
            "created_at": link.created_at.isoformat() if link.created_at else "",
        }
