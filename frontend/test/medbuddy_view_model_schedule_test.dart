// File Name: medbuddy_view_model_schedule_test.dart
// Role: Verifies schedule status updates are routed through the ViewModel.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/check_today_medication_info_control.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

void main() {
  test('dose status update uses slot-scoped backend status flow', () async {
    var patchCalled = false;
    late Map<String, dynamic> patchBody;
    final client = MockClient((http.Request request) async {
      if (request.method == 'GET') {
        expect(request.url.path, '/schedule/today/info');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'patient_hash': 'patient-a',
              'medication_count': 1,
              'total_dose_count': 3,
              'completed_dose_count': 0,
              'remaining_dose_count': 3,
              'progress_ratio': 0,
              'schedules': [
                {
                  'medication_id': '7',
                  'drug_name': 'test-tablet',
                  'dosage_per_time': '1 tablet',
                  'daily_frequency': '3 times',
                  'total_days': '7 days',
                  'medication_status': false,
                  'slot_statuses': {
                    'morning': false,
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
      }

      expect(request.method, 'PATCH');
      expect(request.url.path, '/schedule/7/status');
      patchBody = jsonDecode(request.body) as Map<String, dynamic>;
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
            'medication_status': false,
            'slot_statuses': {
              'morning': true,
              'lunch': false,
              'evening': false,
            },
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
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
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
    expect(patchBody['slot_key'], 'morning');
    expect(
        viewModel.todayMedicationScheduleList.first.medicationStatus, isFalse);
    expect(
      viewModel.isMedicationDoseCompleted(
        'morning',
        viewModel.todayMedicationScheduleList.first,
      ),
      isTrue,
    );
    expect(
      viewModel.isMedicationDoseCompleted(
        'lunch',
        viewModel.todayMedicationScheduleList.first,
      ),
      isFalse,
    );
    expect(viewModel.todayMedicationProgress.completedCount, 1);
    expect(viewModel.todayMedicationProgress.totalCount, 3);
  });

  test('deleting saved medication refreshes today schedule cache', () async {
    final savedMedicationClient = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/delete/3');
      return http.Response('{"success":true}', 200);
    });
    var scheduleFetchCount = 0;
    final scheduleClient = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today/info');
      scheduleFetchCount += 1;
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
            'schedules': <Map<String, dynamic>>[],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: savedMedicationClient,
      ),
      checkSchedule: CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: scheduleClient,
      ),
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: scheduleClient,
      ),
    );
    addTearDown(viewModel.dispose);

    final success = await viewModel.requestDeleteSavedMedication(3);

    expect(success, isTrue);
    expect(scheduleFetchCount, 1);
    expect(viewModel.todayMedicationScheduleList, isEmpty);
  });

  test(
      'today progress is derived from schedule slots, not stale summary counts',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today/info');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'medication_count': 99,
            'total_dose_count': 0,
            'completed_dose_count': 0,
            'remaining_dose_count': 0,
            'progress_ratio': 0,
            'schedules': [
              {
                'medication_id': '7',
                'drug_name': 'test-tablet',
                'daily_frequency': '2 times',
                'slot_statuses': {
                  'morning': true,
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
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();

    expect(viewModel.todayMedicationProgress.totalCount, 2);
    expect(viewModel.todayMedicationProgress.completedCount, 1);
  });

  test('today progress parses Korean daily frequency labels', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today/info');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'patient_hash': 'patient-a',
            'medication_count': 1,
            'total_dose_count': 0,
            'completed_dose_count': 0,
            'remaining_dose_count': 0,
            'progress_ratio': 0,
            'schedules': [
              {
                'medication_id': '7',
                'drug_name': 'test-tablet',
                'daily_frequency': '1일 3회',
                'patient_hash': 'patient-a',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();

    expect(viewModel.todayMedicationProgress.totalCount, 3);
    expect(viewModel.todayMedicationProgress.completedCount, 0);
  });
}
