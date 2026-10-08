import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';
import '../services/caregiver_patient_local_state_service.dart';
import 'manage_user_setting_control.dart';

// 파일명: manage_account_control.dart
// 역할: 사용자 데이터 전체 삭제 요청과 기기 캐시 정리를 담당한다.

// Class Name: AccountDeletionFailureReason
// Role: Names why account-data deletion stopped before the device cache was cleared.
// Responsibilities:
// - Let the settings screen choose the guidance in its own language instead of printing a fixed sentence.
enum AccountDeletionFailureReason { serverRejected, missingAccountScope }

// Class Name: AccountDeletionFailure
// Role: Reports a stopped account-data deletion to callers that handle StateError.
// Responsibilities:
// - Keep the existing Korean sentence as the StateError message and provide the same guidance in English.
// Attributes:
// - reason (AccountDeletionFailureReason): Why the deletion stopped.
class AccountDeletionFailure extends StateError {
  final AccountDeletionFailureReason reason;

  // Function Name: AccountDeletionFailure
  // Description: Creates the failure with the Korean guidance for the reason as its StateError message.
  // Parameters:
  // - reason (AccountDeletionFailureReason): Why the deletion stopped.
  // Returns:
  // - AccountDeletionFailure: the initialized instance.
  AccountDeletionFailure(this.reason) : super(_message(reason, false));

  // Function Name: messageFor
  // Description: Resolves this failure in the language currently shown on screen.
  // Parameters:
  // - isEnglish (bool): Whether to choose the English display string.
  // Returns:
  // - String: English or Korean guidance for this failure.
  String messageFor(bool isEnglish) => _message(reason, isEnglish);

  // Function Name: _message
  // Description: Holds the English and Korean guidance for each deletion failure reason.
  // Parameters:
  // - reason (AccountDeletionFailureReason): Why the deletion stopped.
  // - isEnglish (bool): Whether to choose the English display string.
  // Returns:
  // - String: Guidance for the reason in the requested language.
  static String _message(AccountDeletionFailureReason reason, bool isEnglish) {
    return switch (reason) {
      AccountDeletionFailureReason.serverRejected =>
        isEnglish ? 'Could not delete account data.' : '계정 데이터를 삭제하지 못했습니다.',
      AccountDeletionFailureReason.missingAccountScope =>
        isEnglish
            ? 'There is no account scope to delete.'
            : '삭제할 사용자 범위가 없습니다.',
    };
  }
}

