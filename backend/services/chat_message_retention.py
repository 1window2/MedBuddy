# 파일명: chat_message_retention.py
# 역할: 보관 기간이 지난 환자·보호자 채팅을 정리한다.

from datetime import UTC, datetime, timedelta

from sqlalchemy.orm import Session

from core.config import settings
from entities.chat_message_entity import _ChatMessage
from entities.user_account_entity import as_naive_utc


# 클래스명: ChatMessageRetentionPolicy
# 역할:
# - 채팅 메시지의 보관 기간과 만료 삭제 조건을 한곳에서 관리한다.
# 주요 책임:
# - 보관 일수를 검증하고 UTC 기준 만료 메시지를 일괄 삭제하되 호출자가 커밋을 선택하게 한다.
# 속성:
# - retention_days (int): 최소 1일인 채팅 보관 기간.
class ChatMessageRetentionPolicy:
    # 함수이름: __init__
    # 함수역할:
    # - 지정값 또는 환경설정에서 채팅 보관 일수를 정하고 1일 미만은 거부한다.
    # 매개변수:
    # - retention_days (int | None): 채팅 보관 일수; None이면 CHAT_MESSAGE_RETENTION_DAYS를 사용한다.
    # 반환값:
    # - 없음; 유효하지 않은 보관 일수에는 ValueError.
    def __init__(self, retention_days: int | None = None) -> None:
        configured_days = (
            settings.CHAT_MESSAGE_RETENTION_DAYS
            if retention_days is None
            else retention_days
        )
        if configured_days < 1:
            raise ValueError("채팅 보관 기간은 1일 이상이어야 합니다.")
        self.retention_days = configured_days

    # Function Name: cleanup_expired_messages
    # Description: Deletes messages strictly older than the retention cutoff after converting the comparison time to naive UTC.
    # Parameters: db (Session) owns the deletion; now (datetime | None) overrides current UTC; commit (bool) controls whether this helper commits.
    # Returns: Deleted row count (int); database errors propagate for caller rollback.
    def cleanup_expired_messages(
        self,
        db: Session,
        *,
        now: datetime | None = None,
        commit: bool = True,
    ) -> int:
        comparison_time = as_naive_utc(now or datetime.now(UTC))
        cutoff = comparison_time - timedelta(days=self.retention_days)
        deleted_count = (
            db.query(_ChatMessage)
            .filter(_ChatMessage.created_at < cutoff)
            .delete(synchronize_session=False)
        )
        if commit:
            db.commit()
        return int(deleted_count)
