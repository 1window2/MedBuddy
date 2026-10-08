// 파일명: dose_sync_status_test.dart
// 역할: 전송 대기·서버 거부·유실된 복용 기록 안내가 실제 대기열 상태에 맞게 표시되고 조작되는지 검증한다.
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

// 함수이름: _queueMorningDose
// 함수역할: 운영 경로의 동기화 서비스를 붙이고 아침 복용 기록 한 건을 전송 대기 상태로 만든다.
// 매개변수: 없음. 반환값: 대기 기록 한 건이 있는 테스트 하네스.
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

// 함수이름: _pumpStatus
// 함수역할: tester에 지정 언어의 전송 상태 줄을 표시한다.
// 매개변수: tester, service - 표시할 동기화 서비스, isEnglish - 영어 표시 여부. 반환값: 표시 완료 Future.
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

// 함수이름: main
// 함수역할: 전송 상태 줄과 상세 시트의 회귀 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 대기 기록이 없는 상태 테스트
  // 함수역할: 전송할 기록도 유실 안내도 없으면 아무것도 표시하지 않는지 검증한다.
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
    // 함수이름: 전송 대기 표시 테스트
    // 함수역할: 대기 건수와 상세 시트의 약 이름·날짜·시간대 이름·상태를 언어에 맞게 표시하는지 검증한다.
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

  // 함수이름: 서버 거부 기록 테스트
  // 함수역할: 서버가 거부한 기록을 확인 필요로 표시하고, 확인 대화상자를 거쳐야만 지우는지 검증한다.
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

  // 함수이름: 다시 전송 테스트
  // 함수역할: 시트의 다시 전송 버튼이 거부된 기록을 다시 보내고, 성공하면 목록에서 사라지는지 검증한다.
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
    // 함수이름: 유실 기록 안내 테스트
    // 함수역할: 기기 키 분실로 버려진 기록의 건수를 알리고, 확인하면 안내가 사라지는지 검증한다.
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
