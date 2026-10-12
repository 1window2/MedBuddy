# 파일명: dispatch_chat_message_alert_control.py
# 역할: 채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다.

"""채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다."""

from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import (
    PushDeliveryResult,
    PushNotificationBoundary,
)
from entities.chat_message_entity import _ChatMessage
from entities.medication_schedule_entity import (
    MEDICATION_SLOT_ENGLISH_NAMES,
    MEDICATION_SLOT_KOREAN_NAMES,
)
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)
from services.push_recipient_resolver import PushRecipientResolver


# 클래스명: DispatchChatMessageAlert
# 역할:
# - 채팅 알림의 토큰 조회, 전송과 만료 토큰 정리를 조율한다.
# 주요 책임:
# - 제한된 길이의 메시지 미리보기를 보내고 유효하지 않은 토큰을 비활성화한다.
# - 서버가 만든 복용 기록 메시지는 약 이름을 뺀 문구로 바꿔 미리보기에 싣는다.
# - 전송에 필요한 값을 모두 읽은 뒤 DB 연결을 반환하고 나서 Firebase를 호출한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
# - link_repository (PatientCaregiverLinkRepository): 활성 환자·보호자 연동 저장소.
class DispatchChatMessageAlert:
    """채팅 알림의 토큰 조회, 전송, 만료 토큰 정리를 담당한다."""

    _MAXIMUM_PREVIEW_LENGTH = 120

    # 함수이름: __init__
    # 함수역할:
    # - 채팅 수신자 설정 조회 세션과 기기 푸시 전송 경계를 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
    # 반환값:
    # - 없음.
    def __init__(self, db: Session, push_boundary: PushNotificationBoundary) -> None:
        self.db = db
        self.push_boundary = push_boundary
        self.link_repository = PatientCaregiverLinkRepository(db)

    # 함수이름: notify_new_message
    # 함수역할:
    # - 채팅방에 접속하지 않은 상대 기기에 새 메시지 도착을 알린다.
    # - 수신자와 문구를 모두 읽은 뒤 세션의 읽기 트랜잭션을 끝내고 전송한다. 호출자는 자신의 변경을 먼저 커밋해야 한다.
    # 매개변수:
    # - recipient_hash (str): 알림을 받을 계정 식별자.
    # - link_id (int): 저장된 환자·보호자 연동 식별자.
    # - message_body (str): 메시지 또는 푸시 미리보기에 사용할 사용자 입력 본문.
    # - message_kind (str): 텍스트 또는 구조화 문맥 메시지 유형.
    # - slot_key (str | None): morning, lunch, evening, bedtime 중 복용 시간대 키.
    # - message_id (int | None): 저장된 채팅 메시지 식별자.
    # 반환값:
    # - 푸시 전송 결과
    def notify_new_message(
        self,
        *,
        recipient_hash: str,
        link_id: int,
        message_body: str,
        message_kind: str = "text",
        slot_key: str | None = None,
        message_id: int | None = None,
    ) -> PushDeliveryResult:
        """상대 기기에 길이를 제한한 실제 채팅 내용을 미리 보여준다."""
        dose_receipt: dict[str, object] | None = None
        # Recheck queued work before exposing a preview; completed delivery cannot be recalled.
        if message_id is not None:
            row = self.db.get(_ChatMessage, message_id)
            link = self.link_repository.find_active_for_user_by_id(
                link_id, recipient_hash,
            )
            if row is None or link is None or row.link_id != link_id:
                return PushDeliveryResult(success_count=0)
            hidden_at = (row.patient_deleted_at if recipient_hash == str(link.patient_hash)
                         else row.caregiver_deleted_at)
            if hidden_at is not None or row.deleted_for_everyone_at is not None or row.read_at is not None:
                return PushDeliveryResult(success_count=0)
            message_body = str(row.body)
            message_kind = str(row.message_kind)
            dose_receipt = self._dose_receipt(row)
        resolver = PushRecipientResolver(self.db)
        recipient = resolver.resolve(recipient_hash)
        if not recipient.tokens:
            return PushDeliveryResult(success_count=0)
        if not recipient.chat_enabled:
            return PushDeliveryResult(success_count=0)
        language = recipient.language
        is_english = language == "en"
        # 복용 기록 본문에는 약 이름이 들어 있으므로 잠금 화면에 그대로 내보내지 않는다.
        message_preview = (
            self._dose_receipt_preview(dose_receipt, is_english)
            if dose_receipt is not None
            else self._message_preview(message_body)
        )
        fallback_body = (
            "You received a new message from a linked family member."
            if is_english
            else "연동된 가족에게 새 메시지가 도착했습니다."
        )
        show_details = recipient.show_details
        notification_body = (message_preview or fallback_body) if show_details else fallback_body
        # Firebase 호출이 느려도 풀 연결과 읽기 트랜잭션을 잡고 있지 않도록 먼저 반환한다.
        self.db.rollback()
        result = self.push_boundary.send_notification(
            tokens=list(recipient.tokens),
            title="New family message" if is_english else "새 가족 메시지",
            body=notification_body,
            data={
                "type": "linked_chat_message",
                "recipient_hash": recipient_hash,
                "language": language,
                **({"event_id": f"chat:{link_id}:{message_id}"}
                   if message_id is not None else {}),
                "link_id": str(link_id),
                "message_preview": message_preview if show_details else "",
                "message_kind": message_kind,
                "slot_key": slot_key or "",
            },
        )
        if result.invalid_tokens:
            resolver.disable_invalid(result.invalid_tokens)
        return result

    # 함수이름: _dose_receipt
    # 함수역할:
    # - 메시지가 서버가 작성한 복용 기록인지 확인하고 그 확인 정보를 돌려준다.
    # 매개변수:
    # - row (_ChatMessage): 저장된 채팅 메시지.
    # 반환값:
    # - 복용 기록의 날짜와 시간대를 담은 사전. 사용자가 쓴 메시지면 None.
    @staticmethod
    def _dose_receipt(row: _ChatMessage) -> dict[str, object] | None:
        """구조화 문맥에 복용 확인이 붙은 메시지만 복용 기록으로 본다."""
        context = row.context_payload if isinstance(row.context_payload, dict) else {}
        confirmation = context.get("completion_confirmation")
        return confirmation if isinstance(confirmation, dict) else None

    # 함수이름: _dose_receipt_preview
    # 함수역할:
    # - 복용 기록 메시지의 알림 문구를 약 이름 없이 날짜와 시간대만으로 만든다.
    # 매개변수:
    # - dose_receipt (dict[str, object]): 복용 기록의 날짜와 시간대.
    # - is_english (bool): 수신자의 알림 언어가 영어인지 여부.
    # 반환값:
    # - 약 이름이 없는 알림 표시용 문구.
    @staticmethod
    def _dose_receipt_preview(dose_receipt: dict[str, object], is_english: bool) -> str:
        """날짜와 시간대를 알 수 없으면 그 부분을 빼고 기록 사실만 알린다."""
        slot_key = str(dose_receipt.get("slot_key") or "")
        schedule_date = str(dose_receipt.get("schedule_date") or "").strip()
        if is_english:
            slot_name = MEDICATION_SLOT_ENGLISH_NAMES.get(slot_key, "")
            dose_label = f"{slot_name} doses" if slot_name else "doses"
            suffix = f" for {schedule_date}" if schedule_date else ""
            return f"Recorded {dose_label}{suffix}."
        slot_name = MEDICATION_SLOT_KOREAN_NAMES.get(slot_key, "")
        subject = " ".join(part for part in (schedule_date, slot_name) if part)
        return f"{subject} 복용을 기록했습니다.".strip()

    # 함수이름: _message_preview
    # 함수역할:
    # - 알림에 표시할 메시지를 한 줄로 정리하고 최대 길이를 제한한다.
    # 매개변수:
    # - message_body (str): 사용자가 전송한 원문
    # 반환값:
    # - 알림 표시용 메시지 미리보기
    @classmethod
    def _message_preview(cls, message_body: str) -> str:
        """공백을 정리한 뒤 긴 메시지 끝에 말줄임표를 붙인다."""
        normalized = " ".join(str(message_body or "").split())
        if len(normalized) <= cls._MAXIMUM_PREVIEW_LENGTH:
            return normalized
        return f"{normalized[: cls._MAXIMUM_PREVIEW_LENGTH - 1].rstrip()}…"
