# 파일명: test_dispatch_chat_message_alert_control.py
# 역할: 채팅 푸시의 수신 설정, 언어, 미리보기 개인정보 및 만료 기기 토큰 처리를 검증한다.

"""채팅 푸시 알림의 내용 미리보기와 토큰 정리를 검증한다."""

import sys
import unittest
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from support.db import make_engine, make_session_factory, seed_account  # noqa: E402
from support.fakes import RecordingPushBoundary  # noqa: E402

from boundaries.push_notification_boundary import PushDeliveryResult  # noqa: E402
from controls.dispatch_chat_message_alert_control import (  # noqa: E402
    DispatchChatMessageAlert,
)
from core.database import Base  # noqa: E402
from entities.chat_message_entity import _ChatMessage  # noqa: E402
from entities.device_push_token_entity import _DevicePushToken  # noqa: E402
from entities.patient_caregiver_link_entity import (  # noqa: E402
    _PatientCaregiverLink,
)
from entities.user_account_entity import _UserAccount, utc_now  # noqa: E402
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


_PATIENT = "patient-a"
_CAREGIVER = "caregiver-a"
_OUTSIDER = "outsider-a"
_ACTIVE_TOKEN = "caregiver-a-active-chat-token-12345"
_DISABLED_TOKEN = "caregiver-a-disabled-chat-token-123"
_PATIENT_TOKEN = "patient-a-active-chat-token-1234567"
_MESSAGE_BODY = "저녁 약을 복용했어요."

# (user_settings 값 또는 행 없음, 기대 언어, 메시지 미리보기 노출 여부)
_RECIPIENT_PREFERENCE_CASES = (
    (None, "ko", True),
    ({"language": "en"}, "en", True),
    ({"language": " EN "}, "en", True),
    ({"language": "fr"}, "ko", True),
    ({"notification_detail_mode": "type_only"}, "ko", False),
    ({"language": "en", "notification_detail_mode": "type_only"}, "en", False),
)
_CHAT_TITLE = {"ko": "새 가족 메시지", "en": "New family message"}
_CHAT_FALLBACK_BODY = {
    "ko": "연동된 가족에게 새 메시지가 도착했습니다.",
    "en": "You received a new message from a linked family member.",
}


# 함수이름: _seed_chat_scene
# 함수역할:
# - 환자·보호자 연동과 환자가 보낸 읽지 않은 메시지, 두 참여자의 기기 토큰을 저장한다.
# - 보호자에게는 활성·비활성 토큰을 하나씩 두어 수신 대상 선택을 검증할 수 있게 한다.
# 매개변수:
# - db (Session): 외래 키가 적용된 테스트 세션.
# - user_setting (dict[str, object] | None): 보호자 user_settings 값; None이면 행을 만들지 않는다.
# 반환값:
# - (연동 ID, 메시지 ID).
def _seed_chat_scene(
    db, user_setting: dict[str, object] | None = None,
) -> tuple[int, int]:
    seed_account(db, _PATIENT, _CAREGIVER, _OUTSIDER)
    link = _PatientCaregiverLink(
        patient_hash=_PATIENT, caregiver_hash=_CAREGIVER, linked=True,
    )
    db.add(link)
    db.flush()
    message = _ChatMessage(
        link_id=link.id,
        sender_hash=_PATIENT,
        client_message_id="chat-scene-message-1",
        body=_MESSAGE_BODY,
    )
    db.add_all(
        [
            message,
            _DevicePushToken(user_hash=_CAREGIVER, token=_ACTIVE_TOKEN),
            _DevicePushToken(
                user_hash=_CAREGIVER, token=_DISABLED_TOKEN, enabled=False,
            ),
            _DevicePushToken(user_hash=_PATIENT, token=_PATIENT_TOKEN),
        ]
    )
    if user_setting is not None:
        db.add(_UserSetting(user_hash=_CAREGIVER, **user_setting))
    db.commit()
    return int(link.id), int(message.id)


