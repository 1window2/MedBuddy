// 파일명: as_needed_check_reminder_control.dart
// 역할: 필요시 복용 확인 알림 한 건의 계정별 복원·예약·취소를 관리한다.
// 필요시 약은 사용자가 지정한 다음 시각에 한 번만 확인을 요청한다.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/medication_history_entity.dart';
import '../services/notification_service.dart';

// Class Name: AsNeededCheckReminderControl
// Role: Owns one account's next as-needed medication check reminder.
// Responsibilities: Restore or replace a future reminder, verify the live session around awaits, and publish busy/scheduled state.
// Attributes: patientHash (String), ensureSession (VoidCallback): Account guard; scheduledAt (DateTime?), busy (bool): UI state; _notifications/_preferences/_now: Injected services; _disposed (bool): Lifetime guard.
class AsNeededCheckReminderControl extends ChangeNotifier {
  // 함수이름: AsNeededCheckReminderControl
  // 함수역할: 계정·세션 검사와 알림·저장소·시계 의존성을 묶는다. 생성만으로 알림을 예약하지 않는다.
  // 매개변수: patientHash (String): 계정; ensureSession (VoidCallback): 유효하지 않으면 예외를 던질 검사; notifications/preferences/now: 선택적 알림·설정·시계 공급자.
  // 반환값: 아직 복원하지 않은 확인 알림 컨트롤.
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
  // Function Name: _key
  // Description: Scopes the stored reminder timestamp to this control's account.
  // Parameters: None.
  // Returns: The account-specific preference key used for restoration and deletion.
  String get _key => storageKeyFor(patientHash);
  // Function Name: storageKeyFor
  // Description: Preference key of an account's next as-needed check; account deletion removes it.
  // Parameters: patientHash - account hash. Returns: The preference key.
  static String storageKeyFor(String patientHash) =>
      'medbuddy_as_needed_check_$patientHash';
  // 정기 시간대의 기본 ID와 분리하며 날짜별 ID는 기존 알림 서비스가 만든다.
  static const notificationId = 84005;
  // 함수이름: enabled
  // 함수역할: 보관한 확인 알림 시각이 아직 미래인지 확인한다.
  // 매개변수: 없음.
  // 반환값: 시각이 있고 현재보다 뒤면 true. 플랫폼에 실제 예약됐는지는 다시 조회하지 않는다.
  bool get enabled => scheduledAt?.isAfter(_now()) ?? false;

  // 함수이름: _checkSession
  // 함수역할: 종료된 컨트롤을 거부하고 호출자의 계정 세션 유효성을 확인한다.
  // 매개변수: 없음.
  // 반환값: 없음. 종료 시 StateError, 세션 검사 실패는 원래 예외를 전파한다.
  void _checkSession() {
    if (_disposed) throw StateError('Reminder control is closed.');
    ensureSession();
  }

  // 함수이름: restore
  // 함수역할: 저장된 미래 시각을 복원해 재예약하거나 알림 비허용이면 기존 알림과 저장 시각을 삭제한다.
  // 매개변수: allowed (bool): 알림 허용; isEnglish (bool): 예약할 알림 언어.
  // 반환값: 복원 완료 Future. 사용 중·종료 상태는 무시하며 실패 시 표시 시각을 비우고 예외를 전파한다.
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

  // 함수이름: save
  // 함수역할: 미래 시각의 알림을 권한 확인 후 교체하고 UTC 시각을 저장한다. null이면 알림을 끈다.
  // 매개변수: date (DateTime?): 새 확인 시각 또는 끄기; isEnglish (bool): 알림 언어.
  // 반환값: 완료 Future. 과거 시각·권한 거부·저장 실패는 예외이며 실패 시 가능한 범위에서 예약을 정리한다.
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

  // 함수이름: _schedule
  // 함수역할: 복약 기록 기준 벽시각으로 변환해 필요시 약 확인 알림을 한 날짜에 예약한다.
  // 매개변수: date (DateTime): 예약 시각; isEnglish (bool): 시간대 제목과 언어 선택.
  // 반환값: 플랫폼 등록 완료 Future. 권한·세션 검사는 호출자가 맡고 예약 오류는 전파한다.
  Future<void> _schedule(DateTime date, bool isEnglish) {
    final wall = MedicationHistoryDates.wallTime(date);
    return _notifications.registerNotification(
      id: notificationId,
      slotKey: 'as_needed',
      slotTitle: isEnglish ? 'As-needed' : '필요시 약',
      hour: wall.hour,
      minute: wall.minute,
      activeDates: [DateTime(wall.year, wall.month, wall.day)],
      language: isEnglish ? 'en' : 'ko',
    );
  }

  // 함수이름: dispose
  // 함수역할: 종료 상태를 표시해 진행 중 비동기 작업의 후속 세션 쓰기를 막고 리스너를 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음. 이미 예약한 알림과 저장 시각은 여기서 삭제하지 않는다.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
