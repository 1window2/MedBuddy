import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_guardian_medication_control.dart';

void main() {
  test('requestGuardianMedication decodes guardian medication payload',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/guardian/medications/patient-a');
      expect(request.url.queryParameters['guardian_hash'], 'guardian-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'guardian_hash': 'guardian-a',
            'patient_hash': 'patient-a',
            'saved_medications': [
              {
                'id': 3,
                'patient_hash': 'patient-a',
                'item_name': 'test-tablet',
                'dosage_per_time': '1 tablet',
                'daily_frequency': '2 times',
                'total_days': '5 days',
              },
            ],
            'today_medication_info': {
              'patient_hash': 'patient-a',
              'medication_count': 1,
              'total_dose_count': 2,
              'completed_dose_count': 0,
              'remaining_dose_count': 2,
              'progress_ratio': 0,
              'schedules': [
                {
                  'medication_id': '3',
                  'drug_name': 'test-tablet',
                  'daily_frequency': '2 times',
                  'patient_hash': 'patient-a',
                },
              ],
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = SetGuardianMedication(
      baseUrl: 'http://localhost',
      guardianHash: 'guardian-a',
      client: client,
    );

    final info = await control.requestGuardianMedication(
      patientHash: 'patient-a',
    );

    expect(info.guardianHash, 'guardian-a');
    expect(info.patientHash, 'patient-a');
    expect(info.savedMedications, hasLength(1));
    expect(info.savedMedications.first.itemName, 'test-tablet');
    expect(info.todayMedicationInfo.totalDoseCount, 2);
    expect(info.todayMedicationInfo.schedules, hasLength(1));
  });
}