# 함수이름: test_chat_alert_follows_recipient_language_and_detail_mode
# 함수역할:
# - 채팅 알림의 제목·본문·데이터가 수신자의 언어와 종류만 표시 설정을 따르고 수신자의 활성 토큰만 쓰는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - user_setting (dict[str, object] | None): 수신자 설정 값 또는 행 없음.
# - language (str): 기대하는 알림 언어 코드.
# - show_details (bool): 메시지 미리보기 노출을 기대하는지 여부.
# 반환값:
# - 없음 (None).
@pytest.mark.parametrize(
    ("user_setting", "language", "show_details"), _RECIPIENT_PREFERENCE_CASES,
)
def test_chat_alert_follows_recipient_language_and_detail_mode(
    fk_db, user_setting, language, show_details,
) -> None:
    link_id, message_id = _seed_chat_scene(fk_db, user_setting)
    boundary = RecordingPushBoundary()

    result = DispatchChatMessageAlert(fk_db, boundary).notify_new_message(
        recipient_hash=_CAREGIVER,
        link_id=link_id,
        message_body="",
        message_id=message_id,
        slot_key="evening",
    )

    assert result.success_count == 1
    assert boundary.calls == [
        {
            "tokens": [_ACTIVE_TOKEN],
            "title": _CHAT_TITLE[language],
            "body": _MESSAGE_BODY if show_details else _CHAT_FALLBACK_BODY[language],
            "data": {
                "type": "linked_chat_message",
                "recipient_hash": _CAREGIVER,
                "language": language,
                "event_id": f"chat:{link_id}:{message_id}",
                "link_id": str(link_id),
                "message_preview": _MESSAGE_BODY if show_details else "",
                "message_kind": "text",
                "slot_key": "evening",
            },
        }
    ]


# 함수이름: test_chat_switch_blocks_chat_alert_but_caregiver_switch_does_not
# 함수역할:
# - 채팅 알림 설정을 끄면 전송하지 않고, 보호자 알림 전역 설정은 채팅 알림에 영향을 주지 않는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
def test_chat_switch_blocks_chat_alert_but_caregiver_switch_does_not(fk_db) -> None:
    link_id, message_id = _seed_chat_scene(
        fk_db,
        {"chat_notifications_enabled": False, "caregiver_notifications_enabled": True},
    )

    # 함수이름: send
    # 함수역할: 저장된 메시지의 채팅 알림을 보호자에게 한 번 전송한다.
    # 매개변수: 없음.
    # 반환값: 전송 요청을 기록한 푸시 대체 경계.
    def send() -> RecordingPushBoundary:
        boundary = RecordingPushBoundary()
        DispatchChatMessageAlert(fk_db, boundary).notify_new_message(
            recipient_hash=_CAREGIVER, link_id=link_id, message_body="",
            message_id=message_id,
        )
        return boundary

    assert send().calls == []

    setting = fk_db.query(_UserSetting).filter_by(user_hash=_CAREGIVER).one()
    setting.chat_notifications_enabled = True
    setting.caregiver_notifications_enabled = False
    fk_db.commit()

    assert len(send().calls) == 1


# 함수이름: test_queued_chat_alert_is_dropped_when_it_is_no_longer_deliverable
# 함수역할:
# - 저장된 메시지 알림을 전송 직전에 다시 확인해 연동 해제, 비참여자, 다른 연동, 숨김·삭제·읽음 상태에서는 보내지 않는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - change (str): 전송 전에 적용할 상태 변경 이름.
# 반환값:
# - 없음 (None).
@pytest.mark.parametrize(
    "change",
    (
        "unlinked",
        "outsider",
        "other_link",
        "missing_message",
        "hidden_for_recipient",
        "deleted_for_everyone",
        "read",
    ),
)
def test_queued_chat_alert_is_dropped_when_it_is_no_longer_deliverable(
    fk_db, change,
) -> None:
    link_id, message_id = _seed_chat_scene(fk_db)
    recipient_hash = _CAREGIVER
    requested_link_id = link_id
    requested_message_id = message_id
    link = fk_db.get(_PatientCaregiverLink, link_id)
    message = fk_db.get(_ChatMessage, message_id)
    if change == "unlinked":
        link.linked = False
    elif change == "outsider":
        fk_db.add(_DevicePushToken(user_hash=_OUTSIDER, token="outsider-chat-token-12345"))
        recipient_hash = _OUTSIDER
    elif change == "other_link":
        other_link = _PatientCaregiverLink(
            patient_hash=_OUTSIDER, caregiver_hash=_CAREGIVER, linked=True,
        )
        fk_db.add(other_link)
        fk_db.flush()
        requested_link_id = int(other_link.id)
    elif change == "missing_message":
        requested_message_id = message_id + 1000
    elif change == "hidden_for_recipient":
        message.caregiver_deleted_at = utc_now()
    elif change == "deleted_for_everyone":
        message.deleted_for_everyone_at = utc_now()
    elif change == "read":
        message.read_at = utc_now()
    fk_db.commit()
    boundary = RecordingPushBoundary()

    result = DispatchChatMessageAlert(fk_db, boundary).notify_new_message(
        recipient_hash=recipient_hash,
        link_id=requested_link_id,
        message_body="",
        message_id=requested_message_id,
    )

    assert result.success_count == 0
    assert boundary.calls == []


