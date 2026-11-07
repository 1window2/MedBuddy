# 파일명: push_notification_boundary.py
# 역할: 보호자 알림 유스케이스와 Firebase Cloud Messaging SDK를 분리한다.

import logging
import re
from dataclasses import dataclass
from typing import Protocol

from firebase_admin import exceptions as firebase_exceptions
from firebase_admin import messaging

from boundaries.firebase_admin_boundary import get_firebase_admin_app

logger = logging.getLogger(__name__)


# 클래스명: PushDeliveryResult
# 역할:
# - 푸시 전송 성공, 영구 실패 토큰, 재시도 가능한 실패 개수를 전달한다.
# 주요 책임:
# - 성공 수, 영구 무효 토큰과 재시도 대상 수를 구분하여 후속 토큰 정리와 재전송 판단을 지원한다.
# 속성:
# - success_count (int): 성공한 기기 전송 수.
# - invalid_tokens (tuple[str, ...]): 삭제 또는 비활성화할 등록 토큰.
# - retryable_failure_count (int): 일시적으로 전송에 실패한 대상 수.
@dataclass(frozen=True)
class PushDeliveryResult:
    success_count: int
    invalid_tokens: tuple[str, ...] = ()
    retryable_failure_count: int = 0

    # 함수이름: all_valid_targets_succeeded
    # 함수역할:
    # - 영구 무효 토큰과 관계없이 재시도 대상 전송 실패가 남아 있는지 판정한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - retryable_failure_count가 0이면 True.
    @property
    def all_valid_targets_succeeded(self) -> bool:
        """유효한 대상에 일시적 전송 실패가 남지 않았는지 반환한다."""
        return self.retryable_failure_count == 0


# 클래스명: PushNotificationBoundary
# 역할:
# - Control 계층에서 사용할 기기 푸시 전송 계약을 정의한다.
# 주요 책임:
# - 기기 토큰, 표시 문구와 화면 이동 데이터를 받아 성공 및 실패 분류 결과를 제공한다.
# 속성: 계약 자체에 저장 상태는 없으며 실제 연결·저장소는 구현체가 관리한다.
class PushNotificationBoundary(Protocol):
    # 함수이름: send_notification
    # 함수역할:
    # - 여러 기기에 동일한 알림과 화면 이동 데이터를 전송한다.
    # 매개변수:
    # - tokens (list[str]): 알림을 보낼 기기의 등록 토큰 목록.
    # - title (str): 수신 기기에 표시할 알림 제목.
    # - body (str): 수신 기기에 표시할 알림 본문.
    # - data (dict[str, str]): 푸시에 첨부할 화면 이동용 문자열 데이터.
    # 반환값:
    # - 성공 수, 무효 토큰과 재시도 가능한 실패 수를 담은 PushDeliveryResult.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult: ...


# 클래스명: DisabledPushNotificationBoundary
# 역할:
# - Firebase가 비활성화된 로컬 데모에서 푸시 요청을 안전하게 무시한다.
# 주요 책임:
# - 외부 SDK를 호출하지 않고 성공 수 0인 결과로 로컬 데모 흐름을 유지한다.
# 속성: 없음. 외부 연결이나 토큰을 저장하지 않는 무상태 구현이다.
class DisabledPushNotificationBoundary:
    # 함수이름: send_notification
    # 함수역할:
    # - 로컬 데모에서는 외부 푸시를 보내지 않고 빈 성공 결과를 반환한다.
    # 매개변수:
    # - tokens (list[str]): 알림을 보낼 기기의 등록 토큰 목록.
    # - title (str): 수신 기기에 표시할 알림 제목.
    # - body (str): 수신 기기에 표시할 알림 본문.
    # - data (dict[str, str]): 푸시에 첨부할 화면 이동용 문자열 데이터.
    # 반환값:
    # - 성공 수가 0이고 실패 항목이 없는 PushDeliveryResult.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult:
        return PushDeliveryResult(success_count=0)


