# File Name: medication_dose_rhythm.py
# Role: Reads from a frequency or duration label on which days a medication is taken.
#   A label such as "주 1회", "격일" or "2일 1회" is not a per-day count; scheduling it every day
#   would prompt the patient to take a weekly medicine daily. The client mirrors these rules in
#   frontend/lib/entities/medication_dose_rhythm.dart, and both sides are tested against
#   backend/tests/data/dose_rhythm_vectors.json.

from dataclasses import dataclass
from datetime import date, timedelta
import re

# Longest interval and cycle accepted from a label; anything beyond is read as daily.
MAX_DOSE_INTERVAL_DAYS = 90
_DAYS_PER_WEEK = 7
_DAYS_PER_MONTH = 30

# Days of a seven-day cycle used for "N times a week" when the label names no weekdays:
# spread as evenly as a week allows, counted from the first day of the course.
_WEEKLY_SPREAD = {
    1: (0,),
    2: (0, 3),
    3: (0, 2, 4),
    4: (0, 2, 4, 6),
    5: (0, 1, 2, 3, 4),
    6: (0, 1, 2, 3, 4, 5),
}
_WEEKDAY_INDEX = {"월": 0, "화": 1, "수": 2, "목": 3, "금": 4, "토": 5, "일": 6}
_KOREAN_COUNT = {"한": 1, "두": 2, "세": 3, "네": 4}
_COUNT = r"(\d+|한|두|세|네)\s*(?:회|번)"
_ONCE = r"(?:1\s*(?:회|번)|한\s*번)"

_WEEKDAY_NAMED = re.compile(r"([월화수목금토일])요일")
# "월수금" style: three or more weekday letters standing alone, so that "금일" (today) or the
# "일" of "1일" is never read as a weekday.
_WEEKDAY_RUN = re.compile(r"(?<![0-9가-힣])([월화수목금토일]{3,7})(?![가-힣])")
_EVERY_N_WEEKS = (
    re.compile(rf"(\d+)\s*주(?:일)?\s*(?:에\s*)?{_ONCE}"),
    re.compile(r"(\d+)\s*주(?:일)?\s*(?:마다|간격)"),
    re.compile(r"every\s+(\d+)\s+weeks?"),
)
_EVERY_OTHER_WEEK = re.compile(r"격주|every\s+other\s+week")
_TIMES_PER_WEEK = (
    re.compile(rf"(?:매주|일주일에|(?<![\d개])(?<!\d\s)주)\s*{_COUNT}"),
    re.compile(r"(\d+)\s*(?:times?|x)\s*(?:a|per|/)\s*week"),
)
_ONCE_PER_WEEK = re.compile(r"매주|once\s+(?:a|per)\s+week|weekly")
_TWICE_PER_WEEK = re.compile(r"twice\s+(?:a|per)\s+week")
_EVERY_N_MONTHS = re.compile(rf"(\d+)\s*개월\s*(?:에\s*)?{_ONCE}|(\d+)\s*개월\s*마다")
# "10월 1회" is a date, not "once a month": a month number in front of 월 is excluded.
_TIMES_PER_MONTH = re.compile(
    rf"(?:매월|매달|한\s*달에|(?<![개\d])(?<!\d\s)월)\s*{_COUNT}"
)
_ONCE_PER_MONTH = re.compile(r"매월|매달|once\s+(?:a|per)\s+month|monthly")
_EVERY_OTHER_DAY = re.compile(
    rf"격일|하루\s*걸러|이틀\s*(?:에\s*{_ONCE}|마다)|every\s+other\s+day"
)
_EVERY_N_DAYS = (
    re.compile(rf"(\d+)\s*일\s*(?:에\s*)?{_ONCE}"),
    re.compile(r"(\d+)\s*일\s*(?:마다|간격)"),
    re.compile(r"every\s+(\d+)\s+days?"),
)
# A count that is explicitly per day, e.g. the "1일 2회" of "주 3회, 1일 2회".
_DAILY_COUNT = re.compile(rf"(?:(?<!\d)1\s*일|하루|매일)\s*(?:에\s*)?{_COUNT}")
_EVERY_N_HOURS = re.compile(
    r"(\d+)\s*시간\s*(?:마다|간격)|every\s+(\d+)\s+hours?|\bq\s*(\d+)\s*h\b"
)
_DURATION = re.compile(
    r"(-?\d+)\s*(개월|달|months?|주일|주|weeks?|wks?|일|days?)?", re.IGNORECASE
)


