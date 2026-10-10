// File Name: medication_dose_rhythm.dart
// Role: Reads from a frequency or duration label on which days a medication is taken.
//   A label such as "주 1회", "격일" or "2일 1회" is not a per-day count; scheduling it every day
//   would prompt the patient to take a weekly medicine daily. This mirrors
//   backend/services/medication_dose_rhythm.py, and both sides are tested against
//   backend/tests/data/dose_rhythm_vectors.json.

// Longest interval and cycle accepted from a label; anything beyond is read as daily.
const int maxDoseIntervalDays = 90;
const int _daysPerWeek = 7;
const int _daysPerMonth = 30;

// Days of a seven-day cycle used for "N times a week" when the label names no weekdays:
// spread as evenly as a week allows, counted from the first day of the course.
const Map<int, List<int>> _weeklySpread = {
  1: [0],
  2: [0, 3],
  3: [0, 2, 4],
  4: [0, 2, 4, 6],
  5: [0, 1, 2, 3, 4],
  6: [0, 1, 2, 3, 4, 5],
};
const Map<String, int> _weekdayIndex = {
  '월': 0,
  '화': 1,
  '수': 2,
  '목': 3,
  '금': 4,
  '토': 5,
  '일': 6,
};
const Map<String, int> _koreanCount = {'한': 1, '두': 2, '세': 3, '네': 4};
const String _count = r'(\d+|한|두|세|네)\s*(?:회|번)';
const String _once = r'(?:1\s*(?:회|번)|한\s*번)';

final RegExp _weekdayNamed = RegExp(r'([월화수목금토일])요일');
// "월수금" style: three or more weekday letters standing alone, so that "금일" (today) or the
// "일" of "1일" is never read as a weekday.
final RegExp _weekdayRun = RegExp(r'(?<![0-9가-힣])([월화수목금토일]{3,7})(?![가-힣])');
final List<RegExp> _everyNWeeks = [
  RegExp('(\\d+)\\s*주(?:일)?\\s*(?:에\\s*)?$_once'),
  RegExp(r'(\d+)\s*주(?:일)?\s*(?:마다|간격)'),
  RegExp(r'every\s+(\d+)\s+weeks?'),
];
final RegExp _everyOtherWeek = RegExp(r'격주|every\s+other\s+week');
final List<RegExp> _timesPerWeek = [
  RegExp('(?:매주|일주일에|(?<![\\d개])(?<!\\d\\s)주)\\s*$_count'),
  RegExp(r'(\d+)\s*(?:times?|x)\s*(?:a|per|/)\s*week'),
];
final RegExp _oncePerWeek = RegExp(r'매주|once\s+(?:a|per)\s+week|weekly');
final RegExp _twicePerWeek = RegExp(r'twice\s+(?:a|per)\s+week');
final RegExp _everyNMonths = RegExp(
  '(\\d+)\\s*개월\\s*(?:에\\s*)?$_once|(\\d+)\\s*개월\\s*마다',
);
// "10월 1회" is a date, not "once a month": a month number in front of 월 is excluded.
final RegExp _timesPerMonth = RegExp(
  '(?:매월|매달|한\\s*달에|(?<![개\\d])(?<!\\d\\s)월)\\s*$_count',
);
final RegExp _oncePerMonth = RegExp(
  r'매월|매달|once\s+(?:a|per)\s+month|monthly',
);
final RegExp _everyOtherDay = RegExp(
  '격일|하루\\s*걸러|이틀\\s*(?:에\\s*$_once|마다)|every\\s+other\\s+day',
);
final List<RegExp> _everyNDays = [
  RegExp('(\\d+)\\s*일\\s*(?:에\\s*)?$_once'),
  RegExp(r'(\d+)\s*일\s*(?:마다|간격)'),
  RegExp(r'every\s+(\d+)\s+days?'),
];
// A count that is explicitly per day, e.g. the "1일 2회" of "주 3회, 1일 2회".
final RegExp _dailyCount = RegExp(
  '(?:(?<!\\d)1\\s*일|하루|매일)\\s*(?:에\\s*)?$_count',
);
final RegExp _everyNHours = RegExp(
  r'(\d+)\s*시간\s*(?:마다|간격)|every\s+(\d+)\s+hours?|\bq\s*(\d+)\s*h\b',
);
final RegExp _duration = RegExp(
  r'(-?\d+)\s*(개월|달|months?|주일|주|weeks?|wks?|일|days?)?',
  caseSensitive: false,
);

// Class Name: DoseCycle
// Role: The days of a repeating cycle on which a medication is taken.
// Responsibilities: Answer whether a date is a dose day.
// Attributes:
// - cycleDays (int): Length of the cycle; 1 means every day.
// - offsets (List<int>): Dose days within the cycle, starting at 0.
// - weekdayAnchored (bool): True when the offsets are weekdays (0 = Monday) instead of days counted from the start of the course.
class DoseCycle {
  final int cycleDays;
  final List<int> offsets;
  final bool weekdayAnchored;

