import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';

void main() {
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

  test('explicit structured dosage units remain localized', () {
    const schedule = MedicationSchedule(
      medicationName: '테스트 캡슐',
      dosage: '2캡슐',
    );

    expect(schedule.dosageLabelForLanguage('ko'), '2캡슐');
    expect(schedule.dosageLabelForLanguage('en'), '2 capsule');
  });
}