// Class Name: ManageAccount
// Role: Coordinates deletion of server account data and user-scoped local preferences.
// Responsibilities:
// - Delete authenticated backend data first and retain local state when the server rejects deletion.
// Attributes:
// - userHash (String): Current user hash defining ownership, display, or persistence scope.
// - client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
class ManageAccount {
  static const List<String> _slotKeys = [
    'morning',
    'lunch',
    'evening',
    'bedtime',
  ];
  static const List<String> _scopedSettingNames = [
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
  ];
  // Keys written before settings and reminders were scoped to an account.
  // They are still read as a fallback by any account without its own value,
  // so they are named exactly and never matched by prefix.
  static final List<String> _unscopedLegacyKeys = [
    ...ManageUserSetting.legacyUnscopedKeys,
    for (final slot in _slotKeys) 'medbuddy_medication_reminder_$slot',
  ];
  // Every namespace whose key carries an owner hash. A key of one of these
  // shapes that survives the cleanup below belongs to another account.
  static final List<RegExp> _accountScopedKeyPatterns = [
    RegExp('^user_setting_.+_(?:${_scopedSettingNames.join('|')})\$'),
    RegExp(
      '^medbuddy_medication_reminder_patient_.+_(?:${_slotKeys.join('|')})\$',
    ),
    // The plan written without a signed-in owner is device state, not an account.
    RegExp(
      '^medbuddy_reminder_plan_(?!guest_(?:${_slotKeys.join('|')})\$)'
      '.+_(?:${_slotKeys.join('|')})\$',
    ),
    RegExp(r'^medbuddy\.favorite_(?:pharmacy|hospital)_ids\..+$'),
    RegExp(
      '^(?:'
      '${RegExp.escape(CaregiverPatientLocalStateService.linkedPatientsKeyPrefix)}|'
      '${RegExp.escape(CaregiverPatientLocalStateService.patientLabelKeyPrefix)}|'
      '${RegExp.escape(CaregiverPatientLocalStateService.alertKeyPrefix)}'
      ').+\$',
    ),
    RegExp(r'^notification_inbox_v1\..+$'),
    RegExp(r'^caregiver_delivery_.+_[a-f0-9]{64}$'),
  ];

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
  // Description: Deletes authenticated server account data, then removes only preferences explicitly owned by the current user; server failure leaves the cache untouched. The unscoped legacy settings and reminder keys are removed as well, but only when no other account's data remains on the device, so a later account does not inherit them and an existing one does not lose its fallback.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> deleteAccountData() async {
    final response = await client
        .delete(Uri.parse(ApiConfig.authUrl('/account-data')))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw AccountDeletionFailure(AccountDeletionFailureReason.serverRejected);
    }
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      throw AccountDeletionFailure(
        AccountDeletionFailureReason.missingAccountScope,
      );
    }
    final preferences = await SharedPreferences.getInstance();
    // Underscores are valid inside hashes, so match complete setting/reminder
    // keys instead of treating every underscore as an account boundary.
    final exactKeys = <String>{
      for (final setting in _scopedSettingNames)
        'user_setting_${normalizedUserHash}_$setting',
      for (final slot in _slotKeys) ...{
        'medbuddy_medication_reminder_patient_${normalizedUserHash}_$slot',
        'medbuddy_medication_reminder_patient_${normalizedUserHash}_${normalizedUserHash}_$slot',
        'medbuddy_reminder_plan_${normalizedUserHash}_$slot',
      },
      'medbuddy.favorite_pharmacy_ids.$normalizedUserHash',
      'medbuddy.favorite_hospital_ids.$normalizedUserHash',
      '${CaregiverPatientLocalStateService.linkedPatientsKeyPrefix}'
          '$normalizedUserHash',
    };
    // Only the namespace owner counts; a patient/message reference in another
    // user's key is not owned by the account being deleted.
    final scopedPrefixes = [
      '${CaregiverPatientLocalStateService.patientLabelKeyPrefix}'
          '$normalizedUserHash.',
      '${CaregiverPatientLocalStateService.alertKeyPrefix}'
          '$normalizedUserHash.',
      'notification_inbox_v1.${Uri.encodeComponent(normalizedUserHash)}.',
    ];
    // Delivery markers end in a 64-hex event ID; match the whole key so a
    // hash that merely extends this one keeps its own markers.
    final deliveryMarker = RegExp(
      '^${RegExp.escape('caregiver_delivery_${normalizedUserHash}_')}'
      r'[a-f0-9]{64}$',
    );
    final userScopedKeys = preferences
        .getKeys()
        .where(
          /* Function Name: where callback
         * Description: Selects exact preference keys or delimited namespaces owned by the normalized account hash.
         * Parameters:
         * - key (String): Persisted preference key.
         * Returns:
         * - Whether the key belongs to the account's cleanup set.
         */
          (key) =>
              exactKeys.contains(key) ||
              scopedPrefixes.any(key.startsWith) ||
              deliveryMarker.hasMatch(key),
        )
        .toList(growable: false);
    for (final key in userScopedKeys) {
      await preferences.remove(key);
    }
    // The unscoped legacy keys have no owner in their name. With the deleted
    // account's keys gone, any remaining account-scoped key shows that another
    // account uses this device and may still read them as its fallback.
    final anotherAccountRemains = preferences.getKeys().any(
      /* Function Name: any callback
       * Description: Detects a preference key that carries the owner hash of an account.
       * Parameters:
       * - key (String): Persisted preference key.
       * Returns:
       * - Whether the key belongs to an account-scoped namespace.
       */
      (key) => _accountScopedKeyPatterns.any(
        (pattern) => pattern.hasMatch(key),
      ),
    );
    if (anotherAccountRemains) {
      return;
    }
    for (final key in _unscopedLegacyKeys) {
      await preferences.remove(key);
    }
  }
}
