// File Name: medication_slot_label_test.dart
// Role: Regression coverage for the shared medication slot names and the shared schedule limits
//   (course length and start-date window).

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_limits.dart';
import 'package:medbuddy_frontend/entities/medication_slot_label.dart';

// Function Name: main
// Description:
// - Register regression cases for the shared medication slot names and the shared schedule limits.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  group('medication slot label', () {
    const slotNames = <String, (String, String, String)>{
      'morning': ('Morning', 'morning', '아침'),
      'lunch': ('Lunch', 'lunch', '점심'),
      'evening': ('Evening', 'evening', '저녁'),
      'bedtime': ('Bedtime', 'bedtime', '취침 전'),
    };

    // Function Name: test callback
    // Description:
    // - Expected behavior: each of the four keys maps to its title form, its English sentence
    //   form and its Korean name; lowercase does not alter Korean names.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('maps the four slot keys in both languages and both forms', () {
      for (final entry in slotNames.entries) {
        final (title, sentence, korean) = entry.value;

        expect(medicationSlotLabelOrNull(entry.key, isEnglish: true), title);
        expect(
          medicationSlotLabelOrNull(entry.key, isEnglish: true, lowercase: true),
          sentence,
        );
        expect(medicationSlotLabelOrNull(entry.key, isEnglish: false), korean);
        expect(
          medicationSlotLabelOrNull(entry.key, isEnglish: false, lowercase: true),
          korean,
        );
        expect(medicationSlotLabel(entry.key, isEnglish: true), title);
        expect(medicationSlotLabel(entry.key, isEnglish: false), korean);
        expect(
          medicationSlotLabel(entry.key, isEnglish: false, fallback: '일정'),
          korean,
          reason: 'a fallback must not replace a known slot name',
        );
      }
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a key outside the four slots, including a differently cased or empty
    //   one, has no name instead of being shown as another slot.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('returns null for an unknown key', () {
      for (final slotKey in ['', 'night', 'Morning', ' morning']) {
        expect(medicationSlotLabelOrNull(slotKey, isEnglish: true), isNull);
        expect(medicationSlotLabelOrNull(slotKey, isEnglish: false), isNull);
        expect(
          medicationSlotLabelOrNull(slotKey, isEnglish: true, lowercase: true),
          isNull,
        );
      }
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: an unknown key shows the caller's fallback, or the key itself when no
    //   fallback is given.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('uses the caller fallback or the key for an unknown key', () {
      expect(medicationSlotLabel('night', isEnglish: true), 'night');
      expect(medicationSlotLabel('night', isEnglish: false), 'night');
      expect(
        medicationSlotLabel('night', isEnglish: true, fallback: 'Schedule'),
        'Schedule',
      );
      expect(
        medicationSlotLabel('night', isEnglish: false, fallback: '일정'),
        '일정',
      );
    });
  });

  group('medication schedule limits', () {
    // Function Name: test callback
    // Description:
    // - Expected behavior: a course lasts 1 to 3650 days; zero, negative, longer and unreadable
    //   values are rejected.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('accepts course lengths from 1 to 3650 days only', () {
      expect(maxMedicationCourseDays, 3650);
      expect(isValidMedicationCourseDays(null), isFalse);
      expect(isValidMedicationCourseDays(-1), isFalse);
      expect(isValidMedicationCourseDays(0), isFalse);
      expect(isValidMedicationCourseDays(1), isTrue);
      expect(isValidMedicationCourseDays(3650), isTrue);
      expect(isValidMedicationCourseDays(3651), isFalse);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: the start-date window runs from 1 January 2000 to the day 365 days
    //   after the given moment, with the time of day removed.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('bounds the start date between 2000-01-01 and today plus 365 days', () {
      expect(earliestMedicationStartDate(), DateTime(2000, 1, 1));
      expect(
        latestMedicationStartDate(DateTime(2026, 3, 10, 15, 42, 7)),
        DateTime(2027, 3, 10),
      );
      expect(
        latestMedicationStartDate(DateTime(2026, 3, 10)),
        DateTime(2027, 3, 10),
      );
      // 365 days after a date before 29 February of a leap year lands one calendar day short of the same date.
      expect(
        latestMedicationStartDate(DateTime(2027, 12, 31, 23, 59)),
        DateTime(2028, 12, 30),
      );
    });
  });
}
