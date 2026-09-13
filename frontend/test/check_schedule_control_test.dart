// File Name: check_schedule_control_test.dart
// Role: Regression coverage for schedule queries and patient/slot-scoped completion updates.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';

// Function Name: main
// Description:
// - Register regression cases for schedule queries and patient/slot-scoped completion updates.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: requestTodayMedicationSchedule scopes request by patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestTodayMedicationSchedule scopes request by patient hash',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert today's patient-scoped schedule request and provide one tablet with mixed slot completion.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing the three-dose schedule fixture.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/schedule/today');
        expect(request.url.queryParameters['patient_hash'], 'patient-a');
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
                'slot_statuses': {
                  'morning': true,
                  'lunch': false,
                  'evening': false,
                },
                'patient_hash': 'patient-a',
                'created_date': '2026-06-17',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final schedules = await control.requestTodayMedicationSchedule();

      expect(schedules, hasLength(1));
      expect(schedules.first.medicationID, '7');
      expect(schedules.first.medicationName, 'test-tablet');
      expect(schedules.first.dosage, '1 tablet');
      expect(schedules.first.medicationTime, 7);
      expect(schedules.first.medicationStatus, isFalse);
      expect(schedules.first.isSlotCompleted('morning'), isTrue);
      expect(schedules.first.isSlotCompleted('lunch'), isFalse);
      expect(schedules.first.patientID, 'patient-a');
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestMedicationScheduleWindow requests future reminder courses.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestMedicationScheduleWindow requests future reminder courses',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert the fourteen-day schedule window and return a future three-day medication course.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing the future course.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/schedule/window');
        expect(request.url.queryParameters['patient_hash'], 'patient-a');
        expect(request.url.queryParameters['days'], '14');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'medication_id': '11',
                'drug_name': 'future-tablet',
                'prescription_date': '2026-08-10',
                'total_days': '3 days',
                'schedule_slot_keys': ['morning'],
                'patient_hash': 'patient-a',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final schedules = await control.requestMedicationScheduleWindow();

      expect(schedules, hasLength(1));
      expect(schedules.single.medicationID, '11');
      expect(schedules.single.prescriptionDate, DateTime(2026, 8, 10));
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: updateMedicationStatus sends scoped status patch.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('updateMedicationStatus sends scoped status patch', () async {
    late Map<String, dynamic> requestBody;
    // Function Name: MockClient callback
    // Description:
    // - Capture the patient-scoped medication status PATCH and return its completed state.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with the updated single schedule.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/schedule/7/status');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters.containsKey('role'), isFalse);
      expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
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
    final control = CheckSchedule(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final updatedSchedule = await control.updateMedicationStatus('7', true);

    expect(requestBody['medication_status'], isTrue);
    expect(updatedSchedule.medicationID, '7');
    expect(updatedSchedule.medicationStatus, isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: updateMedicationStatus sends slot key for dose patch.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('updateMedicationStatus sends slot key for dose patch', () async {
    late Map<String, dynamic> requestBody;
    // Function Name: MockClient callback
    // Description:
    // - Capture a dose-specific PATCH and return morning completion with other slots still pending.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with mixed per-slot completion states.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/schedule/7/status');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
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
    final control = CheckSchedule(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final updatedSchedule = await control.updateMedicationStatus(
      '7',
      true,
      slotKey: 'morning',
    );

    expect(requestBody['medication_status'], isTrue);
    expect(requestBody['slot_key'], 'morning');
    expect(updatedSchedule.medicationStatus, isFalse);
    expect(updatedSchedule.isSlotCompleted('morning'), isTrue);
    expect(updatedSchedule.isSlotCompleted('lunch'), isFalse);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: updateMedicationSlotStatus sends one scoped whole-slot patch.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'updateMedicationSlotStatus sends one scoped whole-slot patch',
    () async {
      late Map<String, dynamic> requestBody;
      // Function Name: MockClient callback
      // Description:
      // - Assert one scoped whole-morning PATCH and return both medications marked complete for that slot.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing two updated schedules.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/schedule/slot/morning/status');
        expect(request.url.queryParameters['patient_hash'], 'patient-a');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'medication_id': '7',
                'drug_name': 'first-tablet',
                'daily_frequency': '3 times',
                'slot_statuses': {
                  'morning': true,
                  'lunch': false,
                  'evening': false,
                },
                'patient_hash': 'patient-a',
              },
              {
                'medication_id': '8',
                'drug_name': 'second-tablet',
                'schedule_slot_keys': ['morning'],
                'slot_statuses': {'morning': true},
                'patient_hash': 'patient-a',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final updatedSchedules = await control.updateMedicationSlotStatus(
        'Morning',
        true,
        expectedScheduleDate: '2026-09-10',
      );
      expect(requestBody, {
        'medication_status': true,
        'expected_schedule_date': '2026-09-10',
      });
      // Function Name: map callback
      // Description:
      // - Extract the schedule medication ID for the collection assertion.
      // Parameters:
      // - schedule (MedicationSchedule): Dose schedule supplied or produced by the UI.
      // Returns:
      // - The element's medicationID value.
      expect(updatedSchedules.map((schedule) => schedule.medicationID), [
        '7',
        '8',
      ]);
      expect(
        updatedSchedules.every(
          // Function Name: every callback
          // Description:
          // - Check that each returned medication has its morning dose marked complete.
          // Parameters:
          // - schedule (MedicationSchedule): Dose schedule supplied or produced by the UI.
          // Returns:
          // - True for an element with a completed morning slot.
          (schedule) => schedule.isSlotCompleted('morning'),
        ),
        isTrue,
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: updateMedicationSlotStatus rejects unsupported slots locally.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'updateMedicationSlotStatus rejects unsupported slots locally',
    () async {
      final control = CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        // Function Name: MockClient callback
        // Description:
        // - Complete the mocked HTTP request with status 200 and an empty JSON object without network access.
        // Parameters:
        // - _ (http.Request): Unused intercepted HTTP request.
        // Returns:
        // - Future<http.Response> with status 200.
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        control.updateMedicationSlotStatus('after-midnight', true),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: MedicationSchedule accepts diagram typo status alias.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('MedicationSchedule accepts diagram typo status alias', () {
    final schedule = MedicationSchedule.fromScheduleJson({
      'medicationID': '9',
      'drug_name': 'alias-tablet',
      'medcationStatus': 1,
      'patientID': 'patient-a',
    });

    expect(schedule.medicationID, '9');
    expect(schedule.medicationStatus, isTrue);
    expect(schedule.patientID, 'patient-a');
  });
}
