// 파일명: set_guardian_alert_setting_control_test.dart
// 역할: 보호자 알림 설정 API 요청과 응답 decoding을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_guardian_alert_setting_control.dart';
import 'package:medbuddy_frontend/entities/guardian_alert_setting_entity.dart';

void main() {
  test('requestGuardianAlertSetting scopes lookup by guardian and patient',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/guardian-alert/settings/patient-a');
      expect(request.url.queryParameters['guardian_hash'], 'guardian-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'setting_id': 1,
            'guardian_hash': 'guardian-a',
            'patient_hash': 'patient-a',
            'is_enabled': false,
            'alert_option': 'disable',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetGuardianAlertSetting(
      baseUrl: 'http://localhost',
      guardianHash: 'guardian-a',
      client: client,
    );

    final setting = await control.requestGuardianAlertSetting(
      patientHash: 'patient-a',
    );

    expect(setting.settingID, 1);
    expect(setting.guardianID, 'guardian-a');
    expect(setting.patientID, 'patient-a');
    expect(setting.enabled, isFalse);
    expect(setting.alertOption, 'disable');
  });

  test('updateGuardianAlertSetting sends enable option payload', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/guardian-alert/settings/patient-a');
      expect(request.url.queryParameters['guardian_hash'], 'guardian-a');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'setting_id': 1,
            'guardian_hash': 'guardian-a',
            'patient_hash': 'patient-a',
            'is_enabled': true,
            'alert_option': 'enable',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetGuardianAlertSetting(
      baseUrl: 'http://localhost',
      guardianHash: 'guardian-a',
      client: client,
    );

    final setting = await control.updateGuardianAlertSetting(
      patientHash: 'patient-a',
      enabled: true,
    );

    expect(requestBody['is_enabled'], isTrue);
    expect(requestBody['alert_option'], 'enable');
    expect(setting.enabled, isTrue);
    expect(setting.alertOption, 'enable');
  });

  test('GuardianAlertSetting preserves UML-compatible payload fields', () {
    final setting = const GuardianAlertSetting(
      settingID: 3,
      guardianID: 'guardian-a',
      patientID: 'patient-a',
    ).enable();

    final payload = setting.saveGuardianAlertSetting();

    expect(payload['setting_id'], 3);
    expect(payload['guardian_hash'], 'guardian-a');
    expect(payload['patient_hash'], 'patient-a');
    expect(payload['is_enabled'], isTrue);
    expect(payload['alert_option'], 'enable');
  });

  test('GuardianAlertSetting can derive enabled state from alert option', () {
    final setting = GuardianAlertSetting.fromJson({
      'guardian_hash': 'guardian-a',
      'patient_hash': 'patient-a',
      'alert_option': 'enable',
    });

    expect(setting.enabled, isTrue);
    expect(setting.alertOption, 'enable');
  });
}
