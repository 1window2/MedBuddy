# File Name: saved_medication_entity.py
# Role: SQLAlchemy entity for saved medication snapshots.

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
# Role: Internal SQLAlchemy row for saved medication detail snapshots.
# Responsibilities:
#   - Map saved medication fields to the saved_medications table.
#   - Keep saved medication snapshots scoped to a patient hash.
#   - Preserve the canonical MFDS product identifier for later enrichment.
#   - Preserve interaction, side-effect, and storage guidance shown before save.
#   - Preserve prescription-derived dosage schedule fields for later schedule features.
#   - Persist the current medication schedule status for CheckSchedule use cases.
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


# 함수명: build_saved_medication_deduplication_key
# 역할:
# - 같은 등록일에 같은 처방 정보가 동시에 저장되어도 DB가 식별할 수 있는 키를 만든다.
# - 조제일자, 약명, 복용량, 횟수, 기간, 시간대를 안정적으로 정규화한다.
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


def _normalize_signature_text(value: str | None) -> str:
    return " ".join((value or "").strip().lower().split())


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
# - db_engine: SQLAlchemy engine bound to the application database.
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
