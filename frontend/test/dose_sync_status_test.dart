// File Name: dose_sync_status_test.dart
// Role: Checks pending, rejected and lost-dose notices and actions against real outbox state.
// The production DoseSyncService and outbox store on in-memory SQLite; synthetic data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/widgets/dose_sync_status.dart';

import 'support/dose_sync_harness.dart';
import 'support/fake_controls.dart';

const _medication = MedicationSchedule(
  medicationID: '91',
  medicationName: '테스트정',
  scheduleSlotKeys: ['morning'],
  slotStatuses: {'morning': false},
);

// Function Name: _queueMorningDose
// Description:
// - Attaches production dose synchronization, seeds one medication and queues its morning completion against the default offline responder.
// Parameters:
// - None.
// Returns:
// - Future<DoseSyncHarness>: Harness with one pending dose.
Future<DoseSyncHarness> _queueMorningDose() async {
  final harness = await attachTestDoseSync(
    MedBuddyViewModel(
      checkSchedule: EmptyCheckSchedule(),
      setNotification: EmptySetNotification(),
    ),
  );
  await harness.seedSchedules(const [_medication]);
  expect(
    await harness.service.record(
      medicationIds: [91],
      slotKey: 'morning',
      completed: true,
      medicationNames: ['테스트정'],
    ),
    isTrue,
  );
  await harness.service.drain();
  return harness;
}

// Function Name: _pumpStatus
// Description:
// - Mounts the synchronization status widget at the bottom of a test scaffold and advances one frame.
// Parameters:
// - tester (WidgetTester): Widget driver.
// - service (DoseSyncService): Live status source.
// - isEnglish (bool): Selects the displayed language.
// Returns:
// - Future<void>: Widget is mounted and pumped.
Future<void> _pumpStatus(
  WidgetTester tester,
  DoseSyncService service, {
  required bool isEnglish,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: DoseSyncStatus(service: service, isEnglish: isEnglish),
        ),
      ),
    ),
  );
  await tester.pump();
}

// Function Name: main
// Description:
// - Registers empty, pending, rejected, retried and lost-dose status UI cases.
// Parameters:
// - None.
// Returns:
// - No value; registers widget tests.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Renders no list tile and takes zero height when there are no pending operations or losses.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('nothing is shown while every record is on the server', (
    tester,
  ) async {
    final harness = await attachTestDoseSync(
      MedBuddyViewModel(
        checkSchedule: EmptyCheckSchedule(),
        setNotification: EmptySetNotification(),
      ),
    );

    await _pumpStatus(tester, harness.service, isEnglish: false);

    expect(find.byType(ListTile), findsNothing);
    expect(tester.getSize(find.byType(DoseSyncStatus)).height, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });

  for (final isEnglish in [false, true]) {
    // Function Name: testWidgets callback
    // Description:
    // - Shows one waiting dose and its medication, date, localized slot and taken status in the detail sheet without a delete action.
    // Parameters:
    // - tester (WidgetTester): Drives the widget tree and advances the test clock.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    testWidgets('a waiting record is listed with its slot name (english=$isEnglish)', (
      tester,
    ) async {
      final harness = await _queueMorningDose();
      final day = harness.queued.single['schedule_date'];

      await _pumpStatus(tester, harness.service, isEnglish: isEnglish);

      expect(
        find.text(
          isEnglish ? '1 dose records waiting to sync' : '복용 기록 1건 전송 대기',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text(isEnglish ? 'Dose sync' : '복용 기록 전송'), findsOneWidget);
      expect(find.text('테스트정'), findsOneWidget);
      // 영어 화면에서도 시간대 키(morning)가 아니라 다른 화면과 같은 이름을 쓴다.
      expect(
        find.text(
          isEnglish
              ? '$day · Morning · Taken\nSaved on this device. Waiting to sync.'
              : '$day · 아침 · 복용\n기기에 저장됨 · 서버 전송 대기',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await harness.close();
    });
  }

  // Function Name: testWidgets callback
  // Description:
  // - Displays a rejected dose as needing attention, retains it after canceling deletion and removes it only after confirmation.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('a rejected record needs attention and is removed only on confirmation', (
    tester,
  ) async {
    final harness = await _queueMorningDose();
    harness.respond = (_) async => http.Response('rejected', 409);
    await harness.service.drain();
    expect(harness.service.hasBlocked, isTrue);

    await _pumpStatus(tester, harness.service, isEnglish: false);

    expect(find.text('복용 기록 전송 확인 필요'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('일정 또는 연동이 변경되어 서버에 저장하지 못했습니다.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('저장되지 않은 기록 지우기'));
    await tester.pumpAndSettle();
    expect(find.text('저장되지 않은 기록을 지울까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(await harness.pending(), hasLength(1));

    await tester.tap(find.byTooltip('저장되지 않은 기록 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();

    expect(await harness.pending(), isEmpty);
    expect(find.text('서버에 모두 저장했습니다.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });

  // Function Name: testWidgets callback
  // Description:
  // - Retries one rejected operation from the sheet and clears it after a successful receipt, displaying the saved confirmation.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('retry sends a rejected record again', (tester) async {
    final harness = await _queueMorningDose();
    harness.respond = (_) async => http.Response('rejected', 409);
    await harness.service.drain();
    final attempts = harness.uploads.length;

    await _pumpStatus(tester, harness.service, isEnglish: true);
    expect(find.text('Dose sync needs attention'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    harness.respond = (request) async => doseSyncReceipt(request, [
      _medication.copyWith(slotStatuses: {'morning': true}),
    ]);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();

    expect(harness.uploads.length, attempts + 1);
    expect(await harness.pending(), isEmpty);
    expect(find.text('All records saved to server.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });

  for (final isEnglish in [false, true]) {
    // Function Name: testWidgets callback
    // Description:
    // - Shows the account's two unrecoverable records in either language and clears the stored count when the notice is dismissed.
    // Parameters:
    // - tester (WidgetTester): Drives the widget tree and advances the test clock.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    testWidgets('lost records are announced until dismissed (english=$isEnglish)', (
      tester,
    ) async {
      final harness = await attachTestDoseSync(
        MedBuddyViewModel(
          checkSchedule: EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
        ),
      );
      // 키 분실 복구가 남기는 것과 같은 계정별 건수 표시를 만든다.
      await harness.store.db.insert('metadata', {
        'name': 'lost:${await harness.store.ownerKey(harness.owner)}',
        'value': '2',
      });
      await harness.service.reload();

      await _pumpStatus(tester, harness.service, isEnglish: isEnglish);

      expect(
        find.text(
          isEnglish
              ? '2 dose records could not be recovered'
              : '복용 기록 2건을 복구하지 못했습니다',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      await tester.tap(find.byTooltip(isEnglish ? 'Dismiss' : '확인'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dose-sync-lost-records')), findsNothing);
      expect(await harness.store.lostOperationCount(harness.owner), 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await harness.close();
    });
  }
}
