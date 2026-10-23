// 파일명: notification_readiness_ui_boundary_test.dart
// 역할: 설정 안의 권한 상태·실패·명시적 테스트와 좁은 큰 글씨 화면을 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/notification_readiness_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

class _Control extends NotificationReadinessControl {
  _Control({bool supported = true, bool exact = true, bool settings = true})
    : super(
        notificationService: NotificationService.instance,
        supportsNotifications: supported,
        supportsExactAlarms: exact,
        supportsSystemSettings: settings,
      );
  NotificationReadinessSnapshot state = const NotificationReadinessSnapshot(
    notifications: true,
    medicationChannel: true,
    exactAlarms: true,
  );
  int sends = 0;
  int permissionRequests = 0;
  int settingsOpens = 0;
  int exactRequests = 0;
  int refreshes = 0;
  bool failSend = false;
  bool failRefresh = false;
  bool failSettings = false;
  String? sentLanguage;
  Completer<void>? sendGate;
  Completer<void>? settingsGate;

  @override
  Future<NotificationReadinessSnapshot> refresh() async {
    refreshes++;
    if (failRefresh) throw StateError('unavailable');
    return state;
  }

  @override
  Future<void> sendTest(String language) async {
    sends++;
    sentLanguage = language;
    if (sendGate != null) await sendGate!.future;
    if (failSend) throw StateError('unavailable');
  }

  @override
  Future<void> requestNotificationPermission() async {
    permissionRequests++;
  }

  @override
  Future<void> openSystemSettings() async {
    settingsOpens++;
    if (settingsGate != null) await settingsGate!.future;
    if (failSettings) throw StateError('unavailable');
  }

  @override
  Future<void> openExactSettings() async {
    exactRequests++;
    if (settingsGate != null) await settingsGate!.future;
    if (failSettings) throw StateError('unavailable');
  }
}

