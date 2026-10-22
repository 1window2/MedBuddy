import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/services/as_needed_pending_store.dart';

// 화면 테스트의 저장소만 격리하며 실제 암호화·재시작 동작은 별도 테스트한다.
class FakeAsNeededPendingStore extends AsNeededPendingStore {
  final Map<String, List<MedicationHistoryChange>> batches = {};
  bool failStage = false;
  bool failRemove = false;

  @override
  Future<List<MedicationHistoryChange>> read(String owner) async =>
      List.of(batches[owner] ?? []);

  @override
  Future<List<MedicationHistoryChange>> stage(
    String owner,
    List<MedicationHistoryChange> changes,
  ) async {
    if (failStage) throw StateError('Storage unavailable');
    if (batches[owner]?.isNotEmpty != true) batches[owner] = List.of(changes);
    return read(owner);
  }

  @override
  Future<void> remove(String owner, Set<String> operationIds) async {
    if (failRemove) throw StateError('Storage unavailable');
    batches[owner]?.removeWhere(
      (change) => operationIds.contains(change.operationId),
    );
  }
}
