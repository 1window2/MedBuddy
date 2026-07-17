# File Name: link_patient_caregiver_control.py
# Role: Control mapped from LinkPatientCaregiver in integrated class diagram v5.

import logging
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from entities.caregiver_notification_entity import _CaregiverNotification
from entities.patient_caregiver_link_entity import (
    PatientCaregiverLink,
    PatientLinkCode,
    _PatientCaregiverLink,
    _PatientLinkCode,
)
from entities.patient_hash_entity import (
    DEFAULT_PATIENT_HASH,
    PatientHash,
    normalize_patient_hash,
)

_PATIENT_CODE_TTL_MINUTES = 15
_MAX_CODE_GENERATION_ATTEMPTS = 10
logger = logging.getLogger(__name__)


def _utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: LinkPatientCaregiver
# Role: Coordinates patient-caregiver linking and unlinking.
# Responsibilities:
#   - Create temporary patient link codes.
#   - Register a caregiver with a valid patient code.
#   - List or unlink existing patient-caregiver links.
# Attributes:
#   - db: SQLAlchemy session used for link persistence operations.
class LinkPatientCaregiver:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestLinkScreen
    # Description:
    # - Lists active links that include the current patient or caregiver.
    # Parameters:
    # - user_hash: Patient or caregiver ownership key.
    # Returns:
    # - API-compatible link list response dictionary.
    def requestLinkScreen(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        links = (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.linked.is_(True),
                or_(
                    _PatientCaregiverLink.patient_hash == normalized_user_hash,
                    _PatientCaregiverLink.caregiver_hash == normalized_user_hash,
                ),
            )
            .order_by(_PatientCaregiverLink.id.asc())
            .all()
        )
        return {
            "success": True,
            "message": "Patient-caregiver link lookup succeeded.",
            "data": [self._to_response_dict(link) for link in links],
        }

    # Function Name: generatePatientHash
    # Description:
    # - Creates a temporary patient link code for caregiver registration.
    # Parameters:
    # - patient_hash: Patient ownership key encoded in the generated code.
    # Returns:
    # - API-compatible code response dictionary.
    def generatePatientHash(
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

        patient_link_code = PatientLinkCode(
            code=link_code.patient_code,
            patient_hash=link_code.patient_hash,
            expires_at=link_code.expires_at,
        )
        return {
            "success": True,
            "message": "Patient link code was created.",
            "data": patient_link_code.to_response_dict(),
        }

    # Function Name: requestPatientCaregiverLink
    # Description:
    # - Validates a patient code and creates or restores the caregiver link.
    # Parameters:
    # - caregiver_hash: Caregiver ownership key.
    # - patient_code: Temporary patient code.
    # Returns:
    # - API-compatible link response dictionary.
    def requestPatientCaregiverLink(
        self,
        caregiver_hash: str,
        patient_code: str,
    ) -> dict[str, object]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        normalized_patient_code = self._normalize_patient_code(patient_code)
        link_code = self._get_valid_link_code(normalized_patient_code)

        if link_code.patient_hash == normalized_caregiver_hash:
            raise HTTPException(
                status_code=400,
                detail="A caregiver cannot link to the same patient hash.",
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
                        "caregiver_hash": normalized_caregiver_hash,
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
                normalized_caregiver_hash,
            )
            if link is None:
                link_state = PatientCaregiverLink(
                    patient_hash=link_code.patient_hash,
                    caregiver_hash=normalized_caregiver_hash,
                ).savePatientCaregiverLink()
                link = _PatientCaregiverLink(
                    patient_hash=link_state.patient_hash,
                    caregiver_hash=link_state.caregiver_hash,
                    linked=link_state.link_status,
                )
                self.db.add(link)
                self.db.flush()
            else:
                link_state = PatientCaregiverLink(
                    link_id=link.id,
                    patient_hash=link.patient_hash,
                    caregiver_hash=link.caregiver_hash,
                    link_status=link.linked,
                    linked_at=link.created_at,
                ).savePatientCaregiverLink()
                link.linked = link_state.link_status

            self.db.commit()
            self.db.refresh(link)
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Patient-caregiver link registration failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Patient-caregiver link could not be registered.",
            ) from exc

        return {
            "success": True,
            "message": "Patient-caregiver link was created.",
            "data": self._to_response_dict(link),
        }

    # Function Name: requestUnlink
    # Description:
    # - Soft-deletes a link when the requester participates in that link.
    # Parameters:
    # - link_id: Link row identifier.
    # - user_hash: Patient or caregiver ownership key allowed to unlink.
    # Returns:
    # - API-compatible unlink response dictionary.
    def requestUnlink(
        self,
        link_id: int,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        link = (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.id == link_id,
                _PatientCaregiverLink.linked.is_(True),
                or_(
                    _PatientCaregiverLink.patient_hash == normalized_user_hash,
                    _PatientCaregiverLink.caregiver_hash == normalized_user_hash,
                ),
            )
            .first()
        )
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Patient-caregiver link was not found.",
            )

        try:
            link_state = PatientCaregiverLink(
                link_id=link.id,
                patient_hash=link.patient_hash,
                caregiver_hash=link.caregiver_hash,
                link_status=link.linked,
                linked_at=link.created_at,
            ).removePatientCaregiverLink()
            link.linked = link_state.link_status
            self._revoke_caregiver_notification(link)
            self.db.commit()
            self.db.refresh(link)
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Patient-caregiver unlink failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Patient-caregiver link could not be removed.",
            ) from exc

        return {
            "success": True,
            "message": "Patient-caregiver link was removed.",
            "data": self._to_response_dict(link),
        }

    def _revoke_caregiver_notification(
        self,
        link: _PatientCaregiverLink,
    ) -> None:
        self.db.query(_CaregiverNotification).filter(
            _CaregiverNotification.patient_hash == link.patient_hash,
            _CaregiverNotification.caregiver_hash == link.caregiver_hash,
        ).delete(synchronize_session=False)

    # Function Name: getLinkedPatientHash
    # Description:
    # - Reads the selected linked patient hash for a caregiver.
    # Parameters:
    # - caregiver_hash: Caregiver ownership key.
    # Returns:
    # - Linked patient hash.
    def getLinkedPatientHash(
        self,
        caregiver_hash: str,
        patient_hash: str | None = None,
    ) -> str:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        query = self.db.query(_PatientCaregiverLink).filter(
            _PatientCaregiverLink.caregiver_hash == normalized_caregiver_hash,
            _PatientCaregiverLink.linked.is_(True),
        )
        requested_patient_hash = (patient_hash or "").strip()
        if requested_patient_hash:
            normalized_patient_hash = normalize_patient_hash(requested_patient_hash)
            query = query.filter(
                _PatientCaregiverLink.patient_hash == normalized_patient_hash
            )

        link = query.order_by(_PatientCaregiverLink.id.asc()).first()
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
            patient_code = PatientHash(patient_hash=patient_hash).createPatientHash()
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
        if not PatientHash().validatePatientHash(normalized_patient_code):
            raise HTTPException(status_code=400, detail="Patient code is invalid.")

        link_code = (
            self.db.query(_PatientLinkCode)
            .filter(
                _PatientLinkCode.patient_code == normalized_patient_code,
                _PatientLinkCode.used.is_(False),
            )
            .first()
        )
        if link_code is None:
            raise HTTPException(
                status_code=404,
                detail="Patient code was not found or has expired.",
            )
        patient_link_code = PatientLinkCode(
            code=link_code.patient_code,
            patient_hash=link_code.patient_hash,
            expires_at=link_code.expires_at,
        )
        if patient_link_code.isExpired(_utc_now()):
            raise HTTPException(
                status_code=404,
                detail="Patient code was not found or has expired.",
            )
        return link_code

    def _get_existing_pair(
        self,
        patient_hash: str,
        caregiver_hash: str,
    ) -> _PatientCaregiverLink | None:
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.patient_hash == patient_hash,
                _PatientCaregiverLink.caregiver_hash == caregiver_hash,
            )
            .first()
        )

    def _to_response_dict(self, link: _PatientCaregiverLink) -> dict[str, object]:
        return {
            "id": link.id,
            "link_id": link.id,
            "patient_hash": link.patient_hash,
            "caregiver_hash": link.caregiver_hash,
            "guardian_hash": link.caregiver_hash,
            "linked": link.linked,
            "link_status": link.linked,
            "created_at": link.created_at.isoformat() if link.created_at else "",
            "linked_at": link.created_at.isoformat() if link.created_at else "",
        }
