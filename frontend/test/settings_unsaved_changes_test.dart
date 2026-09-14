// 파일명: settings_unsaved_changes_test.dart
// 역할: 설정의 저장·변경 취소·계속 편집과 저장 실패 시 이탈 방지를 검증한다.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수역할: 사용자 의도와 실제 저장 결과에 따른 종료 동작을 검증한다.
void main() {
  testWidgets('홈 일정 선택은 저장·변경 취소를 따르며 내 일정이 기본이다', (tester) async {
    UserSetting? saved;
    await _pump(tester, (setting) async {
      saved = setting;
      return UserSettingSaveResult(
        setting: setting,
        synchronizedWithServer: true,
      );
    });
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('내 일정'), findsOneWidget);
    await _tap(tester, 'homeScheduleSourceSelector');
    await _tap(tester, 'homeScheduleSource-patients');
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-discard-changes');
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('내 일정'), findsOneWidget);
    expect(saved, isNull);
    await _tap(tester, 'homeScheduleSourceSelector');
    await _tap(tester, 'homeScheduleSource-patients');
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-save-and-leave');
    expect(saved!.homeScheduleSource, 'patients');
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('연결된 환자'), findsOneWidget);
  });

  testWidgets('계속 편집과 변경 취소는 저장하지 않으며 시스템 뒤로가기도 확인한다', (tester) async {
    var saves = 0;
    await _pump(tester, (setting) async {
      saves++;
      return UserSettingSaveResult(
        setting: setting,
        synchronizedWithServer: true,
      );
    });
    await _edit(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsOneWidget);
    await _tap(tester, 'settings-keep-editing');
    expect(_chatEnabled(tester), isFalse);
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-discard-changes');
    expect(find.text('환경설정'), findsOneWidget);
    await _tap(tester, 'settingsMedicationAndNotificationsMenu');
    expect(_chatEnabled(tester), isTrue);
    expect(saves, 0);
    await _tap(tester, 'settingsBackButton');
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    await _tap(tester, 'settingsBackButton');
    expect(find.text('Previous screen'), findsOneWidget);
  });

  for (final synchronized in [true, false]) {
    testWidgets('저장 후 이탈은 저장된 값을 기준으로 다시 비교한다: $synchronized', (tester) async {
      UserSetting? saved;
      await _pump(tester, (setting) async {
        saved = setting;
        return UserSettingSaveResult(
          setting: setting,
          synchronizedWithServer: synchronized,
        );
      });
      await _edit(tester);
      await _tap(tester, 'settingsBackButton');
      await _tap(tester, 'settings-save-and-leave');
      expect(saved!.chatNotificationsEnabled, isFalse);
      expect(find.text('환경설정'), findsOneWidget);
      await _tap(tester, 'settingsMedicationAndNotificationsMenu');
      expect(_chatEnabled(tester), isFalse);
      await _tap(tester, 'settingsBackButton');
      expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    });
  }

  testWidgets('저장 중 뒤로가기는 중복 저장하지 않고 실패하면 편집을 유지한다', (tester) async {
    final gate = Completer<UserSettingSaveResult>();
    var saves = 0;
    await _pump(tester, (setting) {
      saves++;
      return gate.future;
    });
    await _edit(tester);
    await _tap(tester, 'settingsBackButton');
    await tester.tap(find.byKey(const Key('settings-save-and-leave')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(saves, 1);
    gate.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('복약 및 알림'), findsOneWidget);
    expect(_chatEnabled(tester), isFalse);
    await _tap(tester, 'settingsBackButton');
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsOneWidget);
  });

  testWidgets('두 배 글씨에서도 종료 확인의 세 선택지를 사용할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      (setting) async =>
          UserSettingSaveResult(setting: setting, synchronizedWithServer: true),
    );
    await _edit(tester);
    await _tap(tester, 'settingsBackButton');
    expect(find.byKey(const Key('settings-save-and-leave')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 함수역할: 실제 이전 경로와 저장 대역을 가진 설정 화면을 구성한다.
Future<void> _pump(WidgetTester tester, ExtendedUserSettingSaver saver) async {
  final auth = AuthenticationControl.development();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      initialRoute: '/settings',
      routes: {
        '/': (_) => const Scaffold(body: Text('Previous screen')),
        '/settings': (_) => ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: auth,
          previewSpeaker: (text, setting, {onComplete}) async {},
          previewStopper: () async {},
          onExtendedSettingSaveRequested: saver,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) => throw StateError('Use extended settings'),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
}

// 함수역할: 알림 설정을 실제로 변경한다. 매개변수: tester. 반환값: 편집 완료.
Future<void> _edit(WidgetTester tester) async {
  await _tap(tester, 'settingsMedicationAndNotificationsMenu');
  await _tap(tester, 'chatNotificationsSwitch');
}

// 함수역할: 스크롤 영역 내 조작을 찾아 실행한다. 매개변수: tester, key.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// 함수역할: 채팅 알림 편집값을 확인한다. 매개변수: tester. 반환값: 현재 켜짐 여부.
bool _chatEnabled(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const Key('chatNotificationsSwitch')))
    .value;
