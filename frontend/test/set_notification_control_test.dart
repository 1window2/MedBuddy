// File Name: set_notification_control_test.dart
// Role: Verifies medication alarm API requests and decoding.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';

void main() {
  test('requestMedicationAlarm scopes list request and decodes settings',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/notification/settings');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters.containsKey('role'), isFalse);
      expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
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

  test('saveNotificationSetting sends selected alarm time', () async {
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

    final setting = await control.saveNotificationSetting(
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

  test('disableAlarmSetting sends selected patient scope', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/notification/settings/evening/disable');
      expect(request.url.queryParameters['patient_hash'], 'patient-b');
      expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
      expect(request.url.queryParameters.containsKey('role'), isFalse);
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
      client: client,
    );

    final setting = await control.disableAlarmSetting('evening');

    expect(setting.slotKey, 'evening');
    expect(setting.isEnabled, isFalse);
  });

  test('saveNotificationSetting rejects unsupported slot keys before request',
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
      control.saveNotificationSetting(
        slotKey: '../bad',
        hour: 9,
        minute: 0,
      ),
      throwsA(isA<StateError>()),
    );
    expect(requestCalled, isFalse);
  });

  test('registerNotification delegates platform registration through control',
      () async {
    Map<String, Object?>? registration;
    final control = SetNotification(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: MockClient((_) async => http.Response('{}', 500)),
      notificationRegistrar: ({
        required id,
        required slotKey,
        required slotTitle,
        required hour,
        required minute,
        required medicationNames,
        language = 'ko',
      }) async {
        registration = {
          'id': id,
          'slotKey': slotKey,
          'slotTitle': slotTitle,
          'hour': hour,
          'minute': minute,
          'medicationNames': medicationNames,
          'language': language,
        };
      },
    );

    await control.registerNotification(
      id: 17,
      slotKey: 'morning',
      slotTitle: 'Morning',
      hour: 8,
      minute: 25,
      medicationNames: const ['Medicine A'],
      language: 'en',
    );

    expect(registration, {
      'id': 17,
      'slotKey': 'morning',
      'slotTitle': 'Morning',
      'hour': 8,
      'minute': 25,
      'medicationNames': const ['Medicine A'],
      'language': 'en',
    });
  });

  test('MedicationAlarm notification ids are scoped by patient hash', () {
    const patientASetting = MedicationAlarm(
      patientHash: 'patient-a',
      slotKey: 'morning',
      hour: 8,
      minute: 0,
      enabled: true,
    );
    const patientBSetting = MedicationAlarm(
      patientHash: 'patient-b',
      slotKey: 'morning',
      hour: 8,
      minute: 0,
      enabled: true,
    );

    expect(patientASetting.notificationId, isNot(1001));
    expect(patientBSetting.notificationId, isNot(1001));
    expect(
        patientASetting.notificationId, isNot(patientBSetting.notificationId));
    expect(patientASetting.legacyNotificationId, 1001);
  });
}
