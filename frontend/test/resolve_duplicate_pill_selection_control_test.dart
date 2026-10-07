// 파일명: resolve_duplicate_pill_selection_control_test.dart
// 역할: 같은 알약 사진의 안내와 복약 일정 병합 조건을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/resolve_duplicate_pill_selection_control.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';

// 함수이름: main
// 함수역할:
// - 품목 식별자와 검토 일정에 따른 중복 알약 묶기 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  const control = ResolveDuplicatePillSelectionControl();

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 같은 품목으로 선택한 사진 수를 중복 그룹으로 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 품목과 검토한 복약 일정이 모두 같으면 하나로 묶는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('품목과 검토한 복약 일정이 모두 같으면 하나로 묶는다', () {
    final requests = control.mergeEquivalentRequests([_request(), _request()]);

    expect(requests, hasLength(1));
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 같은 약도 복용량이나 기간이 다르면 별도 일정으로 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('같은 약도 복용량이나 기간이 다르면 별도 일정으로 유지한다', () {
    final requests = control.mergeEquivalentRequests([
      _request(dosage: '1정', totalDays: 3),
      _request(dosage: '0.5정', totalDays: 3),
      _request(dosage: '1정', totalDays: 5),
    ]);

    expect(requests, hasLength(3));
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 품목번호가 없는 서로 다른 약명은 중복으로 합치지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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

// 함수이름: _candidate
// 함수역할:
// - 품목 식별자와 약명을 지정한 고정 신뢰도 후보를 만든다.
// 매개변수:
// - itemSeq (String): 중복 비교에 사용할 식약처 품목 식별자.
// - itemName (String): 후보 대역을 구분할 약명.
// 반환값:
// - 제조사와 일치 점수 0.9가 포함된 후보.
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

// 함수이름: _request
// 함수역할:
// - 동일 품목의 복용량과 기간만 달리한 아침·저녁 복약 저장 요청을 만든다.
// 매개변수:
// - dosage (String): 명시된 단위가 있으면 그대로 보존하는 1회 복용량.
// - totalDays (int): 복용 시작일을 포함한 전체 복용 일수.
// 반환값:
// - 2026-08-25 시작 일정과 후보가 결합된 저장 요청.
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
