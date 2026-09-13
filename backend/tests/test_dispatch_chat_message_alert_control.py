# 파일명: test_dispatch_chat_message_alert_control.py
# 역할: 채팅 푸시의 수신 설정, 언어, 미리보기 개인정보 및 만료 기기 토큰 처리를 검증한다.

"""채팅 푸시 알림의 내용 미리보기와 토큰 정리를 검증한다."""

import sys
import unittest
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from boundaries.push_notification_boundary import PushDeliveryResult  # noqa: E402
from controls.dispatch_chat_message_alert_control import (  # noqa: E402
    DispatchChatMessageAlert,
)
from core.database import Base  # noqa: E402
from entities.device_push_token_entity import _DevicePushToken  # noqa: E402
from entities.user_account_entity import _UserAccount  # noqa: E402
from entities.user_setting_entity import _UserSetting  # noqa: E402


# 클래스명: _RecordingPushBoundary
# 역할: 푸시 요청 내용을 기록하고 지정된 무효 토큰을 전달 결과로 돌려주는 대체 경계다.
# 주요 책임:
# - 토큰·제목·본문·데이터를 기록하고 무효 토큰을 제외한 성공 건수를 반환한다.
# 속성:
# - invalid_tokens (tuple[str, ...]): 푸시 대체 객체가 영구 무효로 분류할 토큰.
# - calls (list[dict[str, object]]): 후속 검증을 위해 순서대로 기록한 요청.
class _RecordingPushBoundary:
    """테스트에서 푸시 전달 내용을 기록하는 대체 Boundary다."""

    # 함수이름: __init__
    # 함수역할:
    # - 무효 토큰 목록과 빈 푸시 요청 이력을 준비한다.
    # 매개변수:
    # - invalid_tokens (tuple[str, ...]): 영구적으로 무효하다고 보고할 기기 토큰 목록.
    # 반환값:
    # - 없음 (None).
    def __init__(self, *, invalid_tokens: tuple[str, ...] = ()) -> None:
        self.invalid_tokens = invalid_tokens
        self.calls: list[dict[str, object]] = []

    # 함수이름: send_notification
    # 함수역할:
    # - 토큰·제목·본문·데이터를 기록하고 무효 토큰을 제외한 성공 건수를 반환한다.
    # 매개변수:
    # - tokens (list[str]): 푸시 전달 대상으로 제출할 수신 기기 토큰 목록.
    # - title (str): 푸시 대체 객체가 기록할 알림 제목.
    # - body (str): 기록할 알림 본문.
    # - data (dict[str, str]): 기록할 알림 라우팅 및 맥락 데이터.
    # 반환값:
    # - PushDeliveryResult: 대체 객체에 지정한 전송 성공 건수와 영구·일시 토큰 실패 정보.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult:
        self.calls.append(
            {
                "tokens": tokens,
                "title": title,
                "body": body,
                "data": data,
            }
        )
        return PushDeliveryResult(
            success_count=max(0, len(tokens) - len(self.invalid_tokens)),
            invalid_tokens=self.invalid_tokens,
        )


