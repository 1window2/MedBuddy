// File Name: test_support_test.dart
// Role: Self-test of the shared test helpers in test/support, so a helper that stops recording or
//   stops matching the production interface fails here and not inside a feature test.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

import 'dose_sync_harness.dart';
import 'fake_controls.dart';
import 'fake_notification_service.dart';
import 'json_http.dart';
import 'test_viewport.dart';

const _owner = 'patient-a';
const _medication = MedicationSchedule(
  medicationID: '91',
  medicationName: '테스트정',
  scheduleSlotKeys: ['morning'],
  slotStatuses: {'morning': false},
);
final _now = DateTime.utc(2026, 9, 21, 3); // 12:00 KST

// Function Name: _scheduleClient
// Description:
// - Build the API client of a signed-in patient whose today schedule holds one morning medicine;
//   every other request is answered with 404 so an unexpected call cannot look like a success.
// Parameters:
// - None.
// Returns:
// - http.Client: MockClient serving GET schedule/today.
http.Client _scheduleClient() {
  return MockClient((request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/schedule/today')) {
      return jsonResponse({
        'success': true,
        'data': [_medication.toJson()],
      });
    }
    return jsonResponse({'detail': 'not found'}, status: 404);
  });
}

// Function Name: _viewModel
// Description:
// - Build the view model a signed-in session owns, with the recording notification fake in place
//   of the notification platform.
// Parameters:
// - client (http.Client): API client shared by the view model's controls.
// Returns:
// - MedBuddyViewModel: View model scoped to the test patient.
MedBuddyViewModel _viewModel(http.Client client) {
  return MedBuddyViewModel(
    patientHash: _owner,
    apiClient: client,
    notificationService: RecordingNotificationService(),
  );
}

// Function Name: _recordMorningDose
// Description:
// - Load the schedule and mark the morning slot as taken through the view model, then check that
//   the dose went through the outbox: one queued operation, an upload attempt that omits the
//   medicine names, and the completed state projected back onto the view model.
// Parameters:
// - viewModel (MedBuddyViewModel): View model with the harness attached.
// - harness (DoseSyncHarness): Harness returned by attachTestDoseSync.
// Returns:
// - Future<void>: Completion of the assertions.
Future<void> _recordMorningDose(
  MedBuddyViewModel viewModel,
  DoseSyncHarness harness,
) async {
  await viewModel.fetchTodayMedicationSchedule();
  expect(viewModel.todayMedicationScheduleList, hasLength(1));
  expect(harness.service.hasCache, isTrue);

  expect(await viewModel.requestMedicationSlotStatusUpdate('morning', true), isTrue);
  await harness.service.drain();

  final operation = harness.queued.single;
  expect(operation['slot_key'], 'morning');
  expect(operation['medication_ids'], [91]);
  expect(operation['completed'], isTrue);
  expect(operation['schedule_date'], '2026-09-21');
  expect(operation['medication_names'], ['테스트정']);

  final upload = harness.uploads.first;
  expect(upload.method, 'POST');
  expect(upload.url.path, endsWith('/schedule/completion-operations'));
  expect(upload.url.queryParameters['patient_hash'], _owner);
  final body = jsonDecode(upload.body) as Map<String, dynamic>;
  expect(body['operation_id'], operation['operation_id']);
  expect(body.containsKey('medication_names'), isFalse);

  // The built-in client is offline until the test chooses a response.
  expect((await harness.pending()).single['state'], 'pending');
  expect(
    viewModel.todayMedicationScheduleList.single.isSlotCompleted('morning'),
    isTrue,
  );
}

