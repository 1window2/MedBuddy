import importlib.util
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory
from sqlalchemy import MetaData, Table, create_engine, inspect, select
from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from core.application_clock import application_today
from core.schema_initialization import verify_database_revision
from entities.chat_message_entity import _ChatMessage
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from support.db import seed_account, seed_medication


ROOT = Path(__file__).resolve().parents[1]
OLD_REVISION = "b3a7d9e2f601"
NEW_REVISION = "d19e7c4b2a60"
CATALOG_REVISION = "c5e1a7f3b902"


def migration():
    spec = importlib.util.spec_from_file_location(
        "resource_id_migration", ROOT / "migrations/versions/d19e7c4b2a60_preserve_deleted_resource_ids.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def config_for(tmp_path):
    config = Config(str(ROOT / "alembic.ini"))
    config.attributes["database_url"] = f"sqlite:///{(tmp_path / 'id-migration.db').as_posix()}"
    return config


def snapshot(connection):
    return {
        table: sorted(connection.exec_driver_sql(f'SELECT * FROM "{table}"').all(), key=repr)
        for table in inspect(connection).get_table_names()
        if table != "alembic_version"
    }


def historical_medications(db: Session) -> Table:
    # 최신 ORM 필드가 없는 과거 스키마는 당시 테이블 정의로만 읽고 쓴다.
    return Table("saved_medications", MetaData(), autoload_with=db.connection())


def seed_historical_medication(db: Session, **overrides: object) -> int:
    values = {
        "patient_hash": "patient-a", "created_date": application_today(),
        "item_name": "test-tablet", "daily_frequency": "1",
        "total_days": "7", "schedule_slot_keys": '["morning"]',
        "medication_status": False, "deduplication_key": uuid4().hex,
    }
    values.update(overrides)
    result = db.execute(historical_medications(db).insert().values(**values))
    medication_id = int(result.inserted_primary_key[0])
    db.commit()
    return medication_id


def seed_history(engine):
    with Session(engine) as db:
        seed_account(db, "patient-a", "caregiver-a", "unrelated-owner")
        medication_id = seed_historical_medication(db)
        link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
        db.add(link)
        completions = Table("medication_completions", MetaData(), autoload_with=db.connection())
        db.execute(completions.insert().values(
            saved_medication_id=medication_id, patient_hash="patient-a",
            schedule_date=application_today(), slot_key="morning", completed=True,
        ))
        db.commit()
        result = ManageLinkedChat(db).send_message(
            link_id=link.id, sender_hash="patient-a", client_message_id="migration_message", body="synthetic",
        )
        return medication_id, link.id, result.message.message_id


def test_existing_database_upgrade_preserves_rows_and_prevents_id_reuse(tmp_path):
    config = config_for(tmp_path)
    command.upgrade(config, OLD_REVISION)
    engine = create_engine(config.attributes["database_url"])
    try:
        medication_id, link_id, message_id = seed_history(engine)
        with engine.connect() as connection:
            before = snapshot(connection)
        for direction, revision in [(command.upgrade, NEW_REVISION),
                                    (command.downgrade, OLD_REVISION),
                                    (command.upgrade, NEW_REVISION)]:
            direction(config, revision)
            with engine.connect() as connection:
                assert snapshot(connection) == before
                assert connection.exec_driver_sql("PRAGMA foreign_key_check").all() == []
                assert connection.exec_driver_sql("PRAGMA integrity_check").scalar() == "ok"
        # 현재 컨트롤은 최신 스키마에서 검증하되 위의 과거 왕복 이력 비교는 유지한다.
        command.upgrade(config, "head")
        with Session(engine) as db:
            db.connection().exec_driver_sql("PRAGMA foreign_keys=ON")
            CheckSavedMedication(db).requestDelete(medication_id, "patient-a")
            assert seed_medication(db, item_name="replacement").id > medication_id
            control = LinkPatientCaregiver(db)
            control.requestUnlink(link_id, "patient-a")
            code = control.generatePatientHash("patient-a")["data"]["patient_code"]
            control.requestPatientCaregiverLink("caregiver-a", code)
            assert ManageLinkedChat(db).send_message(
                link_id=link_id, sender_hash="patient-a", client_message_id="after_migration", body="synthetic-new",
            ).message.message_id > message_id
    finally:
        engine.dispose()


def test_migration_rejects_populated_foreign_key_connection_before_changes(tmp_path):
    config = config_for(tmp_path)
    command.upgrade(config, OLD_REVISION)
    engine = create_engine(config.attributes["database_url"])
    try:
        seed_history(engine)
        with engine.connect() as connection:
            connection.exec_driver_sql("PRAGMA foreign_keys=ON")
            before = snapshot(connection)
            schema = connection.exec_driver_sql("SELECT name,sql FROM sqlite_master ORDER BY name").all()
            module = migration()
            with patch.object(module, "op", Operations(MigrationContext.configure(connection))):
                with pytest.raises(RuntimeError, match="foreign_keys=OFF"):
                    module.upgrade()
            assert snapshot(connection) == before
            assert connection.exec_driver_sql("SELECT name,sql FROM sqlite_master ORDER BY name").all() == schema
    finally:
        engine.dispose()


def test_repeat_upgrade_does_not_reset_deleted_high_water_marks(fk_engine, fk_db):
    seed_account(fk_db, "patient-a", "caregiver-a")
    medication = seed_medication(fk_db, id=100)
    fk_db.delete(medication)
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    fk_db.add(link)
    fk_db.commit()
    fk_db.add(_ChatMessage(id=100, link_id=link.id, sender_hash="patient-a", client_message_id="high_water", body="synthetic"))
    fk_db.commit()
    fk_db.query(_ChatMessage).delete()
    fk_db.commit()
    fk_db.rollback()
    with fk_engine.begin() as connection:
        module = migration()
        with patch.object(module, "op", Operations(MigrationContext.configure(connection))):
            module.upgrade()
            module.upgrade()
    assert seed_medication(fk_db, item_name="later").id > 100
    assert ManageLinkedChat(fk_db).send_message(
        link_id=link.id, sender_hash="patient-a", client_message_id="later", body="later",
    ).message.message_id > 100


def test_upgrade_cannot_recover_ids_deleted_before_autoincrement(tmp_path):
    config = config_for(tmp_path)
    command.upgrade(config, OLD_REVISION)
    engine = create_engine(config.attributes["database_url"])
    try:
        _, link_id, _ = seed_history(engine)
        with Session(engine) as db:
            db.connection().exec_driver_sql("PRAGMA foreign_keys=ON")
            deleted_medication_id = seed_historical_medication(db, item_name="old-highest")
            deleted_message_id = ManageLinkedChat(db).send_message(
                link_id=link_id, sender_hash="patient-a", client_message_id="old_highest", body="synthetic",
            ).message.message_id
            medications = historical_medications(db)
            db.execute(medications.delete().where(medications.c.id == deleted_medication_id))
            db.query(_ChatMessage).filter_by(id=deleted_message_id).delete()
            db.commit()
        command.upgrade(config, NEW_REVISION)
        with Session(engine) as db:
            # 삭제 이력은 소급 복원할 수 없으므로 적용 전 동기화 완료와 실패·보류 항목 확인이 필요하다.
            assert seed_historical_medication(db, item_name="after-upgrade") == deleted_medication_id
            assert ManageLinkedChat(db).send_message(
                link_id=link_id, sender_hash="patient-a", client_message_id="after_upgrade", body="synthetic",
            ).message.message_id == deleted_message_id
    finally:
        engine.dispose()


@pytest.mark.parametrize("starting_revision", [NEW_REVISION, CATALOG_REVISION, "both"])
def test_merge_preserves_applied_histories_data_and_deleted_ids(tmp_path, starting_revision):
    config = config_for(tmp_path)
    if starting_revision == "both":
        command.upgrade(config, NEW_REVISION)
        command.upgrade(config, CATALOG_REVISION)
    else:
        command.upgrade(config, starting_revision)
    engine = create_engine(config.attributes["database_url"])
    try:
        _, link_id, _ = seed_history(engine)
        metadata = MetaData()
        metadata.reflect(bind=engine)
        tokens = metadata.tables["device_push_tokens"]
        token_values = dict(
            user_hash="patient-a", token="synthetic-migration-token", platform="android",
            enabled=True, supports_caregiver_actions=True,
            created_at=datetime(2026, 10, 11),
            updated_at=datetime(2026, 10, 11),
        )
        if "registration_version" in tokens.c:
            token_values["registration_version"] = "a" * 32
        with engine.begin() as connection:
            connection.execute(tokens.insert().values(**token_values))
            if "catalog_refresh_state" in metadata.tables:
                connection.execute(metadata.tables["catalog_refresh_state"].insert().values(
                    name="synthetic-catalog", last_success_at=token_values["created_at"],
                ))

        def delete_highest_ids():
            with Session(engine) as db:
                medication_id = seed_historical_medication(db, id=900, item_name="deleted-highest")
                message = _ChatMessage(
                    id=900, link_id=link_id, sender_hash="patient-a",
                    client_message_id="deleted_highest", body="synthetic",
                )
                db.add(message)
                db.commit()
                medications = historical_medications(db)
                db.execute(medications.delete().where(medications.c.id == medication_id))
                db.delete(message)
                db.commit()

        # 적용된 ID 보호 이력의 삭제 상한은 병합으로 초기화되면 안 된다.
        if starting_revision != CATALOG_REVISION:
            delete_highest_ids()
        with engine.connect() as connection:
            before = {
                table.name: connection.execute(select(table)).all()
                for table in metadata.sorted_tables if table.name != "alembic_version"
            }
        command.upgrade(config, "head")
        command.upgrade(config, "head")
        with engine.connect() as connection:
            verify_database_revision(connection)
            assert connection.exec_driver_sql("SELECT version_num FROM alembic_version").scalar_one() == ScriptDirectory.from_config(config).get_current_head()
            for table in metadata.sorted_tables:
                if table.name != "alembic_version":
                    assert connection.execute(select(table)).all() == before[table.name]
            assert connection.exec_driver_sql("PRAGMA foreign_key_check").all() == []
            assert connection.exec_driver_sql("PRAGMA integrity_check").scalar_one() == "ok"
            assert "registration_version" in {
                column["name"] for column in inspect(connection).get_columns("device_push_tokens")
            }
            assert inspect(connection).has_table("catalog_refresh_state")
            for table in ("saved_medications", "chat_messages"):
                assert "AUTOINCREMENT" in connection.exec_driver_sql(
                    "SELECT sql FROM sqlite_master WHERE name = ?", (table,),
                ).scalar_one().upper()
        if starting_revision == CATALOG_REVISION:
            delete_highest_ids()
        with Session(engine) as db:
            assert seed_medication(db, item_name="after-merge").id > 900
            assert ManageLinkedChat(db).send_message(
                link_id=link_id, sender_hash="patient-a",
                client_message_id="after_merge", body="synthetic-after-merge",
            ).message.message_id > 900
    finally:
        engine.dispose()
