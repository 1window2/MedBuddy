# File Name: chat_notification_job_entity.py
# Role: Persist a single notification job per newly committed user chat message.

from datetime import UTC, datetime
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Index
from core.database import Base
from entities.chat_message_entity import _ChatMessage  # noqa: F401


# Function Name: utc_now
# Description: Use the naive UTC convention shared by persisted notification timestamps.
# Parameters: None. Returns: Current UTC timestamp without timezone metadata.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: ChatNotificationJob
# Role: Durable chat delivery state; references history without duplicating message content.
# Responsibilities: Deduplicate by message ID, track retry/lease state, cascade with message deletion.
# Attributes: message_id/recipient_hash - target; status/attempts/available_at - delivery lease.
class ChatNotificationJob(Base):
    __tablename__ = "chat_notification_jobs"
    __table_args__ = (Index("ix_chat_notification_jobs_due", "status", "available_at"),)
    message_id = Column(Integer, ForeignKey("chat_messages.id", ondelete="CASCADE"), primary_key=True)
    recipient_hash = Column(String, ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), nullable=False)
    status = Column(String(16), nullable=False, default="pending")
    attempts = Column(Integer, nullable=False, default=0)
    available_at = Column(DateTime, nullable=False, default=utc_now)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    last_error = Column(String(100), nullable=True)
