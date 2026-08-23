# 파일명: manage_linked_chat_control.py
# 역할: 활성 환자·보호자 연동 안에서 채팅 기록을 관리한다.

"""활성 환자·보호자 연동 안에서 채팅 기록을 관리한다."""

from dataclasses import dataclass
from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from core.application_clock import application_today
from entities.chat_message_entity import ChatMessage, _ChatMessage
from entities.medication_image_url_entity import safe_medication_image_url
from entities.medication_schedule_entity import (
    decode_medication_schedule_slot_keys,
    medication_schedule_slot_keys_for_frequency,
)
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from repositories.chat_message_repository import ChatMessageRepository
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)
from repositories.saved_medication_repository import SavedMedicationRepository
from services.medication_course_policy import MedicationCoursePolicy


# 함수이름: utc_now
# 함수역할: 데이터베이스에 기록할 시간대 정보 없는 UTC 현재 시각을 만든다.
# 매개변수: 없음
# 반환값: UTC 기준 datetime
def utc_now() -> datetime:
    """DB에 기록할 시간대 정보 없는 UTC 현재 시각을 반환한다."""
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: ChatSendResult
# 역할: 저장된 메시지, 수신자와 신규 저장 여부를 함께 전달한다.
# 주요 책임: 중복 전송 결과를 API 계층에서 구분할 수 있게 한다.
@dataclass(frozen=True)
class ChatSendResult:
    """메시지 응답과 신규 저장 여부 및 수신자를 함께 전달한다."""

    message: ChatMessage
    recipient_hash: str
    created: bool


