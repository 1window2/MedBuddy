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

const _medication = MedicationDetail(
  id: 7,
  itemName: 'Test',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // 정기 복용약의 1회량에 붙은 추가 복용 안내 때문에 일정과 알림이 사라지지 않아야 한다(서버와 같은 규칙).
  for (final (frequency, dosage, slots, expected) in [
    ('1일 3회', '1정 (통증 시 2정)', <String>[], false),
    ('1일 2회 아침 저녁', '1정, 필요시 1정 추가', <String>[], false),
    ('', '1정(필요시)', ['morning', 'evening'], false),
    ('', '1정(필요시)', <String>[], true),
    ('1일 3회 필요시', '1정', ['morning'], true),
  ]) {
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

  test('다음 복용일은 중단일 이후로 안내하지 않는다', () {
    final medication = _medication.copyWith(
      prescriptionDate: DateTime(2026, 10, 1),
      dailyFrequency: '주 1회',
      totalDays: '30일',
      stoppedOn: DateTime(2026, 10, 10),
    );
    expect(medication.nextDoseDayFrom(DateTime(2026, 10, 9)), isNull);
  });

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

  test('기록이 있는 적용일 충돌은 날짜 수정이 가능한 오류로 구분한다', () async {
    final client = MockClient((_) async => http.Response('{"detail":"This date already has dose records. Choose a later effective date to preserve them."}', 409));
    addTearDown(client.close);
    expect((await CheckSavedMedication(client: client).changeRegimen(7, _change())).failure, MedicationRegimenFailure.recordedDate);
  });

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

  test('동일 요청 중복을 합치고 저장 후 목록·일정·알림 순서로 갱신한다', () async {
    final control = _PendingControl();
    final events = <String>[];
    final model = _model(control, events);
    addTearDown(model.dispose);
    final change = _change();
    final first = model.changeMedicationRegimen(7, change);
    final duplicate = model.changeMedicationRegimen(7, change);
    expect(identical(first, duplicate), isTrue);
    expect(control.changes, 1);
    control.response.complete(
      const MedicationRegimenResult(medicationId: 8, revision: 1),
    );
    expect((await first).success, isTrue);
    expect(control.loads, 1);
    expect(events, ['schedule', 'reminders']);
  });

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

class _CopyRecordingImageStore extends ManualMedicationImageStore {
  final copies = <String>[];
  @override
  Future<void> copyImage({
    required String patientHash,
    required int fromMedicationId,
    required int toMedicationId,
  }) async {
    copies.add('$patientHash:$fromMedicationId>$toMedicationId');
  }
}

MedicationRegimenChange _change({
  MedicationRegimenAction action = MedicationRegimenAction.stop,
}) => MedicationRegimenChange(
  action: action,
  effectiveDate: DateTime(2026, 10, 18),
  expectedRevision: 0,
);

class _PendingControl extends CheckSavedMedication {
  final response = Completer<MedicationRegimenResult>();
  int changes = 0;
  int loads = 0;
  @override
  Future<MedicationRegimenResult> changeRegimen(
    int medicationId,
    MedicationRegimenChange change,
  ) {
    changes++;
    return response.future;
  }

  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    loads++;
    return [];
  }
}

MedBuddySavedMedicationViewModel _model(
  _PendingControl control,
  List<String> events, {
  bool failRefresh = false,
  ManualMedicationImageStore? imageStore,
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
    synchronizeReminders: () async {
      events.add('reminders');
    },
    onChanged: (_) {},
  );
}
