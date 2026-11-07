# File Name: manage_user_setting_control.py
# Role: Validates and persists account accessibility, language, notification and default reminder-time preferences.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from sqlalchemy.orm.exc import StaleDataError

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.user_setting_entity import UserSetting, _UserSetting

logger = logging.getLogger(__name__)


# Class Name: ManageUserSetting
# Role: Validates and persists accessibility, language, home-schedule and notification preferences.
# Responsibilities: Supplies unsaved defaults, normalizes allowed values, tracks optimistic revisions and resolves legacy concurrent-creation retries.
# Attributes: db (Session) owns setting queries and commits.
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

    # 함수이름: requestUserSetting
    # 함수역할: 정규화한 사용자 범위의 설정을 읽고 저장 전이면 기본 설정과 revision 0을 반환한다.
    # 매개변수: user_hash (str)는 조회 계정 식별자다.
    # 반환값: 설정·revision 성공 응답. 기본값을 DB에 저장하지 않으며 조회 오류는 전달한다.
    def requestUserSetting(
        self,
        user_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        row = self._find_setting(normalized_user_hash)
        setting = self._to_entity(row) if row else UserSetting(user_hash=normalized_user_hash)
        return self._success_response(
            "User setting lookup succeeded.", setting, row.revision if row else 0,
        )

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
    # - expected_revision (int | None): 저장 기준 서버 버전. 구형 클라이언트는 생략한다.
    # - home_schedule_source (str | None): self 또는 patients로 홈 일정 출처를 변경하며 None은 기존 선택을 유지한다.
    # 반환값:
    # - 새 revision과 설정을 담은 성공 응답. 잘못된 값은 400, 버전 충돌은 409, 저장 실패는 500이다.
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
        home_schedule_source: str | None = None,
        *,
        expected_revision: int | None = None,
    ) -> dict[str, object]:
        if home_schedule_source is not None:
            home_schedule_source = home_schedule_source.strip().lower()
            if home_schedule_source not in {"self", "patients"}:
                raise HTTPException(status_code=400, detail="Invalid home schedule source.")
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
            current_revision = row.revision if row else 0
            if expected_revision is not None and expected_revision != current_revision:
                raise self._revision_conflict(current_revision)
            if row is None:
                row = _UserSetting(user_hash=normalized_user_hash)
                self.db.add(row)
            # 값이 같아도 새 저장 의도를 확정해 이전 요청의 뒤늦은 변경을 차단한다.
            row.revision = current_revision + 1
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
                home_schedule_source,
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
                row.revision,
            )
        except (IntegrityError, StaleDataError):
            self.db.rollback()
            if expected_revision is not None:
                current = self._find_setting(normalized_user_hash)
                raise self._revision_conflict(current.revision if current else 0)
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
                home_schedule_source,
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

    # 함수이름: _find_setting
    # 함수역할: 사용자 설정을 DB에서 다시 읽어 세션에 이미 있는 행의 오래된 값도 갱신한다.
    # 매개변수: user_hash (str)는 조회 계정 식별자다.
    # 반환값: _UserSetting 또는 저장 전이면 None. DB 오류는 전달한다.
    def _find_setting(self, user_hash: str) -> _UserSetting | None:
        return (
            self.db.query(_UserSetting)
            .filter(_UserSetting.user_hash == user_hash)
            .populate_existing()
            .first()
        )

    # 함수이름: _revision_conflict
    # 함수역할: 저장 버전 충돌을 표현하는 예외 객체를 구성하며 직접 발생시키지는 않는다.
    # 매개변수: revision (int)은 클라이언트가 재조회·재시도 판단에 사용할 현재 서버 버전이다.
    # 반환값: settings_revision_conflict 코드와 revision을 담은 HTTP 409 예외.
    def _revision_conflict(self, revision: int) -> HTTPException:
        return HTTPException(
            status_code=409,
            detail={"code": "settings_revision_conflict", "revision": revision},
        )

    # Function Name: _update_existing_setting_after_conflict
    # Description: Re-reads a concurrently created/updated row, reapplies normalized legacy-client settings and increments revision; a second stale write is reported as conflict.
    # Parameters: user_hash (str), font_size (int), reading_speed (float), language, language_mode and time_format (str) identify normalized accessibility values;
    #   medication_notifications_enabled, caregiver_notifications_enabled, chat_notifications_enabled (bool) toggle categories; notification_detail_mode (str) controls previews;
    #   default_times (dict[str, str]) maps slots to HH:MM; home_schedule_source (str | None) updates or retains the home source.
    # Returns: Committed preference envelope with revision; missing row or StaleDataError yields HTTP 409, other persistence errors propagate.
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
        home_schedule_source: str | None = None,
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
        row.revision += 1
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
            home_schedule_source,
        )
        self._apply_extended_setting(row, next_setting)
        try:
            self.db.commit()
        except StaleDataError as exc:
            # 재조회 뒤에도 또 다른 저장이 먼저 끝났으면 500 대신 해결 불가 충돌로 알린다.
            self.db.rollback()
            raise HTTPException(
                status_code=409,
                detail="User setting conflict could not be resolved.",
            ) from exc
        self.db.refresh(row)
        return self._success_response("User setting was saved.", self._to_entity(row), row.revision)

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
            home_schedule_source=row.home_schedule_source or "self",
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
        row.home_schedule_source = setting.home_schedule_source
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

    # 함수이름: _success_response
    # 함수역할: 사용자 설정 엔티티와 서버 버전을 동일한 성공 응답으로 직렬화한다.
    # 매개변수: message (str)는 안내, setting (UserSetting)은 설정, revision (int)은 저장 버전이며 기본값 0은 저장 전이다.
    # 반환값: success·message·data·revision dict. DB 조회나 변경은 하지 않는다.
    def _success_response(
        self,
        message: str,
        setting: UserSetting,
        revision: int = 0,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": setting.getUserSetting(),
            "revision": revision,
        }
