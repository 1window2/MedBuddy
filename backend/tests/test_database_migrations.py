from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect


def test_current_schema_migrates_into_an_empty_database(tmp_path: Path) -> None:
    database_path = tmp_path / "migration.db"
    database_url = f"sqlite:///{database_path.as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = database_url

    command.upgrade(config, "head")

    engine = create_engine(database_url)
    try:
        tables = set(inspect(engine).get_table_names())
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
    }.issubset(tables)


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
