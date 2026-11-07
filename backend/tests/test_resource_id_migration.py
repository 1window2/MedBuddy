# 파일명: test_resource_id_migration.py
# 역할: 리소스 ID 재사용 방지 이전의 데이터 보존, 개정 병합과 소급 복구 한계를 검증한다.

import importlib.util
from datetime import datetime
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory
from sqlalchemy import MetaData, Table, create_engine, inspect, select
from sqlalchemy.engine import Connection, Engine, Row
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


# 함수이름: migration
# 함수역할:
# - 리소스 ID 보호 마이그레이션 파일을 별도 모듈로 불러온다.
# 매개변수:
# - 없음.
# 반환값:
# - ModuleType; upgrade를 직접 호출할 마이그레이션 모듈.
def migration() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "resource_id_migration", ROOT / "migrations/versions/d19e7c4b2a60_preserve_deleted_resource_ids.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# 함수이름: config_for
# 함수역할:
# - 임시 SQLite 파일을 대상으로 저장소의 Alembic 설정을 구성한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - Config; 테스트 데이터베이스 URL이 지정된 설정.
def config_for(tmp_path: Path) -> Config:
    config = Config(str(ROOT / "alembic.ini"))
    config.attributes["database_url"] = f"sqlite:///{(tmp_path / 'id-migration.db').as_posix()}"
    return config


# 함수이름: snapshot
# 함수역할:
# - Alembic 개정 표를 제외한 모든 테이블 행을 정렬해 데이터 보존 비교 자료를 만든다.
# 매개변수:
# - connection: Connection; 검사할 SQLite 연결.
# 반환값:
# - dict[str, list[Row]]; 테이블별 전체 행.
def snapshot(connection: Connection) -> dict[str, list[Row[tuple[Any, ...]]]]:
    return {
        table: sorted(connection.exec_driver_sql(f'SELECT * FROM "{table}"').all(), key=repr)
        for table in inspect(connection).get_table_names()
        if table != "alembic_version"
    }


# 함수이름: historical_medications
# 함수역할:
# - 최신 ORM 열을 가정하지 않고 현재 연결의 과거 약품 테이블 정의를 반영한다.
# 매개변수:
# - db: Session; 과거 스키마에 연결된 세션.
# 반환값:
# - Table; 실제 저장 약품 테이블.
def historical_medications(db: Session) -> Table:
    # 최신 ORM 필드가 없는 과거 스키마는 당시 테이블 정의로만 읽고 쓴다.
    return Table("saved_medications", MetaData(), autoload_with=db.connection())


# 함수이름: seed_historical_medication
# 함수역할:
# - 과거 스키마의 열만 사용해 고유 중복 키를 가진 약품을 저장·커밋한다.
# 매개변수:
# - db: Session; 과거 스키마에 연결된 세션.
# - overrides: dict[str, object]; 합성 약품에 덮어쓸 열 값.
# 반환값:
# - int; 삽입된 약품 ID.
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


# 함수이름: seed_history
# 함수역할:
# - 이전 스키마에 계정·약품·완료 기록·연동·채팅 메시지를 만들어 이전 전 비교 상태를 준비한다.
# 매개변수:
# - engine: Engine; 이전 버전 스키마가 적용된 데이터베이스.
# 반환값:
# - tuple[int, int, int]; 약품·연동·메시지 ID.
def seed_history(engine: Engine) -> tuple[int, int, int]:
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


# 함수이름: test_existing_database_upgrade_preserves_rows_and_prevents_id_reuse
# 함수역할:
# - 개정 왕복 중 모든 행과 무결성을 보존하며 최신 스키마에서 삭제 약품·메시지 ID를 재사용하지 않는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - None.
def test_existing_database_upgrade_preserves_rows_and_prevents_id_reuse(tmp_path: Path) -> None:
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


# 함수이름: test_migration_rejects_populated_foreign_key_connection_before_changes
# 함수역할:
# - 외래 키가 활성화된 기존 데이터 연결에서는 이전을 거부하고 데이터·스키마를 변경하지 않는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - None.
def test_migration_rejects_populated_foreign_key_connection_before_changes(tmp_path: Path) -> None:
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


# 함수이름: test_repeat_upgrade_does_not_reset_deleted_high_water_marks
# 함수역할:
# - ID 보호 이전을 반복해도 삭제된 최대 ID 100의 상한을 초기화하지 않는지 확인한다.
# 매개변수:
# - fk_engine: Engine; 외래 키가 활성화된 격리 SQLite 데이터베이스.
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_repeat_upgrade_does_not_reset_deleted_high_water_marks(fk_engine: Engine, fk_db: Session) -> None:
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


# 함수이름: test_upgrade_cannot_recover_ids_deleted_before_autoincrement
# 함수역할:
# - AUTOINCREMENT 적용 전에 삭제된 최대 ID는 복구할 수 없어 재사용될 수 있다는 이전 한계를 명시한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - None.
def test_upgrade_cannot_recover_ids_deleted_before_autoincrement(tmp_path: Path) -> None:
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


# 함수이름: test_merge_preserves_applied_histories_data_and_deleted_ids
# 함수역할:
# - 두 갈래 개정의 어느 시작점에서도 병합·반복 이전이 데이터와 삭제 ID 상한을 보존하는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# - starting_revision: str; ID 보호·카탈로그 개정 또는 두 개정 모두.
# 반환값:
# - None.
@pytest.mark.parametrize("starting_revision", [NEW_REVISION, CATALOG_REVISION, "both"])
def test_merge_preserves_applied_histories_data_and_deleted_ids(tmp_path: Path, starting_revision: str) -> None:
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

        # 함수이름: delete_highest_ids
        # 함수역할:
        # - 약품과 메시지 ID 900을 저장 후 삭제하여 SQLite 시퀀스에만 남은 상한을 만든다.
        # 매개변수:
        # - 없음.
        # 반환값:
        # - None.
        def delete_highest_ids() -> None:
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
