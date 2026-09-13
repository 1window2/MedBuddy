# 파일명: chat_message_retention.py
# 역할: 보관 기간이 지난 환자·보호자 채팅을 정리한다.

from datetime import UTC, datetime, timedelta

from sqlalchemy.orm import Session

from core.config import settings
from entities.chat_message_entity import _ChatMessage


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

    # 함수이름: cleanup_expired_messages
    # 함수역할:
    # - 생성 시각이 보관 기한보다 오래된 채팅을 일괄 삭제한다.
    # 매개변수:
    # - db (Session): 영속 기록에 접근할 호출자의 SQLAlchemy 세션.
    # - now (datetime | None): 보존 기한 비교 기준 시각; 생략 시 현재 UTC 시각.
    # - commit (bool): 호출자 트랜잭션에 맡기지 않고 여기서 삭제를 커밋할지 여부.
    # 반환값:
    # - 삭제한 채팅 메시지 수
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


# 함수이름: _as_naive_utc
# 함수역할:
# - 시간대가 있는 시각은 UTC로 변환한 뒤 시간대 정보를 제거하여 DB 저장값과 비교 가능하게 한다.
# 매개변수:
# - value (datetime): DB 보관 기한과 비교할 기준 시각.
# 반환값:
# - 시간대 정보가 없는 datetime; 원래 naive 값은 그대로 반환한다.
def _as_naive_utc(value: datetime) -> datetime:
    """시간대가 있는 시각을 DB 비교용 UTC 시각으로 정규화한다."""
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)