# Class Name: DoseCycle
# Role: The days of a repeating cycle on which a medication is taken.
# Responsibilities: Answer whether a date is a dose day and expose the cycle for the API.
# Attributes: cycle_days - length of the cycle (1 means every day); offsets - dose days within
#   the cycle, starting at 0; weekday_anchored - True when the offsets are weekdays (0 = Monday)
#   instead of days counted from the start of the course.
@dataclass(frozen=True)
class DoseCycle:
    cycle_days: int = 1
    offsets: tuple[int, ...] = (0,)
    weekday_anchored: bool = False

    # Function Name: is_daily
    # Description: Tells whether the medication is taken every day.
    # Parameters: None. Returns: True for the one-day cycle.
    @property
    def is_daily(self) -> bool:
        return self.cycle_days <= 1

    # Function Name: anchor
    # Description: Returns day 0 of the cycle: the Monday of the week the course starts in for
    #   weekday cycles, otherwise the first day of the course.
    # Parameters: start_date (date) - First day of the course.
    # Returns: The date counted as offset 0.
    def anchor(self, start_date: date) -> date:
        if self.weekday_anchored:
            return start_date - timedelta(days=start_date.weekday())
        return start_date

    # Function Name: includes
    # Description: Tells whether a date is a dose day of a course that starts on start_date.
    # Parameters: start_date (date) - First day of the course; target_date (date) - Date asked.
    # Returns: True on dose days; always True for a daily cycle.
    def includes(self, start_date: date, target_date: date) -> bool:
        if self.is_daily:
            return True
        elapsed = (target_date - self.anchor(start_date)).days
        return elapsed % self.cycle_days in self.offsets


DAILY_CYCLE = DoseCycle()


# Function Name: _number
# Description: Reads a digit group or one of the Korean count words 한, 두, 세, 네.
# Parameters: raw (str | None) - Captured text.
# Returns: The number, or 0 when it cannot be read.
def _number(raw: str | None) -> int:
    if not raw:
        return 0
    if raw in _KOREAN_COUNT:
        return _KOREAN_COUNT[raw]
    try:
        return int(raw)
    except ValueError:
        return 0


# Function Name: _interval
# Description: Builds the cycle "once every N days", or the daily cycle when N is not a usable
#   interval.
# Parameters: days (int) - Interval in days.
# Returns: The cycle.
def _interval(days: int) -> DoseCycle:
    if days < 2 or days > MAX_DOSE_INTERVAL_DAYS:
        return DAILY_CYCLE
    return DoseCycle(cycle_days=days, offsets=(0,))


# Function Name: _times_per_week
# Description: Builds the cycle for N doses a week without named weekdays.
# Parameters: count (int) - Doses per week.
# Returns: A seven-day cycle, or the daily cycle for zero, seven or more.
def _times_per_week(count: int) -> DoseCycle:
    spread = _WEEKLY_SPREAD.get(count)
    if spread is None:
        return DAILY_CYCLE
    return DoseCycle(cycle_days=_DAYS_PER_WEEK, offsets=spread)


