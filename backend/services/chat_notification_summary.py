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


def build_chat_notification_summary(db, *, link, recipient_hash: str,
                                    language: str, show_details: bool) -> dict:
    is_patient = str(link.patient_hash) == recipient_hash
    repository = ChatMessageRepository(db)
    count, _ = repository.unread_summary(
        link_id=link.id, reader_hash=recipient_hash, is_patient=is_patient,
    )
    rows = repository.recent_unread(
        link_id=link.id, reader_hash=recipient_hash, is_patient=is_patient,
    )
    english = str(language).strip().lower() == "en"
    fallback = ("You received a new message from a linked family member."
                if english else "연동된 가족에게 새 메시지가 도착했습니다.")
    alias = link.caregiver_alias if is_patient else link.patient_alias
    role = (("Caregiver" if is_patient else "Patient") if english
            else ("보호자" if is_patient else "환자"))
    peer = str(link.caregiver_hash if is_patient else link.patient_hash).strip()
    sender = str(alias or f"{role} {peer[-4:].upper()}")
    lines = []
    if show_details:
        for row in rows:
            context = row.context_payload if isinstance(row.context_payload, dict) else {}
            receipt = context.get("completion_confirmation")
            if row.message_kind == CHAT_MESSAGE_KIND_MEDICATION_HISTORY_SHARE:
                text = fallback
            elif isinstance(receipt, dict):
                text = dose_receipt_preview(receipt, english)
            else:
                text = str(row.body)
            # 전송 크기를 제한하고 긴 건강정보를 잠금 화면에 모두 노출하지 않는다.
            lines.append(message_preview(text, maximum=80) or fallback)
    group = hashlib.sha256(f"{recipient_hash}|{link.id}".encode()).hexdigest()[:32]
    return {
        "count": count,
        "latest_message_id": int(rows[-1].id) if rows else 0,
        "sender_name": sender if show_details else "",
        "lines": lines,
        "show_details": show_details,
        "group_tag": f"medbuddy-chat-{group}",
    }
