# 파일명: f93ac76b2e11_strengthen_data_lifecycle_integrity.py
# 역할: 내부 사용자 기준 테이블과 환자·보호자 FK를 추가한다. 저장 약의 결정적 중복 키와 유니크 제약을 추가한다. 복용 완료 기록을 저장 약 삭제 cascade에 연결한다.
"""데이터 수명주기와 관계 무결성을 강화한다.

Revision ID: f93ac76b2e11
Revises: e82bc4d1a930
Create Date: 2026-07-29
"""

from collections.abc import Sequence
from datetime import UTC, date, datetime
import hashlib
import json

from alembic import op
import sqlalchemy as sa
from sqlalchemy.engine import RowMapping


revision: str = "f93ac76b2e11"
down_revision: str | None = "e82bc4d1a930"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_USER_HASH_COLUMNS = (
    ("saved_medications", "patient_hash"),
    ("medication_completions", "patient_hash"),
    ("notification_settings", "patient_hash"),
    ("health_recommendation_cache", "patient_hash"),
    ("patient_caregiver_links", "patient_hash"),
    ("patient_caregiver_links", "caregiver_hash"),
    ("patient_link_codes", "patient_hash"),
    ("patient_link_codes", "caregiver_hash"),
    ("guardian_alert_settings", "guardian_hash"),
    ("guardian_alert_settings", "patient_hash"),
    ("device_push_tokens", "user_hash"),
    ("user_settings", "user_hash"),
)


