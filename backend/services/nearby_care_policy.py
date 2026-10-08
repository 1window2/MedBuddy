# File Name: nearby_care_policy.py
# Role: Pure time and distance calculations shared by nearby-care use cases.

import math
from datetime import datetime, timedelta, tzinfo

# The client date picker offers today - 7 days through today + 366 days and sends the picked day
# at 12:00, so the accepted window is counted in calendar days of the application zone.
TARGET_DATE_PAST_DAYS = 7
TARGET_DATE_FUTURE_DAYS = 366


# Function Name: normalize_target_datetime
# Description:
# - Places a requested search time in the application time zone and accepts it when its calendar
#   date lies from TARGET_DATE_PAST_DAYS before to TARGET_DATE_FUTURE_DAYS after today's date.
# - Whole days are compared, not instants: comparing datetimes rejected the first offered day once
#   the current time had passed the requested time of day, and the last offered day before it.
# Parameters:
# - value (datetime | None): Requested search time; a naive value is read as application time.
# - now (datetime): Current time from the caller's clock.
# - timezone (tzinfo): Application time zone.
# Returns:
# - Aware target datetime in the application zone, or the current application time when value is
#   None; raises ValueError for a date outside the window or outside the calendar range.
def normalize_target_datetime(
    value: datetime | None,
    *,
    now: datetime,
    timezone: tzinfo,
) -> datetime:
    current = now.astimezone(timezone)
    if value is None:
        return current
    try:
        normalized = (
            value.replace(tzinfo=timezone)
            if value.tzinfo is None
            else value.astimezone(timezone)
        )
    except OverflowError:
        # A date at the edge of the calendar cannot be shifted into the application zone.
        raise ValueError("Target date is out of range.") from None
    today = current.date()
    if normalized.date() < today - timedelta(days=TARGET_DATE_PAST_DAYS):
        raise ValueError(
            f"Target date cannot be more than {TARGET_DATE_PAST_DAYS} days in the past."
        )
    if normalized.date() > today + timedelta(days=TARGET_DATE_FUTURE_DAYS):
        raise ValueError(
            f"Target date cannot be more than {TARGET_DATE_FUTURE_DAYS} days in the future."
        )
    return normalized


# 함수이름: minutes_until_close
# 함수역할:
# - 현재 영업 중일 때 폐점까지 남은 분을 계산한다.
# 매개변수:
# - now (datetime): 상태·만료 판정에 사용할 기준 시각.
# - is_open_now (bool | None): 알려진 영업 여부; 운영 시간이 없으면 None.
# - start_minutes (int | None): 확인된 경우 자정 이후 분 단위의 오늘 개점 시각.
# - end_minutes (int | None): 확인된 경우 자정 이후 분 단위의 오늘 폐점 시각.
# - previous_start_minutes (int | None): 야간 이월 판정에 사용할 전날 개점 시각(분).
# - previous_end_minutes (int | None): 야간 이월 판정에 사용할 전날 폐점 시각(분).
# 반환값:
# - 현재 영업 구간이 끝날 때까지의 분 수; 24시간 영업이거나 영업 중이 아니거나 시각을 계산할 수 없으면 None.
def minutes_until_close(
    *,
    now: datetime,
    is_open_now: bool | None,
    start_minutes: int | None,
    end_minutes: int | None,
    previous_start_minutes: int | None,
    previous_end_minutes: int | None,
) -> int | None:
    """현재 영업 중일 때 폐점까지 남은 분을 계산한다."""
    if is_open_now is not True:
        return None
    current_minutes = now.hour * 60 + now.minute
    if (
        previous_start_minutes is not None
        and previous_end_minutes is not None
        and previous_end_minutes < previous_start_minutes
        and current_minutes < previous_end_minutes
    ):
        return previous_end_minutes - current_minutes
    if start_minutes is None or end_minutes is None:
        return None
    if start_minutes == 0 and end_minutes in {0, 24 * 60}:
        return None
    if end_minutes > start_minutes:
        return max(end_minutes - current_minutes, 0)
    if end_minutes < start_minutes and current_minutes >= start_minutes:
        return 24 * 60 - current_minutes + end_minutes
    return None


