// 파일명: medication_regimen_model_control_test.dart
// 역할: 정기·필요시 복용 정보의 모델 호환, 일정 유효 기간과 변경 요청 계약을 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_dose_rhythm.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_saved_medication_view_model.dart';

// 기본값 호환과 저장 요청에 사용하는 최소 MedicationDetail이며 약 ID는 7이다.
const _medication = MedicationDetail(
  id: 7,
  itemName: 'Test',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

// Function Name: main
// Description:
// - Initialize the widget binding and register regimen compatibility, request validation, concurrency, schedule recovery, and image-copy tests.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 함수이름: 이전 모델 기본값과 새 약 관리 정보가 JSON 왕복에서 유지된다
  // 함수역할:
  // - 최소 구형 JSON은 정기 복용·버전 0으로 복원되고, 필요시 모드·버전·후속 약 ID·적용일과 중단일은 왕복 후 유지되며 저장용 JSON에는 버전을 넣지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  test('이전 모델 기본값과 새 약 관리 정보가 JSON 왕복에서 유지된다', () {
    final legacy = MedicationDetail.fromJson({'id': 7, 'item_name': 'Test'});
    expect(legacy.dosingMode, 'scheduled');
    expect(legacy.regimenRevision, 0);
    expect(legacy.isAsNeeded, isFalse);
    final original = legacy.copyWith(
      dosingMode: 'as_needed',
      regimenRevision: 2,
      stoppedOn: DateTime(2026, 10, 20),
      supersededById: 8,
      regimenEffectiveFrom: DateTime(2026, 10, 18),
    );
    final copy = MedicationDetail.fromJson(
      original.toJson(),
    ).copyWith(itemName: 'Test 2');
    expect(copy.isAsNeeded, isTrue);
    expect(copy.regimenRevision, 2);
    expect(copy.supersededById, 8);
    expect(copy.stoppedOn, DateTime(2026, 10, 20));
    expect(copy.isActiveOn(DateTime(2026, 10, 17)), isFalse);
    expect(copy.isActiveOn(DateTime(2026, 10, 18)), isTrue);
    expect(copy.isActiveOn(DateTime(2026, 10, 20)), isFalse);
    expect(copy.toSaveJson().containsKey('regimen_revision'), isFalse);
  });

  // Match the server rule: supplemental PRN dose wording must not erase a regular schedule.
  for (final (frequency, dosage, slots, expected) in [
    ('1일 3회', '1정 (통증 시 2정)', <String>[], false),
    ('1일 2회 아침 저녁', '1정, 필요시 1정 추가', <String>[], false),
    ('', '1정(필요시)', ['morning', 'evening'], false),
    ('', '1정(필요시)', <String>[], true),
    ('1일 3회 필요시', '1정', ['morning'], true),
  ]) {
    // Function Name: 1회량의 필요시 표현은 정기 횟수나 시간대가 없을 때만 필요시로 본다: $frequency / $dosage
    // Description:
    // - Keep both detail and schedule models scheduled when PRN wording appears only in the dose alongside a regular frequency or slots; infer PRN when those cues are absent or frequency explicitly says as needed.
    // Parameters:
    // - None.
    // Returns:
    // - void; no return value.
    test('1회량의 필요시 표현은 정기 횟수나 시간대가 없을 때만 필요시로 본다: $frequency / $dosage', () {
      final detail = MedicationDetail.fromJson({
        'id': 7,
        'item_name': 'Test',
        'dosing_mode': 'scheduled',
        'daily_frequency': frequency,
        'dosage_per_time': dosage,
        'schedule_slot_keys': slots,
      });
      expect(detail.isAsNeeded, expected);
      final schedule = MedicationSchedule.fromScheduleJson({
        'medication_id': '7',
        'drug_name': 'Test',
        'dosing_mode': 'scheduled',
        'daily_frequency': frequency,
        'dosage_per_time': dosage,
        'schedule_slot_keys': slots,
      });
      expect(schedule.isAsNeeded, expected);
    });
  }

  for (final instruction in ['필요시 복용', '통증 시', 'PRN', 'as needed', '증상 있을 때']) {
    // 함수이름: 이전 데이터의 필요시 지시도 자동 일정으로 만들지 않는다: $instruction
    // 함수역할:
    // - 한국어·영어의 구형 필요시 지시는 기존 아침 시간대와 상태가 있어도 자동 일정을 제거하고, JSON 왕복·복사 후에도 필요시 분류와 영어 라벨을 유지하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - void; 반환값 없음.
    test('이전 데이터의 필요시 지시도 자동 일정으로 만들지 않는다: $instruction', () {
      final schedule = MedicationSchedule.fromScheduleJson({
        'medication_id': '7',
        'drug_name': 'Test',
        'daily_frequency': instruction,
        'schedule_slot_keys': ['morning'],
        'slot_statuses': {'morning': false},
      });
      expect(schedule.isAsNeeded, isTrue);
      expect(schedule.slotKeys, isEmpty);
      expect(schedule.isDoseDay(DateTime(2026, 10, 17)), isFalse);
      expect(
        MedicationSchedule.fromScheduleJson(
          schedule.toJson(),
        ).copyWith(dosage: '2정').isAsNeeded,
        isTrue,
      );
      expect(schedule.dailyFrequencyLabelForLanguage('en'), 'As needed');
    });
  }

  // 함수이름: 정기 약의 중단일과 적용일이 일정 캐시에도 유지된다
  // 함수역할:
  // - 정기 일정의 JSON 캐시 왕복과 복사 후에도 버전을 유지하고, 적용일은 포함하되 중단일부터는 복용일로 판정하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  test('정기 약의 중단일과 적용일이 일정 캐시에도 유지된다', () {
    final schedule = MedicationSchedule(
      medicationName: 'Test',
      regimenRevision: 3,
      regimenEffectiveFrom: DateTime(2026, 10, 18),
      stoppedOn: DateTime(2026, 10, 20),
    );
    final copy = MedicationSchedule.fromScheduleJson(
      schedule.toJson(),
    ).copyWith(dosage: '1정');
    expect(copy.regimenRevision, 3);
    expect(copy.isDoseDay(DateTime(2026, 10, 17)), isFalse);
    expect(copy.isDoseDay(DateTime(2026, 10, 18)), isTrue);
    expect(copy.isDoseDay(DateTime(2026, 10, 20)), isFalse);
  });

  // 함수이름: 다음 복용일은 중단일 이후로 안내하지 않는다
  // 함수역할:
  // - 주 1회 처방에서 다음 예정일이 중단일 이후라면 다음 복용일을 반환하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  test('다음 복용일은 중단일 이후로 안내하지 않는다', () {
    final medication = _medication.copyWith(
      prescriptionDate: DateTime(2026, 10, 1),
      dailyFrequency: '주 1회',
      totalDays: '30일',
      stoppedOn: DateTime(2026, 10, 10),
    );
    expect(medication.nextDoseDayFrom(DateTime(2026, 10, 9)), isNull);
  });

  // 함수이름: 직접 등록 필요시 복용은 빈 시간대와 모드를 전달한다
  // 함수역할:
  // - 직접 등록된 필요시 항목에 아침 시간대가 남아 있어도 일정 변환 시 제거하고 상세 모델에서도 필요시 모드를 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  test('직접 등록 필요시 복용은 빈 시간대와 모드를 전달한다', () {
    final entry = ManualMedicationEntry(
      medicationName: 'Test',
      dosageAmount: '1',
      dosageUnit: '정',
      startDate: DateTime(2026, 10, 17),
      endDate: DateTime(2026, 10, 20),
      scheduleSlotKeys: ['morning'],
      dosingMode: 'as_needed',
    );
    final schedule = entry.toMedicationSchedule();
    expect(schedule.isAsNeeded, isTrue);
    expect(schedule.slotKeys, isEmpty);
    expect(
      MedicationDetail.fromMedicationSchedule(schedule).isAsNeeded,
      isTrue,
    );
  });

  // 함수이름: 복잡한 지시는 확인 필요로 남기고 기존의 일반 주기는 유지한다
  // 함수역할:
  // - 일반 횟수·격일·요일·8시간 간격은 기존 해석을 유지하고, 감량·조절 지시와 지원하지 않는 120일·5시간 간격은 검토 대상으로 분류하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  test('복잡한 지시는 확인 필요로 남기고 기존의 일반 주기는 유지한다', () {
    for (final value in [
      '',
      '3회',
      '3 times',
      '1일 3회 식후 30분',
      '격일',
      '주 1회',
      '월수금',
      '8시간마다',
    ]) {
      expect(requiresDoseScheduleReview(value), isFalse, reason: value);
    }
    for (final value in [
      '3일간 2정 후 1정으로 감량',
      '처방 지시에 따라 조절',
      'every 120 days',
      '5시간마다',
    ]) {
      expect(requiresDoseScheduleReview(value), isTrue, reason: value);
    }
  });

  // 함수이름: 필요시 저장은 고정 시간대를 보내지 않는다
  // 함수역할:
  // - 필요시 일정 저장 요청은 남아 있는 아침 시간대를 제거하고 as_needed와 빈 schedule_slot_keys를 전송하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('필요시 저장은 고정 시간대를 보내지 않는다', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true,"id":7}', 200);
    });
    addTearDown(client.close);
    final control = CheckSavedMedication(client: client);
    final result = await control.saveMedicationDetail(
      _medication,
      medicationSchedule: const MedicationSchedule(
        medicationName: 'Test',
        dosingMode: 'as_needed',
        intakeTime: '1회',
        scheduleSlotKeys: ['morning'],
      ),
    );
    expect(result.isCompleted, isTrue);
    expect(body['dosing_mode'], 'as_needed');
    expect(body['schedule_slot_keys'], isEmpty);
  });

  // 함수이름: 해석되지 않은 복용 지시는 저장 요청 전에 차단한다
  // 함수역할:
  // - 단계적 감량처럼 해석되지 않은 복용 지시는 HTTP 요청을 보내기 전에 미완료 저장 결과로 차단하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('해석되지 않은 복용 지시는 저장 요청 전에 차단한다', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final result = await CheckSavedMedication(client: client)
        .saveMedicationDetail(
          _medication.copyWith(dailyFrequency: '3일간 2정 후 1정으로 감량'),
        );
    expect(result.isCompleted, isFalse);
    expect(calls, 0);
  });

  // 함수이름: 변경 요청은 적용일과 버전을 보내며 재시도에도 UUID와 본문을 유지한다
  // 함수역할:
  // - 변경 요청이 대상 경로·환자·날짜·버전과 UUID v4를 포함하고, 외부 시간대 목록이 바뀌어도 최초 본문 스냅샷을 재시도에 그대로 쓰는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('변경 요청은 적용일과 버전을 보내며 재시도에도 UUID와 본문을 유지한다', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://medbuddy.test/care/medications/7/change',
      );
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"success":true,"id":8,"revision":3}', 200);
    });
    addTearDown(client.close);
    final control = CheckSavedMedication(
      baseUrl: 'https://medbuddy.test',
      patientHash: 'patient-a',
      client: client,
    );
    final slots = ['morning'];
    final change = MedicationRegimenChange(
      action: MedicationRegimenAction.edit,
      effectiveDate: DateTime(2026, 10, 18, 12),
      expectedRevision: 2,
      changes: {'schedule_slot_keys': slots, 'dosing_mode': 'scheduled'},
    );
    slots.add('evening');
    expect((await control.changeRegimen(7, change)).success, isTrue);
    expect((await control.changeRegimen(7, change)).medicationId, 8);
    expect(bodies.first, bodies.last);
    expect(bodies.first['expected_revision'], 2);
    expect(bodies.first['effective_date'], '2026-10-18');
    expect(bodies.first['patient_hash'], 'patient-a');
    expect((bodies.first['changes'] as Map)['schedule_slot_keys'], ['morning']);
    expect(
      change.operationId,
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
  });

  for (final entry in {
    409: MedicationRegimenFailure.conflict,
    403: MedicationRegimenFailure.forbidden,
    404: MedicationRegimenFailure.missing,
    422: MedicationRegimenFailure.invalid,
    503: MedicationRegimenFailure.network,
  }.entries) {
    // 함수이름: 변경 오류를 성공으로 처리하지 않는다: ${entry.key}
    // 함수역할:
    // - HTTP 409·403·404·422·503 응답을 각각 충돌·권한·누락·잘못된 요청·네트워크 실패로 구분하고 성공으로 처리하지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
    test('변경 오류를 성공으로 처리하지 않는다: ${entry.key}', () async {
      final client = MockClient(
        (_) async => http.Response('{"detail":"test"}', entry.key),
      );
      addTearDown(client.close);
      final result = await CheckSavedMedication(
        client: client,
      ).changeRegimen(7, _change());
      expect(result.success, isFalse);
      expect(result.failure, entry.value);
    });
  }

  // 함수이름: 성공 필드가 누락된 응답도 결과 미확인으로 남긴다
  // 함수역할:
  // - HTTP 200과 success=true만 있고 약 ID·버전이 빠진 응답은 확인된 성공 대신 네트워크 실패로 남기는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('성공 필드가 누락된 응답도 결과 미확인으로 남긴다', () async {
    final client = MockClient(
      (_) async => http.Response('{"success":true}', 200),
    );
    addTearDown(client.close);
    expect(
      (await CheckSavedMedication(
        client: client,
      ).changeRegimen(7, _change())).failure,
      MedicationRegimenFailure.network,
    );
  });

  // 함수이름: 기록이 있는 적용일 충돌은 날짜 수정이 가능한 오류로 구분한다
  // 함수역할:
  // - 복용 기록이 존재하는 날짜라는 409 응답을 일반 버전 충돌과 구분하여 날짜 수정이 가능한 recordedDate 실패로 반환하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('기록이 있는 적용일 충돌은 날짜 수정이 가능한 오류로 구분한다', () async {
    final client = MockClient((_) async => http.Response('{"detail":"This date already has dose records. Choose a later effective date to preserve them."}', 409));
    addTearDown(client.close);
    expect((await CheckSavedMedication(client: client).changeRegimen(7, _change())).failure, MedicationRegimenFailure.recordedDate);
  });

  // 함수이름: 한 약에 다른 변경 요청이 겹쳐도 첫 요청의 성공을 재사용하지 않는다
  // 함수역할:
  // - 한 약의 첫 변경이 대기 중일 때 다른 작업 ID의 요청은 충돌로 거절하고 서버 호출이나 첫 결과 공유를 늘리지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('한 약에 다른 변경 요청이 겹쳐도 첫 요청의 성공을 재사용하지 않는다', () async {
    final control = _PendingControl();
    final model = _model(control, []);
    addTearDown(model.dispose);
    final first = model.changeMedicationRegimen(7, _change());
    final second = await model.changeMedicationRegimen(7, _change());
    expect(second.failure, MedicationRegimenFailure.conflict);
    expect(control.changes, 1);
    control.response.complete(const MedicationRegimenResult(medicationId: 7, revision: 1));
    await first;
  });

  // 함수이름: 동일 요청 중복을 합치고 저장 후 목록·일정·알림 순서로 갱신한다
  // 함수역할:
  // - 같은 변경 객체의 동시 호출은 하나의 Future와 서버 요청을 공유하고, 성공 후 목록을 한 번 다시 읽은 뒤 일정·알림 갱신을 순서대로 수행하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('동일 요청 중복을 합치고 저장 후 목록·일정·알림 순서로 갱신한다', () async {
    final control = _PendingControl();
    final events = <String>[];
    final model = _model(control, events);
    addTearDown(model.dispose);
    final change = _change();
    final first = model.changeMedicationRegimen(7, change);
    final duplicate = model.changeMedicationRegimen(7, change);
    expect(identical(first, duplicate), isTrue);
    // 기기 일정 무효화가 끝나야 서버 변경 요청이 시작된다.
    await Future<void>.delayed(Duration.zero);
    expect(control.changes, 1);
    control.response.complete(
      const MedicationRegimenResult(medicationId: 8, revision: 1),
    );
    expect((await first).success, isTrue);
    expect(control.loads, 1);
    expect(events, ['schedule', 'reminders']);
  });

  // Restore the suspended device plan after an unapplied failure; success and conflicts require a refresh.
  for (final (label, result, expected) in [
    (
      'network failure restores',
      const MedicationRegimenResult(failure: MedicationRegimenFailure.network),
      ['suspend', 'restore:backup'],
    ),
    (
      'invalid request restores',
      const MedicationRegimenResult(failure: MedicationRegimenFailure.invalid),
      ['suspend', 'restore:backup'],
    ),
    (
      'success invalidates',
      const MedicationRegimenResult(medicationId: 8, revision: 1),
      ['suspend', 'invalidate', 'schedule', 'reminders'],
    ),
    (
      'conflict invalidates',
      const MedicationRegimenResult(failure: MedicationRegimenFailure.conflict),
      ['suspend', 'invalidate', 'schedule', 'reminders'],
    ),
  ]) {
    // Function Name: the device schedule after a regimen change: $label
    // Description:
    // - Suspend the device schedule before a change; restore its backup after network/invalid failures, but invalidate and refresh schedule/reminders after success or a revision conflict.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
    test('the device schedule after a regimen change: $label', () async {
      final control = _PendingControl();
      final events = <String>[];
      final model = _model(control, events, trackSchedule: true);
      addTearDown(model.dispose);
      final pending = model.changeMedicationRegimen(7, _change());
      await Future<void>.delayed(Duration.zero);
      control.response.complete(result);
      await pending;
      expect(events, expected);
    });
  }

  // 함수이름: 계정 초기화 이후 완료된 변경은 이전 계정 갱신을 실행하지 않는다
  // 함수역할:
  // - 계정 상태를 지운 뒤 늦게 완료된 변경은 취소 결과로 처리하고 이전 계정의 목록·일정·알림을 갱신하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('계정 초기화 이후 완료된 변경은 이전 계정 갱신을 실행하지 않는다', () async {
    final control = _PendingControl();
    final events = <String>[];
    final model = _model(control, events);
    addTearDown(model.dispose);
    final future = model.changeMedicationRegimen(7, _change());
    model.clear();
    control.response.complete(
      const MedicationRegimenResult(medicationId: 8, revision: 1),
    );
    expect((await future).failure, MedicationRegimenFailure.cancelled);
    expect(control.loads, 0);
    expect(events, isEmpty);
    expect(model.medications, isEmpty);
  });

  // Function Name: 같은 약의 변경만 기기 사진을 새 약 ID로 이어 붙인다
  // Description:
  // - Copy a local medication image from the old ID to the returned ID only for editing the same medicine, never for replacement or stopping.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('같은 약의 변경만 기기 사진을 새 약 ID로 이어 붙인다', () async {
    for (final (action, expected) in [
      (MedicationRegimenAction.edit, ['patient-a:7>8']),
      (MedicationRegimenAction.replace, <String>[]),
      (MedicationRegimenAction.stop, <String>[]),
    ]) {
      final control = _PendingControl();
      final store = _CopyRecordingImageStore();
      final model = _model(control, [], imageStore: store);
      addTearDown(model.dispose);
      final future = model.changeMedicationRegimen(7, _change(action: action));
      control.response.complete(
        const MedicationRegimenResult(medicationId: 8, revision: 1),
      );
      expect((await future).success, isTrue);
      expect(store.copies, expected, reason: action.name);
    }
  });

  // 함수이름: 갱신 실패를 변경 저장 실패로 오해하여 중복 제출하지 않는다
  // 함수역할:
  // - 서버 변경 저장이 성공한 뒤 일정 갱신이 실패하면 저장 성공은 유지하고 refreshFailed를 표시하여 같은 변경을 다시 제출하게 만들지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('갱신 실패를 변경 저장 실패로 오해하여 중복 제출하지 않는다', () async {
    final control = _PendingControl();
    final events = <String>[];
    final model = _model(control, events, failRefresh: true);
    addTearDown(model.dispose);
    final future = model.changeMedicationRegimen(7, _change());
    control.response.complete(
      const MedicationRegimenResult(medicationId: 8, revision: 1),
    );
    final result = await future;
    expect(result.success, isTrue);
    expect(result.refreshFailed, isTrue);
  });
}

