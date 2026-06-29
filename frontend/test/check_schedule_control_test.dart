// 파일명: check_schedule_control_test.dart
// 역할: 프론트 복약 일정 control의 조회 범위와 상태 변경 요청을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';

void main() {
  test('requestTodayMedicationSchedule scopes request by patient hash',
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
  });

  test('requestTodayMedicationSchedule can request guardian linked scope',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today');
      expect(request.url.queryParameters['patient_hash'], 'local_patient');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'medication_id': '7',
              'drug_name': 'guardian-tablet',
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
    });
    final control = CheckSchedule(
      baseUrl: 'http://localhost',
      userHash: 'guardian-a',
      role: 'guardian',
      client: client,
    );

    final schedules = await control.requestTodayMedicationSchedule();

    expect(schedules, hasLength(1));
    expect(schedules.first.patientID, 'patient-a');
    expect(schedules.first.medicationName, 'guardian-tablet');
  });

  test('updateMedicationStatus sends scoped status patch', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/schedule/7/status');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters['role'], 'patient');
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

  test('updateMedicationStatus can patch guardian linked scope', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/schedule/7/status');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'medication_id': '7',
            'drug_name': 'guardian-tablet',
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
      userHash: 'guardian-a',
      role: 'guardian',
      client: client,
    );

    final updatedSchedule = await control.updateMedicationStatus('7', true);

    expect(updatedSchedule.patientID, 'patient-a');
    expect(updatedSchedule.medicationStatus, isTrue);
  });

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
