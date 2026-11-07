# File Name: push_recipient_resolver.py
# Role: Single owner of how a push recipient is read: notification preferences and enabled
#   device tokens, shared by the caregiver completion, missed-dose and chat dispatchers.

import logging
from dataclasses import dataclass

from sqlalchemy import tuple_
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from entities.device_push_token_entity import _DevicePushToken
from entities.user_setting_entity import _UserSetting

logger = logging.getLogger(__name__)

_TYPE_ONLY_DETAIL_MODE = "type_only"


# 클래스명: PushRecipient
# 역할: 세션 연결 해제 뒤에도 읽을 수 있는 수신 계정의 푸시 정보를 보관한다.
# 주요 책임: 일반 토큰과 보호자 행동·환자 복용 확인 행동 지원 토큰 및 표시 설정을 분리한다.
# 속성: user_hash는 str, tokens는 tuple[str], action_tokens·slot_check_action_tokens는 frozenset[str]다.
#   language는 en/ko, show_details·caregiver_enabled·chat_enabled는 미리보기·보호자·채팅 허용 bool이다.
@dataclass(frozen=True)
class PushRecipient:
    user_hash: str
    tokens: tuple[str, ...]
    action_tokens: frozenset[str]
    slot_check_action_tokens: frozenset[str]
    language: str
    show_details: bool
    caregiver_enabled: bool
    chat_enabled: bool


# Class Name: _RecipientPreferences
# Role: The push-related values of one user_settings row.
# Responsibilities:
# - Carry the defaults of an account without a settings row: Korean, details shown, every
#   notification kind wanted.
# Attributes:
# - language (str): Notification language, "en" or "ko".
# - show_details (bool): Whether detailed wording may be shown.
# - caregiver_enabled (bool): Whether caregiver medication alerts are wanted.
# - chat_enabled (bool): Whether chat notifications are wanted.
@dataclass(frozen=True)
class _RecipientPreferences:
    language: str
    show_details: bool
    caregiver_enabled: bool
    chat_enabled: bool


