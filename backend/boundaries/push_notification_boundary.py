# 파일명: push_notification_boundary.py
# 역할: 보호자 알림 유스케이스와 Firebase Cloud Messaging SDK를 분리한다.

import logging
from dataclasses import dataclass
from typing import Protocol

from firebase_admin import messaging

from boundaries.firebase_admin_boundary import get_firebase_admin_app

logger = logging.getLogger(__name__)


# 클래스명: PushDeliveryResult
# 역할: 푸시 전송 성공 개수와 더 이상 사용할 수 없는 토큰을 전달한다.
@dataclass(frozen=True)
class PushDeliveryResult:
    success_count: int
    invalid_tokens: tuple[str, ...] = ()


# 클래스명: PushNotificationBoundary
# 역할: Control 계층에서 사용할 기기 푸시 전송 계약을 정의한다.
class PushNotificationBoundary(Protocol):
    # 함수명: send_notification
    # 역할:
    # - 여러 기기에 동일한 알림과 화면 이동 데이터를 전송한다.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult: ...


# 클래스명: DisabledPushNotificationBoundary
# 역할: Firebase가 비활성화된 로컬 데모에서 푸시 요청을 안전하게 무시한다.
class DisabledPushNotificationBoundary:
    # 함수명: send_notification
    # 역할:
    # - 로컬 데모에서는 외부 푸시를 보내지 않고 빈 성공 결과를 반환한다.
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
# 역할: Firebase Admin SDK를 통해 보호자 기기에 FCM 알림을 전송한다.
# 주요 책임:
#   - 애플리케이션 전용 Firebase Admin 인스턴스를 재사용한다.
#   - 최대 500개 단위로 토큰을 묶어 알림을 전송한다.
#   - 더 이상 유효하지 않은 토큰을 Control 계층에 반환한다.
class FirebasePushNotificationBoundary:
    _MAX_MULTICAST_TOKENS = 500

    # 함수명: __init__
    # 역할:
    # - Firebase Admin 앱을 생성하거나 기존 전용 앱을 재사용한다.
    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    # 함수명: send_notification
    # 역할:
    # - 중복 토큰을 제거하고 Firebase 제한 단위로 나눠 푸시를 전송한다.
    # 반환값:
    # - 성공 개수와 비활성화할 토큰 목록
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

        success_count = 0
        invalid_tokens: list[str] = []
        for offset in range(0, len(normalized_tokens), self._MAX_MULTICAST_TOKENS):
            token_batch = normalized_tokens[
                offset : offset + self._MAX_MULTICAST_TOKENS
            ]
            response = messaging.send_each_for_multicast(
                messaging.MulticastMessage(
                    tokens=token_batch,
                    notification=messaging.Notification(title=title, body=body),
                    data=data,
                    android=messaging.AndroidConfig(
                        priority="high",
                        notification=messaging.AndroidNotification(
                            channel_id="medbuddy_caregiver_updates",
                        ),
                    ),
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
                    (messaging.UnregisteredError, messaging.SenderIdMismatchError),
                ):
                    invalid_tokens.append(token)

        return PushDeliveryResult(
            success_count=success_count,
            invalid_tokens=tuple(invalid_tokens),
        )