  // Function Name: DoseCycle
  // Description: Creates a dose cycle; the default is the daily cycle.
  // Parameters:
  // - cycleDays (int): Length of the cycle in days.
  // - offsets (List<int>): Dose days within the cycle.
  // - weekdayAnchored (bool): Whether the offsets are weekdays.
  // Returns: The cycle.
  const DoseCycle({
    this.cycleDays = 1,
    this.offsets = const [0],
    this.weekdayAnchored = false,
  });

  static const DoseCycle daily = DoseCycle();

  // Function Name: isDaily
  // Description: Tells whether the medication is taken every day.
  // Parameters: None.
  // Returns: bool: true for the one-day cycle.
  bool get isDaily => cycleDays <= 1;

  // Function Name: anchor
  // Description: Returns day 0 of the cycle: the Monday of the week the course starts in for weekday cycles, otherwise the first day of the course.
  // Parameters:
  // - startDate (DateTime): First day of the course.
  // Returns: DateTime: the calendar date counted as offset 0.
  DateTime anchor(DateTime startDate) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    if (weekdayAnchored) {
      return DateTime(start.year, start.month, start.day - (start.weekday - 1));
    }
    return start;
  }

  // Function Name: includes
  // Description: Tells whether a date is a dose day of a course that starts on startDate.
  // Parameters:
  // - startDate (DateTime): First day of the course.
  // - targetDate (DateTime): Date asked about.
  // Returns: bool: true on dose days; always true for a daily cycle.
  bool includes(DateTime startDate, DateTime targetDate) {
    if (isDaily) {
      return true;
    }
    return isDoseDayOfCycle(
      cycleDays: cycleDays,
      offsets: offsets,
      anchor: anchor(startDate),
      date: targetDate,
    );
  }
}

// Function Name: isDoseDayOfCycle
// Description: Tells whether a date is a dose day: the whole days from the anchor to the date, modulo the cycle length, must be one of the offsets. Calendar dates are compared in UTC so a daylight-saving change cannot shift the count.
// Parameters:
// - cycleDays (int): Length of the cycle; 1 or less means every day.
// - offsets (List<int>): Dose days within the cycle.
// - anchor (DateTime?): Date counted as offset 0; without one every day is a dose day.
// - date (DateTime): Date asked about.
// Returns: bool: true on dose days.
bool isDoseDayOfCycle({
  required int cycleDays,
  required List<int> offsets,
  required DateTime? anchor,
  required DateTime date,
}) {
  if (cycleDays <= 1 || anchor == null) {
    return true;
  }
  final elapsed = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(anchor.year, anchor.month, anchor.day)).inDays;
  return offsets.contains(((elapsed % cycleDays) + cycleDays) % cycleDays);
}

// Function Name: _number
// Description: Reads a digit group or one of the Korean count words 한, 두, 세, 네.
// Parameters:
// - raw (String?): Captured text.
// Returns: int: the number, or 0 when it cannot be read.
int _number(String? raw) {
  if (raw == null || raw.isEmpty) {
    return 0;
  }
  return _koreanCount[raw] ?? int.tryParse(raw) ?? 0;
}

// Function Name: _interval
// Description: Builds the cycle "once every N days", or the daily cycle when N is not a usable interval.
// Parameters:
// - days (int): Interval in days.
// Returns: DoseCycle: the cycle.
DoseCycle _interval(int days) {
  if (days < 2 || days > maxDoseIntervalDays) {
    return DoseCycle.daily;
  }
  return DoseCycle(cycleDays: days);
}

// Function Name: _timesPerWeekCycle
// Description: Builds the cycle for N doses a week without named weekdays.
// Parameters:
// - count (int): Doses per week.
// Returns: DoseCycle: a seven-day cycle, or the daily cycle for zero, seven or more.
DoseCycle _timesPerWeekCycle(int count) {
  final spread = _weeklySpread[count];
  if (spread == null) {
    return DoseCycle.daily;
  }
  return DoseCycle(cycleDays: _daysPerWeek, offsets: spread);
}

// Function Name: _normalized
// Description: Lower-cases a label and collapses its whitespace.
// Parameters:
// - raw (String?): Label as stored or recognized.
// Returns: String: the normalized label.
String _normalized(String? raw) =>
    (raw ?? '').toLowerCase().trim().split(RegExp(r'\s+')).join(' ');

