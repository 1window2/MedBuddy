// 파일명: check_schedule_control_test.dart
// 역할: 프론트 복약 일정 control의 조회 범위와 상태 변경 요청을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';

void main() {
  test(
    'requestTodayMedicationSchedule scopes request by patient hash',
    () async {
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

  test(
    'requestMedicationScheduleWindow requests future reminder courses',
    () async {
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

  test('updateMedicationStatus sends scoped status patch', () async {
    late Map<String, dynamic> requestBody;
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

  test('updateMedicationStatus sends slot key for dose patch', () async {
    late Map<String, dynamic> requestBody;
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

  test(
    'updateMedicationSlotStatus sends one scoped whole-slot patch',
    () async {
      late Map<String, dynamic> requestBody;
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
      );

      expect(requestBody, {'medication_status': true});
      expect(updatedSchedules.map((schedule) => schedule.medicationID), [
        '7',
        '8',
      ]);
      expect(
        updatedSchedules.every(
          (schedule) => schedule.isSlotCompleted('morning'),
        ),
        isTrue,
      );
    },
  );

  test(
    'updateMedicationSlotStatus rejects unsupported slots locally',
    () async {
      final control = CheckSchedule(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        control.updateMedicationSlotStatus('after-midnight', true),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

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
