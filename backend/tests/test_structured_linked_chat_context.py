# 파일명: test_structured_linked_chat_context.py
# 역할: 시간대 복약 확인, 약 부족 안내와 약국 공유 채팅의 서버 검증을 확인한다.

"""구조화 채팅 문맥의 권한, 신뢰 경계와 중복 방지를 검증한다."""

import sys
import unittest
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
from entities.pharmacy_catalog_entity import PharmacyCatalogRecord  # noqa: E402
from entities.saved_medication_entity import _SavedMedication  # noqa: E402


class StructuredLinkedChatContextTest(unittest.TestCase):
    """구조화 채팅이 연동 환자의 실제 데이터만 노출하는지 확인한다."""

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

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

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