// Function Name: readDoseCycle
// Description: Reads the dose days from a frequency label. Named weekdays win, then "every N weeks", "N times a week", monthly forms and "every N days". A label that states none of these is read as daily, which is what every plain "1일 3회" label means.
// Parameters:
// - rawFrequency (String?): Frequency label as stored or recognized.
// Returns: DoseCycle: the cycle; the daily cycle when the label does not describe a non-daily rhythm.
DoseCycle readDoseCycle(String? rawFrequency) {
  final text = _normalized(rawFrequency);
  if (text.isEmpty) {
    return DoseCycle.daily;
  }

  final weekdays = <int>{
    for (final match in _weekdayNamed.allMatches(text))
      _weekdayIndex[match.group(1)]!,
  };
  final run = _weekdayRun.firstMatch(text)?.group(1);
  if (run != null && run.split('').toSet().length == run.length) {
    weekdays.addAll(run.split('').map((letter) => _weekdayIndex[letter]!));
  }
  if (weekdays.isNotEmpty) {
    if (weekdays.length >= _daysPerWeek) {
      return DoseCycle.daily;
    }
    return DoseCycle(
      cycleDays: _daysPerWeek,
      offsets: weekdays.toList()..sort(),
      weekdayAnchored: true,
    );
  }

  if (_everyOtherWeek.hasMatch(text)) {
    return _interval(2 * _daysPerWeek);
  }
  for (final pattern in _everyNWeeks) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return _interval(_number(match.group(1)) * _daysPerWeek);
    }
  }
  for (final pattern in _timesPerWeek) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return _timesPerWeekCycle(_number(match.group(1)));
    }
  }
  if (_twicePerWeek.hasMatch(text)) {
    return _timesPerWeekCycle(2);
  }
  if (_oncePerWeek.hasMatch(text)) {
    return _timesPerWeekCycle(1);
  }

  final everyNMonths = _everyNMonths.firstMatch(text);
  if (everyNMonths != null) {
    return _interval(
      _number(everyNMonths.group(1) ?? everyNMonths.group(2)) * _daysPerMonth,
    );
  }
  final timesPerMonth = _timesPerMonth.firstMatch(text);
  if (timesPerMonth != null) {
    final count = _number(timesPerMonth.group(1));
    // Rounded half up with integers so that the server computes the same interval.
    return count > 0
        ? _interval((_daysPerMonth + count ~/ 2) ~/ count)
        : DoseCycle.daily;
  }
  if (_oncePerMonth.hasMatch(text)) {
    return _interval(_daysPerMonth);
  }

  if (_everyOtherDay.hasMatch(text)) {
    return _interval(2);
  }
  for (final pattern in _everyNDays) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return _interval(_number(match.group(1)));
    }
  }
  return DoseCycle.daily;
}

// Function Name: readDosesPerDoseDay
// Description: Reads how many doses are taken on a dose day when the label says so in a way the plain count reader would misread: an explicit per-day count next to a weekly one, an hour interval ("8시간마다" is three doses), or a non-daily label, whose count is per week or month and therefore means one dose on each dose day.
// Parameters:
// - rawFrequency (String?): Frequency label as stored or recognized.
// Returns: int?: the doses per dose day, or null when the plain count reader applies.
int? readDosesPerDoseDay(String? rawFrequency) {
  final text = _normalized(rawFrequency);
  if (text.isEmpty) {
    return null;
  }
  final daily = _dailyCount.firstMatch(text);
  if (daily != null) {
    final count = _number(daily.group(1));
    return count > 0 ? count : null;
  }
  final hourly = _everyNHours.firstMatch(text);
  if (hourly != null) {
    final hours = _number(
      hourly.group(1) ?? hourly.group(2) ?? hourly.group(3),
    );
    if (hours >= 1 && hours <= 24) {
      final doses = (24 + hours ~/ 2) ~/ hours;
      return doses < 1 ? 1 : doses;
    }
  }
  if (!readDoseCycle(text).isDaily) {
    return 1;
  }
  return null;
}

// Function Name: readDurationDays
// Description: Reads a course length in days from the first number of a label and its unit: days as they are, weeks times seven, months times thirty. "7일분 (1주)" is seven days; "2주" is fourteen.
// Parameters:
// - rawDuration (String?): Duration label as stored or recognized.
// Returns: int: the length in days, or 0 when no positive number can be read.
int readDurationDays(String? rawDuration) {
  final match = _duration.firstMatch(rawDuration ?? '');
  if (match == null) {
    return 0;
  }
  final amount = int.tryParse(match.group(1) ?? '') ?? 0;
  if (amount <= 0) {
    return 0;
  }
  final unit = (match.group(2) ?? '').toLowerCase();
  if (unit == '개월' || unit == '달' || unit.startsWith('month')) {
    return amount * _daysPerMonth;
  }
  if (unit == '주' ||
      unit == '주일' ||
      unit.startsWith('week') ||
      unit.startsWith('wk')) {
    return amount * _daysPerWeek;
  }
  return amount;
}
