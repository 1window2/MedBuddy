// File Name: medbuddy_view_model_schedule_test.dart
// Role: Verifies schedule status updates are routed through the ViewModel.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

void main() {
  test('dose status update uses backend schedule status flow', () async {
    var patchCalled = false;
    final client = MockClient((http.Request request) async {
      if (request.method == 'GET') {
        expect(request.url.path, '/schedule/today');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'medication_id': '7',
                'drug_name': 'test-tablet',
                'dosage_per_time': '1 tablet',
                'daily_frequency': '3 times',
                'total_days': '7 days',
                'medication_status': false,
                'patient_hash': 'patient-a',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      expect(request.method, 'PATCH');
      expect(request.url.path, '/schedule/7/status');
      patchCalled = true;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'medication_id': '7',
            'drug_name': 'test-tablet',
            'dosage_per_time': '1 tablet',
            'daily_frequency': '3 times',
            'total_days': '7 days',
            'medication_status': true,
            'patient_hash': 'patient-a',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final viewModel = MedBuddyViewModel(
      checkSchedule: CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
    );

    await viewModel.fetchTodayMedicationSchedule();
    final schedule = viewModel.todayMedicationScheduleList.first;

    final success = await viewModel.requestMedicationDoseStatusUpdate(
      'morning',
      schedule,
      true,
    );

    expect(success, isTrue);
    expect(patchCalled, isTrue);
    expect(
        viewModel.todayMedicationScheduleList.first.medicationStatus, isTrue);
  });
}
