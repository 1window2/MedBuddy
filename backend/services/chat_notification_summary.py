"""채팅 미확인 개수와 개인정보 표시 규칙을 푸시·로컬 알림에 동일하게 적용한다."""

import hashlib

from entities.chat_message_entity import CHAT_MESSAGE_KIND_MEDICATION_HISTORY_SHARE
from entities.medication_schedule_entity import (
    MEDICATION_SLOT_ENGLISH_NAMES, MEDICATION_SLOT_KOREAN_NAMES,
)
from repositories.chat_message_repository import ChatMessageRepository


def message_preview(body: str, maximum: int = 120) -> str:
    text = " ".join(str(body or "").split())
    return text if len(text) <= maximum else f"{text[:maximum - 1].rstrip()}…"


def dose_receipt_preview(receipt: dict, is_english: bool) -> str:
    slot = str(receipt.get("slot_key") or "")
    date = str(receipt.get("schedule_date") or "").strip()
    if is_english:
        name = MEDICATION_SLOT_ENGLISH_NAMES.get(slot, "")
        label = f"{name} doses" if name else "doses"
        return f"Recorded {label}{f' for {date}' if date else ''}."
    name = MEDICATION_SLOT_KOREAN_NAMES.get(slot, "")
    subject = " ".join(part for part in (date, name) if part)
    return f"{subject} 복용을 기록했습니다.".strip()


def chat_fallback_text(english: bool) -> str:
    return ("You received a new message from a linked family member."
            if english else "연동된 가족에게 새 메시지가 도착했습니다.")


def notification_preview(*, message_kind: str, context_payload: object, body: str,
                         english: bool, maximum: int) -> str:
    """공유 기록은 일반 안내로, 복용 기록은 약 이름 없이 날짜·시간대 문구로 바꾼다."""
    if message_kind == CHAT_MESSAGE_KIND_MEDICATION_HISTORY_SHARE:
        return chat_fallback_text(english)
    context = context_payload if isinstance(context_payload, dict) else {}
    receipt = context.get("completion_confirmation")
    text = dose_receipt_preview(receipt, english) if isinstance(receipt, dict) else body
    return message_preview(text, maximum)


def build_chat_notification_summary(db, *, link, recipient_hash: str,
                                    language: str, show_details: bool,
                                    count: int | None = None) -> dict:
    """count는 호출자가 같은 요청에서 이미 센 미확인 개수이며, 없으면 여기서 센다."""
    is_patient = str(link.patient_hash) == recipient_hash
    repository = ChatMessageRepository(db)
    if count is None:
        count, _ = repository.unread_summary(
            link_id=link.id, reader_hash=recipient_hash, is_patient=is_patient,
        )
    rows = repository.recent_unread(
        link_id=link.id, reader_hash=recipient_hash, is_patient=is_patient,
    )
    english = str(language).strip().lower() == "en"
    fallback = chat_fallback_text(english)
    alias = link.caregiver_alias if is_patient else link.patient_alias
    role = (("Caregiver" if is_patient else "Patient") if english
            else ("보호자" if is_patient else "환자"))
    peer = str(link.caregiver_hash if is_patient else link.patient_hash).strip()
    sender = str(alias or f"{role} {peer[-4:].upper()}")
    lines = []
    if show_details:
        for row in rows:
            # 전송 크기를 제한하고 긴 건강정보를 잠금 화면에 모두 노출하지 않는다.
            lines.append(notification_preview(
                message_kind=row.message_kind, context_payload=row.context_payload,
                body=str(row.body), english=english, maximum=80,
            ) or fallback)
    group = hashlib.sha256(f"{recipient_hash}|{link.id}".encode()).hexdigest()[:32]
    return {
        "count": count,
        "latest_message_id": int(rows[-1].id) if rows else 0,
        "sender_name": sender if show_details else "",
        "lines": lines,
        "show_details": show_details,
        "group_tag": f"medbuddy-chat-{group}",
    }
