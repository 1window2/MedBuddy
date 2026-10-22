part of 'dose_outbox_store.dart';

// 계정별 기간 일정은 기존 기기 키로 암호화하고, 일일 체크 캐시와 별도로 보관한다.
extension DoseOfflineScheduleStore on DoseOutboxStore {
  // 오늘의 서버 응답을 반영하면서 이전 기간 일정을 폐기한다. 갱신 실패 시 과거 처방을 다시 살리지 않는다.
  Future<bool> saveAuthoritativeDoseCache(
    String owner,
    Map<String, dynamic> cache, {
    int? expectedRevision,
  }) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(cache, token);
    return db.transaction((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      if (active.firstOrNull?['value'] != token) return false;
      final rows = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      final revision = int.tryParse('${rows.firstOrNull?['value']}') ?? 0;
      if (expectedRevision != null && revision != expectedRevision) {
        return false;
      }
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['offline_schedule:$token'],
      );
      await tx.insert('metadata', {
        'name': 'cache:$token',
        'value': encrypted,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert('metadata', {
        'name': 'revision:$token',
        'value': '${revision + 1}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<void> invalidateDoseSchedules(String owner) async {
    final token = await ownerKey(owner);
    await db.transaction((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      if (active.firstOrNull?['value'] != token) return;
      final rows = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      final revision = int.tryParse('${rows.firstOrNull?['value']}') ?? 0;
      await tx.delete(
        'metadata',
        where: 'name IN (?, ?)',
        whereArgs: ['cache:$token', 'offline_schedule:$token'],
      );
      await tx.insert('metadata', {
        'name': 'revision:$token',
        'value': '${revision + 1}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<bool> restoreDoseSession(
    String owner, {
    required bool Function() isCurrent,
  }) async {
    final token = await ownerKey(owner);
    return db.transaction((tx) async {
      final rows = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      final active = rows.firstOrNull?['value'] as String? ?? '';
      if (!isCurrent() || (active.isNotEmpty && active != token)) return false;
      await tx.insert('metadata', {
        'name': 'active',
        'value': token,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return isCurrent();
    });
  }

  Future<bool> saveOfflineScheduleWindow(
    String owner,
    Map<String, dynamic> window, {
    required int expectedRevision,
  }) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(window, token);
    return db.transaction((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      final revision = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      if (active.firstOrNull?['value'] != token ||
          (int.tryParse('${revision.firstOrNull?['value']}') ?? 0) !=
              expectedRevision) {
        return false;
      }
      await tx.insert('metadata', {
        'name': 'offline_schedule:$token',
        'value': encrypted,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<Map<String, dynamic>?> readOfflineScheduleWindow(String owner) async {
    if (!await isActive(owner)) return null;
    final token = await ownerKey(owner);
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['offline_schedule:$token'],
    );
    return rows.isEmpty
        ? null
        : _decrypt(rows.single['value'] as String, token);
  }

  // 날짜 승격과 캐시 버전 변경을 묶어 늦게 끝난 전날 조회가 오늘 캐시를 덮지 못하게 한다.
  Future<void> prepareOfflineScheduleDay({
    String? owner,
    required String day,
    required List<Map<String, dynamic>>? Function(Map<String, dynamic>) project,
  }) async {
    final expected = owner == null ? null : await ownerKey(owner);
    await db.transaction((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      final token = active.firstOrNull?['value'] as String? ?? '';
      if (token.isEmpty || (expected != null && token != expected)) return;
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

      final cache = await read('cache:$token');
      if (cache?['date'] == day) return;
      // 기기 시각이 뒤로 이동한 경우에도 미래 캐시를 과거 일정으로 재사용하지 않는다.
      if ((cache?['date'] as String? ?? '').compareTo(day) > 0) return;
      final window = await read('offline_schedule:$token');
      if (window == null) return;
      final schedules = project(window);
      if (schedules == null) return;
      final revisions = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      final revision = int.tryParse('${revisions.firstOrNull?['value']}') ?? 0;
      await tx.insert('metadata', {
        'name': 'cache:$token',
        'value': await _encrypt({
          'date': day,
          'schedules': schedules,
          'offline': true,
        }, token),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert('metadata', {
        'name': 'revision:$token',
        'value': '${revision + 1}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
