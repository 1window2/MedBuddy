# 파일명: link_patient_caregiver_control.py
# 역할: Control mapped from the LinkPatientCaregiver box in ClassDiagram2.

from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from entities.patient_caregiver_link_entity import (
    PatientCaregiverLink,
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


# 클래스명: LinkPatientCaregiver
# 역할: patient-caregiver linking and unlinking 흐름을 조정한다.
# 주요 책임:
#   - Create temporary patient link codes.
#   - Register a caregiver with a valid patient code.
#   - List or unlink existing patient-caregiver links.
# 속성:
#   - db: 연동 정보 저장 작업에 사용하는 SQLAlchemy 세션
class LinkPatientCaregiver:
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: requestPatientCaregiverLink
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 연동 페이지 조회 wrapper이다.
    # 매개변수:
    # - user_hash: 환자 또는 보호자 권한을 구분하는 해시
    # 반환값:
    # - API-compatible link list response dictionary.
    def requestPatientCaregiverLink(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_link_page(user_hash)

    # 함수명: requestLinkPage
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 연동 row 조회 wrapper이다.
    # 매개변수:
    # - user_hash: 환자 또는 보호자 권한을 구분하는 해시
    # 반환값:
    # - API-compatible link list response dictionary.
    def requestLinkPage(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_link_page(user_hash)

    # 함수명: request_link_page
    # 함수역할:
    # - Lists active links that include the current patient or caregiver.
    # 매개변수:
    # - user_hash: 환자 또는 보호자 권한을 구분하는 해시
    # 반환값:
    # - API-compatible link list response dictionary.
    def request_link_page(
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

    # 함수명: request_patient_code
    # 함수역할:
    # - 보호자 등록에 사용할 임시 환자 연동 코드를 생성한다.
    # 매개변수:
    # - patient_hash: 생성된 코드에 담길 환자 해시
    # 반환값:
    # - API-compatible code response dictionary.
    def request_patient_code(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        expires_at = datetime.utcnow() + timedelta(minutes=_PATIENT_CODE_TTL_MINUTES)

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
            raise HTTPException(
                status_code=500,
                detail=f"Patient link code creation failed: {exc}",
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

    # 함수명: registerPatientCode
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 보호자 등록 wrapper이다.
    # 매개변수:
    # - caregiver_hash: 보호자 권한을 구분하는 해시
    # - patient_code: Temporary patient code.
    # 반환값:
    # - API-compatible link response dictionary.
    def registerPatientCode(
        self,
        caregiver_hash: str,
        patient_code: str,
    ) -> dict[str, object]:
        return self.register_patient_code(caregiver_hash, patient_code)

    # 함수명: register_patient_code
    # 함수역할:
    # - Validates a patient code and creates or restores the caregiver link.
    # 매개변수:
    # - caregiver_hash: 보호자 권한을 구분하는 해시
    # - patient_code: Temporary patient code.
    # 반환값:
    # - API-compatible link response dictionary.
    def register_patient_code(
        self,
        caregiver_hash: str,
        patient_code: str,
    ) -> dict[str, object]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        link_code = self._get_valid_link_code(patient_code)

        if link_code.patient_hash == normalized_caregiver_hash:
            raise HTTPException(
                status_code=400,
                detail="A caregiver cannot link to the same patient hash.",
            )

        try:
            link = self._get_existing_pair(
                link_code.patient_hash,
                normalized_caregiver_hash,
            )
            if link is None:
                link_state = PatientCaregiverLink(
                    patient_id=link_code.patient_hash,
                    caregiver_id=normalized_caregiver_hash,
                ).createPatientCaregiverLink()
                link = _PatientCaregiverLink(
                    patient_hash=link_state.patient_id,
                    caregiver_hash=link_state.caregiver_id,
                    linked=link_state.linked,
                )
                self.db.add(link)
                self.db.flush()
            else:
                link_state = PatientCaregiverLink(
                    link_id=link.id,
                    patient_id=link.patient_hash,
                    caregiver_id=link.caregiver_hash,
                    linked=link.linked,
                ).createPatientCaregiverLink()
                link.linked = link_state.linked

            link_code.used = True
            link_code.caregiver_hash = normalized_caregiver_hash
            self.db.commit()
            self.db.refresh(link)
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Patient-caregiver link registration failed: {exc}",
            ) from exc

        return {
            "success": True,
            "message": "Patient-caregiver link was created.",
            "data": self._to_response_dict(link),
        }

    # 함수명: requestUnlink
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 연동 해제 wrapper이다.
    # 매개변수:
    # - link_id: Link row identifier.
    # - user_hash: 연동 해제를 요청할 수 있는 환자 또는 보호자 해시
    # 반환값:
    # - API-compatible unlink response dictionary.
    def requestUnlink(
        self,
        link_id: int,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_unlink(link_id, user_hash)

    # 함수명: request_unlink
    # 함수역할:
    # - Soft-deletes a link when the requester participates in that link.
    # 매개변수:
    # - link_id: Link row identifier.
    # - user_hash: 연동 해제를 요청할 수 있는 환자 또는 보호자 해시
    # 반환값:
    # - API-compatible unlink response dictionary.
    def request_unlink(
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
                patient_id=link.patient_hash,
                caregiver_id=link.caregiver_hash,
                linked=link.linked,
            ).deletePatientCaregiverLink()
            link.linked = link_state.linked
            self.db.commit()
            self.db.refresh(link)
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Patient-caregiver unlink failed: {exc}",
            ) from exc

        return {
            "success": True,
            "message": "Patient-caregiver link was removed.",
            "data": self._to_response_dict(link),
        }

    # 함수명: getLinkedPatientHash
    # 함수역할:
    # - Reads the first linked patient hash for a caregiver.
    # 매개변수:
    # - caregiver_hash: 보호자 권한을 구분하는 해시
    # 반환값:
    # - Linked patient hash.
    def getLinkedPatientHash(self, caregiver_hash: str) -> str:
        return self.get_linked_patient_hash(caregiver_hash)

    # 함수명: get_linked_patient_hash
    # 함수역할:
    # - Reads the first linked patient hash for a caregiver.
    # 매개변수:
    # - caregiver_hash: 보호자 권한을 구분하는 해시
    # 반환값:
    # - Linked patient hash.
    def get_linked_patient_hash(self, caregiver_hash: str) -> str:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        link = (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.caregiver_hash == normalized_caregiver_hash,
                _PatientCaregiverLink.linked.is_(True),
            )
            .order_by(_PatientCaregiverLink.id.asc())
            .first()
        )
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Linked patient was not found.",
            )
        return str(link.patient_hash)

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
        normalized_patient_code = (patient_code or "").strip().upper()
        if not normalized_patient_code:
            raise HTTPException(status_code=400, detail="Patient code is required.")

        link_code = (
            self.db.query(_PatientLinkCode)
            .filter(
                _PatientLinkCode.patient_code == normalized_patient_code,
                _PatientLinkCode.used.is_(False),
            )
            .first()
        )
        if link_code is None or link_code.expires_at < datetime.utcnow():
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
            "patient_hash": link.patient_hash,
            "caregiver_hash": link.caregiver_hash,
            "linked": link.linked,
            "created_at": link.created_at.isoformat() if link.created_at else "",
        }
