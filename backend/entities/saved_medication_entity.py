# 파일명: saved_medication_entity.py
# 역할: 저장 복약 스냅샷의 영속 구조와 처방·시간대 기반 중복 비교 키를 정의한다.

from datetime import date

import hashlib
import json
import secrets

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from core.application_clock import application_today
from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.user_account_entity import _UserAccount  # noqa: F401


# Class Name: _SavedMedication
# Role:
# - Internal SQLAlchemy row for saved medication detail snapshots.
# Responsibilities:
# - Map saved medication fields to the saved_medications table.
# - Keep saved medication snapshots scoped to a patient hash.
# - Preserve the canonical MFDS product identifier for later enrichment.
# - Preserve interaction, side-effect, and storage guidance shown before save.
# - Preserve prescription-derived dosage schedule fields for later schedule features.
# - Persist the current medication schedule status for CheckSchedule use cases.
# Attributes:
# - patient_hash (String): Patient ownership scope for the operation.
# - created_date (Date): Date the schedule or medication snapshot was created.
# - prescription_date (Date): Prescription dispensing date, if available.
# - prescription_batch_id (String(64)): Optional identifier linking medications from one analysis batch.
# - item_seq (String): Canonical MFDS product identifier.
# - item_name (String): Public medication product name.
class _SavedMedication(Base):
    __tablename__ = "saved_medications"
    __table_args__ = (
        UniqueConstraint(
            "patient_hash",
            "created_date",
            "deduplication_key",
            name="uq_saved_medication_daily_signature",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    created_date = Column(Date, nullable=True, default=application_today)
    prescription_date = Column(Date, nullable=True)
    prescription_batch_id = Column(String(64), nullable=True, index=True)
    item_seq = Column(String, nullable=True, index=True)
    item_name = Column(String, index=True)
    efficacy = Column(String)
    use_method = Column(String)
    warning_message = Column(String)
    interaction = Column(Text, nullable=True)
    side_effect = Column(Text, nullable=True)
    storage_method = Column(Text, nullable=True)
    dosage_per_time = Column(String, nullable=True)
    daily_frequency = Column(String, nullable=True)
    total_days = Column(String, nullable=True)
    schedule_slot_keys = Column(Text, nullable=False, default="[]", server_default="[]")
    deduplication_key = Column(
        String(64),
        nullable=False,
        index=True,
        default=lambda: secrets.token_hex(32),
    )
    image_url = Column(String, nullable=True)
    medication_status = Column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
    )
    medication_status_date = Column(Date, nullable=True)
    ai_guide = Column(String, nullable=True)


# Function Name: build_saved_medication_deduplication_key
# Description:
# - Hashes normalized medication, date, course and slot fields, including a batch identifier only when provided.
# Parameters:
# - item_name (str | None): Public medication product name.
# - prescription_date (date | None): Prescription dispensing date, if available.
# - prescription_batch_id (str | None): Optional identifier linking medications from one analysis batch.
# - dosage_per_time (str | None): Dose per administration from the prescription.
# - daily_frequency (str | None): Number or description of doses per day.
# - total_days (str | None): Prescribed course duration.
# - schedule_slot_keys (object): User-confirmed medication time slots.
# Returns:
# - SHA-256 fingerprint compatible with legacy snapshots lacking a batch ID.
def build_saved_medication_deduplication_key(
    *,
    item_name: str | None,
    prescription_date: date | None,
    prescription_batch_id: str | None,
    dosage_per_time: str | None,
    daily_frequency: str | None,
    total_days: str | None,
    schedule_slot_keys: object,
) -> str:
    normalized_slots = _normalize_schedule_slot_value(schedule_slot_keys)
    signature_parts = [
        _normalize_signature_text(item_name),
        prescription_date.isoformat() if prescription_date else "",
        _normalize_signature_text(dosage_per_time),
        _normalize_signature_text(daily_frequency),
        _normalize_signature_text(total_days),
        normalized_slots,
    ]
    normalized_batch_id = _normalize_signature_text(prescription_batch_id)
    if normalized_batch_id:
        signature_parts.append(normalized_batch_id)
    signature = "\0".join(signature_parts)
    return hashlib.sha256(signature.encode("utf-8")).hexdigest()


# 함수이름: _normalize_signature_text
# 함수역할:
# - 중복 비교에 사용할 문자열의 대소문자와 연속 공백을 통일한다.
# 매개변수:
# - value (str | None): 중복 키를 구성할 선택적 약품·복용 정보 문자열.
# 반환값:
# - 정규화된 문자열; None은 빈 문자열.
def _normalize_signature_text(value: str | None) -> str:
    return " ".join((value or "").strip().lower().split())


# 함수이름: _normalize_schedule_slot_value
# 함수역할:
# - JSON 또는 목록 입력에서 지원 시간대만 골라 고정 순서로 중복 없이 직렬화한다.
# 매개변수:
# - value (object): JSON 문자열 또는 목록 형태의 복용 시간대 입력.
# 반환값:
# - 결정적 비교용 시간대 JSON; 잘못된 입력은 빈 목록 JSON.
def _normalize_schedule_slot_value(value: object) -> str:
    decoded: object = value
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except (TypeError, ValueError, json.JSONDecodeError):
            decoded = []
    if not isinstance(decoded, (list, tuple, set)):
        decoded = []
    requested = {str(item).strip().lower() for item in decoded}
    ordered = [
        slot_key
        for slot_key in ("morning", "lunch", "evening", "bedtime")
        if slot_key in requested
    ]
    return json.dumps(ordered, ensure_ascii=True, separators=(",", ":"))

