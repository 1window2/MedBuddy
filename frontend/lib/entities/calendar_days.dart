// File Name: calendar_days.dart
// Role: Moves a date by whole calendar days without 24-hour arithmetic, so a
//   daylight-saving change in the device's time zone cannot shift the result.

// Function Name: addCalendarDays
// Description:
// - Returns midnight of the date `days` calendar days after `date`. A local value
//   is rebuilt with the local DateTime constructor, which applies the device's own
//   time-zone rules (the Android/iOS tz database) to that date, so every region's
//   daylight-saving changes are handled without per-region code. Adding
//   Duration(days: n) instead moves n x 24 hours and, across a fall-back change,
//   lands at 23:00 of the previous day. A UTC value stays in UTC, which has no
//   daylight saving. This is the same construction as Flutter's
//   DateUtils.addDaysToDate, usable outside the widget layer.
// Parameters:
// - date (DateTime): Any time on the starting date; only its calendar date is used.
// - days (int): Calendar days to move; negative values move backwards.
// Returns:
// - DateTime: Midnight of the resulting date, local or UTC like `date`.
DateTime addCalendarDays(DateTime date, int days) => date.isUtc
    ? DateTime.utc(date.year, date.month, date.day + days)
    : DateTime(date.year, date.month, date.day + days);
