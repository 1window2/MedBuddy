// File Name: medication_dose_rhythm_test.dart
// Role: Checks the dose-day rules against the vectors the server is tested with as well.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_dose_rhythm.dart';

// Function Name: main
// Description: Registers the shared-vector cases for frequency labels, duration labels and dose days.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  final vectors =
      jsonDecode(
            File(
              '../backend/tests/data/dose_rhythm_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  // Function Name: frequency vector test
  // Description: Every frequency label yields the listed cycle and per-day dose count.
  // Parameters: None. Returns: None; a mismatch fails the test.
  test('frequency labels give the dose cycle and the doses per dose day', () {
    for (final vector in (vectors['frequency'] as List).cast<Map>()) {
      final text = vector['text'] as String;
      final cycle = readDoseCycle(text);
      expect(
        [cycle.cycleDays, cycle.offsets, cycle.weekdayAnchored],
        vector['cycle'],
        reason: 'cycle of "$text"',
      );
      expect(
        readDosesPerDoseDay(text),
        vector['doses'],
        reason: 'doses of "$text"',
      );
    }
  });

  // Function Name: duration vector test
  // Description: Every duration label yields the listed number of days.
  // Parameters: None. Returns: None; a mismatch fails the test.
  test('duration labels are read with their unit', () {
    for (final vector in (vectors['duration'] as List).cast<Map>()) {
      final text = vector['text'] as String;
      expect(readDurationDays(text), vector['days'], reason: '"$text"');
    }
  });

  // Function Name: dose day vector test
  // Description: A date is a dose day exactly when the vector says so.
  // Parameters: None. Returns: None; a mismatch fails the test.
  test('dose days follow the cycle from the course start', () {
    for (final vector in (vectors['due'] as List).cast<Map>()) {
      final text = vector['text'] as String;
      final date = vector['date'] as String;
      expect(
        readDoseCycle(text).includes(
          DateTime.parse(vector['start'] as String),
          DateTime.parse(date),
        ),
        vector['due'],
        reason: '"$text" on $date',
      );
    }
  });

  // Function Name: cycle arithmetic test
  // Description: Dates before the anchor and a missing anchor are handled without a negative remainder or an exception.
  // Parameters: None. Returns: None; a mismatch fails the test.
  test('cycle arithmetic handles dates before the anchor', () {
    final anchor = DateTime(2026, 10, 7);
    bool due(DateTime date) => isDoseDayOfCycle(
      cycleDays: 7,
      offsets: const [0],
      anchor: anchor,
      date: date,
    );

    expect(due(DateTime(2026, 9, 30)), isTrue);
    expect(due(DateTime(2026, 10, 6)), isFalse);
    expect(due(DateTime(2026, 10, 7, 23, 59)), isTrue);
    expect(
      isDoseDayOfCycle(
        cycleDays: 7,
        offsets: const [0],
        anchor: null,
        date: anchor,
      ),
      isTrue,
    );
  });

  // Function Name: next dose day test
  // Description: The next dose day is the first dose day on or after the asked date, never before the course starts, and none once the course has ended.
  // Parameters: None. Returns: None; a mismatch fails the test.
  test('next dose day skips rest days and stops at the course end', () {
    // 2026-10-07 is a Wednesday.
    final start = DateTime(2026, 10, 7);
    final weekly = readDoseCycle('주 1회');
    final alternate = readDoseCycle('격일');
    final weekdays = readDoseCycle('월수금');

    expect(nextDoseDay(weekly, startDate: start, from: start), start);
    expect(
      nextDoseDay(weekly, startDate: start, from: DateTime(2026, 10, 8, 21)),
      DateTime(2026, 10, 14),
    );
    expect(
      nextDoseDay(alternate, startDate: start, from: DateTime(2026, 10, 8)),
      DateTime(2026, 10, 9),
    );
    expect(
      nextDoseDay(weekdays, startDate: start, from: DateTime(2026, 10, 10)),
      DateTime(2026, 10, 12),
    );
    expect(
      nextDoseDay(weekly, startDate: start, from: DateTime(2026, 10, 1)),
      start,
    );
    expect(
      nextDoseDay(
        weekly,
        startDate: start,
        from: DateTime(2026, 10, 8),
        endDate: DateTime(2026, 10, 13),
      ),
      isNull,
    );
    expect(
      nextDoseDay(
        weekly,
        startDate: start,
        from: DateTime(2026, 10, 8),
        endDate: DateTime(2026, 10, 14),
      ),
      DateTime(2026, 10, 14),
    );
  });

  // Function Name: saved medication next dose day test
  // Description: A saved medication reports a next dose day only when it is not taken every day, counting from the dispensing date or, without one, the registration date.
  // Parameters: None. Returns: None; a mismatch fails the test.
  test('saved medication reports the next dose day of a non-daily course', () {
    MedicationDetail medication(
      String frequency, {
      DateTime? prescriptionDate,
      DateTime? createdDate,
      String totalDays = '28',
    }) => MedicationDetail(
      itemName: 'next dose day',
      efficacy: '',
      usageMethod: '',
      warning: '',
      dailyFrequency: frequency,
      totalDays: totalDays,
      prescriptionDate: prescriptionDate,
      createdDate: createdDate,
    );
    final start = DateTime(2026, 10, 7);
    final asked = DateTime(2026, 10, 9);

    expect(
      medication('주 1회', prescriptionDate: start).nextDoseDayFrom(asked),
      DateTime(2026, 10, 14),
    );
    expect(
      medication('주 1회', createdDate: start).nextDoseDayFrom(asked),
      DateTime(2026, 10, 14),
    );
    expect(
      medication('1일 3회', prescriptionDate: start).nextDoseDayFrom(asked),
      isNull,
    );
    expect(medication('주 1회').nextDoseDayFrom(asked), isNull);
    expect(
      medication(
        '주 1회',
        prescriptionDate: start,
        totalDays: '7',
      ).nextDoseDayFrom(asked),
      isNull,
    );
  });
}
