# File Name: process_chat_notifications_control.py
# Role: Claim durable chat jobs and retry delivery without holding DB sessions across awaits.

from collections.abc import Awaitable, Callable
from datetime import datetime, timedelta
from typing import NamedTuple

from sqlalchemy import update
from sqlalchemy.orm import Session, sessionmaker
from starlette.concurrency import run_in_threadpool

from boundaries.push_notification_boundary import PushNotificationBoundary
from controls.dispatch_chat_message_alert_control import DispatchChatMessageAlert
from core.config import settings
from core.request_rate_limits import RateLimitRule, RequestRateLimitStore
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob as Job, utc_now


# Class Name: Claim
# Role: Detached lease metadata; contains no message text or device credentials.
# Attributes: message_id/recipient/link_id - routing; attempt - fencing token; created_at - expiry.
class Claim(NamedTuple):
    message_id: int
    recipient: str
    link_id: int
    attempt: int
    created_at: datetime


# Function Name: reserve_chat_push
# Description: Preserve per-recipient/link cooldown; unavailable quota storage raises for retry.
# Parameters: store - shared limiter; recipient_hash/link_id - scoped delivery target.
# Returns: Whether this delivery may proceed now.
async def reserve_chat_push(store: RequestRateLimitStore, *, recipient_hash: str, link_id: int) -> bool:
    if not settings.RATE_LIMIT_ENABLED:
        return True
    allowed, _ = await store.consume(
        identity=f"chat-push:{recipient_hash}:{link_id}",
        request_scope="POST:/api/v1/chat/push",
        rule=RateLimitRule(1, settings.CHAT_PUSH_MIN_INTERVAL_SECONDS),
    )
    return allowed


# Class Name: ProcessChatNotifications
# Role: Coordinate atomic claims, live delivery policy and bounded retry state.
# Responsibilities: Recover five-minute abandoned leases; fence late results; expire after 24h/eight attempts.
# Attributes: sessions - isolated sessions; push - boundary factory; connected/reserve - async policies.
class ProcessChatNotifications:
    # Function Name: __init__
    # Description: Inject persistence, delivery and event-loop-owned policies.
    # Parameters: sessions/push - factories; connected/reserve - recipient/link policy callbacks.
    # Returns: Initialized processor; no work starts here.
    def __init__(self, sessions: sessionmaker[Session], push: Callable[[], PushNotificationBoundary],
                 connected: Callable[..., Awaitable[bool]], reserve: Callable[..., Awaitable[bool]]) -> None:
        self.sessions, self.push = sessions, push
        self.connected, self.reserve = connected, reserve

    # Function Name: claim
    # Description: Atomically acquire one due job; increasing attempts fences stale completion writes.
    # Parameters: None. Returns: Detached claim or None when no job was acquired.
    def claim(self) -> Claim | None:
        now = utc_now()
        with self.sessions() as db:
            candidate = db.query(Job, _ChatMessage.link_id).join(
                _ChatMessage, _ChatMessage.id == Job.message_id,
            ).filter(Job.status.in_(("pending", "processing")), Job.available_at <= now).order_by(
                Job.available_at, Job.message_id,
            ).first()
            if candidate is None:
                return None
            row, link_id = candidate
            claim = Claim(row.message_id, row.recipient_hash, link_id, row.attempts + 1, row.created_at)
            acquired = db.execute(update(Job).where(
                Job.message_id == row.message_id, Job.attempts == row.attempts,
                Job.status.in_(("pending", "processing")), Job.available_at <= now,
            ).values(status="processing", attempts=claim.attempt,
                     available_at=now + timedelta(minutes=5))).rowcount
            db.commit()
            return claim if acquired == 1 else None

    # Function Name: finish
    # Description: Record terminal state or backoff only while this attempt still owns the lease.
    # Parameters: claim - lease; status - pending/completed/suppressed/dead; error - safe diagnostic.
    # Returns: None; a stale worker cannot overwrite a newer attempt's state.
    def finish(self, claim: Claim, status: str, error: str | None = None) -> None:
        if status == "pending" and claim.attempt >= 8:
            status = "dead"
        delay = max(settings.CHAT_PUSH_MIN_INTERVAL_SECONDS + 1, min(30 * 2 ** min(claim.attempt, 5), 900))
        with self.sessions() as db:
            db.execute(update(Job).where(
                Job.message_id == claim.message_id, Job.status == "processing", Job.attempts == claim.attempt,
            ).values(status=status, available_at=utc_now() + timedelta(seconds=delay), last_error=error))
            db.commit()

    # Function Name: deliver
    # Description: Re-read current history and consent through the existing dispatcher before FCM.
    # Parameters: claim - acquired delivery lease.
    # Returns: None; transient/partial failures raise for persisted retry.
    def deliver(self, claim: Claim) -> None:
        with self.sessions() as db:
            job = db.get(Job, claim.message_id)
            if job is None or job.status != "processing" or job.attempts != claim.attempt:
                return
            row = db.get(_ChatMessage, claim.message_id)
            if row is None:
                return
            context = row.context_payload or {}
            schedule = context.get("schedule_context") or {}
            result = DispatchChatMessageAlert(db, self.push()).notify_new_message(
                recipient_hash=claim.recipient, link_id=claim.link_id,
                message_body="", message_id=claim.message_id,
                slot_key=str(schedule.get("slot_key") or ""),
            )
            if not result.all_valid_targets_succeeded:
                raise RuntimeError("retryable_push_failure")

    # Function Name: run_once
    # Description: Process a bounded batch without blocking the event loop or retaining DB sessions.
    # Parameters: limit - maximum jobs per polling cycle.
    # Returns: Number of jobs handled, including deliberately suppressed and failed jobs.
    async def run_once(self, limit: int = 50) -> int:
        count = 0
        for _ in range(max(1, min(limit, 200))):
            claim = await run_in_threadpool(self.claim)
            if claim is None:
                break
            count += 1
            try:
                if claim.attempt > 8 or claim.created_at <= utc_now() - timedelta(hours=24):
                    status = "dead"
                elif await self.connected(link_id=claim.link_id, user_hash=claim.recipient):
                    status = "suppressed"
                elif not await self.reserve(link_id=claim.link_id, recipient_hash=claim.recipient):
                    status = "suppressed"
                else:
                    await run_in_threadpool(self.deliver, claim)
                    status = "completed"
                await run_in_threadpool(self.finish, claim, status)
            except Exception as exc:
                await run_in_threadpool(self.finish, claim, "pending", type(exc).__name__)
        return count
