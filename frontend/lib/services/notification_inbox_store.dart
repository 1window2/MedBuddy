// 파일명: notification_inbox_store.dart
// 역할: 기기 내 계정별 알림 기록, 예약 내역과 읽음·삭제 상태를 보관한다.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../entities/notification_inbox_entity.dart';

// 클래스명: NotificationInboxStore
// 역할: 알림마다 독립 키를 사용해 전경·백그라운드의 서로 다른 알림 쓰기가 충돌하지 않게 한다.
class NotificationInboxStore {
  static const activeUserKey = 'notification_inbox_active_user';
  static final changes = StreamController<String>.broadcast();
  static const retention = Duration(days: 90);
  final String userHash;
  final DateTime Function() now;
  final Future<SharedPreferences> Function() loadPreferences;

  // 함수이름: NotificationInboxStore
  // 함수역할: 계정과 저장·시각 경계를 연결한다. 매개변수: userHash, 선택적 시계·저장소. 반환값: 저장소.
  NotificationInboxStore({
    required this.userHash,
    DateTime Function()? now,
    Future<SharedPreferences> Function()? loadPreferences,
  }) : now = now ?? DateTime.now,
       loadPreferences = loadPreferences ?? SharedPreferences.getInstance {
    if (userHash.trim().isEmpty) {
      throw ArgumentError.value(userHash, 'userHash');
    }
  }

  // 함수이름: prefix
  // 함수역할: 계정 범위를 키에 구분한다. 매개변수: 없음. 반환값: 인코딩된 접두사.
  String get prefix =>
      'notification_inbox_v1.${Uri.encodeComponent(userHash)}.';

  // 함수이름: _preferences
  // 함수역할: 다른 isolate가 저장한 최신 값을 읽는다. 매개변수: 없음. 반환값: 갱신된 저장소.
  Future<SharedPreferences> _preferences() async {
    final preferences = await loadPreferences();
    await preferences.reload();
    return preferences;
  }

  // 함수이름: _key
  // 함수역할: 알림의 상태별 키를 만든다. 매개변수: kind, id. 반환값: 저장 키.
  String _key(String kind, String id) =>
      '$prefix$kind.${Uri.encodeComponent(id)}';

  // 함수이름: record
  // 함수역할: 중복 전송은 기존 읽음·삭제 상태를 유지한다. 매개변수: entry. 반환값: 저장 완료.
  Future<void> record(NotificationInboxEntry entry) async {
    if (entry.occurredAt.isBefore(now().subtract(retention))) return;
    final preferences = await _preferences();
    final key = _key('entry', entry.id);
    if (!preferences.containsKey(key)) {
      if (!await preferences.setString(key, jsonEncode(entry.toJson()))) {
        throw StateError('Notification history could not be saved.');
      }
      changes.add(userHash);
    }
  }

  // 함수이름: load
  // 함수역할: 시각이 지난 알림을 최신순으로 읽고 오래된 항목을 정리한다. 매개변수: 없음. 반환값: 최대 500개.
  Future<List<NotificationInboxEntry>> load() async {
    final preferences = await _preferences();
    final current = now();
    final result = <NotificationInboxEntry>[];
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith('${prefix}entry.'),
    )) {
      try {
        final json =
            jsonDecode(preferences.getString(key)!) as Map<String, dynamic>;
        final id = json['id'] as String;
        final entry = NotificationInboxEntry.fromJson(
          json,
          isRead: preferences.getBool(_key('read', id)) ?? false,
        );
        if (entry.occurredAt.isBefore(current.subtract(retention))) {
          await preferences.remove(key);
          await preferences.remove(_key('read', id));
          await preferences.remove(_key('hidden', id));
        } else if (!entry.occurredAt.isAfter(current) &&
            !(preferences.getBool(_key('hidden', id)) ?? false)) {
          result.add(entry);
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    result.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return result.take(500).toList(growable: false);
  }

  // 함수이름: markRead
  // 함수역할: 지정 항목만 읽음으로 남긴다. 매개변수: ids. 반환값: 저장 완료.
  Future<void> markRead(Iterable<String> ids) => _setFlags('read', ids);

  // 함수이름: remove
  // 함수역할: 알림만 숨겨 재수신 시 부활을 막는다. 매개변수: ids. 반환값: 저장 완료.
  Future<void> remove(Iterable<String> ids) => _setFlags('hidden', ids);

  // 함수이름: _setFlags
  // 함수역할: 읽음과 삭제를 독립 키로 저장한다. 매개변수: kind, ids. 반환값: 완료 또는 저장 오류.
  Future<void> _setFlags(String kind, Iterable<String> ids) async {
    final preferences = await _preferences();
    for (final id in ids) {
      if (!await preferences.setBool(_key(kind, id), true)) {
        throw StateError('Notification history could not be updated.');
      }
    }
    changes.add(userHash);
  }

  // 함수이름: cancelFutureReminders
  // 함수역할: 아직 오지 않은 복약 예약만 취소하고 지난 기록은 유지한다. 매개변수: 선택적 slotKey, id. 반환값: 완료.
  Future<void> cancelFutureReminders({String? slotKey, int? id}) async {
    final preferences = await _preferences();
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith('${prefix}entry.'),
    )) {
      try {
        final entry = NotificationInboxEntry.fromJson(
          jsonDecode(preferences.getString(key)!) as Map<String, dynamic>,
        );
        final parts = entry.payload.split(':');
        if (!entry.id.startsWith('reminder:') ||
            !entry.occurredAt.isAfter(now())) {
          continue;
        }
        if (slotKey != null && (parts.length < 2 || parts[1] != slotKey)) {
          continue;
        }
        if (slotKey == null &&
            id != null &&
            (parts.length < 3 || parts[2] != '$id')) {
          continue;
        }
        await preferences.remove(key);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    changes.add(userHash);
  }
}
