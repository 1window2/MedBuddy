# File Name: link_patient_caregiver_control.py
# Role: Manages expiring patient codes, caregiver registration, patient aliases and link revocation.

import logging
from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from core.account_database_lock import ACCOUNT_BUSY_DETAIL, lock_account_operations
from core.config import settings
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
from entities.user_account_entity import _UserAccount, utc_now
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)

_PATIENT_CODE_TTL_MINUTES = 15
_MAX_CODE_GENERATION_ATTEMPTS = 10
_MAX_PATIENT_ALIAS_LENGTH = 20
logger = logging.getLogger(__name__)


# Class Name: LinkPatientCaregiver
# Role: Coordinates expiring patient codes, active caregiver links, private aliases and revocation.
# Responsibilities: Validates codes, serializes participant mutations, enforces link limits and clears linked chat/notifications on unlink.
# Attributes: db (Session) owns transactions; link_repository (PatientCaregiverLinkRepository) resolves current links.
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

    # Function Name: requestLinkScreen
    # Description: Normalizes the caller scope and lists its active links, hiding aliases authored by the other participant.
    # Parameters: user_hash (str) is the patient or caregiver account scope.
    # Returns: Success envelope with visible link dictionaries; scope/query failures propagate.
    def requestLinkScreen(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        links = self.link_repository.list_active_for_user(normalized_user_hash)
        return {
            "success": True,
            "message": "Patient-caregiver link lookup succeeded.",
            "data": [
                self.toResponseDict(link, viewer_hash=normalized_user_hash)
                for link in links
            ],
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
        expires_at = utc_now() + timedelta(minutes=_PATIENT_CODE_TTL_MINUTES)

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
    # Description: Validates and locks the code's participants, reserves the single-use code and creates/reactivates a link within account limits.
    # Parameters: caregiver_hash (str) is the registering caregiver; patient_code (str) is the temporary patient code.
    # Returns: Committed link envelope; rejects self-linking, invalid/used codes, deleted accounts and exceeded limits. Persistence failures roll back and become HTTP 500.
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
        link_code = self._lock_link_participants(
            normalized_patient_code,
            str(link_code.patient_hash),
            normalized_caregiver_hash,
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

            link = self.link_repository.find_pair(
                link_code.patient_hash,
                normalized_caregiver_hash,
            )
            if link is None or not link.linked:
                # 복용 기록마다 연동된 보호자 모두에게 전달되므로 한 계정의 활성 연동 수를 제한한다.
                limit = settings.PATIENT_CAREGIVER_LINK_MAX_PER_ACCOUNT
                if (
                    len(self.link_repository.list_active_for_patient(
                        str(link_code.patient_hash)
                    )) >= limit
                    or len(self.link_repository.list_active_for_caregiver(
                        normalized_caregiver_hash
                    )) >= limit
                ):
                    raise HTTPException(
                        status_code=409,
                        detail="연동할 수 있는 인원을 넘었습니다. 쓰지 않는 연동을 해제한 뒤 다시 시도해주세요.",
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
            "data": self.toResponseDict(link, viewer_hash=normalized_caregiver_hash),
        }

    # 함수이름: _lock_link_participants
    # 함수역할:
    # - 환자와 보호자 계정을 같은 순서로 잠근 뒤 코드를 다시 읽는다. 한 환자의 두 코드를 두 보호자가
    #   동시에 등록해도 활성 연동 수를 차례로 세게 해 환자당 한도를 넘지 않게 한다.
    # - 잠금 전환 중 삭제된 계정의 코드를 소비하지 않도록 두 참여자의 삭제 표식을 다시 확인한다.
    # 매개변수:
    # - patient_code (str): 정규화한 환자 코드
    # - patient_hash (str): 코드 주인의 계정 식별값
    # - caregiver_hash (str): 등록하는 보호자 계정 식별값
    # 반환값:
    # - 잠금 안에서 다시 읽은 유효한 코드. 미저장 변경은 RuntimeError, 삭제 계정은 410, 코드 충돌은 409, 잠금 실패는 503이다.
    def _lock_link_participants(
        self,
        patient_code: str,
        patient_hash: str,
        caregiver_hash: str,
    ) -> _PatientLinkCode:
        if self.db.new or self.db.dirty or self.db.deleted:
            raise RuntimeError("Link registration requires a clean database session.")
        # 인증 단계의 보호자 계정 잠금을 먼저 풀어 두 계정의 잠금 순서가 요청마다 같게 한다.
        # 첫 요청이면 인증 단계가 만든 계정 행이 아직 commit 전이므로 버리지 않고 commit한다.
        self.db.commit()
        try:
            lock_account_operations(self.db, (patient_hash, caregiver_hash))
            self.db.expire_all()
            # 잠금 전환 사이에 보호자가 삭제돼도 등록 중이던 환자 코드는 남아 있을 수 있다.
            # 코드 예약 전에 두 계정의 삭제 표식을 다시 확인한다.
            deleted_account = (
                self.db.query(_UserAccount.user_hash)
                .filter(
                    _UserAccount.user_hash.in_((patient_hash, caregiver_hash)),
                    _UserAccount.deletion_requested_at.is_not(None),
                )
                .first()
            )
            if deleted_account is not None:
                raise HTTPException(
                    status_code=410,
                    detail="This MedBuddy account has been deleted.",
                )
            link_code = self._get_valid_link_code(patient_code)
        except OperationalError as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=503,
                detail=ACCOUNT_BUSY_DETAIL,
                headers={"Retry-After": "5"},
            ) from exc
        except BaseException:
            self.db.rollback()
            raise
        if str(link_code.patient_hash) != patient_hash:
            self.db.rollback()
            raise HTTPException(status_code=409, detail="Patient code was already used.")
        return link_code

    # Function Name: requestUnlink
    # Description: Locks both participants, deactivates their link and removes its notification/chat state while invalidating unused patient codes.
    # Parameters: link_id (int) is the active relationship; user_hash (str) must identify one participant.
    # Returns: Committed inactive-link envelope; missing links yield 404, lock failure 503 and mutation failure 500 after rollback.
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
        link = self._lock_unlink_participants(link, normalized_user_hash)

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
            # 해제 전에 발급한 코드로 해제된 보호자가 환자 몰래 다시 연동하지 못하게 남은 코드를 모두 막는다.
            self.db.query(_PatientLinkCode).filter(
                _PatientLinkCode.patient_hash == link.patient_hash,
                _PatientLinkCode.used.is_(False),
            ).update({"used": True}, synchronize_session=False)
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
            "data": self.toResponseDict(link, viewer_hash=normalized_user_hash),
        }

    # Function Name: _lock_unlink_participants
    # Description: Commits the clean authentication transaction, acquires both account locks in stable order and rechecks the active pair before revocation.
    # Parameters: link (_PatientCaregiverLink) supplies the expected pair; user_hash (str) must remain a participant.
    # Returns: Revalidated locked link. Dirty sessions raise RuntimeError, disappeared/changed links yield 404 and lock failures yield retryable 503.
    def _lock_unlink_participants(
        self,
        link: _PatientCaregiverLink,
        user_hash: str,
    ) -> _PatientCaregiverLink:
        if self.db.new or self.db.dirty or self.db.deleted:
            raise RuntimeError("Unlink requires a clean database session.")
        link_id = link.id
        participants = (str(link.patient_hash), str(link.caregiver_hash))
        # 인증 단계에서 만든 계정 행은 버리지 않고 commit해 요청자 계정 잠금만 푼다.
        self.db.commit()
        try:
            lock_account_operations(self.db, participants)
            self.db.expire_all()
            locked = self.link_repository.find_active_for_user_by_id(link_id, user_hash)
        except OperationalError as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=503,
                detail=ACCOUNT_BUSY_DETAIL,
                headers={"Retry-After": "5"},
            ) from exc
        except BaseException:
            self.db.rollback()
            raise
        if locked is None or (str(locked.patient_hash), str(locked.caregiver_hash)) != participants:
            self.db.rollback()
            raise HTTPException(
                status_code=404,
                detail="Patient-caregiver link was not found.",
            )
        return locked

    # Function Name: updatePatientAlias
    # Description: Lets the linked caregiver save or explicitly clear their private patient alias, preserving empty text rather than legacy NULL.
    # Parameters: link_id (int) selects the active pair; caregiver_hash (str) is the owner; patient_alias (str) is validated by the alias normalizer.
    # Returns: Updated link envelope visible to the caregiver; missing links yield 404 and persistence failures roll back to HTTP 500.
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
            "data": self.toResponseDict(link, viewer_hash=str(link.caregiver_hash)),
        }

    # Function Name: update_caregiver_alias
    # Description: Saves the patient's private caregiver alias after collapsing whitespace and truncating to 20 characters; empty text clears it.
    # Parameters: link_id (int) selects the active pair; patient_hash (str) is its patient; caregiver_alias (str) is the new label.
    # Returns: Updated patient-visible link envelope; missing/foreign links yield 404 and persistence failures yield 500 after rollback.
    def update_caregiver_alias(
        self, link_id: int, patient_hash: str, caregiver_alias: str
    ) -> dict[str, object]:
        link = self.link_repository.find_active_for_patient_by_id(
            link_id, normalize_patient_hash(patient_hash)
        )
        if link is None:
            raise HTTPException(
                status_code=404, detail="Patient-caregiver link was not found."
            )
        try:
            link.caregiver_alias = " ".join(caregiver_alias.split())[:20]
            self.db.commit()
            self.db.refresh(link)
        except Exception as exc:
            self.db.rollback()
            logger.error("Caregiver alias persistence failed: %s", type(exc).__name__)
            raise HTTPException(
                status_code=500, detail="Caregiver alias could not be saved."
            ) from exc
        return {
            "success": True,
            "message": "Caregiver alias was saved.",
            "data": self.toResponseDict(link, viewer_hash=str(link.patient_hash)),
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
        if patient_link_code.isExpired(utc_now()):
            raise HTTPException(
                status_code=404,
                detail="Patient code was not found or has expired.",
            )
        return link_code

    # Function Name: toResponseDict
    # Description: Serializes a link with compatibility field aliases and hides each participant's private label from the person it describes.
    # Parameters: link (_PatientCaregiverLink) supplies persisted state; viewer_hash (str | None) filters aliases when provided.
    # Returns: Link dict with ISO timestamps or empty timestamp strings; when viewer_hash is omitted, both aliases remain present.
    @staticmethod
    def toResponseDict(
        link: _PatientCaregiverLink,
        viewer_hash: str | None = None,
    ) -> dict[str, object]:
        """연결 레코드를 모든 연동 API가 공유하는 응답 형식으로 변환한다."""
        patient_alias = link.patient_alias
        caregiver_alias = link.caregiver_alias
        if viewer_hash is not None:
            if viewer_hash == str(link.patient_hash):
                patient_alias = None
            if viewer_hash == str(link.caregiver_hash):
                caregiver_alias = None
        return {
            "id": link.id,
            "link_id": link.id,
            "patient_hash": link.patient_hash,
            "caregiver_hash": link.caregiver_hash,
            "guardian_hash": link.caregiver_hash,
            "patient_alias": patient_alias,
            "caregiver_alias": caregiver_alias,
            "linked": link.linked,
            "link_status": link.linked,
            "created_at": link.created_at.isoformat() if link.created_at else "",
            "linked_at": link.created_at.isoformat() if link.created_at else "",
        }
