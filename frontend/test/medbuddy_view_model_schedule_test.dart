// File Name: medbuddy_view_model_schedule_test.dart
// Role: Verifies schedule status updates are routed through the ViewModel.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('dose status update uses slot-scoped backend status flow', () async {
    var patchCalled = false;
    late Map<String, dynamic> patchBody;
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
                'slot_statuses': {
                  'morning': false,
                  'lunch': false,
                  'evening': false,
                },
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
      expect(request.url.path, '/schedule/today');
      scheduleFetchCount += 1;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': <Map<String, dynamic>>[],
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
      expect(request.url.path, '/schedule/today');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
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
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();

    expect(viewModel.todayMedicationProgress.totalCount, 2);
    expect(viewModel.todayMedicationProgress.completedCount, 1);
  });

  test('slotKeysForSchedule prefers backend slot status keys', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'medication_id': '7',
              'drug_name': 'test-tablet',
              'daily_frequency': '1 time',
              'slot_statuses': {
                'lunch': false,
              },
              'patient_hash': 'patient-a',
            },
          ],
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
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();
    final schedule = viewModel.todayMedicationScheduleList.single;

    expect(viewModel.slotKeysForSchedule(schedule), ['lunch']);
    expect(viewModel.todayMedicationProgress.totalCount, 1);
  });

  test('today progress parses Korean daily frequency labels', () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'medication_id': '7',
              'drug_name': 'test-tablet',
              'daily_frequency': '1일 3회',
              'patient_hash': 'patient-a',
            },
          ],
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
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();

    expect(viewModel.todayMedicationProgress.totalCount, 3);
    expect(viewModel.todayMedicationProgress.completedCount, 0);
  });

  test('refreshMedicationOverview registers enabled reminders for live slots',
      () async {
    SharedPreferences.setMockInitialValues({});
    final notificationService = _FakeNotificationService();
    final client = MockClient((http.Request request) async {
      if (request.url.path.endsWith('/notification/settings')) {
        return _jsonResponse({
          'success': true,
          'data': [
            {
              'patient_hash': PatientHash.defaultPatientHash,
              'slot_key': 'morning',
              'hour': 8,
              'minute': 15,
              'is_enabled': true,
            },
          ],
        });
      }
      if (request.url.path.endsWith('/schedule/today/info')) {
        return _jsonResponse({
          'success': true,
          'data': {
            'patient_hash': PatientHash.defaultPatientHash,
            'schedules': [
              {
                'medication_id': '11',
                'drug_name': 'test-tablet',
                'daily_frequency': '1 time',
                'slot_statuses': {'morning': false},
                'patient_hash': PatientHash.defaultPatientHash,
              },
            ],
          },
        });
      }
      return http.Response('Not found', 404);
    });
    final viewModel = MedBuddyViewModel(
      apiClient: client,
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);

    await viewModel.refreshMedicationOverview();

    expect(notificationService.registeredSlotKeys, ['morning']);
    expect(notificationService.registeredMedicationNames.single, [
      'test-tablet',
    ]);
  });

  test('failed local registration rolls persisted reminder back to disabled',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requestMethods = <String>[];
    final notificationService = _FakeNotificationService(
      failRegistration: true,
    );
    final client = MockClient((http.Request request) async {
      requestMethods.add(request.method);
      if (request.method == 'PUT') {
        return _jsonResponse({
          'success': true,
          'data': {
            'patient_hash': PatientHash.defaultPatientHash,
            'slot_key': 'morning',
            'hour': 8,
            'minute': 30,
            'is_enabled': true,
          },
        });
      }
      if (request.method == 'PATCH') {
        return _jsonResponse({
          'success': true,
          'data': {
            'patient_hash': PatientHash.defaultPatientHash,
            'slot_key': 'morning',
            'hour': 8,
            'minute': 30,
            'is_enabled': false,
          },
        });
      }
      return http.Response('Not found', 404);
    });
    final viewModel = MedBuddyViewModel(
      apiClient: client,
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);

    final result = await viewModel.requestMedicationReminderSave(
      slotKey: 'morning',
      slotTitle: 'Morning',
      hour: 8,
      minute: 30,
      schedules: const [MedicationSchedule(medicationName: 'test-tablet')],
    );

    final setting = const MedicationAlarm(
      patientHash: PatientHash.defaultPatientHash,
      slotKey: 'morning',
      hour: 8,
      minute: 30,
      enabled: true,
    );
    final preferences = await SharedPreferences.getInstance();
    final cachedSetting = jsonDecode(
      preferences.getString(
        'medbuddy_medication_reminder_patient_local_patient_'
        'local_patient_morning',
      )!,
    ) as Map<String, dynamic>;

    expect(result, isFalse);
    expect(requestMethods, ['PUT', 'PATCH']);
    expect(
      notificationService.canceledIds,
      containsAll([setting.notificationId, setting.legacyNotificationId]),
    );
    expect(cachedSetting['is_enabled'], isFalse);
    expect(viewModel.medicationReminderSettings, isEmpty);
  });
}

http.Response _jsonResponse(Map<String, dynamic> payload) {
  return http.Response(
    jsonEncode(payload),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

class _FakeNotificationService implements NotificationService {
  final bool failRegistration;
  final List<int> canceledIds = [];
  final List<String> registeredSlotKeys = [];
  final List<List<String>> registeredMedicationNames = [];

  _FakeNotificationService({this.failRegistration = false});

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    String language = 'ko',
  }) async {
    registeredSlotKeys.add(slotKey);
    registeredMedicationNames.add(medicationNames);
    if (failRegistration) {
      throw StateError('Simulated local notification failure.');
    }
  }

  @override
  Future<void> cancelReminder(int id) async {
    canceledIds.add(id);
  }
}
