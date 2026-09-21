// 파일명: dose_outbox_store.dart
// 역할: 앱과 Android 백그라운드 작업이 공유하는 암호화 복약 전송 대기 저장소.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../entities/dose_widget_state.dart';

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
  static Future<DoseOutboxStore> open() => _opening ??= _open();

  static Future<DoseOutboxStore> _open() async {
    const secure = FlutterSecureStorage();
    final path = '${await getDatabasesPath()}/dose_outbox_v1.db';
    var encodedKey = await secure.read(key: 'medbuddy_dose_outbox_key_v1');
    if (encodedKey == null) {
      if (await databaseExists(path)) {
        throw StateError('Dose storage key unavailable.');
      }
      final key = await AesGcm.with256bits().newSecretKey();
      encodedKey = base64Encode(await key.extractBytes());
      await secure.write(key: 'medbuddy_dose_outbox_key_v1', value: encodedKey);
    }
    final db = await openDatabase(path, version: 1, onCreate: createSchema);
    return DoseOutboxStore(db, SecretKey(base64Decode(encodedKey)));
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute(
      'CREATE TABLE operations (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL, owner TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'pending\', lease TEXT, lease_until INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

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

  Future<void> activate(String? owner) async {
    await db.insert('metadata', {
      'name': 'active',
      'value': owner == null ? '' : await ownerKey(owner),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
  // 함수역할: 가장 이른 요청을 선점한다. 취소 요청이 미확인 복용 요청을 앞지르지 않는다.
  // 매개변수: owner - 계정, lease - 작업 소유자, now - 현재 밀리초 시각.
  // 반환값: 처리할 요청 또는 null. 선점 만료 후에도 같은 요청 ID로 재시도한다.
  Future<Map<String, dynamic>?> claim(
    String owner,
    String lease,
    int now,
  ) async {
    final token = await ownerKey(owner);
    final row = await db.transaction<Map<String, Object?>?>((tx) async {
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      if (active.isEmpty || active.single['value'] != token) return null;
      final rows = await tx.query(
        'operations',
        where: 'owner = ?',
        whereArgs: [token],
        orderBy: 'seq',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final first = rows.single;
      if (first['state'] == 'blocked' || (first['lease_until'] as int) > now) {
        return null;
      }
      await tx.update(
        'operations',
        {'lease': lease, 'lease_until': now + 120000},
        where: 'id = ?',
        whereArgs: [first['id']],
      );
      return first;
    });
    return row == null ? null : _decrypt(row['payload'] as String, token);
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
    });
  }
}
