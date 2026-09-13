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
    inspect,
    text,
)
from sqlalchemy.engine import Engine

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


# Function Name: ensure_saved_medication_schema
# Description:
# - Adds newly introduced saved medication columns to an existing SQLite table.
# - SQLAlchemy create_all creates missing tables but does not alter existing tables.
# Parameters:
# - db_engine (Engine): SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_saved_medication_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_SavedMedication.__tablename__):
        return

    existing_columns = {
        column["name"] for column in inspector.get_columns(_SavedMedication.__tablename__)
    }
    optional_columns = {
        "patient_hash": f"VARCHAR DEFAULT '{DEFAULT_PATIENT_HASH}'",
        "created_date": "DATE",
        "prescription_date": "DATE",
        "prescription_batch_id": "VARCHAR(64)",
        "item_seq": "VARCHAR",
        "dosage_per_time": "VARCHAR",
        "daily_frequency": "VARCHAR",
        "total_days": "VARCHAR",
        "schedule_slot_keys": "TEXT DEFAULT '[]'",
        "deduplication_key": "VARCHAR(64) DEFAULT ''",
        "image_url": "VARCHAR",
        "medication_status": "BOOLEAN DEFAULT 0",
        "medication_status_date": "DATE",
        "ai_guide": "VARCHAR",
        "interaction": "TEXT",
        "side_effect": "TEXT",
        "storage_method": "TEXT",
    }
    today = application_today().isoformat()

    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_SavedMedication.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_SavedMedication.__tablename__} "
                "SET created_date = :today "
                "WHERE created_date IS NULL OR created_date = ''"
            ),
            {"today": today},
        )
        medication_rows = connection.execute(
            text(
                f"SELECT id, patient_hash, created_date, item_name, "
                "prescription_date, dosage_per_time, daily_frequency, "
                "total_days, schedule_slot_keys, prescription_batch_id "
                f"FROM {_SavedMedication.__tablename__}"
            )
        ).mappings()
        used_keys: set[tuple[str, str, str]] = set()
        for row in medication_rows:
            prescription_date = row["prescription_date"]
            if isinstance(prescription_date, str) and prescription_date:
                prescription_date = date.fromisoformat(prescription_date)
            created_date = str(row["created_date"] or today)
            patient_hash = str(row["patient_hash"] or DEFAULT_PATIENT_HASH)
            deduplication_key = build_saved_medication_deduplication_key(
                item_name=row["item_name"],
                prescription_date=prescription_date,
                prescription_batch_id=row["prescription_batch_id"],
                dosage_per_time=row["dosage_per_time"],
                daily_frequency=row["daily_frequency"],
                total_days=row["total_days"],
                schedule_slot_keys=row["schedule_slot_keys"],
            )
            unique_key = (patient_hash, created_date, deduplication_key)
            if unique_key in used_keys:
                deduplication_key = hashlib.sha256(
                    f"{deduplication_key}\0legacy:{row['id']}".encode("utf-8")
                ).hexdigest()
                unique_key = (patient_hash, created_date, deduplication_key)
            used_keys.add(unique_key)
            connection.execute(
                text(
                    f"UPDATE {_SavedMedication.__tablename__} "
                    "SET deduplication_key = :deduplication_key "
                    "WHERE id = :medication_id AND "
                    "(deduplication_key IS NULL OR deduplication_key = '')"
                ),
                {
                    "deduplication_key": deduplication_key,
                    "medication_id": row["id"],
                },
            )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_SavedMedication.__tablename__}_patient_hash "
                f"ON {_SavedMedication.__tablename__} (patient_hash)"
            )
        )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                "uq_saved_medication_daily_signature "
                f"ON {_SavedMedication.__tablename__} "
                "(patient_hash, created_date, deduplication_key)"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_SavedMedication.__tablename__}_item_seq "
                f"ON {_SavedMedication.__tablename__} (item_seq)"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_SavedMedication.__tablename__}_prescription_batch_id "
                f"ON {_SavedMedication.__tablename__} (prescription_batch_id)"
            )
        )
