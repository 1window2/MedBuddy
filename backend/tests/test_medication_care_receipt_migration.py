"""기존 영수증의 약 연결 복구와 삭제된 약의 응답 제거를 검증한다."""

from datetime import datetime
import json
from pathlib import Path
from uuid import uuid4

from alembic import command
from alembic.config import Config
from fastapi import HTTPException
import pytest
from sqlalchemy import MetaData, Table, create_engine, select
from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.manage_medication_care_control import ManageMedicationCare
from entities.medication_care_entity import _MedicationCareOperation


@pytest.mark.parametrize("delete_original", [False, True])
def test_upgrade_backfills_legacy_receipts_and_preserves_idempotency(tmp_path, delete_original):
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = f"sqlite:///{(tmp_path / 'care-receipt-upgrade.db').as_posix()}"
    command.upgrade(config, "c8d3e7a92104")
    engine = create_engine(config.attributes["database_url"])
    metadata = MetaData()
    users = Table("user_accounts", metadata, autoload_with=engine)
    medications = Table("saved_medications", metadata, autoload_with=engine)
    operations = Table("medication_care_operations", metadata, autoload_with=engine)
    now = datetime(2026, 10, 22)
    payloads = [
        json.dumps({"success": True, "medication_id": 1, "item_name": "legacy-private", "reason": "private-reason"}),
        json.dumps({"success": True, "id": 2, "revision": 1}),
        json.dumps({"success": True, "medication_id": 999, "item_name": "already-deleted"}),
        "invalid-json", "[]", json.dumps({"medication_id": True, "item_name": "invalid-id"}),
        json.dumps({"medication_id": 3, "item_name": "wrong-owner"}),
    ]
    request_ids = [uuid4() for _ in payloads]
    try:
        with engine.begin() as connection:
            for owner in ("patient-a", "patient-b"):
                connection.execute(users.insert().values(user_hash=owner, created_at=now, updated_at=now))
            for identifier, owner in ((1, "patient-a"), (2, "patient-a"), (3, "patient-b")):
                connection.execute(medications.insert().values(
                    id=identifier, patient_hash=owner, item_name=f"test-{identifier}", created_date=now.date(),
                    deduplication_key=f"legacy-test-{identifier}",
                    superseded_by_id=2 if identifier == 1 else None,
                ))
            connection.execute(operations.insert(), [
                {"id": index + 1, "patient_hash": "patient-a", "operation_id": str(request_ids[index]),
                 "request_hash": "a" * 64, "response_json": payload, "created_at": now}
                for index, payload in enumerate(payloads)
            ])
        command.upgrade(config, "head")
        with Session(engine) as db:
            rows = db.query(_MedicationCareOperation).order_by(_MedicationCareOperation.id).all()
            assert len(rows) == len(payloads)
            assert rows[0].medication_id == 1 and rows[0].response_json == payloads[0]
            assert rows[1].medication_id == 1 and rows[1].replacement_medication_id == 2
            assert rows[1].response_json == payloads[1]
            for index, row in enumerate(rows):
                assert row.operation_id == str(request_ids[index]) and row.request_hash == "a" * 64
                if index >= 2:
                    assert row.response_redacted and row.response_json == "{}"
                    assert row.medication_id is None and row.replacement_medication_id is None
                    with pytest.raises(HTTPException) as error:
                        ManageMedicationCare(db)._replay("patient-a", request_ids[index], "a" * 64)
                    assert error.value.status_code == 410
            CheckSavedMedication(db).requestDelete(1 if delete_original else 2, "patient-a")
            with pytest.raises(HTTPException) as error:
                ManageMedicationCare(db)._replay("patient-a", request_ids[1], "a" * 64)
            assert error.value.status_code == 410
            with pytest.raises(HTTPException) as error:
                ManageMedicationCare(db)._replay("patient-a", request_ids[1], "b" * 64)
            assert error.value.status_code == 409
        command.downgrade(config, "c8d3e7a92104")
        command.upgrade(config, "head")
        with engine.connect() as connection:
            assert connection.execute(select(operations.c.response_json).where(operations.c.id == 2)).scalar_one() == "{}"
            assert connection.exec_driver_sql("PRAGMA foreign_key_check").all() == []
    finally:
        engine.dispose()


def test_receipt_upgrade_processes_multiple_batches(tmp_path):
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = f"sqlite:///{(tmp_path / 'care-receipt-batches.db').as_posix()}"
    command.upgrade(config, "c8d3e7a92104")
    engine = create_engine(config.attributes["database_url"])
    try:
        users = Table("user_accounts", MetaData(), autoload_with=engine)
        operations = Table("medication_care_operations", MetaData(), autoload_with=engine)
        now = datetime(2026, 10, 22)
        with engine.begin() as connection:
            connection.execute(users.insert().values(user_hash="patient-a", created_at=now, updated_at=now))
            connection.execute(operations.insert(), [
                {"patient_hash": "patient-a", "operation_id": str(uuid4()), "request_hash": "a" * 64,
                 "response_json": '{"medication_id":999,"reason":"deleted-health-data"}', "created_at": now}
                for _ in range(503)
            ])
        command.upgrade(config, "head")
        with Session(engine) as db:
            assert db.query(_MedicationCareOperation).count() == 503
            assert db.query(_MedicationCareOperation).filter_by(response_redacted=True, response_json="{}").count() == 503
    finally:
        engine.dispose()
