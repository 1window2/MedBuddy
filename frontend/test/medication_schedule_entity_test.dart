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
  // 함수이름: 복용 횟수·일수 문구 해석 테스트
  // 함수역할: 횟수는 단위가 붙은 숫자를, 일수는 첫 숫자를 읽어 서버의 해석과 같은 값을 내는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('frequency and duration text follow the server parsing rules', () {
    expect(medicationScheduleCountFromText('1일 3회 식후 30분'), 3);
    expect(medicationScheduleCountFromText('3회 (8시간마다)'), 3);
    expect(medicationScheduleCountFromText('2 times daily'), 2);
    expect(medicationScheduleCountFromText('3회'), 3);
    expect(medicationScheduleCountFromText('하루 2'), 2);
    expect(medicationScheduleCountFromText(4), 4);
    expect(medicationScheduleCountFromText('수시'), 0);

    expect(medicationDayCountFromText('7일분 (1주)'), 7);
    expect(medicationDayCountFromText('30'), 30);
    expect(medicationDayCountFromText('총 5일'), 5);
    expect(medicationDayCountFromText(14), 14);
    expect(medicationDayCountFromText(''), 0);

    final schedule = MedicationSchedule.fromAnalysisJson(const {
      'drug_name': 'synthetic',
      'daily_frequency': '1일 3회 식후 30분',
      'total_days': '7일분 (1주)',
    });
    expect(schedule.dailyFrequencyCount, 3);
    expect(schedule.medicationTime, 7);
  });

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
