// 파일명: dose_day_rollover_test.dart
// 역할: 앱 기준 날짜가 바뀐 뒤 첫 재개에서 만료된 복용 투영이 성공한 일정 조회로 취급되지 않는지 검증한다.
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
    client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/schedule/today')) {
        // 네트워크 조회가 기기 저장소 왕복보다 늦게 끝나는 실제 순서를 만든다.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'medication_id': 91,
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

      // 경합으로 첫 조회가 버려졌다면 성공으로 보고하지 않고 복구 대상으로 남긴다.
      if (viewModel.todayMedicationScheduleList.isEmpty) {
        expect(recovered, isFalse);
        expect(viewModel.hasTodayScheduleLoadError, isTrue);
      }

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
}
