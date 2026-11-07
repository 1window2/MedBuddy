// 파일명: dose_history_pending_store.dart
// 역할: 필요시 복용의 미확인 요청을 계정별 암호화 저장소에 유지한다.
part of 'dose_outbox_store.dart';

// 필요시 복용 의도는 일반 시간대 전송 대기열과 섞지 않고 같은 암호화 DB에 보관한다.
// 클래스명: DoseHistoryPendingStore
// 역할: 전송 확인 전의 필요시 복용 요청을 저장소에 연결하는 확장이다.
// 주요 책임: 활성 계정 검증, 기존 요청 ID 보존, 확인한 요청만 제거, 키 유실용 건수 유지.
// 속성: 추가 필드 없음. DoseOutboxStore의 DB·암호화 키·계정 검증 도우미를 사용한다.
extension DoseHistoryPendingStore on DoseOutboxStore {
  // Function Name: _requireHistoryOwner
  // Description: Rejects history work after the active account changed within the transaction.
  // Parameters: tx (DatabaseExecutor) - current transaction; token (String) - expected owner hash.
  // Returns: Completion for matching ownership; otherwise throws StateError.
  Future<void> _requireHistoryOwner(DatabaseExecutor tx, String token) async {
    if (await _activeToken(tx) != token) {
      throw StateError('Account changed.');
    }
  }

  // 함수이름: _readHistoryPending
  // 함수역할: 트랜잭션에서 계정의 changes 목록을 복호화하여 독립된 맵 목록으로 읽는다.
  // 매개변수: tx (DatabaseExecutor) - 읽기 연결; token (String) - 계정 해시.
  // 반환값: 저장된 요청 목록, 없으면 빈 목록. DB·암호화·형식 오류는 전파한다.
  Future<List<Map<String, dynamic>>> _readHistoryPending(
    DatabaseExecutor tx,
    String token,
  ) async {
    final rows = await tx.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['history-pending:$token'],
    );
    if (rows.isEmpty) return [];
    final value = await _decrypt(rows.single['value'] as String, token);
    return (value['changes'] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  // 함수이름: readHistoryPending
  // 함수역할: 활성 계정 검증과 필요시 복용 대기 요청 조회를 한 트랜잭션으로 묶는다.
  // 매개변수: owner (String) - 조회할 계정
  // 반환값: 복호화한 요청 목록. 계정 변경은 StateError, 저장소 오류는 그대로 전파한다.
  Future<List<Map<String, dynamic>>> readHistoryPending(String owner) async {
    final token = await ownerKey(owner);
    return db.transaction((tx) async {
      await _requireHistoryOwner(tx, token);
      return _readHistoryPending(tx, token);
    });
  }

  // 미확인 의도가 남아 있으면 새 번호로 덮어쓰지 않고 먼저 저장된 의도를 돌려준다.
  // 함수이름: stageHistoryPending
  // 함수역할: 기존 미확인 요청을 우선 유지하고 없을 때만 새 요청 묶음과 건수를 저장한다.
  // 매개변수: owner (String) - 활성 계정; changes (List<Map<String, dynamic>>) - 새 요청 묶음.
  // 반환값: 실제로 유지한 기존 또는 새 요청 목록. 계정 변경·저장 오류는 예외로 전달한다.
  Future<List<Map<String, dynamic>>> stageHistoryPending(
    String owner,
    List<Map<String, dynamic>> changes,
  ) async {
    final token = await ownerKey(owner);
    return db.transaction((tx) async {
      await _requireHistoryOwner(tx, token);
      final existing = await _readHistoryPending(tx, token);
      if (existing.isNotEmpty) return existing;
      await _writeHistoryPending(tx, token, changes);
      return changes;
    });
  }

  // 함수이름: _writeHistoryPending
  // 함수역할: 요청 본문은 암호화하고 유실 안내용 건수만 평문으로 저장한다. 빈 목록이면 두 키를 삭제한다.
  // 매개변수: tx (DatabaseExecutor) - 호출자의 트랜잭션; token (String) - 계정 해시; changes - JSON 요청 목록.
  // 반환값: 저장·삭제 완료 Future. 자체 계정 검사 없이 전달받은 트랜잭션을 사용하며 오류는 전파한다.
  Future<void> _writeHistoryPending(
    DatabaseExecutor tx,
    String token,
    List<Map<String, dynamic>> changes,
  ) async {
    if (changes.isEmpty) {
      await tx.delete(
        'metadata',
        where: 'name IN (?, ?)',
        whereArgs: ['history-pending:$token', 'history-pending-count:$token'],
      );
      return;
    }
    await tx.insert('metadata', {
      'name': 'history-pending:$token',
      'value': await _encrypt({'changes': changes}, token),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // 키 유실 안내에는 건강정보 없이 복구 불가능한 요청 개수만 사용한다.
    await tx.insert('metadata', {
      'name': 'history-pending-count:$token',
      'value': '${changes.length}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 함수이름: removeHistoryPending
  // 함수역할: 확인 완료된 operation_id만 제거하고 나머지 요청과 유실용 건수를 유지한다.
  // 매개변수: owner (String) - 활성 계정; operationIds (Set<String>) - 제거할 요청 ID 집합.
  // 반환값: 반영 완료 Future. 빈 ID 집합은 즉시 완료하며 계정 변경·저장 오류는 전파한다.
  Future<void> removeHistoryPending(
    String owner,
    Set<String> operationIds,
  ) async {
    if (operationIds.isEmpty) return;
    final token = await ownerKey(owner);
    await db.transaction((tx) async {
      await _requireHistoryOwner(tx, token);
      final existing = await _readHistoryPending(tx, token);
      await _writeHistoryPending(
        tx,
        token,
        existing
            .where((entry) => !operationIds.contains(entry['operation_id']))
            .toList(),
      );
    });
  }
}