# 클래스명: FirebasePushNotificationBoundary
# 역할: 보호자·연동 채팅 알림을 Firebase Admin으로 전달한다.
# 주요 책임: 토큰 중복을 제거해 최대 500개씩 전송하고 행동 버튼 지원·이벤트 그룹을 반영하며 영구 무효 토큰과 재시도 실패를 분리한다.
# 속성: _app은 공유 Firebase App, _MAX_MULTICAST_TOKENS (int)는 배치 상한이다.
class FirebasePushNotificationBoundary:
    _MAX_MULTICAST_TOKENS = 500

    # Function Name: __init__
    # Description:
    # - Reuse the configured project's Firebase Admin app for multicast notifications.
    # Parameters:
    # - project_id (str): Firebase project ID used by the shared Admin app.
    # Returns:
    # - None; the shared app is retained.
    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    # 함수이름: send_notification
    # 함수역할: 빈 토큰·중복을 제거하고 배치 전송하며 이벤트별 그룹과 지원 기기의 데이터 전용 행동 알림을 구성한다.
    # 매개변수: tokens (list[str])는 기기, title·body (str)는 표시 문구, data (dict[str, str])는 신뢰된 유형·그룹·행동 문맥이다.
    # 반환값: 성공 수·영구 무효 토큰·재시도 실패를 담은 PushDeliveryResult. 대상이 없으면 0이며 SDK 호출 자체의 오류는 전달한다.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult:
        normalized_tokens = list(
            dict.fromkeys(token.strip() for token in tokens if token.strip())
        )
        if not normalized_tokens:
            return PushDeliveryResult(success_count=0)

        event_key = data.get("event_key")
        # 같은 필요시 복용의 재전송은 기존 알림을 교체하고 다른 복용 알림은 유지한다.
        prn_notification_key = (
            event_key
            if data.get("type") == "caregiver_dose_completed"
            and data.get("slot_key") == "as_needed"
            and isinstance(event_key, str)
            and re.fullmatch(r"[0-9a-f]{64}", event_key)
            else None
        )
        # 정기 완료도 개별 아웃박스 이벤트 키로만 묶어 다른 완료 요청은 별도로 표시한다.
        notification_key = prn_notification_key or (
            event_key
            if data.get("type") == "caregiver_slot_completed"
            and data.get("slot_key") in ("morning", "lunch", "evening", "bedtime")
            and isinstance(event_key, str)
            and re.fullmatch(r"[0-9a-f]{64}", event_key)
            else None
        )
        is_chat = data.get("type") == "linked_chat_message"
        # Android 버튼은 앱의 백그라운드 수신기가 직접 그려야 하므로 OS 자동 표시를 끈다.
        data_only = data.get("action_version") == "1" and (
            data.get("type") == "caregiver_slot_missed"
            or (is_chat and data.get("message_kind") == "slot_check_request")
        )
        chat_group = data.get("chat_group", "")
        chat_count = None
        if is_chat and re.fullmatch(r"medbuddy-chat-[0-9a-f]{32}", chat_group):
            notification_key = chat_group
            try:
                chat_count = max(0, int(data.get("chat_count", "0")))
            except ValueError:
                pass
        success_count = 0
        invalid_tokens: list[str] = []
        retryable_failure_count = 0
        for offset in range(0, len(normalized_tokens), self._MAX_MULTICAST_TOKENS):
            token_batch = normalized_tokens[
                offset : offset + self._MAX_MULTICAST_TOKENS
            ]
            response = messaging.send_each_for_multicast(
                messaging.MulticastMessage(
                    tokens=token_batch,
                    notification=(None if data_only
                                  else messaging.Notification(title=title, body=body)),
                    data=data,
                    android=messaging.AndroidConfig(
                        priority="high",
                        notification=(None if data_only else messaging.AndroidNotification(
                            channel_id="medbuddy_linked_chat" if is_chat else "medbuddy_caregiver_updates",
                            tag=notification_key,
                            notification_count=chat_count,
                        )),
                    ),
                    apns=(messaging.APNSConfig(
                        headers={"apns-collapse-id": notification_key},
                        payload=(messaging.APNSPayload(messaging.Aps(thread_id=notification_key))
                                 if is_chat else None),
                    )
                          if notification_key is not None else None),
                ),
                app=self._app,
            )
            success_count += response.success_count
            for token, send_response in zip(
                token_batch,
                response.responses,
                strict=True,
            ):
                if send_response.success:
                    continue
                if isinstance(
                    send_response.exception,
                    (
                        firebase_exceptions.InvalidArgumentError,
                        messaging.UnregisteredError,
                        messaging.SenderIdMismatchError,
                    ),
                ):
                    invalid_tokens.append(token)
                else:
                    retryable_failure_count += 1

        return PushDeliveryResult(
            success_count=success_count,
            invalid_tokens=tuple(invalid_tokens),
            retryable_failure_count=retryable_failure_count,
        )
