// 파일명: manage_account_control_test.dart
// 역할: 계정 데이터 삭제의 서버 우선 순서와 사용자별 로컬 캐시 보존 규칙을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medbuddy_frontend/controls/manage_account_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('서버 삭제 실패 시 로컬 캐시를 보존한다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_usr_test_font_size': 'large',
    });
    final control = ManageAccount(
      userHash: 'usr_test',
      client: MockClient((_) async => http.Response('failure', 500)),
    );

    await expectLater(control.deleteAccountData(), throwsStateError);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('user_setting_usr_test_font_size'), 'large');
  });
}