# 함수이름: test_message_hidden_only_for_the_sender_is_still_delivered
# 함수역할:
# - 보낸 사람만 자기 화면에서 숨긴 메시지는 상대에게 계속 알리는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
def test_message_hidden_only_for_the_sender_is_still_delivered(fk_db) -> None:
    link_id, message_id = _seed_chat_scene(fk_db)
    fk_db.get(_ChatMessage, message_id).patient_deleted_at = utc_now()
    fk_db.commit()
    boundary = RecordingPushBoundary()

    DispatchChatMessageAlert(fk_db, boundary).notify_new_message(
        recipient_hash=_CAREGIVER, link_id=link_id, message_body="",
        message_id=message_id,
    )

    assert len(boundary.calls) == 1


# 함수이름: test_dose_receipt_push_never_carries_medication_names
# 함수역할:
# - 서버가 쓴 복용 기록 메시지의 알림 본문과 데이터에 약 이름이 실리지 않는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - user_setting (dict[str, object] | None): 수신자 설정 값 또는 행 없음.
# - expected_preview (str): 약 이름 없이 날짜와 시간대만 담은 기대 문구.
# 반환값:
# - 없음 (None).
@pytest.mark.parametrize(
    ("user_setting", "expected_preview"),
    [
        (None, "2026-10-09 아침 복용을 기록했습니다."),
        ({"language": "en"}, "Recorded morning doses for 2026-10-09."),
    ],
)
def test_dose_receipt_push_never_carries_medication_names(
    fk_db, user_setting, expected_preview,
) -> None:
    link_id, message_id = _seed_chat_scene(fk_db, user_setting)
    row = fk_db.get(_ChatMessage, message_id)
    row.body = "2026-10-09 아침 · 비밀혈압약, 비밀당뇨약 복용을 기록했습니다."
    row.context_payload = {
        "completion_confirmation": {
            "schedule_date": "2026-10-09",
            "slot_key": "morning",
            "medication_ids": [1, 2],
        },
    }
    fk_db.commit()
    boundary = RecordingPushBoundary()

    DispatchChatMessageAlert(fk_db, boundary).notify_new_message(
        recipient_hash=_CAREGIVER, link_id=link_id, message_body="",
        message_id=message_id,
    )

    call = boundary.calls[0]
    assert call["body"] == expected_preview
    assert call["data"]["message_preview"] == expected_preview
    assert "비밀" not in str(call)


# 함수이름: test_chat_push_is_sent_after_the_session_released_its_connection
# 함수역할:
# - 채팅 알림을 보내는 시점에 세션이 트랜잭션도 풀 연결도 잡고 있지 않은지 검증한다.
# 매개변수:
# - tmp_path (Path): 풀 연결 수를 셀 수 있는 파일 엔진을 만들 임시 디렉터리.
# 반환값:
# - 없음 (None).
def test_chat_push_is_sent_after_the_session_released_its_connection(tmp_path) -> None:
    engine = make_engine(tmp_path)
    db = make_session_factory(engine)()
    try:
        link_id, message_id = _seed_chat_scene(db)
        seen_at_send: list[tuple[int, bool]] = []
        boundary = RecordingPushBoundary(
            on_send=lambda call: seen_at_send.append(
                (engine.pool.checkedout(), db.in_transaction())
            ),
        )

        result = DispatchChatMessageAlert(db, boundary).notify_new_message(
            recipient_hash=_CAREGIVER, link_id=link_id, message_body="",
            message_id=message_id,
        )

        assert result.success_count == 1
        assert seen_at_send == [(0, False)]
    finally:
        db.close()
        engine.dispose()


