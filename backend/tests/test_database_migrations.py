# 파일명: test_database_migrations.py
# 역할: 신규·기존 로컬 DB의 마이그레이션, 필수 스키마 및 데이터 보존 왕복을 검증한다.

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, MetaData, Table, select
from datetime import datetime

from entities.chat_message_entity import _ChatMessage
from entities.pharmacy_catalog_entity import PharmacyCatalogRecord


# 함수이름: test_chat_deletion_upgrade_preserves_existing_content_and_round_trips
# 함수역할:
# - 채팅 삭제 컬럼을 추가하고 다운그레이드·재적용해도 기존 메시지 본문이 보존되는지 검증한다.
# 매개변수:
# - tmp_path (Path): 격리 마이그레이션 DB를 만들 pytest 임시 디렉터리.
# 반환값:
# - 없음 (None).
def test_chat_deletion_upgrade_preserves_existing_content_and_round_trips(tmp_path: Path) -> None:
    database_url = f"sqlite:///{(tmp_path / 'chat-deletion.db').as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url
    command.upgrade(config, "9c4e7b2a6d10")
    engine = create_engine(database_url)
    metadata = MetaData()
    users = Table("user_accounts", metadata, autoload_with=engine)
    links = Table("patient_caregiver_links", metadata, autoload_with=engine)
    messages = Table("chat_messages", metadata, autoload_with=engine)
    now = datetime(2026, 9, 9)
    with engine.begin() as connection:
        connection.execute(users.insert(), [
            {"user_hash": user, "created_at": now, "updated_at": now}
            for user in ("patient-a", "caregiver-a")
        ])
        connection.execute(links.insert().values(id=1, patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True, created_at=now))
        connection.execute(messages.insert().values(id=1, link_id=1, sender_hash="patient-a", client_message_id="preserved_001", body="Keep this message", created_at=now))
    try:
        command.upgrade(config, "head")
        columns = {item["name"] for item in inspect(engine).get_columns("chat_messages")}
        assert {"patient_deleted_at", "caregiver_deleted_at", "deleted_for_everyone_at"} <= columns
        with engine.connect() as connection:
            assert connection.execute(select(messages.c.body)).scalar_one() == "Keep this message"
        command.downgrade(config, "9c4e7b2a6d10")
        command.upgrade(config, "head")
        with engine.connect() as connection:
            assert connection.execute(select(messages.c.body)).scalar_one() == "Keep this message"
    finally:
        engine.dispose()


# Function Name: test_current_schema_migrates_into_an_empty_database
# Description:
# - Migrates an empty database to the complete schema, including medication safety metadata,
#   deletion tombstones, caregiver aliases, and completion foreign keys.
# Parameters:
# - tmp_path (Path): Pytest temporary directory for the isolated migration database.
# Returns:
# - None.
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
        "interaction",
        "side_effect",
        "storage_method",
    }.issubset(saved_columns)
    assert {
        "deletion_requested_at",
        "identity_deleted_at",
    }.issubset(user_account_columns)
    assert "patient_alias" in caregiver_link_columns
    assert any(
        foreign_key["referred_table"] == "saved_medications"
        for foreign_key in completion_foreign_keys
    )


# 함수이름: test_chat_migration_adopts_auto_created_local_table
# 함수역할:
# - 로컬에서 자동 생성한 채팅 테이블을 수용하여 최신 마이그레이션과 필수 조회 인덱스를 구성하는지 검증한다.
# 매개변수:
# - tmp_path (Path): 격리 마이그레이션 DB를 만들 pytest 임시 디렉터리.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_pharmacy_migration_adopts_auto_created_local_table
# 함수역할:
# - 로컬에서 자동 생성한 약국 테이블을 수용하여 이름·위도·경도 인덱스를 구성하는지 검증한다.
# 매개변수:
# - tmp_path (Path): 격리 마이그레이션 DB를 만들 pytest 임시 디렉터리.
# 반환값:
# - 없음 (None).
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
# - 운영 환경에 필요한 보호자 알림 마감 시·분과 시간대 설정 컬럼이 마이그레이션에 포함되는지 검증한다.
# 매개변수:
# - tmp_path (Path): 격리 마이그레이션 DB를 만들 pytest 임시 디렉터리.
# 반환값:
# - 없음 (None).
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
# - 데이터 무결성 마이그레이션을 되돌리고 재적용한 뒤 계정 테이블과 약 중복 방지 키가 복구되는지 검증한다.
# 매개변수:
# - tmp_path (Path): 격리 마이그레이션 DB를 만들 pytest 임시 디렉터리.
# 반환값:
# - 없음 (None).
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
