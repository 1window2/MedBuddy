// 파일명: dose_outbox_store.dart
// 역할: 앱과 Android 백그라운드 작업이 공유하는 암호화 복약 전송 대기 저장소.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../entities/dose_widget_state.dart';
import '../entities/user_setting_entity.dart';
import 'dose_store_open_gate.dart';
import 'slot_check_notification_context.dart';

part 'dose_widget_store.dart';
part 'dose_history_pending_store.dart';
part 'dose_offline_schedule_store.dart';
part 'slot_check_notification_store.dart';

// 클래스명: DoseOutboxStore
// 역할: 계정별 기록과 캐시를 암호화하고 저장·전송·응답 반영 순서를 보장한다.
// 주요 책임:
// - 계정별 암호화·선점·응답 확인을 처리하고 이전 세션 활성화와 오래된 날짜의 캐시 덮어쓰기를 막는다.
// 속성: db (Database) - SQLite 연결; key (SecretKey) - 기기 보안 저장소의 AES-GCM 키;
// - _cipher (AesGcm): 계정 키를 추가 인증 데이터로 사용하는 암호화 방식.
class DoseOutboxStore {
  final Database db;
  final SecretKey key;
  final AesGcm _cipher = AesGcm.with256bits();

  // 함수이름: DoseOutboxStore
  // 함수역할: 이미 열린 DB와 암호화 키를 결합한다. 스키마 생성과 키 복구는 수행하지 않는다.
  // 매개변수: db (Database) - 준비된 SQLite 연결; key (SecretKey) - 저장 데이터에 사용할 AES 키.
  // 반환값: 주입된 자원을 사용하는 DoseOutboxStore.
  DoseOutboxStore(this.db, this.key);

  static Future<DoseOutboxStore>? _opening;
  // Function Name: open
  // Description: Shares one store-opening attempt per isolate and permits a fresh attempt after failure.
  // Parameters: None.
  // Returns: The shared opened store; original opening errors retain their stack trace.
  static Future<DoseOutboxStore> open() => _opening ??= _open().catchError((
    Object error,
    StackTrace stackTrace,
  ) {
    // A transient storage failure must not block dose records until restart.
    _opening = null;
    Error.throwWithStackTrace(error, stackTrace);
  });

  static const _keyName = 'medbuddy_dose_outbox_key_v1';

  // Function Name: _open
  // Description: Opens the version-1 dose database using the device secure-storage key and schema initializer.
  // Parameters: None.
  // Returns: An encrypted store after missing-key recovery; platform, storage, and decoding errors propagate.
  static Future<DoseOutboxStore> _open() async {
    const secure = FlutterSecureStorage();
    final path = '${await getDatabasesPath()}/dose_outbox_v1.db';
    return openWith(
      readKey: () => secure.read(key: _keyName),
      writeKey: (value) => secure.write(key: _keyName, value: value),
      openDatabase: () =>
          openDatabase(path, version: 1, onCreate: createSchema),
    );
  }

  // Function Name: openWith
  // Description: Opens through the cross-engine gate and recovers only a genuinely missing key, never a key-read error.
  // Parameters: readKey/writeKey - asynchronous secure-storage access; openDatabase - database opener;
  // - openGate (DoseStoreOpenGate): Serializes database opening across Flutter engines in this process.
  // Returns: Store using the recovered/base64-decoded key. Key, database, and decoding failures propagate.
  @visibleForTesting
  static Future<DoseOutboxStore> openWith({
    required Future<String?> Function() readKey,
    required Future<void> Function(String value) writeKey,
    required Future<Database> Function() openDatabase,
    DoseStoreOpenGate openGate = const DoseStoreOpenGate(),
  }) async {
    var encodedKey = await readKey();
    final db = await openGate.run(openDatabase);
    encodedKey ??= await _recoverMissingKey(db, readKey, writeKey);
    return DoseOutboxStore(db, SecretKey(base64Decode(encodedKey)));
  }

