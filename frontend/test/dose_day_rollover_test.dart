// File Name: dose_day_rollover_test.dart
// Role: Verify that midnight recovery does not treat an expired projection as a successful load
//   and that dose actions are durably assigned to the current schedule day.
// Real SQLite/crypto regressions; synthetic data and mock HTTP only.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

// Function Name: main
// Description: Registers real SQLite and encryption regressions for midnight recovery, reminder preservation, and durable dose recording.
// Parameters: None.
// Returns: void; initializes test bindings and registers fixtures and cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late DoseOutboxStore store;
  late Directory directory;
  late DateTime current;
  late List<String> disableCalls;
  late List<Map<String, dynamic>> uploads;
  late bool scheduleOnline;
  late bool uploadOnline;
  late int scheduledMedicationId;
  late http.Client client;

  // Function Name: setUp callback
  // Description: Creates an encrypted temporary outbox, resets the controlled day and connectivity, and installs delayed schedule responses plus recorded uploads and disable requests.
  // Parameters: None.
  // Returns: Future<void>; completes when the database, key, and mock client are ready, or propagates fixture setup failures.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('dose-rollover-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    current = DateTime.utc(2026, 9, 21, 3); // 12:00 KST
    disableCalls = [];
    uploads = [];
    scheduleOnline = true;
    uploadOnline = true;
    scheduledMedicationId = 91;
    client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/schedule/today')) {
        // 네트워크 조회가 기기 저장소 왕복보다 늦게 끝나는 실제 순서를 만든다.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!scheduleOnline) return http.Response('unavailable', 503);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'medication_id': scheduledMedicationId,
                'drug_name': 'synthetic',
                'daily_frequency': '1',
                'schedule_slot_keys': ['morning'],
                'slot_statuses': {'morning': false},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.method == 'GET' && path.endsWith('/notification/settings')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'patient_hash': 'patient-a',
                'slot_key': 'morning',
                'hour': 8,
                'minute': 0,
                'is_enabled': true,
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          path.endsWith('/schedule/completion-operations')) {
        uploads.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (!uploadOnline) return http.Response('unavailable', 503);
        return http.Response(
          jsonEncode({
            'success': true,
            'operation_id': (jsonDecode(request.body) as Map)['operation_id'],
            'schedule_date': doseScheduleDay(current),
            'data': [
              {
                'medication_id': 91,
                'drug_name': 'synthetic',
                'daily_frequency': '1',
                'schedule_slot_keys': ['morning'],
                'slot_statuses': {'morning': true},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.method == 'PATCH' && path.endsWith('/disable')) {
        disableCalls.add(path);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'patient_hash': 'patient-a',
              'slot_key': 'morning',
              'hour': 8,
              'minute': 0,
              'is_enabled': false,
            },
          }),
          200,
        );
      }
      return http.Response('{"detail":"unexpected"}', 500);
    });
  });

  // Function Name: tearDown callback
  // Description: Closes the mock HTTP client and SQLite database, then removes the temporary outbox directory.
  // Parameters: None.
  // Returns: Future<void>; completes after cleanup, or propagates a database-close or deletion failure.
  tearDown(() async {
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  // Function Name: signedInViewModelAfterDayOne
  // Description: Attaches active dose synchronization to a patient view model, drains it, and loads the first day's schedule into its projection.
  // Parameters: None.
  // Returns: Future<MedBuddyViewModel>; the initialized model after asserting one schedule, no load error, and no reminder-disable request.
  Future<MedBuddyViewModel> signedInViewModelAfterDayOne() async {
    final viewModel = MedBuddyViewModel(
      patientHash: 'patient-a',
      apiClient: client,
    );
    viewModel.attachDoseSync(
      DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => store,
        clock: () => current,
      ),
    );
    await viewModel.doseSync!.initialize(activate: true);
    await viewModel.doseSync!.drain();
    await viewModel.refreshMedicationSchedule();
    expect(viewModel.todayMedicationScheduleList, hasLength(1));
    expect(viewModel.hasTodayScheduleLoadError, isFalse);
    expect(disableCalls, isEmpty);
    return viewModel;
  }

  // Function Name: expired projection recovery test
  // Description: Races resume-time draining with next-day recovery; an empty discarded result must remain a load error, and a later recovery must restore the schedule without disabling reminders.
  // Parameters: None.
  // Returns: Future<void>; fails if an empty projection is reported as success or subsequent recovery loses the schedule or reminder.
  test(
    'an expired projection on a new day is flagged for recovery, not shown as an empty schedule',
    () async {
      final viewModel = await signedInViewModelAfterDayOne();
      current = current.add(const Duration(days: 1));

      // 실제 기기의 재개 콜백과 같이 동기화 재전송과 화면 복구가 함께 시작된다.
      viewModel.doseSync!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final recovered = await viewModel.recoverMedicationConnectivity();
      await viewModel.doseSync!.drain();

      // 재개와 겹친 첫 조회의 결과는 둘 중 하나다. 오늘 일정이 표시되고 성공으로 보고되거나,
      // 조회가 버려져 비어 있으면서 복구 대상으로 남는다. 빈 일정이 성공으로 보고되는 일은 없다.
      final shown = viewModel.todayMedicationScheduleList.isNotEmpty;
      expect(recovered, shown);
      expect(viewModel.hasTodayScheduleLoadError, !shown);

      expect(await viewModel.recoverMedicationConnectivity(), isTrue);
      expect(viewModel.todayMedicationScheduleList, hasLength(1));
      expect(viewModel.hasTodayScheduleLoadError, isFalse);
      expect(disableCalls, isEmpty);
      viewModel.dispose();
    },
  );

  // Function Name: next-day refresh and drain race test
  // Description: Verifies that a refresh overlapping the new day's first drain keeps the morning reminder enabled and a subsequent refresh restores the schedule.
  // Parameters: None.
  // Returns: Future<void>; fails if any disable request is sent or the final schedule is missing.
  test(
    'a refresh racing the first drain of a new day does not disable enabled reminders',
    () async {
      final viewModel = await signedInViewModelAfterDayOne();
      current = current.add(const Duration(days: 1));

      viewModel.doseSync!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await viewModel.refreshMedicationSchedule();
      await viewModel.doseSync!.drain();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(disableCalls, isEmpty);
      expect(
        viewModel.medicationReminderSettings['morning']?.isEnabled,
        isTrue,
      );

      await viewModel.refreshMedicationSchedule();
      expect(viewModel.todayMedicationScheduleList, hasLength(1));
      expect(disableCalls, isEmpty);
      viewModel.dispose();
    },
  );

  for (final resumeFirst in [false, true]) {
    // Function Name: dated dose action and resume ordering test
    // Description: Runs a dated slot action before or after resume and verifies one upload for the new day's medication, followed by an empty outbox and no reminder disable.
    // Parameters: None; resumeFirst selects the registration loop's ordering case.
    // Returns: Future<void>; fails if the dose date, medication, completion state, or upload count differs.
    test(
      'a dose taken on the first resume of a new day is recorded (resumeFirst=$resumeFirst)',
      () async {
        final viewModel = await signedInViewModelAfterDayOne();
        current = current.add(const Duration(days: 1));

        if (resumeFirst) {
          viewModel.doseSync!.didChangeAppLifecycleState(
            AppLifecycleState.resumed,
          );
        }
        // 알림 경로는 알림의 날짜를 함께 넘긴다(main.dart).
        final action = viewModel.requestMedicationSlotStatusUpdate(
          'morning',
          true,
          expectedScheduleDate: doseScheduleDay(current),
        );
        if (!resumeFirst) {
          viewModel.doseSync!.didChangeAppLifecycleState(
            AppLifecycleState.resumed,
          );
        }

        expect(await action, isTrue);
        await viewModel.doseSync!.drain();
        expect(disableCalls, isEmpty);
        // 새 날짜의 아침 약 전체가 한 번만 기록된다.
        expect(uploads, hasLength(1));
        expect(uploads.single['schedule_date'], doseScheduleDay(current));
        expect(uploads.single['slot_key'], 'morning');
        expect(uploads.single['medication_ids'], [91]);
        expect(uploads.single['completed'], isTrue);
        expect(await store.pending('patient-a'), isEmpty);
        viewModel.dispose();
      },
    );
  }

  for (final resumeFirst in [false, true]) {
    // Function Name: stale-list tap and durable retry test
    // Description: Rejects a tap on yesterday's item and refreshes the list; a second tap queues today's dose offline, updates the projection, and reuses the same operation ID after reconnection.
    // Parameters: None; resumeFirst selects whether resume precedes the stale-list tap.
    // Returns: Future<void>; fails if the first tap records a dose, the retry uses the wrong day, or reconnection leaves pending work or duplicates operation identity.
    test(
      'a dose tapped on yesterday\'s list right after midnight is refused, then recorded from today\'s list (resumeFirst=$resumeFirst)',
      () async {
        final viewModel = await signedInViewModelAfterDayOne();
        final tapped = viewModel.todayMedicationScheduleList.single;
        current = current.add(const Duration(days: 1));
        // 서버 전송은 아직 되지 않는다: 기록은 기기 대기열에만 있어야 한다.
        uploadOnline = false;

        if (resumeFirst) {
          viewModel.doseSync!.didChangeAppLifecycleState(
            AppLifecycleState.resumed,
          );
        }
        expect(
          await viewModel.requestMedicationDoseStatusUpdate(
            'morning',
            tapped,
            true,
          ),
          isFalse,
        );
        expect(
          viewModel.statusMessage,
          '날짜가 바뀌어 오늘 일정을 다시 불러왔습니다. 확인한 뒤 다시 눌러주세요.',
        );
        expect(await store.pending('patient-a'), isEmpty);
        expect(
          viewModel.todayMedicationScheduleList.single.isSlotCompleted(
            'morning',
          ),
          isFalse,
        );
        // 다시 읽은 오늘 목록에서 누르면 기록된다.
        final saved = await viewModel.requestMedicationDoseStatusUpdate(
          'morning',
          viewModel.todayMedicationScheduleList.single,
          true,
        );
        await viewModel.doseSync!.drain();

        expect(saved, isTrue);
        final queued = (await store.pending('patient-a')).single;
        expect(queued['schedule_date'], doseScheduleDay(current));
        expect(queued['slot_key'], 'morning');
        expect(queued['medication_ids'], [91]);
        expect(queued['completed'], isTrue);
        expect(queued['state'], 'pending');
        expect(
          viewModel.todayMedicationScheduleList.single.isSlotCompleted(
            'morning',
          ),
          isTrue,
        );
        expect(viewModel.hasTodayScheduleLoadError, isFalse);
        // 기기에만 있는 기록은 서버 기록 화면을 다시 읽게 하지 않는다.
        final savedBefore = viewModel.savedDoseRecords.value;

        // 연결되면 같은 요청이 한 번만 전송된다.
        uploadOnline = true;
        await viewModel.doseSync!.drain();
        expect(await store.pending('patient-a'), isEmpty);
        expect(viewModel.savedDoseRecords.value, savedBefore + 1);
        expect(
          uploads.map((upload) => upload['operation_id']).toSet(),
          {queued['operation_id']},
        );
        expect(disableCalls, isEmpty);
        viewModel.dispose();
      },
    );
  }

  // Function Name: undated versus dated slot action test
  // Description: Rejects an undated whole-slot request from yesterday's list, then accepts an explicitly current-day request after another rollover and queues it under that date.
  // Parameters: None.
  // Returns: Future<void>; fails if the undated request queues work or the dated request is rejected or assigned another day.
  test(
    'a whole slot tapped on yesterday\'s list is refused; a dated request is recorded',
    () async {
      final viewModel = await signedInViewModelAfterDayOne();
      current = current.add(const Duration(days: 1));
      uploadOnline = false;

      expect(
        await viewModel.requestMedicationSlotStatusUpdate('morning', true),
        isFalse,
      );
      expect(await store.pending('patient-a'), isEmpty);

      current = current.add(const Duration(days: 1));
      expect(
        await viewModel.requestMedicationSlotStatusUpdate(
          'morning',
          true,
          expectedScheduleDate: doseScheduleDay(current),
        ),
        isTrue,
      );
      expect(
        (await store.pending('patient-a')).single['schedule_date'],
        doseScheduleDay(current),
      );
      viewModel.dispose();
    },
  );

  // Function Name: failed next-day schedule load test
  // Description: Makes today's schedule unavailable and verifies that individual and whole-slot actions report the load failure without queuing, uploading, or displaying a taken dose.
  // Parameters: None.
  // Returns: Future<void>; fails if stale data records a dose or the connection failure is hidden.
  test(
    'a dose after midnight is neither queued nor shown as taken when today cannot be loaded',
    () async {
      final viewModel = await signedInViewModelAfterDayOne();
      final tapped = viewModel.todayMedicationScheduleList.single;
      current = current.add(const Duration(days: 1));
      scheduleOnline = false;

      expect(
        await viewModel.requestMedicationDoseStatusUpdate(
          'morning',
          tapped,
          true,
        ),
        isFalse,
      );
      // 다시 읽기에 실패한 이유를 그대로 알린다.
      expect(viewModel.statusMessage, contains('서버가 일시적으로 응답하지 않습니다'));
      expect(
        await viewModel.requestMedicationSlotStatusUpdate('morning', true),
        isFalse,
      );
      expect(viewModel.statusMessage, contains('서버가 일시적으로 응답하지 않습니다'));

      expect(await store.pending('patient-a'), isEmpty);
      expect(uploads, isEmpty);
      expect(
        viewModel.todayMedicationScheduleList.any(
          (schedule) => schedule.isSlotCompleted('morning'),
        ),
        isFalse,
      );
      viewModel.dispose();
    },
  );

  // Function Name: medication removed after rollover test
  // Description: Replaces today's medication ID and verifies that tapping yesterday's item only refreshes the list and asks for confirmation, without recording either medication.
  // Parameters: None.
  // Returns: Future<void>; fails if pending/uploads appear, the replacement list is wrong, or the replacement is shown as taken.
  test(
    'a medicine that is no longer scheduled today is not recorded',
    () async {
      final viewModel = await signedInViewModelAfterDayOne();
      final tapped = viewModel.todayMedicationScheduleList.single;
      current = current.add(const Duration(days: 1));
      scheduledMedicationId = 92;

      expect(
        await viewModel.requestMedicationDoseStatusUpdate(
          'morning',
          tapped,
          true,
        ),
        isFalse,
      );

      expect(await store.pending('patient-a'), isEmpty);
      expect(uploads, isEmpty);
      expect(viewModel.todayMedicationScheduleList.single.medicationID, '92');
      expect(
        viewModel.todayMedicationScheduleList.single.isSlotCompleted('morning'),
        isFalse,
      );
      expect(
        viewModel.statusMessage,
        '날짜가 바뀌어 오늘 일정을 다시 불러왔습니다. 확인한 뒤 다시 눌러주세요.',
      );
      viewModel.dispose();
    },
  );

  // Function Name: offline outbox-before-display test
  // Description: Disables reads and uploads on the same day and verifies that every taken-state notification already has a pending outbox record with the correct medication, slot, and date.
  // Parameters: None.
  // Returns: Future<void>; fails if the UI reports a taken dose before durable queuing or omits the pending-upload message.
  test('an offline dose is in the outbox before it is shown as taken', () async {
    final viewModel = await signedInViewModelAfterDayOne();
    final tapped = viewModel.todayMedicationScheduleList.single;
    uploadOnline = false;
    scheduleOnline = false;
    final shownAsTaken = <bool>[];
    final queuedWhenShown = <int>[];
    viewModel.doseSync!.addListener(() {
      // 서비스가 화면에 변경을 알리는 시점마다 화면 상태와 대기열 길이를 함께 기록한다.
      shownAsTaken.add(
        viewModel.doseSync!.schedules.any((s) => s.isSlotCompleted('morning')),
      );
      queuedWhenShown.add(viewModel.doseSync!.pendingCount);
    });

    expect(
      await viewModel.requestMedicationDoseStatusUpdate('morning', tapped, true),
      isTrue,
    );
    await viewModel.doseSync!.drain();

    expect(shownAsTaken, contains(true));
    for (var i = 0; i < shownAsTaken.length; i++) {
      if (shownAsTaken[i]) expect(queuedWhenShown[i], 1);
    }
    final queued = (await store.pending('patient-a')).single;
    expect(queued['medication_ids'], [91]);
    expect(queued['slot_key'], 'morning');
    expect(queued['schedule_date'], doseScheduleDay(current));
    expect(
      viewModel.todayMedicationScheduleList.single.isSlotCompleted('morning'),
      isTrue,
    );
    expect(viewModel.statusMessage, '기기에 기록했습니다. 서버 전송 대기 중입니다.');
    viewModel.dispose();
  });
}