# 함수이름: test_rejected_chat_token_is_disabled_in_a_committed_transaction
# 함수역할:
# - Firebase가 거부한 채팅 수신 토큰만 비활성화하고 그 변경이 다른 연결에서 보이도록 커밋되는지 검증한다.
# 매개변수:
# - tmp_path (Path): 세션마다 다른 연결을 쓰는 파일 엔진을 만들 임시 디렉터리.
# 반환값:
# - 없음 (None).
def test_rejected_chat_token_is_disabled_in_a_committed_transaction(tmp_path) -> None:
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    db = sessions()
    observer = sessions()
    try:
        link_id, message_id = _seed_chat_scene(db)
        boundary = RecordingPushBoundary(invalid_tokens=(_ACTIVE_TOKEN,))

        result = DispatchChatMessageAlert(db, boundary).notify_new_message(
            recipient_hash=_CAREGIVER, link_id=link_id, message_body="",
            message_id=message_id,
        )

        assert result.invalid_tokens == (_ACTIVE_TOKEN,)
        enabled_by_token = {
            str(row.token): bool(row.enabled)
            for row in observer.query(_DevicePushToken).all()
        }
        assert enabled_by_token == {
            _ACTIVE_TOKEN: False,
            _DISABLED_TOKEN: False,
            _PATIENT_TOKEN: True,
        }
        assert not db.in_transaction()
    finally:
        observer.close()
        db.close()
        engine.dispose()


# 함수이름: test_sent_chat_push_is_reported_even_when_token_cleanup_fails
# 함수역할:
# - 전송 뒤 무효 토큰 정리가 DB 장애로 실패해도 전송 결과를 그대로 돌려주고 세션을 계속 쓸 수 있는지 검증한다.
# - 예외가 올라가면 호출한 작업이 같은 메시지를 다시 보내게 된다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
def test_sent_chat_push_is_reported_even_when_token_cleanup_fails(fk_db) -> None:
    link_id, message_id = _seed_chat_scene(fk_db)
    # 거부되는 토큰 외에 정상 기기 하나를 더 두어 전달된 푸시가 실제로 있도록 한다.
    fk_db.add(_DevicePushToken(user_hash=_CAREGIVER, token="caregiver-a-second-chat-token-12"))
    fk_db.commit()
    original_commit = fk_db.commit

    # 함수이름: fail_cleanup_commit
    # 함수역할: 전송 직후의 커밋 한 번을 DB 장애처럼 실패시키고 원래 커밋으로 되돌린다.
    # 매개변수: 없음.
    # 반환값: 없음 (None).
    def fail_cleanup_commit() -> None:
        fk_db.commit = original_commit
        raise OperationalError("COMMIT", None, Exception("database is unavailable"))

    # 함수이름: arm_failure
    # 함수역할: 전송 시점에 다음 커밋 실패를 예약한다.
    # 매개변수: call (dict[str, object]): 기록된 전송 요청.
    # 반환값: 없음 (None).
    def arm_failure(call: dict[str, object]) -> None:
        fk_db.commit = fail_cleanup_commit

    boundary = RecordingPushBoundary(
        invalid_tokens=(_ACTIVE_TOKEN,), on_send=arm_failure,
    )

    result = DispatchChatMessageAlert(fk_db, boundary).notify_new_message(
        recipient_hash=_CAREGIVER, link_id=link_id, message_body="",
        message_id=message_id,
    )

    assert result.success_count == 1
    assert result.invalid_tokens == (_ACTIVE_TOKEN,)
    assert result.all_valid_targets_succeeded
    assert len(boundary.calls) == 1
    # 정리 트랜잭션은 되돌려졌고 세션은 다음 작업에 그대로 쓸 수 있다.
    assert fk_db.query(_DevicePushToken).filter_by(token=_ACTIVE_TOKEN).one().enabled


if __name__ == "__main__":
    unittest.main()
