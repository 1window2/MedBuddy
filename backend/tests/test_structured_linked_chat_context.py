# 파일명: test_structured_linked_chat_context.py
# 역할: 구조화 채팅의 서버 복약·약국 스냅샷, 역할별 권한 및 완료 이벤트 멱등성을 검증한다.

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