# Class Name: PushRecipientResolver
# Role: Resolves push recipients with one rule set for every dispatcher.
# Responsibilities:
# - Read an account's preferences and enabled tokens, each at most once per instance.
# - Disable tokens Firebase rejected, in a short transaction of their own.
# Attributes:
# - db (Session): SQLAlchemy session of the current work.
# - _preferences (dict[str, _RecipientPreferences]): Preferences already read, by account.
# - _tokens (dict[str, tuple[tuple[str, bool, bool], ...]]): (token, supports caregiver actions,
#   supports slot-check actions) triples already read, by account.
# Note: Use one instance for one dispatch only. A longer-lived instance would not see a
#   preference change or a token that moved to another account in the meantime.
class PushRecipientResolver:
    # 함수이름: __init__
    # 함수역할: 요청 세션을 연결하고 설정·토큰·등록 세대 캐시를 빈 상태로 시작한다.
    # 매개변수: db (Session)는 현재 전송 작업의 세션이다.
    # 반환값: None. 생성 시 DB를 조회하지 않는다.
    def __init__(self, db: Session) -> None:
        self.db = db
        self._preferences: dict[str, _RecipientPreferences] = {}
        self._tokens: dict[str, tuple[tuple[str, bool, bool], ...]] = {}
        self._token_versions: dict[str, tuple[int, str, str]] = {}

    # 함수이름: resolve
    # 함수역할: 수신 계정의 설정·활성 토큰을 재사용 가능한 일반 값으로 묶고 행동 지원 토큰을 별도 집합으로 구분한다.
    # 매개변수: user_hash (str)는 수신 계정이다.
    # 반환값: PushRecipient. 활성 기기가 없으면 tokens는 빈 tuple이며 DB 오류는 전달한다.
    def resolve(self, user_hash: str) -> PushRecipient:
        preferences = self._read_preferences(user_hash)
        tokens = self._read_tokens(user_hash)
        return PushRecipient(
            user_hash=user_hash,
            tokens=tuple(token for token, _, _ in tokens),
            action_tokens=frozenset(
                token for token, supports_actions, _ in tokens if supports_actions
            ),
            slot_check_action_tokens=frozenset(
                token for token, _, supports_slot_check in tokens if supports_slot_check
            ),
            language=preferences.language,
            show_details=preferences.show_details,
            caregiver_enabled=preferences.caregiver_enabled,
            chat_enabled=preferences.chat_enabled,
        )

    # Function Name: caregiver_alerts_enabled
    # Description:
    # - Checks the account-wide caregiver alert switch without reading device tokens.
    # Parameters:
    # - user_hash (str): Caregiver account.
    # Returns:
    # - True when there is no settings row or caregiver alerts are switched on.
    def caregiver_alerts_enabled(self, user_hash: str) -> bool:
        return self._read_preferences(user_hash).caregiver_enabled

    # Function Name: notification_display
    # Description:
    # - Returns how an account wants notification text shown, without reading device tokens.
    # Parameters:
    # - user_hash (str): Recipient account.
    # Returns:
    # - (language, show_details); "ko" and True when there is no settings row.
    def notification_display(self, user_hash: str) -> tuple[str, bool]:
        preferences = self._read_preferences(user_hash)
        return preferences.language, preferences.show_details

    # 함수이름: disable_invalid
    # 함수역할: 전송 전에 관찰한 동일 ID·소유 계정·등록 세대의 무효 토큰만 비활성화해 이후 재등록·계정 전환을 보존한다.
    # 매개변수: invalid_tokens (tuple[str])는 제공자가 영구 무효로 거절한 토큰이다.
    # 반환값: None. 관찰한 등록이 없으면 생략하며 DB·롤백 오류는 기록하고 삼켜 이미 보낸 알림이 재전송되지 않게 한다.
    def disable_invalid(self, invalid_tokens: tuple[str, ...]) -> None:
        rejected_tokens = tuple(dict.fromkeys(invalid_tokens))
        if not rejected_tokens:
            return
        # 실제 전송 전에 관찰한 등록만 해제하며, 이후 계정 전환·재등록은 보존한다.
        versions = [
            (version[0], token, version[1], version[2])
            for token in rejected_tokens
            if (version := self._token_versions.pop(token, None)) is not None
        ]
        if not versions:
            return
        for user_hash, tokens in self._tokens.items():
            self._tokens[user_hash] = tuple(
                entry for entry in tokens if entry[0] not in rejected_tokens
            )
        try:
            self.db.query(_DevicePushToken).filter(
                tuple_(
                    _DevicePushToken.id, _DevicePushToken.token,
                    _DevicePushToken.user_hash, _DevicePushToken.registration_version,
                ).in_(versions),
                _DevicePushToken.enabled.is_(True),
            ).update({"enabled": False}, synchronize_session=False)
            self.db.commit()
        except SQLAlchemyError as exc:
            logger.warning(
                "Rejected push tokens could not be disabled: %s",
                type(exc).__name__,
            )
            try:
                self.db.rollback()
            except SQLAlchemyError as rollback_exc:
                logger.warning(
                    "Push token cleanup could not be rolled back: %s",
                    type(rollback_exc).__name__,
                )

    # Function Name: _read_preferences
    # Description:
    # - Reads the push-related settings columns of one account and remembers the result.
    # - An account without a settings row keeps receiving detailed Korean notifications.
    # Parameters:
    # - user_hash (str): Recipient account.
    # Returns:
    # - Language, detail visibility and the per-kind switches.
    def _read_preferences(self, user_hash: str) -> _RecipientPreferences:
        preferences = self._preferences.get(user_hash)
        if preferences is not None:
            return preferences
        row = (
            self.db.query(
                _UserSetting.language,
                _UserSetting.notification_detail_mode,
                _UserSetting.caregiver_notifications_enabled,
                _UserSetting.chat_notifications_enabled,
            )
            .filter(_UserSetting.user_hash == user_hash)
            .first()
        )
        if row is None:
            preferences = _RecipientPreferences(
                language="ko",
                show_details=True,
                caregiver_enabled=True,
                chat_enabled=True,
            )
        else:
            preferences = _RecipientPreferences(
                language=(
                    "en"
                    if str(row.language or "").strip().lower() == "en"
                    else "ko"
                ),
                show_details=row.notification_detail_mode != _TYPE_ONLY_DETAIL_MODE,
                caregiver_enabled=bool(row.caregiver_notifications_enabled),
                chat_enabled=bool(row.chat_notifications_enabled),
            )
        self._preferences[user_hash] = preferences
        return preferences

    # 함수이름: _read_tokens
    # 함수역할: 계정의 활성 토큰과 행동 기능을 한 번 읽어 캐시하고 나중의 무효 정리를 위해 등록 세대를 기억한다.
    # 매개변수: user_hash (str)는 수신 계정이다.
    # 반환값: (토큰 str, 보호자 행동 bool, 복용 확인 행동 bool) tuple. 복용 확인 행동은 Android 기기만 허용한다.
    def _read_tokens(self, user_hash: str) -> tuple[tuple[str, bool, bool], ...]:
        tokens = self._tokens.get(user_hash)
        if tokens is not None:
            return tokens
        rows = (
            self.db.query(
                _DevicePushToken.id,
                _DevicePushToken.token,
                _DevicePushToken.supports_caregiver_actions,
                _DevicePushToken.supports_slot_check_actions,
                _DevicePushToken.platform,
                _DevicePushToken.registration_version,
            )
            .filter(
                _DevicePushToken.user_hash == user_hash,
                _DevicePushToken.enabled.is_(True),
            )
            .all()
        )
        tokens = tuple((str(row.token), bool(row.supports_caregiver_actions),
                        bool(row.supports_slot_check_actions) and row.platform == "android") for row in rows)
        for row in rows:
            self._token_versions[str(row.token)] = (int(row.id), user_hash, row.registration_version)
        self._tokens[user_hash] = tokens
        return tokens
