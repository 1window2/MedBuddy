// 파일명: photo_dose_view_model_test.dart
// 역할: 사진으로 복용 기록 전후의 앱 상태 처리(겹치는 미전송 기록 감지, 기록 뒤 오늘 일정·기록 신호 갱신)를 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/photo_dose_plan_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dose_sync_harness.dart';
import 'support/fake_notification_service.dart';

final _now = DateTime.utc(2026, 10, 25, 3);
const _day = '2026-10-25';

PhotoDosePlan _plan(
  List<int> ids, {
  String slot = 'morning',
  String day = _day,
}) => PhotoDosePlan.fromJson({
  'success': true,
  'plan_token': 'MjAyNi0xMC0yNVQxMjowMDowMCswOTowMA.abcdef0123456789',
  'as_of': '2026-10-25T12:00:00+09:00',
  'pills': [],
  'groups': [
    {
      'schedule_date': day,
      'slot_key': slot,
      'reminder_at': '${day}T08:00:00+09:00',
      'timing': 'late',
      'medication_ids': ids,
    },
  ],
  'as_needed': [],
  'medications': [],
  'write': {
    'groups': [],
    'as_needed_medication_ids': [],
    'regimen_revisions': {},
  },
  'ready': true,
});

MedicationSchedule _schedule(String id, bool morningTaken) =>
    MedicationSchedule(
      medicationID: id,
      medicationName: 'tablet-$id',
      scheduleSlotKeys: const ['morning'],
      slotStatuses: {'morning': morningTaken},
    );

void main() {
  test(
    'an unsent record for the same day, slot and medicine blocks the photo',
    () async {
      SharedPreferences.setMockInitialValues({});
      final viewModel = MedBuddyViewModel(
        notificationService: RecordingNotificationService(),
      );
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      await harness.seedSchedules([
        _schedule('7', true),
        _schedule('8', false),
      ]);
      // 오프라인에서 아침 7번 복용을 취소해 둔 기록이 큐에 남아 있다.
      await harness.service.record(
        medicationIds: const [7],
        slotKey: 'morning',
        completed: false,
      );
      expect(await harness.pending(), isNotEmpty);

      expect(viewModel.hasPendingDoseOverlap(_plan([7])), isTrue);
      expect(viewModel.hasPendingDoseOverlap(_plan([8])), isFalse);
      expect(
        viewModel.hasPendingDoseOverlap(_plan([7], slot: 'evening')),
        isFalse,
      );
      expect(
        viewModel.hasPendingDoseOverlap(_plan([7], day: '2026-10-24')),
        isFalse,
      );
    },
  );

  test(
    'recording replaces today\'s schedule and signals history readers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final viewModel = MedBuddyViewModel(
        notificationService: RecordingNotificationService(),
      );
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      await harness.seedSchedules([_schedule('7', false)]);
      expect(viewModel.todayMedicationProgress.completedCount, 0);
      final before = viewModel.savedDoseRecords.value;

      await viewModel.recordPhotoDose(
        PhotoDoseRecordResult(
          operationId: 'op',
          takenAt: DateTime(2026, 10, 25, 12),
          scheduleDate: _day,
          todaySchedule: [_schedule('7', true).toJson()],
        ),
      );

      expect(viewModel.todayMedicationProgress.completedCount, 1);
      expect(viewModel.savedDoseRecords.value, before + 1);
    },
  );

  test('own medicines are required before opening the camera', () {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      notificationService: RecordingNotificationService(),
    );
    addTearDown(viewModel.dispose);
    expect(viewModel.hasOwnMedicinesForPhotoDose, isFalse);
  });
}
