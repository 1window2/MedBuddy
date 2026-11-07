// 파일명: slot_check_notification_store.dart
// 역할: 알림의 복용 확인 버튼 소비와 전송 대기 기록을 원자적으로 저장한다.
part of 'dose_outbox_store.dart';

// 버튼 소비와 복약 전송 대기를 같은 트랜잭션에 넣어 엔진 간 동시 클릭도 한 번만 반영한다.
// 클래스명: SlotCheckNotificationStore
// 역할: 확인 요청 알림의 복용 완료 동작을 계정별 전송 대기 저장소에 연결한다.
// 주요 책임: 활성 계정·오늘 일정·중복 이벤트·보류 상태를 검사하고 버튼 소비와 복용 기록을 함께 저장한다.
// 속성: 추가 필드 없음. DoseOutboxStore의 DB·암호화 키·계정 검증 기능을 사용한다.
extension SlotCheckNotificationStore on DoseOutboxStore {
  // Function Name: recordSlotCheck
  // Description: Atomically consume a current-day check event and enqueue completion for its valid projected slot; reject stale ownership, invalid schedules or overlapping blocked operations.
  // Parameters: request (SlotCheckNotificationContext): owner, event, link, slot and date; clock (DateTime Function()): rechecked day boundary.
  // Returns: Future<bool>: true for a newly recorded or already consumed event; false for failed guards. Storage/crypto errors propagate.
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
      // 함수이름: read
      // 함수역할: 복용 확인 트랜잭션에서 현재 계정의 버튼 소비 또는 일정 상태를 복호화한다.
      // 매개변수: name (String) - 조회할 전체 메타데이터 키.
      // 반환값: JSON 맵 또는 저장값이 없으면 null. DB·복호화 오류는 전파한다.
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
