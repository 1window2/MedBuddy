# 파일명: test_dispatch_chat_message_alert_control.py
# 역할: 채팅 푸시 알림의 내용 미리보기와 토큰 정리를 검증한다.

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


class _RecordingPushBoundary:
    """테스트에서 푸시 전달 내용을 기록하는 대체 Boundary다."""

    def __init__(self, *, invalid_tokens: tuple[str, ...] = ()) -> None:
        self.invalid_tokens = invalid_tokens
        self.calls: list[dict[str, object]] = []

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


class DispatchChatMessageAlertTest(unittest.TestCase):
    """오프라인 상대에게 보내는 채팅 알림 정책을 확인한다."""

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

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

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
