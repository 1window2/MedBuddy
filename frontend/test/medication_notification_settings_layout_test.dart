// 파일명: medication_notification_settings_layout_test.dart
// 역할: 목록형 복약·알림 설정의 초안 편집, 선택 취소, 저장과 접근성을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

import 'support/fake_notification_service.dart';

// 함수이름: main
// 함수역할: 복약 알림의 배치·초안 저장·권한·시각 선택과 큰 글씨 접근성 사례를 등록한다.
// 매개변수: 없음.
// 반환값: 없음. 복약 설정 테스트 등록.
void main() {
  for (final language in ['ko', 'en']) {
    // 함수이름: testWidgets: '휴대폰 권한 다음에 알림 종류와 세부 설정을 배치한다 $language'
    // 함수역할: 언어별로 기기 권한·시험 알림·세 알림 종류·기본 시각·세부 일정·공개 범위 행의 위치를 비교한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 지정 순서를 유지하고 홈 위젯 추가는 이 구역에 없으며 레이아웃 예외가 없다.
    testWidgets('휴대폰 권한 다음에 알림 종류와 세부 설정을 배치한다 $language', (tester) async {
      await _pumpSettings(tester, setting: UserSetting(language: language));
      final keys = [
        'deviceNotificationSettingsRow',
        'deviceExactReminderSettingsRow',
        'notificationSettingsSendTest',
        'medicationNotificationsSwitch',
        'caregiverNotificationsSwitch',
        'chatNotificationsSwitch',
        'defaultMedicationTime-morning',
        'medicationScheduleSettingsRow',
        'notificationPrivacySelector',
      ];
      for (var index = 1; index < keys.length; index++) {
        expect(
          tester.getBottomLeft(find.byKey(ValueKey(keys[index - 1]))).dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(ValueKey(keys[index]))).dy,
          ),
        );
      }
      expect(find.byKey(const ValueKey('addDoseHomeWidget')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets: '알림 종류와 공개 범위를 초안으로 편집한 뒤 함께 저장한다'
  // 함수역할: 세 알림 종류를 끄고 공개 범위를 type_only로 고른 뒤 저장 버튼을 누른다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 선택 중 저장하지 않고 한 번에 세 false와 공개 범위를 전달하며 기존 아침 시각은 유지된다.
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

  // 함수이름: testWidgets: '공개 범위 선택을 취소하면 원래 값을 유지한다'
  // 함수역할: type_only 초안의 공개 범위 선택창을 시스템 뒤로가기로 닫고 저장한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 취소는 저장·변경을 일으키지 않고 최종 저장도 type_only이다.
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

  // 함수이름: testWidgets: '네 시간대는 같은 시간 선택기로 편집하고 취소한 값은 유지한다'
  // 함수역할: 네 시간대의 초기 시각을 확인하고 각각 새 시각을 반환한 뒤 아침 재편집만 취소한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 확정한 09:10·13:20·19:30·23:40을 저장하고 취소는 마지막 확정값을 되돌리지 않는다.
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

  // 함수이름: testWidgets: '휴대폰 설정과 세부 일정 이동 콜백을 유지한다'
  // 함수역할: 채팅 알림 초안을 수정한 채 세부 일정과 기기 설정 이동을 실행하고 마지막에 저장한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 각 이동 콜백은 한 번이고 이동 중 저장 없이 채팅 알림 false 초안을 보존한다.
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

  // 앱 알림 초안과 기기의 권한은 분리하며 기기 설정에서 권한을 변경한다.
  for (final language in ['ko', 'en']) {
    // 함수이름: testWidgets: '기기 권한은 알림 초안과 별도로 확인하고 변경한다 $language'
    // 함수역할: 320px·2배 글씨에서 정확 알람 권한이 없는 기기로 알림 초안을 껐다 켜고 권한을 허용한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 권한 행은 초안과 독립적으로 남고 요청은 한 번이며 허용된 스위치와 예외 없는 화면을 확인한다.
    testWidgets('기기 권한은 알림 초안과 별도로 확인하고 변경한다 $language', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final notificationService = RecordingNotificationService()
        ..exactRemindersAllowed = false;
      await _pumpSettings(
        tester,
        width: 320,
        setting: UserSetting(language: language, fontSize: 20),
        notificationService: notificationService,
      );

      final allow = find.byKey(
        const ValueKey('deviceExactReminderSettingsRow'),
      );
      await tester.ensureVisible(allow);
      await tester.pumpAndSettle();
      expect(allow.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tap(tester, 'medicationNotificationsSwitch');
      expect(find.byKey(const Key('exact-reminder-notice')), findsNothing);
      expect(allow, findsOneWidget);
      await _tap(tester, 'medicationNotificationsSwitch');
      await tester.ensureVisible(allow);
      await tester.pumpAndSettle();

      notificationService.exactPermissionAfterRequest = true;
      await tester.tap(allow);
      await tester.pumpAndSettle();
      expect(notificationService.exactPermissionRequestCount, 1);
      expect(find.byKey(const Key('exact-reminder-notice')), findsNothing);
      expect(tester.widget<SwitchListTile>(allow).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 411.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['ko', 'en']) {
        // 함수이름: testWidgets: '복약 설정 목록과 선택창이 잘리지 않는다 $width $scale $language'
        // 함수역할: 너비·배율·언어 조합에서 알림/시각/이동 행과 공개 범위 선택지·저장 버튼까지 스크롤한다.
        // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
        // 반환값: 각 행은 48px 이상이며 선택지와 저장은 터치 가능하고 예외가 없다.
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
// 함수역할: 기기 크기와 개발 인증을 설정하고 실제 저장/OS 이동 대신 관찰 대역을 연결해 복약 설정을 연다.
// 매개변수: tester (WidgetTester): 화면 제어; setting (UserSetting): 초기값; width (double): 너비; onSave (ValueChanged<UserSetting>?): 저장 관찰; onDevice/onSchedule (VoidCallback?): 이동 관찰; notificationService (RecordingNotificationService?): 권한/알림 대역.
// 반환값: 복약 및 알림 구역 진입 완료.
Future<void> _pumpSettings(
  WidgetTester tester, {
  UserSetting setting = const UserSetting(),
  double width = 411,
  ValueChanged<UserSetting>? onSave,
  VoidCallback? onDevice,
  VoidCallback? onSchedule,
  RecordingNotificationService? notificationService,
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
        // 화면의 초안만 기록하며 실제 알림과 저장소는 변경하지 않는다.
        onExtendedSettingSaveRequested: (draft) async {
          onSave?.call(draft);
          return UserSettingSaveResult(
            setting: draft,
            synchronizedWithServer: true,
          );
        },
        onMedicationScheduleRequested: onSchedule ?? () {},
        notificationService: notificationService,
        readinessControl: _DeviceControl(
          notificationService ?? RecordingNotificationService(),
          () async {
            onDevice?.call();
          },
        ),
      ),
    ),
  );
  await _tap(tester, 'settingsMedicationAndNotificationsMenu');
}

// 클래스명: _DeviceControl
// 역할: 기기 알림 권한 상태를 제어하는 테스트 대역.
// 주요 책임: 알림·채널은 허용으로 고정하고 정확 알람 상태와 권한 요청만 기록 서비스에서 읽는다.
// 속성: service (RecordingNotificationService): 정확 알람 상태 및 요청 기록.
class _DeviceControl extends NotificationReadinessControl {
  final RecordingNotificationService service;

  // 함수이름: _DeviceControl
  // 함수역할: 알림·정확 알람·기기 설정 지원을 켜고 설정 열기 대역을 연결한다.
  // 매개변수: service (RecordingNotificationService): 알림 대역; openSettings (Future<void> Function()): 기기 설정 열기 동작.
  // 반환값: 새 _DeviceControl.
  _DeviceControl(this.service, Future<void> Function() openSettings)
    : super(
        notificationService: service,
        supportsNotifications: true,
        supportsExactAlarms: true,
        supportsSystemSettings: true,
        openNotificationSettings: openSettings,
      );

  // 함수이름: refresh
  // 함수역할: 알림과 채널은 허용하고 정확 알람만 서비스 상태를 반영한 스냅샷을 만든다.
  // 매개변수: 없음.
  // 반환값: Future<NotificationReadinessSnapshot>: 모의 기기 권한 상태.
  @override
  Future<NotificationReadinessSnapshot> refresh() async =>
      NotificationReadinessSnapshot(
        notifications: true,
        medicationChannel: true,
        exactAlarms: service.exactRemindersAllowed,
      );

  // 함수이름: openExactSettings
  // 함수역할: 실제 설정 화면 대신 알림 대역의 정확 알람 권한 요청을 실행한다.
  // 매개변수: 없음.
  // 반환값: 권한 요청 완료.
  @override
  Future<void> openExactSettings() async {
    await service.requestExactReminderPermission();
  }
}