# 함수이름: upgrade
# 함수역할:
# - 내부 사용자 기준 테이블과 환자·보호자 FK를 추가한다.
# - 저장 약의 결정적 중복 키와 유니크 제약을 추가한다.
# - 복용 완료 기록을 저장 약 삭제 cascade에 연결한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def upgrade() -> None:
    op.create_table(
        "user_accounts",
        sa.Column("user_hash", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("user_hash"),
    )
    _backfill_user_accounts()

    op.add_column(
        "saved_medications",
        sa.Column("deduplication_key", sa.String(length=64), nullable=True),
    )
    _backfill_deduplication_keys()

    with op.batch_alter_table("saved_medications", recreate="always") as batch_op:
        batch_op.alter_column(
            "deduplication_key",
            existing_type=sa.String(length=64),
            nullable=False,
        )
        batch_op.create_index(
            "ix_saved_medications_deduplication_key",
            ["deduplication_key"],
            unique=False,
        )
        batch_op.create_unique_constraint(
            "uq_saved_medication_daily_signature",
            ["patient_hash", "created_date", "deduplication_key"],
        )
        batch_op.create_foreign_key(
            "fk_saved_medications_patient_hash_user_accounts",
            "user_accounts",
            ["patient_hash"],
            ["user_hash"],
            ondelete="CASCADE",
        )

    _add_user_foreign_keys()
    with op.batch_alter_table(
        "medication_completions",
        recreate="always",
    ) as batch_op:
        batch_op.create_foreign_key(
            "fk_medication_completions_saved_medication",
            "saved_medications",
            ["saved_medication_id"],
            ["id"],
            ondelete="CASCADE",
        )


# 함수이름: downgrade
# 함수역할:
# - 이번 revision이 추가한 FK, 중복 제약, 사용자 기준 테이블을 제거한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def downgrade() -> None:
    with op.batch_alter_table(
        "medication_completions",
        recreate="always",
    ) as batch_op:
        batch_op.drop_constraint(
            "fk_medication_completions_saved_medication",
            type_="foreignkey",
        )
    _drop_user_foreign_keys()
    with op.batch_alter_table("saved_medications", recreate="always") as batch_op:
        batch_op.drop_constraint(
            "fk_saved_medications_patient_hash_user_accounts",
            type_="foreignkey",
        )
        batch_op.drop_constraint(
            "uq_saved_medication_daily_signature",
            type_="unique",
        )
        batch_op.drop_index("ix_saved_medications_deduplication_key")
        batch_op.drop_column("deduplication_key")
    op.drop_table("user_accounts")


# 함수이름: _backfill_user_accounts
# 함수역할:
# - 기존 소유 범위 열의 고유 사용자 식별자와 기본 로컬 사용자를 모아 계정 기준 테이블에 채운다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def _backfill_user_accounts() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    table_names = set(inspector.get_table_names())
    user_hashes = {"local_patient"}
    for table_name, column_name in _USER_HASH_COLUMNS:
        if table_name not in table_names:
            continue
        rows = connection.execute(
            sa.text(
                f"SELECT DISTINCT {column_name} FROM {table_name} "
                f"WHERE {column_name} IS NOT NULL AND {column_name} <> ''"
            )
        )
        user_hashes.update(str(row[0]).strip() for row in rows if str(row[0]).strip())

    account_table = sa.table(
        "user_accounts",
        sa.column("user_hash", sa.String()),
        sa.column("created_at", sa.DateTime()),
        sa.column("updated_at", sa.DateTime()),
    )
    timestamp = datetime.now(UTC).replace(tzinfo=None)
    op.bulk_insert(
        account_table,
        [
            {
                "user_hash": user_hash,
                "created_at": timestamp,
                "updated_at": timestamp,
            }
            for user_hash in sorted(user_hashes)
        ],
    )


# 함수이름: _backfill_deduplication_keys
# 함수역할:
# - 기존 저장 약의 생성일과 중복 키를 채우고 같은 키가 충돌하면 행 식별자로 구분해 기록을 보존한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def _backfill_deduplication_keys() -> None:
    connection = op.get_bind()
    rows = connection.execute(
        sa.text(
            "SELECT id, patient_hash, created_date, prescription_date, "
            "item_name, dosage_per_time, daily_frequency, total_days, "
            "schedule_slot_keys FROM saved_medications ORDER BY id"
        )
    ).mappings()
    fallback_date = date.today().isoformat()
    used_keys: set[tuple[str, str, str]] = set()
    for row in rows:
        patient_hash = str(row["patient_hash"] or "local_patient")
        created_date = str(row["created_date"] or fallback_date)
        if not row["created_date"]:
            connection.execute(
                sa.text(
                    "UPDATE saved_medications SET created_date = :created_date "
                    "WHERE id = :medication_id"
                ),
                {"created_date": created_date, "medication_id": row["id"]},
            )
        deduplication_key = _build_deduplication_key(row)
        identity = (patient_hash, created_date, deduplication_key)
        if identity in used_keys:
            deduplication_key = hashlib.sha256(
                f"{deduplication_key}\0legacy:{row['id']}".encode("utf-8")
            ).hexdigest()
            identity = (patient_hash, created_date, deduplication_key)
        used_keys.add(identity)
        connection.execute(
            sa.text(
                "UPDATE saved_medications "
                "SET deduplication_key = :deduplication_key "
                "WHERE id = :medication_id"
            ),
            {
                "deduplication_key": deduplication_key,
                "medication_id": row["id"],
            },
        )


# 함수이름: _build_deduplication_key
# 함수역할:
# - 기존 약품명·조제일·복용량·횟수·기간·시간대를 정규화해 마이그레이션용 중복 키를 계산한다.
# 매개변수:
# - row (RowMapping): 기존 약품명·조제일·복용량·시간대 열이 담긴 저장 약 행.
# 반환값:
# - 정규화 필드를 NUL로 결합한 값의 SHA-256 해시.
def _build_deduplication_key(row: RowMapping) -> str:
    signature = "\0".join(
        (
            _normalize_text(row["item_name"]),
            str(row["prescription_date"] or ""),
            _normalize_text(row["dosage_per_time"]),
            _normalize_text(row["daily_frequency"]),
            _normalize_text(row["total_days"]),
            _normalize_slots(row["schedule_slot_keys"]),
        )
    )
    return hashlib.sha256(signature.encode("utf-8")).hexdigest()


# 함수이름: _normalize_text
# 함수역할:
# - 기존 열 값을 소문자 문자열로 바꾸고 연속 공백을 정리한다.
# 매개변수:
# - value (object): 기존 행에서 중복 키를 구성할 원본 열 값.
# 반환값:
# - 중복 키 비교용 문자열; 값이 없으면 빈 문자열.
def _normalize_text(value: object) -> str:
    return " ".join(str(value or "").strip().lower().split())


# 함수이름: _normalize_slots
# 함수역할:
# - 기존 시간대 JSON에서 지원 목록만 골라 고정 순서의 압축 JSON으로 바꾼다.
# 매개변수:
# - value (object): 기존 행의 복용 시간대 JSON 또는 목록 값.
# 반환값:
# - 결정적인 시간대 JSON; 잘못된 값은 빈 목록 JSON.
def _normalize_slots(value: object) -> str:
    try:
        decoded = json.loads(str(value or "[]"))
    except (TypeError, ValueError, json.JSONDecodeError):
        decoded = []
    if not isinstance(decoded, list):
        decoded = []
    requested = {str(item).strip().lower() for item in decoded}
    ordered = [
        slot_key
        for slot_key in ("morning", "lunch", "evening", "bedtime")
        if slot_key in requested
    ]
    return json.dumps(ordered, separators=(",", ":"))


# 함수이름: _add_user_foreign_keys
# 함수역할:
# - 복약·알림·연동·설정 표에 계정 외래키를 추가하며 코드 사용 보호자는 SET NULL, 나머지는 CASCADE로 연결한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def _add_user_foreign_keys() -> None:
    definitions = (
        (
            "medication_completions",
            "fk_medication_completions_patient_hash_user_accounts",
            "patient_hash",
            "CASCADE",
        ),
        (
            "notification_settings",
            "fk_notification_settings_patient_hash_user_accounts",
            "patient_hash",
            "CASCADE",
        ),
        (
            "health_recommendation_cache",
            "fk_health_recommendation_cache_patient_hash_user_accounts",
            "patient_hash",
            "CASCADE",
        ),
        (
            "patient_caregiver_links",
            "fk_patient_caregiver_links_patient_hash_user_accounts",
            "patient_hash",
            "CASCADE",
        ),
        (
            "patient_caregiver_links",
            "fk_patient_caregiver_links_caregiver_hash_user_accounts",
            "caregiver_hash",
            "CASCADE",
        ),
        (
            "patient_link_codes",
            "fk_patient_link_codes_patient_hash_user_accounts",
            "patient_hash",
            "CASCADE",
        ),
        (
            "patient_link_codes",
            "fk_patient_link_codes_caregiver_hash_user_accounts",
            "caregiver_hash",
            "SET NULL",
        ),
        (
            "guardian_alert_settings",
            "fk_guardian_alert_settings_guardian_hash_user_accounts",
            "guardian_hash",
            "CASCADE",
        ),
        (
            "guardian_alert_settings",
            "fk_guardian_alert_settings_patient_hash_user_accounts",
            "patient_hash",
            "CASCADE",
        ),
        (
            "device_push_tokens",
            "fk_device_push_tokens_user_hash_user_accounts",
            "user_hash",
            "CASCADE",
        ),
        (
            "user_settings",
            "fk_user_settings_user_hash_user_accounts",
            "user_hash",
            "CASCADE",
        ),
    )
    for table_name, constraint_name, column_name, ondelete in definitions:
        with op.batch_alter_table(table_name, recreate="always") as batch_op:
            batch_op.create_foreign_key(
                constraint_name,
                "user_accounts",
                [column_name],
                ["user_hash"],
                ondelete=ondelete,
            )


# 함수이름: _drop_user_foreign_keys
# 함수역할:
# - 이번 버전이 추가한 사용자 계정 외래키를 역순으로 제거해 계정 기준 테이블 삭제를 준비한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def _drop_user_foreign_keys() -> None:
    definitions = (
        (
            "user_settings",
            "fk_user_settings_user_hash_user_accounts",
        ),
        (
            "device_push_tokens",
            "fk_device_push_tokens_user_hash_user_accounts",
        ),
        (
            "guardian_alert_settings",
            "fk_guardian_alert_settings_patient_hash_user_accounts",
        ),
        (
            "guardian_alert_settings",
            "fk_guardian_alert_settings_guardian_hash_user_accounts",
        ),
        (
            "patient_link_codes",
            "fk_patient_link_codes_caregiver_hash_user_accounts",
        ),
        (
            "patient_link_codes",
            "fk_patient_link_codes_patient_hash_user_accounts",
        ),
        (
            "patient_caregiver_links",
            "fk_patient_caregiver_links_caregiver_hash_user_accounts",
        ),
        (
            "patient_caregiver_links",
            "fk_patient_caregiver_links_patient_hash_user_accounts",
        ),
        (
            "health_recommendation_cache",
            "fk_health_recommendation_cache_patient_hash_user_accounts",
        ),
        (
            "notification_settings",
            "fk_notification_settings_patient_hash_user_accounts",
        ),
        (
            "medication_completions",
            "fk_medication_completions_patient_hash_user_accounts",
        ),
    )
    for table_name, constraint_name in definitions:
        with op.batch_alter_table(table_name, recreate="always") as batch_op:
            batch_op.drop_constraint(constraint_name, type_="foreignkey")
