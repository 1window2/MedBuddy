// File Name: set_caregiver_notification_control_test.dart
// Role: Regression coverage for caregiver notification scope, slot settings, and payload
//   compatibility.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_caregiver_notification_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';

// 함수이름: main
// 함수역할:
// - 보호자 알림 범위, 시간대 설정과 데이터 호환성 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 보호자 알림 조회가 보호자·환자 식별자와 시간대 범위를 전달하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestCaregiverNotificationSetting scopes lookup by caregiver and patient',
    () async {
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 보호자·환자·아침 시간대 조회 범위를 검사하고 비활성 설정을 제공한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
      // 반환값:
      // - 보호자 알림 설정의 HTTP 200 응답.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/caregiver-notification/settings/patient-a');
        expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
        expect(request.url.queryParameters['slot_key'], 'morning');
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
      expect(setting.notificationType, 'disabled');
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 보호자 알림 저장에 활성 상태와 알림 방식을 전달하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'saveCaregiverNotificationSetting sends enable option payload',
    () async {
      late Map<String, dynamic> requestBody;
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 보호자·환자·저녁 시간대 저장 범위와 본문을 검사하고 완료 알림 활성 설정을 제공한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
      // 반환값:
      // - 활성 복용 완료 알림의 HTTP 200 응답.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/caregiver-notification/settings/patient-a');
        expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
        expect(request.url.queryParameters['slot_key'], 'evening');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'setting_id': 1,
              'caregiver_hash': 'caregiver-a',
              'patient_hash': 'patient-a',
              'is_enabled': true,
              'alert_option': 'dose_completed',
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
        slotKey: 'evening',
        mode: CaregiverNotificationMode.doseCompleted,
      );

      expect(requestBody['notification_enabled'], isTrue);
      expect(requestBody['notification_type'], 'dose_completed');
      expect(setting.notificationEnabled, isTrue);
      expect(setting.notificationType, 'dose_completed');
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 모든 시간대 알림 설정을 한 번의 요청으로 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('모든 시간대 알림 설정을 한 번의 요청으로 조회한다', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 전체 시간대 조회 경로와 보호자 범위를 검사하고 아침 활성·저녁 비활성 설정을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 두 시간대 설정 목록의 HTTP 200 응답.
    final client = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/caregiver-notification/settings/patient-a/slots',
      );
      expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'caregiver_hash': 'caregiver-a',
              'patient_hash': 'patient-a',
              'slot_key': 'morning',
              'notification_type': 'dose_completed',
            },
            {
              'caregiver_hash': 'caregiver-a',
              'patient_hash': 'patient-a',
              'slot_key': 'evening',
              'notification_type': 'disabled',
            },
          ],
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

    final settings = await control.requestCaregiverNotificationSettings(
      patientHash: 'patient-a',
    );

    expect(settings['morning']?.notificationEnabled, isTrue);
    expect(settings['evening']?.notificationEnabled, isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 보호자 알림 모델이 UML 호환 필드와 전송 형식을 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('CaregiverNotification preserves UML-compatible payload fields', () {
    final setting = const CaregiverNotification(
      notificationId: 3,
      caregiverHash: 'caregiver-a',
      patientHash: 'patient-a',
      slotKey: 'bedtime',
    ).updateNotificationSetting(CaregiverNotificationMode.doseCompleted);

    final payload = setting.toJson();

    expect(payload['notification_id'], 3);
    expect(payload['caregiver_hash'], 'caregiver-a');
    expect(payload['patient_hash'], 'patient-a');
    expect(payload['slot_key'], 'bedtime');
    expect(payload['notification_enabled'], isTrue);
    expect(payload['notification_type'], 'dose_completed');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 알림 방식에서 보호자 알림 활성 상태를 유도하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('CaregiverNotification can derive enabled state from alert option', () {
    final setting = CaregiverNotification.fromJson({
      'guardian_hash': 'legacy-guardian-a',
      'patient_hash': 'patient-a',
      'alert_option': 'enable',
    });

    expect(setting.notificationEnabled, isTrue);
    expect(setting.notificationType, 'dose_completed');
    expect(setting.caregiverHash, 'legacy-guardian-a');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 미복용 알림의 마감 시각을 모델 변환 후에도 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('CaregiverNotification preserves missed-dose deadline', () {
    final setting = CaregiverNotification.fromJson({
      'caregiver_hash': 'caregiver-a',
      'patient_hash': 'patient-a',
      'notification_type': 'missed_deadline',
      'deadline_hour': 21,
      'deadline_minute': 30,
    });

    expect(setting.mode, CaregiverNotificationMode.missedDeadline);
    expect(setting.deadlineHour, 21);
    expect(setting.deadlineMinute, 30);
    expect(setting.notificationEnabled, isTrue);
  });
}
