import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';
import 'package:medbuddy_frontend/controls/check_today_medication_info_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';
import 'package:medbuddy_frontend/services/medication_notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('default API controls share an injected app transport', () async {
    final requestedPaths = <String>[];
    final client = MockClient((http.Request request) async {
      requestedPaths.add(request.url.path);
      return http.Response(
        jsonEncode({'success': true, 'data': []}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final viewModel = MedBuddyViewModel(apiClient: client);
    addTearDown(() {
      viewModel.dispose();
      client.close();
    });

    await viewModel.checkSavedMedication.requestSavedMedicationInfo();
    await viewModel.checkSchedule.requestTodayMedicationSchedule();

    expect(
      requestedPaths,
      containsAll(<String>[
        '/api/v1/medication/list',
        '/api/v1/medication/schedule/today',
      ]),
    );
  });

  test('setMedicationAccessScope persists selected guardian medication scope',
      () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-a',
      userHash: 'guardian-a',
      role: 'guardian',
    );

    expect(viewModel.medicationPatientHash, 'patient-a');
    expect(viewModel.medicationUserHash, 'guardian-a');
    expect(viewModel.medicationRole, 'guardian');
  });

  test('setMedicationAccessScope normalizes empty patient scope to default',
      () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: ' ',
      role: 'patient',
    );

    expect(viewModel.medicationPatientHash, PatientHash.defaultPatientHash);
    expect(viewModel.medicationUserHash, isNull);
    expect(viewModel.medicationRole, 'patient');
  });

  test('setMedicationAccessScope normalizes the legacy caregiver role', () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-a',
      userHash: 'guardian-a',
      role: 'caregiver',
    );

    expect(viewModel.medicationRole, 'guardian');
  });

  test('setMedicationAccessScope rejects unsupported roles', () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    expect(
      () => viewModel.setMedicationAccessScope(
        patientHash: 'patient-a',
        role: 'administrator',
      ),
      throwsArgumentError,
    );
  });

  test('setMedicationAccessScope rejects conflicting patient identity', () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    expect(
      () => viewModel.setMedicationAccessScope(
        patientHash: 'patient-a',
        userHash: 'patient-b',
        role: 'patient',
      ),
      throwsArgumentError,
    );
  });

  test('fetchHealthRecommendation uses selected medication access scope',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/health/recommendation');
      expect(request.url.queryParameters['patient_hash'], 'patient-b');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'diet_recommendation': 'diet',
            'exercise_recommendation': 'exercise',
            'caution_items': ['caution'],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final viewModel = MedBuddyViewModel(
      checkHealthRecommendation: CheckHealthRecommendation(
        baseUrl: 'http://localhost',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      userHash: 'guardian-a',
      role: 'guardian',
    );
    await viewModel.fetchHealthRecommendation();

    expect(viewModel.healthRecommendation?.dietRecommendation, 'diet');
  });

  test('loadMedicationReminderSettings uses selected medication access scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/notification/settings');
      expect(request.url.queryParameters['patient_hash'], 'patient-b');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'patient_hash': 'patient-b',
              'slot_key': 'morning',
              'hour': 7,
              'minute': 45,
              'is_enabled': true,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final viewModel = MedBuddyViewModel(
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      userHash: 'guardian-a',
      role: 'guardian',
    );
    await viewModel.loadMedicationReminderSettings();

    final setting = viewModel.medicationReminderSettings['morning'];
    expect(setting?.hour, 7);
    expect(setting?.minute, 45);
    expect(setting?.isEnabled, isTrue);
  });

  test('setMedicationAccessScope clears stale medication scope data', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((http.Request request) async {
      if (request.url.path == '/schedule/today/info') {
        return _jsonResponse(_schedulePayload('patient-a'));
      }
      if (request.url.path == '/health/recommendation') {
        return _jsonResponse(_healthRecommendationPayload());
      }
      return _jsonResponse({'success': true, 'data': []});
    });
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
      checkHealthRecommendation: CheckHealthRecommendation(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();
    await viewModel.fetchHealthRecommendation();
    await viewModel.loadMedicationReminderSettings();

    expect(viewModel.todayMedicationScheduleList, isNotEmpty);
    expect(viewModel.healthRecommendation, isNotNull);
    expect(viewModel.medicationReminderSettings, isNotEmpty);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      userHash: 'guardian-a',
      role: 'guardian',
    );

    expect(viewModel.todayMedicationScheduleList, isEmpty);
    expect(viewModel.healthRecommendation, isNull);
    expect(viewModel.medicationReminderSettings, isEmpty);
  });

  test('stale schedule response cannot overwrite a newly selected scope',
      () async {
    final patientAResponse = Completer<http.Response>();
    final patientARequestStarted = Completer<void>();
    final client = MockClient((http.Request request) async {
      final patientHash = request.url.queryParameters['patient_hash'];
      if (patientHash == 'patient-a') {
        patientARequestStarted.complete();
        return patientAResponse.future;
      }
      return _jsonResponse(_schedulePayload('patient-b', medicationId: '8'));
    });
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-a',
      role: 'patient',
    );
    final staleLoad = viewModel.fetchTodayMedicationSchedule();
    await patientARequestStarted.future;

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      role: 'patient',
    );
    await viewModel.fetchTodayMedicationSchedule();
    patientAResponse.complete(
      _jsonResponse(_schedulePayload('patient-a', medicationId: '7')),
    );
    await staleLoad;

    expect(viewModel.todayMedicationScheduleList.single.patientID, 'patient-b');
    expect(viewModel.isTodayScheduleLoading, isFalse);
  });

  test('stale alarm response cannot overwrite a newly selected scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final patientAResponse = Completer<http.Response>();
    final patientARequestStarted = Completer<void>();
    final client = MockClient((http.Request request) async {
      final patientHash = request.url.queryParameters['patient_hash'];
      if (patientHash == 'patient-a') {
        patientARequestStarted.complete();
        return patientAResponse.future;
      }
      return _jsonResponse(
        _alarmPayload('patient-b', hour: 9, minute: 45),
      );
    });
    final viewModel = MedBuddyViewModel(
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-a',
      role: 'patient',
    );
    final staleLoad = viewModel.loadMedicationReminderSettings();
    await patientARequestStarted.future;

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      role: 'patient',
    );
    await viewModel.loadMedicationReminderSettings();
    patientAResponse.complete(
      _jsonResponse(_alarmPayload('patient-a', hour: 7, minute: 15)),
    );
    await staleLoad;

    final setting = viewModel.medicationReminderSettings['morning'];
    expect(setting?.patientHash, 'patient-b');
    expect(setting?.hour, 9);
    expect(setting?.minute, 45);
  });

  test('refreshMedicationOverview loads reminder and schedule for active scope',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requestedPaths = <String>[];
    final client = MockClient((http.Request request) async {
      requestedPaths.add(request.url.path);
      expect(request.method, 'GET');
      expect(request.url.queryParameters['patient_hash'], 'patient-b');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');

      if (request.url.path == '/notification/settings') {
        return _jsonResponse(_alarmPayload('patient-b'));
      }

      expect(request.url.path, '/schedule/today/info');
      return _jsonResponse(_schedulePayload('patient-b', medicationId: '9'));
    });
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        client: client,
      ),
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        client: client,
      ),
      notificationService: _FakeMedicationNotificationService(),
    );
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      userHash: 'guardian-a',
      role: 'guardian',
    );
    await viewModel.refreshMedicationOverview();

    expect(requestedPaths, contains('/notification/settings'));
    expect(requestedPaths, contains('/schedule/today/info'));
    expect(viewModel.todayMedicationScheduleList.single.patientID, 'patient-b');
    expect(viewModel.medicationReminderSettings['morning']?.hour, 8);
  });

  test('refreshMedicationOverview reschedules enabled reminders', () async {
    SharedPreferences.setMockInitialValues({});
    final notificationService = _FakeMedicationNotificationService();
    final client = MockClient((http.Request request) async {
      if (request.url.path == '/notification/settings') {
        return _jsonResponse(_alarmPayload('patient-a'));
      }
      if (request.url.path == '/schedule/today/info') {
        return _jsonResponse(_schedulePayload('patient-a'));
      }
      return _jsonResponse({'success': false});
    });
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);

    await viewModel.refreshMedicationOverview();

    expect(notificationService.scheduledSlotKeys, contains('morning'));
    expect(notificationService.scheduledMedicationNames.single,
        contains('patient-a-tablet'));
    expect(notificationService.canceledIds, contains(1001));
  });

  test('reminder synchronization follows backend slot status keys', () async {
    SharedPreferences.setMockInitialValues({});
    final notificationService = _FakeMedicationNotificationService();
    final client = MockClient((http.Request request) async {
      if (request.url.path == '/notification/settings') {
        return _jsonResponse(
          _alarmPayload(
            'patient-a',
            slotKey: 'lunch',
            hour: 12,
            minute: 30,
          ),
        );
      }
      if (request.url.path == '/schedule/today/info') {
        return _jsonResponse(
          _schedulePayload(
            'patient-a',
            dailyFrequency: '1 time',
            slotStatuses: {'lunch': false},
          ),
        );
      }
      return _jsonResponse({'success': false});
    });
    final viewModel = MedBuddyViewModel(
      checkTodayMedicationInfo: CheckTodayMedicationInfo(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      ),
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);

    await viewModel.refreshMedicationOverview();

    expect(notificationService.scheduledSlotKeys, ['lunch']);
  });

  test('failed local reminder registration rolls back every persisted state',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requestMethods = <String>[];
    final notificationService = _FakeMedicationNotificationService(
      failAfterScheduling: true,
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
      return _jsonResponse({'success': false});
    });
    final viewModel = MedBuddyViewModel(
      setNotification: SetNotification(
        baseUrl: 'http://localhost',
        client: client,
      ),
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);

    final result = await viewModel.requestMedicationReminderSave(
      slotKey: 'morning',
      slotTitle: 'Morning',
      hour: 8,
      minute: 30,
      schedules: const [MedicationSchedule(medicationName: 'tablet')],
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

Map<String, dynamic> _schedulePayload(
  String patientHash, {
  String medicationId = '7',
  String dailyFrequency = '1 time',
  Map<String, bool>? slotStatuses,
}) {
  return {
    'success': true,
    'data': {
      'patient_hash': patientHash,
      'schedules': [
        {
          'medication_id': medicationId,
          'drug_name': '$patientHash-tablet',
          'daily_frequency': dailyFrequency,
          if (slotStatuses != null) 'slot_statuses': slotStatuses,
          'patient_hash': patientHash,
        },
      ],
    },
  };
}

Map<String, dynamic> _healthRecommendationPayload() {
  return {
    'success': true,
    'data': {
      'diet_recommendation': 'diet',
      'exercise_recommendation': 'exercise',
      'caution_items': ['caution'],
    },
  };
}

Map<String, dynamic> _alarmPayload(
  String patientHash, {
  String slotKey = 'morning',
  int hour = 8,
  int minute = 15,
}) {
  return {
    'success': true,
    'data': [
      {
        'patient_hash': patientHash,
        'slot_key': slotKey,
        'hour': hour,
        'minute': minute,
        'is_enabled': true,
      },
    ],
  };
}

class _FakeMedicationNotificationService
    implements MedicationNotificationService {
  final bool failAfterScheduling;
  final List<int> canceledIds = [];
  final List<String> scheduledSlotKeys = [];
  final List<List<String>> scheduledMedicationNames = [];

  _FakeMedicationNotificationService({
    this.failAfterScheduling = false,
  });

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleDailyReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    String language = 'ko',
  }) async {
    scheduledSlotKeys.add(slotKey);
    scheduledMedicationNames.add(medicationNames);
    if (failAfterScheduling) {
      throw StateError('Simulated local notification failure.');
    }
  }

  @override
  Future<void> cancelReminder(int id) async {
    canceledIds.add(id);
  }
}
