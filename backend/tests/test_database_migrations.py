# 파일명: test_database_migrations.py
# 역할: 데이터베이스 마이그레이션 체인과 스키마 호환성을 검증한다.

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from entities.chat_message_entity import _ChatMessage
from entities.pharmacy_catalog_entity import PharmacyCatalogRecord


def test_current_schema_migrates_into_an_empty_database(tmp_path: Path) -> None:
    database_path = tmp_path / "migration.db"
    database_url = f"sqlite:///{database_path.as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url

    command.upgrade(config, "head")

    engine = create_engine(database_url)
    try:
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        saved_columns = {
            column["name"]
            for column in inspector.get_columns("saved_medications")
        }
        completion_foreign_keys = inspector.get_foreign_keys(
            "medication_completions"
        )
        user_account_columns = {
            column["name"]
            for column in inspector.get_columns("user_accounts")
        }
        caregiver_link_columns = {
            column["name"]
            for column in inspector.get_columns("patient_caregiver_links")
        }
    finally:
        engine.dispose()
    assert {
        "alembic_version",
        "saved_medications",
        "medication_completions",
        "notification_settings",
        "guardian_alert_settings",
        "patient_caregiver_links",
        "patient_link_codes",
        "user_settings",
        "user_accounts",
        "pill_identification_references",
        "pharmacy_catalog_records",
        "pharmacy_holiday_schedules",
        "pharmacy_holiday_fetches",
        "korean_holidays",
        "korean_holiday_month_fetches",
        "chat_messages",
    }.issubset(tables)
    assert "official_designations" in {
        column["name"]
        for column in inspector.get_columns("pharmacy_catalog_records")
    }
    assert "deduplication_key" in saved_columns
    assert "prescription_batch_id" in saved_columns
    assert {
        "deletion_requested_at",
        "identity_deleted_at",
    }.issubset(user_account_columns)
    assert "patient_alias" in caregiver_link_columns
    assert any(
        foreign_key["referred_table"] == "saved_medications"
        for foreign_key in completion_foreign_keys
    )


def test_chat_migration_adopts_auto_created_local_table(tmp_path: Path) -> None:
    """로컬 자동 생성 테이블이 있어도 채팅 마이그레이션을 완료한다."""
    database_path = tmp_path / "auto-created-chat.db"
    database_url = f"sqlite:///{database_path.as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url

    command.upgrade(config, "7d2e4f1a8c63")
    engine = create_engine(database_url)
    try:
        _ChatMessage.__table__.create(bind=engine)
        command.upgrade(config, "head")
        inspector = inspect(engine)
        index_names = {
            str(index["name"])
            for index in inspector.get_indexes("chat_messages")
        }
    finally:
        engine.dispose()

    assert {
        "ix_chat_messages_id",
        "ix_chat_messages_link_id",
        "ix_chat_messages_sender_hash",
        "ix_chat_messages_created_at",
    }.issubset(index_names)


def test_pharmacy_migration_adopts_auto_created_local_table(
    tmp_path: Path,
) -> None:
    """로컬 자동 생성 약국 테이블이 있어도 최신 마이그레이션을 완료한다."""
    database_path = tmp_path / "auto-created-pharmacy.db"
    database_url = f"sqlite:///{database_path.as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url

    command.upgrade(config, "6e1b4a9c2d80")
    engine = create_engine(database_url)
    try:
        PharmacyCatalogRecord.__table__.create(bind=engine)
        command.upgrade(config, "head")
        inspector = inspect(engine)
        index_names = {
            str(index["name"])
            for index in inspector.get_indexes("pharmacy_catalog_records")
        }
    finally:
        engine.dispose()

    assert {
        "ix_pharmacy_catalog_records_name",
        "ix_pharmacy_catalog_records_latitude",
        "ix_pharmacy_catalog_records_longitude",
    }.issubset(index_names)


# 함수이름: test_guardian_alert_migration_contains_slot_columns
# 함수역할:
# - 운영 환경에서 자동 생성되지 않는 보호자 시간대별 알림 컬럼이 마이그레이션에 포함됐는지 검증한다.
# 매개변수:
# - tmp_path: 격리된 SQLite 파일을 생성할 pytest 임시 경로
# 반환값:
# - 없음
def test_guardian_alert_migration_contains_slot_columns(tmp_path: Path) -> None:
    database_path = tmp_path / "guardian-alert-migration.db"
    database_url = f"sqlite:///{database_path.as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url

    command.upgrade(config, "head")

    engine = create_engine(database_url)
    try:
        column_names = {
            column["name"]
            for column in inspect(engine).get_columns("guardian_alert_settings")
        }
    finally:
        engine.dispose()

    assert {
        "deadline_hour",
        "deadline_minute",
        "slot_settings",
    }.issubset(column_names)


# 함수이름: test_data_lifecycle_migration_supports_round_trip
# 함수역할:
# - 데이터 무결성 마이그레이션을 되돌린 뒤 다시 적용할 수 있는지 검증한다.
def test_data_lifecycle_migration_supports_round_trip(tmp_path: Path) -> None:
    database_path = tmp_path / "lifecycle-round-trip.db"
    database_url = f"sqlite:///{database_path.as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url

    command.upgrade(config, "head")
    command.downgrade(config, "e82bc4d1a930")
    command.upgrade(config, "head")

    engine = create_engine(database_url)
    try:
        inspector = inspect(engine)
        assert "user_accounts" in inspector.get_table_names()
        assert "deduplication_key" in {
            column["name"]
            for column in inspector.get_columns("saved_medications")
        }
    finally:
        engine.dispose()