// Class Name: _CopyRecordingImageStore
// Role: Image-store double recording copy requests without touching image files.
// Responsibilities:
// - Expose patient-scoped source and destination IDs for regimen-change assertions.
// Attributes:
// - copies (List<String>): recorded patientHash:fromMedicationId>toMedicationId entries.
class _CopyRecordingImageStore extends ManualMedicationImageStore {
  final copies = <String>[];
  // Function Name: copyImage
  // Description:
  // - Record the patient and medication ID pair without copying an image.
  // Parameters:
  // - patientHash (String): owner of the image mapping.
  // - fromMedicationId (int): original medication ID.
  // - toMedicationId (int): returned medication ID.
  // Returns:
  // - Future<void>; completes after appending the copy record.
  @override
  Future<void> copyImage({
    required String patientHash,
    required int fromMedicationId,
    required int toMedicationId,
  }) async {
    copies.add('$patientHash:$fromMedicationId>$toMedicationId');
  }
}

// Function Name: _change
// Description:
// - Create a fresh operation ID for a fixed-date, revision-zero regimen change.
// Parameters:
// - action (MedicationRegimenAction): requested operation, defaulting to stop.
// Returns:
// - MedicationRegimenChange; October 18, 2026 effective date with no field changes.
MedicationRegimenChange _change({
  MedicationRegimenAction action = MedicationRegimenAction.stop,
}) => MedicationRegimenChange(
  action: action,
  effectiveDate: DateTime(2026, 10, 18),
  expectedRevision: 0,
);

