# File Name: push_recipient_resolver.py
# Role: Single owner of how a push recipient is read: notification preferences and enabled
#   device tokens, shared by the caregiver completion, missed-dose and chat dispatchers.

import logging
from dataclasses import dataclass

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from entities.device_push_token_entity import _DevicePushToken
from entities.user_setting_entity import _UserSetting

logger = logging.getLogger(__name__)

_TYPE_ONLY_DETAIL_MODE = "type_only"


# Class Name: PushRecipient
# Role: Everything a dispatcher needs to push to one account, detached from the session.
# Responsibilities:
# - Hold plain values only, so it stays readable after the session released its connection.
# Attributes:
# - user_hash (str): Recipient account.
# - tokens (tuple[str, ...]): Enabled device tokens of the account.
# - action_tokens (frozenset[str]): The tokens whose device renders caregiver action data itself.
# - language (str): Notification language, "en" or "ko".
# - show_details (bool): False when the account chose the "type_only" privacy mode.
# - caregiver_enabled (bool): Whether caregiver medication alerts are wanted.
# - chat_enabled (bool): Whether chat notifications are wanted.
@dataclass(frozen=True)
class PushRecipient:
    user_hash: str
    tokens: tuple[str, ...]
    action_tokens: frozenset[str]
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
# - _tokens (dict[str, tuple[tuple[str, bool], ...]]): (token, supports actions) pairs already
#   read, by account.
# Note: Use one instance for one dispatch only. A longer-lived instance would not see a
#   preference change or a token that moved to another account in the meantime.
class PushRecipientResolver:
    # Function Name: __init__
    # Description:
    # - Binds the session and starts with nothing read.
    # Parameters:
    # - db (Session): SQLAlchemy session of the current work.
    # Returns:
    # - None.
    def __init__(self, db: Session) -> None:
        self.db = db
        self._preferences: dict[str, _RecipientPreferences] = {}
        self._tokens: dict[str, tuple[tuple[str, bool], ...]] = {}

    # Function Name: resolve
    # Description:
    # - Returns the preferences and enabled device tokens of one account as plain values.
    # Parameters:
    # - user_hash (str): Recipient account.
    # Returns:
    # - PushRecipient; tokens is empty when the account has no enabled device.
    def resolve(self, user_hash: str) -> PushRecipient:
        preferences = self._read_preferences(user_hash)
        tokens = self._read_tokens(user_hash)
        return PushRecipient(
            user_hash=user_hash,
            tokens=tuple(token for token, _ in tokens),
            action_tokens=frozenset(
                token for token, supports_actions in tokens if supports_actions
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

    # Function Name: disable_invalid
    # Description:
    # - Disables tokens Firebase rejected as expired or mismatched and commits at once.
    # - Runs after the push has left, so a database error is logged and not raised: raising
    #   would make the caller send the same notification again. A token left enabled is
    #   rejected and cleaned up on the next send.
    # Parameters:
    # - invalid_tokens (tuple[str, ...]): Tokens rejected by Firebase.
    # Returns:
    # - None.
    def disable_invalid(self, invalid_tokens: tuple[str, ...]) -> None:
        rejected_tokens = tuple(dict.fromkeys(invalid_tokens))
        if not rejected_tokens:
            return
        for user_hash, tokens in self._tokens.items():
            self._tokens[user_hash] = tuple(
                entry for entry in tokens if entry[0] not in rejected_tokens
            )
        try:
            self.db.query(_DevicePushToken).filter(
                _DevicePushToken.token.in_(rejected_tokens)
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

    # Function Name: _read_tokens
    # Description:
    # - Reads the enabled device tokens of one account and remembers the result.
    # Parameters:
    # - user_hash (str): Recipient account.
    # Returns:
    # - (token, supports caregiver actions) pairs.
    def _read_tokens(self, user_hash: str) -> tuple[tuple[str, bool], ...]:
        tokens = self._tokens.get(user_hash)
        if tokens is not None:
            return tokens
        tokens = tuple(
            (str(row.token), bool(row.supports_caregiver_actions))
            for row in (
                self.db.query(
                    _DevicePushToken.token,
                    _DevicePushToken.supports_caregiver_actions,
                )
                .filter(
                    _DevicePushToken.user_hash == user_hash,
                    _DevicePushToken.enabled.is_(True),
                )
                .all()
            )
        )
        self._tokens[user_hash] = tokens
        return tokens
