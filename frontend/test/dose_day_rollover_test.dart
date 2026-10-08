// 파일명: dose_day_rollover_test.dart
// 역할: 앱 기준 날짜가 바뀐 뒤 첫 재개에서 만료된 복용 투영이 성공한 일정 조회로 취급되지 않는지,
//   날짜가 바뀐 직후의 복용 기록이 새 날짜의 대기열에 저장되는지 검증한다.
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

// 함수이름: main
// 함수역할: 날짜 변경 직후의 일정 조회·알림 동기화 경합 회귀 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
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

  tearDown(() async {
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  // 함수이름: signedInViewModelAfterDayOne
  // 함수역할: 첫날 일정을 정상 조회해 캐시까지 채운 ViewModel을 만든다.
  // 매개변수: 없음. 반환값: 첫날 조회를 마친 ViewModel.
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

  // 함수이름: 날짜 변경 직후 복용 기록 테스트
  // 함수역할: 전날부터 살아 있던 앱에서 알림의 "복용했어요"가 재개와 겹쳐도 복용 기록이 저장되는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  for (final resumeFirst in [false, true]) {
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
        final action = viewModel.requestMedicationSlotStatusUpdate(
          'morning',
          true,
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

  // 함수이름: 날짜 변경 직후 개별 복용 체크 테스트
  // 함수역할: 전날 목록이 그대로 보이는 화면에서 약 하나를 체크해도, 오늘 일정을 다시 읽은 뒤 같은 약의
  //   오늘 기록으로 대기열에 저장되고 그 뒤에야 화면에 복용으로 표시되는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  for (final resumeFirst in [false, true]) {
    test(
      'a single dose checked right after midnight is queued for the new day (resumeFirst=$resumeFirst)',
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
        final saved = await viewModel.requestMedicationDoseStatusUpdate(
          'morning',
          tapped,
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

        // 연결되면 같은 요청이 한 번만 전송된다.
        uploadOnline = true;
        await viewModel.doseSync!.drain();
        expect(await store.pending('patient-a'), isEmpty);
        expect(
          uploads.map((upload) => upload['operation_id']).toSet(),
          {queued['operation_id']},
        );
        expect(disableCalls, isEmpty);
        viewModel.dispose();
      },
    );
  }

  // 함수이름: 날짜 변경 뒤 일정 조회 실패 테스트
  // 함수역할: 오늘 일정을 읽지 못하면 전날 목록으로 오늘 복용을 기록하지 않고, 화면에도 복용으로 표시하지
  //   않으며 실패를 알리는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
      expect(viewModel.statusMessage, '오늘의 복약 일정을 다시 불러온 뒤 기록해주세요.');
      expect(
        await viewModel.requestMedicationSlotStatusUpdate('morning', true),
        isFalse,
      );
      // 시간대 전체 기록은 다시 읽기에 실패한 이유를 그대로 알린다.
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

  // 함수이름: 날짜 변경 뒤 사라진 약 테스트
  // 함수역할: 체크한 약이 오늘 일정에 없으면 다른 약이나 전날 약으로 기록하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
      expect(viewModel.statusMessage, '오늘의 복약 일정을 다시 불러온 뒤 기록해주세요.');
      viewModel.dispose();
    },
  );

  // 함수이름: 같은 날 오프라인 복용 기록 테스트
  // 함수역할: 연결이 없어도 복용 체크가 대기열에 먼저 저장되고 그 기록으로 화면에 복용이 표시되는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
