// Role: Render missed-dose data deliveries once per account and delivery event.
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/caregiver_alert_context_entity.dart';
import 'notification_inbox_store.dart';
import 'notification_service.dart';

typedef CaregiverAlertPresenter = Future<void> Function(
  CaregiverAlertContext alert, String title, String body, String language,
);

class CaregiverAlertDeliveryService {
  static final Set<String> _presenting = {};

  static Future<bool> display(
    Map<String, dynamic> data, {
    CaregiverAlertPresenter? presenter,
  }) async {
    final alert = CaregiverAlertContext.fromData(data);
    if (alert == null) return false;
    final key = 'caregiver_delivery_${alert.recipientHash}_${alert.eventId}';
    if (!_presenting.add(key)) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      if (preferences.getString(NotificationInboxStore.activeUserKey) != alert.recipientHash ||
          preferences.getBool(key) == true) return false;
      final language = data['language'] == 'en' ? 'en' : 'ko';
      final detailed = preferences.getString(
        'user_setting_${alert.recipientHash}_notification_detail_mode',
      ) != 'type_only';
      final title = detailed && (data['title']?.toString().isNotEmpty ?? false)
          ? data['title'].toString() : language == 'en' ? 'Medication update' : '복약 상태 알림';
      final body = detailed && (data['body']?.toString().isNotEmpty ?? false)
          ? data['body'].toString() : language == 'en'
          ? 'Check your linked patient’s medication status.' : '연동된 환자의 복약 상태를 확인해 주세요.';
      await (presenter ?? _present)(alert, title, body, language);
      await preferences.setBool(key, true);
      return true;
    } finally {
      _presenting.remove(key);
    }
  }

  static Future<void> _present(CaregiverAlertContext alert, String title, String body, String language) =>
      NotificationService.instance.showCaregiverAlert(
        id: alert.notificationId, title: title, body: body,
        patientHash: alert.patientHash, historyUserHash: alert.recipientHash,
        language: language, alertContext: alert,
      );
}