# 클래스명: ManageLinkedChat
# 역할: 활성 환자·보호자 연동 안에서 채팅 사용 사례를 수행한다.
# 주요 책임: 권한 검증, 기록 조회, 복약 맥락 검증, 저장과 읽음 처리를 조율한다.
class ManageLinkedChat:
    """채팅 접근 권한, 저장, 기록 조회, 읽음 처리를 조율한다."""

    def __init__(
        self,
        db: Session,
        *,
        link_repository: PatientCaregiverLinkRepository | None = None,
        message_repository: ChatMessageRepository | None = None,
        medication_repository: SavedMedicationRepository | None = None,
        course_policy: MedicationCoursePolicy | None = None,
    ) -> None:
        self.db = db
        self.link_repository = link_repository or PatientCaregiverLinkRepository(db)
        self.message_repository = message_repository or ChatMessageRepository(db)
        self.medication_repository = (
            medication_repository or SavedMedicationRepository(db)
        )
        self.course_policy = course_policy or MedicationCoursePolicy()

    # 함수이름: request_history
    # 함수역할: 참여자에게 연동별 채팅 기록 한 페이지를 반환한다.
    # 매개변수: link_id, user_hash, before_message_id, limit
    # 반환값: 채팅 기록과 다음 페이지 존재 여부
    def request_history(
        self,
        *,
        link_id: int,
        user_hash: str,
        before_message_id: int | None,
        limit: int,
    ) -> dict[str, object]:
        """참여자에게 연동별 채팅 기록 한 페이지를 반환한다."""
        self.require_active_link(link_id=link_id, user_hash=user_hash)
        rows, has_more = self.message_repository.list_recent(
            link_id,
            before_message_id=before_message_id,
            limit=limit,
        )
        return {
            "success": True,
            "data": [ChatMessage.from_row(row).to_response_dict() for row in rows],
            "has_more": has_more,
        }

    # 함수이름: request_medication_contexts
    # 함수역할: 연동 환자가 오늘 복용 중인 약을 채팅 선택 목록으로 반환한다.
    # 매개변수: link_id, user_hash
    # 반환값: 선택 가능한 복약 정보 목록
    def request_medication_contexts(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> dict[str, object]:
        """연동 환자가 오늘 복용 중인 약을 두 참여자에게 동일하게 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=user_hash)
        today = application_today()
        medications = [
            medication
            for medication in self.medication_repository.list_by_patient(
                str(link.patient_hash)
            )
            if self.course_policy.is_active_on(medication, today)
            and (medication.item_name or "").strip()
        ]
        return {
            "success": True,
            "data": [self._medication_context_response(item) for item in medications],
        }

    # 함수이름: request_medication_detail
    # 함수역할: 채팅 참여자에게 연동 환자가 저장한 약의 상세정보를 반환한다.
    # 매개변수: link_id, user_hash, medication_id
    # 반환값: 권한이 확인된 저장 복약 상세정보
    def request_medication_detail(
        self,
        *,
        link_id: int,
        user_hash: str,
        medication_id: int,
    ) -> dict[str, object]:
        """채팅 약 카드를 누른 참여자에게 환자 소유 상세정보를 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=user_hash)
        medication = self.medication_repository.find_owned_by_id(
            medication_id,
            str(link.patient_hash),
        )
        if medication is None:
            raise HTTPException(
                status_code=404,
                detail="Medication detail was not found for this chat.",
            )
        return {
            "success": True,
            "data": self._medication_detail_response(medication),
        }

    # 함수이름: send_message
    # 함수역할: 복약 맥락 메시지를 멱등하게 저장하고 상대 참여자를 반환한다.
    # 매개변수: link_id, sender_hash, client_message_id, body, medication_id
    # 반환값: ChatSendResult
    def send_message(
        self,
        *,
        link_id: int,
        sender_hash: str,
        client_message_id: str,
        body: str,
        medication_id: int | None = None,
    ) -> ChatSendResult:
        """메시지를 한 번만 저장하고 상대 사용자 식별자를 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=sender_hash)
        recipient_hash = self._other_participant(link, sender_hash)
        existing = self.message_repository.find_client_request(
            link_id=link_id,
            sender_hash=sender_hash,
            client_message_id=client_message_id,
        )
        if existing is not None:
            return ChatSendResult(
                message=ChatMessage.from_row(existing),
                recipient_hash=recipient_hash,
                created=False,
            )

        medication = self._resolve_active_medication(link, medication_id)
        row = _ChatMessage(
            link_id=link_id,
            sender_hash=sender_hash,
            client_message_id=client_message_id,
            body=body,
            medication_id=int(medication.id),
            medication_name=str(medication.item_name),
            medication_image_url=safe_medication_image_url(medication.image_url),
            medication_dosage=(medication.dosage_per_time or "").strip(),
        )
        try:
            self.message_repository.add(row)
            self.db.commit()
            self.db.refresh(row)
        except IntegrityError:
            self.db.rollback()
            existing = self.message_repository.find_client_request(
                link_id=link_id,
                sender_hash=sender_hash,
                client_message_id=client_message_id,
            )
            if existing is None:
                raise
            return ChatSendResult(
                message=ChatMessage.from_row(existing),
                recipient_hash=recipient_hash,
                created=False,
            )
        return ChatSendResult(
            message=ChatMessage.from_row(row),
            recipient_hash=recipient_hash,
            created=True,
        )

    # 함수이름: mark_read
    # 함수역할: 상대 메시지를 지정한 범위까지 읽음 처리한다.
    # 매개변수: link_id, reader_hash, through_message_id
    # 반환값: 변경 개수와 마지막 읽음 메시지 정보
    def mark_read(
        self,
        *,
        link_id: int,
        reader_hash: str,
        through_message_id: int | None,
    ) -> dict[str, object]:
        """상대가 보낸 메시지를 읽음 처리하고 변경 범위를 반환한다."""
        self.require_active_link(link_id=link_id, user_hash=reader_hash)
        read_at = utc_now()
        count, last_read_message_id = self.message_repository.mark_incoming_read(
            link_id=link_id,
            reader_hash=reader_hash,
            through_message_id=through_message_id,
            read_at=read_at,
        )
        self.db.commit()
        return {
            "success": True,
            "data": {
                "updated_count": count,
                "through_message_id": last_read_message_id,
                "read_at": read_at.replace(tzinfo=UTC).isoformat(),
            },
        }

    # 함수이름: request_unread_count
    # 함수역할: 현재 사용자가 읽지 않은 상대 메시지 수를 반환한다.
    # 매개변수: link_id, user_hash
    # 반환값: 읽지 않은 메시지 수
    def request_unread_count(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> dict[str, object]:
        """현재 연동에서 사용자가 읽지 않은 메시지 수를 반환한다."""
        self.require_active_link(link_id=link_id, user_hash=user_hash)
        return {
            "success": True,
            "data": {
                "unread_count": self.message_repository.unread_count(
                    link_id=link_id,
                    reader_hash=user_hash,
                )
            },
        }

    # 함수이름: require_active_link
    # 함수역할: 사용자가 참여한 활성 연동을 반환하거나 접근을 거부한다.
    # 매개변수: link_id, user_hash
    # 반환값: 활성 환자·보호자 연동
    def require_active_link(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> _PatientCaregiverLink:
        """현재 사용자가 참여한 활성 연동을 반환하거나 접근을 거부한다."""
        link = self.link_repository.find_active_for_user_by_id(link_id, user_hash)
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Active patient-caregiver chat was not found.",
            )
        return link

    def _resolve_active_medication(
        self,
        link: _PatientCaregiverLink,
        medication_id: int | None,
    ) -> _SavedMedication:
        """선택한 약이 연동 환자의 현재 복용 약인지 검증한다."""
        if medication_id is None:
            raise HTTPException(
                status_code=400,
                detail="Select an active medication before sending a message.",
            )
        medication = self.medication_repository.find_owned_by_id(
            medication_id,
            str(link.patient_hash),
        )
        if medication is None or not self.course_policy.is_active_on(
            medication,
            application_today(),
        ):
            raise HTTPException(
                status_code=400,
                detail="Selected medication is not active for this patient.",
            )
        if not (medication.item_name or "").strip():
            raise HTTPException(
                status_code=400,
                detail="Selected medication does not have a display name.",
            )
        return medication

    def _medication_context_response(
        self,
        medication: _SavedMedication,
    ) -> dict[str, object]:
        """복약 목록 행을 오늘 일정형 채팅 선택기에 필요한 정보로 변환한다."""
        schedule_slot_keys = decode_medication_schedule_slot_keys(
            medication.schedule_slot_keys
        )
        if not schedule_slot_keys:
            frequency_count = self.course_policy.read_frequency_count(
                medication.daily_frequency
            )
            schedule_slot_keys = medication_schedule_slot_keys_for_frequency(
                frequency_count
            )
        return {
            "medication_id": int(medication.id),
            "medication_name": str(medication.item_name).strip(),
            "image_url": safe_medication_image_url(medication.image_url),
            "dosage_per_time": (medication.dosage_per_time or "").strip(),
            "schedule_slot_keys": schedule_slot_keys,
        }

    # 함수이름: _medication_detail_response
    # 함수역할: 저장 복약정보를 공통 약 상세 화면용 응답으로 변환한다.
    # 매개변수: medication - 권한이 확인된 환자 소유 약 정보
    # 반환값: 이미지 URL이 안전하게 보정된 상세정보 응답
    @staticmethod
    def _medication_detail_response(
        medication: _SavedMedication,
    ) -> dict[str, object]:
        """저장 복약정보를 공통 약 상세 화면이 읽을 수 있는 응답으로 변환한다."""
        return {
            "id": int(medication.id),
            "patient_hash": str(medication.patient_hash or ""),
            "created_date": (
                medication.created_date.isoformat()
                if medication.created_date
                else ""
            ),
            "prescription_date": (
                medication.prescription_date.isoformat()
                if medication.prescription_date
                else ""
            ),
            "item_seq": medication.item_seq or "",
            "item_name": medication.item_name or "",
            "efficacy": medication.efficacy or "",
            "use_method": medication.use_method or "",
            "warning_message": medication.warning_message or "",
            "dosage_per_time": medication.dosage_per_time or "",
            "daily_frequency": medication.daily_frequency or "",
            "total_days": medication.total_days or "",
            "image_url": safe_medication_image_url(medication.image_url),
            "ai_guide": medication.ai_guide or "",
        }

    @staticmethod
    def _other_participant(link: _PatientCaregiverLink, user_hash: str) -> str:
        """연동에서 현재 사용자 반대편 참여자의 hash를 반환한다."""
        if str(link.patient_hash) == user_hash:
            return str(link.caregiver_hash)
        return str(link.patient_hash)
