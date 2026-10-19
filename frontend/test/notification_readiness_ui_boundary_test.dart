// 파일명: notification_readiness_ui_boundary_test.dart
// 역할: 점검 상태·실패·명시적 확인과 좁은 큰 글씨 화면을 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/notification_readiness_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

class _Control extends NotificationReadinessControl {
  _Control()
    : super(
        notificationService: NotificationService.instance,
        supportsNotifications: true,
        supportsExactAlarms: true,
        supportsSystemSettings: true,
      );
  NotificationReadinessSnapshot state = const NotificationReadinessSnapshot(
    hasMedication: true,
    notifications: true,
    medicationChannel: true,
    exactAlarms: true,
  );
  int sends = 0;
  int permissionRequests = 0;
  int refreshes = 0;
  bool failSend = false;
  Completer<void>? sendGate;
  @override
  Future<NotificationReadinessSnapshot> refresh() async {
    refreshes++;
    return state;
  }

  @override
  Future<void> sendTest(String language) async {
    sends++;
    if (sendGate != null) await sendGate!.future;
    if (failSend) throw StateError('unavailable');
  }

  @override
  Future<void> requestNotificationPermission() async {
    permissionRequests++;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Control control, {
  bool english = false,
  bool includeActions = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: NotificationReadinessUI(
        control: control,
        savedSetting: const UserSetting(),
        isEnglish: english,
        onMedicationRegistrationRequested: includeActions ? () {} : null,
        onMedicationScheduleRequested: includeActions ? () {} : null,
        onWidgetRequested: includeActions ? () async {} : null,
        onCaregiverSetupRequested: includeActions ? () {} : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, String key) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('설명 간격과 각 항목의 버튼 묶음 간격을 동일하게 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final control = _Control()
      ..state = const NotificationReadinessSnapshot(
        hasMedication: true,
        notifications: false,
        medicationChannel: false,
        exactAlarms: false,
      );
    await _open(tester, control, includeActions: true);
    final firstBody = find.textContaining('등록된 약이 있습니다');
    final secondBody = find.textContaining('보호자로만 이용한다면');
    final add = find.byKey(const ValueKey('readinessAddMedication'));
    final schedule = find.byKey(const ValueKey('readinessSchedule'));
    expect(
      tester.getTopLeft(secondBody).dy - tester.getBottomLeft(firstBody).dy,
      12,
    );
    expect(tester.getTopLeft(add).dy - tester.getBottomLeft(secondBody).dy, 20);
    expect(tester.getTopLeft(schedule).dy - tester.getBottomLeft(add).dy, 12);
    expect(tester.getSize(add).width, tester.getSize(schedule).width);
    final bodyStyle = DefaultTextStyle.of(tester.element(firstBody)).style;
    expect(bodyStyle.fontSize, 16);
    expect(bodyStyle.height, 1.5);
    final permission = find.byKey(const ValueKey('readinessRequestPermission'));
    final exact = find.byKey(const ValueKey('readinessRequestExact'));
    final settings = find.byKey(const ValueKey('readinessSystemSettings'));
    expect(
      tester.getTopLeft(exact).dy - tester.getBottomLeft(permission).dy,
      12,
    );
    expect(tester.getTopLeft(settings).dy - tester.getBottomLeft(exact).dy, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('테스트 알림의 주의사항과 결과는 버튼 묶음보다 먼저 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, _Control(), includeActions: true);
    await _show(tester, 'readinessSendTest');
    final send = find.byKey(const ValueKey('readinessSendTest'));
    final limitations = find.byKey(const ValueKey('readinessTestLimitations'));
    expect(
      tester.getTopLeft(send).dy - tester.getBottomLeft(limitations).dy,
      20,
    );
    await tester.tap(send);
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('readinessTestResult'));
    final confirm = find.byKey(const ValueKey('readinessConfirmTest'));
    expect(tester.getTopLeft(send).dy - tester.getBottomLeft(result).dy, 20);
    expect(tester.getTopLeft(confirm).dy - tester.getBottomLeft(send).dy, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('전송 성공과 사용자의 실제 확인을 구분하고 자동 권한 요청을 하지 않는다', (tester) async {
    final control = _Control();
    await _open(tester, control);
    expect(control.permissionRequests, 0);
    await _show(tester, 'readinessSendTest');
    await tester.tap(find.byKey(const ValueKey('readinessSendTest')));
    await tester.pumpAndSettle();
    expect(control.sends, 1);
    expect(find.textContaining('실제 표시 여부는 아직'), findsOneWidget);
    await _show(tester, 'readinessConfirmTest');
    await tester.tap(find.byKey(const ValueKey('readinessConfirmTest')));
    await tester.pumpAndSettle();
    expect(find.text('사용자가 이번 테스트 알림을 확인했습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('권한 거절과 미확인은 성공이나 약 없음으로 표시하지 않는다', (tester) async {
    final control = _Control()
      ..state = const NotificationReadinessSnapshot(
        notifications: false,
        medicationChannel: false,
        exactAlarms: false,
      );
    await _open(tester, control);
    expect(find.textContaining('등록 여부를 확인하지 못했습니다'), findsOneWidget);
    await _show(tester, 'readinessRequestPermission');
    expect(find.byKey(const ValueKey('readinessSendTest')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('readinessRequestPermission')));
    await tester.pumpAndSettle();
    expect(control.permissionRequests, 1);
    expect(control.sends, 0);
  });

  testWidgets('실패는 재시도할 수 있고 전송 중 연타를 막는다', (tester) async {
    final control = _Control()
      ..sendGate = Completer<void>()
      ..failSend = true;
    await _open(tester, control);
    await _show(tester, 'readinessSendTest');
    final send = find.byKey(const ValueKey('readinessSendTest'));
    await tester.tap(send);
    await tester.pump();
    await tester.tap(send);
    expect(control.sends, 1);
    control.sendGate!.complete();
    await tester.pumpAndSettle();
    await _show(tester, 'readinessError');
    expect(find.textContaining('테스트 알림을 보내지 못했습니다'), findsOneWidget);
    control.failSend = false;
    await _show(tester, 'readinessSendTest');
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(control.sends, 2);
    expect(find.byKey(const ValueKey('readinessError')), findsNothing);
  });

  testWidgets('전송 중 화면을 닫아도 완료 후 상태를 갱신하지 않는다', (tester) async {
    final control = _Control()..sendGate = Completer<void>();
    await _open(tester, control);
    await _show(tester, 'readinessSendTest');
    await tester.tap(find.byKey(const ValueKey('readinessSendTest')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    control.sendGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('시스템 설정 복귀 때 권한을 다시 읽는다', (tester) async {
    final control = _Control();
    await _open(tester, control);
    control.state = const NotificationReadinessSnapshot(notifications: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(control.refreshes, 2);
    await _show(tester, 'readinessSystemPermission');
    expect(find.text('휴대폰 알림 권한: 허용되지 않음'), findsOneWidget);
  });

  for (final english in [false, true]) {
    testWidgets('320px 2배 글씨에서 점검 내용이 겹치지 않는다 english=$english', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, _Control(), english: english, includeActions: true);
      expect(
        find.text(
          english
              ? 'Check medication setup and notifications.'
              : '약 등록과 알림 수신 상태를 점검합니다.',
        ),
        findsOneWidget,
      );
      for (var i = 0; i < 25; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await _show(tester, 'readinessCaregiver');
      expect(find.byKey(const ValueKey('readinessCaregiver')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
