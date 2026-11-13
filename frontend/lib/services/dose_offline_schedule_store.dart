// File Name: dose_offline_schedule_store.dart
// Role: Stores revision-guarded offline schedules and reversible regimen-change backups.
part of 'dose_outbox_store.dart';

// 계정별 기간 일정은 기존 기기 키로 암호화하고, 일일 체크 캐시와 별도로 보관한다.
// Class Name: DoseOfflineScheduleStore
// Role: Extends the encrypted outbox with account-scoped schedule-window transactions.
// Responsibilities: Preserve ownership/revision checks while saving, suspending, restoring, or projecting schedules.
// Attributes: No additional fields; uses DoseOutboxStore.db, encryption key, and metadata helpers.
extension DoseOfflineScheduleStore on DoseOutboxStore {
  // 오늘의 서버 응답을 반영하면서 이전 기간 일정을 폐기한다. 갱신 실패 시 과거 처방을 다시 살리지 않는다.
  // Function Name: saveAuthoritativeDoseCache
  // Description: Replaces today's snapshot, drops the old offline window, and increments the cache revision atomically.
  // Parameters: owner (String) - active account; cache (Map<String, dynamic>) - confirmed snapshot;
  // - expectedRevision (int?): Optional version captured before loading.
  // Returns: False for inactive ownership/revision conflict, true when saved; encryption and database errors propagate.
  Future<bool> saveAuthoritativeDoseCache(
    String owner,
    Map<String, dynamic> cache, {
    int? expectedRevision,
  }) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(cache, token);
    return db.transaction((tx) async {
      if (await _activeToken(tx) != token) return false;
      final revision = await _revision(tx, token);
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
      await _bumpRevision(tx, token, revision);
      return true;
    });
  }

  // 처방 변경 요청 직전에 일일·기간 일정을 암호문 그대로 꺼내 둔 뒤 비운다. 요청이 서버에서
  // 적용되지 않았으면 그사이 다른 기록이 없을 때만 되돌려, 오프라인에서 실패한 변경 때문에
  // 오늘 기록할 일정이 사라지지 않게 한다.
  // Function Name: suspendDoseSchedules
  // Description: Removes both schedule snapshots while retaining ciphertext and the post-removal revision for conditional recovery.
  // Parameters: owner (String) - account about to change a regimen.
  // Returns: Backup for an active account, otherwise null; database failures propagate.
  Future<DoseScheduleBackup?> suspendDoseSchedules(String owner) async {
    final token = await ownerKey(owner);
    return db.transaction((tx) async {
      if (await _activeToken(tx) != token) return null;
      // Function Name: raw
      // Description: Reads a snapshot's ciphertext within the suspension transaction without decrypting it.
      // Parameters: name (String) - complete metadata key.
      // Returns: Stored ciphertext, or null if the snapshot is absent.
      Future<String?> raw(String name) async {
        final rows = await tx.query(
          'metadata',
          where: 'name = ?',
          whereArgs: [name],
        );
        return rows.firstOrNull?['value'] as String?;
      }

      final cache = await raw('cache:$token');
      final window = await raw('offline_schedule:$token');
      final revision = await _revision(tx, token);
      await tx.delete(
        'metadata',
        where: 'name IN (?, ?)',
        whereArgs: ['cache:$token', 'offline_schedule:$token'],
      );
      await _bumpRevision(tx, token, revision);
      return DoseScheduleBackup._(token, cache, window, revision + 1);
    });
  }

  // 꺼내 둔 뒤 같은 계정에 다른 기록이 없었을 때만 되돌린다. 되돌리지 못하면 false.
  // Function Name: restoreDoseSchedules
  // Description: Restores non-null backup snapshots only for the same active account and unchanged post-suspension revision.
  // Parameters: owner (String) - account; backup (DoseScheduleBackup) - previously suspended snapshots.
  // Returns: True after restoration and revision increment; false for account/version mismatch. Database errors propagate.
  Future<bool> restoreDoseSchedules(
    String owner,
    DoseScheduleBackup backup,
  ) async {
    final token = await ownerKey(owner);
    if (token != backup._token) return false;
    return db.transaction((tx) async {
      final active = await _activeToken(tx);
      final revision = await _revision(tx, token);
      if (active != token || revision != backup._revision) {
        return false;
      }
      for (final (name, value) in [
        ('cache:$token', backup._cache),
        ('offline_schedule:$token', backup._window),
      ]) {
        if (value == null) continue;
        await tx.insert('metadata', {
          'name': name,
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _bumpRevision(tx, token, revision);
      return true;
    });
  }

  // Function Name: invalidateDoseSchedules
  // Description: Deletes daily and offline schedules together and increments the revision to reject earlier reads.
  // Parameters: owner (String) - account whose regimen is no longer trustworthy.
  // Returns: Completion; inactive accounts are untouched and database errors propagate.
  Future<void> invalidateDoseSchedules(String owner) async {
    final token = await ownerKey(owner);
    await db.transaction((tx) async {
      if (await _activeToken(tx) != token) return;
      final revision = await _revision(tx, token);
      await tx.delete(
        'metadata',
        where: 'name IN (?, ?)',
        whereArgs: ['cache:$token', 'offline_schedule:$token'],
      );
      await _bumpRevision(tx, token, revision);
    });
  }

  // Function Name: restoreDoseSession
  // Description: Restores the active marker after aborted sign-out without replacing another account.
  // Parameters: owner (String) - original account; isCurrent (bool Function()) - live session check before and after the write.
  // Returns: False if the guard fails or another account is active; a final false does not roll back the marker already written.
  Future<bool> restoreDoseSession(
    String owner, {
    required bool Function() isCurrent,
  }) async {
    final token = await ownerKey(owner);
    return db.transaction((tx) async {
      final active = await _activeToken(tx) ?? '';
      if (!isCurrent() || (active.isNotEmpty && active != token)) return false;
      await tx.insert('metadata', {
        'name': 'active',
        'value': token,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return isCurrent();
    });
  }

  // Function Name: saveOfflineScheduleWindow
  // Description: Stores an encrypted course window without advancing the daily-cache revision.
  // Parameters: owner (String) - account; window (Map<String, dynamic>) - bounded course data;
  // - expectedRevision (int): Daily-cache version the window belongs to.
  // Returns: False for inactive ownership or revision mismatch; true when saved. Storage errors propagate.
  Future<bool> saveOfflineScheduleWindow(
    String owner,
    Map<String, dynamic> window, {
    required int expectedRevision,
  }) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(window, token);
    return db.transaction((tx) async {
      final active = await _activeToken(tx);
      final revision = await _revision(tx, token);
      if (active != token || revision != expectedRevision) {
        return false;
      }
      await tx.insert('metadata', {
        'name': 'offline_schedule:$token',
        'value': encrypted,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  // 함수이름: readOfflineScheduleWindow
  // 함수역할: 조회 시작 시 활성 계정인지 확인하고 암호화한 기간 일정을 읽는다.
  // 매개변수: owner (String) - 조회할 계정
  // 반환값: 저장된 기간 데이터, 비활성 계정·저장값 없음이면 null. 날짜 유효성은 검사하지 않으며 읽기 오류는 전파한다.
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
  // Function Name: prepareOfflineScheduleDay
  // Description: Projects an eligible offline window into a new daily cache and increments its revision in one transaction.
  // Parameters: owner (String?) - expected account, or current active account; day (String) - YYYY-MM-DD;
  // - project: Converts window data to daily schedule maps, returning null outside its valid period.
  // Returns: Completion; skips missing/mismatched owners, current/future caches, and unusable windows. Projection/storage errors propagate.
  Future<void> prepareOfflineScheduleDay({
    String? owner,
    required String day,
    required List<Map<String, dynamic>>? Function(Map<String, dynamic>) project,
  }) async {
    final expected = owner == null ? null : await ownerKey(owner);
    await db.transaction((tx) async {
      final token = await _activeToken(tx) ?? '';
      if (token.isEmpty || (expected != null && token != expected)) return;
      // 함수이름: read
      // 함수역할: 날짜 투영 트랜잭션 안에서 활성 계정의 메타데이터를 복호화한다.
      // 매개변수: name (String) - 날짜 캐시 또는 기간 일정의 전체 저장 키
      // 반환값: JSON 맵 또는 저장값이 없으면 null. 복호화 오류는 전파한다.
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
      final revision = await _revision(tx, token);
      await tx.insert('metadata', {
        'name': 'cache:$token',
        'value': await _encrypt({
          'date': day,
          'schedules': schedules,
          'offline': true,
        }, token),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _bumpRevision(tx, token, revision);
    });
  }
}

// 처방 변경 요청 동안 비워 둔 일정의 암호문과, 비운 직후의 캐시 버전.
// Class Name: DoseScheduleBackup
// Role: Holds opaque snapshots for a single revision-guarded regimen rollback.
// Responsibilities: Bind daily/window ciphertext to the account and version from which it was suspended.
// Attributes: _token (String) - hashed account; _cache/_window (String?) - ciphertext; _revision (int) - version after removal.
class DoseScheduleBackup {
  // Function Name: DoseScheduleBackup._
  // Description: Captures suspension results without decrypting or copying stored payloads.
  // Parameters: _token (String) - owner hash; _cache/_window (String?) - prior snapshots; _revision (int) - rollback guard.
  // Returns: Immutable backup used only by this library's restore operation.
  const DoseScheduleBackup._(
    this._token,
    this._cache,
    this._window,
    this._revision,
  );

  final String _token;
  final String? _cache;
  final String? _window;
  final int _revision;
}
