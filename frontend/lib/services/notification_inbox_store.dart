// 파일명: notification_inbox_store.dart
// 역할: 기기 내 계정별 알림 기록, 예약 내역과 읽음·삭제 상태를 보관한다.
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../entities/notification_inbox_entity.dart';

// Class Name: NotificationInboxStore
// Role: Persist notification history and user-specific read/hidden markers.
// Responsibilities: Retain recent entries, avoid duplicate records and notify subscribers of changes.
// Attributes: userHash (String): owner; now/loadPreferences: clock and storage boundaries; retention (Duration): 90 days; activeUserKey/changes: shared session marker and change stream.
class NotificationInboxStore {
  static const activeUserKey = 'notification_inbox_active_user';
  static final changes = StreamController<String>.broadcast();
  static const retention = Duration(days: 90);
  final String userHash;
  final DateTime Function() now;
  final Future<SharedPreferences> Function() loadPreferences;

  // 함수이름: NotificationInboxStore
  // 함수역할: 계정별 알림 저장소에 시계와 설정 저장소 경계를 연결하고 빈 계정은 거절한다.
  // 매개변수: userHash (String): 비어 있지 않은 소유 계정; now (DateTime Function()?): 보존 기간 판단 시계; loadPreferences (Future<SharedPreferences> Function()?): 저장소 로더.
  // 반환값: NotificationInboxStore: 구성된 저장소; 공백뿐인 계정은 ArgumentError.
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

  // Function Name: prefixFor
  // Description: Build a versioned preference namespace from a trimmed, URI-encoded owner.
  // Parameters: userHash (String): owner identity.
  // Returns: String: inbox key prefix.
  static String prefixFor(String userHash) =>
      'notification_inbox_v1.${Uri.encodeComponent(userHash.trim())}.';

  // Function Name: prefix
  // Description: Resolve this store's owner-specific preference namespace.
  // Parameters: None.
  // Returns: String: inbox key prefix.
  String get prefix => prefixFor(userHash);

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

  // Function Name: record
  // Description: Record one notification using the retention and duplicate rules of recordAll.
  // Parameters: entry (NotificationInboxEntry): received or scheduled notification.
  // Returns: Future<void>: persistence completion.
  Future<void> record(NotificationInboxEntry entry) => recordAll([entry]);

  // Function Name: recordAll
  // Description: Insert only recent, previously unseen notifications; emit a change even if a later insert fails after earlier writes succeeded.
  // Parameters: entries (Iterable<NotificationInboxEntry>): candidate history entries.
  // Returns: Future<void>: writes complete; throws when storage rejects an insert.
  Future<void> recordAll(Iterable<NotificationInboxEntry> entries) async {
    final oldest = now().subtract(retention);
    final recent = [
      for (final entry in entries)
        if (!entry.occurredAt.isBefore(oldest)) entry,
    ];
    if (recent.isEmpty) return;
    final preferences = await _preferences();
    var saved = false;
    try {
      for (final entry in recent) {
        final key = _key('entry', entry.id);
        if (preferences.containsKey(key)) continue;
        if (!await preferences.setString(key, jsonEncode(entry.toJson()))) {
          throw StateError('Notification history could not be saved.');
        }
        saved = true;
      }
    } finally {
      // 중간에 실패해도 이미 저장한 항목은 화면에 반영되어야 한다.
      if (saved) changes.add(userHash);
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

  // Function Name: remove
  // Description: Hide selected entries and redact stored content while preserving deduplication identity.
  // Parameters: ids (Iterable<String>): notification entry IDs.
  // Returns: Future<void>: redaction completion and change notification; rejected writes throw.
  Future<void> remove(Iterable<String> ids) async {
    final preferences = await _preferences();
    for (final id in ids) {
      if (!await preferences.setBool(_key('hidden', id), true)) {
        throw StateError('Notification history could not be updated.');
      }
      final key = _key('entry', id);
      final stored = preferences.getString(key);
      if (stored == null) continue;
      if (!await preferences.setString(key, _withoutContent(id, stored))) {
        throw StateError('Notification history could not be updated.');
      }
    }
    changes.add(userHash);
  }

  // Function Name: _withoutContent
  // Description: Remove sensitive content while retaining valid category and time, using safe defaults for malformed stored JSON.
  // Parameters: id (String): preserved identity; stored (String): existing JSON.
  // Returns: String: redacted entry JSON with empty title, body and payload.
  String _withoutContent(String id, String stored) {
    Object? category;
    Object? occurredAt;
    try {
      final json = jsonDecode(stored);
      if (json is Map<String, dynamic>) {
        category = json['category'];
        occurredAt = json['occurred_at'];
      }
    } on FormatException {
      // 깨진 저장값은 기본값으로 덮어쓴다.
    }
    final occurredAtText =
        occurredAt is String && DateTime.tryParse(occurredAt) != null
        ? occurredAt
        : now().toUtc().toIso8601String();
    return jsonEncode({
      'id': id,
      'title': '',
      'body': '',
      'payload': '',
      'category':
          NotificationInboxCategory.values.any((value) => value.name == category)
          ? category
          : NotificationInboxCategory.medication.name,
      'occurred_at': occurredAtText,
    });
  }

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

  // Function Name: cancelFutureReminders
  // Description: Remove future reminder history matching a slot, or an ID when no slot is supplied; skip malformed records.
  // Parameters: slotKey (String?): preferred slot filter; id (int?): notification-ID filter; neither selects all future reminders.
  // Returns: Future<void>: history cleanup; does not cancel platform notifications.
  Future<void> cancelFutureReminders({String? slotKey, int? id}) async {
    final preferences = await _preferences();
    var removed = false;
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
        removed = true;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    if (removed) changes.add(userHash);
  }
}
