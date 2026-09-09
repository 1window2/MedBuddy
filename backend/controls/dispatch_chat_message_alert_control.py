# 파일명: dispatch_chat_message_alert_control.py
# 역할: 채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다.

"""채팅방에 접속하지 않은 상대에게 새 메시지 푸시를 전달한다."""

from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import (
    PushDeliveryResult,
    PushNotificationBoundary,
)
from entities.device_push_token_entity import _DevicePushToken
from entities.chat_message_entity import _ChatMessage
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_setting_entity import _UserSetting


# 클래스명: DispatchChatMessageAlert
# 역할:
# - 채팅 알림의 토큰 조회, 전송과 만료 토큰 정리를 조율한다.
# 주요 책임:
# - 제한된 길이의 메시지 미리보기를 보내고 유효하지 않은 토큰을 비활성화한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
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

    # 함수이름: notify_new_message
    # 함수역할:
    # - 채팅방에 접속하지 않은 상대 기기에 새 메시지 도착을 알린다.
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
        # Recheck queued work before exposing a preview; completed delivery cannot be recalled.
        if message_id is not None:
            row = self.db.get(_ChatMessage, message_id)
            link = self.db.get(_PatientCaregiverLink, link_id)
            if row is None or link is None or not link.linked or row.link_id != link_id:
                return PushDeliveryResult(success_count=0)
            if recipient_hash not in (str(link.patient_hash), str(link.caregiver_hash)):
                return PushDeliveryResult(success_count=0)
            hidden_at = (row.patient_deleted_at if recipient_hash == str(link.patient_hash)
                         else row.caregiver_deleted_at)
            if hidden_at is not None or row.deleted_for_everyone_at is not None:
                return PushDeliveryResult(success_count=0)
            message_body = str(row.body)
            message_kind = str(row.message_kind)
        token_rows = (
            self.db.query(_DevicePushToken)
            .filter(
                _DevicePushToken.user_hash == recipient_hash,
                _DevicePushToken.enabled.is_(True),
            )
            .all()
        )
        if not token_rows:
            return PushDeliveryResult(success_count=0)
        recipient_setting = self._recipient_setting(recipient_hash)
        if recipient_setting is not None and not bool(
            recipient_setting.chat_notifications_enabled
        ):
            return PushDeliveryResult(success_count=0)
        language = self._recipient_language(recipient_setting)
        is_english = language == "en"
        message_preview = self._message_preview(message_body)
        fallback_body = (
            "You received a new message from a linked family member."
            if is_english
            else "연동된 가족에게 새 메시지가 도착했습니다."
        )
        show_details = (
            recipient_setting is None
            or recipient_setting.notification_detail_mode != "type_only"
        )
        notification_body = (message_preview or fallback_body) if show_details else fallback_body
        result = self.push_boundary.send_notification(
            tokens=[str(row.token) for row in token_rows],
            title="New family message" if is_english else "새 가족 메시지",
            body=notification_body,
            data={
                "type": "linked_chat_message",
                "link_id": str(link_id),
                "message_preview": message_preview if show_details else "",
                "message_kind": message_kind,
                "slot_key": slot_key or "",
            },
        )
        if result.invalid_tokens:
            self.db.query(_DevicePushToken).filter(
                _DevicePushToken.token.in_(result.invalid_tokens)
            ).update({"enabled": False}, synchronize_session=False)
            self.db.commit()
        return result

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

    # 함수이름: _recipient_setting
    # 함수역할:
    # - 수신자의 채팅 알림과 개인정보 표시 설정을 조회한다.
    # 매개변수:
    # - recipient_hash (str): 알림을 받을 사용자 식별값
    # 반환값:
    # - 사용자 설정 DB 행 또는 설정이 없으면 None
    def _recipient_setting(self, recipient_hash: str) -> _UserSetting | None:
        """설정이 없는 기존 사용자는 이전처럼 알림을 받도록 None을 반환한다."""
        return (
            self.db.query(_UserSetting)
            .filter(_UserSetting.user_hash == recipient_hash)
            .first()
        )

    # 함수이름: _recipient_language
    # 함수역할:
    # - 저장된 언어를 읽고 지원하지 않는 값은 한국어로 보정한다.
    # 매개변수:
    # - setting (_UserSetting | None): 수신자의 사용자 설정 DB 행
    # 반환값:
    # - ko 또는 en 언어 코드
    def _recipient_language(self, setting: _UserSetting | None) -> str:
        """수신자 설정이 없거나 잘못된 경우 한국어를 기본값으로 사용한다."""
        if setting is None:
            return "ko"
        language = str(setting.language or "").strip().lower()
        return "en" if language == "en" else "ko"