# 함수이름: parse_minutes
# 함수역할:
# - 시각에서 숫자를 추출해 시·분 범위를 확인하고 허용된 경우 24:00도 처리한다.
# 매개변수:
# - value (str): 공공 약국 API의 시·분 문자열.
# - allow_24 (bool): 폐점 시각으로 정확히 24:00을 허용할지 여부.
# 반환값:
# - 자정 이후 분 수; 잘못된 시각은 None.
def parse_minutes(value: str, *, allow_24: bool = False) -> int | None:
    normalized = "".join(character for character in value if character.isdigit())
    if len(normalized) not in {3, 4}:
        return None
    normalized = normalized.zfill(4)
    hour = int(normalized[:2])
    minute = int(normalized[2:])
    if allow_24 and hour == 24 and minute == 0:
        return 24 * 60
    if hour > 23 or minute > 59:
        return None
    return hour * 60 + minute


# Function Name: is_open_now
# Description:
# - Checks today's interval and yesterday's overnight carryover, treating midnight-to-midnight as all-day operation.
# Parameters:
# - now (datetime): Reference datetime for time-sensitive status or expiration checks.
# - start_minutes (int | None): Today's opening time as minutes since midnight, if known.
# - end_minutes (int | None): Today's closing time as minutes since midnight, if known.
# - previous_start_minutes (int | None): Previous day's opening time for overnight checks.
# - previous_end_minutes (int | None): Previous day's closing time for overnight checks.
# Returns:
# - True when open, False when closed with known hours, or None when today's hours are unknown.
def is_open_now(
    *,
    now: datetime,
    start_minutes: int | None,
    end_minutes: int | None,
    previous_start_minutes: int | None = None,
    previous_end_minutes: int | None = None,
) -> bool | None:
    current_minutes = now.hour * 60 + now.minute
    if start_minutes is not None and end_minutes is not None:
        if end_minutes > start_minutes:
            if start_minutes <= current_minutes < end_minutes:
                return True
        elif end_minutes < start_minutes:
            if current_minutes >= start_minutes:
                return True
        elif start_minutes == 0:
            return True

    if (
        previous_start_minutes is not None
        and previous_end_minutes is not None
        and previous_end_minutes < previous_start_minutes
        and current_minutes < previous_end_minutes
    ):
        return True
    if start_minutes is None or end_minutes is None:
        return None
    return False


# 함수이름: format_time
# 함수역할:
# - 자정 이후 분 수를 HH:MM 표시로 변환하고 1440분은 24:00으로 보존한다.
# 매개변수:
# - minutes (int | None): 시각 표시로 변환할 자정 이후 분 수.
# 반환값:
# - 표시용 시각 또는 입력이 없을 때 None.
def format_time(minutes: int | None) -> str | None:
    if minutes is None:
        return None
    if minutes == 24 * 60:
        return "24:00"
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


# 함수이름: haversine_distance
# 함수역할:
# - 두 위도·경도의 대권 거리를 평균 지구 반지름으로 계산한다.
# 매개변수:
# - start_latitude (float): 출발 위치의 위도(도).
# - start_longitude (float): 출발 위치의 경도(도).
# - end_latitude (float): 도착 위치의 위도(도).
# - end_longitude (float): 도착 위치의 경도(도).
# 반환값:
# - 두 위치 사이의 거리(km).
def haversine_distance(
    start_latitude: float,
    start_longitude: float,
    end_latitude: float,
    end_longitude: float,
) -> float:
    earth_radius_km = 6371.0088
    start_latitude_radians = math.radians(start_latitude)
    end_latitude_radians = math.radians(end_latitude)
    latitude_delta = math.radians(end_latitude - start_latitude)
    longitude_delta = math.radians(end_longitude - start_longitude)
    haversine = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(start_latitude_radians)
        * math.cos(end_latitude_radians)
        * math.sin(longitude_delta / 2) ** 2
    )
    return earth_radius_km * 2 * math.asin(math.sqrt(haversine))
