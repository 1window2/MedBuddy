import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_today_medication_info_control.dart';

void main() {
  test('requestTodayMedicationInfo decodes schedules from summary payload',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today/info');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters['role'], 'patient');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'medication_count': 1,
            'total_dose_count': 3,
            'completed_dose_count': 1,
            'remaining_dose_count': 2,
            'progress_ratio': 1 / 3,
            'schedules': [
              {
                'medication_id': '7',
                'drug_name': 'test-tablet',
                'daily_frequency': '3 times',
                'slot_statuses': {
                  'morning': true,
                  'lunch': false,
                  'evening': false,
                },
                'patient_hash': 'patient-a',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = CheckTodayMedicationInfo(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final schedules = await control.requestTodayMedicationInfo();

    expect(schedules, hasLength(1));
    expect(schedules.first.patientID, 'patient-a');
    expect(schedules.first.medicationID, '7');
    expect(schedules.first.isSlotCompleted('morning'), isTrue);
  });

  test('requestTodayMedicationInfo can request guardian linked scope',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.url.path, '/schedule/today/info');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'medication_count': 0,
            'total_dose_count': 0,
            'completed_dose_count': 0,
            'remaining_dose_count': 0,
            'progress_ratio': 0,
            'schedules': [],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = CheckTodayMedicationInfo(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      userHash: 'guardian-a',
      role: 'guardian',
      client: client,
    );

    final schedules = await control.requestTodayMedicationInfo();

    expect(schedules, isEmpty);
  });
}
