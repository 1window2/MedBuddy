// File Name: medication_schedule_entity_test.dart
// Role: Regression coverage for preserved OCR dosage values, explicit localized units, frequency
//   labels and slot-key derivation.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_schedule_slot_policy.dart';

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

  // 함수이름: 복용 횟수 표시 문구 테스트
  // 함수역할: 영어 화면에서 "3회"·"1일 3회"·숫자만 있는 횟수를 문장으로 바꾸고, 읽을 수 없는 문구와
  //   한국어 표시는 저장된 그대로 두는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('frequency label reads the stored count forms in English', () {
    String label(String intakeTime, String language) => MedicationSchedule(
      medicationName: 'synthetic',
      intakeTime: intakeTime,
    ).dailyFrequencyLabelForLanguage(language);

    expect(label('3회', 'en'), '3 times daily');
    expect(label('1일 3회', 'en'), '3 times daily');
    expect(label('1일3회', 'en'), '3 times daily');
    expect(label('3', 'en'), '3 times daily');
    expect(label('1회', 'en'), 'once daily');
    expect(label(' 2회 ', 'en'), '2 times daily');
    // 읽을 수 없는 문구는 추측하지 않고 그대로 보여 준다.
    expect(label('필요시 복용', 'en'), '필요시 복용');
    expect(label('1일 3회 식후 30분', 'en'), '1일 3회 식후 30분');
    expect(label('0회', 'en'), '0회');
    expect(label('', 'en'), 'Frequency not available');

    expect(label('3회', 'ko'), '3회');
    expect(label('1일 3회', 'ko'), '1일 3회');
    expect(label('필요시 복용', 'ko'), '필요시 복용');
    expect(label('', 'ko'), '복용 횟수 정보 없음');
  });

  // 함수이름: 복약 시간대 유도 테스트
  // 함수역할: 명시 시간대, 하루 복용 횟수, 완료 상태가 기록된 시간대 순으로 시간대를 정하고 화면
  //   분류용 정책 함수가 같은 결과를 내는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 불일치 시 테스트 실패.
  test('slot keys come from explicit slots, then frequency, then recorded statuses', () {
    const explicit = MedicationSchedule(
      medicationName: 'explicit',
      intakeTime: '3회',
      scheduleSlotKeys: ['lunch'],
      slotStatuses: {'morning': true, 'lunch': false},
    );
    const byFrequency = MedicationSchedule(
      medicationName: 'frequency',
      intakeTime: '2회',
      slotStatuses: {'bedtime': true},
    );
    const byStatuses = MedicationSchedule(
      medicationName: 'statuses',
      slotStatuses: {'bedtime': true, 'lunch': false, 'unknown': true},
    );
    const unknownStatusesOnly = MedicationSchedule(
      medicationName: 'unknown',
      slotStatuses: {'unknown': true},
    );
    const nothing = MedicationSchedule(medicationName: 'nothing');

    expect(explicit.slotKeys, ['lunch']);
    expect(byFrequency.slotKeys, ['morning', 'evening']);
    // 횟수를 알 수 없으면 기록된 시간대를 정해진 순서로 쓴다.
    expect(byStatuses.slotKeys, ['lunch', 'bedtime']);
    expect(unknownStatusesOnly.slotKeys, ['morning']);
    expect(nothing.slotKeys, ['morning']);
    for (final schedule in [
      explicit,
      byFrequency,
      byStatuses,
      unknownStatusesOnly,
      nothing,
    ]) {
      expect(resolveScheduleSlotKeys(schedule), schedule.slotKeys);
      // 저장·복원해도 같은 시간대가 유지된다.
      expect(
        MedicationSchedule.fromScheduleJson(schedule.toJson()).slotKeys,
        schedule.slotKeys,
      );
    }
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
