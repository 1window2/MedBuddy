// 파일명: manual_medication_entry_entity_test.dart
// 역할: 직접 등록 입력이 기존 복약 일정 형식으로 정확히 변환되는지 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';

// 함수이름: main
// 함수역할:
// - 직접 등록한 복용 기간과 일정 변환 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 직접 등록한 시작일과 종료일을 양끝을 포함한 복용 일수로 계산한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('직접 등록한 시작일과 종료일을 양끝을 포함한 복용 일수로 계산한다', () {
    final entry = ManualMedicationEntry(
      medicationName: ' 테스트약 ',
      dosageAmount: '0.5',
      dosageUnit: '정',
      startDate: DateTime(2026, 8, 23, 18),
      endDate: DateTime(2026, 8, 26, 9),
      scheduleSlotKeys: const ['morning', 'evening'],
    );

    expect(entry.totalDays, 4);
    expect(entry.dosage, '0.5정');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 복용 일수는 달력 날짜만으로 계산해 서머타임 전환일이 끼어도 하루가 줄지 않는다.
  //   전환일이 있는 시간대(예: TZ=America/New_York)에서 실행하면 현지 시각 차이로 계산하던 방식은 실패한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('복용 일수는 서머타임 전환일이 끼어도 달력 날짜로 계산한다', () {
    // 2026-03-08(미국), 2026-03-29(유럽)은 하루가 23시간, 2026-11-01(미국)은 25시간인 날이다.
    expect(
      inclusiveMedicationCourseDays(DateTime(2026, 3, 7), DateTime(2026, 3, 9)),
      3,
    );
    expect(
      inclusiveMedicationCourseDays(DateTime(2026, 3, 8), DateTime(2026, 3, 9)),
      2,
    );
    expect(
      inclusiveMedicationCourseDays(
        DateTime(2026, 3, 28),
        DateTime(2026, 3, 30),
      ),
      3,
    );
    expect(
      inclusiveMedicationCourseDays(
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 2),
      ),
      3,
    );
    expect(
      inclusiveMedicationCourseDays(
        DateTime(2026, 3, 7, 23, 30),
        DateTime(2026, 3, 9, 0, 15),
      ),
      3,
    );
    expect(
      inclusiveMedicationCourseDays(
        DateTime.utc(2026, 3, 7),
        DateTime.utc(2026, 3, 9),
      ),
      3,
    );
    expect(
      inclusiveMedicationCourseDays(DateTime(2026, 8, 23), DateTime(2026, 8, 23)),
      1,
    );
    expect(
      inclusiveMedicationCourseDays(DateTime(2016, 8, 24), DateTime(2026, 8, 21)),
      3650,
    );

    final entry = ManualMedicationEntry(
      medicationName: '테스트약',
      dosageAmount: '1',
      dosageUnit: '정',
      startDate: DateTime(2026, 3, 7),
      endDate: DateTime(2026, 3, 9),
      scheduleSlotKeys: const ['morning'],
    );
    expect(entry.totalDays, 3);
    expect(entry.toMedicationSchedule().medicationTime, 3);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 직접 등록값은 기존 저장 흐름이 사용하는 복약 일정으로 변환된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('직접 등록값은 기존 저장 흐름이 사용하는 복약 일정으로 변환된다', () {
    final entry = ManualMedicationEntry(
      medicationName: ' 테스트약 ',
      dosageAmount: '1',
      dosageUnit: '캡슐',
      startDate: DateTime(2026, 8, 23),
      endDate: DateTime(2026, 8, 25),
      scheduleSlotKeys: const ['morning', 'lunch', 'evening'],
      localImagePath: 'local-pill.jpg',
    );

    final schedule = entry.toMedicationSchedule();

    expect(schedule.medicationName, '테스트약');
    expect(schedule.rawMedicationName, '테스트약');
    expect(schedule.dosage, '1캡슐');
    expect(schedule.intakeTime, '3회');
    expect(schedule.medicationTime, 3);
    expect(schedule.scheduleSlotKeys, ['morning', 'lunch', 'evening']);
    expect(schedule.nameCorrectionSource, 'manual_entry');
    expect(schedule.prescriptionDate, DateTime(2026, 8, 23));
  });
}