  // 함수이름: _recoverMissingKey
  // 함수역할: 키가 사라진 DB를 매번 실패시키지 않고, 읽을 수 없게 된 기록의 건수만 남긴 뒤
  //   새 키로 다시 시작한다. 처음 설치한 빈 DB에서는 키만 만든다.
  // 매개변수: db - 열린 DB, readKey/writeKey - 기기 보안 저장소 접근.
  // 반환값: 사용할 키. 앱과 백그라운드 작업이 동시에 열어도 같은 키를 받는다.
  static Future<String> _recoverMissingKey(
    Database db,
    Future<String?> Function() readKey,
    Future<void> Function(String value) writeKey,
  ) async {
    // 키가 없으면 기존 행은 어느 실행 환경에서도 복호화할 수 없다. 그 사이 다른 실행 환경이
    // 새 키를 만들었다면 그 키로 쓴 행이므로 지우지 않는다.
    await db.transaction((tx) async {
      if (await readKey() != null) return;
      final lost = <String, int>{};
      for (final row in await tx.query(
        'metadata',
        where: 'name LIKE ?',
        whereArgs: ['$_lostPrefix%'],
      )) {
        lost[(row['name'] as String).substring(_lostPrefix.length)] =
            int.tryParse(row['value'] as String) ?? 0;
      }
      for (final row in await tx.rawQuery(
        'SELECT owner, COUNT(*) AS count FROM operations GROUP BY owner',
      )) {
        final owner = row['owner'] as String;
        lost[owner] = (lost[owner] ?? 0) + (row['count'] as int);
      }
      for (final row in await tx.query(
        'metadata',
        where: 'name LIKE ?',
        whereArgs: ['history-pending-count:%'],
      )) {
        final owner = (row['name'] as String).substring(
          'history-pending-count:'.length,
        );
        lost[owner] =
            (lost[owner] ?? 0) + (int.tryParse(row['value'] as String) ?? 0);
      }
      await tx.delete('operations');
      await tx.delete('metadata');
      for (final entry in lost.entries) {
        if (entry.value <= 0) continue;
        await tx.insert('metadata', {
          'name': '$_lostPrefix${entry.key}',
          'value': '${entry.value}',
        });
      }
    });
    // 새 키는 한 실행 환경만 만든다. 나머지는 잠금을 기다린 뒤 저장된 키를 읽어 함께 쓴다.
    // 키 저장이 실패하거나 도중에 종료되어도 DB에는 건수만 남아 다음 열기에서 이어진다.
    return db.transaction((tx) async {
      final existing = await readKey();
      if (existing != null) return existing;
      final key = await AesGcm.with256bits().newSecretKey();
      final encoded = base64Encode(await key.extractBytes());
      await writeKey(encoded);
      return encoded;
    });
  }

  // 함수이름: createSchema
  // 함수역할: 전송 순서·선점 상태를 담는 operations와 계정 상태용 metadata 테이블을 만든다.
  // 매개변수: db (Database) - 신규 DB; version (int) - SQLite 생성 콜백 버전이며 현재 구현에서는 사용하지 않는다.
  // 반환값: 생성 완료 Future. SQL 오류는 전파한다.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute(
      'CREATE TABLE operations (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL, owner TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'pending\', lease TEXT, lease_until INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  // 키 분실로 읽을 수 없게 된 전송 대기 건수를 계정 해시별로 평문 보관한다.
  static const _lostPrefix = 'lost:';

