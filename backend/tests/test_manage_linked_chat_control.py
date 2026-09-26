# 파일명: test_manage_linked_chat_control.py
# 역할: 활성 연동 채팅의 참여자 권한, 멱등 전송, 읽음 상태 및 복약 스냅샷을 검증한다.

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


# 클래스명: ManageLinkedChatTest
# 역할: 활성 연동에서만 대화와 실제 환자 복약 정보가 공유되는지 검증하는 테스트 모음이다.
# 주요 책임:
# - 동일 클라이언트 요청 재전송이 같은 메시지 ID를 반환하고 저장 행은 한 건만 남는지 검증한다.
# - 비참여자의 채팅 약 상세 조회를 404로 거절하는지 검증한다.
# - 지정 환자·약명·처방일·복용 기간의 약을 현재 DB에 저장하고 갱신된 행을 반환한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
# - link_control (LinkPatientCaregiver): fixture의 환자·보호자 관계를 생성할 연동 control.
# - link_id (int): 시험용 환자와 보호자가 공유하는 활성 연동 ID.
# - chat (ManageLinkedChat): 격리 테스트 세션에 연결한 채팅 control.
# - medication (_SavedMedication): 현재 테스트 조건에서 공유할 저장된 활성 약.
class ManageLinkedChatTest(unittest.TestCase):
    """활성 연동에서만 대화가 유지되는지 확인한다."""

    # 함수이름: setUp
    # 함수역할:
    # - 격리 DB에 환자·보호자 연동과 약을 만들고 연동 및 채팅 control을 준비한다.
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
        self.link_control = LinkPatientCaregiver(self.db)
        code_response = self.link_control.generatePatientHash("patient-a")
        link_response = self.link_control.requestPatientCaregiverLink(
            "caregiver-a",
            code_response["data"]["patient_code"],
        )
        self.link_id = int(link_response["data"]["id"])
        self.chat = ManageLinkedChat(self.db)
        self.medication = self._save_medication()

    # 함수이름: tearDown
    # 함수역할:
    # - 연동 채팅 테스트의 세션과 데이터베이스 엔진을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # 함수이름: test_retried_client_request_is_saved_once
    # 함수역할:
    # - 동일 클라이언트 요청 재전송이 같은 메시지 ID를 반환하고 저장 행은 한 건만 남는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_history_and_read_state_are_scoped_to_participants
    # 함수역할:
    # - 발신자·수신자의 미읽음 수를 구분하고 수신자의 읽음 갱신이 채팅 기록에 반영되는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_history_has_more_only_when_an_older_message_exists
    # 함수역할:
    # - 페이지 크기와 전체 메시지 수가 같으면 has_more가 거짓이고 실제 이전 메시지가 있을 때만 참인지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_unrelated_user_cannot_access_link_chat
    # 함수역할:
    # - 연동 외 사용자의 조회·전송을 모두 404로 거절하고 메시지를 저장하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_unlink_removes_chat_history
    # 함수역할:
    # - 연동 해제 시 채팅 기록을 제거하고 이후 접근을 404로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_participants_receive_same_active_medication_contexts
    # 함수역할:
    # - 환자와 보호자에게 같은 활성 약 목록 및 아침·점심·저녁 시간대를 제공하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_participants_can_open_patient_medication_detail
    # 함수역할:
    # - 양측 참여자가 채팅 약 카드에서 동일 환자의 약명과 효능 상세를 조회하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_unrelated_user_cannot_open_chat_medication_detail
    # 함수역할:
    # - 비참여자의 채팅 약 상세 조회를 404로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_unrelated_user_cannot_open_chat_medication_detail(self) -> None:
        """연동 참여자가 아닌 사용자는 채팅 약 상세정보를 볼 수 없는지 검증한다."""
        with self.assertRaises(HTTPException) as context:
            self.chat.request_medication_detail(
                link_id=self.link_id,
                user_hash="stranger",
                medication_id=int(self.medication.id),
            )

        self.assertEqual(context.exception.status_code, 404)

    # 함수이름: test_sent_message_preserves_medication_snapshot
    # 함수역할:
    # - 메시지에 전송 당시 약명·1회 용량·공식 사진 URL이 스냅샷으로 보존되는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_sent_message_preserves_multiple_medication_snapshots
    # 함수역할:
    # - 여러 첨부 약의 순서와 스냅샷을 기록 조회에서도 유지하며 구형 단일 약 필드도 제공하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_sent_message_preserves_multiple_medication_snapshots(self) -> None:
        """여러 약을 첨부한 메시지가 전송 당시의 모든 약 정보를 보존한다."""
        evening_medication = self._save_medication(item_name="저녁정")

        sent = self.chat.send_message(
            link_id=self.link_id,
            sender_hash="caregiver-a",
            client_message_id="message_request_multiple_001",
            body="두 약 모두 복용하셨나요?",
            medication_id=int(self.medication.id),
            medication_ids=[
                int(self.medication.id),
                int(evening_medication.id),
            ],
        )

        response = sent.message.to_response_dict()
        contexts = response["medication_contexts"]
        history = self.chat.request_history(
            link_id=self.link_id,
            user_hash="patient-a",
            before_message_id=None,
            limit=50,
        )

        self.assertEqual(
            response["medication_context"]["medication_name"],
            "테스트정",
        )
        self.assertEqual(
            [context["medication_name"] for context in contexts],
            ["테스트정", "저녁정"],
        )
        self.assertEqual(history["data"][0]["medication_contexts"], contexts)

    # 함수이름: test_sent_message_rejects_more_than_ten_medication_contexts
    # 함수역할:
    # - 구형 단일 약 필드와 복수 약 선택을 합쳐 10개를 넘으면 HTTP 400으로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_sent_message_rejects_more_than_ten_medication_contexts(self) -> None:
        """구형 단일 약 필드를 함께 보내도 전체 선택 약을 10개로 제한한다."""
        medications = [
            self._save_medication(item_name=f"추가약{index}")
            for index in range(10)
        ]

        with self.assertRaises(HTTPException) as context:
            self.chat.send_message(
                link_id=self.link_id,
                sender_hash="caregiver-a",
                client_message_id="message_request_too_many_medications",
                body="선택 약 개수 제한 확인",
                medication_id=int(self.medication.id),
                medication_ids=[int(item.id) for item in medications],
            )

        self.assertEqual(context.exception.status_code, 400)

    # 함수이름: test_message_without_medication_context_is_allowed
    # 함수역할:
    # - 약을 선택하지 않은 일반 메시지는 원문과 빈 복약 맥락으로 정상 저장되는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_unowned_or_inactive_medication_is_rejected
    # 함수역할:
    # - 다른 환자의 약이나 종료된 약을 단일·복수 첨부 모두에서 HTTP 400으로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

        with self.assertRaises(HTTPException) as plural_context:
            self.chat.send_message(
                link_id=self.link_id,
                sender_hash="patient-a",
                client_message_id="message_request_invalid_multiple",
                body="여러 약 권한 검증",
                medication_ids=[
                    int(self.medication.id),
                    int(other_medication.id),
                ],
            )
        self.assertEqual(plural_context.exception.status_code, 400)

    # 함수이름: _save_medication
    # 함수역할:
    # - 지정 환자·약명·처방일·복용 기간의 약을 현재 DB에 저장하고 갱신된 행을 반환한다.
    # 매개변수:
    # - patient_hash (str): 약 또는 연동 데이터 범위를 식별할 환자 소유자 해시.
    # - item_name (str): 공식 카탈로그 또는 저장 약 레코드의 제품명.
    # - prescription_date (date | None): 처방 또는 복용 시작일이며 None이면 fixture 기본 날짜 사용.
    # - total_days (str): 처방된 복용 기간 문자열이며 미상일 수 있음.
    # 반환값:
    # - _SavedMedication: 생성된 ID를 포함하여 저장·갱신한 약 행.
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
