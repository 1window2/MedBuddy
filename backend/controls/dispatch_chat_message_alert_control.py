# 파일명: dispatch_chat_message_alert_control.py
# 역할: 채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다.

"""채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다."""

import json

from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import (
    PushDeliveryResult,
    PushNotificationBoundary,
)
from entities.chat_message_entity import _ChatMessage
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
        context_payload: object = None
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
            # 접힌 알림은 첫 줄만 보이므로 앱 전경 알림처럼 최신 메시지를 맨 위에 둔다.
            # chat_summary의 lines는 앱의 InboxStyle이 읽는 오래된 순서 그대로 보낸다.
            notification_body = "\n".join(reversed(summary["lines"])) or fallback_body
            grouped_data = {"chat_summary": json.dumps(summary, ensure_ascii=False),
                            "chat_group": summary["group_tag"],
                            "chat_count": str(summary["count"])}
        # Firebase 호출이 느려도 풀 연결과 읽기 트랜잭션을 잡고 있지 않도록 먼저 반환한다.
        self.db.rollback()
        result = self.push_boundary.send_notification(
            tokens=list(recipient.tokens),
            title=title,
            body=notification_body,
            data={
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
            },
        )
        if result.invalid_tokens:
            resolver.disable_invalid(result.invalid_tokens)
        return result
