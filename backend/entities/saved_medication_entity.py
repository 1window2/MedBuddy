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
from entities.medication_schedule_entity import (
    decode_medication_schedule_slot_keys,
    normalize_medication_schedule_slot_keys,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.user_account_entity import _UserAccount  # noqa: F401


# 클래스명: _SavedMedication
# 역할: 환자 소유 약의 상세·안전정보·복용 계획을 영속화한다.
# 주요 책임: 환자별 일일 중복 서명을 제한하고 제품·처방 배치·안전 안내·복용 상태·변경 이력을 보존한다.
# 속성: id는 Integer, patient_hash는 계정 외래키, created_date·prescription_date는 Date, prescription_batch_id·item_seq는 식별 문자열이다.
#   item_name과 효능·용법·경고·상호작용·부작용·보관·AI 안내는 상세 문자열, dosage_per_time·daily_frequency·total_days는 처방 지시다.
#   schedule_slot_keys는 JSON Text, dosing_mode는 String, regimen_revision은 Integer, regimen_effective_from·stopped_on은 Date다.
#   superseded_by_id는 대체 약 Integer, deduplication_key는 String(64), medication_status·medication_status_date는 완료 여부·날짜, image_url은 이미지 주소다.
# 비고: SQLite 자동 증가 ID는 삭제된 약의 지연 요청이 새 약을 가리키지 않게 한다.
class _SavedMedication(Base):
    __tablename__ = "saved_medications"
    __table_args__ = (
        UniqueConstraint(
            "patient_hash",
            "created_date",
            "deduplication_key",
            name="uq_saved_medication_daily_signature",
        ),
        # 삭제된 약의 지연 요청이 새 약을 가리키지 않도록 SQLite ID를 재사용하지 않는다.
        {"sqlite_autoincrement": True},
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
    dosing_mode = Column(String(16), nullable=False, default="scheduled", server_default="scheduled")
    regimen_revision = Column(Integer, nullable=False, default=0, server_default="0")
    regimen_effective_from = Column(Date, nullable=True)
    stopped_on = Column(Date, nullable=True)
    superseded_by_id = Column(Integer, nullable=True)
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


# 함수이름: build_saved_medication_deduplication_key
# 함수역할: 약명·처방 지시·시간대를 정규화해 배치 구분과 필요시 모드를 포함하는 중복 방지 서명을 만든다.
# 매개변수: item_name, prescription_batch_id, dosage_per_time, daily_frequency, total_days (str | None)는 약·배치·지시다.
#   prescription_date (date | None)는 조제일, schedule_slot_keys (object)는 시간대, dosing_mode (str)는 정기/필요시 모드다.
# 반환값: SHA-256 64자리 str. 빈 배치와 정기 모드는 추가 표식을 넣지 않아 기존 서명과 호환한다.
def build_saved_medication_deduplication_key(
    *,
    item_name: str | None,
    prescription_date: date | None,
    prescription_batch_id: str | None,
    dosage_per_time: str | None,
    daily_frequency: str | None,
    total_days: str | None,
    schedule_slot_keys: object,
    dosing_mode: str = "scheduled",
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
    if dosing_mode == "as_needed":
        signature_parts.append("dosing_mode:as_needed")
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


# Function Name: _normalize_schedule_slot_value
# Description: Uses shared slot decoders/normalizers to produce a deterministic compact JSON comparison key.
# Parameters: value (object) is stored JSON text or a slot collection.
# Returns: ASCII JSON of supported slots in canonical order; invalid/absent selections follow shared empty-list handling.
def _normalize_schedule_slot_value(value: object) -> str:
    slots = (
        decode_medication_schedule_slot_keys(value)
        if isinstance(value, str)
        else normalize_medication_schedule_slot_keys(value)
    )
    return json.dumps(slots, ensure_ascii=True, separators=(",", ":"))

