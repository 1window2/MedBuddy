part of 'dose_outbox_store.dart';

// 버튼 소비와 복약 전송 대기를 같은 트랜잭션에 넣어 엔진 간 동시 클릭도 한 번만 반영한다.
extension SlotCheckNotificationStore on DoseOutboxStore {
  // 함수이름: recordSlotCheck
  // 함수역할: 활성 계정의 오늘 캐시에서 요청 시간대의 약을 골라 미완료가 있으면 완료 기록을 전송 대기열에
  //   넣고, 같은 요청의 버튼을 소비한 것으로 표시한다. 막힌 기록이 있거나 날짜·계정이 바뀌면 저장하지 않는다.
  // 매개변수: request 검증한 확인 요청, clock 오늘 날짜를 정할 시계.
  // 반환값: 저장했거나 이미 처리한 요청이면 true.
  Future<bool> recordSlotCheck(
    SlotCheckNotificationContext request, {
    required DateTime Function() clock,
  }) async {
    final token = await ownerKey(request.owner);
    final digest = (await Sha256().hash(
      utf8.encode('$token|${request.eventId}'),
    )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return db.transaction((tx) async {
      if (await _activeToken(tx) != token ||
          request.scheduleDate != doseWidgetDay(clock())) {
        return false;
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

      final markerKey = 'slot-check:$token';
      final previous = await read(markerKey);
      final consumed = previous?['date'] == request.scheduleDate
          ? (previous?['events'] as List).cast<String>().toSet()
          : <String>{};
      if (consumed.contains(request.eventId)) return true;
      final cache = await read('cache:$token');
      if (cache?['date'] != request.scheduleDate) return false;
      final rows = await tx.query(
        'operations',
        where: 'owner = ?',
        whereArgs: [token],
        orderBy: 'seq',
      );
      final operations = [
        for (final row in rows)
          {
            ...await _decrypt(row['payload'] as String, token),
            'state': row['state'],
          },
      ];
      final schedules = DoseWidgetState.projectedSchedules(
        cache,
        operations,
        request.scheduleDate,
      ).where((item) => item.slotKeys.contains(request.slotKey)).toList();
      if (schedules.isEmpty || schedules.length > 100) return false;
      final ids = schedules
          .map((item) => int.tryParse(item.medicationID))
          .toList();
      if (ids.any((id) => id == null || id <= 0)) return false;
      if (operations.any(
        (op) =>
            op['state'] == 'blocked' &&
            op['schedule_date'] == request.scheduleDate &&
            op['slot_key'] == request.slotKey &&
            (op['medication_ids'] as List).any(ids.contains),
      )) {
        return false;
      }
      if (request.scheduleDate != doseWidgetDay(clock())) return false;
      // 서버 확인 뒤 버튼을 다시 눌러도, 이후 사용자가 취소한 복용을 되살리지 않는다.
      if (schedules.any((item) => !item.isSlotCompleted(request.slotKey))) {
        final operation = {
          'operation_id': digest,
          'schedule_date': request.scheduleDate,
          'slot_key': request.slotKey,
          'medication_ids': ids.cast<int>()..sort(),
          // 전송 대기 목록의 제목으로만 쓰며 서버로 보내기 전에 뺀다(앱·위젯 기록과 같다).
          'medication_names': [for (final item in schedules) item.medicationName],
          'completed': true,
          'link_id': request.linkId,
          'regimen_revisions': {
            for (final item in schedules)
              item.medicationID: item.regimenRevision,
          },
        };
        await tx.insert('operations', {
          'id': digest,
          'owner': token,
          'payload': await _encrypt(operation, token),
        });
      }
      consumed.add(request.eventId);
      await tx.insert('metadata', {
        'name': markerKey,
        'value': await _encrypt({
          'date': request.scheduleDate,
          'events': consumed.toList(),
        }, token),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }
}