# 클래스명: DispatchChatMessageAlertTest
# 역할: 오프라인 연동 상대에게 보내는 채팅 알림과 미리보기 정책을 검증하는 테스트 모음이다.
# 주요 책임:
# - 실제 메시지 미리보기와 연동 데이터를 전달하고 무효 기기 토큰을 비활성화하는지 검증한다.
# - 긴 메시지 미리보기를 말줄임표 포함 120자로 제한하는지 검증한다.
# - 종류만 표시하는 설정에서 일반 안내 본문을 사용하고 데이터의 메시지 미리보기도 비우는지 검증한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
class DispatchChatMessageAlertTest(unittest.TestCase):
    """오프라인 상대에게 보내는 채팅 알림 정책을 확인한다."""

    # 함수이름: setUp
    # 함수역할:
    # - 격리된 SQLite DB에 환자와 보호자 계정을 등록하여 푸시 설정 테스트를 준비한다.
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
        self.db = sessionmaker(bind=self.engine)()
        self.db.add_all(
            [
                _UserAccount(user_hash="patient-a"),
                _UserAccount(user_hash="caregiver-a"),
            ]
        )
        self.db.commit()

    # 함수이름: tearDown
    # 함수역할:
    # - 푸시 테스트의 DB 세션과 엔진을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # 함수이름: test_notification_includes_message_preview_and_disables_invalid_token
    # 함수역할:
    # - 실제 메시지 미리보기와 연동 데이터를 전달하고 무효 기기 토큰을 비활성화하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_notification_includes_message_preview_and_disables_invalid_token(
        self,
    ) -> None:
        """알림에 실제 채팅 내용을 표시하고 만료 토큰을 비활성화하는지 검증한다."""
        active_token = "active-chat-token-value-12345"
        invalid_token = "invalid-chat-token-value-123"
        self.db.add_all(
            [
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token=active_token,
                    platform="android",
                    enabled=True,
                ),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token=invalid_token,
                    platform="android",
                    enabled=True,
                ),
            ]
        )
        self.db.commit()
        boundary = _RecordingPushBoundary(invalid_tokens=(invalid_token,))

        result = DispatchChatMessageAlert(self.db, boundary).notify_new_message(
            recipient_hash="caregiver-a",
            link_id=17,
            message_body="  저녁 약을   복용했어요.\n확인해주세요.  ",
        )

        self.assertEqual(result.success_count, 1)
        self.assertEqual(len(boundary.calls), 1)
        call = boundary.calls[0]
        self.assertEqual(call["title"], "새 가족 메시지")
        self.assertEqual(call["body"], "저녁 약을 복용했어요. 확인해주세요.")
        self.assertEqual(
            call["data"],
            {
                "type": "linked_chat_message",
                "link_id": "17",
                "recipient_hash": "caregiver-a",
                "language": "ko",
                "message_preview": "저녁 약을 복용했어요. 확인해주세요.",
                "message_kind": "text",
                "slot_key": "",
            },
        )
        invalid_row = (
            self.db.query(_DevicePushToken)
            .filter(_DevicePushToken.token == invalid_token)
            .one()
        )
        self.assertFalse(invalid_row.enabled)

    # 함수이름: test_missing_recipient_token_skips_push_boundary
    # 함수역할:
    # - 수신 기기 토큰이 없으면 푸시 경계를 호출하지 않고 성공 건수가 0인지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_missing_recipient_token_skips_push_boundary(self) -> None:
        """수신 기기 토큰이 없을 때 외부 푸시 호출을 생략하는지 검증한다."""
        boundary = _RecordingPushBoundary()

        result = DispatchChatMessageAlert(self.db, boundary).notify_new_message(
            recipient_hash="caregiver-a",
            link_id=17,
            message_body="메시지",
        )

        self.assertEqual(result.success_count, 0)
        self.assertEqual(boundary.calls, [])

    # 함수이름: test_english_recipient_receives_message_preview
    # 함수역할:
    # - 영어 수신자에게 영어 제목과 원래 메시지 본문을 전달하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_english_recipient_receives_message_preview(self) -> None:
        """영어 설정 수신자도 실제 메시지 내용을 알림에서 확인하는지 검증한다."""
        self.db.add_all(
            [
                _UserSetting(user_hash="caregiver-a", language="en"),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token="english-chat-token-value-12345",
                    platform="android",
                    enabled=True,
                ),
            ]
        )
        self.db.commit()
        boundary = _RecordingPushBoundary()

        DispatchChatMessageAlert(self.db, boundary).notify_new_message(
            recipient_hash="caregiver-a",
            link_id=21,
            message_body="I took the morning medication.",
        )

        self.assertEqual(boundary.calls[0]["title"], "New family message")
        self.assertEqual(
            boundary.calls[0]["body"],
            "I took the morning medication.",
        )

    # 함수이름: test_long_message_preview_is_bounded
    # 함수역할:
    # - 긴 메시지 미리보기를 말줄임표 포함 120자로 제한하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_long_message_preview_is_bounded(self) -> None:
        """긴 채팅이 시스템 알림을 과도하게 채우지 않도록 길이를 제한한다."""
        self.db.add(
            _DevicePushToken(
                user_hash="caregiver-a",
                token="long-message-chat-token-12345",
                platform="android",
                enabled=True,
            )
        )
        self.db.commit()
        boundary = _RecordingPushBoundary()

        DispatchChatMessageAlert(self.db, boundary).notify_new_message(
            recipient_hash="caregiver-a",
            link_id=31,
            message_body="가" * 160,
        )

        preview = boundary.calls[0]["body"]
        self.assertEqual(len(preview), 120)
        self.assertTrue(str(preview).endswith("…"))

    # 함수이름: test_disabled_chat_notification_skips_push
    # 함수역할:
    # - 채팅 알림을 끈 수신자에게 외부 푸시를 호출하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_disabled_chat_notification_skips_push(self) -> None:
        """수신자가 채팅 알림을 끄면 푸시 경계를 호출하지 않는지 검증한다."""
        self.db.add_all(
            [
                _UserSetting(
                    user_hash="caregiver-a",
                    chat_notifications_enabled=False,
                ),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token="disabled-chat-token-value-12345",
                    platform="android",
                    enabled=True,
                ),
            ]
        )
        self.db.commit()
        boundary = _RecordingPushBoundary()

        result = DispatchChatMessageAlert(self.db, boundary).notify_new_message(
            recipient_hash="caregiver-a",
            link_id=41,
            message_body="저녁 약을 복용했어요.",
        )

        self.assertEqual(result.success_count, 0)
        self.assertEqual(boundary.calls, [])

    # 함수이름: test_type_only_notification_hides_chat_preview
    # 함수역할:
    # - 종류만 표시하는 설정에서 일반 안내 본문을 사용하고 데이터의 메시지 미리보기도 비우는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_type_only_notification_hides_chat_preview(self) -> None:
        """알림 종류만 표시하면 채팅 원문을 푸시 본문과 데이터에서 숨긴다."""
        self.db.add_all(
            [
                _UserSetting(
                    user_hash="caregiver-a",
                    notification_detail_mode="type_only",
                ),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token="private-chat-token-value-12345",
                    platform="android",
                    enabled=True,
                ),
            ]
        )
        self.db.commit()
        boundary = _RecordingPushBoundary()

        DispatchChatMessageAlert(self.db, boundary).notify_new_message(
            recipient_hash="caregiver-a",
            link_id=42,
            message_body="저녁 약을 복용했어요.",
        )

        self.assertEqual(
            boundary.calls[0]["body"],
            "연동된 가족에게 새 메시지가 도착했습니다.",
        )
        self.assertEqual(boundary.calls[0]["data"]["message_preview"], "")


if __name__ == "__main__":
    unittest.main()
