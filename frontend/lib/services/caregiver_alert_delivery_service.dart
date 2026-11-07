// File Name: caregiver_alert_delivery_service.dart
// Role: Presents account-owned caregiver deliveries with durable event deduplication.
// Role: Render missed-dose data deliveries once per account and delivery event.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/caregiver_alert_context_entity.dart';
import '../entities/user_setting_entity.dart';
import 'notification_inbox_store.dart';
import 'notification_service.dart';
import 'user_setting_preference_keys.dart';

// Function Name: CaregiverAlertPresenter
// Description: Presents one validated caregiver alert with localized text through an injected delivery boundary.
// Parameters: alert (CaregiverAlertContext) - delivery identity; title/body/language (String) - localized notification content and locale.
// Returns: Display completion Future; failures must propagate so the delivery is not marked as presented.
typedef CaregiverAlertPresenter = Future<void> Function(
  CaregiverAlertContext alert, String title, String body, String language,
);

// 클래스명: CaregiverAlertDeliveryService
// 역할: 현재 수신자에게 보호자 알림을 표시하고 완료 이벤트 중복 표시를 억제한다.
// 주요 책임: 활성 사용자·영속 수신 표식·진행 중 표시를 확인하고 오래된 표식을 정리한다.
// 속성: _presenting (Set<String>): 진행 중 키; markerRetention (Duration): 표식 보존 기간; markerKeyPattern (RegExp): 허용 키; clock (DateTime Function()): 정리 시각.
class CaregiverAlertDeliveryService {
  static final Set<String> _presenting = {};
  static const Duration markerRetention = Duration(days: 7);
  static final RegExp markerKeyPattern = RegExp(r'^caregiver_delivery_.+_[a-f0-9]{64}$');
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  // 정기 완료 알림의 성공한 표시만 계정별로 보존해 재수신·재시작 후 반복 표시를 막는다.
  // 표시 실패는 기록하지 않아 같은 이벤트의 다음 전송에서 다시 표시할 수 있다.
  // 함수이름: presentCompletionOnce
  // 함수역할: 현재 수신 계정과 유효한 이벤트 해시를 확인해 이미 표시한 완료 알림은 생략하고 성공한 표시만 기록한다.
  // 매개변수: recipientHash/eventKey (String) - 수신 계정·64자리 소문자 해시; present (Future<void> Function()) - 실제 표시 함수.
  // 반환값: 새로 표시하고 기록하면 true, 잘못된 키·다른 계정·중복이면 false. 표시·설정 오류는 전파하고 실행 중 표식은 해제한다.
  static Future<bool> presentCompletionOnce({
    required String recipientHash,
    required String eventKey,
    required Future<void> Function() present,
  }) async {
    if (recipientHash.isEmpty || !RegExp(r'^[0-9a-f]{64}$').hasMatch(eventKey)) {
      return false;
    }
    final key = markerKeyFor(recipientHash, eventKey);
    if (!_presenting.add(key)) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      if (preferences.getString(NotificationInboxStore.activeUserKey) != recipientHash ||
          preferences.get(key) != null) {
        return false;
      }
      await present();
      await preferences.setInt(key, clock().millisecondsSinceEpoch);
      await _pruneMarkers(preferences);
      return true;
    } finally {
      _presenting.remove(key);
    }
  }

  // Function Name: display
  // Description: Shows a missed-dose delivery for the signed-in recipient once, honoring the lock-screen detail setting, then records a dated delivery marker and prunes expired ones.
  // Parameters:
  // - data (Map<String, dynamic>): FCM data payload.
  // - presenter (CaregiverAlertPresenter?): Replaces the system notification in tests.
  // Returns:
  // - Future<bool>: true when the alert was shown; false when invalid, for another account, or already shown.
  static Future<bool> display(
    Map<String, dynamic> data, {
    CaregiverAlertPresenter? presenter,
  }) async {
    final alert = CaregiverAlertContext.fromData(data);
    if (alert == null) return false;
    final key = markerKeyFor(alert.recipientHash, alert.eventId);
    if (!_presenting.add(key)) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      // Older builds stored `true`; newer ones store the delivery time in milliseconds.
      if (preferences.getString(NotificationInboxStore.activeUserKey) != alert.recipientHash ||
          preferences.get(key) != null) {
        return false;
      }
      final language = normalizeAppLanguage(data['language']?.toString());
      final detailed = preferences.getString(
        UserSettingPreference.notificationDetailMode.keyFor(alert.recipientHash),
      ) != 'type_only';
      final title = detailed && (data['title']?.toString().isNotEmpty ?? false)
          ? data['title'].toString() : language == 'en' ? 'Medication update' : '복약 상태 알림';
      final body = detailed && (data['body']?.toString().isNotEmpty ?? false)
          ? data['body'].toString() : language == 'en'
          ? 'Check your linked patient\'s medication status.' : '연동된 환자의 복약 상태를 확인해 주세요.';
      await (presenter ?? _present)(alert, title, body, language);
      await preferences.setInt(key, clock().millisecondsSinceEpoch);
      await _pruneMarkers(preferences);
      return true;
    } finally {
      _presenting.remove(key);
    }
  }

  // Function Name: markerKeyFor
  // Description: Builds the preference key that records one delivery for one recipient; account deletion removes the same keys.
  // Parameters:
  // - recipientHash (String): Account hash of the recipient, used as given.
  // - eventId (String): Delivery event ID; an empty ID yields the recipient's marker prefix.
  // Returns:
  // - String: The key "caregiver_delivery_<recipientHash>_<eventId>".
  static String markerKeyFor(String recipientHash, String eventId) =>
      'caregiver_delivery_${recipientHash}_$eventId';

  // Function Name: _pruneMarkers
  // Description: Removes delivery markers older than markerRetention, after which a late duplicate delivery is no longer expected. Undated markers from older builds are dated now so they expire on the same schedule. Pruning failures never undo a shown alert.
  // Parameters:
  // - preferences (SharedPreferences): Freshly reloaded preference store.
  // Returns:
  // - Future<void>: Completes after pruning was attempted.
  static Future<void> _pruneMarkers(SharedPreferences preferences) async {
    try {
      final now = clock().millisecondsSinceEpoch;
      final cutoff = now - markerRetention.inMilliseconds;
      for (final key in preferences.getKeys().where(markerKeyPattern.hasMatch).toList()) {
        final value = preferences.get(key);
        if (value is int) {
          if (value < cutoff) await preferences.remove(key);
        } else {
          await preferences.setInt(key, now);
        }
      }
    } catch (error) {
      debugPrint('Caregiver delivery marker pruning failed: ${error.runtimeType}');
    }
  }

  // Function Name: _present
  // Description: Delegates a caregiver alert to the notification service with its recipient history scope and stable event ID.
  // Parameters: alert (CaregiverAlertContext) - validated alert; title/body/language (String) - localized content and locale.
  // Returns: Platform presentation completion; errors propagate to prevent successful-delivery marking.
  static Future<void> _present(CaregiverAlertContext alert, String title, String body, String language) =>
      NotificationService.instance.showCaregiverAlert(
        id: alert.notificationId, title: title, body: body,
        patientHash: alert.patientHash, historyUserHash: alert.recipientHash,
        language: language, alertContext: alert,
      );
}
