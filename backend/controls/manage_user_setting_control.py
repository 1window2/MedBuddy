# File Name: manage_user_setting_control.py
# Role: Validates and persists account accessibility, language, notification and default reminder-time preferences.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.user_setting_entity import UserSetting, _UserSetting

logger = logging.getLogger(__name__)


# 클래스명: ManageUserSetting
# 역할:
# - 사용자별 접근성·언어·기본 복약 시각과 알림 표시 설정을 검증하고 저장한다.
# 주요 책임:
# - 입력 허용 범위를 확인하고 기존 설정을 기본값으로 보완하며 동시 생성 충돌 뒤에는 기존 행을 갱신한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
class ManageUserSetting:
    # Function Name: __init__
    # Description:
    # - Binds user preference reads and writes to the supplied database session.
    # Parameters:
    # - db (Session): SQLAlchemy session for this unit of work.
    # Returns:
    # - None.
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestUserSetting
    # Description:
    # - Returns persisted user settings or a default setting if none exists yet.
    # Parameters:
    # - user_hash (str): User ownership key used to scope settings.
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

    # 함수이름: saveUserSetting
    # 함수역할:
    # - 접근성·언어·시각·알림 옵션을 검증해 저장하고 동시 생성 충돌은 기존 행 갱신으로 복구한다.
    # 매개변수:
    # - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
    # - font_size (int): 지원하는 접근성 범위의 표시 글자 크기.
    # - reading_speed (float): 음성 읽기 속도 배율.
    # - language (str): 요청한 한국어 또는 영어 콘텐츠 언어.
    # - language_mode (str): 명시적 언어 또는 시스템 언어 사용 설정.
    # - time_format (str): 사용자가 선택한 12시간제·24시간제 표시.
    # - medication_notifications_enabled (bool): 복약 알림 전체 활성 여부.
    # - caregiver_notifications_enabled (bool): 보호자 알림 전체 활성 여부.
    # - chat_notifications_enabled (bool): 새 채팅 메시지 알림 전체 활성 여부.
    # - notification_detail_mode (str): 알림 미리보기의 전체 내용·종류만 표시 모드.
    # - default_morning_time (str): HH:MM 형식의 기본 아침 알림 시각.
    # - default_lunch_time (str): HH:MM 형식의 기본 점심 알림 시각.
    # - default_evening_time (str): HH:MM 형식의 기본 저녁 알림 시각.
    # - default_bedtime (str): HH:MM 형식의 기본 취침 전 알림 시각.
    # 반환값:
    # - 저장된 사용자 설정을 담은 성공 응답.
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

    # Function Name: _find_setting
    # Description:
    # - Finds the preference row belonging to one user scope.
    # Parameters:
    # - user_hash (str): Account ownership scope for the operation.
    # Returns:
    # - Stored setting row, or None before the first save.
    def _find_setting(self, user_hash: str) -> _UserSetting | None:
        return (
            self.db.query(_UserSetting)
            .filter(_UserSetting.user_hash == user_hash)
            .first()
        )

    # 함수이름: _update_existing_setting_after_conflict
    # 함수역할:
    # - 동시 생성으로 이미 생긴 사용자 설정 행을 다시 조회해 요청 값을 적용한다.
    # 매개변수:
    # - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
    # - font_size (int): 지원하는 접근성 범위의 표시 글자 크기.
    # - reading_speed (float): 음성 읽기 속도 배율.
    # - language (str): 요청한 한국어 또는 영어 콘텐츠 언어.
    # - language_mode (str): 명시적 언어 또는 시스템 언어 사용 설정.
    # - time_format (str): 사용자가 선택한 12시간제·24시간제 표시.
    # - medication_notifications_enabled (bool): 복약 알림 전체 활성 여부.
    # - caregiver_notifications_enabled (bool): 보호자 알림 전체 활성 여부.
    # - chat_notifications_enabled (bool): 새 채팅 메시지 알림 전체 활성 여부.
    # - notification_detail_mode (str): 알림 미리보기의 전체 내용·종류만 표시 모드.
    # - default_times (dict[str, str]): 복용 시간대별 기본 알림 시각.
    # 반환값:
    # - 저장된 설정 응답; 충돌 행이 없으면 HTTP 409.
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

    # Function Name: _validate_font_size
    # Description:
    # - Rejects font sizes outside the supported 12-24 range.
    # Parameters:
    # - font_size (int): Display font size in the supported accessibility range.
    # Returns:
    # - Accepted font size, or HTTP 400 for an invalid value.
    def _validate_font_size(self, font_size: int) -> int:
        if font_size < 12 or font_size > 24:
            raise HTTPException(status_code=400, detail="Font size is invalid.")
        return font_size

    # Function Name: _validate_reading_speed
    # Description:
    # - Rejects reading-speed multipliers outside 0.5-2.0.
    # Parameters:
    # - reading_speed (float): Speech/reading speed multiplier.
    # Returns:
    # - Accepted speed multiplier, or HTTP 400 for an invalid value.
    def _validate_reading_speed(self, reading_speed: float) -> float:
        if reading_speed < 0.5 or reading_speed > 2.0:
            raise HTTPException(status_code=400, detail="Reading speed is invalid.")
        return reading_speed

    # Function Name: _normalize_language
    # Description:
    # - Trims and lowercases language input and requires ko or en.
    # Parameters:
    # - language (str): Requested Korean or English content language.
    # Returns:
    # - Supported language code, or HTTP 400.
    def _normalize_language(self, language: str) -> str:
        normalized_language = (language or "").strip().lower()
        if normalized_language not in {"ko", "en"}:
            raise HTTPException(status_code=400, detail="Language is not supported.")
        return normalized_language

    # 함수이름: _normalize_language_mode
    # 함수역할:
    # - 기기 설정 따르기를 포함한 언어 선택 모드를 검증한다.
    # 매개변수:
    # - language_mode (str): 명시적 언어 또는 시스템 언어 사용 설정.
    # 반환값:
    # - system, ko, en 중 정규화된 언어 모드; 미지원 값은 HTTP 400.
    def _normalize_language_mode(self, language_mode: str) -> str:
        normalized_mode = (language_mode or "").strip().lower()
        if normalized_mode not in {"system", "ko", "en"}:
            raise HTTPException(status_code=400, detail="Language mode is invalid.")
        return normalized_mode

    # 함수이름: _normalize_time_format
    # 함수역할:
    # - 화면에 표시할 12시간제 또는 24시간제 값을 검증한다.
    # 매개변수:
    # - time_format (str): 사용자가 선택한 12시간제·24시간제 표시.
    # 반환값:
    # - 12h 또는 24h 형식; 미지원 값은 HTTP 400.
    def _normalize_time_format(self, time_format: str) -> str:
        normalized_format = (time_format or "").strip().lower()
        if normalized_format not in {"12h", "24h"}:
            raise HTTPException(status_code=400, detail="Time format is invalid.")
        return normalized_format

    # 함수이름: _normalize_notification_detail_mode
    # 함수역할:
    # - 잠금 화면에서 민감한 알림 내용을 표시할지 검증한다.
    # 매개변수:
    # - detail_mode (str): 요청한 알림 미리보기 상세 모드.
    # 반환값:
    # - full 또는 type_only 표시 모드; 미지원 값은 HTTP 400.
    def _normalize_notification_detail_mode(self, detail_mode: str) -> str:
        normalized_mode = (detail_mode or "").strip().lower()
        if normalized_mode not in {"full", "type_only"}:
            raise HTTPException(
                status_code=400,
                detail="Notification detail mode is invalid.",
            )
        return normalized_mode

    # 함수이름: _normalize_time
    # 함수역할:
    # - 기본 복약 시각을 HH:mm 형식으로 정규화한다.
    # 매개변수:
    # - value (str): 사용자가 입력한 기본 복약 시각(HH:MM).
    # 반환값:
    # - 정규화한 HH:MM 시각; 형식 또는 시·분 범위 오류는 HTTP 400.
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

    # 함수이름: _to_entity
    # 함수역할:
    # - 저장 행의 누락된 접근성·언어·시간·알림 값을 기본 설정으로 보완한다.
    # 매개변수:
    # - row (_UserSetting): 계정에 저장된 접근성·알림 설정 행.
    # 반환값:
    # - 모든 사용자 설정 항목이 채워진 UserSetting.
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

    # 함수이름: _apply_extended_setting
    # 함수역할:
    # - 알림, 개인정보, 기본 복약 시각과 표시 설정을 DB 행에 반영한다.
    # 매개변수:
    # - row (_UserSetting): 계정에 저장된 접근성·알림 설정 행.
    # - setting (UserSetting): 전체 접근성·언어·알림·기본 복약 시각 상태.
    # 반환값:
    # - 없음.
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

    # Function Name: _success_response
    # Description:
    # - Serializes the preference entity and attaches a user-facing operation message.
    # Parameters:
    # - message (str): User-facing operation status message.
    # - setting (UserSetting): Complete accessibility, language, notification and reminder-time state.
    # Returns:
    # - Success envelope containing the complete user settings.
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