// Function Name: main
// Description: Registers the self-tests of every helper under test/support.
// Parameters: None. Returns: None.
void main() {
  group('RecordingNotificationService', () {
    // The fake must be usable wherever the production type is expected and keep every argument.
    test('records reminder registrations, cancellations and snoozes', () async {
      final fake = RecordingNotificationService();
      final NotificationService service = fake;
      final date = DateTime(2026, 9, 21);

      await service.initialize();
      expect(await service.requestPermission(), isTrue);
      await service.registerNotification(
        id: 17,
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 8,
        minute: 30,
        medicationNames: ['테스트정'],
        activeDates: [date],
        medicationNamesByDate: {
          '2026-09-21': ['테스트정'],
        },
        language: 'en',
      );
      await service.cancelReminder(17, slotKey: 'morning');
      await service.cancelReminderForDate(
        owner: _owner,
        slotKey: 'morning',
        date: date,
      );
      await service.snoozeMedicationReminder(
        id: 31,
        slotKey: 'bedtime',
        slotTitle: '취침 전',
        scheduleDate: date,
      );

      expect(fake.initializeCount, 1);
      expect(fake.permissionRequestCount, 1);
      final registration = fake.registrations.single;
      expect(registration.id, 17);
      expect(registration.slotTitle, '아침');
      expect((registration.hour, registration.minute), (8, 30));
      expect(registration.medicationNamesByDate, {
        '2026-09-21': ['테스트정'],
      });
      expect(registration.language, 'en');
      expect(fake.registeredIds, [17]);
      expect(fake.registeredSlotKeys, ['morning']);
      expect(fake.registeredMedicationNames.single, ['테스트정']);
      expect(fake.registeredActiveDates.single, [date]);
      expect(fake.canceledIds, [17]);
      expect(fake.cancellations.single.slotKey, 'morning');
      expect(fake.dateCancellations.single, (
        owner: _owner,
        slotKey: 'morning',
        date: date,
      ));
      expect(fake.snoozes.single, (
        id: 31,
        slotKey: 'bedtime',
        slotTitle: '취침 전',
        language: 'ko',
        delay: const Duration(minutes: 10),
        scheduleDate: date,
      ));
    });

    // A failing platform must still leave the attempt visible to the test.
    test('failure switches throw after recording the attempt', () async {
      final fake = RecordingNotificationService(
        failRegistration: true,
        failSnooze: true,
        permissionGranted: false,
      );

      expect(await fake.requestPermission(), isFalse);
      await expectLater(
        fake.registerNotification(
          id: 1,
          slotKey: 'lunch',
          slotTitle: '점심',
          hour: 12,
          minute: 0,
          medicationNames: const [],
          activeDates: const [],
        ),
        throwsStateError,
      );
      await expectLater(
        fake.snoozeMedicationReminder(id: 1, slotKey: 'lunch', slotTitle: '점심'),
        throwsStateError,
      );
      expect(fake.registeredSlotKeys, ['lunch']);
      expect(fake.snoozes, hasLength(1));

      fake.failRegistration = false;
      await fake.registerNotification(
        id: 2,
        slotKey: 'evening',
        slotTitle: '저녁',
        hour: 18,
        minute: 0,
        medicationNames: const [],
        activeDates: const [],
      );
      expect(fake.registeredIds, [1, 2]);
    });

    // Session clean-up and shown alerts are distinguishable by kind.
    test('records session cancellations, alerts and session settings', () async {
      final fake = RecordingNotificationService();
      expect(fake.canceledAllMedicationReminders, isFalse);
      expect(fake.showSensitiveDetails, isNull);

      fake.setHistoryUser(_owner, persistSession: false);
      fake.setShowSensitiveDetails(false);
      await fake.openSystemNotificationSettings();
      await fake.cancelAllScheduledMedicationReminders();
      expect(fake.canceledAllMedicationReminders, isTrue);
      expect(fake.cancelAllMedicationRemindersCount, 0);
      await fake.cancelAllMedicationReminders();
      await fake.showCaregiverAlert(
        id: 5,
        title: '복약 알림',
        body: '아침 약을 복용했습니다.',
        patientHash: 'patient-b',
        recordHistory: false,
      );
      await fake.showLinkedChatAlert(
        id: 6,
        linkId: 17,
        messagePreview: '안녕하세요',
        slotKey: 'evening',
      );

      expect(fake.historyUsers.single, (userHash: _owner, persistSession: false));
      expect(fake.showSensitiveDetails, isFalse);
      expect(fake.systemSettingsOpenCount, 1);
      expect(fake.cancelAllScheduledMedicationRemindersCount, 1);
      expect(fake.cancelAllMedicationRemindersCount, 1);
      final caregiverAlert = fake.caregiverAlerts.single;
      expect(caregiverAlert.id, 5);
      // The privacy flag is recorded but never rewrites the body.
      expect(caregiverAlert.body, '아침 약을 복용했습니다.');
      expect(caregiverAlert.patientHash, 'patient-b');
      expect(caregiverAlert.recordHistory, isFalse);
      final chatAlert = fake.linkedChatAlerts.single;
      expect((chatAlert.id, chatAlert.linkId), (6, 17));
      expect(chatAlert.messagePreview, '안녕하세요');
      expect(chatAlert.slotKey, 'evening');
      expect(chatAlert.recordHistory, isTrue);
    });
  });

  group('fake controls', () {
    // The empty controls answer their entry read locally; a request would fail the test.
    test('empty controls return no rows without a request', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('unexpected', 500);
      });
      final schedule = EmptyCheckSchedule(patientHash: _owner, client: client);
      final reminders = EmptySetNotification(patientHash: _owner, client: client);
      addTearDown(schedule.dispose);
      addTearDown(reminders.dispose);

      expect(await schedule.requestTodayMedicationSchedule(), isEmpty);
      expect(await reminders.requestMedicationAlarm(), isEmpty);
      expect(schedule.patientHash, _owner);
      expect(requests, 0);
    });

    // One fake covers the fixed, failing and pending variants kept in the nearby-care tests.
    test('device location answers, fails or stays pending', () async {
      final location = FakeDeviceLocation();
      final DeviceLocationBoundary boundary = location;
      expect(
        (await boundary.requestCurrentCoordinate()).latitude,
        FakeDeviceLocation.seoulCityHall.latitude,
      );

      const moved = DeviceCoordinate(latitude: 35.1, longitude: 129.0);
      location.coordinate = moved;
      expect(await boundary.requestCurrentCoordinate(), same(moved));

      location.error = const DeviceLocationException(
        DeviceLocationFailure.denied,
      );
      await expectLater(
        boundary.requestCurrentCoordinate(),
        throwsA(
          isA<DeviceLocationException>().having(
            (error) => error.failure,
            'failure',
            DeviceLocationFailure.denied,
          ),
        ),
      );
      expect(location.requests, 3);
      expect(await boundary.openApplicationSettings(), isTrue);
      expect(await boundary.openDeviceLocationSettings(), isTrue);
      expect(location.applicationSettingsRequests, 1);
      expect(location.deviceSettingsRequests, 1);

      final pending = FakeDeviceLocation(pending: true);
      var answered = false;
      final request = pending.requestCurrentCoordinate().then((coordinate) {
        answered = true;
        return coordinate;
      });
      await Future<void>.delayed(Duration.zero);
      expect(pending.requests, 1);
      expect(answered, isFalse);
      pending.result.complete(moved);
      expect(await request, same(moved));
    });
  });

  // Korean fixture text must survive the response encoding.
  test('jsonResponse encodes UTF-8 JSON with the backend content type', () {
    final response = jsonResponse({'name': '타이레놀'}, status: 404);
    expect(response.statusCode, 404);
    expect(response.headers['content-type'], 'application/json; charset=utf-8');
    expect(jsonDecode(response.body), {'name': '타이레놀'});
    expect(jsonDecode(utf8.decode(response.bodyBytes)), {'name': '타이레놀'});
    expect(jsonResponse(const []).statusCode, 200);
  });

  group('setTestViewport', () {
    // The size is logical (pixel ratio 1) and the text scale reaches MediaQuery.
    testWidgets('applies the logical size and text scale', (tester) async {
      setTestViewport(tester, const Size(320, 640), textScale: 2);

      late MediaQueryData media;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(media.size, const Size(320, 640));
      expect(media.textScaler.scale(10), 20);
    });

    // In file order this proves the resets registered above ran; in any other order it still holds.
    testWidgets('the next test starts from the default surface', (tester) async {
      expect(tester.view.physicalSize, const Size(2400, 1800));
      expect(tester.view.devicePixelRatio, 3);
    });

    // Without textScale the helper must not touch a scale set elsewhere, such as the global hook.
    testWidgets('leaves the text scale alone when none is given', (tester) async {
      final textScale = tester.platformDispatcher.textScaleFactor;
      setTestViewport(tester, const Size(430, 900));
      expect(tester.view.physicalSize, const Size(430, 900));
      expect(tester.view.devicePixelRatio, 1);
      expect(tester.platformDispatcher.textScaleFactor, textScale);
    });
  });

  group('attachTestDoseSync', () {
    // The harness must put a view-model dose on the production outbox path and expose it.
    test('queues a view-model dose and uploads it once the server answers', () async {
      final client = _scheduleClient();
      final viewModel = _viewModel(client);
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);

      expect(viewModel.doseSync, same(harness.service));
      expect(harness.owner, _owner);
      expect(harness.queued, isEmpty);
      await _recordMorningDose(viewModel, harness);

      harness.respond = (request) async => doseSyncReceipt(request, [
        _medication.copyWith(
          slotStatuses: {'morning': true},
          medicationStatus: true,
        ),
      ]);
      await harness.service.drain();

      expect(await harness.pending(), isEmpty);
      expect(harness.queued, hasLength(1));
      expect(
        viewModel.todayMedicationScheduleList.single.isSlotCompleted('morning'),
        isTrue,
      );
      await harness.close();
      await harness.close();
    });

    // Widget tests run on a fake clock; the harness must work there without runAsync.
    testWidgets('works inside a widget test and leaves no timer behind', (tester) async {
      final viewModel = _viewModel(_scheduleClient());
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);

      await _recordMorningDose(viewModel, harness);
      // The service's own retry timer (at most two minutes) fires on the fake clock.
      final attempts = harness.uploads.length;
      await tester.pump(const Duration(minutes: 3));
      expect(harness.uploads.length, greaterThan(attempts));

      await tester.pumpWidget(const SizedBox.shrink());
      await harness.close();
    });

    // A seeded cache is enough for callers that read the service directly, as the chat screen does.
    test('seeded schedules back direct records, one database per harness', () async {
      final first = await attachTestDoseSync(
        _viewModel(_scheduleClient()),
        clock: () => _now,
      );
      final second = await attachTestDoseSync(
        _viewModel(_scheduleClient()),
        clock: () => _now,
      );

      expect(first.service.hasCache, isFalse);
      await first.seedSchedules(const [_medication]);
      expect(first.service.hasCache, isTrue);
      expect(first.service.schedules.single.medicationID, '91');
      expect(
        await first.service.record(
          medicationIds: [91],
          slotKey: 'morning',
          completed: true,
          linkId: 17,
          medicationNames: ['테스트정'],
        ),
        isTrue,
      );
      await first.service.drain();

      expect(first.queued.single['link_id'], 17);
      expect(first.service.schedules.single.isSlotCompleted('morning'), isTrue);
      expect(second.service.hasCache, isFalse);
      expect(second.queued, isEmpty);
      expect(await second.pending(), isEmpty);
    });
  });
}
