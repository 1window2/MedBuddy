# 파일명: push_notification_boundary.py
# 역할: 보호자 알림 유스케이스와 Firebase Cloud Messaging SDK를 분리한다.

import logging
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


# Class Name: FirebasePushNotificationBoundary
# Role:
# - Sends caregiver FCM notifications through Firebase Admin.
# Responsibilities:
# - Reuse the application-specific Admin app.
# - Deduplicate and batch at most 500 tokens per multicast.
# - Return invalid tokens for control-layer cleanup and count retryable failures.
# Attributes:
# - _app (App): Shared Firebase Admin app.
# - _MAX_MULTICAST_TOKENS (int): Provider batch-size limit.
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

    # Function Name: send_notification
    # Description:
    # - Deduplicate nonblank tokens, send high-priority FCM batches and classify permanent versus retryable per-device failures.
    # Parameters:
    # - tokens (list[str]): Device registration tokens targeted by this notification.
    # - title (str): Notification title displayed on the receiving device.
    # - body (str): Notification text displayed on the receiving device.
    # - data (dict[str, str]): String-valued routing data attached to the push notification.
    # Returns:
    # - Success count, permanently invalid tokens and retryable failure count; an empty target set yields zero counts.
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
        retryable_failure_count = 0
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
