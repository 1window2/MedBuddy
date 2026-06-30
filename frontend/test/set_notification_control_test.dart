// File Name: set_notification_control_test.dart
// Role: Verifies medication alarm API requests and decoding.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';

void main() {
  test('requestMedicationAlarm scopes list request and decodes settings',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/notification/settings');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters['role'], 'patient');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'patient_hash': 'patient-a',
              'slot_key': 'morning',
              'hour': 8,
              'minute': 30,
              'is_enabled': true,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetNotification(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final settings = await control.requestMedicationAlarm();

    expect(settings, hasLength(1));
    expect(settings.first.slotKey, 'morning');
    expect(settings.first.hour, 8);
    expect(settings.first.minute, 30);
    expect(settings.first.isEnabled, isTrue);
  });

  test('setMedicationAlarm sends selected alarm time', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/notification/settings/lunch');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'slot_key': 'lunch',
            'hour': 13,
            'minute': 15,
            'is_enabled': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetNotification(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final setting = await control.setMedicationAlarm(
      slotKey: 'lunch',
      hour: 13,
      minute: 15,
    );

    expect(requestBody['hour'], 13);
    expect(requestBody['minute'], 15);
    expect(setting.slotKey, 'lunch');
    expect(setting.timeLabel, '13:15');
    expect(setting.isEnabled, isTrue);
  });

  test('disableAlarmSetting sends selected guardian scope', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/notification/settings/evening/disable');
      expect(request.url.queryParameters['patient_hash'], 'patient-b');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-b',
            'slot_key': 'evening',
            'hour': 18,
            'minute': 0,
            'is_enabled': false,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetNotification(
      baseUrl: 'http://localhost',
      patientHash: 'patient-b',
      userHash: 'guardian-a',
      role: 'guardian',
      client: client,
    );

    final setting = await control.disableAlarmSetting('evening');

    expect(setting.slotKey, 'evening');
    expect(setting.isEnabled, isFalse);
  });

  test('setMedicationAlarm rejects unsupported slot keys before request',
      () async {
    var requestCalled = false;
    final client = MockClient((http.Request request) async {
      requestCalled = true;
      return http.Response('{}', 500);
    });
    final control = SetNotification(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    await expectLater(
      control.setMedicationAlarm(
        slotKey: '../bad',
        hour: 9,
        minute: 0,
      ),
      throwsA(isA<StateError>()),
    );
    expect(requestCalled, isFalse);
  });
}