// 클래스명: _PendingControl
// 역할: 약 변경 응답 완료 시점을 테스트에서 제어하는 컨트롤 대역.
// 주요 책임:
// - 변경·목록 조회 횟수를 기록하고 공유 Completer로 동시 요청과 늦은 응답을 재현한다.
// 속성:
// - response (Completer<MedicationRegimenResult>): 테스트에서 완료할 공통 변경 응답.
// - changes (int): 변경 요청 횟수.
// - loads (int): 저장된 약 목록 조회 횟수.
class _PendingControl extends CheckSavedMedication {
  final response = Completer<MedicationRegimenResult>();
  int changes = 0;
  int loads = 0;
  // 함수이름: changeRegimen
  // 함수역할:
  // - 호출 횟수를 늘리고 미리 준비한 응답 Future를 반환하여 테스트가 완료 시점을 정하게 한다.
  // 매개변수:
  // - medicationId (int): 인터페이스상 대상 약 ID로, 대역은 값을 사용하지 않는다.
  // - change (MedicationRegimenChange): 전달된 변경 요청으로, 대역은 내용을 검사하지 않는다.
  // 반환값:
  // - Future<MedicationRegimenResult>; response가 완료될 때 지정된 결과 또는 오류로 끝난다.
  @override
  Future<MedicationRegimenResult> changeRegimen(
    int medicationId,
    MedicationRegimenChange change,
  ) {
    changes++;
    return response.future;
  }

