// 파일명: manage_account_control_test.dart
// 역할: 계정 데이터 삭제의 서버 우선 순서와 사용자별 로컬 캐시 보존 규칙을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medbuddy_frontend/controls/manage_account_control.dart';

// Function Name: main
// Description:
// - Register regression cases for server-authorized account deletion and user-scoped cache cleanup.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Function Name: test callback
  // Description:
  // - Verify that successful server deletion clears only the current user's cached data.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('서버 삭제 성공 후 현재 사용자 캐시만 비운다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_usr_test_font_size': 'large',
      'medbuddy_medication_reminder_patient_usr_test_morning': '08:00',
      'user_setting_usr_other_font_size': 'small',
      'medbuddy_app_language': 'ko',
    });
    late http.Request capturedRequest;
    final control = ManageAccount(
      userHash: 'usr_test',
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 서버 계정 삭제 요청을 보관하고 삭제 성공을 제공한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
      // 반환값:
      // - success=true인 HTTP 200 응답.
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"success":true}', 200);
      }),
    );

    await control.deleteAccountData();

    expect(capturedRequest.method, 'DELETE');
    expect(capturedRequest.url.path, '/api/v1/auth/account-data');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('user_setting_usr_test_font_size'), isNull);
    expect(
      preferences.getString(
        'medbuddy_medication_reminder_patient_usr_test_morning',
      ),
      isNull,
    );
    expect(preferences.getString('user_setting_usr_other_font_size'), 'small');
    expect(preferences.getString('medbuddy_app_language'), 'ko');
  });

  // Function Name: test callback
  // Description:
  // - Verify that rejected server deletion preserves local user data.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('서버 삭제 실패 시 로컬 캐시를 보존한다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_usr_test_font_size': 'large',
    });
    final control = ManageAccount(
      userHash: 'usr_test',
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 네트워크 없이 HTTP 500 상태와 고정 응답 본문를 제공한다.
      // 매개변수:
      // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
      // 반환값:
      // - HTTP 500 응답 Future.
      client: MockClient((_) async => http.Response('failure', 500)),
    );

    await expectLater(control.deleteAccountData(), throwsStateError);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('user_setting_usr_test_font_size'), 'large');
  });

  // Function Name: scopedPreferences
  // Description: Creates representative keys using the existing account-owned storage formats.
  // Parameters:
  // - owner (String): Account hash used in each preference namespace.
  // Returns:
  // - Map<String, Object>: Settings, reminders, favorites, links, and inbox records.
  Map<String, Object> scopedPreferences(String owner) => {
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
      'nearby_pharmacy_lab_enabled',
      'linked_medication_chat_lab_enabled',
      'multi_pill_identification_lab_enabled',
    ])
      'user_setting_${owner}_$setting': 'cached',
    for (final slot in const ['morning', 'lunch', 'evening', 'bedtime']) ...{
      'medbuddy_medication_reminder_patient_${owner}_$slot': 'legacy',
      'medbuddy_medication_reminder_patient_${owner}_${owner}_$slot': 'current',
    },
    'medbuddy.favorite_pharmacy_ids.$owner': <String>['pharmacy-1'],
    'caregiver_linked_patients.$owner': <String>['patient-1'],
    'caregiver_patient_label.$owner.patient-1': 'Family',
    'caregiver_alert.$owner.patient-1.morning.snapshot_data': '{}',
    for (final kind in const ['entry', 'read', 'hidden'])
      'notification_inbox_v1.${Uri.encodeComponent(owner)}.$kind.notice-1':
          'cached',
  };

  // Function Name: test callback
  // Description: Removes only the exact owner, even when another hash shares its prefix, suffix, or an underscore-delimited segment.
  // Parameters: None.
  // Returns: Future<void>; completes when other accounts and unscoped values remain intact.
  test(
    'similar hashes and references in another owner namespace are preserved',
    () async {
      final owned = scopedPreferences('usr_test');
      final preserved = <String, Object>{
        for (final other in const [
          'usr_test2',
          'xusr_test',
          'usr_test_extra',
          'usr_test_font_size',
        ])
          ...scopedPreferences(other),
        'caregiver_patient_label.usr_other.usr_test': 'Patient',
        'caregiver_alert.usr_other.usr_test.morning.mode': 'all',
        'notification_inbox_v1.usr_other.entry.usr_test': 'message',
        'unrelated_usr_test_cache': 'keep',
        'user_setting_font_size': 18,
        'medbuddy_medication_reminder_morning': '08:00',
        'medbuddy.favorite_pharmacy_ids': <String>['shared'],
        'medbuddy_app_language': 'ko',
        'notification_inbox_active_user': 'usr_test',
      };
      SharedPreferences.setMockInitialValues({...owned, ...preserved});
      // Function Name: MockClient callback
      // Description: Authorizes deletion without contacting the account server.
      // Parameters: request (http.Request), unused request.
      // Returns: HTTP 200 response.
      final client = MockClient(
        (request) async => http.Response('{"success":true}', 200),
      );
      addTearDown(client.close);
      await ManageAccount(
        userHash: '  usr_test  ',
        client: client,
      ).deleteAccountData();
      final preferences = await SharedPreferences.getInstance();
      for (final key in owned.keys) {
        expect(preferences.containsKey(key), isFalse, reason: key);
      }
      expect(preferences.getKeys(), preserved.keys.toSet());
      for (final entry in preserved.entries) {
        expect(preferences.get(entry.key), entry.value, reason: entry.key);
      }
    },
  );

  // Function Name: test callback
  // Description: Treats hash punctuation literally and uses the inbox's URI-encoded owner scope.
  // Parameters: None.
  // Returns: Future<void>; completes when only the requested account's keys are removed.
  test(
    'literal and URI-encoded account scopes do not match similar names',
    () async {
      final owned = scopedPreferences('usr.test+id@demo');
      final preserved = scopedPreferences('usrXtest+id@demo');
      SharedPreferences.setMockInitialValues({...owned, ...preserved});
      // Function Name: MockClient callback
      // Description: Authorizes deletion without real account changes.
      // Parameters: request (http.Request), unused request.
      // Returns: HTTP 200 response.
      final client = MockClient(
        (request) async => http.Response('{"success":true}', 200),
      );
      addTearDown(client.close);
      await ManageAccount(
        userHash: 'usr.test+id@demo',
        client: client,
      ).deleteAccountData();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), preserved.keys.toSet());
    },
  );
}
