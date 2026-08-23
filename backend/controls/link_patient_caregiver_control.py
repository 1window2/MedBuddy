# 파일명: link_patient_caregiver_control.py
# 역할: 통합 클래스 다이어그램의 LinkPatientCaregiver 사용 사례를 수행한다.

import logging
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from entities.caregiver_notification_entity import _CaregiverNotification
from entities.chat_message_entity import _ChatMessage
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
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)

_PATIENT_CODE_TTL_MINUTES = 15
_MAX_CODE_GENERATION_ATTEMPTS = 10
logger = logging.getLogger(__name__)


def _utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: LinkPatientCaregiver
# 역할: 환자·보호자 연동 생성과 해제를 조율한다.
# 주요 책임:
#   - 임시 환자 연동 코드를 생성한다.
#   - 유효한 코드로 보호자를 환자에게 등록한다.
#   - 기존 연동을 조회하거나 해제한다.
# 속성:
#   - db: 연동 영속성 작업에 사용하는 SQLAlchemy 세션
class LinkPatientCaregiver:
    def __init__(
        self,
        db: Session,
        link_repository: PatientCaregiverLinkRepository | None = None,
    ) -> None:
        self.db = db
        self.link_repository = (
            link_repository or PatientCaregiverLinkRepository(db)
        )

    # 함수이름: requestLinkScreen
    # 함수역할: 현재 환자 또는 보호자가 참여한 활성 연동을 조회한다.
    # 매개변수: user_hash - 환자 또는 보호자 소유권 식별값
    # 반환값: API 응답 형식의 연동 목록
    def requestLinkScreen(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        links = self.link_repository.list_active_for_user(normalized_user_hash)
        return {
            "success": True,
            "message": "Patient-caregiver link lookup succeeded.",
            "data": [self._to_response_dict(link) for link in links],
        }

    # 함수이름: generatePatientHash
    # 함수역할: 보호자 등록에 사용할 임시 환자 연동 코드를 생성한다.
    # 매개변수: patient_hash - 코드에 연결할 환자 소유권 식별값
    # 반환값: API 응답 형식의 코드 정보
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

    # 함수이름: requestPatientCaregiverLink
    # 함수역할: 환자 코드를 검증하고 보호자 연동을 생성하거나 복구한다.
    # 매개변수:
    # - caregiver_hash: 보호자 소유권 식별값
    # - patient_code: 임시 환자 코드
    # 반환값: API 응답 형식의 연동 정보
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

    # 함수이름: requestUnlink
    # 함수역할: 요청자가 참여한 연동을 논리 삭제한다.
    # 매개변수:
    # - link_id: 연동 행 식별자
    # - user_hash: 해제 권한을 가진 환자 또는 보호자 식별값
    # 반환값: API 응답 형식의 해제 결과
    def requestUnlink(
        self,
        link_id: int,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        link = self.link_repository.find_active_for_user_by_id(
            link_id,
            normalized_user_hash,
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
            self._remove_chat_history(link.id)
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

    def _remove_chat_history(self, link_id: int) -> None:
        """연동 해제와 함께 더 이상 접근할 수 없는 대화 기록을 삭제한다."""
        self.db.query(_ChatMessage).filter(
            _ChatMessage.link_id == link_id,
        ).delete(synchronize_session=False)

    # 함수이름: getLinkedPatientHash
    # 함수역할: 보호자가 선택한 연동 환자의 식별값을 확인한다.
    # 매개변수: caregiver_hash - 보호자 소유권 식별값
    # 반환값: 연동된 환자 식별값
    def getLinkedPatientHash(
        self,
        caregiver_hash: str,
        patient_hash: str | None = None,
    ) -> str:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        requested_patient_hash = (patient_hash or "").strip()
        normalized_patient_hash = (
            normalize_patient_hash(requested_patient_hash)
            if requested_patient_hash
            else None
        )
        link = self.link_repository.find_active_for_caregiver(
            normalized_caregiver_hash,
            normalized_patient_hash,
        )
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
        return self.link_repository.find_pair(patient_hash, caregiver_hash)

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
