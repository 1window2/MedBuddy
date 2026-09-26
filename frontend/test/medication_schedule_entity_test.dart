// File Name: medication_schedule_entity_test.dart
// Role: Regression coverage for preserved OCR dosage values and explicit localized units.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';

// Function Name: main
// Description:
// - Register regression cases for preserved OCR dosage values and explicit localized units.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: unitless OCR dosage is preserved instead of inferred from drug name.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test(
    'unitless OCR dosage is preserved instead of inferred from drug name',
    () {
      const liquid = MedicationSchedule(
        medicationName: '어린이 해열 시럽',
        dosage: '5',
      );
      const tablet = MedicationSchedule(medicationName: '테스트정', dosage: '1');

      expect(liquid.dosageLabelForLanguage('ko'), '5');
      expect(liquid.dosageLabelForLanguage('en'), '5');
      expect(tablet.dosageLabelForLanguage('ko'), '1');
      expect(tablet.dosageLabelForLanguage('en'), '1');
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: explicit structured dosage units remain localized.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('explicit structured dosage units remain localized', () {
    const schedule = MedicationSchedule(
      medicationName: '테스트 캡슐',
      dosage: '2캡슐',
    );

    expect(schedule.dosageLabelForLanguage('ko'), '2캡슐');
    expect(schedule.dosageLabelForLanguage('en'), '2 capsule');
  });
}
