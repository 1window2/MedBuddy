// 파일명: dose_outbox_store.dart
// 역할: 앱과 Android 백그라운드 작업이 공유하는 암호화 복약 전송 대기 저장소.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../entities/dose_widget_state.dart';
import '../entities/user_setting_entity.dart';

part 'dose_widget_store.dart';

// 클래스명: DoseOutboxStore
// 역할: 계정별 기록과 캐시를 암호화하고 저장·전송·응답 반영 순서를 보장한다.
// 속성: db - SQLite 연결, key - 기기 보안 저장소의 AES-GCM 키.
class DoseOutboxStore {
  final Database db;
  final SecretKey key;
  final AesGcm _cipher = AesGcm.with256bits();

  DoseOutboxStore(this.db, this.key);

  static Future<DoseOutboxStore>? _opening;
  static Future<DoseOutboxStore> open() => _opening ??= _open().catchError((
    Object error,
    StackTrace stackTrace,
  ) {
    // A transient storage failure must not block dose records until restart.
    _opening = null;
    Error.throwWithStackTrace(error, stackTrace);
  });

  static const _keyName = 'medbuddy_dose_outbox_key_v1';

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

  // 함수이름: openWith
  // 함수역할: 보안 저장소의 키로 DB를 연다. 키가 없으면 새 키로 빈 저장소를 시작한다.
  // 매개변수: readKey/writeKey - 기기 보안 저장소 접근, openDatabase - DB 열기.
  // 반환값: 열린 저장소. 보안 저장소나 DB 오류는 그대로 전달해 다음 요청에서 다시 시도한다.
  // 키를 읽는 중 발생한 오류는 키가 없는 것으로 취급하지 않으므로 기록을 지우지 않는다.
  @visibleForTesting
  static Future<DoseOutboxStore> openWith({
    required Future<String?> Function() readKey,
    required Future<void> Function(String value) writeKey,
    required Future<Database> Function() openDatabase,
  }) async {
    var encodedKey = await readKey();
    final db = await openDatabase();
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

  Future<String> ownerKey(String owner) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(owner))).bytes);

  Future<String> _encrypt(Map<String, dynamic> value, String owner) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: key,
      aad: utf8.encode(owner),
    );
    return base64Encode(box.concatenation());
  }

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
  // 매개변수: owner 활성 계정, null이면 로그아웃. 반환값: 활성 계정 변경 완료 Future.
  Future<void> activate(String? owner) async {
    final next = owner == null ? '' : await ownerKey(owner);
    await db.transaction((tx) async {
      final rows = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      final previous = rows.firstOrNull?['value'] as String? ?? '';
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

  Future<bool> isActive(String owner) async {
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['active'],
    );
    return rows.isNotEmpty && rows.single['value'] == await ownerKey(owner);
  }

  // 함수이름: enqueue
  // 함수역할: 활성 계정을 검증한 뒤 디스크에 저장한다. 실패하면 성공으로 표시하지 않는다.
  // 매개변수: owner - 계정, operation - 복용 요청. 반환값: 저장 완료 Future.
  Future<void> enqueue(String owner, Map<String, dynamic> operation) async {
    final token = await ownerKey(owner);
    final encrypted = await _encrypt(operation, token);
    await db.transaction((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      if (active.isEmpty || active.single['value'] != token) {
        throw StateError('Account changed.');
      }
      await tx.insert('operations', {
        'id': operation['operation_id'],
        'owner': token,
        'payload': encrypted,
      });
    });
  }

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

  // 함수이름: claim
  // 함수역할: 지금 보낼 수 있는 가장 이른 요청을 선점한다. 같은 날짜·시간대·약의 앞선 요청이 남아 있으면
  //   (보류·선점 중 포함) 그 뒤 요청은 기다리게 해 취소 요청이 미확인 복용 요청을 앞지르지 않게 하고,
  //   서로 관계없는 요청은 앞선 요청의 보류와 상관없이 보낸다.
  // 매개변수: owner - 계정, lease - 작업 소유자, now - 현재 밀리초 시각.
  // 반환값: 처리할 요청 또는 null. 선점 만료 후에도 같은 요청 ID로 재시도한다.
  Future<Map<String, dynamic>?> claim(
    String owner,
    String lease,
    int now,
  ) async {
    final token = await ownerKey(owner);
    return db.transaction<Map<String, dynamic>?>((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      if (active.isEmpty || active.single['value'] != token) return null;
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

  // 함수이름: hasUploadableOperation
  // 함수역할: 지금 또는 다른 작업자의 선점이 끝난 뒤 전송을 시도할 기록이 있는지 확인한다. 서버 거부로
  //   보류된 기록과, 같은 날짜·시간대·약에서 보류된 기록 뒤에 기다리는 기록은 사용자가 다시 시도할 때까지 보낼 것이 없다고 본다.
  // 매개변수: owner - 계정. 반환값: 전송할 기록이 있으면 true.
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
    final earlier = <Map<String, dynamic>>[];
    final ready = <({Map<String, Object?> row, Map<String, dynamic> payload})>[];
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
      if (now != null && (row['lease_until'] as int) > now) continue;
      ready.add((row: row, payload: payload));
    }
    return ready;
  }

  // 함수이름: sharesDoseOrder
  // 함수역할: 두 복용 요청의 전송 순서가 결과를 바꾸는지 판단한다. 같은 날짜·시간대에서 약이 하나라도 겹치면 순서를 지킨다.
  // 매개변수: first, second - 복용 요청 본문.
  // 반환값: 앞선 요청이 끝날 때까지 뒤 요청을 기다리게 해야 하면 true.
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

  // 함수이름: replaceClaimed
  // 함수역할: 선점한 요청을 같은 대기열 위치에서 새 본문으로 바꾸고 선점을 풀어 바로 다시 보낼 수 있게 한다.
  //   채팅 한도 초과로 거절된 채팅 복용 요청을 채팅 없는 일반 복용 기록으로 바꿀 때 쓴다.
  // 매개변수: owner - 계정, id - 기존 요청 ID, lease - 작업 소유자, operation - 새 요청 본문(새 operation_id 포함).
  // 반환값: 바꿨으면 true, 다른 작업자가 선점했거나 이미 처리되어 없으면 false.
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

  // 함수이름: lostOperationCount
  // 함수역할: 기기 키가 사라져 전송하지 못하고 버려진 이 계정의 복용 기록 건수를 읽는다.
  // 매개변수: owner - 계정. 반환값: 사용자가 아직 확인하지 않은 유실 건수(없으면 0).
  Future<int> lostOperationCount(String owner) async {
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['$_lostPrefix${await ownerKey(owner)}'],
    );
    return rows.isEmpty ? 0 : int.tryParse(rows.single['value'] as String) ?? 0;
  }

  // 함수이름: clearLostOperations
  // 함수역할: 사용자가 유실 안내를 확인한 뒤 건수 표시를 지운다.
  // 매개변수: owner - 계정. 반환값: 삭제 완료 Future.
  Future<void> clearLostOperations(String owner) async {
    await db.delete(
      'metadata',
      where: 'name = ?',
      whereArgs: ['$_lostPrefix${await ownerKey(owner)}'],
    );
  }

  Future<int> cacheRevision(String owner) async {
    final rows = await db.query(
      'metadata',
      where: 'name = ?',
      whereArgs: ['revision:${await ownerKey(owner)}'],
    );
    return rows.isEmpty ? 0 : int.parse(rows.single['value'] as String);
  }

  // 함수이름: saveCache
  // 함수역할: 조회 시작 시점의 버전과 비교해 늦은 응답이 최신 상태를 덮어쓰지 않게 한다.
  // 매개변수: owner - 계정, cache - 일정, expectedRevision - 조회 당시 버전.
  // 반환값: 저장했으면 true, 더 최신 변경이 있으면 false.
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
      await tx.insert('metadata', {
        'name': 'revision:$token',
        'value': '${revision + 1}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  // 함수이름: acknowledge
  // 함수역할: 선점 소유자를 확인하고 서버 캐시 저장과 전송 대기 제거를 함께 커밋한다.
  // 매개변수: owner - 계정, id - 요청 ID, lease - 작업 소유자, cache - 서버 일정.
  // 반환값: 반영 완료 Future. 다른 작업이 선점한 요청은 변경하지 않는다.
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
      await tx.insert('metadata', {
        'name': 'cache:$token',
        'value': encrypted,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert('metadata', {
        'name': 'revision:$token',
        'value': '${revision + 1}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.delete(
        'operations',
        where: 'owner = ? AND id = ? AND lease = ?',
        whereArgs: [token, id, lease],
      );
    });
  }

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

  Future<void> clearAccount(String owner) async {
    final token = await ownerKey(owner);
    await db.transaction((tx) async {
      await tx.delete('operations', where: 'owner = ?', whereArgs: [token]);
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
    });
  }
}
