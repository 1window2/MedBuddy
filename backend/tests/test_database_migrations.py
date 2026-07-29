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
