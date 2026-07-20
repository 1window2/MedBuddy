// 파일명: set_caregiver_notification_control_test.dart
// 역할: 보호자 알림 설정 API 요청과 응답 decoding을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_caregiver_notification_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';

void main() {
  test(
      'requestCaregiverNotificationSetting scopes lookup by caregiver and patient',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/caregiver-notification/settings/patient-a');
      expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'setting_id': 1,
            'caregiver_hash': 'caregiver-a',
            'patient_hash': 'patient-a',
            'is_enabled': false,
            'alert_option': 'disable',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetCaregiverNotification(
      baseUrl: 'http://localhost',
      caregiverHash: 'caregiver-a',
      client: client,
    );

    final setting = await control.requestCaregiverNotificationSetting(
      patientHash: 'patient-a',
    );

    expect(setting.notificationId, 1);
    expect(setting.caregiverHash, 'caregiver-a');
    expect(setting.patientHash, 'patient-a');
    expect(setting.notificationEnabled, isFalse);
    expect(setting.notificationType, 'disable');
  });

  test('saveCaregiverNotificationSetting sends enable option payload',
      () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/caregiver-notification/settings/patient-a');
      expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'setting_id': 1,
            'caregiver_hash': 'caregiver-a',
            'patient_hash': 'patient-a',
            'is_enabled': true,
            'alert_option': 'enable',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetCaregiverNotification(
      baseUrl: 'http://localhost',
      caregiverHash: 'caregiver-a',
      client: client,
    );

    final setting = await control.saveCaregiverNotificationSetting(
      patientHash: 'patient-a',
      enabled: true,
    );

    expect(requestBody['notification_enabled'], isTrue);
    expect(requestBody['notification_type'], 'enable');
    expect(setting.notificationEnabled, isTrue);
    expect(setting.notificationType, 'enable');
  });

  test('CaregiverNotification preserves UML-compatible payload fields', () {
    final setting = const CaregiverNotification(
      notificationId: 3,
      caregiverHash: 'caregiver-a',
      patientHash: 'patient-a',
    ).updateNotificationSetting(true);

    final payload = setting.toJson();

    expect(payload['notification_id'], 3);
    expect(payload['caregiver_hash'], 'caregiver-a');
    expect(payload['patient_hash'], 'patient-a');
    expect(payload['notification_enabled'], isTrue);
    expect(payload['notification_type'], 'enable');
  });

  test('CaregiverNotification can derive enabled state from alert option', () {
    final setting = CaregiverNotification.fromJson({
      'guardian_hash': 'legacy-guardian-a',
      'patient_hash': 'patient-a',
      'alert_option': 'enable',
    });

    expect(setting.notificationEnabled, isTrue);
    expect(setting.notificationType, 'enable');
    expect(setting.caregiverHash, 'legacy-guardian-a');
  });
}
