# File Name: link_patient_caregiver_control.py
# Role: Manages expiring patient codes, caregiver registration, patient aliases and link revocation.

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
_MAX_PATIENT_ALIAS_LENGTH = 20
logger = logging.getLogger(__name__)


# Function Name: _utc_now
# Description:
# - Produces the naive UTC timestamp used by persisted link-code expiration checks.
# Parameters:
# - None.
# Returns:
# - Current UTC datetime without timezone metadata.
def _utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: LinkPatientCaregiver
# 역할:
# - 환자·보호자 연동 생성과 해제를 조율한다.
# 주요 책임:
# - 임시 환자 연동 코드를 생성한다.
# - 유효한 코드로 보호자를 환자에게 등록한다.
# - 기존 연동을 조회하거나 해제한다.
# 속성:
# - db (Session): 연동 영속성 작업에 사용하는 SQLAlchemy 세션
class LinkPatientCaregiver:
    # 함수이름: __init__
    # 함수역할:
    # - 환자·보호자 연동 저장소와 코드 발급에 사용할 DB 세션을 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - link_repository (PatientCaregiverLinkRepository | None): 활성 환자·보호자 연동 저장소.
    # 반환값:
    # - 없음.
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
    # 함수역할:
    # - 현재 환자 또는 보호자가 참여한 활성 연동을 조회한다.
    # 매개변수:
    # - user_hash (str): 환자 또는 보호자 소유권 식별값
    # 반환값:
    # - API 응답 형식의 연동 목록
    def requestLinkScreen(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        links = self.link_repository.list_active_for_user(normalized_user_hash)
        return {
            "success": True,
            "message": "Patient-caregiver link lookup succeeded.",
            "data": [self.toResponseDict(link) for link in links],
        }

    # Function Name: generatePatientHash
    # Description:
    # - Generates and commits a unique, expiring patient link code for caregiver registration.
    # Parameters:
    # - patient_hash (str): Patient ownership scope for the operation.
    # Returns:
    # - Success envelope with patient hash, temporary code and UTC expiration.
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
    # 함수역할:
    # - 환자 코드를 검증하고 보호자 연동을 생성하거나 복구한다.
    # 매개변수:
    # - caregiver_hash (str): 보호자 소유권 식별값
    # - patient_code (str): 임시 환자 코드
    # 반환값:
    # - API 응답 형식의 연동 정보
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
            "data": self.toResponseDict(link),
        }

    # 함수이름: requestUnlink
    # 함수역할:
    # - 요청자가 참여한 연동을 논리 삭제한다.
    # 매개변수:
    # - link_id (int): 연동 행 식별자
    # - user_hash (str): 해제 권한을 가진 환자 또는 보호자 식별값
    # 반환값:
    # - API 응답 형식의 해제 결과
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
            "data": self.toResponseDict(link),
        }

    # 함수이름: updatePatientAlias
    # 함수역할:
    # - 보호자가 지정한 환자 별칭을 연결 관계에 저장한다.
    # - 빈 별칭은 서버 값과 기기 캐시를 기본 표시 이름으로 되돌릴 수 있게 허용한다.
    # 매개변수:
    # - link_id (int): 저장된 환자·보호자 연동 식별자.
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_alias (str): 보호자가 지정한 환자 표시 이름; 빈 값은 별칭 해제.
    # 반환값:
    # - 정규화한 환자 별칭이 저장된 연동 정보 응답.
    def updatePatientAlias(
        self,
        link_id: int,
        caregiver_hash: str,
        patient_alias: str,
    ) -> dict[str, object]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        link = self.link_repository.find_active_for_caregiver_by_id(
            link_id,
            normalized_caregiver_hash,
        )
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Patient-caregiver link was not found.",
            )

        normalized_alias = self._normalize_patient_alias(patient_alias)
        try:
            # 빈 문자열은 사용자가 별칭을 명시적으로 지운 상태로 보존한다.
            # 기존 행의 NULL과 구분해야 다른 기기의 오래된 캐시도 정리할 수 있다.
            link.patient_alias = normalized_alias
            self.db.commit()
            self.db.refresh(link)
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Patient alias persistence failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Patient alias could not be saved.",
            ) from exc

        return {
            "success": True,
            "message": "Patient alias was saved.",
            "data": self.toResponseDict(link),
        }

    # Function Name: _revoke_caregiver_notification
    # Description:
    # - Deletes notification settings for the unlinked patient-caregiver pair within the caller's transaction.
    # Parameters:
    # - link (_PatientCaregiverLink): Persisted patient-caregiver relationship and participant hashes.
    # Returns:
    # - None.
    def _revoke_caregiver_notification(
        self,
        link: _PatientCaregiverLink,
    ) -> None:
        self.db.query(_CaregiverNotification).filter(
            _CaregiverNotification.patient_hash == link.patient_hash,
            _CaregiverNotification.caregiver_hash == link.caregiver_hash,
        ).delete(synchronize_session=False)

    # 함수이름: _remove_chat_history
    # 함수역할:
    # - 연동 해제와 함께 더 이상 접근할 수 없는 대화 기록을 삭제한다.
    # 매개변수:
    # - link_id (int): 저장된 환자·보호자 연동 식별자.
    # 반환값:
    # - 없음.
    def _remove_chat_history(self, link_id: int) -> None:
        """연동 해제와 함께 더 이상 접근할 수 없는 대화 기록을 삭제한다."""
        self.db.query(_ChatMessage).filter(
            _ChatMessage.link_id == link_id,
        ).delete(synchronize_session=False)

    # 함수이름: getLinkedPatientHash
    # 함수역할:
    # - 보호자가 선택한 연동 환자의 식별값을 확인한다.
    # 매개변수:
    # - caregiver_hash (str): 보호자 소유권 식별값
    # - patient_hash (str | None): 작업 대상 환자의 데이터 소유 범위 식별자.
    # 반환값:
    # - 연동된 환자 식별값
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

    # Function Name: _normalize_patient_code
    # Description:
    # - Trims and uppercases a submitted link code, rejecting blank input.
    # Parameters:
    # - patient_code (str): Temporary patient link code entered for caregiver registration.
    # Returns:
    # - Normalized code, or HTTP 400 when absent.
    def _normalize_patient_code(self, patient_code: str) -> str:
        normalized_patient_code = (patient_code or "").strip().upper()
        if not normalized_patient_code:
            raise HTTPException(status_code=400, detail="Patient code is required.")
        return normalized_patient_code

    # 함수이름: _normalize_patient_alias
    # 함수역할:
    # - 연속 공백을 한 칸으로 줄이고 보호자 표시 이름을 허용 길이로 제한한다.
    # 매개변수:
    # - patient_alias (str): 보호자가 지정한 환자 표시 이름; 빈 값은 별칭 해제.
    # 반환값:
    # - 정리된 별칭; 빈 문자열은 별칭 해제를 나타낸다.
    def _normalize_patient_alias(self, patient_alias: str) -> str:
        normalized_alias = " ".join((patient_alias or "").split())
        return normalized_alias[:_MAX_PATIENT_ALIAS_LENGTH]

    # Function Name: _generate_unique_patient_code
    # Description:
    # - Retries secure link-code generation until the code is absent from persisted records.
    # Parameters:
    # - patient_hash (str): Patient ownership scope for the operation.
    # Returns:
    # - Unused code, or RuntimeError after the bounded attempts are exhausted.
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

    # Function Name: _get_valid_link_code
    # Description:
    # - Validates code syntax, unused state and expiration before allowing a caregiver link.
    # Parameters:
    # - patient_code (str): Temporary patient link code entered for caregiver registration.
    # Returns:
    # - Active unused code row, or HTTP 400/404 for invalid or unavailable codes.
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

    # 함수이름: _get_existing_pair
    # 함수역할:
    # - 환자와 보호자 식별자로 기존 연동 쌍을 조회한다.
    # 매개변수:
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # 반환값:
    # - 기존 연동 행 또는 없을 때 None.
    def _get_existing_pair(
        self,
        patient_hash: str,
        caregiver_hash: str,
    ) -> _PatientCaregiverLink | None:
        return self.link_repository.find_pair(patient_hash, caregiver_hash)

    # 함수이름: toResponseDict
    # 함수역할:
    # - 연결 레코드를 모든 연동 API가 공유하는 응답 형식으로 변환한다.
    # 매개변수:
    # - link (_PatientCaregiverLink): 저장된 환자·보호자 연동과 참여자 식별자.
    # 반환값:
    # - 환자·보호자 식별자, 별칭, 연동 상태와 생성 시각을 담은 응답 사전.
    @staticmethod
    def toResponseDict(link: _PatientCaregiverLink) -> dict[str, object]:
        """연결 레코드를 모든 연동 API가 공유하는 응답 형식으로 변환한다."""
        return {
            "id": link.id,
            "link_id": link.id,
            "patient_hash": link.patient_hash,
            "caregiver_hash": link.caregiver_hash,
            "guardian_hash": link.caregiver_hash,
            "patient_alias": link.patient_alias,
            "linked": link.linked,
            "link_status": link.linked,
            "created_at": link.created_at.isoformat() if link.created_at else "",
            "linked_at": link.created_at.isoformat() if link.created_at else "",
        }

    # 함수이름: _to_response_dict
    # 함수역할:
    # - 이전 내부 호출과 테스트를 위한 호환 별칭이다.
    # 매개변수:
    # - link (_PatientCaregiverLink): 저장된 환자·보호자 연동과 참여자 식별자.
    # 반환값:
    # - 공통 직렬화 규칙을 적용한 연동 정보 사전.
    def _to_response_dict(self, link: _PatientCaregiverLink) -> dict[str, object]:
        """이전 내부 호출과 테스트를 위한 호환 별칭이다."""
        return self.toResponseDict(link)
