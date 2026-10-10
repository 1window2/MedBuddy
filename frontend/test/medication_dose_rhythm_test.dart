// File Name: medication_dose_rhythm_test.dart
// Role: Checks the dose-day rules against the vectors the server is tested with as well.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
