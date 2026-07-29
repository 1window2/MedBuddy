// 파일명: manage_account_control_test.dart
// 역할: 계정 데이터 삭제의 서버 우선 순서와 로컬 캐시 보존 규칙을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medbuddy_frontend/controls/manage_account_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('서버 삭제 성공 후 로컬 캐시를 비운다', () async {
    SharedPreferences.setMockInitialValues({'saved-setting': 'value'});
    late http.Request capturedRequest;
    final control = ManageAccount(
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"success":true}', 200);
      }),
    );

    await control.deleteAccountData();

    expect(capturedRequest.method, 'DELETE');
    expect(capturedRequest.url.path, '/api/v1/auth/account-data');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), isEmpty);
  });

  test('서버 삭제 실패 시 로컬 캐시를 보존한다', () async {
    SharedPreferences.setMockInitialValues({'saved-setting': 'value'});
    final control = ManageAccount(
      client: MockClient((_) async => http.Response('failure', 500)),
    );

    await expectLater(control.deleteAccountData(), throwsStateError);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('saved-setting'), 'value');
  });
}
