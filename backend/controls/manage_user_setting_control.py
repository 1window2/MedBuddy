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
    # - Returns persisted user settings or a default setting if none exists yet.
    # Parameters:
    # - user_hash: User ownership key used to scope settings.
    # Returns:
    # - API-compatible user setting dictionary.
    def requestUserSetting(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        row = self._find_setting(normalized_user_hash)
        setting = self._to_entity(row) if row else UserSetting(user_hash=normalized_user_hash)
        return self._success_response("User setting lookup succeeded.", setting)

    # Function Name: saveUserSetting
    # Description:
    # - Creates or updates one user setting row.
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
        language_mode: str = "ko",
        time_format: str = "24h",
        medication_notifications_enabled: bool = True,
        caregiver_notifications_enabled: bool = True,
        chat_notifications_enabled: bool = True,
        notification_detail_mode: str = "full",
        default_morning_time: str = "08:00",
        default_lunch_time: str = "12:00",
        default_evening_time: str = "18:00",
        default_bedtime: str = "22:00",
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        normalized_font_size = self._validate_font_size(font_size)
        normalized_reading_speed = self._validate_reading_speed(reading_speed)
        normalized_language = self._normalize_language(language)
        normalized_language_mode = self._normalize_language_mode(language_mode)
        normalized_time_format = self._normalize_time_format(time_format)
        normalized_detail_mode = self._normalize_notification_detail_mode(
            notification_detail_mode
        )
        normalized_default_times = {
            "morning": self._normalize_time(default_morning_time),
            "lunch": self._normalize_time(default_lunch_time),
            "evening": self._normalize_time(default_evening_time),
            "bedtime": self._normalize_time(default_bedtime),
        }

        try:
            row = self._find_setting(normalized_user_hash)
            if row is None:
                row = _UserSetting(user_hash=normalized_user_hash)
                self.db.add(row)
            next_setting = self._to_entity(row).updateUserSetting(
                normalized_font_size,
                normalized_reading_speed,
                normalized_language,
                normalized_language_mode,
                normalized_time_format,
                medication_notifications_enabled,
                caregiver_notifications_enabled,
                chat_notifications_enabled,
                normalized_detail_mode,
                normalized_default_times["morning"],
                normalized_default_times["lunch"],
                normalized_default_times["evening"],
                normalized_default_times["bedtime"],
            )
            row.font_size = next_setting.font_size
            row.reading_speed = next_setting.reading_speed
            row.language = next_setting.language
            self._apply_extended_setting(row, next_setting)
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
                normalized_language_mode,
                normalized_time_format,
                medication_notifications_enabled,
                caregiver_notifications_enabled,
                chat_notifications_enabled,
                normalized_detail_mode,
                normalized_default_times,
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
        language_mode: str,
        time_format: str,
        medication_notifications_enabled: bool,
        caregiver_notifications_enabled: bool,
        chat_notifications_enabled: bool,
        notification_detail_mode: str,
        default_times: dict[str, str],
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
        next_setting = self._to_entity(row).updateUserSetting(
            font_size,
            reading_speed,
            language,
            language_mode,
            time_format,
            medication_notifications_enabled,
            caregiver_notifications_enabled,
            chat_notifications_enabled,
            notification_detail_mode,
            default_times["morning"],
            default_times["lunch"],
            default_times["evening"],
            default_times["bedtime"],
        )
        self._apply_extended_setting(row, next_setting)
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

    # 함수명: _normalize_language_mode
    # 역할: 기기 설정 따르기를 포함한 언어 선택 모드를 검증한다.
    def _normalize_language_mode(self, language_mode: str) -> str:
        normalized_mode = (language_mode or "").strip().lower()
        if normalized_mode not in {"system", "ko", "en"}:
            raise HTTPException(status_code=400, detail="Language mode is invalid.")
        return normalized_mode

    # 함수명: _normalize_time_format
    # 역할: 화면에 표시할 12시간제 또는 24시간제 값을 검증한다.
    def _normalize_time_format(self, time_format: str) -> str:
        normalized_format = (time_format or "").strip().lower()
        if normalized_format not in {"12h", "24h"}:
            raise HTTPException(status_code=400, detail="Time format is invalid.")
        return normalized_format

    # 함수명: _normalize_notification_detail_mode
    # 역할: 잠금 화면에서 민감한 알림 내용을 표시할지 검증한다.
    def _normalize_notification_detail_mode(self, detail_mode: str) -> str:
        normalized_mode = (detail_mode or "").strip().lower()
        if normalized_mode not in {"full", "type_only"}:
            raise HTTPException(
                status_code=400,
                detail="Notification detail mode is invalid.",
            )
        return normalized_mode

    # 함수명: _normalize_time
    # 역할: 기본 복약 시각을 HH:mm 형식으로 정규화한다.
    def _normalize_time(self, value: str) -> str:
        parts = str(value or "").strip().split(":")
        if len(parts) != 2:
            raise HTTPException(status_code=400, detail="Default time is invalid.")
        try:
            hour = int(parts[0])
            minute = int(parts[1])
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail="Default time is invalid.",
            ) from exc
        if not 0 <= hour <= 23 or not 0 <= minute <= 59:
            raise HTTPException(status_code=400, detail="Default time is invalid.")
        return f"{hour:02d}:{minute:02d}"

    def _to_entity(self, row: _UserSetting) -> UserSetting:
        return UserSetting(
            user_hash=row.user_hash,
            font_size=row.font_size if row.font_size is not None else 16,
            reading_speed=(
                row.reading_speed if row.reading_speed is not None else 1.0
            ),
            language=row.language or "ko",
            language_mode=row.language_mode or row.language or "ko",
            time_format=row.time_format or "24h",
            medication_notifications_enabled=(
                row.medication_notifications_enabled is not False
            ),
            caregiver_notifications_enabled=(
                row.caregiver_notifications_enabled is not False
            ),
            chat_notifications_enabled=row.chat_notifications_enabled is not False,
            notification_detail_mode=row.notification_detail_mode or "full",
            default_morning_time=row.default_morning_time or "08:00",
            default_lunch_time=row.default_lunch_time or "12:00",
            default_evening_time=row.default_evening_time or "18:00",
            default_bedtime=row.default_bedtime or "22:00",
        )

    # 함수명: _apply_extended_setting
    # 역할: 알림, 개인정보, 기본 복약 시각과 표시 설정을 DB 행에 반영한다.
    def _apply_extended_setting(
        self,
        row: _UserSetting,
        setting: UserSetting,
    ) -> None:
        row.language_mode = setting.language_mode
        row.time_format = setting.time_format
        row.medication_notifications_enabled = (
            setting.medication_notifications_enabled
        )
        row.caregiver_notifications_enabled = (
            setting.caregiver_notifications_enabled
        )
        row.chat_notifications_enabled = setting.chat_notifications_enabled
        row.notification_detail_mode = setting.notification_detail_mode
        row.default_morning_time = setting.default_morning_time
        row.default_lunch_time = setting.default_lunch_time
        row.default_evening_time = setting.default_evening_time
        row.default_bedtime = setting.default_bedtime

    def _success_response(
        self,
        message: str,
        setting: UserSetting,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": setting.getUserSetting(),
        }
