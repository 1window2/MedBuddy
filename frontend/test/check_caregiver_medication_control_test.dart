// File Name: check_caregiver_medication_control_test.dart
// Role: Regression coverage for caregiver-scoped aggregate and selected-patient medication requests.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';

// 함수이름: main
// 함수역할:
// - 보호자 범위의 통합 및 선택 환자 복약 조회 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 보호자 통합 조회에서 여러 환자의 별칭과 일정을 한 번에 해석한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('보호자 통합 조회에서 여러 환자의 별칭과 일정을 한 번에 해석한다', () async {
    var requestCount = 0;
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 통합 조회의 GET 경로와 보호자 범위를 검사하고 별칭·알림·일정을 포함한 두 환자 데이터를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 통합 감시 데이터의 HTTP 200 응답.
    final client = MockClient((request) async {
      requestCount += 1;
      expect(request.method, 'GET');
      expect(request.url.path, '/caregiver/monitoring');
      expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'caregiver_hash': 'caregiver-a',
            'patients': [
              {
                'link': {
                  'id': 1,
                  'patient_hash': 'patient-a',
                  'caregiver_hash': 'caregiver-a',
                  'patient_alias': '어머니',
                  'linked': true,
                },
                'notification_settings': [
                  {
                    'patient_hash': 'patient-a',
                    'caregiver_hash': 'caregiver-a',
                    'slot_key': 'morning',
                    'notification_type': 'dose_completed',
                  },
                ],
                'today_medication_info': {
                  'patient_hash': 'patient-a',
                  'schedules': [
                    {
                      'medication_id': 'medication-1',
                      'medication_name': '테스트정',
                      'daily_frequency': 1,
                      'slot_statuses': {'morning': false},
                    },
                  ],
                },
              },
              {
                'link': {
                  'id': 2,
                  'patient_hash': 'patient-b',
                  'caregiver_hash': 'caregiver-a',
                  'patient_alias': '아버지',
                  'linked': true,
                },
                'notification_settings': const [],
                'today_medication_info': {
                  'patient_hash': 'patient-b',
                  'schedules': const [],
                },
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = CheckCaregiverMedication(
      baseUrl: 'http://medbuddy.test',
      caregiverHash: 'caregiver-a',
      client: client,
    );

    final snapshots = await control.requestMonitoringSnapshot();

    expect(requestCount, 1);
    expect(snapshots, hasLength(2));
    expect(snapshots.first.patientAlias, '어머니');
    expect(snapshots.first.notificationSettings['morning']?.slotKey, 'morning');
    expect(snapshots.first.schedules.single.medicationName, '테스트정');
    expect(snapshots.last.patientAlias, '아버지');
    expect(snapshots.last.schedules, isEmpty);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 선택한 연동 환자만 보호자 식별자 범위로 조회하고 저장 약과 오늘 일정을 해석하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requests one explicitly selected linked patient as a caregiver',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert the selected-patient route and caregiver scope, then provide saved medication and dose
      //   data.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing patient-b medication information.
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/caregiver/medications/patient-b');
        expect(request.url.queryParameters['caregiver_hash'], 'caregiver-a');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'caregiver_hash': 'caregiver-a',
              'patient_hash': 'patient-b',
              'saved_medications': [
                {
                  'id': 7,
                  'patient_hash': 'patient-b',
                  'item_name': 'Test tablet',
                  'efficacy': 'Effect',
                  'use_method': 'Use method',
                  'warning_message': 'Caution',
                },
              ],
              'today_medication_info': {
                'patient_hash': 'patient-b',
                'schedules': [
                  {
                    'medication_id': '7',
                    'medication_name': 'Test tablet',
                    'daily_frequency': 1,
                    'slot_statuses': {'morning': false},
                  },
                ],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckCaregiverMedication(
        baseUrl: 'http://medbuddy.test',
        caregiverHash: 'caregiver-a',
        client: client,
      );

      final result = await control.requestPatientMedicationInfo(
        patientHash: 'patient-b',
      );

      expect(result.caregiverHash, 'caregiver-a');
      expect(result.patientHash, 'patient-b');
      expect(result.savedMedications.single.itemName, 'Test tablet');
      expect(
        result.todayMedicationScheduleList.single.medicationName,
        'Test tablet',
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: surfaces a rejected caregiver-patient selection.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('surfaces a rejected caregiver-patient selection', () async {
    final client = MockClient(
      // Function Name: MockClient callback
      // Description:
      // - Reject access to a patient who is not linked to the requesting caregiver.
      // Parameters:
      // - _ (http.Request): Unused intercepted HTTP request.
      // Returns:
      // - HTTP 403 with the unlinked-patient detail.
      (_) async => http.Response(
        jsonEncode({'detail': 'Patient is not linked to this caregiver.'}),
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final control = CheckCaregiverMedication(
      baseUrl: 'http://medbuddy.test',
      caregiverHash: 'caregiver-a',
      client: client,
    );

    expect(
      // Function Name: expect callback
      // Description:
      // - Request an unlinked patient's medication information so the access error reaches the matcher.
      // Parameters:
      // - None.
      // Returns:
      // - A failed medication-info Future for patient-x.
      () => control.requestPatientMedicationInfo(patientHash: 'patient-x'),
      throwsA(
        isA<StateError>().having(
          // Function Name: having callback
          // Description:
          // - Select the user-facing exception message for a focused matcher assertion.
          // Parameters:
          // - error (Object): Typed exception inspected by the matcher.
          // Returns:
          // - The exception's message value.
          (error) => error.message,
          'message',
          contains('Patient is not linked'),
        ),
      ),
    );
  });
}
