import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

// 파일명: manage_account_control.dart
// 역할: 사용자 데이터 전체 삭제 요청과 기기 캐시 정리를 담당한다.

// Class Name: ManageAccount
// Role: Coordinates deletion of server account data and user-scoped local preferences.
// Responsibilities:
// - Delete authenticated backend data first and retain local state when the server rejects deletion.
// Attributes:
// - userHash (String): Current user hash defining ownership, display, or persistence scope.
// - client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
class ManageAccount {
  final String userHash;
  final http.Client client;

  // Function Name: ManageAccount
  // Description: Binds authenticated account deletion and subsequent local-cache cleanup to the supplied user scope and HTTP client.
  // Parameters:
  // - userHash (String): Current user hash defining ownership, display, or persistence scope.
  // - client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - ManageAccount: the initialized instance.
  const ManageAccount({required this.userHash, required this.client});

  // Function Name: deleteAccountData
  // Description: Deletes authenticated server account data, then removes only preferences explicitly owned by the current user; server failure leaves the cache untouched.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> deleteAccountData() async {
    final response = await client
        .delete(Uri.parse(ApiConfig.authUrl('/account-data')))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('계정 데이터를 삭제하지 못했습니다.');
    }
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      throw StateError('삭제할 사용자 범위가 없습니다.');
    }
    final preferences = await SharedPreferences.getInstance();
    // Underscores are valid inside hashes, so match complete setting/reminder
    // keys instead of treating every underscore as an account boundary.
    final exactKeys = <String>{
      for (final setting in const [
        'font_size',
        'reading_speed',
        'language',
        'language_mode',
        'time_format',
        'home_schedule_source',
        'medication_notifications_enabled',
        'caregiver_notifications_enabled',
        'chat_notifications_enabled',
        'notification_detail_mode',
        'default_morning_time',
        'default_lunch_time',
        'default_evening_time',
        'default_bedtime',
        // Retired account-scoped settings may still exist after an upgrade.
        'nearby_pharmacy_lab_enabled',
        'linked_medication_chat_lab_enabled',
        'multi_pill_identification_lab_enabled',
      ])
        'user_setting_${normalizedUserHash}_$setting',
      for (final slot in const ['morning', 'lunch', 'evening', 'bedtime']) ...{
        'medbuddy_medication_reminder_patient_${normalizedUserHash}_$slot',
        'medbuddy_medication_reminder_patient_${normalizedUserHash}_${normalizedUserHash}_$slot',
      },
      'medbuddy.favorite_pharmacy_ids.$normalizedUserHash',
      'caregiver_linked_patients.$normalizedUserHash',
    };
    // Only the namespace owner counts; a patient/message reference in another
    // user's key is not owned by the account being deleted.
    final scopedPrefixes = [
      'caregiver_patient_label.$normalizedUserHash.',
      'caregiver_alert.$normalizedUserHash.',
      'notification_inbox_v1.${Uri.encodeComponent(normalizedUserHash)}.',
    ];
    final userScopedKeys = preferences
        .getKeys()
        .where(
          /* Function Name: where callback
         * Description: Selects exact preference keys or delimited namespaces owned by the normalized account hash.
         * Parameters:
         * - key (String): Persisted preference key.
         * Returns:
         * - Whether the key belongs to the account's cleanup set.
         */ (key) =>
              exactKeys.contains(key) || scopedPrefixes.any(key.startsWith),
        )
        .toList(growable: false);
    for (final key in userScopedKeys) {
      await preferences.remove(key);
    }
  }
}
