// Role: Render missed-dose data deliveries once per account and delivery event.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/caregiver_alert_context_entity.dart';
import '../entities/user_setting_entity.dart';
import 'notification_inbox_store.dart';
import 'notification_service.dart';
import 'user_setting_preference_keys.dart';

typedef CaregiverAlertPresenter = Future<void> Function(
  CaregiverAlertContext alert, String title, String body, String language,
);

// Class Name: CaregiverAlertDeliveryService
// Role: Shows each missed-dose delivery once per account even when FCM delivers it to both the foreground and background handlers.
// Attributes:
// - _presenting (Set<String>): Delivery markers being shown in this isolate.
// - markerRetention (Duration): How long a delivery marker is kept before it is pruned.
// - clock (DateTime Function()): Time source for marker dates; replaced only by tests.
// - markerKeyPattern (RegExp): Matches every account's delivery marker key; account deletion uses the same shape.
class CaregiverAlertDeliveryService {
  static final Set<String> _presenting = {};
  static const Duration markerRetention = Duration(days: 7);
  static final RegExp markerKeyPattern = RegExp(r'^caregiver_delivery_.+_[a-f0-9]{64}$');
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

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
          ? 'Check your linked patient’s medication status.' : '연동된 환자의 복약 상태를 확인해 주세요.';
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

  static Future<void> _present(CaregiverAlertContext alert, String title, String body, String language) =>
      NotificationService.instance.showCaregiverAlert(
        id: alert.notificationId, title: title, body: body,
        patientHash: alert.patientHash, historyUserHash: alert.recipientHash,
        language: language, alertContext: alert,
      );
}
