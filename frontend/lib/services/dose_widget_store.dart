part of 'dose_outbox_store.dart';

// Widget actions and their outbox operation commit together. Multiple widgets,
// rapid taps and retried Android jobs cannot apply one button twice.
extension DoseWidgetStore on DoseOutboxStore {
  // 함수이름: updateWidget
  // 함수역할: 유효한 복용 버튼만 한 번 저장하고 다음 미완료 일정으로 갱신한다.
  // 매개변수: owner 계정, configuration 설정, action 동작, actionToken 중복 방지 토큰,
  //   now 날짜 검증 시각.
  // 반환값: 현재 계정의 위젯 상태. 로그아웃 또는 계정 불일치이면 null.
  Future<DoseWidgetState?> updateWidget({
    String? owner,
    Map<String, dynamic>? configuration,
    String? action,
    String? actionToken,
    required DateTime now,
  }) async {
    final expectedOwner = owner == null ? null : await ownerKey(owner);
    return db.transaction((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      final token = active.firstOrNull?['value'] as String?;
      if (token == null ||
          token.isEmpty ||
          (expectedOwner != null && token != expectedOwner)) {
        return null;
      }
      Future<Map<String, dynamic>?> read(String name) async {
        final rows = await tx.query(
          'metadata',
          where: 'name = ?',
          whereArgs: [name],
        );
        return rows.isEmpty
            ? null
            : _decrypt(rows.single['value'] as String, token);
      }

      final previous = await read('widget:$token') ?? <String, dynamic>{};
      final account = owner ?? previous['owner'] as String?;
      if (account == null) return null;
      final cache = await read('cache:$token');
      final rows = await tx.query(
        'operations',
        where: 'owner = ?',
        whereArgs: [token],
        orderBy: 'seq',
      );
      final operations = <Map<String, dynamic>>[
        for (final row in rows)
          {
            ...await _decrypt(row['payload'] as String, token),
            'state': row['state'],
          },
      ];
      final day = doseWidgetDay(now);
      final candidate = previous['take'] as Map?;
      if (action == 'take' &&
          candidate != null &&
          candidate['token'] == actionToken &&
          candidate['date'] == day &&
          cache?['date'] == day &&
          !operations.any((op) => op['state'] == 'blocked')) {
        final projected = DoseWidgetState.projectedSchedules(
          cache,
          operations,
          day,
        );
        final ids = (candidate['ids'] as List).cast<int>();
        final slot = candidate['slot'] as String;
        final valid =
            ids.isNotEmpty &&
            ids.every(
              (id) => projected.any(
                (s) =>
                    int.tryParse(s.medicationID) == id &&
                    s.slotKeys.contains(slot) &&
                    !s.isSlotCompleted(slot),
              ),
            );
        if (valid) {
          final operation = <String, dynamic>{
            'operation_id': actionToken,
            'schedule_date': day,
            'slot_key': slot,
            'medication_ids': ids,
            'completed': true,
            'medication_names': candidate['names'],
          };
          await tx.insert('operations', {
            'id': actionToken,
            'owner': token,
            'payload': await _encrypt(operation, token),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          operations.add({...operation, 'state': 'pending'});
          previous['take'] = null;
        }
      }
      final result = DoseWidgetState.build(
        owner: account,
        cache: cache,
        operations: operations,
        previous: previous,
        now: now,
        configuration: configuration,
      );
      await tx.insert('metadata', {
        'name': 'widget:$token',
        'value': await _encrypt(result.data, token),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return result;
    });
  }
}
