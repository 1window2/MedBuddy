# 파일명: test_structured_linked_chat_context.py
# 역할: 구조화 채팅의 서버 복약·약국 스냅샷, 역할별 권한 및 완료 이벤트 멱등성을 검증한다.

"""구조화 채팅 문맥의 권한, 신뢰 경계와 중복 방지를 검증한다."""

import sys
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
from controls.manage_linked_chat_control import ManageLinkedChat  # noqa: E402
from controls.check_schedule_control import CheckSchedule  # noqa: E402
from core.application_clock import application_today  # noqa: E402
from core.database import Base  # noqa: E402
from entities.chat_message_entity import (  # noqa: E402
    CHAT_MESSAGE_KIND_MEDICATION_DISCOMFORT,
    CHAT_MESSAGE_KIND_MEDICATION_SHORTAGE,
    CHAT_MESSAGE_KIND_PHARMACY_SHARE,
    CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST,
    CHAT_MESSAGE_KIND_SLOT_COMPLETION,
    _ChatMessage,
)
from entities.medication_completion_entity import _MedicationCompletion  # noqa: E402
from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox  # noqa: E402
from entities.pharmacy_catalog_entity import PharmacyCatalogRecord  # noqa: E402
from entities.saved_medication_entity import _SavedMedication  # noqa: E402


