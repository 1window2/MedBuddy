// 필요시 약은 사용자가 지정한 다음 시각에 한 번만 확인을 요청한다.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/medication_history_entity.dart';
import '../services/notification_service.dart';

class AsNeededCheckReminderControl extends ChangeNotifier {
  AsNeededCheckReminderControl({
    required this.patientHash,
    required this.ensureSession,
    NotificationService? notifications,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
  }) : _notifications = notifications ?? NotificationService.instance,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  final String patientHash;
  final VoidCallback ensureSession;
  final NotificationService _notifications;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  DateTime? scheduledAt;
  bool busy = false;
  bool _disposed = false;
  String get _key => 'medbuddy_as_needed_check_$patientHash';
  // 정기 시간대의 기본 ID와 분리하며 날짜별 ID는 기존 알림 서비스가 만든다.
  static const notificationId = 84005;
  bool get enabled => scheduledAt?.isAfter(_now()) ?? false;

  void _checkSession() {
    if (_disposed) throw StateError('Reminder control is closed.');
    ensureSession();
  }

  Future<void> restore({required bool allowed, required bool isEnglish}) async {
    if (busy || _disposed) return;
    busy = true;
    try {
      _checkSession();
      final prefs = await _preferences();
      _checkSession();
      final date = DateTime.tryParse(prefs.getString(_key) ?? '');
      scheduledAt = date != null && date.isAfter(_now()) ? date : null;
      if (!allowed) {
        await _notifications.cancelReminder(
          notificationId,
          slotKey: 'as_needed',
        );
        _checkSession();
        await prefs.remove(_key);
        scheduledAt = null;
      } else if (enabled) {
        await _schedule(scheduledAt!, isEnglish);
        _checkSession();
      }
    } catch (_) {
      scheduledAt = null;
      rethrow;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> save(DateTime? date, {required bool isEnglish}) async {
    if (busy || _disposed) return;
    _checkSession();
    if (date != null && !date.isAfter(_now())) {
      throw const FormatException('Choose a future reminder time.');
    }
    busy = true;
    notifyListeners();
    try {
      final prefs = await _preferences();
      _checkSession();
      if (date == null) {
        await _notifications.cancelReminder(
          notificationId,
          slotKey: 'as_needed',
        );
      } else {
        if (!await _notifications.requestPermission()) {
          throw StateError('Notification permission is required.');
        }
        _checkSession();
        // 이전 예약을 명시적으로 지워, 오늘보다 이른 시각으로 바꿔도 남지 않게 한다.
        await _notifications.cancelReminder(
          notificationId,
          slotKey: 'as_needed',
        );
        _checkSession();
        await _schedule(date, isEnglish);
      }
      _checkSession();
      final stored = date == null
          ? await prefs.remove(_key)
          : await prefs.setString(_key, date.toUtc().toIso8601String());
      if (!stored) throw StateError('Could not store reminder.');
      scheduledAt = date;
    } catch (_) {
      // 예약 또는 설정 저장에 실패하면 켜진 것처럼 표시하지 않는다.
      try {
        _checkSession();
        await _notifications.cancelReminder(
          notificationId,
          slotKey: 'as_needed',
        );
        final prefs = await _preferences();
        _checkSession();
        await prefs.remove(_key);
        scheduledAt = null;
      } catch (_) {}
      rethrow;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _schedule(DateTime date, bool isEnglish) {
    final wall = MedicationHistoryDates.wallTime(date);
    return _notifications.registerNotification(
      id: notificationId,
      slotKey: 'as_needed',
      slotTitle: isEnglish ? 'As-needed' : '필요시 약',
      hour: wall.hour,
      minute: wall.minute,
      medicationNames: const [],
      activeDates: [DateTime(wall.year, wall.month, wall.day)],
      language: isEnglish ? 'en' : 'ko',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
