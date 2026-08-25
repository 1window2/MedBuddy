// 파일명: resolve_duplicate_pill_selection_control_test.dart
// 역할: 같은 알약 사진의 안내와 복약 일정 병합 조건을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/resolve_duplicate_pill_selection_control.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';

void main() {
  const control = ResolveDuplicatePillSelectionControl();

  test('같은 품목으로 선택한 사진 수를 중복 그룹으로 반환한다', () {
    final groups = control.findDuplicateGroups([
      _candidate(itemSeq: 'same-pill', itemName: '같은 약'),
      _candidate(itemSeq: 'same-pill', itemName: '같은 약'),
      _candidate(itemSeq: 'other-pill', itemName: '다른 약'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.itemSeq, 'same-pill');
    expect(groups.single.count, 2);
  });

  test('품목과 검토한 복약 일정이 모두 같으면 하나로 묶는다', () {
    final requests = control.mergeEquivalentRequests([_request(), _request()]);

    expect(requests, hasLength(1));
  });

  test('같은 약도 복용량이나 기간이 다르면 별도 일정으로 유지한다', () {
    final requests = control.mergeEquivalentRequests([
      _request(dosage: '1정', totalDays: 3),
      _request(dosage: '0.5정', totalDays: 3),
      _request(dosage: '1정', totalDays: 5),
    ]);

    expect(requests, hasLength(3));
  });

  test('품목번호가 없는 서로 다른 약명은 중복으로 합치지 않는다', () {
    final candidates = [
      _candidate(itemSeq: '', itemName: '첫 번째 약'),
      _candidate(itemSeq: '', itemName: '두 번째 약'),
      _candidate(itemSeq: '', itemName: ' 첫 번째  약 '),
    ];

    expect(control.findDuplicateGroups(candidates), hasLength(1));
    expect(control.uniqueCandidates(candidates), hasLength(2));
    expect(control.countEquivalentCandidates(candidates, candidates.first), 2);
  });
}

PillIdentificationCandidate _candidate({
  required String itemSeq,
  required String itemName,
}) {
  return PillIdentificationCandidate(
    itemSeq: itemSeq,
    itemName: itemName,
    manufacturer: '제조사',
    matchScore: 0.9,
  );
}

IdentifiedPillSaveRequest _request({String dosage = '1정', int totalDays = 3}) {
  return IdentifiedPillSaveRequest(
    candidate: _candidate(itemSeq: 'same-pill', itemName: '같은 약'),
    medicationSchedule: MedicationSchedule(
      medicationName: '같은 약',
      prescriptionDate: DateTime(2026, 8, 25),
      dosage: dosage,
      intakeTime: '2회',
      medicationTime: totalDays,
      scheduleSlotKeys: const ['morning', 'evening'],
    ),
  );
}
