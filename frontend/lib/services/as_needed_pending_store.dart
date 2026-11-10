// 파일명: as_needed_pending_store.dart
// 역할: 필요시 복용 변경 모델과 암호화한 미확인 요청 JSON을 연결한다.
import '../entities/medication_history_entity.dart';
import 'dose_outbox_store.dart';

// 필요시 복용의 식별자·확정한 시각을 기기 암호화 저장소와 연결한다.
// 클래스명: AsNeededPendingStore
// 역할: 재시작 뒤에도 동일한 필요시 복용 요청 ID와 복용 시각을 복원한다.
// 주요 책임: 요청 모델의 직렬화·검증과 계정별 저장·확인 삭제를 위임한다.
// 속성: _openStore (Future<DoseOutboxStore> Function()) - 공유 암호화 저장소 공급자.
class AsNeededPendingStore {
  // 함수이름: AsNeededPendingStore
  // 함수역할: 저장소 열기 함수를 주입하며 생성 시에는 실제 저장소를 열지 않는다.
  // 매개변수: openStore - 비동기 저장소 공급자. 없으면 DoseOutboxStore.open 사용.
  // 반환값: 필요시 복용 대기 저장 어댑터.
  AsNeededPendingStore({Future<DoseOutboxStore> Function()? openStore})
    : _openStore = openStore ?? DoseOutboxStore.open;

  final Future<DoseOutboxStore> Function() _openStore;

  // 함수이름: read
  // 함수역할: 활성 계정의 미확인 요청을 읽고 필요시 복용 변경 모델로 검증·복원한다.
  // 매개변수: owner (String) - 계정 식별자
  // 반환값: 저장된 변경 목록 Future. 계정 변경·저장소·잘못된 요청 형식은 예외로 전달한다.
  Future<List<MedicationHistoryChange>> read(String owner) async =>
      (await (await _openStore()).readHistoryPending(
        owner,
      )).map(_decode).toList();

  // 함수이름: stage
  // 함수역할: 새 요청을 직렬화해 맡기되 이미 미확인 요청이 있으면 기존 요청을 반환한다.
  // 매개변수: owner (String) - 활성 계정; changes (List<MedicationHistoryChange>) - 저장하려는 변경 묶음.
  // 반환값: 저장소가 실제로 유지한 요청 모델 목록. 저장·복원 오류는 전파한다.
  Future<List<MedicationHistoryChange>> stage(
    String owner,
    List<MedicationHistoryChange> changes,
  ) async => (await (await _openStore()).stageHistoryPending(
    owner,
    changes.map(_encode).toList(),
  )).map(_decode).toList();

  // 함수이름: remove
  // 함수역할: 서버 확인이 끝난 요청 ID만 암호화 저장소에서 제거한다.
  // 매개변수: owner (String) - 계정; operationIds (Set<String>) - 확인한 요청 ID.
  // 반환값: 제거 완료 Future. 저장소 오류는 전파한다.
  Future<void> remove(String owner, Set<String> operationIds) async =>
      (await _openStore()).removeHistoryPending(owner, operationIds);

  // 함수이름: _encode
  // 함수역할: 재전송에 필요한 요청 ID·상태·UTC 복용 시각과 원본 기록 정보를 JSON으로 보존한다.
  // 매개변수: change (MedicationHistoryChange) - 저장할 필요시 복용 변경
  // 반환값: JSON 맵. 입력 유효성 검사는 수행하지 않는다.
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

  // 함수이름: _decode
  // 함수역할: 저장 JSON에서 필요시 복용·초기 버전·슬롯 접두사·UUID를 확인한 뒤 요청을 복원한다.
  // 매개변수: json (Map<String, dynamic>) - _encode가 만든 저장 데이터
  // 반환값: MedicationHistoryChange. 잘못된 요청은 FormatException 또는 필드 형식 오류를 전달한다.
  static MedicationHistoryChange _decode(Map<String, dynamic> json) {
    final entry = MedicationHistoryEntry.fromJson(
      Map<String, dynamic>.from(json['entry'] as Map),
    );
    final operation = json['operation_id'] as String;
    if (!entry.isAsNeeded ||
        entry.revision != 0 ||
        !entry.slotKey.startsWith(
          MedicationHistoryEntry.asNeededEventKeyPrefix,
        ) ||
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
