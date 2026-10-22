part of 'dose_outbox_store.dart';

// 필요시 복용 의도는 일반 시간대 전송 대기열과 섞지 않고 같은 암호화 DB에 보관한다.
extension DoseHistoryPendingStore on DoseOutboxStore {
  Future<void> _requireHistoryOwner(DatabaseExecutor tx, String token) async {
    final active = await tx.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['active'],
    );
    if (active.isEmpty || active.single['value'] != token) {
      throw StateError('Account changed.');
    }
  }

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

  Future<List<Map<String, dynamic>>> readHistoryPending(String owner) async {
    final token = await ownerKey(owner);
    return db.transaction((tx) async {
      await _requireHistoryOwner(tx, token);
      return _readHistoryPending(tx, token);
    });
  }

  // 미확인 의도가 남아 있으면 새 번호로 덮어쓰지 않고 먼저 저장된 의도를 돌려준다.
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
