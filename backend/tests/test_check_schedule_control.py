# File Name: test_check_schedule_control.py
# Role: Regression coverage for patient-scoped schedules, dose completion, transactional outbox
#   events, and legacy schema compatibility.

import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from threading import Barrier, Lock, Thread

from fastapi import HTTPException
from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_schedule_control import CheckSchedule  # noqa: E402
from core.application_clock import application_today  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    MedicationCompletion,
    _MedicationCompletion,
    ensure_medication_completion_schema,
)
from entities.caregiver_alert_outbox_entity import (  # noqa: E402
    CAREGIVER_ALERT_STATUS_PENDING,
    _CaregiverAlertOutbox,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH  # noqa: E402
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    ensure_saved_medication_schema,
)


# 클래스명: _CompletionEventRecorder
# 역할: 복약 완료 알림의 환자와 시간대를 기록하는 테스트용 이벤트 경계다.
# 주요 책임:
# - 완료된 환자 해시와 시간대 키를 한 이벤트로 기록한다.
# 속성:
# - events (list[dict[str, str]]): 복약 완료 알림으로 기록한 환자·시간대 쌍.
class _CompletionEventRecorder:
    # 함수이름: __init__
    # 함수역할:
    # - 복약 완료 알림 이력을 빈 목록으로 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.events: list[dict[str, str]] = []

    # 함수이름: notifySlotCompleted
    # 함수역할:
    # - 완료된 환자 해시와 시간대 키를 한 이벤트로 기록한다.
    # 매개변수:
    # - patient_hash (str): 약 또는 연동 데이터 범위를 식별할 환자 소유자 해시.
    # - slot_key (str): 복약 시간대 키 또는 약 전체 상태 변경을 뜻하는 None.
    # 반환값:
    # - 없음 (None).
    def notifySlotCompleted(
        self,
        *,
        patient_hash: str,
        slot_key: str,
    ) -> None:
        self.events.append(
            {
                "patient_hash": patient_hash,
                "slot_key": slot_key,
            }
        )


