import '../entities/medication_history_entity.dart';
import 'dose_outbox_store.dart';

// 필요시 복용의 식별자·확정한 시각을 기기 암호화 저장소와 연결한다.
class AsNeededPendingStore {
  AsNeededPendingStore({Future<DoseOutboxStore> Function()? openStore})
    : _openStore = openStore ?? DoseOutboxStore.open;

  final Future<DoseOutboxStore> Function() _openStore;

  Future<List<MedicationHistoryChange>> read(String owner) async =>
      (await (await _openStore()).readHistoryPending(
        owner,
      )).map(_decode).toList();

  Future<List<MedicationHistoryChange>> stage(
    String owner,
    List<MedicationHistoryChange> changes,
  ) async => (await (await _openStore()).stageHistoryPending(
    owner,
    changes.map(_encode).toList(),
  )).map(_decode).toList();

  Future<void> remove(String owner, Set<String> operationIds) async =>
      (await _openStore()).removeHistoryPending(owner, operationIds);

  static Map<String, dynamic> _encode(MedicationHistoryChange change) => {
    'operation_id': change.operationId,
    'status': change.status.name,
    'actual_taken_at': change.actualTakenAt?.toUtc().toIso8601String(),
    'reason': change.reason,
    'entry': {
      'medication_id': change.entry.medicationId,
      'item_name': change.entry.itemName,
      'schedule_date': MedicationHistoryDates.format(change.entry.scheduleDate),
      'slot_key': change.entry.slotKey,
      'dosing_mode': change.entry.dosingMode,
      'status': change.entry.status.name,
      'revision': change.entry.revision,
    },
  };

  static MedicationHistoryChange _decode(Map<String, dynamic> json) {
    final entry = MedicationHistoryEntry.fromJson(
      Map<String, dynamic>.from(json['entry'] as Map),
    );
    final operation = json['operation_id'] as String;
    if (!entry.isAsNeeded ||
        entry.revision != 0 ||
        !entry.slotKey.startsWith('as_needed:') ||
        !MedicationHistoryChange.isUuid(operation)) {
      throw const FormatException('Invalid pending as-needed dose.');
    }
    return MedicationHistoryChange(
      entry: entry,
      status: MedicationHistoryStatus.parse(json['status']),
      operationId: operation,
      actualTakenAt: MedicationHistoryDates.parseTimestamp(
        json['actual_taken_at'],
      ),
      reason: json['reason'] as String? ?? '',
    );
  }
}