  // 함수이름: requestSavedMedicationInfo
  // 함수역할:
  // - 저장 약 목록을 다시 읽은 횟수를 기록하고 빈 목록으로 응답한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationDetail>>; 빈 목록으로 완료한다.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    loads++;
    return [];
  }
}

// Function Name: _model
// Description:
// - Build a patient-scoped view model whose refresh and optional schedule-lifecycle callbacks append ordered events; register controller cleanup.
// Parameters:
// - control (_PendingControl): controllable regimen response and list-load counter.
// - events (List<String>): mutable destination for refresh and lifecycle events.
// - failRefresh (bool): make schedule refresh throw StateError after recording its event.
// - imageStore (ManualMedicationImageStore?): image-copy dependency or the default store.
// - trackSchedule (bool): install suspend/restore/invalidate callbacks with a fixed backup marker.
// Returns:
// - MedBuddySavedMedicationViewModel; configured for patient-a with Korean settings and a no-op change listener.
MedBuddySavedMedicationViewModel _model(
  _PendingControl control,
  List<String> events, {
  bool failRefresh = false,
  ManualMedicationImageStore? imageStore,
  bool trackSchedule = false,
}) {
  final details = CheckMedicationDetail();
  addTearDown(details.dispose);
  addTearDown(control.dispose);
  return MedBuddySavedMedicationViewModel(
    checkSavedMedication: control,
    checkMedicationDetail: details,
    manualMedicationImageStore: imageStore ?? ManualMedicationImageStore(),
    patientHash: 'patient-a',
    readEnglishSetting: () => false,
    fetchTodayMedicationSchedule: () async {
      events.add('schedule');
      if (failRefresh) throw StateError('failed');
    },
    invalidateSchedule: trackSchedule
        ? () async => events.add('invalidate')
        : null,
    suspendSchedule: trackSchedule
        ? () async {
            events.add('suspend');
            return 'backup';
          }
        : null,
    restoreSchedule: trackSchedule
        ? (backup) async => events.add('restore:$backup')
        : null,
    synchronizeReminders: () async {
      events.add('reminders');
    },
    onChanged: (_) {},
  );
}
