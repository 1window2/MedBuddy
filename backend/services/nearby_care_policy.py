# File Name: nearby_care_policy.py
# Role: Pure time and distance calculations shared by nearby-care use cases.

import math
import re
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


# Function Name: minutes_until_close
# Description: Counts minutes left in the applicable open interval, checking yesterday's overnight carryover first.
# Parameters: now (datetime) is local time; is_open_now (bool | None) must be True; start_minutes, end_minutes (int | None) are today's bounds;
#   previous_start_minutes, previous_end_minutes (int | None) are yesterday's bounds, all measured from midnight.
# Returns: Remaining minutes (int), or None when not known open, hours are unavailable, or today's interval is all-day.
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


# Function Name: parse_minutes
# Description: Extracts digits, pads three-digit times and checks hour/minute ranges.
# Parameters: value (str) is a provider time label; allow_24 (bool) permits exactly 24:00 for closing times.
# Returns: Minutes since midnight (int), or None for unsupported lengths or out-of-range times.
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


# 함수이름: parse_operating_hours
# 함수역할: 정확한 두 시각 표기만 허용하고 동일한 시작·종료를 휴무나 종일 운영으로 추정하지 않는다.
# 매개변수: values (object)는 시작·종료 문자열의 tuple 또는 list여야 한다.
# 반환값: 분 단위 시각 쌍. 누락·형식 오류·범위 초과·동일 시각이면 (None, None)이다.
def parse_operating_hours(values: object) -> tuple[int | None, int | None]:
    """명시된 시각 쌍만 읽고 동일한 시작·종료를 휴무나 종일 운영으로 추정하지 않는다."""
    if not isinstance(values, (tuple, list)) or len(values) != 2:
        return None, None
    if not all(isinstance(value, str) and re.fullmatch(
        r"(?:[0-9]{3,4}|[0-9]{1,2}:[0-9]{2})", value,
    ) for value in values):
        return None, None
    start = parse_minutes(values[0])
    end = parse_minutes(values[1], allow_24=True)
    if start is None or end is None or start == end:
        return None, None
    return start, end


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


# Function Name: format_time
# Description: Formats minute offsets as HH:MM, preserving the endpoint 1440 as 24:00.
# Parameters: minutes (int | None) is an already-validated offset from midnight.
# Returns: Display string, or None when no time is available; this helper does not validate ranges.
def format_time(minutes: int | None) -> str | None:
    if minutes is None:
        return None
    if minutes == 24 * 60:
        return "24:00"
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


# Function Name: haversine_distance
# Description: Computes great-circle distance using the mean Earth radius and the haversine formula.
# Parameters: start_latitude, start_longitude, end_latitude, end_longitude (float) are validated coordinates in degrees.
# Returns: Distance in kilometers (float); coordinate validation belongs to the caller.
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
