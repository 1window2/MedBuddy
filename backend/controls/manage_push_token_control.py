# 파일명: manage_push_token_control.py
# 역할: 인증된 사용자의 FCM 기기 토큰 등록과 해제를 처리한다.

import logging

from sqlalchemy.orm import Session

from entities.device_push_token_entity import _DevicePushToken
from entities.patient_hash_entity import normalize_patient_hash

logger = logging.getLogger(__name__)


# 클래스명: ManagePushToken
# 역할: 사용자별 기기 푸시 토큰 생명주기를 관리한다.
# 주요 책임:
#   - 새 토큰을 현재 인증 사용자에게 등록한다.
#   - 다른 계정에서 사용되던 갱신 토큰의 소유권을 안전하게 교체한다.
#   - 로그아웃한 기기의 토큰을 비활성화한다.
class ManagePushToken:
    # 함수명: __init__
    # 역할:
    # - 요청 범위의 DB 세션을 푸시 토큰 관리 Control에 연결한다.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: registerPushToken
    # 역할:
    # - 기기 토큰을 현재 인증 사용자에게 등록하고 기존 토큰이면 소유권과 상태를 갱신한다.
    # 매개변수:
    # - user_hash: 현재 인증 사용자의 식별 hash
    # - token: Firebase Cloud Messaging이 발급한 기기 토큰
    # - platform: 토큰이 발급된 모바일 플랫폼
    # 반환값:
    # - 등록 성공 여부와 활성 상태
    def registerPushToken(
        self,
        user_hash: str,
        token: str,
        platform: str,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        normalized_token = token.strip()
        normalized_platform = platform.strip().lower()
        push_token = (
            self.db.query(_DevicePushToken)
            .filter(_DevicePushToken.token == normalized_token)
            .first()
        )
        if push_token is None:
            push_token = _DevicePushToken(
                user_hash=normalized_user_hash,
                token=normalized_token,
                platform=normalized_platform,
                enabled=True,
            )
            self.db.add(push_token)
        else:
            push_token.user_hash = normalized_user_hash
            push_token.platform = normalized_platform
            push_token.enabled = True

        self.db.commit()
        self.db.refresh(push_token)
        return {
            "success": True,
            "message": "Push token was registered.",
            "data": {"platform": push_token.platform, "enabled": push_token.enabled},
        }

    # 함수명: unregisterPushToken
    # 역할:
    # - 현재 인증 사용자와 일치하는 기기 토큰을 비활성화한다.
    # 매개변수:
    # - user_hash: 현재 인증 사용자의 식별 hash
    # - token: 비활성화할 기기 토큰
    # 반환값:
    # - 해제 요청 처리 결과
    def unregisterPushToken(
        self,
        user_hash: str,
        token: str,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        normalized_token = token.strip()
        push_token = (
            self.db.query(_DevicePushToken)
            .filter(
                _DevicePushToken.user_hash == normalized_user_hash,
                _DevicePushToken.token == normalized_token,
            )
            .first()
        )
        if push_token is not None:
            push_token.enabled = False
            self.db.commit()
        return {
            "success": True,
            "message": "Push token was unregistered.",
        }
