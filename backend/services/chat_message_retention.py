# 파일명: chat_message_retention.py
# 역할: 보관 기간이 지난 환자·보호자 채팅을 정리한다.

from datetime import UTC, datetime, timedelta

from sqlalchemy.orm import Session

from core.config import settings
from entities.chat_message_entity import _ChatMessage


# 클래스명: ChatMessageRetentionPolicy
# 역할: 채팅 메시지의 보관 기간과 만료 삭제 조건을 한곳에서 관리한다.
class ChatMessageRetentionPolicy:
    def __init__(self, retention_days: int | None = None) -> None:
        configured_days = (
            settings.CHAT_MESSAGE_RETENTION_DAYS
            if retention_days is None
            else retention_days
        )
        if configured_days < 1:
            raise ValueError("채팅 보관 기간은 1일 이상이어야 합니다.")
        self.retention_days = configured_days

    # 함수이름: cleanup_expired_messages
    # 함수역할: 생성 시각이 보관 기한보다 오래된 채팅을 일괄 삭제한다.
    # 매개변수: db, now, commit
    # 반환값: 삭제한 채팅 메시지 수
    def cleanup_expired_messages(
        self,
        db: Session,
        *,
        now: datetime | None = None,
        commit: bool = True,
    ) -> int:
        comparison_time = _as_naive_utc(now or datetime.now(UTC))
        cutoff = comparison_time - timedelta(days=self.retention_days)
        deleted_count = (
            db.query(_ChatMessage)
            .filter(_ChatMessage.created_at < cutoff)
            .delete(synchronize_session=False)
        )
        if commit:
            db.commit()
        return int(deleted_count)


def _as_naive_utc(value: datetime) -> datetime:
    """시간대가 있는 시각을 DB 비교용 UTC 시각으로 정규화한다."""
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)
