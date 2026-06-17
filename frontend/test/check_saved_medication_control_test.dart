import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';

void main() {
  test('saveMedicationDetail sends patient hash and schedule fields', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost/save');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true}', 200);
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final success = await control.saveMedicationDetail(
      const MedicationDetail(
        itemName: 'test-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
      medicationSchedule: const MedicationSchedule(
        medicationName: 'test-tablet',
        dosage: '1 tablet',
        intakeTime: '3 times',
        medicationTime: 7,
      ),
    );

    expect(success, isTrue);
    expect(requestBody['patient_hash'], 'patient-a');
    expect(requestBody['dosage_per_time'], '1 tablet');
    expect(requestBody['daily_frequency'], '3 times');
    expect(requestBody['total_days'], '7\uC77C');
  });

  test('requestSavedMedicationInfo scopes list request by patient hash',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/list');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'id': 1,
              'patient_hash': 'patient-a',
              'item_name': 'test-tablet',
              'efficacy': 'effect',
              'use_method': 'usage',
              'warning_message': 'warning',
              'dosage_per_time': '1 tablet',
              'daily_frequency': '3 times',
              'total_days': '7 days',
              'ai_guide': 'guide',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final medications = await control.requestSavedMedicationInfo();

    expect(medications, hasLength(1));
    expect(medications.first.patientHash, 'patient-a');
    expect(medications.first.dosagePerTime, '1 tablet');
  });

  test('requestDelete scopes delete request by patient hash', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/delete/3');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      return http.Response('{"success":true}', 200);
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final success = await control.requestDelete(3);

    expect(success, isTrue);
  });

  test('default patient hash remains available before UC-6 linking', () {
    expect(PatientHash.defaultPatientHash, 'local_patient');
  });
}
