# File Name: manage_user_setting_control.py
# Role: Control class for user display and reading settings.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.user_setting_entity import UserSetting, _UserSetting

logger = logging.getLogger(__name__)


# Class Name: ManageUserSetting
# Role: Coordinates user setting changes.
class ManageUserSetting:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestUserSetting
    # Description:
    # - Class diagram compatible wrapper for user setting retrieval.
    # Parameters:
    # - user_hash: User ownership key used to scope settings.
    # Returns:
    # - API-compatible user setting dictionary.
    def requestUserSetting(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_user_setting(user_hash)

    # Function Name: request_user_setting
    # Description:
    # - Returns persisted user settings or a default setting if none exists yet.
    # Parameters:
    # - user_hash: User ownership key used to scope settings.
    # Returns:
    # - API-compatible user setting dictionary.
    def request_user_setting(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        row = self._find_setting(normalized_user_hash)
        setting = self._to_entity(row) if row else UserSetting(user_hash=normalized_user_hash)
        return self._success_response("User setting lookup succeeded.", setting)

    # Function Name: saveUserSetting
    # Description:
    # - Class diagram compatible wrapper for user setting persistence.
    # Parameters:
    # - user_hash: User ownership key used to scope settings.
    # - font_size: Selected display font size.
    # - reading_speed: Selected voice/reading speed multiplier.
    # - language: Selected language code.
    # Returns:
    # - API-compatible saved user setting dictionary.
    def saveUserSetting(
        self,
        user_hash: str,
        font_size: int,
        reading_speed: float,
        language: str,
    ) -> dict[str, object]:
        return self.save_user_setting(user_hash, font_size, reading_speed, language)

    # Function Name: updateUserSetting
    # Description:
    # - Class diagram compatible wrapper for updating user settings.
    # Parameters:
    # - user_hash: User ownership key used to scope settings.
    # - font_size: Selected display font size.
    # - reading_speed: Selected voice/reading speed multiplier.
    # - language: Selected language code.
    # Returns:
    # - API-compatible saved user setting dictionary.
    def updateUserSetting(
        self,
        user_hash: str,
        font_size: int,
        reading_speed: float,
        language: str,
    ) -> dict[str, object]:
        return self.save_user_setting(user_hash, font_size, reading_speed, language)

    # Function Name: save_user_setting
    # Description:
    # - Creates or updates one user setting row.
    # Parameters:
    # - user_hash: User ownership key used to scope settings.
    # - font_size: Selected display font size.
    # - reading_speed: Selected voice/reading speed multiplier.
    # - language: Selected language code.
    # Returns:
    # - API-compatible saved user setting dictionary.
    def save_user_setting(
        self,
        user_hash: str,
        font_size: int,
        reading_speed: float,
        language: str,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        normalized_font_size = self._validate_font_size(font_size)
        normalized_reading_speed = self._validate_reading_speed(reading_speed)
        normalized_language = self._normalize_language(language)

        try:
            row = self._find_setting(normalized_user_hash)
            if row is None:
                row = _UserSetting(user_hash=normalized_user_hash)
                self.db.add(row)
            row.font_size = normalized_font_size
            row.reading_speed = normalized_reading_speed
            row.language = normalized_language
            self.db.commit()
            self.db.refresh(row)
            return self._success_response(
                "User setting was saved.",
                self._to_entity(row),
            )
        except IntegrityError:
            self.db.rollback()
            return self._update_existing_setting_after_conflict(
                normalized_user_hash,
                normalized_font_size,
                normalized_reading_speed,
                normalized_language,
            )
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "User setting persistence failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="User settings could not be saved.",
            ) from exc

    def _find_setting(self, user_hash: str) -> _UserSetting | None:
        return (
            self.db.query(_UserSetting)
            .filter(_UserSetting.user_hash == user_hash)
            .first()
        )

    def _update_existing_setting_after_conflict(
        self,
        user_hash: str,
        font_size: int,
        reading_speed: float,
        language: str,
    ) -> dict[str, object]:
        row = self._find_setting(user_hash)
        if row is None:
            raise HTTPException(
                status_code=409,
                detail="User setting conflict could not be resolved.",
            )
        row.font_size = font_size
        row.reading_speed = reading_speed
        row.language = language
        self.db.commit()
        self.db.refresh(row)
        return self._success_response("User setting was saved.", self._to_entity(row))

    def _validate_font_size(self, font_size: int) -> int:
        if font_size < 12 or font_size > 24:
            raise HTTPException(status_code=400, detail="Font size is invalid.")
        return font_size

    def _validate_reading_speed(self, reading_speed: float) -> float:
        if reading_speed < 0.5 or reading_speed > 2.0:
            raise HTTPException(status_code=400, detail="Reading speed is invalid.")
        return reading_speed

    def _normalize_language(self, language: str) -> str:
        normalized_language = (language or "").strip().lower()
        if normalized_language not in {"ko", "en"}:
            raise HTTPException(status_code=400, detail="Language is not supported.")
        return normalized_language

    def _to_entity(self, row: _UserSetting) -> UserSetting:
        return UserSetting(
            user_hash=row.user_hash,
            font_size=row.font_size,
            reading_speed=row.reading_speed,
            language=row.language,
        )

    def _success_response(
        self,
        message: str,
        setting: UserSetting,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": setting.to_response_dict(),
        }