# Class Name: CheckScheduleTest
# Role: Database-backed schedule tests covering treatment windows, dose transitions, and
#   completion-event atomicity.
# Responsibilities:
# - Persists and refreshes a medication with configurable course dates, dose slots, and legacy
#   completion state.
# - Requires UML-named completion attributes to map correctly to the persisted medication,
#   patient, date, slot, and completion fields.
# - Adds required completion fields, deduplicates legacy rows with default ownership and slot
#   values, and rejects a duplicate completion key.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - control (CheckSchedule): Use-case control under test, isolated from production state.
class CheckScheduleTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated medication/completion database and schedule control using the
    #   current schemas.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_saved_medication_schema(self.engine)
        ensure_medication_completion_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = CheckSchedule(self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the schedule session and disposes its database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: _saved_medication
    # Description:
    # - Persists and refreshes a medication with configurable course dates, dose slots, and
    #   legacy completion state.
    # Parameters:
    # - patient_hash (str): Patient owner identifying the medication or linked-data scope.
    # - item_name (str): Product name in the authoritative or saved medication record.
    # - created_date (date | None): Original saved-medication date; None uses today's date.
    # - prescription_date (date | None): Course start/prescription date; None uses the
    #   fixture's default.
    # - total_days (str | None): Prescribed course-duration label, possibly unknown.
    # - daily_frequency (str | None): Prescription dose-frequency label.
    # - schedule_slot_keys (str): Confirmed dose slots, encoded as JSON when the storage
    #   helper expects text.
    # - medication_status (bool): Requested complete or incomplete state.
    # - medication_status_date (date | None): Date associated with the legacy completion
    #   flag.
    # Returns:
    # - _SavedMedication: Persisted and refreshed medication row, including its generated
    #   ID.
    def _saved_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "test-tablet",
        created_date: date | None = None,
        prescription_date: date | None = None,
        total_days: str | None = "7 days",
        daily_frequency: str | None = "3 times",
        schedule_slot_keys: str = "[]",
        medication_status: bool = False,
        medication_status_date: date | None = None,
    ) -> _SavedMedication:
        medication = _SavedMedication(
            patient_hash=patient_hash,
            created_date=created_date or application_today(),
            prescription_date=prescription_date,
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            dosage_per_time="1 tablet",
            daily_frequency=daily_frequency,
            total_days=total_days,
            schedule_slot_keys=schedule_slot_keys,
            medication_status=medication_status,
            medication_status_date=medication_status_date,
            ai_guide="guide",
            image_url="https://nedrug.mfds.go.kr/medicine.jpg",
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication

    # Function Name: test_today_schedule_is_scoped_and_filters_expired_medications
    # Description:
    # - Returns only the requested patient's active medication, using prescription dates for
    #   eligibility while retaining original save dates and images.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_today_schedule_is_scoped_and_filters_expired_medications(self) -> None:
        today = application_today()
        old_saved_date = today - timedelta(days=20)
        active_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="active-tablet",
            created_date=old_saved_date,
            prescription_date=today,
        )
        self._saved_medication(
            patient_hash="patient-a",
            item_name="expired-tablet",
            created_date=today,
            prescription_date=today - timedelta(days=8),
            total_days="7 days",
        )
        self._saved_medication(
            patient_hash="patient-b",
            item_name="other-patient-tablet",
            created_date=today,
        )

        response = self.control.requestTodayMedicationSchedule("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 1)
        schedule = response["data"][0]
        self.assertEqual(schedule["medication_id"], str(active_medication.id))
        self.assertEqual(schedule["drug_name"], "active-tablet")
        self.assertEqual(schedule["patient_hash"], "patient-a")
        self.assertFalse(schedule["medication_status"])
        self.assertEqual(
            schedule["image_url"],
            "https://nedrug.mfds.go.kr/medicine.jpg",
        )
        self.assertEqual(schedule["created_date"], old_saved_date.isoformat())
        self.assertEqual(schedule["prescription_date"], today.isoformat())

    # Function Name: test_schedule_window_includes_future_starting_course
    # Description:
    # - Includes a future-starting course within the fourteen-day window and returns its
    #   exact start and end bounds.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_schedule_window_includes_future_starting_course(self) -> None:
        today = application_today()
        future_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="future-tablet",
            prescription_date=today + timedelta(days=5),
            total_days="3 days",
        )
        self._saved_medication(
            patient_hash="patient-a",
            item_name="outside-window-tablet",
            prescription_date=today + timedelta(days=15),
            total_days="3 days",
        )
        self._saved_medication(
            patient_hash="patient-b",
            item_name="other-patient-tablet",
            prescription_date=today + timedelta(days=2),
        )

        response = self.control.requestMedicationScheduleWindow(
            "patient-a",
            days=14,
        )

        self.assertTrue(response["success"])
        self.assertEqual(response["window_start"], today.isoformat())
        self.assertEqual(
            response["window_end"],
            (today + timedelta(days=13)).isoformat(),
        )
        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(
            response["data"][0]["medication_id"],
            str(future_medication.id),
        )

    # Function Name: test_status_update_is_scoped_by_patient_hash
    # Description:
    # - Rejects cross-patient completion updates with 404 and persists today's completed
    #   status for the owner.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_status_update_is_scoped_by_patient_hash(self) -> None:
        medication = self._saved_medication(patient_hash="patient-b")

        with self.assertRaises(HTTPException) as context:
            self.control.updateMedicationStatus(
                medication.id,
                True,
                "patient-a",
            )
        self.assertEqual(context.exception.status_code, 404)

        response = self.control.updateMedicationStatus(
            medication.id,
            True,
            "patient-b",
        )

        self.assertTrue(response["success"])
        self.assertTrue(response["data"]["medication_status"])
        self.db.refresh(medication)
        self.assertTrue(medication.medication_status)
        self.assertEqual(medication.medication_status_date, application_today())

    # Function Name: test_slot_status_update_only_marks_requested_dose
    # Description:
    # - Completes only the requested morning dose, leaving the overall medication incomplete
    #   and other slots untouched.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_slot_status_update_only_marks_requested_dose(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")

        response = self.control.updateMedicationStatus(
            medication.id,
            True,
            "patient-a",
            slot_key="morning",
        )

        self.assertTrue(response["success"])
        self.assertFalse(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": False, "evening": False},
        )
        self.assertEqual(response["data"]["completed_slot_keys"], ["morning"])
        self.db.refresh(medication)
        self.assertFalse(medication.medication_status)

        completions = (
            self.db.query(_MedicationCompletion)
            .filter(_MedicationCompletion.saved_medication_id == medication.id)
            .all()
        )
        self.assertEqual(len(completions), 1)
        self.assertEqual(completions[0].slot_key, "morning")
        self.assertTrue(completions[0].completed)

    # Function Name: test_whole_slot_update_is_atomic_scoped_and_reversible
    # Description:
    # - Completes and reverses every medication in one patient's slot atomically, emits one
    #   outbox event, and leaves another patient's rows untouched.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_stale_notification_cannot_complete_today(self) -> None:
        """Reject a mismatched reminder day before writing completion or outbox rows."""
        self._saved_medication(patient_hash="patient-a", item_name="tablet")
        for delta in (-1, 1):
            with self.assertRaises(HTTPException) as raised:
                self.control.updateMedicationSlotStatus(
                    "morning", True, "patient-a",
                    expected_schedule_date=application_today() + timedelta(days=delta),
                )
            self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)
        self.assertEqual(self.db.query(_CaregiverAlertOutbox).count(), 0)

    def test_whole_slot_update_is_atomic_scoped_and_reversible(self) -> None:
        first_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="first-tablet",
        )
        second_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="second-tablet",
            daily_frequency="1 time",
            schedule_slot_keys='["morning"]',
        )
        other_patient_medication = self._saved_medication(
            patient_hash="patient-b",
            item_name="other-patient-tablet",
        )
        event_recorder = _CompletionEventRecorder()
        control = CheckSchedule(
            self.db,
            completion_event_boundary=event_recorder,
        )

        completed_response = control.updateMedicationSlotStatus(
            "morning",
            True,
            "patient-a",
            expected_schedule_date=application_today(),
        )

        self.assertTrue(completed_response["success"])
        self.assertEqual(
            {schedule["medication_id"] for schedule in completed_response["data"]},
            {str(first_medication.id), str(second_medication.id)},
        )
        self.assertTrue(
            all(
                schedule["slot_statuses"]["morning"]
                for schedule in completed_response["data"]
            )
        )
        self.assertEqual(
            event_recorder.events,
            [{"patient_hash": "patient-a", "slot_key": "morning"}],
        )
        completion_events = control.consumeCompletionEvents()
        self.assertEqual(len(completion_events), 1)
        self.assertIsInstance(completion_events[0]["outbox_id"], int)

        unchecked_response = control.updateMedicationSlotStatus(
            "morning",
            False,
            "patient-a",
        )

        self.assertTrue(
            all(
                not schedule["slot_statuses"]["morning"]
                for schedule in unchecked_response["data"]
            )
        )
        self.assertEqual(control.consumeCompletionEvents(), [])
        self.db.refresh(other_patient_medication)
        self.assertFalse(other_patient_medication.medication_status)
        other_patient_completions = (
            self.db.query(_MedicationCompletion)
            .filter(
                _MedicationCompletion.saved_medication_id
                == other_patient_medication.id
            )
            .all()
        )
        self.assertEqual(other_patient_completions, [])

    # Function Name: test_whole_slot_update_rejects_invalid_or_empty_slot
    # Description:
    # - Rejects an unknown whole-slot key with 400 and a valid but empty slot with 404.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_whole_slot_update_rejects_invalid_or_empty_slot(self) -> None:
        self._saved_medication(
            patient_hash="patient-a",
            daily_frequency="1 time",
            schedule_slot_keys='["morning"]',
        )

        with self.assertRaises(HTTPException) as invalid_context:
            self.control.updateMedicationSlotStatus(
                "after-midnight",
                True,
                "patient-a",
            )
        self.assertEqual(invalid_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as empty_context:
            self.control.updateMedicationSlotStatus(
                "bedtime",
                True,
                "patient-a",
            )
        self.assertEqual(empty_context.exception.status_code, 404)

    # 함수이름: test_completion_event_is_emitted_only_when_slot_becomes_fully_completed
    # 함수역할:
    # - 시간대의 마지막 약이 완료될 때만 대기 상태 outbox 이벤트를 한 번 만들고 부분 완료·반복 완료에는 알림을 만들지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_completion_event_is_emitted_only_when_slot_becomes_fully_completed(
        self,
    ) -> None:
        first_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="first-tablet",
        )
        second_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="second-tablet",
        )
        event_recorder = _CompletionEventRecorder()
        control = CheckSchedule(
            self.db,
            completion_event_boundary=event_recorder,
        )

        control.updateMedicationStatus(
            first_medication.id,
            True,
            "patient-a",
            slot_key="morning",
        )
        self.assertEqual(event_recorder.events, [])

        control.updateMedicationStatus(
            second_medication.id,
            True,
            "patient-a",
            slot_key="morning",
        )
        completion_events = control.consumeCompletionEvents()
        self.assertEqual(len(completion_events), 1)
        self.assertEqual(completion_events[0]["patient_hash"], "patient-a")
        self.assertEqual(completion_events[0]["slot_key"], "morning")
        self.assertIsInstance(completion_events[0]["outbox_id"], int)
        outbox_row = self.db.get(
            _CaregiverAlertOutbox,
            int(completion_events[0]["outbox_id"]),
        )
        self.assertIsNotNone(outbox_row)
        self.assertEqual(outbox_row.status, CAREGIVER_ALERT_STATUS_PENDING)
        control.updateMedicationStatus(
            second_medication.id,
            True,
            "patient-a",
            slot_key="morning",
        )

        self.assertEqual(
            event_recorder.events,
            [
                {
                    "patient_hash": "patient-a",
                    "slot_key": "morning",
                }
            ],
        )
        self.assertEqual(control.consumeCompletionEvents(), [])

    # Function Name: test_two_sessions_reuse_one_completion_outbox_event
    # Description:
    # - Requires concurrent sessions creating the same completion event to finish without
    #   errors and return one shared outbox row ID.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_two_sessions_reuse_one_completion_outbox_event(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            database_path = Path(temporary_directory) / "outbox-concurrency.db"
            engine = create_engine(
                f"sqlite:///{database_path.as_posix()}",
                connect_args={"check_same_thread": False, "timeout": 10},
            )

            # Function Name: enable_concurrent_writes
            # Description:
            # - Enables SQLite WAL and a ten-second busy timeout so competing test
            #   sessions can serialize writes.
            # Parameters:
            # - dbapi_connection (sqlite3.Connection): SQLite driver connection
            #   configured for concurrent writes.
            # - _record (ConnectionRecord): SQLAlchemy connection-pool record;
            #   unused by the SQLite setup hook.
            # Returns:
            # - None.
            @event.listens_for(engine, "connect")
            def enable_concurrent_writes(dbapi_connection, _record) -> None:
                cursor = dbapi_connection.cursor()
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.execute("PRAGMA busy_timeout=10000")
                cursor.close()

            Base.metadata.create_all(bind=engine)
            session_factory = sessionmaker(
                autocommit=False,
                autoflush=False,
                bind=engine,
            )
            start_barrier = Barrier(2)
            result_lock = Lock()
            outbox_ids: list[int] = []
            errors: list[Exception] = []

            # 두 요청이 같은 이벤트를 동시에 만들더라도 DB 고유 키가 한 행만 남긴다.
            # 함수이름: insert_same_event
            # 함수역할:
            # - 두 작업을 동시에 시작하여 같은 고유 이벤트 키로 생성·조회한 행 ID를 기록하고 실패 시 롤백 후 오류를 수집한다.
            # 매개변수:
            # - 없음.
            # 반환값:
            # - 없음 (None).
            def insert_same_event() -> None:
                session = session_factory()
                try:
                    start_barrier.wait(timeout=5)
                    row = CheckSchedule(session)._get_or_create_completion_outbox(
                        event_key="a" * 64,
                        patient_hash="patient-a",
                        slot_key="morning",
                    )
                    session.commit()
                    with result_lock:
                        outbox_ids.append(int(row.id))
                except Exception as exc:  # pragma: no cover - assertion reports details
                    session.rollback()
                    with result_lock:
                        errors.append(exc)
                finally:
                    session.close()

            workers = [Thread(target=insert_same_event) for _ in range(2)]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(timeout=15)

            verification_session = session_factory()
            try:
                rows = verification_session.query(_CaregiverAlertOutbox).all()
                self.assertFalse(any(worker.is_alive() for worker in workers))
                self.assertEqual(errors, [])
                self.assertEqual(len(rows), 1)
                self.assertEqual(outbox_ids, [int(rows[0].id), int(rows[0].id)])
            finally:
                verification_session.close()
                engine.dispose()

    # Function Name: test_completion_transition_is_computed_before_transaction_commit
    # Description:
    # - Requires both before/after slot-state reads to occur before transaction commit.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_completion_transition_is_computed_before_transaction_commit(
        self,
    ) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="serialized-tablet",
        )
        commit_completed = False
        completion_state_reads: list[bool] = []
        original_reader = self.control._slot_completion_states_for_patient

        # Function Name: mark_commit
        # Description:
        # - Marks the transaction as committed for the ordering assertions in the
        #   surrounding test.
        # Parameters:
        # - _session (object): Session passed to the after-commit listener; the callback
        #   records only timing.
        # Returns:
        # - None.
        def mark_commit(_session: object) -> None:
            nonlocal commit_completed
            commit_completed = True

        # Function Name: tracked_reader
        # Description:
        # - Records whether commit has occurred before delegating to the original
        #   slot-state reader.
        # Parameters:
        # - patient_hash (str): Patient owner identifying the medication or linked-data
        #   scope.
        # - schedule_date (date): Calendar day whose dose-completion states are queried.
        # - slot_keys (list[str]): Medication slots included in the completion-state
        #   lookup.
        # Returns:
        # - dict[str, bool]: Original per-slot completion states, unchanged by
        #   instrumentation.
        def tracked_reader(
            patient_hash: str,
            schedule_date: date,
            slot_keys: list[str],
        ) -> dict[str, bool]:
            completion_state_reads.append(commit_completed)
            return original_reader(patient_hash, schedule_date, slot_keys)

        event.listen(self.db, "after_commit", mark_commit)
        self.control._slot_completion_states_for_patient = tracked_reader
        try:
            self.control.updateMedicationStatus(
                medication.id,
                True,
                "patient-a",
                slot_key="morning",
            )
        finally:
            event.remove(self.db, "after_commit", mark_commit)
            self.control._slot_completion_states_for_patient = original_reader

        self.assertEqual(completion_state_reads, [False, False])

    # Function Name: test_medication_completion_preserves_uml_entity_names
    # Description:
    # - Requires UML-named completion attributes to map correctly to the persisted
    #   medication, patient, date, slot, and completion fields.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_medication_completion_preserves_uml_entity_names(self) -> None:
        schedule_date = application_today()
        completed_at = datetime(2026, 1, 1, 8, 0)
        completion = MedicationCompletion(
            patient_hash="patient-a",
            medicine_name="test-tablet",
            time_slot="morning",
            completed_at=completed_at,
            completed=True,
        )

        row = completion.insertMedicationCompletion(
            saved_medication_id=7,
            schedule_date=schedule_date,
        )

        self.assertEqual(completion.patientHash, "patient-a")
        self.assertEqual(completion.medicineName, "test-tablet")
        self.assertEqual(completion.timeSlot, "morning")
        self.assertEqual(completion.completedAt, completed_at)
        self.assertEqual(row.saved_medication_id, 7)
        self.assertEqual(row.patient_hash, "patient-a")
        self.assertEqual(row.schedule_date, schedule_date)
        self.assertEqual(row.slot_key, "morning")
        self.assertTrue(row.completed)

    # Function Name: test_all_slots_complete_sets_legacy_row_status
    # Description:
    # - Sets the legacy overall completion flag only after morning, lunch, and evening are
    #   all complete.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_all_slots_complete_sets_legacy_row_status(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")

        for slot_key in ["morning", "lunch", "evening"]:
            response = self.control.updateMedicationStatus(
                medication.id,
                True,
                "patient-a",
                slot_key=slot_key,
            )

        self.assertTrue(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": True, "evening": True},
        )
        self.db.refresh(medication)
        self.assertTrue(medication.medication_status)

    # Function Name: test_unchecking_one_slot_clears_legacy_row_status
    # Description:
    # - Clears overall completion when lunch is unchecked while preserving completed morning
    #   and evening slots.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unchecking_one_slot_clears_legacy_row_status(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")
        self.control.updateMedicationStatus(medication.id, True, "patient-a")

        response = self.control.updateMedicationStatus(
            medication.id,
            False,
            "patient-a",
            slot_key="lunch",
        )

        self.assertFalse(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": False, "evening": True},
        )
        self.db.refresh(medication)
        self.assertFalse(medication.medication_status)

    # Function Name: test_slot_update_preserves_other_legacy_completed_slots
    # Description:
    # - Preserves other completed legacy slots when one slot is unchecked and clears the
    #   legacy overall flag.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_slot_update_preserves_other_legacy_completed_slots(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            medication_status=True,
            medication_status_date=application_today(),
        )

        response = self.control.updateMedicationStatus(
            medication.id,
            False,
            "patient-a",
            slot_key="lunch",
        )

        self.assertFalse(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": False, "evening": True},
        )
        self.db.refresh(medication)
        self.assertFalse(medication.medication_status)

    # Function Name: test_invalid_slot_key_is_rejected
    # Description:
    # - Rejects a slot absent from the medication's configured schedule with HTTP 400.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_slot_key_is_rejected(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")

        with self.assertRaises(HTTPException) as context:
            self.control.updateMedicationStatus(
                medication.id,
                True,
                "patient-a",
                slot_key="bedtime",
            )

        self.assertEqual(context.exception.status_code, 400)

    # Function Name: test_previous_day_completion_does_not_mark_today_complete
    # Description:
    # - Does not carry yesterday's legacy completion flag into today's schedule.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_previous_day_completion_does_not_mark_today_complete(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            medication_status=True,
            medication_status_date=application_today() - timedelta(days=1),
        )

        response = self.control.requestTodayMedicationSchedule("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"][0]["medication_id"], str(medication.id))
        self.assertFalse(response["data"][0]["medication_status"])

    # Function Name: test_today_schedule_batches_completion_lookup
    # Description:
    # - Loads completion states for two medications using one batched SELECT rather than
    #   per-medication queries.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_today_schedule_batches_completion_lookup(self) -> None:
        first_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="first-tablet",
        )
        second_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="second-tablet",
        )
        self.db.add_all(
            [
                _MedicationCompletion(
                    saved_medication_id=first_medication.id,
                    patient_hash="patient-a",
                    schedule_date=application_today(),
                    slot_key="morning",
                    completed=True,
                ),
                _MedicationCompletion(
                    saved_medication_id=second_medication.id,
                    patient_hash="patient-a",
                    schedule_date=application_today(),
                    slot_key="lunch",
                    completed=True,
                ),
            ]
        )
        self.db.commit()
        completion_select_count = 0

        # Function Name: count_completion_select
        # Description:
        # - Counts only SELECT statements against medication_completions to measure
        #   schedule-query batching.
        # Parameters:
        # - _connection (object): SQLAlchemy connection passed to the query listener.
        #   Unused by this double.
        # - _cursor (object): Database cursor supplied to the SQL event listener. Unused
        #   by this double.
        # - statement (str): SQL statement inspected for query shape or count.
        # - _parameters (object): Bound SQL parameters supplied to the event listener.
        #   Unused by this double.
        # - _context (object): SQL execution context supplied to the query listener.
        #   Unused by this double.
        # - _executemany (bool): SQL event flag indicating batch execution. Unused by
        #   this double.
        # Returns:
        # - None.
        def count_completion_select(
            _connection: object,
            _cursor: object,
            statement: str,
            _parameters: object,
            _context: object,
            _executemany: bool,
        ) -> None:
            nonlocal completion_select_count
            normalized_statement = " ".join(statement.lower().split())
            if (
                normalized_statement.startswith("select")
                and "from medication_completions" in normalized_statement
            ):
                completion_select_count += 1

        event.listen(
            self.engine,
            "before_cursor_execute",
            count_completion_select,
        )
        try:
            response = self.control.requestTodayMedicationSchedule("patient-a")
        finally:
            event.remove(
                self.engine,
                "before_cursor_execute",
                count_completion_select,
            )

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 2)
        self.assertEqual(completion_select_count, 1)

    # Function Name: test_empty_patient_hash_falls_back_to_default_hash
    # Description:
    # - Uses the default patient scope when the requested hash contains only whitespace.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_empty_patient_hash_falls_back_to_default_hash(self) -> None:
        medication = self._saved_medication(patient_hash=DEFAULT_PATIENT_HASH)

        response = self.control.requestTodayMedicationSchedule(" ")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"][0]["medication_id"], str(medication.id))

    # Function Name: test_completion_schema_upgrade_hardens_legacy_table
    # Description:
    # - Adds required completion fields, deduplicates legacy rows with default ownership and
    #   slot values, and rejects a duplicate completion key.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_completion_schema_upgrade_hardens_legacy_table(self) -> None:
        legacy_engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        try:
            with legacy_engine.begin() as connection:
                connection.execute(
                    text(
                        "CREATE TABLE medication_completions ("
                        "id INTEGER PRIMARY KEY, "
                        "saved_medication_id INTEGER"
                        ")"
                    )
                )
                connection.execute(
                    text(
                        "INSERT INTO medication_completions "
                        "(id, saved_medication_id) "
                        "VALUES (1, 10), (2, 10)"
                    )
                )

            ensure_medication_completion_schema(legacy_engine)

            existing_columns = {
                column["name"]
                for column in inspect(legacy_engine).get_columns(
                    "medication_completions"
                )
            }
            self.assertIn("patient_hash", existing_columns)
            self.assertIn("schedule_date", existing_columns)
            self.assertIn("slot_key", existing_columns)
            self.assertIn("completed", existing_columns)
            self.assertIn("completed_at", existing_columns)

            with legacy_engine.connect() as connection:
                rows = connection.execute(
                    text(
                        "SELECT saved_medication_id, patient_hash, schedule_date, "
                        "slot_key, completed, completed_at "
                        "FROM medication_completions"
                    )
                ).all()
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0][0], 10)
                self.assertEqual(rows[0][1], DEFAULT_PATIENT_HASH)
                self.assertIsNotNone(rows[0][2])
                self.assertEqual(rows[0][3], "morning")
                self.assertEqual(rows[0][4], 1)
                self.assertIsNotNone(rows[0][5])
                with self.assertRaises(IntegrityError):
                    connection.execute(
                        text(
                            "INSERT INTO medication_completions "
                            "(saved_medication_id, patient_hash, schedule_date, "
                            "slot_key, completed) "
                            "VALUES (10, :patient_hash, :schedule_date, 'morning', 1)"
                        ),
                        {
                            "patient_hash": DEFAULT_PATIENT_HASH,
                            "schedule_date": rows[0][2],
                        },
                    )
        finally:
            legacy_engine.dispose()

if __name__ == "__main__":
    unittest.main()
