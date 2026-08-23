# 파일명: test_manage_linked_chat_control.py
# 역할: 환자·보호자 연동 채팅의 권한, 중복 방지, 읽음 처리를 검증한다.

"""환자·보호자 연동 채팅의 권한, 중복 방지, 읽음 처리를 검증한다."""

import sys
import unittest
from datetime import timedelta
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
from entities.chat_message_entity import _ChatMessage  # noqa: E402
from entities.saved_medication_entity import _SavedMedication  # noqa: E402


class ManageLinkedChatTest(unittest.TestCase):
    """활성 연동에서만 대화가 유지되는지 확인한다."""

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
        self.link_control = LinkPatientCaregiver(self.db)
        code_response = self.link_control.generatePatientHash("patient-a")
        link_response = self.link_control.requestPatientCaregiverLink(
            "caregiver-a",
            code_response["data"]["patient_code"],
        )
        self.link_id = int(link_response["data"]["id"])
        self.chat = ManageLinkedChat(self.db)
        self.medication = self._save_medication()

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_retried_client_request_is_saved_once(self) -> None:
        """동일 요청 식별자의 재전송이 메시지를 중복 생성하지 않는지 검증한다."""
        first = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="patient-a",
            client_message_id="message_request_001",
            body="아침 약을 복용했어요.",
            medication_id=int(self.medication.id),
        )
        retried = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="patient-a",
            client_message_id="message_request_001",
            body="아침 약을 복용했어요.",
            medication_id=int(self.medication.id),
        )

        self.assertTrue(first.created)
        self.assertFalse(retried.created)
        self.assertEqual(first.message.message_id, retried.message.message_id)
        self.assertEqual(self.db.query(_ChatMessage).count(), 1)

    def test_history_and_read_state_are_scoped_to_participants(self) -> None:
        """참여자별 읽지 않은 수와 읽음 상태가 올바르게 갱신되는지 검증한다."""
        sent = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="patient-a",
            client_message_id="message_request_002",
            body="점심 약도 확인해주세요.",
            medication_id=int(self.medication.id),
        )

        patient_unread = self.chat.request_unread_count(
            link_id=self.link_id,
            user_hash="patient-a",
        )
        caregiver_unread = self.chat.request_unread_count(
            link_id=self.link_id,
            user_hash="caregiver-a",
        )
        read_response = self.chat.mark_read(
            link_id=self.link_id,
            reader_hash="caregiver-a",
            through_message_id=sent.message.message_id,
        )
        history = self.chat.request_history(
            link_id=self.link_id,
            user_hash="caregiver-a",
            before_message_id=None,
            limit=50,
        )

        self.assertEqual(patient_unread["data"]["unread_count"], 0)
        self.assertEqual(caregiver_unread["data"]["unread_count"], 1)
        self.assertEqual(read_response["data"]["updated_count"], 1)
        self.assertEqual(len(history["data"]), 1)
        self.assertIsNotNone(history["data"][0]["read_at"])

    def test_history_has_more_only_when_an_older_message_exists(self) -> None:
        """페이지 크기와 메시지 수가 같을 때 잘못된 다음 페이지를 표시하지 않는다."""
        for index in range(2):
            self.chat.send_message(
                link_id=self.link_id,
                sender_hash="patient-a",
                client_message_id=f"page_request_{index:03d}",
                body=f"페이지 메시지 {index}",
                medication_id=int(self.medication.id),
            )

        exact_page = self.chat.request_history(
            link_id=self.link_id,
            user_hash="caregiver-a",
            before_message_id=None,
            limit=2,
        )
        shorter_page = self.chat.request_history(
            link_id=self.link_id,
            user_hash="caregiver-a",
            before_message_id=None,
            limit=1,
        )

        self.assertFalse(exact_page["has_more"])
        self.assertTrue(shorter_page["has_more"])

    def test_unrelated_user_cannot_access_link_chat(self) -> None:
        """연동에 참여하지 않은 사용자의 조회와 전송을 모두 거부하는지 검증한다."""
        with self.assertRaises(HTTPException) as history_context:
            self.chat.request_history(
                link_id=self.link_id,
                user_hash="stranger",
                before_message_id=None,
                limit=50,
            )
        with self.assertRaises(HTTPException) as send_context:
            self.chat.send_message(
                link_id=self.link_id,
                sender_hash="stranger",
                client_message_id="message_request_003",
                body="허용되지 않은 메시지",
                medication_id=int(self.medication.id),
            )

        self.assertEqual(history_context.exception.status_code, 404)
        self.assertEqual(send_context.exception.status_code, 404)
        self.assertEqual(self.db.query(_ChatMessage).count(), 0)

    def test_unlink_removes_chat_history(self) -> None:
        """연동 해제 후 대화 기록과 접근 권한이 함께 제거되는지 검증한다."""
        self.chat.send_message(
            link_id=self.link_id,
            sender_hash="caregiver-a",
            client_message_id="message_request_004",
            body="연동 해제 전 메시지",
            medication_id=int(self.medication.id),
        )

        self.link_control.requestUnlink(self.link_id, "caregiver-a")

        self.assertEqual(self.db.query(_ChatMessage).count(), 0)
        with self.assertRaises(HTTPException) as context:
            self.chat.request_history(
                link_id=self.link_id,
                user_hash="patient-a",
                before_message_id=None,
                limit=50,
            )
        self.assertEqual(context.exception.status_code, 404)

    def test_participants_receive_same_active_medication_contexts(self) -> None:
        """환자와 보호자가 동일한 활성 복약 목록을 받는지 검증한다."""
        patient_response = self.chat.request_medication_contexts(
            link_id=self.link_id,
            user_hash="patient-a",
        )
        caregiver_response = self.chat.request_medication_contexts(
            link_id=self.link_id,
            user_hash="caregiver-a",
        )

        self.assertEqual(patient_response["data"], caregiver_response["data"])
        self.assertEqual(patient_response["data"][0]["medication_name"], "테스트정")
        self.assertEqual(
            patient_response["data"][0]["schedule_slot_keys"],
            ["morning", "lunch", "evening"],
        )

    def test_participants_can_open_patient_medication_detail(self) -> None:
        """두 참여자가 채팅 약 카드에서 동일한 환자 약 상세정보를 보는지 검증한다."""
        self.medication.efficacy = "테스트 효능"
        self.medication.use_method = "하루 세 번 복용"
        self.medication.warning_message = "복용 전 주의사항 확인"
        self.db.commit()

        patient_response = self.chat.request_medication_detail(
            link_id=self.link_id,
            user_hash="patient-a",
            medication_id=int(self.medication.id),
        )
        caregiver_response = self.chat.request_medication_detail(
            link_id=self.link_id,
            user_hash="caregiver-a",
            medication_id=int(self.medication.id),
        )

        self.assertEqual(patient_response["data"], caregiver_response["data"])
        self.assertEqual(patient_response["data"]["item_name"], "테스트정")
        self.assertEqual(patient_response["data"]["efficacy"], "테스트 효능")

    def test_unrelated_user_cannot_open_chat_medication_detail(self) -> None:
        """연동 참여자가 아닌 사용자는 채팅 약 상세정보를 볼 수 없는지 검증한다."""
        with self.assertRaises(HTTPException) as context:
            self.chat.request_medication_detail(
                link_id=self.link_id,
                user_hash="stranger",
                medication_id=int(self.medication.id),
            )

        self.assertEqual(context.exception.status_code, 404)

    def test_sent_message_preserves_medication_snapshot(self) -> None:
        """전송 당시 약명, 용량, 사진이 메시지 응답에 보존되는지 검증한다."""
        sent = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="caregiver-a",
            client_message_id="message_request_005",
            body="이 약은 아직 안 드셨나요?",
            medication_id=int(self.medication.id),
        )

        response = sent.message.to_response_dict()
        context = response["medication_context"]
        self.assertEqual(context["medication_name"], "테스트정")
        self.assertEqual(context["dosage_per_time"], "1정")
        self.assertEqual(
            context["image_url"],
            "https://nedrug.mfds.go.kr/pill.png",
        )

    def test_message_without_medication_context_is_allowed(self) -> None:
        """약을 고르지 않은 일반 메시지도 복약 카드 없이 저장되는지 검증한다."""
        sent = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="patient-a",
            client_message_id="message_request_006",
            body="오늘은 몸 상태가 괜찮아요.",
        )

        response = sent.message.to_response_dict()
        self.assertTrue(sent.created)
        self.assertEqual(response["body"], "오늘은 몸 상태가 괜찮아요.")
        self.assertIsNone(response["medication_context"])

    def test_unowned_or_inactive_medication_is_rejected(self) -> None:
        """다른 사용자의 약과 복용 종료 약을 채팅에 첨부할 수 없는지 검증한다."""
        other_medication = self._save_medication(patient_hash="caregiver-a")
        inactive_medication = self._save_medication(
            item_name="종료된약",
            prescription_date=application_today() - timedelta(days=10),
            total_days="3일",
        )

        for medication in (other_medication, inactive_medication):
            with self.assertRaises(HTTPException) as context:
                self.chat.send_message(
                    link_id=self.link_id,
                    sender_hash="patient-a",
                    client_message_id=f"message_request_{medication.id}",
                    body="검증 대상 메시지",
                    medication_id=int(medication.id),
                )
            self.assertEqual(context.exception.status_code, 400)

    def _save_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "테스트정",
        prescription_date=None,
        total_days: str = "7일",
    ) -> _SavedMedication:
        """채팅 검증에 사용할 복약정보를 현재 테스트 DB에 저장한다."""
        medication = _SavedMedication(
            patient_hash=patient_hash,
            created_date=application_today(),
            prescription_date=prescription_date or application_today(),
            item_name=item_name,
            dosage_per_time="1정",
            daily_frequency="1일 3회",
            total_days=total_days,
            image_url="https://nedrug.mfds.go.kr/pill.png",
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication


if __name__ == "__main__":
    unittest.main()