# Function Name: read_dose_cycle
# Description:
# - Reads the dose days from a frequency label. Named weekdays win, then "every N weeks",
#   "N times a week", monthly forms and "every N days". A label that states none of these is
#   read as daily, which is what every plain "1일 3회" label means.
# Parameters:
# - raw_frequency (str | None): Frequency label as stored or recognized.
# Returns:
# - The cycle; DAILY_CYCLE when the label does not describe a non-daily rhythm.
def read_dose_cycle(raw_frequency: str | None) -> DoseCycle:
    text = " ".join(str(raw_frequency or "").lower().split())
    if not text:
        return DAILY_CYCLE

    weekdays = {_WEEKDAY_INDEX[letter] for letter in _WEEKDAY_NAMED.findall(text)}
    run = _WEEKDAY_RUN.search(text)
    if run is not None and len(set(run.group(1))) == len(run.group(1)):
        weekdays.update(_WEEKDAY_INDEX[letter] for letter in run.group(1))
    if weekdays:
        if len(weekdays) >= _DAYS_PER_WEEK:
            return DAILY_CYCLE
        return DoseCycle(
            cycle_days=_DAYS_PER_WEEK,
            offsets=tuple(sorted(weekdays)),
            weekday_anchored=True,
        )

    if _EVERY_OTHER_WEEK.search(text):
        return _interval(2 * _DAYS_PER_WEEK)
    for pattern in _EVERY_N_WEEKS:
        match = pattern.search(text)
        if match is not None:
            return _interval(_number(match.group(1)) * _DAYS_PER_WEEK)
    for pattern in _TIMES_PER_WEEK:
        match = pattern.search(text)
        if match is not None:
            return _times_per_week(_number(match.group(1)))
    if _TWICE_PER_WEEK.search(text):
        return _times_per_week(2)
    if _ONCE_PER_WEEK.search(text):
        return _times_per_week(1)

    match = _EVERY_N_MONTHS.search(text)
    if match is not None:
        return _interval(_number(match.group(1) or match.group(2)) * _DAYS_PER_MONTH)
    match = _TIMES_PER_MONTH.search(text)
    if match is not None:
        count = _number(match.group(1))
        # Rounded half up with integers so that the client computes the same interval.
        return (
            _interval((_DAYS_PER_MONTH + count // 2) // count) if count > 0 else DAILY_CYCLE
        )
    if _ONCE_PER_MONTH.search(text):
        return _interval(_DAYS_PER_MONTH)

    if _EVERY_OTHER_DAY.search(text):
        return _interval(2)
    for pattern in _EVERY_N_DAYS:
        match = pattern.search(text)
        if match is not None:
            return _interval(_number(match.group(1)))
    return DAILY_CYCLE


# Function Name: read_doses_per_dose_day
# Description:
# - Reads how many doses are taken on a dose day when the label says so in a way the plain
#   count reader would misread: an explicit per-day count next to a weekly one, an hour
#   interval ("8시간마다" is three doses), or a non-daily label, whose count is per week or
#   month and therefore means one dose on each dose day.
# Parameters:
# - raw_frequency (str | None): Frequency label as stored or recognized.
# Returns:
# - The doses per dose day, or None when the plain count reader applies.
def read_doses_per_dose_day(raw_frequency: str | None) -> int | None:
    text = " ".join(str(raw_frequency or "").lower().split())
    if not text:
        return None
    match = _DAILY_COUNT.search(text)
    if match is not None:
        count = _number(match.group(1))
        return count if count > 0 else None
    match = _EVERY_N_HOURS.search(text)
    if match is not None:
        hours = _number(match.group(1) or match.group(2) or match.group(3))
        if 1 <= hours <= 24:
            return max(1, (24 + hours // 2) // hours)
    if not read_dose_cycle(text).is_daily:
        return 1
    return None


# Function Name: read_duration_days
# Description:
# - Reads a course length in days from the first number of a label and its unit: days as they
#   are, weeks times seven, months times thirty. "7일분 (1주)" is seven days; "2주" is fourteen.
# Parameters:
# - raw_duration (str | None): Duration label as stored or recognized.
# Returns:
# - The length in days, or 0 when no positive number can be read.
def read_duration_days(raw_duration: str | None) -> int:
    match = _DURATION.search(str(raw_duration or ""))
    if match is None:
        return 0
    amount = _number(match.group(1))
    if amount <= 0:
        return 0
    unit = (match.group(2) or "").lower()
    if unit in ("개월", "달") or unit.startswith("month"):
        return amount * _DAYS_PER_MONTH
    if unit in ("주", "주일") or unit.startswith(("week", "wk")):
        return amount * _DAYS_PER_WEEK
    return amount