# 클래스명: StructuredLinkedChatContextTest
# 역할: 연동 환자의 실제 일정·약·약국 정보만 구조화 채팅으로 노출되는지 검증하는 테스트 모음이다.
# 주요 책임:
# - 양측에 같은 아침 완료 건수를 제공하지만 복약 확인 요청 권한은 보호자에게만 허용하는지 검증한다.
# - 약 부족 메시지에 실제 남은 7일과 종료일을 붙이고 불편 메시지에는 안전 안내 표시를 포함하는지 검증한다.
# - 현재부터 7일간 하루 세 번 복용하는 환자 약을 저장하고 갱신된 행을 반환한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
# - link_id (int): 시험용 환자와 보호자가 공유하는 활성 연동 ID.
# - medication (_SavedMedication): 현재 테스트 조건에서 공유할 저장된 활성 약.
# - chat (ManageLinkedChat): 격리 테스트 세션에 연결한 채팅 control.
class StructuredLinkedChatContextTest(unittest.TestCase):
    """구조화 채팅이 연동 환자의 실제 데이터만 노출하는지 확인한다."""

    # 함수이름: setUp
    # 함수역할:
    # - 격리 DB에 환자·보호자 연동과 현재 약을 저장하고 구조화 채팅 control을 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        link_control = LinkPatientCaregiver(self.db)
        code_response = link_control.generatePatientHash("patient-a")
        link_response = link_control.requestPatientCaregiverLink(
            "caregiver-a",
            code_response["data"]["patient_code"],
        )
        self.link_id = int(link_response["data"]["id"])
        self.medication = self._save_medication()
        self.chat = ManageLinkedChat(self.db)

    # 함수이름: tearDown
    # 함수역할:
    # - 구조화 채팅 테스트의 DB 세션과 엔진을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # 함수이름: test_schedule_context_exposes_progress_and_caregiver_action_only
    # 함수역할:
    # - 양측에 같은 아침 완료 건수를 제공하지만 복약 확인 요청 권한은 보호자에게만 허용하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_schedule_context_exposes_progress_and_caregiver_action_only(self) -> None:
        """같은 일정에서 완료 수는 같고 확인 요청 권한만 보호자에게 주는지 본다."""
        self.db.add(
            _MedicationCompletion(
                saved_medication_id=int(self.medication.id),
                patient_hash="patient-a",
                schedule_date=application_today(),
                slot_key="morning",
                completed=True,
            )
        )
        self.db.commit()

        patient = self.chat.request_schedule_contexts(
            link_id=self.link_id,
            user_hash="patient-a",
        )
        caregiver = self.chat.request_schedule_contexts(
            link_id=self.link_id,
            user_hash="caregiver-a",
        )

        patient_morning = patient["data"][0]
        caregiver_morning = caregiver["data"][0]
        self.assertEqual(patient_morning["slot_key"], "morning")
        self.assertEqual(patient_morning["completed_count"], 1)
        self.assertEqual(patient_morning["total_count"], 1)
        self.assertFalse(patient_morning["can_request_check"])
        self.assertTrue(caregiver_morning["can_request_check"])

    # 함수이름: test_only_caregiver_can_send_slot_check_request
    # 함수역할:
    # - 보호자의 시간대 확인 메시지에 서버 일정 스냅샷을 붙이고 환자의 동일 요청은 403으로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_only_caregiver_can_send_slot_check_request(self) -> None:
        """시간대 확인 요청은 보호자만 보내고 서버 일정 스냅샷을 쓰는지 본다."""
        sent = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="caregiver-a",
            client_message_id="slot-check-001",
            body="아침 약을 확인해주세요.",
            message_kind=CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST,
            slot_key="morning",
        )

        context = sent.message.to_response_dict()["context"]
        self.assertEqual(sent.message.message_kind, CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST)
        self.assertEqual(context["schedule_context"]["slot_key"], "morning")
        self.assertEqual(context["schedule_context"]["total_count"], 1)
        with self.assertRaises(HTTPException) as patient_request:
            self.chat.send_message(
                link_id=self.link_id,
                sender_hash="patient-a",
                client_message_id="slot-check-002",
                body="잘못된 요청",
                message_kind=CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST,
                slot_key="morning",
            )
        self.assertEqual(patient_request.exception.status_code, 403)

    # 함수이름: test_slot_completion_is_server_only_and_idempotent
    # 함수역할:
    # - 클라이언트의 완료 메시지 위조를 403으로 거절하고 서버 완료 사건은 재시도해도 한 건만 저장하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_slot_completion_is_server_only_and_idempotent(self) -> None:
        """완료 메시지는 클라이언트가 위조할 수 없고 사건별 한 번만 저장되는지 본다."""
        with self.assertRaises(HTTPException) as client_request:
            self.chat.send_message(
                link_id=self.link_id,
                sender_hash="patient-a",
                client_message_id="forged-slot-completion",
                body="완료",
                message_kind=CHAT_MESSAGE_KIND_SLOT_COMPLETION,
                slot_key="morning",
            )
        self.assertEqual(client_request.exception.status_code, 403)

        first_count = self.chat.publish_slot_completion(
            patient_hash="patient-a",
            slot_key="morning",
        )
        retried_count = self.chat.publish_slot_completion(
            patient_hash="patient-a",
            slot_key="morning",
        )

        self.assertEqual(first_count, 1)
        self.assertEqual(retried_count, 0)
        self.assertEqual(
            self.db.query(_ChatMessage)
            .filter(_ChatMessage.message_kind == CHAT_MESSAGE_KIND_SLOT_COMPLETION)
            .count(),
            1,
        )

    # 함수이름: test_medication_quick_replies_use_server_course_information
    # 함수역할:
    # - 약 부족 메시지에 실제 남은 7일과 종료일을 붙이고 불편 메시지에는 안전 안내 표시를 포함하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_medication_quick_replies_use_server_course_information(self) -> None:
        """약 부족·불편 메시지에 실제 복용 기간과 안전 안내 표시를 붙이는지 본다."""
        shortage = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="patient-a",
            client_message_id="shortage-001",
            body="약이 부족해요.",
            medication_id=int(self.medication.id),
            message_kind=CHAT_MESSAGE_KIND_MEDICATION_SHORTAGE,
        )
        discomfort = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="patient-a",
            client_message_id="discomfort-001",
            body="먹고 나서 불편해요.",
            medication_id=int(self.medication.id),
            message_kind=CHAT_MESSAGE_KIND_MEDICATION_DISCOMFORT,
        )

        shortage_context = shortage.message.to_response_dict()["context"]
        discomfort_context = discomfort.message.to_response_dict()["context"]
        self.assertEqual(shortage_context["remaining_days"], 7)
        self.assertEqual(
            shortage_context["course_end_date"],
            (application_today() + timedelta(days=6)).isoformat(),
        )
        self.assertTrue(discomfort_context["show_safety_guidance"])

    # 함수이름: test_pharmacy_share_uses_catalog_snapshot
    # 함수역할:
    # - 약국 공유가 클라이언트 주장 대신 서버 카탈로그의 약국명·전화·당일 운영시간을 사용하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_pharmacy_share_uses_catalog_snapshot(self) -> None:
        """약국 공유 메시지가 요청 본문이 아닌 서버 카탈로그를 기준으로 생성되는지 본다."""
        self.db.add(
            PharmacyCatalogRecord(
                pharmacy_id="pharmacy-001",
                name="메드버디약국",
                address="서울특별시 마포구",
                telephone="02-1234-5678",
                latitude=37.55,
                longitude=126.92,
                weekly_hours={
                    str(application_today().isoweekday()): ["0900", "2100"]
                },
                source_updated_at=datetime(2026, 8, 24, 1, 2, 3),
            )
        )
        self.db.commit()

        sent = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="caregiver-a",
            client_message_id="pharmacy-share-001",
            body="이 약국을 확인해보세요.",
            message_kind=CHAT_MESSAGE_KIND_PHARMACY_SHARE,
            pharmacy_id="pharmacy-001",
        )

        pharmacy = sent.message.to_response_dict()["context"]["pharmacy_context"]
        self.assertEqual(pharmacy["name"], "메드버디약국")
        self.assertEqual(pharmacy["today_hours"], "09:00 - 21:00")
        self.assertEqual(pharmacy["telephone"], "02-1234-5678")

    # 함수이름: _record_taken
    # 함수역할: 선택한 아침 약의 명시적 복용 확인 요청을 만들고 사례별 입력을 적용한다.
    # 매개변수: overrides: 기본 요청에서 바꿀 필드. 반환값: 복용 확인 처리 결과.
    def _record_taken(self, **overrides):
        """Create an explicit confirmation without changing the normal chat API."""
        arguments = dict(
            link_id=self.link_id, sender_hash="patient-a",
            client_message_id="taken-request-001", schedule_date=application_today(),
            slot_key="morning", medication_ids=[int(self.medication.id)],
        )
        arguments.update(overrides)
        return self.chat.record_medication_taken(**arguments)

    # 함수이름: test_chat_confirmation_updates_only_selected_dose_and_returns_progress
    # 함수역할: 선택 약만 완료되고 미선택 약을 포함한 전체 진행률이 정확히 반환되는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_chat_confirmation_updates_only_selected_dose_and_returns_progress(self):
        other = self._save_medication()
        result, events = self._record_taken()
        self.assertTrue(result.created)
        context = result.message.context_payload
        self.assertEqual(context["schedule_context"]["completed_count"], 1)
        self.assertEqual(context["schedule_context"]["total_count"], 2)
        self.assertEqual(context["completion_confirmation"]["medication_ids"], [self.medication.id])
        self.assertEqual(events, [])
        rows = self.db.query(_MedicationCompletion).all()
        self.assertEqual([(row.saved_medication_id, row.slot_key, row.completed) for row in rows],
                         [(self.medication.id, "morning", True)])
        self.assertNotEqual(other.id, self.medication.id)

    # 함수이름: test_full_confirmation_reuses_outbox_without_duplicate_chat
    # 함수역할: 시간대 전체 완료 시 알림은 생성하되 알림 발행 과정에서 확인 채팅이 중복되지 않는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_full_confirmation_reuses_outbox_without_duplicate_chat(self):
        result, events = self._record_taken()
        self.assertEqual(len(events), 1)
        self.assertEqual(self.db.query(_CaregiverAlertOutbox).count(), 1)
        self.assertEqual(result.message.message_kind, CHAT_MESSAGE_KIND_SLOT_COMPLETION)
        self.assertEqual(self.chat.publish_slot_completion(patient_hash="patient-a", slot_key="morning"), 0)
        self.assertEqual(self.db.query(_ChatMessage).count(), 1)

    # 함수이름: test_retry_does_not_reapply_a_later_undo
    # 함수역할: 복용 취소 뒤 채팅 확인을 재전송해도 기존 메시지를 반환하고 취소 상태를 유지하는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_retry_does_not_reapply_a_later_undo(self):
        first, _ = self._record_taken()
        CheckSchedule(self.db).updateMedicationSlotStatus("morning", False, "patient-a")
        second, events = self._record_taken()
        self.assertFalse(second.created)
        self.assertEqual(first.message.message_id, second.message.message_id)
        self.assertEqual(events, [])
        self.assertFalse(self.db.query(_MedicationCompletion).one().completed)

    # 함수이름: test_confirmation_rejects_changed_idempotency_payload
    # 함수역할: 같은 요청 식별자로 다른 시간대의 복용 확인을 보내면 409로 거부하는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_confirmation_rejects_changed_idempotency_payload(self):
        self._record_taken()
        with self.assertRaises(HTTPException) as error:
            self._record_taken(slot_key="evening")
        self.assertEqual(error.exception.status_code, 409)

    # 함수이름: test_confirmation_rejects_caregiver_stale_date_and_invalid_selection
    # 함수역할: 보호자·무효 연동·지난 날짜·미래 날짜·잘못된 약 선택을 거부하고 기록과 채팅을 남기지 않는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_confirmation_rejects_caregiver_stale_date_and_invalid_selection(self):
        for overrides, expected in [
            ({"sender_hash": "caregiver-a"}, 403),
            ({"sender_hash": "unlinked-user"}, 404),
            ({"schedule_date": application_today() - timedelta(days=1)}, 409),
            ({"schedule_date": application_today() + timedelta(days=1)}, 409),
            ({"medication_ids": [self.medication.id, 999999]}, 409),
            ({"medication_ids": []}, 409),
        ]:
            with self.subTest(overrides=overrides):
                with self.assertRaises(HTTPException) as error:
                    self._record_taken(**overrides)
                self.assertEqual(error.exception.status_code, expected)
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)
        self.assertEqual(self.db.query(_ChatMessage).count(), 0)

    # 함수이름: test_chat_failure_rolls_back_dose_and_outbox
    # 함수역할: 확인 채팅 저장 실패 시 복용 기록과 보호자 알림도 함께 롤백되는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_chat_failure_rolls_back_dose_and_outbox(self):
        with patch.object(self.chat.message_repository, "add", side_effect=RuntimeError("failed")):
            with self.assertRaises(RuntimeError):
                self._record_taken()
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)
        self.assertEqual(self.db.query(_CaregiverAlertOutbox).count(), 0)
        self.assertEqual(self.db.query(_ChatMessage).count(), 0)

    # 함수이름: test_ordinary_taken_text_never_records_a_dose
    # 함수역할: 일반 메시지에 '먹었어요'라고 적어도 명시적 복용 확인 없이 기록이 바뀌지 않는지 검증한다.
    # 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
    def test_ordinary_taken_text_never_records_a_dose(self):
        self.chat.send_message(
            link_id=self.link_id, sender_hash="patient-a", client_message_id="ordinary-text-001",
            body="먹었어요", medication_ids=[self.medication.id],
        )
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)

    # 함수이름: _save_medication
    # 함수역할:
    # - 현재부터 7일간 하루 세 번 복용하는 환자 약을 저장하고 갱신된 행을 반환한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - _SavedMedication: 생성된 ID를 포함하여 저장·갱신한 약 행.
    def _save_medication(self) -> _SavedMedication:
        """구조화 채팅 테스트에 사용할 현재 복용 약을 저장한다."""
        medication = _SavedMedication(
            patient_hash="patient-a",
            created_date=application_today(),
            prescription_date=application_today(),
            item_name="테스트정",
            dosage_per_time="1정",
            daily_frequency="1일 3회",
            total_days="7일",
            image_url="https://nedrug.mfds.go.kr/pill.png",
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication


if __name__ == "__main__":
    unittest.main()
