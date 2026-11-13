# 파일명: dispatch_chat_message_alert_control.py
# 역할: 채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다.

"""채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다."""

import json

from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import (
    PushDeliveryResult,
    PushNotificationBoundary,
)
from entities.chat_message_entity import (
    CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST,
    CHAT_MESSAGE_KIND_TEXT,
    _ChatMessage,
)
from core.application_clock import application_today
from entities.medication_schedule_entity import MEDICATION_SCHEDULE_SLOT_KEYS
from services.chat_notification_summary import (
    build_chat_notification_summary, chat_fallback_text, notification_preview,
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

    # Function Name: __init__
    # Description: Bind the shared database session and push adapter and create the active-link repository.
    # Parameters: db (Session) reads recipients and messages; push_boundary (PushNotificationBoundary) delivers notifications.
    # Returns: None.
    def __init__(self, db: Session, push_boundary: PushNotificationBoundary) -> None:
        self.db = db
        self.push_boundary = push_boundary
        self.link_repository = PatientCaregiverLinkRepository(db)

    # Function Name: notify_new_message
    # Description: Recheck queued message visibility and unread state, honor preview preferences, build grouped summaries and supported action payloads, then deliver outside the read transaction.
    # Parameters: recipient_hash and link_id identify the destination; message_body and message_kind provide fallback content; slot_key optionally identifies a dose slot; message_id triggers authoritative stored-message checks.
    # Returns: PushDeliveryResult, with zero deliveries for ineligible recipients/messages; disables invalid registrations and propagates delivery failures.
    def notify_new_message(
        self,
        *,
        recipient_hash: str,
        link_id: int,
        message_body: str,
        message_kind: str = CHAT_MESSAGE_KIND_TEXT,
        slot_key: str | None = None,
        message_id: int | None = None,
    ) -> PushDeliveryResult:
        """상대 기기에 길이를 제한한 실제 채팅 내용을 미리 보여준다."""
        context_payload: object = None
        action_data: dict[str, str] = {}
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
            context_payload = row.context_payload
            # 저장된 보호자 요청만 버튼을 제공하며 지연된 과거 날짜를 오늘로 바꾸지 않는다.
            context = context_payload if isinstance(context_payload, dict) else {}
            schedule = context.get("schedule_context")
            schedule = schedule if isinstance(schedule, dict) else {}
            if (message_kind == CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST
                    and recipient_hash == str(link.patient_hash)
                    and str(row.sender_hash) == str(link.caregiver_hash)
                    and schedule.get("slot_key") in MEDICATION_SCHEDULE_SLOT_KEYS
                    and schedule.get("schedule_date") == application_today().isoformat()):
                slot_key = schedule["slot_key"]
                action_data = {
                    "action_version": "1",
                    "patient_hash": recipient_hash,
                    "message_id": str(message_id),
                    "schedule_date": schedule["schedule_date"],
                }
        resolver = PushRecipientResolver(self.db)
        recipient = resolver.resolve(recipient_hash)
        if not recipient.tokens:
            return PushDeliveryResult(success_count=0)
        if not recipient.chat_enabled:
            return PushDeliveryResult(success_count=0)
        language = recipient.language
        is_english = language == "en"
        # 복용 기록 본문의 약 이름과 이력 공유의 기간·건수·건강 정보는 잠금 화면에 그대로 내보내지 않는다.
        preview = notification_preview(
            message_kind=message_kind, context_payload=context_payload, body=message_body,
            english=is_english, maximum=self._MAXIMUM_PREVIEW_LENGTH,
        )
        fallback_body = chat_fallback_text(is_english)
        show_details = recipient.show_details
        notification_body = (preview or fallback_body) if show_details else fallback_body
        title = "New family message" if is_english else "새 가족 메시지"
        grouped_data = {}
        if message_id is not None:
            summary = build_chat_notification_summary(
                self.db, link=link, recipient_hash=recipient_hash,
                language=language, show_details=show_details,
            )
            if summary["count"] == 0:
                return PushDeliveryResult(success_count=0)
            title = f"{summary['sender_name'] or title} ({summary['count']})"
            # 접힌 알림은 첫 줄만 보이므로, 앱 전경 알림의 접힌 본문처럼 최신 메시지가 보이게 맨 위에 둔다.
            # chat_summary의 lines는 앱의 InboxStyle이 읽는 오래된 순서 그대로 보낸다.
            notification_body = "\n".join(reversed(summary["lines"])) or fallback_body
            grouped_data = {"chat_summary": json.dumps(summary, ensure_ascii=False),
                            "chat_group": summary["group_tag"],
                            "chat_count": str(summary["count"])}
        # Firebase 호출이 느려도 풀 연결과 읽기 트랜잭션을 잡고 있지 않도록 먼저 반환한다.
        self.db.rollback()
        data = {
            "type": "linked_chat_message",
            "recipient_hash": recipient_hash,
            "language": language,
            **({"event_id": f"chat:{link_id}:{message_id}"}
               if message_id is not None else {}),
            "link_id": str(link_id),
            "message_preview": preview if show_details else "",
            "message_kind": message_kind,
            "slot_key": slot_key or "",
            **grouped_data,
        }
        # 버튼 지원 Android는 직접 알림을 그리고, 나머지는 기존 OS 알림을 유지한다.
        # 앱은 제목·본문을 언어와 message_preview로 직접 만들므로 데이터에 제목·본문을 다시 싣지 않는다.
        groups = [(list(recipient.tokens), data)]
        if action_data:
            groups = [
                ([token for token in recipient.tokens if token in recipient.slot_check_action_tokens],
                 {**data, **action_data}),
                ([token for token in recipient.tokens if token not in recipient.slot_check_action_tokens], data),
            ]
        results = [self.push_boundary.send_notification(
            tokens=tokens, title=title, body=notification_body, data=payload,
        ) for tokens, payload in groups if tokens]
        result = PushDeliveryResult(
            success_count=sum(item.success_count for item in results),
            invalid_tokens=tuple(token for item in results for token in item.invalid_tokens),
            retryable_failure_count=sum(item.retryable_failure_count for item in results),
        )
        if result.invalid_tokens:
            resolver.disable_invalid(result.invalid_tokens)
        return result
