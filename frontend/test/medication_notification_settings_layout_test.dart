// 파일명: medication_notification_settings_layout_test.dart
// 역할: 목록형 복약·알림 설정의 초안 편집, 선택 취소, 저장과 접근성을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: main
// 함수역할: UI 정리 후 기존 저장 계약과 큰 글씨 동작을 검사한다. 매개변수·반환값: 없음.
void main() {
  // 세 알림 스위치와 공개 범위는 저장 버튼을 누를 때 함께 전달한다.
  testWidgets('알림 종류와 공개 범위를 초안으로 편집한 뒤 함께 저장한다', (tester) async {
    final saves = <UserSetting>[];
    await _pumpSettings(tester, onSave: saves.add);
    for (final key in [
      'medicationNotificationsSwitch',
      'caregiverNotificationsSwitch',
      'chatNotificationsSwitch',
    ]) {
      await _tap(tester, key);
      expect(
        tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value,
        isFalse,
      );
    }
    await _tap(tester, 'notificationPrivacySelector');
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'full',
    );
    await _tap(tester, 'notificationPrivacy-type_only');
    expect(find.text('종류만 표시'), findsOneWidget);
    expect(saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.single.medicationNotificationsEnabled, isFalse);
    expect(saves.single.caregiverNotificationsEnabled, isFalse);
    expect(saves.single.chatNotificationsEnabled, isFalse);
    expect(saves.single.notificationDetailMode, 'type_only');
    expect(saves.single.defaultMorningTime, '08:00');
  });

  // 선택창 닫기는 공개 범위를 변경하거나 저장하지 않는다.
  testWidgets('공개 범위 선택을 취소하면 원래 값을 유지한다', (tester) async {
    final saves = <UserSetting>[];
    await _pumpSettings(
      tester,
      setting: const UserSetting(notificationDetailMode: 'type_only'),
      onSave: saves.add,
    );
    await _tap(tester, 'notificationPrivacySelector');
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'type_only',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('종류만 표시'), findsOneWidget);
    expect(saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();
    expect(saves.single.notificationDetailMode, 'type_only');
  });

  // 시간 행은 동일한 기존 선택기로 연결하며, 확정한 반환값만 해당 시간대에 적용한다.
  testWidgets('네 시간대는 같은 시간 선택기로 편집하고 취소한 값은 유지한다', (tester) async {
    final saves = <UserSetting>[];
    await _pumpSettings(tester, onSave: saves.add);
    final entries = [
      (
        'morning',
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 9, minute: 10),
      ),
      (
        'lunch',
        const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 13, minute: 20),
      ),
      (
        'evening',
        const TimeOfDay(hour: 18, minute: 0),
        const TimeOfDay(hour: 19, minute: 30),
      ),
      (
        'bedtime',
        const TimeOfDay(hour: 22, minute: 0),
        const TimeOfDay(hour: 23, minute: 40),
      ),
    ];
    for (final entry in entries) {
      await _tap(tester, 'defaultMedicationTime-${entry.$1}');
      final picker = find.byType(SetNotificationUI);
      expect(tester.widget<SetNotificationUI>(picker).initialTime, entry.$2);
      Navigator.of(tester.element(picker)).pop(entry.$3);
      await tester.pumpAndSettle();
    }
    await _tap(tester, 'defaultMedicationTime-morning');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();
    expect(saves.single.defaultMorningTime, '09:10');
    expect(saves.single.defaultLunchTime, '13:20');
    expect(saves.single.defaultEveningTime, '19:30');
    expect(saves.single.defaultBedtime, '23:40');
  });

  // 외부 설정·일정 이동은 기존 콜백만 호출하며 저장 중인 초안을 버리지 않는다.
  testWidgets('휴대폰 설정과 세부 일정 이동 콜백을 유지한다', (tester) async {
    var deviceOpens = 0;
    var scheduleOpens = 0;
    final saves = <UserSetting>[];
    await _pumpSettings(
      tester,
      onSave: saves.add,
      onDevice: () => deviceOpens++,
      onSchedule: () => scheduleOpens++,
    );
    await _tap(tester, 'chatNotificationsSwitch');
    await _tap(tester, 'medicationScheduleSettingsRow');
    await _tap(tester, 'deviceNotificationSettingsRow');
    expect(deviceOpens, 1);
    expect(scheduleOpens, 1);
    expect(saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();
    expect(saves.single.chatNotificationsEnabled, isFalse);
  });

  for (final width in [320.0, 411.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['ko', 'en']) {
        // 좁은 화면·확대 글씨에서 각 행과 공개 범위 선택지, 저장 버튼에 접근할 수 있다.
        testWidgets('복약 설정 목록과 선택창이 잘리지 않는다 $width $scale $language', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpSettings(
            tester,
            width: width,
            setting: UserSetting(
              language: language,
              fontSize: 20,
              timeFormat: '12h',
            ),
          );
          for (final key in [
            'medicationNotificationsSwitch',
            'caregiverNotificationsSwitch',
            'chatNotificationsSwitch',
            'defaultMedicationTime-morning',
            'defaultMedicationTime-lunch',
            'defaultMedicationTime-evening',
            'defaultMedicationTime-bedtime',
            'medicationScheduleSettingsRow',
            'deviceNotificationSettingsRow',
          ]) {
            final row = find.byKey(ValueKey(key));
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            expect(row.hitTestable(), findsOneWidget);
            expect(tester.getRect(row).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          }
          await _tap(tester, 'notificationPrivacySelector');
          final option = find.byKey(
            const ValueKey('notificationPrivacy-type_only'),
          );
          await tester.ensureVisible(option);
          await tester.pumpAndSettle();
          expect(option.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(
            find
                .widgetWithText(
                  FilledButton,
                  language == 'en' ? 'Save' : '저장하기',
                )
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

// 함수이름: _tap
// 함수역할: key의 설정 항목을 스크롤 후 선택한다. 매개변수: tester·key. 반환값: 화면 전환 완료.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// 함수이름: _pumpSettings
// 함수역할: 실제 저장·OS 이동 없이 복약 설정 화면을 구성한다.
// 매개변수: 화면 도구, 초기 설정·너비와 저장·이동 관찰 콜백. 반환값: 복약 설정 진입 완료.
Future<void> _pumpSettings(
  WidgetTester tester, {
  UserSetting setting = const UserSetting(),
  double width = 411,
  ValueChanged<UserSetting>? onSave,
  VoidCallback? onDevice,
  VoidCallback? onSchedule,
}) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = AuthenticationControl.development();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      home: ManageUserSettingUI(
        initialSetting: setting,
        authenticationControl: auth,
        onSettingSaveRequested:
            ({
              required fontSizeOption,
              required readingSpeedOption,
              required language,
            }) async => UserSettingSaveResult(
              setting: setting,
              synchronizedWithServer: true,
            ),
        // 화면의 초안만 기록하며 실제 알림과 저장소는 변경하지 않는다.
        onExtendedSettingSaveRequested: (draft) async {
          onSave?.call(draft);
          return UserSettingSaveResult(
            setting: draft,
            synchronizedWithServer: true,
          );
        },
        onMedicationScheduleRequested: onSchedule ?? () {},
        onDeviceNotificationSettingsRequested: () async {
          onDevice?.call();
        },
      ),
    ),
  );
  await _tap(tester, 'settingsMedicationAndNotificationsMenu');
}
