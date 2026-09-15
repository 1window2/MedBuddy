// File Name: set_notification_control_test.dart
// Role: Verifies medication alarm API requests and decoding.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';

// Function Name: main
// Description:
// - Register regression cases for medication alarm scope, time settings, platform registration, and
//   notification IDs.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 환자 범위로 복약 알림 목록을 요청하고 시각과 활성 상태를 해석하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestMedicationAlarm scopes list request and decodes settings',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert patient-scoped alarm lookup without legacy parameters and provide enabled morning settings.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with an enabled 08:30 morning alarm.
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
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: saveNotificationSetting sends selected alarm time.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('saveNotificationSetting sends selected alarm time', () async {
    late Map<String, dynamic> requestBody;
    // Function Name: MockClient callback
    // Description:
    // - Capture lunch-alarm PUT settings and return the selected enabled 13:15 time.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing the saved lunch alarm.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: disableAlarmSetting sends selected patient scope.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('disableAlarmSetting sends selected patient scope', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert patient-b's evening-disable PATCH and retain its time while disabling the alarm.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with the disabled 18:00 evening alarm.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 지원하지 않는 시간대는 HTTP 요청 전에 거부하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'saveNotificationSetting rejects unsupported slot keys before request',
    () async {
      var requestCalled = false;
      // Function Name: MockClient callback
      // Description:
      // - Complete the mocked HTTP request with status 500 and an empty JSON object without network access.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
      //   consumed by this fixture.
      // Returns:
      // - Future<http.Response> with status 500.
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
        control.saveNotificationSetting(slotKey: '../bad', hour: 9, minute: 0),
        throwsA(isA<StateError>()),
      );
      expect(requestCalled, isFalse);
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: registerNotification delegates platform registration through control.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'registerNotification delegates platform registration through control',
    () async {
      Map<String, Object?>? registration;
      final control = SetNotification(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        // Function Name: MockClient callback
        // Description:
        // - Complete the mocked HTTP request with status 500 and an empty JSON object without network access.
        // Parameters:
        // - _ (http.Request): Unused intercepted HTTP request.
        // Returns:
        // - Future<http.Response> with status 500.
        client: MockClient((_) async => http.Response('{}', 500)),
        notificationRegistrar:
            // Function Name: notificationRegistrar callback
            // Description:
            // - Capture every platform-registration argument, including per-date medication names and language.
            // Parameters:
            // - id (int): Identifier of the medication, message, or notification fixture.
            // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
            // - slotTitle (String): Localized user-visible name of the dose slot.
            // - hour (int): Selected local alarm hour in 24-hour time.
            // - minute (int): Selected minute component of the local alarm time.
            // - medicationNames (List<String>): Medication names eligible for this reminder.
            // - activeDates (List<DateTime>): Dates on which this dose is active.
            // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
            // - language (String): Language code used for labels or notification content.
            // Returns:
            // - Future<void>; records the delegated registration payload.
            ({
              required id,
              required slotKey,
              required slotTitle,
              required hour,
              required minute,
              required medicationNames,
              required activeDates,
              medicationNamesByDate = const <String, List<String>>{},
              language = 'ko',
            }) async {
              registration = {
                'id': id,
                'slotKey': slotKey,
                'slotTitle': slotTitle,
                'hour': hour,
                'minute': minute,
                'medicationNames': medicationNames,
                'activeDates': activeDates,
                'medicationNamesByDate': medicationNamesByDate,
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
        activeDates: [DateTime(2026, 8, 17)],
        language: 'en',
      );

      expect(registration, {
        'id': 17,
        'slotKey': 'morning',
        'slotTitle': 'Morning',
        'hour': 8,
        'minute': 25,
        'medicationNames': const ['Medicine A'],
        'activeDates': [DateTime(2026, 8, 17)],
        'medicationNamesByDate': const <String, List<String>>{},
        'language': 'en',
      });
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 환자 식별자가 다른 경우 로컬 알림 식별자가 충돌하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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
      patientASetting.notificationId,
      isNot(patientBSetting.notificationId),
    );
    expect(patientASetting.legacyNotificationId, 1001);
  });
}
