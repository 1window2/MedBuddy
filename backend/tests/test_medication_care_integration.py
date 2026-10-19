# 파일명: test_medication_care_integration.py
# 역할: 새 기록 API의 HTTP 검증, 동시 쓰기와 기존 DB 업그레이드를 격리 환경에서 확인한다.

from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path
from threading import Barrier
from uuid import uuid4

from alembic import command
from alembic.config import Config
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import MetaData, Table, create_engine, select
from sqlalchemy.orm import Session

from api import dependencies
from api.router import router
from controls.manage_medication_care_control import ManageMedicationCare
from core.application_clock import application_today
from core.database import get_db
from entities.medication_care_entity import _MedicationCareAudit
from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication
from support.db import make_engine, make_session_factory
from test_medication_care import change, medication, principal, report


# 함수이름: test_http_contract_validation_and_scope
# 함수역할: 약 라우터 접두사 아래 경로와 UUID·시각·권한·범위 오류를 검증한다.
# 매개변수: fk_db: 격리 DB. 반환값: 없음.
def test_http_contract_validation_and_scope(fk_db: Session) -> None:
    med = medication(fk_db)
    identifier = med.id
    app = FastAPI()
    app.include_router(router, prefix="/api/v1/medication")

    # 함수이름: db_dependency
    # 함수역할: HTTP 테스트에 외부 DB 대신 격리 세션을 주입한다.
    # 매개변수: 없음. 반환값: 테스트 세션.
    def db_dependency() -> Iterator[Session]:
        yield fk_db

    app.dependency_overrides[get_db] = db_dependency
    app.dependency_overrides[dependencies.get_authenticated_principal] = principal
    app.dependency_overrides[dependencies.get_registered_principal] = principal
    app.dependency_overrides[dependencies.verify_app_check_token] = lambda: None
    base = "/api/v1/medication/care"
    today = application_today().isoformat()
    path = f"{base}/history/{identifier}/{today}/morning"
    with TestClient(app) as client:
        result = client.put(path, json=report().model_dump(mode="json"))
        assert result.status_code == 200 and result.json()["revision"] == 1
        history = client.get(f"{base}/history", params={"start_date": today, "end_date": today})
        assert history.status_code == 200 and history.json()["items"][0]["status"] == "taken"
        assert client.put(path, json=report().model_dump(mode="json")).status_code == 409
        assert client.put(path, json={"status": "taken", "operation_id": str(uuid4())}).status_code == 422
        assert client.put(path, json={"status": "skipped", "operation_id": "not-a-uuid"}).status_code == 422
        assert client.put(path, json={**report().model_dump(mode="json"), "patient_hash": "another-patient"}).status_code == 403
        assert client.post(f"{base}/medications/{identifier}/change", json=change(action="stop", changes={}).model_dump(mode="json", exclude_none=True)).status_code == 200


# 함수이름: test_concurrent_regimen_changes_have_one_winner
# 함수역할: 서로 다른 연결에서 같은 조회 버전을 수정하면 한 요청만 성공하는지 확인한다.
# 매개변수: tmp_path: 임시 DB 위치. 반환값: 없음.
def test_concurrent_regimen_changes_have_one_winner(tmp_path: Path) -> None:
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    try:
        with factory() as seed:
            med_id = medication(seed).id
        barrier = Barrier(2)

        # 함수이름: write
        # 함수역할: 두 세션이 같은 시점에 동일 버전의 약을 수정하도록 한다.
        # 매개변수: index: 입력 구분. 반환값: 성공/충돌 코드.
        def write(index: int) -> int:
            with factory() as db:
                barrier.wait(timeout=10)
                try:
                    ManageMedicationCare(db).change_medication(principal(), med_id, change(changes={"dosage_per_time": f"{index + 1} tablets"}))
                    return 200
                except HTTPException as exc:
                    return exc.status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(write, [0, 1]))
        assert sorted(outcomes) == [200, 409]
        with factory() as db:
            assert db.query(_SavedMedication).count() == 2
            assert db.query(_MedicationCareAudit).count() == 1
    finally:
        engine.dispose()


# 함수이름: test_concurrent_dose_changes_have_one_winner
# 함수역할: 같은 시간대의 최초 보고가 겹쳐도 한 행과 한 감사 버전만 생성되는지 확인한다.
# 매개변수: tmp_path: 임시 DB 위치. 반환값: 없음.
def test_concurrent_dose_changes_have_one_winner(tmp_path: Path) -> None:
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    try:
        with factory() as seed:
            med_id = medication(seed).id
        barrier = Barrier(2)

        # 함수이름: write
        # 함수역할: 같은 조회 버전으로 복용/미복용 보고를 동시에 보낸다.
        # 매개변수: status: 요청 상태. 반환값: 성공/충돌 코드.
        def write(status: str) -> int:
            with factory() as db:
                barrier.wait(timeout=10)
                try:
                    ManageMedicationCare(db).update_history(principal(), med_id, application_today(), "morning", report(status=status))
                    return 200
                except HTTPException as exc:
                    return exc.status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(write, ["taken", "skipped"]))
        assert sorted(outcomes) == [200, 409]
        with factory() as db:
            row = db.query(_MedicationCompletion).one()
            assert row.revision == 1
            assert db.query(_MedicationCareAudit).count() == 1
    finally:
        engine.dispose()


# 함수이름: test_care_migration_preserves_prior_completion_and_round_trips
# 함수역할: 실제 이전 리비전 DB의 약·완료 데이터를 보존하며 새 스키마를 왕복한다.
# 매개변수: tmp_path: 임시 DB 위치. 반환값: 없음.
def test_care_migration_preserves_prior_completion_and_round_trips(tmp_path: Path) -> None:
    url = f"sqlite:///{(tmp_path / 'care-upgrade.db').as_posix()}"
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.attributes["database_url"] = url
    command.upgrade(config, "ab29d71c4e60")
    engine = create_engine(url)
    try:
        meta = MetaData()
        users = Table("user_accounts", meta, autoload_with=engine)
        medications = Table("saved_medications", meta, autoload_with=engine)
        completions = Table("medication_completions", meta, autoload_with=engine)
        now = datetime(2026, 10, 17, 8)
        with engine.begin() as connection:
            connection.execute(users.insert().values(user_hash="patient-a", created_at=now, updated_at=now))
            connection.execute(medications.insert().values(id=1, patient_hash="patient-a", item_name="preserved", created_date=now.date(), deduplication_key="original-dedup-key"))
            connection.execute(completions.insert().values(saved_medication_id=1, patient_hash="patient-a", schedule_date=now.date(), slot_key="morning", completed=True, completed_at=now))
        command.upgrade(config, "head")
        current = Table("medication_completions", MetaData(), autoload_with=engine)
        with engine.connect() as connection:
            row = connection.execute(select(current)).mappings().one()
            assert row["completed"] and row["completed_at"] == now
            assert row["actual_taken_at"] is None and row["revision"] == 0
        command.downgrade(config, "ab29d71c4e60")
        command.upgrade(config, "head")
        with engine.connect() as connection:
            assert connection.execute(select(medications.c.deduplication_key)).scalar_one() == "original-dedup-key"
            assert connection.execute(select(completions.c.completed_at)).scalar_one() == now
    finally:
        engine.dispose()
