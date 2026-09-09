// File Name: medbuddy_view_model_schedule_test.dart
// Role: Regression coverage for schedule state races, completion updates, deletion refreshes, and
//   reminder rollback.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/manage_account_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_feature_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Function Name: main
// Description:
// - Register regression cases for schedule state races, completion updates, deletion refreshes, and
//   reminder rollback.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 일정 변경은 일정 화면 채널에만 전달된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('일정 변경은 일정 화면 채널에만 전달된다', () async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _DelayedCheckSchedule(
        Future.value(const <MedicationSchedule>[]),
      ),
    );
    addTearDown(viewModel.dispose);
    var scheduleUpdateCount = 0;
    var prescriptionUpdateCount = 0;
    // 함수이름: addListener 콜백
    // 함수역할:
    // - 일정 전용 변경 채널의 알림 횟수를 기록한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 일정 채널 알림 수가 증가한다.
    viewModel.updatesFor(MedBuddyFeature.schedule).addListener(() {
      scheduleUpdateCount += 1;
    });
    // 함수이름: addListener 콜백
    // 함수역할:
    // - 처방 분석 채널의 알림 횟수를 기록해 일정 변경의 채널 격리를 확인한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 처방 채널 알림 수가 증가한다.
    viewModel.updatesFor(MedBuddyFeature.prescription).addListener(() {
      prescriptionUpdateCount += 1;
    });

    await viewModel.fetchTodayMedicationSchedule();

    expect(scheduleUpdateCount, 2);
    expect(prescriptionUpdateCount, 0);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 비동기 일정 조회가 끝나기 전에 ViewModel을 폐기해도 예외가 발생하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('비동기 일정 조회가 끝나기 전에 ViewModel을 폐기해도 예외가 발생하지 않는다', () async {
    final scheduleCompleter = Completer<List<MedicationSchedule>>();
    final viewModel = MedBuddyViewModel(
      checkSchedule: _DelayedCheckSchedule(scheduleCompleter.future),
    );

    final loadFuture = viewModel.fetchTodayMedicationSchedule();
    viewModel.dispose();
    scheduleCompleter.complete(const <MedicationSchedule>[]);

    await expectLater(loadFuture, completes);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 최신 일정 조회가 끝나면 이전 요청이 대기 중이어도 로딩이 종료된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('최신 일정 조회가 끝나면 이전 요청이 대기 중이어도 로딩이 종료된다', () async {
    final firstResponse = Completer<List<MedicationSchedule>>();
    final secondResponse = Completer<List<MedicationSchedule>>();
    final viewModel = MedBuddyViewModel(
      checkSchedule: _SequentialCheckSchedule([
        firstResponse.future,
        secondResponse.future,
      ]),
    );
    addTearDown(viewModel.dispose);

    final firstLoad = viewModel.fetchTodayMedicationSchedule();
    final secondLoad = viewModel.fetchTodayMedicationSchedule();
    expect(viewModel.isTodayScheduleLoading, isTrue);

    secondResponse.complete(const <MedicationSchedule>[]);
    await secondLoad;

    expect(viewModel.isTodayScheduleLoading, isFalse);

    firstResponse.complete(const <MedicationSchedule>[]);
    await firstLoad;
    expect(viewModel.isTodayScheduleLoading, isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 복용 완료 변경이 약 식별자와 시간대 범위를 가진 서버 갱신 흐름을 사용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('dose status update uses slot-scoped backend status flow', () async {
    var patchCalled = false;
    late Map<String, dynamic> patchBody;
    // Function Name: MockClient callback
    // Description:
    // - Serve the initial uncompleted schedule, then capture a dose PATCH and return morning completion.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with the read-list or updated single schedule.
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
      viewModel.todayMedicationScheduleList.first.medicationStatus,
      isFalse,
    );
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: whole-slot update replaces every returned schedule in one request.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'whole-slot update replaces every returned schedule in one request',
    () async {
      var patchCount = 0;
      // Function Name: MockClient callback
      // Description:
      // - Serve two pending morning doses, count the whole-slot PATCH, and return both completed schedules.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 containing the corresponding schedule list.
      final client = MockClient((http.Request request) async {
        if (request.method == 'GET') {
          return _jsonResponse({
            'success': true,
            'data': [
              {
                'medication_id': '7',
                'drug_name': 'first-tablet',
                'daily_frequency': '3 times',
                'slot_statuses': {
                  'morning': false,
                  'lunch': false,
                  'evening': false,
                },
                'patient_hash': 'patient-a',
              },
              {
                'medication_id': '8',
                'drug_name': 'second-tablet',
                'schedule_slot_keys': ['morning'],
                'slot_statuses': {'morning': false},
                'patient_hash': 'patient-a',
              },
            ],
          });
        }

        patchCount += 1;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/schedule/slot/morning/status');
        return _jsonResponse({
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
        });
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

      final success = await viewModel.requestMedicationSlotStatusUpdate(
        'morning',
        true,
      );

      expect(success, isTrue);
      expect(patchCount, 1);
      expect(
        viewModel.todayMedicationScheduleList.every(
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
      expect(viewModel.todayMedicationProgress.completedCount, 2);
      expect(viewModel.todayMedicationProgress.totalCount, 4);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 완료 변경보다 먼저 시작된 일정 조회 응답이 최신 완료 상태를 덮어쓰지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'older schedule GET cannot overwrite a newer completion PATCH',
    () async {
      final staleGetStarted = Completer<void>();
      final staleGetResponse = Completer<http.Response>();
      var getCount = 0;
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 첫 조회와 완료 PATCH는 즉시 응답하되 두 번째 GET을 대기시켜 오래된 응답 경쟁을 재현한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
      // 반환값:
      // - 현재 단계의 일정 응답 또는 테스트가 완료하는 오래된 GET Future.
      final client = MockClient((http.Request request) async {
        if (request.method == 'GET') {
          getCount += 1;
          if (getCount == 1) {
            return _scheduleResponse(morningCompleted: false);
          }
          expect(getCount, 2);
          staleGetStarted.complete();
          return staleGetResponse.future;
        }

        expect(request.method, 'PATCH');
        expect(request.url.path, '/schedule/7/status');
        return _scheduleResponse(morningCompleted: true, wrapInList: false);
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

      final staleFetch = viewModel.fetchTodayMedicationSchedule();
      await staleGetStarted.future;
      final patchSucceeded = await viewModel.requestMedicationDoseStatusUpdate(
        'morning',
        schedule,
        true,
      );

      expect(patchSucceeded, isTrue);
      expect(
        viewModel.isMedicationDoseCompleted(
          'morning',
          viewModel.todayMedicationScheduleList.single,
        ),
        isTrue,
      );

      staleGetResponse.complete(_scheduleResponse(morningCompleted: false));
      await staleFetch;

      expect(getCount, 2);
      expect(viewModel.isTodayScheduleLoading, isFalse);
      expect(
        viewModel.isMedicationDoseCompleted(
          'morning',
          viewModel.todayMedicationScheduleList.single,
        ),
        isTrue,
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 묶음 삭제의 혼합 결과를 한 번 반영하고 오늘 일정도 한 번만 새로 조회하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'batch delete applies mixed results once and refreshes schedule once',
    () async {
      final deletedRequestIds = <int>[];
      // Function Name: MockClient callback
      // Description:
      // - Serve three saved tablets and record deletions while failing only medication 2.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 for reads/successful deletions; HTTP 500 for deletion 2.
      final savedMedicationClient = MockClient((http.Request request) async {
        if (request.method == 'GET') {
          expect(request.url.path, '/list');
          return _jsonResponse({
            'success': true,
            'data': [
              _savedMedicationJson(1, 'tablet-one'),
              _savedMedicationJson(2, 'tablet-two'),
              _savedMedicationJson(3, 'tablet-three'),
            ],
          });
        }

        expect(request.method, 'DELETE');
        final id = int.parse(request.url.pathSegments.last);
        deletedRequestIds.add(id);
        return http.Response(
          jsonEncode({'success': id != 2}),
          id == 2 ? 500 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      var scheduleFetchCount = 0;
      // Function Name: MockClient callback
      // Description:
      // - Count the schedule refresh following grouped deletion and return no remaining doses.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with an empty schedule list.
      final scheduleClient = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/schedule/today');
        scheduleFetchCount += 1;
        return _jsonResponse({
          'success': true,
          'data': <Map<String, dynamic>>[],
        });
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

      await viewModel.fetchSavedMedicationInfo();
      final observedSavedIds = <List<int>>[];
      // Function Name: addListener callback
      // Description:
      // - Capture each published saved-ID list so mixed deletion results can be checked for a single state
      //   update.
      // Parameters:
      // - None.
      // Returns:
      // - No value; appends the current saved-ID snapshot.
      viewModel.addListener(() {
        observedSavedIds.add(
          viewModel.savedMedicationInfoList
              // Function Name: map callback
              // Description:
              // - Extract the non-null saved medication ID for the collection assertion.
              // Parameters:
              // - medication (MedicationDetail): Saved medication whose ID is inspected.
              // Returns:
              // - The element's id! value.
              .map((medication) => medication.id!)
              .toList(growable: false),
        );
      });

      final result = await viewModel.requestDeleteSavedMedications([1, 2, 3]);

      expect(result.successCount, 2);
      expect(result.failureCount, 1);
      expect(result.totalCount, 3);
      expect(result.hasFailures, isTrue);
      expect(deletedRequestIds, containsAll(<int>[1, 2, 3]));
      expect(deletedRequestIds, hasLength(3));
      expect(scheduleFetchCount, 1);
      expect(
        viewModel.savedMedicationInfoList
            // Function Name: map callback
            // Description:
            // - Extract the saved medication ID for the collection assertion.
            // Parameters:
            // - medication (MedicationDetail): Saved medication whose ID is inspected.
            // Returns:
            // - The element's id value.
            .map((medication) => medication.id)
            .toList(),
        [2],
      );
      expect(observedSavedIds, isNotEmpty);
      for (final savedIds in observedSavedIds) {
        expect(savedIds, [2]);
      }
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 저장 약 삭제 후 오늘 일정 캐시가 새 서버 결과로 갱신되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('deleting saved medication refreshes today schedule cache', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert deletion of medication 3 and acknowledge its removal.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with success=true.
    final savedMedicationClient = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/delete/3');
      return http.Response('{"success":true}', 200);
    });
    var scheduleFetchCount = 0;
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 약 삭제 후 오늘 일정 재조회 횟수를 기록하고 빈 최신 일정을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 빈 일정 데이터의 HTTP 200 응답.
    final scheduleClient = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/schedule/today');
      scheduleFetchCount += 1;
      return http.Response(
        jsonEncode({'success': true, 'data': <Map<String, dynamic>>[]}),
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 오늘 복약 진행률이 오래된 요약 숫자 대신 현재 일정의 시간대 상태를 사용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'today progress is derived from schedule slots, not stale summary counts',
    () async {
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 하루 두 번 일정의 아침 완료·저녁 미완료 상태를 제공해 진행률 계산을 검사한다.
      // 매개변수:
      // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
      // 반환값:
      // - 시간대별 상태를 가진 HTTP 200 응답.
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
                'slot_statuses': {'morning': true, 'evening': false},
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
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: slotKeysForSchedule prefers explicit backend schedule slot keys.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'slotKeysForSchedule prefers explicit backend schedule slot keys',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Provide a schedule explicitly restricted to lunch so backend slot keys take precedence.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with a single explicit lunch slot.
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
                'slot_statuses': {'lunch': false},
                'schedule_slot_keys': ['lunch'],
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
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: completed-only slot status does not shrink the expected daily schedule.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'completed-only slot status does not shrink the expected daily schedule',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Provide completed-slot keys without narrowing the three-times-daily expected schedule.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with morning completion and daily frequency three.
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
                'daily_frequency': '3 times',
                'completed_slot_keys': ['morning'],
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
      expect(viewModel.todayMedicationProgress.completedCount, 1);
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: today progress parses Korean daily frequency labels.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('today progress parses Korean daily frequency labels', () async {
    // Function Name: MockClient callback
    // Description:
    // - Provide a Korean three-times-daily frequency label for progress parsing.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing the frequency-label schedule.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 복약 개요 갱신이 실제 일정 시간대에 활성화된 로컬 알림을 등록하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'refreshMedicationOverview registers enabled reminders for live slots',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notificationService = _FakeNotificationService();
      // Function Name: MockClient callback
      // Description:
      // - Serve enabled 08:15 morning settings and a live morning dose, rejecting unrelated routes.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 for the two supported reads; HTTP 404 otherwise.
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
      expect(notificationService.registeredActiveDates, hasLength(1));
      final activeDate =
          notificationService.registeredActiveDates.single.single;
      final now = DateTime.now();
      expect(
        DateTime(activeDate.year, activeDate.month, activeDate.day),
        DateTime(now.year, now.month, now.day),
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 기본 복약 시각을 바꿔도 기존 비활성 알림 시각은 유지된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('기본 복약 시각을 바꿔도 기존 비활성 알림 시각은 유지된다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_local_patient_default_morning_time': '07:00',
    });
    final notificationService = _FakeNotificationService();
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 비활성 오전 9:45 알림과 빈 일정을 제공해 기본 시각 변경 시 기존 시각 보존을 검사한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 지원 조회의 HTTP 200 응답 또는 그 외 404.
    final client = MockClient((http.Request request) async {
      if (request.url.path.endsWith('/notification/settings')) {
        return _jsonResponse({
          'success': true,
          'data': [
            {
              'patient_hash': PatientHash.defaultPatientHash,
              'slot_key': 'morning',
              'hour': 9,
              'minute': 45,
              'is_enabled': false,
            },
          ],
        });
      }
      if (request.url.path.endsWith('/schedule/today/info')) {
        return _jsonResponse({
          'success': true,
          'data': {
            'patient_hash': PatientHash.defaultPatientHash,
            'schedules': <Map<String, dynamic>>[],
          },
        });
      }
      return http.Response('Not found', 404);
    });
    final viewModel = MedBuddyViewModel(
      apiClient: client,
      notificationService: notificationService,
      manageUserSetting: ManageUserSetting(
        userHash: PatientHash.defaultPatientHash,
        useRemotePersistence: false,
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.loadUserSetting();

    expect(viewModel.userSetting.defaultMorningTime, '07:00');
    final existingSetting = viewModel.medicationReminderSettings['morning'];
    expect(existingSetting, isNotNull);
    expect(existingSetting!.hour, 9);
    expect(existingSetting.minute, 45);
    expect(existingSetting.isEnabled, isFalse);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 복약 알림 날짜는 처방된 복용 종료일을 넘지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('복약 알림 날짜는 처방된 복용 종료일을 넘지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final notificationService = _FakeNotificationService();
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 알림 시각 저장 PUT에 오전 8:30 활성 설정을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 저장 성공 HTTP 200 또는 미지원 요청의 404.
    final client = MockClient((http.Request request) async {
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
      return http.Response('Not found', 404);
    });
    final viewModel = MedBuddyViewModel(
      apiClient: client,
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final result = await viewModel.requestMedicationReminderSave(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: 8,
      minute: 30,
      schedules: [
        MedicationSchedule(
          medicationName: '테스트정',
          prescriptionDate: today,
          medicationTime: 3,
        ),
      ],
    );

    expect(result, isTrue);
    expect(notificationService.registeredActiveDates.single, [
      today,
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
    ]);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 로컬 알림 등록 실패 시 저장된 활성 상태를 비활성으로 되돌리는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'failed local registration rolls persisted reminder back to disabled',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requestMethods = <String>[];
      final notificationService = _FakeNotificationService(
        failRegistration: true,
      );
      // Function Name: MockClient callback
      // Description:
      // - Record request order and model enabling via PUT followed by disabling via PATCH during rollback.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with the corresponding enabled flag; HTTP 404 for other routes.
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
      final cachedSetting =
          jsonDecode(
                preferences.getString(
                  'medbuddy_medication_reminder_patient_local_patient_'
                  'local_patient_morning',
                )!,
              )
              as Map<String, dynamic>;

      expect(result, isFalse);
      expect(requestMethods, ['PUT', 'PATCH']);
      expect(
        notificationService.canceledIds,
        containsAll([setting.notificationId, setting.legacyNotificationId]),
      );
      expect(cachedSetting['is_enabled'], isFalse);
      expect(viewModel.medicationReminderSettings, isEmpty);
    },
  );

  // Function Name: test callback
  // Description:
  // - Verify that all device medication reminders are canceled before account data is deleted.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('계정 데이터 삭제 전에 기기의 복약 알림을 모두 취소한다', () async {
    SharedPreferences.setMockInitialValues({});
    final notificationService = _FakeNotificationService();
    final accountControl = ManageAccount(
      userHash: 'patient-a',
      // Function Name: MockClient callback
      // Description:
      // - Assert device reminders were canceled before accepting the account-data DELETE.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 acknowledging deletion after cleanup.
      client: MockClient((request) async {
        expect(notificationService.canceledAllMedicationReminders, isTrue);
        expect(request.method, 'DELETE');
        return http.Response('{"success":true}', 200);
      }),
    );
    final viewModel = MedBuddyViewModel(
      manageAccount: accountControl,
      notificationService: notificationService,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestAccountDataDeletion();

    expect(notificationService.canceledAllMedicationReminders, isTrue);
  });
}

// 클래스명: _DelayedCheckSchedule
// 역할: ViewModel 폐기 이후 완료되는 일정 조회를 재현한다.
// 주요 책임:
// - 새 요청을 만들지 않고 주입한 지연 응답을 그대로 제공한다.
class _DelayedCheckSchedule extends CheckSchedule {
  final Future<List<MedicationSchedule>> responseFuture;

  // 함수이름: _DelayedCheckSchedule
  // 함수역할:
  // - 폐기 이후에 완료시킬 일정 조회 Future를 보관한다.
  // 매개변수:
  // - responseFuture (Future<List<MedicationSchedule>>): 테스트가 외부에서 완료시킬 일정 응답.
  // 반환값:
  // - 지정 응답 시점을 사용하는 일정 대역.
  _DelayedCheckSchedule(this.responseFuture);

  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 새 요청을 만들지 않고 주입한 지연 응답을 그대로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 생성자에 지정한 일정 조회 Future.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() {
    return responseFuture;
  }
}

// 클래스명: _SequentialCheckSchedule
// 역할: 일정 조회가 겹친 상황에서 각 요청을 원하는 순서로 완료한다.
// 주요 책임:
// - 호출할 때마다 다음 응답 Future를 선택해 완료 순서를 독립적으로 제어한다.
// 속성:
// - _requestIndex (int): 다음에 선택할 외부 제어 일정 Future의 인덱스.
class _SequentialCheckSchedule extends CheckSchedule {
  final List<Future<List<MedicationSchedule>>> responseFutures;
  int _requestIndex = 0;

  // 함수이름: _SequentialCheckSchedule
  // 함수역할:
  // - 겹친 일정 조회마다 순서대로 사용할 응답 Future 목록을 보관한다.
  // 매개변수:
  // - responseFutures (List<Future<List<MedicationSchedule>>>): 연속 요청 순서에 따라 선택할 응답 목록.
  // 반환값:
  // - 요청별 완료 시점을 제어하는 일정 대역.
  _SequentialCheckSchedule(this.responseFutures);

  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 호출할 때마다 다음 응답 Future를 선택해 완료 순서를 독립적으로 제어한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 요청 순번에 해당하는 일정 Future.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() {
    return responseFutures[_requestIndex++];
  }
}

// Function Name: _scheduleResponse
// Description:
// - Build a morning-completion response in either list-GET or single-PATCH shape.
// Parameters:
// - morningCompleted (bool): Completion state assigned to the morning dose.
// - wrapInList (bool): Whether response data uses the GET list rather than PATCH object shape.
// Returns:
// - HTTP 200 containing the requested completion state and response shape.
http.Response _scheduleResponse({
  required bool morningCompleted,
  bool wrapInList = true,
}) {
  final schedule = <String, dynamic>{
    'medication_id': '7',
    'drug_name': 'test-tablet',
    'dosage_per_time': '1 tablet',
    'daily_frequency': '3 times',
    'total_days': '7 days',
    'medication_status': false,
    'slot_statuses': {
      'morning': morningCompleted,
      'lunch': false,
      'evening': false,
    },
    'patient_hash': 'patient-a',
  };
  return _jsonResponse({
    'success': true,
    'data': wrapInList ? [schedule] : schedule,
  });
}

// Function Name: _savedMedicationJson
// Description:
// - Build a saved-tablet JSON row with stable patient identity and dates.
// Parameters:
// - id (int): Identifier of the medication, message, or notification fixture.
// - name (String): Display name of the saved-medication fixture.
// Returns:
// - The patient-a medication map for the supplied ID and name.
Map<String, dynamic> _savedMedicationJson(int id, String name) {
  return {
    'id': id,
    'patient_hash': 'patient-a',
    'created_date': '2026-07-15',
    'prescription_date': '2026-07-15',
    'item_seq': '20000000$id',
    'item_name': name,
    'efficacy': 'effect',
    'use_method': 'usage',
    'warning_message': 'warning',
  };
}

// Function Name: _jsonResponse
// Description:
// - Encode a successful JSON API payload with explicit UTF-8 content type.
// Parameters:
// - payload (Map<String, dynamic>): JSON response fields supplied by the test.
// Returns:
// - HTTP 200 containing the supplied JSON payload.
http.Response _jsonResponse(Map<String, dynamic> payload) {
  return http.Response(
    jsonEncode(payload),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

// Class Name: _FakeNotificationService
// Role: Notification spy that records registrations and cancellations and can reject registration.
// Responsibilities:
// - Skip real notification-plugin initialization while satisfying the platform interface.
// - Grant notification permission in the fake without invoking an OS permission prompt.
// - Record registered slots, medication names, and dates, then optionally reject local registration.
// Attributes:
// - failRegistration (bool): Whether local notification registration should throw.
// - canceledAllMedicationReminders (bool): Whether session-wide reminder cancellation occurred.
class _FakeNotificationService implements NotificationService {
  // 함수이름: setShowSensitiveDetails
  // 함수역할:
  // - 플랫폼 알림을 표시하지 않는 대역이므로 잠금 화면 상세정보 설정을 외부에 적용하지 않는다.
  // 매개변수:
  // - showSensitiveDetails (bool): 잠금 화면 알림에 민감 상세정보를 표시할지 여부. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 없음; 플랫폼 상태를 변경하지 않는다.
  @override
  void setShowSensitiveDetails(bool showSensitiveDetails) {}

  // 함수이름: openSystemNotificationSettings
  // 함수역할:
  // - 기기의 설정 앱을 열지 않고 시스템 알림 설정 이동을 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> openSystemNotificationSettings() async {}

  // 함수이름: cancelAllScheduledMedicationReminders
  // 함수역할:
  // - 계정 정리 순서를 검사하도록 예약 복약 알림 전체 취소 여부를 기록한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 전체 취소 플래그 설정 완료.
  @override
  Future<void> cancelAllScheduledMedicationReminders() async {
    canceledAllMedicationReminders = true;
  }

  // 함수이름: showLinkedChatAlert
  // 함수역할:
  // - 복약 대화 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // - messageKind (String?): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
  // - messagePreview (String?): 알림 인터페이스로 전달하는 선택적 채팅 미리보기. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showLinkedChatAlert({
    required int id,
    required int linkId,
    String language = 'ko',
    String? messageKind,
    String? messagePreview,
    String? slotKey,
  }) async {}

  final bool failRegistration;
  bool canceledAllMedicationReminders = false;
  final List<int> canceledIds = [];
  final List<String> registeredSlotKeys = [];
  final List<List<String>> registeredMedicationNames = [];
  final List<List<DateTime>> registeredActiveDates = [];

  // Function Name: _FakeNotificationService
  // Description:
  // - Choose whether the notification spy rejects registration attempts.
  // Parameters:
  // - failRegistration (bool): Whether local notification registration should throw.
  // Returns:
  // - A recording notification service with the requested failure mode.
  _FakeNotificationService({this.failRegistration = false});

  // Function Name: initialize
  // Description:
  // - Skip real notification-plugin initialization while satisfying the platform interface.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> initialize() async {}

  // Function Name: requestPermission
  // Description:
  // - Grant notification permission in the fake without invoking an OS permission prompt.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool> resolving to true.
  @override
  Future<bool> requestPermission() async => true;

  // Function Name: registerNotification
  // Description:
  // - Record registered slots, medication names, and dates, then optionally reject local registration.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
  // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
  //   fixture.
  // - medicationNames (List<String>): Medication names eligible for this reminder.
  // - activeDates (List<DateTime>): Dates on which this dose is active.
  // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
  //   Accepted but not consumed by this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - Completion on success; StateError when failRegistration is enabled.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) async {
    registeredSlotKeys.add(slotKey);
    registeredMedicationNames.add(medicationNames);
    registeredActiveDates.add(activeDates);
    if (failRegistration) {
      throw StateError('Simulated local notification failure.');
    }
  }

  // 함수이름: cancelReminder
  // 함수역할:
  // - 개별 취소 식별자를 기록해 알림 롤백 대상을 검사할 수 있게 한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 취소 기록 추가 완료.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {
    canceledIds.add(id);
  }

  // Function Name: cancelAllMedicationReminders
  // Description:
  // - Record that all medication reminders were canceled before account cleanup.
  // Parameters:
  // - None.
  // Returns:
  // - Completion after setting the cancellation flag.
  @override
  Future<void> cancelAllMedicationReminders() async {
    canceledAllMedicationReminders = true;
  }

  // Function Name: snoozeMedicationReminder
  // Description:
  // - Accept the snooze action without scheduling a real delayed notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // - delay (Duration): Requested snooze interval or retry-wait callback. Accepted but not consumed by
  //   this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
  }) async {}

  // 함수이름: showCaregiverAlert
  // 함수역할:
  // - 보호자 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
  // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
  // - patientHash (String?): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
    String? patientHash,
    String language = 'ko',
  }) async {}
}