Future<void> _open(
  WidgetTester tester,
  _Control control, {
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: NotificationDeviceSettings(
            control: control,
            isEnglish: english,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _sendKey = ValueKey('notificationSettingsSendTest');

void main() {
  testWidgets('약 등록 점검 없이 기존 설정 행과 테스트 버튼만 제공한다', (tester) async {
    await _open(tester, _Control());
    expect(find.text('알림 허용'), findsOneWidget);
    expect(find.text('정확한 시간에 알림'), findsOneWidget);
    expect(find.text('테스트 알림 보내기'), findsOneWidget);
    expect(find.textContaining('사용 준비'), findsNothing);
    expect(find.textContaining('약 등록'), findsNothing);
    expect(find.textContaining('알림 채널'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final phone = find.byKey(const ValueKey('deviceNotificationSettingsRow'));
    final exact = find.byKey(const ValueKey('deviceExactReminderSettingsRow'));
    expect(tester.widget<SwitchListTile>(phone).value, isTrue);
    expect(tester.widget<SwitchListTile>(exact).value, isTrue);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.text('허용됨'), findsNothing);
    expect(tester.getSize(phone).width, tester.getSize(exact).width);
    expect(tester.getTopLeft(exact).dy - tester.getBottomLeft(phone).dy, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('진입 시 권한을 요청하지 않고 테스트 요청을 실제 수신으로 단정하지 않는다', (tester) async {
    final control = _Control();
    await _open(tester, control);
    expect(control.permissionRequests, 0);
    expect(control.exactRequests, 0);
    expect(control.settingsOpens, 0);
    expect(control.sends, 0);
    await _tap(tester, 'notificationSettingsSendTest');
    expect(control.sends, 1);
    expect(control.sentLanguage, 'ko');
    expect(find.textContaining('휴대폰 알림창을 확인'), findsOneWidget);
    // 테스트 한 번이 이후 알림을 보장하지 않는다는 주의는 테스트할 수 있을 때 함께 보인다.
    expect(
      find.byKey(const ValueKey('notificationSettingsTestLimitations')),
      findsOneWidget,
    );
    expect(find.textContaining('수신 완료'), findsNothing);
    expect(find.text('테스트 알림을 봤어요'), findsNothing);
  });

  for (final state in [
    const NotificationReadinessSnapshot(notifications: false),
    const NotificationReadinessSnapshot(
      notifications: true,
      medicationChannel: false,
    ),
    const NotificationReadinessSnapshot(notifications: true),
    const NotificationReadinessSnapshot(),
  ]) {
    testWidgets(
      '차단 또는 미확인 상태에서는 테스트를 막는다 ${state.notifications}/${state.medicationChannel}',
      (tester) async {
        final control = _Control()..state = state;
        await _open(tester, control);
        expect(
          tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
          isNull,
        );
        await _tap(tester, 'deviceNotificationSettingsRow');
        expect(control.settingsOpens, 1);
        expect(control.sends, 0);
        expect(control.permissionRequests, 0);
        if (state.notifications == true && state.medicationChannel == false) {
          expect(find.textContaining('복약 알림 꺼짐'), findsOneWidget);
          // 복약 알림이 오지 않으므로 스위치도 꺼짐으로 보인다.
          expect(
            tester
                .widget<SwitchListTile>(
                  find.byKey(const ValueKey('deviceNotificationSettingsRow')),
                )
                .value,
            isFalse,
          );
        }
      },
    );
  }

  testWidgets('정확한 시간 권한 없이도 즉시 테스트가 가능하고 복귀하면 다시 읽는다', (tester) async {
    final control = _Control()
      ..state = const NotificationReadinessSnapshot(
        notifications: true,
        medicationChannel: true,
        exactAlarms: false,
      );
    await _open(tester, control);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNotNull,
    );
    await _tap(tester, 'deviceExactReminderSettingsRow');
    expect(control.exactRequests, 1);
    control.state = const NotificationReadinessSnapshot(
      notifications: true,
      medicationChannel: true,
      exactAlarms: true,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
          )
          .value,
      isTrue,
    );
    expect(control.refreshes, greaterThanOrEqualTo(3));
  });

  testWidgets('이미 허용된 권한도 설정을 열며 취소하면 켜진 상태를 유지한다', (tester) async {
    final control = _Control();
    await _open(tester, control);
    await _tap(tester, 'deviceExactReminderSettingsRow');
    expect(control.exactRequests, 1);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
          )
          .value,
      isTrue,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('설정 이동 중 연타와 가짜 상태 변경을 막고 복귀 후 꺼짐을 반영한다', (tester) async {
    final control = _Control()..settingsGate = Completer<void>();
    await _open(tester, control);
    final phone = find.byKey(const ValueKey('deviceNotificationSettingsRow'));
    await tester.tap(phone);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(phone).value, isTrue);
    expect(tester.widget<SwitchListTile>(phone).onChanged, isNull);
    await tester.tap(phone);
    expect(control.settingsOpens, 1);
    control.state = const NotificationReadinessSnapshot(
      notifications: false,
      medicationChannel: true,
      exactAlarms: false,
    );
    control.settingsGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(phone).value, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('별도 시간 권한이 없는 구형 Android에는 해당 스위치를 숨긴다', (tester) async {
    final control = _Control()
      ..state = const NotificationReadinessSnapshot(
        notifications: true,
        medicationChannel: true,
        exactAlarms: true,
        exactAlarmsEditable: false,
      );
    await _open(tester, control);
    expect(
      find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
      findsNothing,
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('전송 중 연타를 막고 실패 후 재시도할 수 있다', (tester) async {
    final control = _Control()
      ..sendGate = Completer<void>()
      ..failSend = true;
    await _open(tester, control);
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    expect(control.sends, 1);
    control.sendGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('테스트 알림을 보내지 못했습니다'), findsOneWidget);
    control.failSend = false;
    await _tap(tester, 'notificationSettingsSendTest');
    expect(control.sends, 2);
    expect(
      find.byKey(const ValueKey('notificationSettingsError')),
      findsNothing,
    );
  });

  testWidgets('전송 중 설정을 닫아도 완료 후 화면을 갱신하지 않는다', (tester) async {
    final control = _Control()..sendGate = Completer<void>();
    await _open(tester, control);
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    control.sendGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('상태 조회 실패와 설정 이동 실패를 성공으로 표시하지 않는다', (tester) async {
    final control = _Control()
      ..failRefresh = true
      ..failSettings = true;
    await _open(tester, control);
    expect(find.text('상태를 확인하지 못했습니다.'), findsNWidgets(2));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNull,
    );
    await _tap(tester, 'deviceNotificationSettingsRow');
    expect(find.textContaining('설정을 열지 못했습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('알림 미지원 환경은 미지원으로 표시한다', (tester) async {
    await _open(
      tester,
      _Control(supported: false, exact: false, settings: false),
    );
    expect(find.text('지원하지 않음'), findsOneWidget);
    expect(find.text('정확한 시간에 알림'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNull,
    );
  });

  testWidgets('정확한 알림 권한이 없는 플랫폼에서는 채널 상태를 요구하지 않는다', (tester) async {
    final control = _Control(exact: false, settings: false)
      ..state = const NotificationReadinessSnapshot(notifications: true);
    await _open(tester, control, english: true);
    await _tap(tester, 'notificationSettingsSendTest');
    expect(control.sentLanguage, 'en');
    expect(find.text('On-time reminders'), findsNothing);
    await _tap(tester, 'deviceNotificationSettingsRow');
    expect(control.permissionRequests, 1);
  });

  for (final english in [false, true]) {
    testWidgets('320px 2배 글씨에서 설정과 버튼이 잘리지 않는다 english=$english', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, _Control(), english: english);
      for (final key in [
        'deviceNotificationSettingsRow',
        'deviceExactReminderSettingsRow',
        'notificationSettingsSendTest',
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder.hitTestable(), findsOneWidget);
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
