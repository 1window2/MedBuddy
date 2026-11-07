# 파일명: manage_push_token_control.py
# 역할: 인증된 사용자의 FCM 기기 토큰 등록과 해제를 처리한다.

import logging
import secrets
from datetime import datetime

from sqlalchemy.orm import Session

from entities.device_push_token_entity import _DevicePushToken
from entities.patient_hash_entity import normalize_patient_hash

logger = logging.getLogger(__name__)


# 클래스명: ManagePushToken
# 역할:
# - 사용자별 기기 푸시 토큰 생명주기를 관리한다.
# 주요 책임:
# - 새 토큰을 현재 인증 사용자에게 등록한다.
# - 다른 계정에서 사용되던 갱신 토큰의 소유권을 안전하게 교체한다.
# - 로그아웃한 기기의 토큰을 비활성화한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
class ManagePushToken:
    # 함수이름: __init__
    # 함수역할:
    # - 요청 범위의 DB 세션을 푸시 토큰 관리 Control에 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # 반환값:
    # - 없음.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: registerPushToken
    # 함수역할: 토큰을 현재 계정에 등록·재활성화하고 새 등록 세대를 발급하며 취소된 세션에 속한 오래된 다른 토큰을 비활성화한다.
    # 매개변수: user_hash (str)는 인증 계정, token (str)은 FCM 토큰, platform (str)은 기기 플랫폼이다.
    #   supports_caregiver_actions·supports_slot_check_actions (bool)는 행동 지원이며 복용 확인 행동은 Android만 허용한다.
    #   sessions_valid_after (datetime | None)는 다른 토큰의 오래된 등록을 차단할 세션 유효 기준이다.
    # 반환값: platform·enabled 성공 응답. commit·refresh 오류는 전달하며 입력 형식·권한은 상위 경계에서 검증한다.
    def registerPushToken(
        self,
        user_hash: str,
        token: str,
        platform: str,
        supports_caregiver_actions: bool = False,
        sessions_valid_after: datetime | None = None,
        supports_slot_check_actions: bool = False,
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

        push_token.supports_caregiver_actions = supports_caregiver_actions
        # 구버전 재등록·앱 다운그레이드는 새 기능을 끄며 Android만 직접 표시한다.
        push_token.supports_slot_check_actions = (
            supports_slot_check_actions and normalized_platform == "android"
        )
        # 같은 계정의 재등록도 이전 전송 결과와 구분할 수 있게 갱신한다.
        push_token.registration_version = secrets.token_hex(16)
        if sessions_valid_after is not None:
            # 앱은 시작할 때마다 토큰을 다시 등록한다. 세션 취소(비밀번호 변경 등) 뒤로 한 번도 다시
            # 등록되지 않은 같은 계정의 기기는 취소된 세션의 기기이므로 더 이상 알림을 보내지 않는다.
            self.db.query(_DevicePushToken).filter(
                _DevicePushToken.user_hash == normalized_user_hash,
                _DevicePushToken.token != normalized_token,
                _DevicePushToken.enabled.is_(True),
                _DevicePushToken.updated_at < sessions_valid_after,
            ).update({"enabled": False}, synchronize_session=False)
        self.db.commit()
        self.db.refresh(push_token)
        return {
            "success": True,
            "message": "Push token was registered.",
            "data": {"platform": push_token.platform, "enabled": push_token.enabled},
        }

    # 함수이름: unregisterPushToken
    # 함수역할:
    # - 현재 인증 사용자와 일치하는 기기 토큰을 비활성화한다.
    # 매개변수:
    # - user_hash (str): 현재 인증 사용자의 식별 hash
    # - token (str): 비활성화할 기기 토큰
    # 반환값:
    # - 해제 요청 처리 결과
    def unregisterPushToken(
        self,
        user_hash: str,
        token: str,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        normalized_token = token.strip()
        # 소유권 확인과 해제를 함께 처리하여 계정 전환 직후의 토큰을 끄지 않는다.
        (
            self.db.query(_DevicePushToken)
            .filter(
                _DevicePushToken.user_hash == normalized_user_hash,
                _DevicePushToken.token == normalized_token,
                _DevicePushToken.enabled.is_(True),
            )
            .update({"enabled": False}, synchronize_session=False)
        )
        self.db.commit()
        return {
            "success": True,
            "message": "Push token was unregistered.",
        }