  // 함수이름: ownerKey
  // 함수역할: 원본 계정 식별자를 저장소에서 사용하는 SHA-256 해시 키로 바꾼다.
  // 매개변수: owner (String) - 계정 식별자 원문
  // 반환값: URL-safe Base64 해시 Future. 입력 문자열을 정규화하지 않는다.
  Future<String> ownerKey(String owner) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(owner))).bytes);

  // 활성 계정 키를 읽는다. 로그아웃 상태는 빈 문자열, 기록이 없으면 null이다.
  // Function Name: _activeToken
  // Description: Reads the active-account marker using the caller's database or transaction.
  // Parameters: executor (DatabaseExecutor) - connection participating in the current read/write sequence.
  // Returns: Hashed account key, empty string after sign-out, or null before the first activation.
  Future<String?> _activeToken(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['active'],
    );
    return rows.firstOrNull?['value'] as String?;
  }

  // 계정의 캐시 버전을 읽으며 없거나 숫자가 아닌 값은 0으로 본다.
  // Function Name: _revision
  // Description: Reads the account's concurrency version, tolerating absent or malformed metadata.
  // Parameters: executor (DatabaseExecutor) - database/transaction; token (String) - already-hashed owner key.
  // Returns: Stored integer, or zero when unavailable; database errors propagate.
  Future<int> _revision(DatabaseExecutor executor, String token) async {
    final rows = await executor.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['revision:$token'],
    );
    return int.tryParse('${rows.firstOrNull?['value']}') ?? 0;
  }

  // 읽은 버전의 다음 값을 저장해 그 전에 시작한 조회의 늦은 저장을 거부하게 한다.
  // Function Name: _bumpRevision
  // Description: Persists the successor of a revision read within the same write sequence.
  // Parameters: executor (DatabaseExecutor) - write transaction; token (String) - hashed owner; revision (int) - current value.
  // Returns: Completion after replacement; it does not independently re-read or lock the revision.
  Future<void> _bumpRevision(
    DatabaseExecutor executor,
    String token,
    int revision,
  ) async {
    await executor.insert('metadata', {
      'name': 'revision:$token',
      'value': '${revision + 1}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 함수이름: _encrypt
  // 함수역할: JSON 본문을 계정 키에 결합된 AES-GCM 암호문으로 만든다.
  // 매개변수: value (Map<String, dynamic>) - JSON 직렬화 가능한 본문; owner (String) - 추가 인증 데이터로 쓸 계정 키.
  // 반환값: nonce·암호문·인증 태그를 합친 Base64 문자열. 직렬화·암호화 오류는 전파한다.
  Future<String> _encrypt(Map<String, dynamic> value, String owner) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: key,
      aad: utf8.encode(owner),
    );
    return base64Encode(box.concatenation());
  }

  // 함수이름: _decrypt
  // 함수역할: 계정 키로 인증 태그를 검증하며 저장 암호문을 JSON 맵으로 복원한다.
  // 매개변수: value (String) - Base64 암호문; owner (String) - 암호화 때 사용한 계정 키.
  // 반환값: 복원한 본문 Future. 키·계정·형식 불일치는 예외로 전달한다.
  Future<Map<String, dynamic>> _decrypt(String value, String owner) async {
    final bytes = await _cipher.decrypt(
      SecretBox.fromConcatenation(
        base64Decode(value),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: key,
      aad: utf8.encode(owner),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  // 함수이름: activate
  // 함수역할: 계정 전환과 이전 위젯 버튼 무효화를 함께 저장한다. 복약 전송 대기는 보존한다.
  // 매개변수: owner (String?) - 활성 계정, null이면 로그아웃;
  // - isCurrent (bool Function()?): DB 작업 시작 시 세션 유효성을 재검사할 함수.
  // 반환값: 변경 완료 Future. isCurrent가 false이면 기존 계정·위젯을 그대로 두며 저장소 오류는 전파한다.
  Future<void> activate(String? owner, {bool Function()? isCurrent}) async {
    final next = owner == null ? '' : await ownerKey(owner);
    await db.transaction((tx) async {
      // 키 계산이나 DB 대기 중 종료된 세션은 새 계정을 덮어쓰지 않는다.
      if (isCurrent != null && !isCurrent()) return;
      final previous = await _activeToken(tx) ?? '';
      if (previous != next) {
        // 설정은 유지하되 재로그인으로 과거 버튼·환자 탐색·지연 응답이 살아나지 않게 한다.
        for (final token in {
          previous,
          next,
        }.where((value) => value.isNotEmpty)) {
          final widgetRows = await tx.query(
            'metadata',
            where: 'name = ?',
            whereArgs: ['widget:$token'],
          );
          if (widgetRows.isEmpty) continue;
          final widget = await _decrypt(
            widgetRows.single['value'] as String,
            token,
          );
          await tx.update(
            'metadata',
            {
              'value': await _encrypt({
                'owner': widget['owner'],
                'config': widget['config'],
                'patient_revision': newWidgetActionToken(),
              }, token),
            },
            where: 'name = ?',
            whereArgs: ['widget:$token'],
          );
        }
      }
      await tx.insert('metadata', {
        'name': 'active',
        'value': next,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // Function Name: isActive
  // Description: Compares the persisted active marker with the supplied account's hash.
  // Parameters: owner (String) - account whose queued work may run.
  // Returns: True only for the active account; storage errors propagate.
  Future<bool> isActive(String owner) async =>
      await _activeToken(db) == await ownerKey(owner);

  // Function Name: enqueue
  // Description: Encrypts a dose request and inserts it only while its account is active in the write transaction.
  // Parameters: owner (String) - account; operation (Map<String, dynamic>) - validated payload with a unique operation_id.
  // Returns: Durable insertion completion; account changes raise StateError and duplicate IDs/storage failures propagate.
  Future<void> enqueue(String owner, Map<String, dynamic> operation) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(operation, token);
    await db.transaction((tx) async {
      if (await _activeToken(tx) != token) {
        throw StateError('Account changed.');
      }
      await tx.insert('operations', {
        'id': operation['operation_id'],
        'owner': token,
        'payload': encrypted,
      });
    });
  }

  // 함수이름: pending
  // 함수역할: 해당 계정의 모든 대기·보류 요청을 등록 순서대로 복호화한다.
  // 매개변수: owner (String) - 조회할 계정
  // 반환값: DB의 state가 포함된 요청 목록. 활성 계정 여부와 무관하게 조회하며 읽기·복호화 오류는 전파한다.
  Future<List<Map<String, dynamic>>> pending(String owner) async {
    final token = await ownerKey(owner);
    final rows = await db.query(
      'operations',
      where: 'owner = ?',
      whereArgs: [token],
      orderBy: 'seq',
    );
    return [
      for (final row in rows)
        {
          ...await _decrypt(row['payload'] as String, token),
          'state': row['state'],
        },
    ];
  }

  // Function Name: claim
  // Description: Leases the oldest eligible operation for two minutes while preserving per-dose order and account-wide upload serialization.
  // Parameters: owner (String) - active account; lease (String) - worker token; now (int) - current epoch milliseconds.
  // Returns: Decrypted request, or null for inactive ownership/no eligible work; expired claims retain their operation ID.
  Future<Map<String, dynamic>?> claim(
    String owner,
    String lease,
    int now,
  ) async {
    final token = await ownerKey(owner);
    return db.transaction<Map<String, dynamic>?>((tx) async {
      if (await _activeToken(tx) != token) return null;
      final ready = await _readyOperations(tx, token, now: now);
      if (ready.isEmpty) return null;
      final first = ready.first;
      await tx.update(
        'operations',
        {'lease': lease, 'lease_until': now + 120000},
        where: 'id = ?',
        whereArgs: [first.row['id']],
      );
      return first.payload;
    });
  }

  // Function Name: hasUploadableOperation
  // Description: Checks for work that can upload now or after an existing lease, excluding blocked dose chains.
  // Parameters: owner (String) - account to inspect; active ownership is not checked here.
  // Returns: True when any ordered request is eligible; database/decryption errors propagate.
  Future<bool> hasUploadableOperation(String owner) async {
    final token = await ownerKey(owner);
    return (await _readyOperations(db, token)).isNotEmpty;
  }

  // 함수이름: _readyOperations
  // 함수역할: 오래된 순으로 요청을 복호화해, 보류되지 않았고 같은 날짜·시간대·약의 앞선 요청이 남아 있지 않은 요청만 고른다.
  // 매개변수: executor - DB 또는 트랜잭션, token - 계정 키, now - 주어지면 다른 작업자가 선점 중인 요청도 제외할 현재 밀리초 시각.
  // 반환값: 전송 가능한 요청의 원본 행과 복호화한 본문 목록(오래된 순).
  Future<List<({Map<String, Object?> row, Map<String, dynamic> payload})>>
  _readyOperations(DatabaseExecutor executor, String token, {int? now}) async {
    final rows = await executor.query(
      'operations',
      where: 'owner = ?',
      whereArgs: [token],
      orderBy: 'seq',
    );
    // ACK는 전체 일정이므로 같은 계정의 전송은 선점이 끝난 뒤 시작해 응답 역전을 막는다.
    // now가 없는 재시도 확인은 선점 중인 기록도 계속 전송 대기로 센다.
    if (now != null && rows.any((row) => (row['lease_until'] as int) > now)) {
      return [];
    }
    final earlier = <Map<String, dynamic>>[];
    final ready =
        <({Map<String, Object?> row, Map<String, dynamic> payload})>[];
    for (final row in rows) {
      final payload = await _decrypt(row['payload'] as String, token);
      final waiting = earlier.any(
        /* 함수이름: any 콜백
         * 함수역할: 앞선 요청이 같은 날짜·시간대·약을 다루는지 확인한다.
         * 매개변수: prior - 앞선 요청 본문.
         * 반환값: 순서를 지켜야 하면 true.
         */
        (prior) => sharesDoseOrder(prior, payload),
      );
      earlier.add(payload);
      if (waiting || row['state'] == 'blocked') continue;
      ready.add((row: row, payload: payload));
    }
    return ready;
  }

  // Function Name: sharesDoseOrder
  // Description: Detects dose changes whose ordering matters because they affect a common medication on one date and slot.
  // Parameters: first, second (Map<String, dynamic>) - queued dose payloads; missing medication lists are empty.
  // Returns: True only when date, slot, and at least one medication ID overlap.
  @visibleForTesting
  static bool sharesDoseOrder(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    if (first['schedule_date'] != second['schedule_date'] ||
        first['slot_key'] != second['slot_key']) {
      return false;
    }
    final firstIds = {...(first['medication_ids'] as List? ?? const [])};
    return (second['medication_ids'] as List? ?? const []).any(
      firstIds.contains,
    );
  }

  // Function Name: replaceClaimed
  // Description: Replaces a leased payload in place and releases its lease, allowing a chat-free retry without changing queue order.
  // Parameters: owner/id/lease (String) - account, original operation ID, and claim token;
  // - operation (Map<String, dynamic>): Replacement body with a new operation_id.
  // Returns: True if that claim still exists and was replaced; false for a lost claim. Encryption/SQL errors propagate.
  Future<bool> replaceClaimed(
    String owner,
    String id,
    String lease,
    Map<String, dynamic> operation,
  ) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(operation, token);
    final changed = await db.update(
      'operations',
      {
        'id': operation['operation_id'],
        'payload': encrypted,
        'state': 'pending',
        'lease': null,
        'lease_until': 0,
      },
      where: 'owner = ? AND id = ? AND lease = ?',
      whereArgs: [token, id, lease],
    );
    return changed > 0;
  }

  // 함수이름: finish
  // 함수역할: 소유한 선점만 해제하여 재시도·보류 상태로 바꾸거나 처리된 요청을 삭제한다.
  // 매개변수: owner/id/lease (String) - 계정·요청·선점 키; blocked/retry (bool) - 보류 또는 재대기 여부.
  // 반환값: 변경 완료 Future. blocked가 retry보다 우선하며 두 값이 false이면 삭제한다. 다른 선점은 변경하지 않는다.
  Future<void> finish(
    String owner,
    String id,
    String lease, {
    bool blocked = false,
    bool retry = false,
  }) async {
    final whereArgs = [await ownerKey(owner), id, lease];
    if (blocked || retry) {
      await db.update(
        'operations',
        {
          'state': blocked ? 'blocked' : 'pending',
          'lease': null,
          'lease_until': 0,
        },
        where: 'owner = ? AND id = ? AND lease = ?',
        whereArgs: whereArgs,
      );
    } else {
      await db.delete(
        'operations',
        where: 'owner = ? AND id = ? AND lease = ?',
        whereArgs: whereArgs,
      );
    }
  }

  // 함수이름: retryBlocked
  // 함수역할: 사용자의 재시도 요청에 따라 해당 계정의 보류 기록을 모두 대기로 돌린다.
  // 매개변수: owner (String) - 대상 계정
  // 반환값: 상태 갱신 완료 Future. 실제 전송은 시작하지 않으며 DB 오류는 전파한다.
  Future<void> retryBlocked(String owner) async {
    await db.update(
      'operations',
      {'state': 'pending'},
      where: 'owner = ? AND state = ?',
      whereArgs: [await ownerKey(owner), 'blocked'],
    );
  }

  // 함수이름: discardRejected
  // 함수역할: 서버가 명시적으로 거부한 요청만 제거한다. 응답 유실은 재전송으로 확인한다.
  // 매개변수: owner - 계정, id - 요청 ID. 반환값: 삭제 완료 Future.
  Future<void> discardRejected(String owner, String id) async {
    await db.delete(
      'operations',
      where: 'owner = ? AND id = ? AND state = ?',
      whereArgs: [await ownerKey(owner), id, 'blocked'],
    );
  }

  // Function Name: lostOperationCount
  // Description: Reads this account's unacknowledged record-loss count after encryption-key recovery.
  // Parameters: owner (String) - account whose loss notice is displayed.
  // Returns: Stored count, or zero for missing/non-numeric metadata; database errors propagate.
  Future<int> lostOperationCount(String owner) async {
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['$_lostPrefix${await ownerKey(owner)}'],
    );
    return rows.isEmpty ? 0 : int.tryParse(rows.single['value'] as String) ?? 0;
  }

  // Function Name: clearLostOperations
  // Description: Removes only the account's acknowledged loss-count metadata, not its pending operations.
  // Parameters: owner (String) - account acknowledging the notice.
  // Returns: Deletion completion; database errors propagate.
  Future<void> clearLostOperations(String owner) async {
    await db.delete(
      'metadata',
      where: 'name = ?',
      whereArgs: ['$_lostPrefix${await ownerKey(owner)}'],
    );
  }

  // 함수이름: cacheRevision
  // 함수역할: 해당 계정 캐시의 동시성 검사용 버전을 읽는다.
  // 매개변수: owner (String) - 대상 계정
  // 반환값: 저장된 정수 버전, 없으면 0. 숫자가 아닌 저장값이나 DB 오류는 예외로 전달한다.
  Future<int> cacheRevision(String owner) async {
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['revision:${await ownerKey(owner)}'],
    );
    return rows.isEmpty ? 0 : int.parse(rows.single['value'] as String);
  }

  // Function Name: saveCache
  // Description: Replaces an encrypted snapshot and increments its revision atomically, optionally rejecting intervening writes.
  // Parameters: owner (String) - account; cache (Map<String, dynamic>) - snapshot;
  // - expectedRevision (int?): Version captured before retrieval; null skips the comparison.
  // Returns: True when stored, false for a revision mismatch; this low-level write does not require active ownership.
  Future<bool> saveCache(
    String owner,
    Map<String, dynamic> cache, {
    int? expectedRevision,
  }) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(cache, token);
    return db.transaction((tx) async {
      final rows = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      final revision = rows.isEmpty
          ? 0
          : int.parse(rows.single['value'] as String);
      if (expectedRevision != null && expectedRevision != revision) {
        return false;
      }
      await tx.insert('metadata', {
        'name': 'cache:$token',
        'value': encrypted,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _bumpRevision(tx, token, revision);
      return true;
    });
  }

  // 함수이름: acknowledge
  // 함수역할: 선점 소유자를 확인해 요청 제거·버전 증가를 함께 커밋하고 서버 캐시는 같은 날짜 또는 더 새 날짜일 때만 저장한다.
  // 매개변수: owner/id/lease (String) - 계정·요청·선점 키; cache (Map<String, dynamic>) - YYYY-MM-DD date가 있는 서버 일정.
  // 반환값: 반영 완료 Future. 다른 선점은 변경하지 않으며 늦은 이전 날짜 응답도 요청 확인은 마치되 최신 캐시는 보존한다.
  Future<void> acknowledge(
    String owner,
    String id,
    String lease,
    Map<String, dynamic> cache,
  ) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(cache, token);
    await db.transaction((tx) async {
      final rows = await tx.query(
        'operations',
        where: 'owner = ? AND id = ? AND lease = ?',
        whereArgs: [token, id, lease],
      );
      if (rows.isEmpty) return;
      final revisions = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      final revision = revisions.isEmpty
          ? 0
          : int.parse(revisions.single['value'] as String);
      final currentRows = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['cache:$token'],
      );
      final current = currentRows.isEmpty
          ? null
          : await _decrypt(currentRows.single['value'] as String, token);
      // 자정을 넘겨 도착한 영수증은 확인만 마치고 더 최신 날짜의 캐시를 보존한다.
      final currentDay = current?['date'] as String? ?? '';
      final receiptDay = cache['date'] as String? ?? '';
      if (currentDay.compareTo(receiptDay) <= 0) {
        await tx.insert('metadata', {
          'name': 'cache:$token',
          'value': encrypted,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _bumpRevision(tx, token, revision);
      await tx.delete(
        'operations',
        where: 'owner = ? AND id = ? AND lease = ?',
        whereArgs: [token, id, lease],
      );
    });
  }

  // 함수이름: readCache
  // 함수역할: 계정별 일정 스냅샷을 복호화한다. 날짜 유효성은 호출자가 판단한다.
  // 매개변수: owner (String) - 조회할 계정
  // 반환값: 저장된 JSON 맵, 없으면 null. 읽기·인증 태그·JSON 오류는 전파한다.
  Future<Map<String, dynamic>?> readCache(String owner) async {
    final token = await ownerKey(owner);
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['cache:$token'],
    );
    return rows.isEmpty
        ? null
        : _decrypt(rows.single['value'] as String, token);
  }

  // 함수이름: clearAccount
  // 함수역할: 계정의 전송 대기·일정·위젯·유실·기록 대기·시간대 알림 상태를 하나의 트랜잭션에서 삭제한다.
  // 매개변수: owner (String) - 삭제할 계정
  // 반환값: 삭제 완료 Future. 활성 계정 표식과 기기 암호화 키는 바꾸지 않으며 DB 오류는 전파한다.
  Future<void> clearAccount(String owner) async {
    final token = await ownerKey(owner);
    await db.transaction((tx) async {
      await tx.delete('operations', where: 'owner = ?', whereArgs: [token]);
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['slot-check:$token'],
      );
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['cache:$token'],
      );
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['revision:$token'],
      );
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['widget:$token'],
      );
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['$_lostPrefix$token'],
      );
      await tx.delete(
        'metadata',
        where: 'name IN (?, ?)',
        whereArgs: ['history-pending:$token', 'history-pending-count:$token'],
      );
      await tx.delete(
        'metadata',
        where: 'name = ?',
        whereArgs: ['offline_schedule:$token'],
      );
    });
  }
}
