import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';

void main() {
  test('보호자 통합 조회에서 여러 환자의 별칭과 일정을 한 번에 해석한다', () async {
    var requestCount = 0;
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

  test(
    'requests one explicitly selected linked patient as a caregiver',
    () async {
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

  test('surfaces a rejected caregiver-patient selection', () async {
    final client = MockClient(
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
      () => control.requestPatientMedicationInfo(patientHash: 'patient-x'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Patient is not linked'),
        ),
      ),
    );
  });
}
