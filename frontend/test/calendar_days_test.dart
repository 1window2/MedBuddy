// File Name: calendar_days_test.dart
// Role: Regression coverage for calendar-day arithmetic across daylight-saving changes.
//   The assertions hold in every time zone; CI also runs this file with
//   TZ=America/New_York and TZ=Europe/Berlin, where 24-hour arithmetic used to end
//   a course or the reminder window one day early.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/calendar_days.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';

// Function Name: main
// Description: Registers the calendar-day cases around the 2026 European
//   (October 25) and US (November 1) fall-back changes, and the source guard.
// Parameters: None. Returns: No value.
void main() {
  test('adding calendar days lands on local midnight across a fall-back change', () {
    for (final (start, days, expected) in [
      (DateTime(2026, 10, 19), 27, DateTime(2026, 11, 15)),
      (DateTime(2026, 10, 20, 18, 30), 7, DateTime(2026, 10, 27)),
      (DateTime(2026, 11, 2), -3, DateTime(2026, 10, 30)),
      (DateTime(2026, 3, 1), 30, DateTime(2026, 3, 31)),
    ]) {
      final result = addCalendarDays(start, days);
      expect(result, expected, reason: '$start + $days');
      expect(result.isUtc, isFalse);
    }
    expect(
      addCalendarDays(DateTime.utc(2026, 10, 19, 9), 27),
      DateTime.utc(2026, 11, 15),
    );
  });

  test('a four-week course spanning a fall-back change ends on its last day', () {
    final medication = MedicationDetail(
      id: 1,
      itemName: 'Weekly',
      efficacy: '',
      usageMethod: '',
      warning: '',
      createdDate: DateTime(2026, 10, 19),
      prescriptionDate: DateTime(2026, 10, 19),
      totalDays: '4주',
    );
    expect(medication.medicationEndDate, DateTime(2026, 11, 15));
    expect(medication.isActiveOn(DateTime(2026, 11, 15)), isTrue);
    expect(medication.isActiveOn(DateTime(2026, 11, 16)), isFalse);
  });

  test('the reminder window keeps the last course day after a fall-back change', () {
    final schedule = MedicationSchedule(
      medicationName: 'Course',
      prescriptionDate: DateTime(2026, 10, 28),
      medicationTime: 6,
      scheduleSlotKeys: const ['morning'],
    );
    expect(
      MedicationReminderRefreshService.activeReminderDates(
        [schedule],
        now: DateTime(2026, 10, 30, 6),
      ),
      [
        DateTime(2026, 10, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 2),
      ],
    );
  });

  // Day steps of 24 hours on a local date shift by an hour across a daylight-saving
  // change. Only code that works on UTC dates (MedicationHistoryDates) may use them.
  test('lib moves local dates by calendar days, not Duration(days: ...)', () {
    const utcOnlyFiles = {
      'lib/entities/medication_history_entity.dart',
      'lib/boundaries/medication_history_ui_boundary.dart',
      'lib/widgets/as_needed_schedule_section.dart',
    };
    final pattern = RegExp(r'(add|subtract)\((const )?Duration\(days');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (utcOnlyFiles.contains(path)) continue;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (pattern.hasMatch(lines[index])) offenders.add('$path:${index + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'use addCalendarDays or DateUtils.addDaysToDate');
  });
}
