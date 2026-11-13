// 파일명: fake_as_needed_pending_store.dart
// 역할: 필요시 복약 화면 테스트에 계정별 메모리 대기열과 저장소 실패를 제공한다.

import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/services/as_needed_pending_store.dart';

// 화면 테스트의 저장소만 격리하며 실제 암호화·재시작 동작은 별도 테스트한다.
// 클래스명: FakeAsNeededPendingStore
// 역할: 계정당 최초 미전송 묶음을 보존하는 메모리 저장소 대역이다.
// 주요 책임:
// - 대기 기록 읽기·등록·작업 ID별 삭제를 수행하고 선택한 단계의 오류를 재현한다.
// 속성:
// - batches(Map<String, List<MedicationHistoryChange>>): 계정별 대기 기록.
// - failStage / failRemove / failRead(bool): 해당 작업에서 StateError를 발생시키는 설정.
class FakeAsNeededPendingStore extends AsNeededPendingStore {
  final Map<String, List<MedicationHistoryChange>> batches = {};
  bool failStage = false;
  bool failRemove = false;
  bool failRead = false;

  // Function Name: read
  // Description:
  // - Return a shallow copy of the owner's pending batch, or simulate unavailable storage.
  // Parameters:
  // - owner (String): Account whose pending changes are requested.
  // Returns:
  // - Future<List<MedicationHistoryChange>>: A separate list, empty for an unknown owner.
  // - Throws StateError when failRead is set.
  @override
  Future<List<MedicationHistoryChange>> read(String owner) async {
    if (failRead) throw StateError('Storage unavailable');
    return List.of(batches[owner] ?? []);
  }

  // 함수이름: stage
  // 함수역할:
  // - 기존 미전송 묶음이 비어 있을 때만 새 목록의 사본을 등록하고 현재 대기 목록을 읽는다.
  // 매개변수:
  // - owner(String): 대기 기록을 소유한 계정.
  // - changes(List<MedicationHistoryChange>): 등록을 시도할 변경 묶음.
  // 반환값:
  // - Future<List<MedicationHistoryChange>>: 유지되거나 새로 등록된 목록의 사본.
  // - failStage가 켜져 있거나 이어지는 read가 실패하면 StateError를 전달한다.
  @override
  Future<List<MedicationHistoryChange>> stage(
    String owner,
    List<MedicationHistoryChange> changes,
  ) async {
    if (failStage) throw StateError('Storage unavailable');
    if (batches[owner]?.isNotEmpty != true) batches[owner] = List.of(changes);
    return read(owner);
  }

  // 함수이름: remove
  // 함수역할:
  // - 지정한 계정에서 승인된 작업 ID와 일치하는 기록만 제거한다.
  // 매개변수:
  // - owner(String): 수정할 대기열의 계정.
  // - operationIds(Set<String>): 제거 대상 작업 ID 집합.
  // 반환값:
  // - Future<void>: 삭제 완료; 계정이 없어도 성공하며 failRemove이면 StateError를 발생시킨다.
  @override
  Future<void> remove(String owner, Set<String> operationIds) async {
    if (failRemove) throw StateError('Storage unavailable');
    batches[owner]?.removeWhere(
      (change) => operationIds.contains(change.operationId),
    );
  }
}
